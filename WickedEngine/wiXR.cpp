#include "wiXR.h"
#include "wiScene_Components.h"
#include "wiBacklog.h"

#if defined(WICKED_OPENXR)
#include "wiGraphicsDevice_Vulkan.h"
#endif // WICKED_OPENXR

#if defined(WICKED_OPENXR) && defined(WICKEDENGINE_BUILD_VULKAN)
#define WICKED_XR_IMPLEMENTATION
#endif

// The tracking origin is independent of the XR implementation:
namespace wi::xr
{
	namespace
	{
		XMFLOAT4X4 tracking_origin = wi::math::IDENTITY_MATRIX;
	}
	void SetTrackingOrigin(const XMMATRIX& world_from_tracking)
	{
		XMStoreFloat4x4(&tracking_origin, world_from_tracking);
	}
	XMMATRIX GetTrackingOrigin()
	{
		return XMLoadFloat4x4(&tracking_origin);
	}
}

#ifdef WICKED_XR_IMPLEMENTATION

#define XR_USE_GRAPHICS_API_VULKAN
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>

#include <mutex>
#include <string>
#include <cstring>

using namespace wi::graphics;

namespace wi::xr
{
	namespace
	{
		// Bindings of one interaction profile to the input actions. Paths are relative to /user/hand/<left|right>/
		struct InteractionProfile
		{
			const char* path = nullptr;
			const char* trigger = nullptr;
			const char* squeeze = nullptr;
			const char* thumbstick = nullptr;
			const char* thumbstick_click = nullptr;
			const char* primary[2] = {}; // left, right
			const char* secondary[2] = {}; // left, right
			const char* menu[2] = {}; // left, right
		};
		// New controller types can be supported by extending this table:
		const InteractionProfile interaction_profiles[] = {
			{
				"/interaction_profiles/khr/simple_controller",
				"input/select/click", nullptr, nullptr, nullptr,
				{}, {}, { "input/menu/click", "input/menu/click" }
			},
			{
				"/interaction_profiles/oculus/touch_controller",
				"input/trigger/value", "input/squeeze/value", "input/thumbstick", "input/thumbstick/click",
				{ "input/x/click", "input/a/click" }, { "input/y/click", "input/b/click" }, { "input/menu/click", nullptr }
			},
			{
				"/interaction_profiles/valve/index_controller",
				"input/trigger/value", "input/squeeze/value", "input/thumbstick", "input/thumbstick/click",
				{ "input/a/click", "input/a/click" }, { "input/b/click", "input/b/click" }, {}
			},
			{
				"/interaction_profiles/htc/vive_controller",
				"input/trigger/value", "input/squeeze/click", "input/trackpad", "input/trackpad/click",
				{}, {}, { "input/menu/click", "input/menu/click" }
			},
			{
				"/interaction_profiles/microsoft/motion_controller",
				"input/trigger/value", "input/squeeze/click", "input/thumbstick", "input/thumbstick/click",
				{}, {}, { "input/menu/click", "input/menu/click" }
			},
		};

		const char* const hand_paths[size_t(Hand::Count)] = {
			"/user/hand/left",
			"/user/hand/right",
		};

		struct SwapchainImage
		{
			Texture texture;
		};

		struct State
		{
			XrInstance instance = XR_NULL_HANDLE;
			XrSystemId system = XR_NULL_SYSTEM_ID;
			XrSession session = XR_NULL_HANDLE;
			XrSpace space_app = XR_NULL_HANDLE; // tracking space (stage or local)
			XrSpace space_head = XR_NULL_HANDLE;
			XrSwapchain swapchain = XR_NULL_HANDLE;
			XrSessionState session_state = XR_SESSION_STATE_UNKNOWN;
			XrEnvironmentBlendMode blend_mode = XR_ENVIRONMENT_BLEND_MODE_OPAQUE;
			// Extension functions are not exported by the OpenXR loader, they must be queried from the instance:
			PFN_xrGetVulkanGraphicsRequirements2KHR get_vulkan_graphics_requirements = nullptr;
			PFN_xrCreateVulkanInstanceKHR create_vulkan_instance = nullptr;
			PFN_xrGetVulkanGraphicsDevice2KHR get_vulkan_graphics_device = nullptr;
			PFN_xrCreateVulkanDeviceKHR create_vulkan_device = nullptr;
			bool session_running = false;
			bool exit_requested = false;
			bool frame_begun = false;
			bool frame_should_render = false;
			bool image_acquired = false;

			GraphicsDevice_Vulkan* device = nullptr;
			XMUINT2 eye_resolution = XMUINT2(0, 0);
			wi::vector<SwapchainImage> swapchain_images;
			uint32_t swapchain_image_index = 0;

			XrFrameState frame_state = { XR_TYPE_FRAME_STATE };
			XrView views[EYE_COUNT] = {};
			bool views_valid = false;

			EyeView eyes[EYE_COUNT];
			Pose head;
			ControllerState controllers[size_t(Hand::Count)];

			// Input:
			XrActionSet action_set = XR_NULL_HANDLE;
			XrPath hand_subaction_paths[size_t(Hand::Count)] = {};
			XrAction action_grip_pose = XR_NULL_HANDLE;
			XrAction action_aim_pose = XR_NULL_HANDLE;
			XrAction action_trigger = XR_NULL_HANDLE;
			XrAction action_squeeze = XR_NULL_HANDLE;
			XrAction action_thumbstick = XR_NULL_HANDLE;
			XrAction action_thumbstick_click = XR_NULL_HANDLE;
			XrAction action_primary = XR_NULL_HANDLE;
			XrAction action_secondary = XR_NULL_HANDLE;
			XrAction action_menu = XR_NULL_HANDLE;
			XrAction action_haptic = XR_NULL_HANDLE;
			XrSpace space_grip[size_t(Hand::Count)] = {};
			XrSpace space_aim[size_t(Hand::Count)] = {};
		};
		State& GetState()
		{
			// Intentionally never destroyed: Shutdown() can be called from the destructor of a global Application object,
			//	and the destruction order of static objects would not guarantee that this still exists at that point
			static State* state = new State;
			return *state;
		}

		// Logs the error and returns false if an OpenXR call failed
		bool xr_check(XrResult result, const char* what)
		{
			if (XR_SUCCEEDED(result))
				return true;
			char result_string[XR_MAX_RESULT_STRING_SIZE] = "unknown";
			State& state = GetState();
			if (state.instance != XR_NULL_HANDLE)
			{
				xrResultToString(state.instance, result, result_string);
			}
			wilog_error("[wi::xr] %s failed: %s (%d)", what, result_string, (int)result);
			return false;
		}

		// The graphics queue can be used by the OpenXR runtime inside some functions, so those need to be synchronized with the engine
		struct QueueLock
		{
			std::unique_lock<std::mutex> lock;
			QueueLock()
			{
				State& state = GetState();
				if (state.device != nullptr)
				{
					lock = std::unique_lock<std::mutex>(state.device->GetGraphicsQueueLocker());
				}
			}
		};

		const XrPosef xr_pose_identity = { {0, 0, 0, 1}, {0, 0, 0} };

		// Converts from OpenXR tracking space (right handed, -Z forward) to engine world space (left handed, +Z forward) with tracking origin applied
		Pose ConvertPose(const XrPosef& xr_pose, bool valid)
		{
			Pose pose;
			pose.valid = valid;
			if (!valid)
				return pose;
			const XMVECTOR Q = XMVectorSet(-xr_pose.orientation.x, -xr_pose.orientation.y, xr_pose.orientation.z, xr_pose.orientation.w);
			const XMVECTOR P = XMVectorSet(xr_pose.position.x, xr_pose.position.y, -xr_pose.position.z, 1);
			const XMMATRIX M = XMMatrixRotationQuaternion(Q) * XMMatrixTranslationFromVector(P) * GetTrackingOrigin();
			XMVECTOR S, R, T;
			XMMatrixDecompose(&S, &R, &T, M);
			XMStoreFloat3(&pose.position, T);
			XMStoreFloat4(&pose.orientation, XMQuaternionNormalize(R));
			return pose;
		}

		Pose LocateSpace(XrSpace space, XrTime time)
		{
			const State& state = GetState();
			XrSpaceLocation location = { XR_TYPE_SPACE_LOCATION };
			if (space == XR_NULL_HANDLE || XR_FAILED(xrLocateSpace(space, state.space_app, time, &location)))
				return {};
			const XrSpaceLocationFlags required = XR_SPACE_LOCATION_POSITION_VALID_BIT | XR_SPACE_LOCATION_ORIENTATION_VALID_BIT;
			return ConvertPose(location.pose, (location.locationFlags & required) == required);
		}

		XrPath StringToPath(const std::string& str)
		{
			XrPath path = XR_NULL_PATH;
			xrStringToPath(GetState().instance, str.c_str(), &path);
			return path;
		}

		XrAction CreateAction(XrActionType type, const char* name, const char* localized_name)
		{
			State& state = GetState();
			XrActionCreateInfo info = { XR_TYPE_ACTION_CREATE_INFO };
			info.actionType = type;
			strncpy(info.actionName, name, sizeof(info.actionName) - 1);
			strncpy(info.localizedActionName, localized_name, sizeof(info.localizedActionName) - 1);
			info.countSubactionPaths = arraysize(state.hand_subaction_paths);
			info.subactionPaths = state.hand_subaction_paths;
			XrAction action = XR_NULL_HANDLE;
			xr_check(xrCreateAction(state.action_set, &info, &action), "xrCreateAction");
			return action;
		}

		bool CreateInput()
		{
			State& state = GetState();

			XrActionSetCreateInfo set_info = { XR_TYPE_ACTION_SET_CREATE_INFO };
			strncpy(set_info.actionSetName, "wicked_default", sizeof(set_info.actionSetName) - 1);
			strncpy(set_info.localizedActionSetName, "Default", sizeof(set_info.localizedActionSetName) - 1);
			if (!xr_check(xrCreateActionSet(state.instance, &set_info, &state.action_set), "xrCreateActionSet"))
				return false;

			for (size_t hand = 0; hand < size_t(Hand::Count); ++hand)
			{
				state.hand_subaction_paths[hand] = StringToPath(hand_paths[hand]);
			}

			state.action_grip_pose = CreateAction(XR_ACTION_TYPE_POSE_INPUT, "grip_pose", "Grip Pose");
			state.action_aim_pose = CreateAction(XR_ACTION_TYPE_POSE_INPUT, "aim_pose", "Aim Pose");
			state.action_trigger = CreateAction(XR_ACTION_TYPE_FLOAT_INPUT, "trigger", "Trigger");
			state.action_squeeze = CreateAction(XR_ACTION_TYPE_FLOAT_INPUT, "squeeze", "Squeeze");
			state.action_thumbstick = CreateAction(XR_ACTION_TYPE_VECTOR2F_INPUT, "thumbstick", "Thumbstick");
			state.action_thumbstick_click = CreateAction(XR_ACTION_TYPE_BOOLEAN_INPUT, "thumbstick_click", "Thumbstick Click");
			state.action_primary = CreateAction(XR_ACTION_TYPE_BOOLEAN_INPUT, "button_primary", "Primary Button");
			state.action_secondary = CreateAction(XR_ACTION_TYPE_BOOLEAN_INPUT, "button_secondary", "Secondary Button");
			state.action_menu = CreateAction(XR_ACTION_TYPE_BOOLEAN_INPUT, "button_menu", "Menu Button");
			state.action_haptic = CreateAction(XR_ACTION_TYPE_VIBRATION_OUTPUT, "haptic", "Haptic");

			// Suggest bindings for every known interaction profile, the runtime will select the one that matches the hardware:
			for (const InteractionProfile& profile : interaction_profiles)
			{
				wi::vector<XrActionSuggestedBinding> bindings;
				auto bind = [&](XrAction action, size_t hand, const char* subpath) {
					if (action == XR_NULL_HANDLE || subpath == nullptr)
						return;
					bindings.push_back({ action, StringToPath(std::string(hand_paths[hand]) + "/" + subpath) });
				};
				for (size_t hand = 0; hand < size_t(Hand::Count); ++hand)
				{
					bind(state.action_grip_pose, hand, "input/grip/pose");
					bind(state.action_aim_pose, hand, "input/aim/pose");
					bind(state.action_haptic, hand, "output/haptic");
					bind(state.action_trigger, hand, profile.trigger);
					bind(state.action_squeeze, hand, profile.squeeze);
					bind(state.action_thumbstick, hand, profile.thumbstick);
					bind(state.action_thumbstick_click, hand, profile.thumbstick_click);
					bind(state.action_primary, hand, profile.primary[hand]);
					bind(state.action_secondary, hand, profile.secondary[hand]);
					bind(state.action_menu, hand, profile.menu[hand]);
				}
				XrInteractionProfileSuggestedBinding suggested = { XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING };
				suggested.interactionProfile = StringToPath(profile.path);
				suggested.suggestedBindings = bindings.data();
				suggested.countSuggestedBindings = (uint32_t)bindings.size();
				// A runtime is allowed to reject profiles that it doesn't know, that is not an error:
				if (XR_FAILED(xrSuggestInteractionProfileBindings(state.instance, &suggested)))
				{
					wilog_warning("[wi::xr] interaction profile was not accepted by the runtime: %s", profile.path);
				}
			}

			for (size_t hand = 0; hand < size_t(Hand::Count); ++hand)
			{
				XrActionSpaceCreateInfo space_info = { XR_TYPE_ACTION_SPACE_CREATE_INFO };
				space_info.subactionPath = state.hand_subaction_paths[hand];
				space_info.poseInActionSpace = xr_pose_identity;
				space_info.action = state.action_grip_pose;
				xr_check(xrCreateActionSpace(state.session, &space_info, &state.space_grip[hand]), "xrCreateActionSpace");
				space_info.action = state.action_aim_pose;
				xr_check(xrCreateActionSpace(state.session, &space_info, &state.space_aim[hand]), "xrCreateActionSpace");
			}

			XrSessionActionSetsAttachInfo attach_info = { XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO };
			attach_info.countActionSets = 1;
			attach_info.actionSets = &state.action_set;
			return xr_check(xrAttachSessionActionSets(state.session, &attach_info), "xrAttachSessionActionSets");
		}

		float GetActionFloat(XrAction action, size_t hand)
		{
			State& state = GetState();
			XrActionStateGetInfo info = { XR_TYPE_ACTION_STATE_GET_INFO };
			info.action = action;
			info.subactionPath = state.hand_subaction_paths[hand];
			XrActionStateFloat value = { XR_TYPE_ACTION_STATE_FLOAT };
			if (action == XR_NULL_HANDLE || XR_FAILED(xrGetActionStateFloat(state.session, &info, &value)) || !value.isActive)
				return 0;
			return value.currentState;
		}
		bool GetActionBool(XrAction action, size_t hand)
		{
			State& state = GetState();
			XrActionStateGetInfo info = { XR_TYPE_ACTION_STATE_GET_INFO };
			info.action = action;
			info.subactionPath = state.hand_subaction_paths[hand];
			XrActionStateBoolean value = { XR_TYPE_ACTION_STATE_BOOLEAN };
			if (action == XR_NULL_HANDLE || XR_FAILED(xrGetActionStateBoolean(state.session, &info, &value)) || !value.isActive)
				return false;
			return value.currentState == XR_TRUE;
		}
		XMFLOAT2 GetActionVector2(XrAction action, size_t hand)
		{
			State& state = GetState();
			XrActionStateGetInfo info = { XR_TYPE_ACTION_STATE_GET_INFO };
			info.action = action;
			info.subactionPath = state.hand_subaction_paths[hand];
			XrActionStateVector2f value = { XR_TYPE_ACTION_STATE_VECTOR2F };
			if (action == XR_NULL_HANDLE || XR_FAILED(xrGetActionStateVector2f(state.session, &info, &value)) || !value.isActive)
				return XMFLOAT2(0, 0);
			return XMFLOAT2(value.currentState.x, value.currentState.y);
		}

		void UpdateInput(XrTime time)
		{
			State& state = GetState();
			if (state.action_set == XR_NULL_HANDLE)
				return;

			XrActiveActionSet active_set = { state.action_set, XR_NULL_PATH };
			XrActionsSyncInfo sync_info = { XR_TYPE_ACTIONS_SYNC_INFO };
			sync_info.countActiveActionSets = 1;
			sync_info.activeActionSets = &active_set;
			// This returns XR_SESSION_NOT_FOCUSED when the application is not focused, then inputs are simply inactive:
			xrSyncActions(state.session, &sync_info);

			for (size_t hand = 0; hand < size_t(Hand::Count); ++hand)
			{
				ControllerState& controller = state.controllers[hand];
				controller.grip = LocateSpace(state.space_grip[hand], time);
				controller.aim = LocateSpace(state.space_aim[hand], time);
				controller.trigger = GetActionFloat(state.action_trigger, hand);
				controller.squeeze = GetActionFloat(state.action_squeeze, hand);
				controller.thumbstick = GetActionVector2(state.action_thumbstick, hand);
				controller.thumbstick_click = GetActionBool(state.action_thumbstick_click, hand);
				controller.button_primary = GetActionBool(state.action_primary, hand);
				controller.button_secondary = GetActionBool(state.action_secondary, hand);
				controller.button_menu = GetActionBool(state.action_menu, hand);
			}
		}

		void UpdateTracking()
		{
			State& state = GetState();
			const XrTime time = state.frame_state.predictedDisplayTime;

			XrViewLocateInfo locate_info = { XR_TYPE_VIEW_LOCATE_INFO };
			locate_info.viewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
			locate_info.displayTime = time;
			locate_info.space = state.space_app;
			XrViewState view_state = { XR_TYPE_VIEW_STATE };
			uint32_t view_count = 0;
			for (XrView& view : state.views)
			{
				view = { XR_TYPE_VIEW };
			}
			const XrResult result = xrLocateViews(state.session, &locate_info, &view_state, EYE_COUNT, &view_count, state.views);
			const XrViewStateFlags required = XR_VIEW_STATE_POSITION_VALID_BIT | XR_VIEW_STATE_ORIENTATION_VALID_BIT;
			state.views_valid = XR_SUCCEEDED(result) && view_count == EYE_COUNT && (view_state.viewStateFlags & required) == required;

			if (state.views_valid)
			{
				for (uint32_t eye = 0; eye < EYE_COUNT; ++eye)
				{
					const XrView& view = state.views[eye];
					EyeView& dst = state.eyes[eye];
					dst.pose = ConvertPose(view.pose, true);
					dst.angle_left = view.fov.angleLeft;
					dst.angle_right = view.fov.angleRight;
					dst.angle_up = view.fov.angleUp;
					dst.angle_down = view.fov.angleDown;
				}
			}

			const Pose head = LocateSpace(state.space_head, time);
			if (head.valid)
			{
				state.head = head;
			}

			UpdateInput(time);
		}

		void HandleSessionStateChange(XrSessionState new_state)
		{
			State& state = GetState();
			state.session_state = new_state;
			switch (new_state)
			{
			case XR_SESSION_STATE_READY:
			{
				XrSessionBeginInfo begin_info = { XR_TYPE_SESSION_BEGIN_INFO };
				begin_info.primaryViewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
				QueueLock lock;
				state.session_running = xr_check(xrBeginSession(state.session, &begin_info), "xrBeginSession");
			}
			break;
			case XR_SESSION_STATE_STOPPING:
			{
				QueueLock lock;
				xr_check(xrEndSession(state.session), "xrEndSession");
				state.session_running = false;
			}
			break;
			case XR_SESSION_STATE_EXITING:
			case XR_SESSION_STATE_LOSS_PENDING:
				state.session_running = false;
				state.exit_requested = true;
				break;
			default:
				break;
			}
		}

		void PollEvents()
		{
			State& state = GetState();
			XrEventDataBuffer event = { XR_TYPE_EVENT_DATA_BUFFER };
			while (xrPollEvent(state.instance, &event) == XR_SUCCESS)
			{
				switch (event.type)
				{
				case XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED:
				{
					const XrEventDataSessionStateChanged& changed = *(const XrEventDataSessionStateChanged*)&event;
					if (changed.session == state.session)
					{
						HandleSessionStateChange(changed.state);
					}
				}
				break;
				case XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING:
					state.session_running = false;
					state.exit_requested = true;
					break;
				default:
					break;
				}
				event = { XR_TYPE_EVENT_DATA_BUFFER };
			}
		}

		bool CreateSwapchain()
		{
			State& state = GetState();

			XrViewConfigurationView config_views[EYE_COUNT] = { { XR_TYPE_VIEW_CONFIGURATION_VIEW }, { XR_TYPE_VIEW_CONFIGURATION_VIEW } };
			uint32_t view_count = 0;
			if (!xr_check(xrEnumerateViewConfigurationViews(state.instance, state.system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, EYE_COUNT, &view_count, config_views), "xrEnumerateViewConfigurationViews"))
				return false;
			state.eye_resolution.x = std::max(config_views[0].recommendedImageRectWidth, config_views[1].recommendedImageRectWidth);
			state.eye_resolution.y = std::max(config_views[0].recommendedImageRectHeight, config_views[1].recommendedImageRectHeight);

			// Select the color format, the order is the preference of the engine:
			uint32_t format_count = 0;
			xrEnumerateSwapchainFormats(state.session, 0, &format_count, nullptr);
			wi::vector<int64_t> runtime_formats(format_count);
			if (!xr_check(xrEnumerateSwapchainFormats(state.session, format_count, &format_count, runtime_formats.data()), "xrEnumerateSwapchainFormats"))
				return false;
			const Format preferred_formats[] = {
				Format::R8G8B8A8_UNORM_SRGB,
				Format::B8G8R8A8_UNORM_SRGB,
				Format::R8G8B8A8_UNORM,
				Format::B8G8R8A8_UNORM,
			};
			Format format = Format::UNKNOWN;
			for (Format preferred : preferred_formats)
			{
				const int64_t native = (int64_t)GraphicsDevice_Vulkan::GetNativeFormat(preferred);
				if (std::find(runtime_formats.begin(), runtime_formats.end(), native) != runtime_formats.end())
				{
					format = preferred;
					break;
				}
			}
			if (format == Format::UNKNOWN)
			{
				wilog_error("[wi::xr] the runtime doesn't support any of the swapchain formats that the engine can use!");
				return false;
			}

			// One swapchain is used as texture array, so both eyes can be rendered in one pass:
			XrSwapchainCreateInfo swapchain_info = { XR_TYPE_SWAPCHAIN_CREATE_INFO };
			swapchain_info.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT | XR_SWAPCHAIN_USAGE_SAMPLED_BIT;
			swapchain_info.format = (int64_t)GraphicsDevice_Vulkan::GetNativeFormat(format);
			swapchain_info.sampleCount = 1;
			swapchain_info.width = state.eye_resolution.x;
			swapchain_info.height = state.eye_resolution.y;
			swapchain_info.faceCount = 1;
			swapchain_info.arraySize = EYE_COUNT;
			swapchain_info.mipCount = 1;
			{
				QueueLock lock;
				if (!xr_check(xrCreateSwapchain(state.session, &swapchain_info, &state.swapchain), "xrCreateSwapchain"))
					return false;
			}

			uint32_t image_count = 0;
			xrEnumerateSwapchainImages(state.swapchain, 0, &image_count, nullptr);
			wi::vector<XrSwapchainImageVulkan2KHR> images(image_count, { XR_TYPE_SWAPCHAIN_IMAGE_VULKAN2_KHR });
			if (!xr_check(xrEnumerateSwapchainImages(state.swapchain, image_count, &image_count, (XrSwapchainImageBaseHeader*)images.data()), "xrEnumerateSwapchainImages"))
				return false;

			TextureDesc desc;
			desc.type = TextureDesc::Type::TEXTURE_2D;
			desc.width = state.eye_resolution.x;
			desc.height = state.eye_resolution.y;
			desc.array_size = EYE_COUNT;
			desc.mip_levels = 1;
			desc.format = format;
			desc.bind_flags = BindFlag::RENDER_TARGET | BindFlag::SHADER_RESOURCE;
			desc.layout = ResourceState::RENDERTARGET; // OpenXR requires the image to be in color attachment layout when it is released

			state.swapchain_images.resize(image_count);
			for (uint32_t i = 0; i < image_count; ++i)
			{
				Texture& texture = state.swapchain_images[i].texture;
				if (!state.device->CreateTextureFromNativeImage(&desc, (void*)images[i].image, &texture))
					return false;
				state.device->SetName(&texture, "wi::xr::swapchain");
				// Per eye render target views, so that one eye can be rendered separately too:
				for (uint32_t eye = 0; eye < EYE_COUNT; ++eye)
				{
					// The subresource index will be the same as the eye index
					state.device->CreateSubresource(&texture, SubresourceType::RTV, eye, 1, 0, 1);
					state.device->CreateSubresource(&texture, SubresourceType::SRV, eye, 1, 0, 1);
				}
			}

			wilog("[wi::xr] swapchain created: %ux%u per eye, %u images", state.eye_resolution.x, state.eye_resolution.y, image_count);
			return true;
		}
	}

	bool Initialize()
	{
		State& state = GetState();
		if (state.instance != XR_NULL_HANDLE)
			return true;

		// Check that the runtime supports the Vulkan binding:
		uint32_t extension_count = 0;
		if (XR_FAILED(xrEnumerateInstanceExtensionProperties(nullptr, 0, &extension_count, nullptr)))
		{
			wilog_warning("[wi::xr] no OpenXR runtime was found");
			return false;
		}
		wi::vector<XrExtensionProperties> extensions(extension_count, { XR_TYPE_EXTENSION_PROPERTIES });
		xrEnumerateInstanceExtensionProperties(nullptr, extension_count, &extension_count, extensions.data());
		bool vulkan_supported = false;
		for (const XrExtensionProperties& extension : extensions)
		{
			if (strcmp(extension.extensionName, XR_KHR_VULKAN_ENABLE2_EXTENSION_NAME) == 0)
			{
				vulkan_supported = true;
				break;
			}
		}
		if (!vulkan_supported)
		{
			wilog_error("[wi::xr] the OpenXR runtime doesn't support " XR_KHR_VULKAN_ENABLE2_EXTENSION_NAME);
			return false;
		}

		const char* enabled_extensions[] = {
			XR_KHR_VULKAN_ENABLE2_EXTENSION_NAME,
		};
		XrInstanceCreateInfo instance_info = { XR_TYPE_INSTANCE_CREATE_INFO };
		strncpy(instance_info.applicationInfo.applicationName, "Wicked Engine Application", sizeof(instance_info.applicationInfo.applicationName) - 1);
		strncpy(instance_info.applicationInfo.engineName, "Wicked Engine", sizeof(instance_info.applicationInfo.engineName) - 1);
		instance_info.applicationInfo.applicationVersion = 1;
		instance_info.applicationInfo.engineVersion = 1;
		instance_info.applicationInfo.apiVersion = XR_MAKE_VERSION(1, 0, 0); // compatible with OpenXR 1.0 and 1.1 runtimes
		instance_info.enabledExtensionCount = arraysize(enabled_extensions);
		instance_info.enabledExtensionNames = enabled_extensions;
		if (!xr_check(xrCreateInstance(&instance_info, &state.instance), "xrCreateInstance"))
		{
			state.instance = XR_NULL_HANDLE;
			return false;
		}

		xrGetInstanceProcAddr(state.instance, "xrGetVulkanGraphicsRequirements2KHR", (PFN_xrVoidFunction*)&state.get_vulkan_graphics_requirements);
		xrGetInstanceProcAddr(state.instance, "xrCreateVulkanInstanceKHR", (PFN_xrVoidFunction*)&state.create_vulkan_instance);
		xrGetInstanceProcAddr(state.instance, "xrGetVulkanGraphicsDevice2KHR", (PFN_xrVoidFunction*)&state.get_vulkan_graphics_device);
		xrGetInstanceProcAddr(state.instance, "xrCreateVulkanDeviceKHR", (PFN_xrVoidFunction*)&state.create_vulkan_device);
		if (state.get_vulkan_graphics_requirements == nullptr || state.create_vulkan_instance == nullptr || state.get_vulkan_graphics_device == nullptr || state.create_vulkan_device == nullptr)
		{
			wilog_error("[wi::xr] the Vulkan functions of the OpenXR runtime could not be loaded!");
			Shutdown();
			return false;
		}

		XrSystemGetInfo system_info = { XR_TYPE_SYSTEM_GET_INFO };
		system_info.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
		if (XR_FAILED(xrGetSystem(state.instance, &system_info, &state.system)))
		{
			wilog_warning("[wi::xr] no head mounted display was found");
			Shutdown();
			return false;
		}

		XrInstanceProperties instance_properties = { XR_TYPE_INSTANCE_PROPERTIES };
		xrGetInstanceProperties(state.instance, &instance_properties);
		XrSystemProperties system_properties = { XR_TYPE_SYSTEM_PROPERTIES };
		xrGetSystemProperties(state.instance, state.system, &system_properties);
		wilog("[wi::xr] initialized, runtime: %s, system: %s", instance_properties.runtimeName, system_properties.systemName);

		return true;
	}

	void Shutdown()
	{
		State& state = GetState();
		if (state.device != nullptr)
		{
			state.device->WaitForGPU();
		}
		state.swapchain_images.clear();
		if (state.swapchain != XR_NULL_HANDLE)
		{
			xrDestroySwapchain(state.swapchain);
		}
		if (state.session != XR_NULL_HANDLE)
		{
			// Destroying the session also destroys the spaces that belong to it
			xrDestroySession(state.session);
		}
		if (state.instance != XR_NULL_HANDLE)
		{
			// Destroying the instance also destroys the action set and actions
			xrDestroyInstance(state.instance);
		}
		state = {};
	}

	bool IsInitialized()
	{
		return GetState().instance != XR_NULL_HANDLE;
	}
	bool IsSessionRunning()
	{
		return GetState().session_running;
	}
	bool IsExitRequested()
	{
		return GetState().exit_requested;
	}

	const VulkanCreationHooks* GetVulkanCreationHooks()
	{
		if (!IsInitialized())
			return nullptr;

		static VulkanCreationHooks hooks_storage;
		VulkanCreationHooks* hooks = &hooks_storage;

		hooks->create_instance = [](const VkInstanceCreateInfo* create_info, VkInstance* instance) -> VkResult {
			State& state = GetState();

			XrGraphicsRequirementsVulkan2KHR requirements = { XR_TYPE_GRAPHICS_REQUIREMENTS_VULKAN2_KHR };
			if (!xr_check(state.get_vulkan_graphics_requirements(state.instance, state.system, &requirements), "xrGetVulkanGraphicsRequirements2KHR"))
				return VK_ERROR_INITIALIZATION_FAILED;
			const uint32_t api_version = create_info->pApplicationInfo->apiVersion;
			const XrVersion engine_version = XR_MAKE_VERSION(VK_API_VERSION_MAJOR(api_version), VK_API_VERSION_MINOR(api_version), 0);
			if (engine_version < requirements.minApiVersionSupported)
			{
				wilog_error("[wi::xr] the OpenXR runtime requires a newer Vulkan version than what the engine uses!");
				return VK_ERROR_INITIALIZATION_FAILED;
			}

			XrVulkanInstanceCreateInfoKHR xr_create_info = { XR_TYPE_VULKAN_INSTANCE_CREATE_INFO_KHR };
			xr_create_info.systemId = state.system;
			xr_create_info.pfnGetInstanceProcAddr = vkGetInstanceProcAddr;
			xr_create_info.vulkanCreateInfo = create_info;
			VkResult vulkan_result = VK_SUCCESS;
			if (!xr_check(state.create_vulkan_instance(state.instance, &xr_create_info, instance, &vulkan_result), "xrCreateVulkanInstanceKHR"))
				return VK_ERROR_INITIALIZATION_FAILED;
			return vulkan_result;
		};

		hooks->select_physical_device = [](VkInstance instance) -> VkPhysicalDevice {
			State& state = GetState();
			XrVulkanGraphicsDeviceGetInfoKHR get_info = { XR_TYPE_VULKAN_GRAPHICS_DEVICE_GET_INFO_KHR };
			get_info.systemId = state.system;
			get_info.vulkanInstance = instance;
			VkPhysicalDevice physical_device = VK_NULL_HANDLE;
			if (!xr_check(state.get_vulkan_graphics_device(state.instance, &get_info, &physical_device), "xrGetVulkanGraphicsDevice2KHR"))
				return VK_NULL_HANDLE;
			return physical_device;
		};

		hooks->create_device = [](VkPhysicalDevice physical_device, const VkDeviceCreateInfo* create_info, VkDevice* device) -> VkResult {
			State& state = GetState();
			XrVulkanDeviceCreateInfoKHR xr_create_info = { XR_TYPE_VULKAN_DEVICE_CREATE_INFO_KHR };
			xr_create_info.systemId = state.system;
			xr_create_info.pfnGetInstanceProcAddr = vkGetInstanceProcAddr;
			xr_create_info.vulkanPhysicalDevice = physical_device;
			xr_create_info.vulkanCreateInfo = create_info;
			VkResult vulkan_result = VK_SUCCESS;
			if (!xr_check(state.create_vulkan_device(state.instance, &xr_create_info, device, &vulkan_result), "xrCreateVulkanDeviceKHR"))
				return VK_ERROR_INITIALIZATION_FAILED;
			return vulkan_result;
		};

		return hooks;
	}

	bool CreateSession(GraphicsDevice* device)
	{
		State& state = GetState();
		if (!IsInitialized() || device == nullptr)
			return false;
		if (state.session != XR_NULL_HANDLE)
			return true;
		if (strcmp(device->GetTag(), "[Vulkan]") != 0)
		{
			wilog_error("[wi::xr] only the Vulkan graphics device is supported!");
			return false;
		}
		state.device = static_cast<GraphicsDevice_Vulkan*>(device);

		XrGraphicsBindingVulkan2KHR binding = { XR_TYPE_GRAPHICS_BINDING_VULKAN2_KHR };
		binding.instance = state.device->GetInstance();
		binding.physicalDevice = state.device->GetPhysicalDevice();
		binding.device = state.device->GetDevice();
		binding.queueFamilyIndex = state.device->GetGraphicsFamilyIndex();
		binding.queueIndex = 0;

		XrSessionCreateInfo session_info = { XR_TYPE_SESSION_CREATE_INFO };
		session_info.next = &binding;
		session_info.systemId = state.system;
		if (!xr_check(xrCreateSession(state.instance, &session_info, &state.session), "xrCreateSession"))
		{
			state.session = XR_NULL_HANDLE;
			return false;
		}

		// Prefer the stage space (origin on the floor of the play area), fall back to local space (origin at the initial head position):
		uint32_t space_count = 0;
		xrEnumerateReferenceSpaces(state.session, 0, &space_count, nullptr);
		wi::vector<XrReferenceSpaceType> space_types(space_count);
		xrEnumerateReferenceSpaces(state.session, space_count, &space_count, space_types.data());
		const bool stage_supported = std::find(space_types.begin(), space_types.end(), XR_REFERENCE_SPACE_TYPE_STAGE) != space_types.end();

		XrReferenceSpaceCreateInfo space_info = { XR_TYPE_REFERENCE_SPACE_CREATE_INFO };
		space_info.poseInReferenceSpace = xr_pose_identity;
		space_info.referenceSpaceType = stage_supported ? XR_REFERENCE_SPACE_TYPE_STAGE : XR_REFERENCE_SPACE_TYPE_LOCAL;
		if (!xr_check(xrCreateReferenceSpace(state.session, &space_info, &state.space_app), "xrCreateReferenceSpace"))
			return false;
		space_info.referenceSpaceType = XR_REFERENCE_SPACE_TYPE_VIEW;
		if (!xr_check(xrCreateReferenceSpace(state.session, &space_info, &state.space_head), "xrCreateReferenceSpace"))
			return false;

		// Prefer opaque blending (VR), but accept whatever the device supports:
		uint32_t blend_count = 0;
		xrEnumerateEnvironmentBlendModes(state.instance, state.system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 0, &blend_count, nullptr);
		wi::vector<XrEnvironmentBlendMode> blend_modes(blend_count);
		xrEnumerateEnvironmentBlendModes(state.instance, state.system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, blend_count, &blend_count, blend_modes.data());
		if (!blend_modes.empty() && std::find(blend_modes.begin(), blend_modes.end(), XR_ENVIRONMENT_BLEND_MODE_OPAQUE) == blend_modes.end())
		{
			state.blend_mode = blend_modes[0];
		}

		if (!CreateSwapchain())
			return false;

		if (!CreateInput())
		{
			wilog_warning("[wi::xr] input could not be initialized, controllers will not be available");
		}

		return true;
	}

	bool BeginFrame()
	{
		State& state = GetState();
		if (state.session == XR_NULL_HANDLE)
			return false;

		state.frame_begun = false;
		state.frame_should_render = false;
		state.image_acquired = false;

		PollEvents();
		if (!state.session_running)
			return false;

		// Blocks until the runtime decides that the next frame should start, this is what throttles the application to the display refresh rate:
		state.frame_state = { XR_TYPE_FRAME_STATE };
		if (!xr_check(xrWaitFrame(state.session, nullptr, &state.frame_state), "xrWaitFrame"))
			return false;

		{
			QueueLock lock;
			if (!xr_check(xrBeginFrame(state.session, nullptr), "xrBeginFrame"))
				return false;
		}
		state.frame_begun = true;

		UpdateTracking();

		if (state.frame_state.shouldRender == XR_TRUE && state.views_valid)
		{
			QueueLock lock;
			if (xr_check(xrAcquireSwapchainImage(state.swapchain, nullptr, &state.swapchain_image_index), "xrAcquireSwapchainImage"))
			{
				state.image_acquired = true;
				XrSwapchainImageWaitInfo wait_info = { XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO };
				wait_info.timeout = XR_INFINITE_DURATION;
				state.frame_should_render = xr_check(xrWaitSwapchainImage(state.swapchain, &wait_info), "xrWaitSwapchainImage");
			}
		}

		return state.frame_should_render;
	}

	void EndFrame()
	{
		State& state = GetState();
		if (!state.frame_begun)
			return;
		state.frame_begun = false;

		QueueLock lock;

		if (state.image_acquired)
		{
			xr_check(xrReleaseSwapchainImage(state.swapchain, nullptr), "xrReleaseSwapchainImage");
			state.image_acquired = false;
		}

		XrCompositionLayerProjectionView projection_views[EYE_COUNT] = {};
		XrCompositionLayerProjection layer = { XR_TYPE_COMPOSITION_LAYER_PROJECTION };
		const XrCompositionLayerBaseHeader* layers[1] = {};
		uint32_t layer_count = 0;

		if (state.frame_should_render)
		{
			for (uint32_t eye = 0; eye < EYE_COUNT; ++eye)
			{
				XrCompositionLayerProjectionView& projection_view = projection_views[eye];
				projection_view.type = XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW;
				// The same pose and fov must be submitted that was used for rendering:
				projection_view.pose = state.views[eye].pose;
				projection_view.fov = state.views[eye].fov;
				projection_view.subImage.swapchain = state.swapchain;
				projection_view.subImage.imageRect.offset = { 0, 0 };
				projection_view.subImage.imageRect.extent = { (int32_t)state.eye_resolution.x, (int32_t)state.eye_resolution.y };
				projection_view.subImage.imageArrayIndex = eye;
			}
			layer.space = state.space_app;
			layer.viewCount = EYE_COUNT;
			layer.views = projection_views;
			layers[layer_count++] = (const XrCompositionLayerBaseHeader*)&layer;
		}

		XrFrameEndInfo end_info = { XR_TYPE_FRAME_END_INFO };
		end_info.displayTime = state.frame_state.predictedDisplayTime;
		end_info.environmentBlendMode = state.blend_mode;
		end_info.layerCount = layer_count;
		end_info.layers = layer_count > 0 ? layers : nullptr;
		xr_check(xrEndFrame(state.session, &end_info), "xrEndFrame");

		state.frame_should_render = false;
	}

	XMUINT2 GetEyeResolution()
	{
		return GetState().eye_resolution;
	}
	const Texture* GetSwapchainTexture()
	{
		State& state = GetState();
		if (!state.frame_should_render || state.swapchain_image_index >= state.swapchain_images.size())
			return nullptr;
		return &state.swapchain_images[state.swapchain_image_index].texture;
	}
	float GetPredictedDisplayPeriod()
	{
		return float(double(GetState().frame_state.predictedDisplayPeriod) * 1e-9);
	}

	const EyeView& GetEyeView(uint32_t eye)
	{
		return GetState().eyes[std::min(eye, EYE_COUNT - 1)];
	}
	const Pose& GetHeadPose()
	{
		return GetState().head;
	}
	const ControllerState& GetControllerState(Hand hand)
	{
		return GetState().controllers[std::min(size_t(hand), size_t(Hand::Count) - 1)];
	}

	void Vibrate(Hand hand, float amplitude, float duration_seconds, float frequency)
	{
		State& state = GetState();
		if (!state.session_running || state.action_haptic == XR_NULL_HANDLE || size_t(hand) >= size_t(Hand::Count))
			return;
		XrHapticVibration vibration = { XR_TYPE_HAPTIC_VIBRATION };
		vibration.amplitude = saturate(amplitude);
		vibration.duration = XrDuration(double(duration_seconds) * 1e9);
		vibration.frequency = frequency > 0 ? frequency : XR_FREQUENCY_UNSPECIFIED;
		XrHapticActionInfo haptic_info = { XR_TYPE_HAPTIC_ACTION_INFO };
		haptic_info.action = state.action_haptic;
		haptic_info.subactionPath = state.hand_subaction_paths[size_t(hand)];
		xrApplyHapticFeedback(state.session, &haptic_info, (const XrHapticBaseHeader*)&vibration);
	}
}

#else

// Implementation when the engine was built without OpenXR support:
namespace wi::xr
{
	namespace
	{
		const EyeView eye_view_dummy;
		const Pose pose_dummy;
		const ControllerState controller_dummy;
	}
	bool Initialize() { return false; }
	void Shutdown() {}
	bool IsInitialized() { return false; }
	bool IsSessionRunning() { return false; }
	bool IsExitRequested() { return false; }
	const wi::graphics::VulkanCreationHooks* GetVulkanCreationHooks() { return nullptr; }
	bool CreateSession(wi::graphics::GraphicsDevice* device) { return false; }
	bool BeginFrame() { return false; }
	void EndFrame() {}
	XMUINT2 GetEyeResolution() { return XMUINT2(0, 0); }
	const wi::graphics::Texture* GetSwapchainTexture() { return nullptr; }
	float GetPredictedDisplayPeriod() { return 0; }
	const EyeView& GetEyeView(uint32_t eye) { return eye_view_dummy; }
	const Pose& GetHeadPose() { return pose_dummy; }
	const ControllerState& GetControllerState(Hand hand) { return controller_dummy; }
	void Vibrate(Hand hand, float amplitude, float duration_seconds, float frequency) {}
}

#endif // WICKED_XR_IMPLEMENTATION

// Camera helpers are independent of the XR implementation:
namespace wi::xr
{
	namespace
	{
		void ApplyPoseAndProjectionToCamera(
			const Pose& pose,
			float tan_left, float tan_right, float tan_up, float tan_down,
			wi::scene::CameraComponent& camera,
			float znear, float zfar
		)
		{
			camera.zNearP = znear;
			camera.zFarP = zfar;
			camera.fov = std::atan(tan_up) - std::atan(tan_down);
			camera.jitter = XMFLOAT2(0, 0);

			const XMVECTOR Q = XMLoadFloat4(&pose.orientation);
			XMStoreFloat3(&camera.Eye, XMLoadFloat3(&pose.position));
			XMStoreFloat3(&camera.At, XMVector3Normalize(XMVector3Rotate(XMVectorSet(0, 0, 1, 0), Q)));
			XMStoreFloat3(&camera.Up, XMVector3Normalize(XMVector3Rotate(XMVectorSet(0, 1, 0, 0), Q)));

			// Asymmetric projection with reversed depth buffer (near and far are swapped, like the rest of the engine):
			//	The extents are specified on the first plane that is passed, which is the far plane here
			const XMMATRIX P = XMMatrixPerspectiveOffCenterLH(tan_left * zfar, tan_right * zfar, tan_down * zfar, tan_up * zfar, zfar, znear);
			XMStoreFloat4x4(&camera.Projection, P);
			camera.SetCustomProjectionEnabled(true);
			camera.SetOrtho(false);
			camera.UpdateCamera();
		}
	}

	void ApplyEyeToCamera(const EyeView& eye, wi::scene::CameraComponent& camera, float znear, float zfar)
	{
		ApplyPoseAndProjectionToCamera(
			eye.pose,
			std::tan(eye.angle_left), std::tan(eye.angle_right), std::tan(eye.angle_up), std::tan(eye.angle_down),
			camera, znear, zfar
		);
	}

	void ApplyHeadToCullingCamera(wi::scene::CameraComponent& camera, float znear, float zfar)
	{
		const Pose& head = GetHeadPose();
		const XMVECTOR head_orientation_inverse = XMQuaternionInverse(XMLoadFloat4(&head.orientation));
		const XMVECTOR head_position = XMLoadFloat3(&head.position);

		// Compute the extents in head space that contain the frustum of both eyes (the eyes can be rotated relative to the head):
		float tan_left = 0, tan_right = 0, tan_up = 0, tan_down = 0;
		float max_eye_offset = 0;
		for (uint32_t i = 0; i < EYE_COUNT; ++i)
		{
			const EyeView& eye = GetEyeView(i);
			const XMVECTOR eye_to_head = XMQuaternionMultiply(XMLoadFloat4(&eye.pose.orientation), head_orientation_inverse);
			const float tan_x[] = { std::tan(eye.angle_left), std::tan(eye.angle_right) };
			const float tan_y[] = { std::tan(eye.angle_down), std::tan(eye.angle_up) };
			for (float x : tan_x)
			{
				for (float y : tan_y)
				{
					XMFLOAT3 corner;
					XMStoreFloat3(&corner, XMVector3Rotate(XMVectorSet(x, y, 1, 0), eye_to_head));
					if (corner.z <= 0.001f)
						continue;
					tan_left = std::min(tan_left, corner.x / corner.z);
					tan_right = std::max(tan_right, corner.x / corner.z);
					tan_down = std::min(tan_down, corner.y / corner.z);
					tan_up = std::max(tan_up, corner.y / corner.z);
				}
			}
			const XMVECTOR eye_offset = XMVector3Rotate(XMLoadFloat3(&eye.pose.position) - head_position, head_orientation_inverse);
			max_eye_offset = std::max(max_eye_offset, std::abs(XMVectorGetX(eye_offset)));
		}

		// The camera is moved backwards so that its frustum also contains the eyes that are next to the head center:
		const float min_tan = std::max(0.01f, std::min(-tan_left, tan_right));
		const float pull_back = max_eye_offset / min_tan;
		Pose pose = head;
		XMStoreFloat3(&pose.position, head_position - XMVector3Rotate(XMVectorSet(0, 0, pull_back, 0), XMLoadFloat4(&head.orientation)));

		ApplyPoseAndProjectionToCamera(pose, tan_left, tan_right, tan_up, tan_down, camera, znear, zfar + pull_back);
	}
}
