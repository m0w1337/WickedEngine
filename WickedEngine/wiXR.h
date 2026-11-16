#pragma once
#include "CommonInclude.h"
#include "wiGraphics.h"
#include "wiMath.h"
#include "wiScene_Decl.h"

namespace wi::graphics
{
	class GraphicsDevice;
	struct VulkanCreationHooks;
}

// Virtual reality support based on OpenXR
//	The implementation is only available if the engine was built with WICKED_OPENXR, otherwise every function is a no-op
//
//	Usage overview (wi::Application handles all of this automatically if XR was requested):
//		1) Initialize()				- before the graphics device is created
//		2) GetVulkanCreationHooks()	- pass it to the GraphicsDevice_Vulkan constructor
//		3) CreateSession()			- after the graphics device was created
//		4) every frame: BeginFrame() -> render into GetSwapchainTexture() -> submit command lists -> EndFrame()
namespace wi::xr
{
	static constexpr uint32_t EYE_COUNT = 2;

	enum class Hand
	{
		Left,
		Right,
		Count
	};

	// A tracked pose in engine world space (left handed, Y up, +Z forward)
	struct Pose
	{
		XMFLOAT3 position = XMFLOAT3(0, 0, 0);
		XMFLOAT4 orientation = XMFLOAT4(0, 0, 0, 1);
		bool valid = false;

		XMMATRIX GetMatrix() const
		{
			return XMMatrixRotationQuaternion(XMLoadFloat4(&orientation)) * XMMatrixTranslationFromVector(XMLoadFloat3(&position));
		}
	};

	// Describes one eye of the head mounted display for the current frame
	struct EyeView
	{
		Pose pose;
		// Field of view half angles in radians, left and down are usually negative:
		float angle_left = -XM_PIDIV4;
		float angle_right = XM_PIDIV4;
		float angle_up = XM_PIDIV4;
		float angle_down = -XM_PIDIV4;
	};

	struct ControllerState
	{
		Pose grip; // the pose of the hand holding the controller
		Pose aim; // the pose of a pointing ray
		float trigger = 0;
		float squeeze = 0;
		XMFLOAT2 thumbstick = XMFLOAT2(0, 0);
		bool thumbstick_click = false;
		bool button_primary = false; // A or X
		bool button_secondary = false; // B or Y
		bool button_menu = false;
	};

	// Creates the OpenXR instance and looks for a head mounted display
	//	Returns false if there is no OpenXR runtime or no headset available
	bool Initialize();
	// Destroys everything that was created by the XR system
	void Shutdown();
	// Returns true if Initialize() was successful
	bool IsInitialized();
	// Returns true if the XR session exists and frames can be submitted to the headset
	bool IsSessionRunning();
	// Returns true if the runtime requested the application to quit
	bool IsExitRequested();

	// Returns the hooks that let the OpenXR runtime take part in Vulkan instance and device creation
	//	Returns nullptr if XR is not initialized. The returned object is owned by the XR system
	const wi::graphics::VulkanCreationHooks* GetVulkanCreationHooks();

	// Creates the XR session, the reference space, the swapchain and the input actions for an existing graphics device
	bool CreateSession(wi::graphics::GraphicsDevice* device);

	// Starts a new XR frame: processes runtime events, waits for the optimal frame start, updates tracking and acquires the swapchain image
	//	Returns true if the application should render the frame, then EndFrame() must be called after the command lists were submitted
	bool BeginFrame();
	// Hands over the rendered swapchain image to the XR compositor. It must be called after the graphics device submitted the command lists
	void EndFrame();

	// Resolution of one eye in pixels as recommended by the runtime
	XMUINT2 GetEyeResolution();
	// The swapchain texture of the current frame. It is a texture array, every eye has its own array slice
	//	Only valid between BeginFrame() and EndFrame()
	const wi::graphics::Texture* GetSwapchainTexture();
	// Display refresh period in seconds as predicted by the runtime
	float GetPredictedDisplayPeriod();

	// The tracking origin transforms from tracking space (play area) to engine world space
	//	It can be used to move or rotate the player in the world
	void SetTrackingOrigin(const XMMATRIX& world_from_tracking);
	XMMATRIX GetTrackingOrigin();

	// Tracking state of the current frame, in engine world space:
	const EyeView& GetEyeView(uint32_t eye);
	const Pose& GetHeadPose();
	const ControllerState& GetControllerState(Hand hand);

	// Starts a vibration on the controller. amplitude: [0, 1], frequency in Hz (0 = runtime default)
	void Vibrate(Hand hand, float amplitude, float duration_seconds, float frequency = 0);

	// Sets up a camera to match an eye of the headset (view and asymmetric projection)
	void ApplyEyeToCamera(const EyeView& eye, wi::scene::CameraComponent& camera, float znear, float zfar);
	// Sets up a camera at the head position whose frustum contains the frustums of both eyes. It can be used for culling
	void ApplyHeadToCullingCamera(wi::scene::CameraComponent& camera, float znear, float zfar);
}
