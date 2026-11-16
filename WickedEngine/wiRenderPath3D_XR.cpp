#include "wiRenderPath3D_XR.h"
#include "wiImage.h"
#include "wiRenderer.h"
#include "wiBacklog.h"

using namespace wi::graphics;

namespace wi
{
	// These effects are uncomfortable or look wrong in a head mounted display, so they are disabled by default:
	static void ApplyDefaultSettings(RenderPath3D& eye)
	{
		eye.setMotionBlurEnabled(false);
		eye.setDepthOfFieldEnabled(false);
		eye.setChromaticAberrationEnabled(false);
		eye.setLensFlareEnabled(false);
		eye.setLightShaftsEnabled(false);
		eye.setEyeAdaptionEnabled(false);
	}

	RenderPath3D_XR::RenderPath3D_XR()
	{
		for (uint32_t i = 0; i < arraysize(eyes); ++i)
		{
			eyes[i].camera = &cameras[i];
			// The scene is shared between the eyes, so it must be updated only once per frame:
			eyes[i].setSceneUpdateEnabled(i == 0);
			// The occlusion queries are allocated per object in the scene, not per render path, so only one eye can use them:
			//	Otherwise one eye allocates queries for objects that the other eye never draws, and the query resolve
			//	waits for them forever on Vulkan (VK_QUERY_RESULT_WAIT_BIT), which hangs the GPU
			//	(this only matters when single pass stereo rendering is not supported, otherwise occlusion culling is not used at all)
			eyes[i].setOcclusionCullingEnabled(i == 0);
			ApplyDefaultSettings(eyes[i]);
		}

		eyes[0].stereo_culling_camera = &culling_camera;
	}

	void RenderPath3D_XR::SetScene(wi::scene::Scene* scene)
	{
		for (RenderPath3D& eye : eyes)
		{
			eye.scene = scene;
		}
	}

	void RenderPath3D_XR::UpdateEyeResolution()
	{
		// The eyes are rendered in the resolution that is recommended by the headset, independently from the window:
		XMUINT2 resolution = wi::xr::GetEyeResolution();
		if (resolution.x == 0 || resolution.y == 0)
		{
			// Without a headset, the window is split into two halves:
			resolution.x = std::max(1u, GetPhysicalWidth() / 2);
			resolution.y = std::max(1u, GetPhysicalHeight());
		}
		for (RenderPath3D& eye : eyes)
		{
			eye.init(resolution.x, resolution.y);
			eye.colorspace = ColorSpace::SRGB;
		}
	}

	void RenderPath3D_XR::UpdateCameras()
	{
		for (uint32_t i = 0; i < arraysize(eyes); ++i)
		{
			wi::xr::EyeView view = wi::xr::GetEyeView(i);
			if (!wi::xr::IsSessionRunning())
			{
				// Without a headset, the eyes of a standing player are simulated, so the application remains usable on the desktop:
				const float half_ipd = 0.032f;
				const float aspect = (float)eyes[i].GetPhysicalWidth() / (float)eyes[i].GetPhysicalHeight();
				view = {};
				XMStoreFloat3(&view.pose.position, XMVector3Transform(XMVectorSet(i == 0 ? -half_ipd : half_ipd, fallback_eye_height, 0, 1), wi::xr::GetTrackingOrigin()));
				XMStoreFloat4(&view.pose.orientation, XMQuaternionRotationMatrix(wi::xr::GetTrackingOrigin()));
				view.pose.valid = true;
				view.angle_up = fallback_fov * 0.5f;
				view.angle_down = -view.angle_up;
				view.angle_right = std::atan(std::tan(view.angle_up) * aspect);
				view.angle_left = -view.angle_right;
			}
			wi::xr::ApplyEyeToCamera(view, cameras[i], znear, zfar);
			cameras[i].width = (float)eyes[i].GetPhysicalWidth();
			cameras[i].height = (float)eyes[i].GetPhysicalHeight();
		}

		// The culling camera contains the view of both eyes:
		if (wi::xr::IsSessionRunning())
		{
			wi::xr::ApplyHeadToCullingCamera(culling_camera, znear, zfar);
		}
		else
		{
			// The simulated eyes are parallel and symmetric, so the camera only needs to be moved backwards from the center between them:
			const float half_ipd = 0.032f;
			const float aspect = (float)eyes[0].GetPhysicalWidth() / (float)eyes[0].GetPhysicalHeight();
			wi::xr::EyeView view = {};
			view.angle_up = fallback_fov * 0.5f;
			view.angle_down = -view.angle_up;
			view.angle_right = std::atan(std::tan(view.angle_up) * aspect);
			view.angle_left = -view.angle_right;
			const float pull_back = half_ipd / std::max(0.01f, std::tan(view.angle_right));
			XMStoreFloat3(&view.pose.position, XMVector3Transform(XMVectorSet(0, fallback_eye_height, -pull_back, 1), wi::xr::GetTrackingOrigin()));
			XMStoreFloat4(&view.pose.orientation, XMQuaternionRotationMatrix(wi::xr::GetTrackingOrigin()));
			view.pose.valid = true;
			wi::xr::ApplyEyeToCamera(view, culling_camera, znear, zfar + pull_back);
		}
		culling_camera.width = cameras[0].width;
		culling_camera.height = cameras[0].height;
	}

	void RenderPath3D_XR::Load()
	{
		for (RenderPath3D& eye : eyes)
		{
			eye.Load();
		}
	}
	void RenderPath3D_XR::Start()
	{
		UpdateEyeResolution();
		for (RenderPath3D& eye : eyes)
		{
			eye.Start();
		}
	}
	void RenderPath3D_XR::Stop()
	{
		for (RenderPath3D& eye : eyes)
		{
			eye.Stop();
		}
	}
	void RenderPath3D_XR::PreUpdate()
	{
		// Single pass stereo rendering: the first eye renders the scene for both eyes at once if the graphics device supports it
		eyes[0].SetStereoSecondary(single_pass_stereo ? &eyes[1] : nullptr);
		const int stereo_mode = eyes[0].IsStereoPrimary() ? 1 : 0;
		if (stereo_mode != logged_stereo_mode)
		{
			logged_stereo_mode = stereo_mode;
			wilog("[wi::xr] stereo rendering: %s", stereo_mode ? "single pass for both eyes" : "one pass per eye");
		}
		UpdateEyeResolution();
		for (RenderPath3D& eye : eyes)
		{
			eye.PreUpdate();
		}
	}
	void RenderPath3D_XR::FixedUpdate()
	{
		for (RenderPath3D& eye : eyes)
		{
			eye.FixedUpdate();
		}
	}
	void RenderPath3D_XR::Update(float dt)
	{
		UpdateCameras();
		for (RenderPath3D& eye : eyes)
		{
			eye.Update(dt);
		}
	}
	void RenderPath3D_XR::PostUpdate()
	{
		for (RenderPath3D& eye : eyes)
		{
			eye.PostUpdate();
		}
	}
	void RenderPath3D_XR::PreRender()
	{
		for (RenderPath3D& eye : eyes)
		{
			eye.PreRender();
		}
	}
	void RenderPath3D_XR::Render() const
	{
		for (const RenderPath3D& eye : eyes)
		{
			eye.Render();
		}

		// Copy the results into the headset's swapchain, every eye has its own array slice:
		const Texture* swapchain_texture = wi::xr::GetSwapchainTexture();
		if (swapchain_texture == nullptr)
			return;

		GraphicsDevice* device = GetDevice();
		CommandList cmd = device->BeginCommandList();
		device->EventBegin("RenderPath3D_XR::SubmitEyes", cmd);

		const TextureDesc& desc = swapchain_texture->GetDesc();
		Viewport viewport;
		viewport.width = (float)desc.width;
		viewport.height = (float)desc.height;

		wi::image::Params fx;
		fx.blendFlag = wi::enums::BLENDMODE_OPAQUE;
		fx.quality = wi::image::QUALITY_LINEAR;
		fx.enableFullScreen();
		if (IsFormatSRGB(desc.format))
		{
			// The render result is in SRGB color space, but the SRGB swapchain format expects linear colors to be written:
			fx.enableLinearOutputMapping(1.0f);
		}

		for (uint32_t i = 0; i < arraysize(eyes); ++i)
		{
			const RenderPassImage rp[] = {
				RenderPassImage::RenderTarget(
					swapchain_texture,
					RenderPassImage::LoadOp::DONTCARE,
					RenderPassImage::StoreOp::STORE,
					desc.layout,
					desc.layout,
					(int)i // subresource index is the eye index
				),
			};
			device->RenderPassBegin(rp, arraysize(rp), cmd);
			device->BindViewports(1, &viewport, cmd);
			wi::image::Draw(&eyes[i].GetRenderResult3D(), fx, cmd);
			device->RenderPassEnd(cmd);
		}

		device->EventEnd(cmd);
	}
	void RenderPath3D_XR::PostRender()
	{
		for (RenderPath3D& eye : eyes)
		{
			eye.PostRender();
		}
	}
	void RenderPath3D_XR::Compose(CommandList cmd) const
	{
		if (!wi::xr::IsSessionRunning())
		{
			// Without a headset, both eyes are shown side by side:
			wi::image::SetCanvas(*this);
			for (uint32_t i = 0; i < arraysize(eyes); ++i)
			{
				wi::image::Params fx;
				fx.blendFlag = wi::enums::BLENDMODE_OPAQUE;
				fx.quality = wi::image::QUALITY_LINEAR;
				fx.siz = XMFLOAT2(GetLogicalWidth() / float(arraysize(eyes)), GetLogicalHeight());
				fx.pos = XMFLOAT3(fx.siz.x * float(i), 0, 0);
				wi::image::Draw(&eyes[i].GetRenderResult3D(), fx, cmd);
			}
			return;
		}

		// Desktop mirror:
		const RenderPath3D& eye = eyes[std::min(mirror_eye, (uint32_t)arraysize(eyes) - 1)];
		wi::image::Params fx;
		fx.blendFlag = wi::enums::BLENDMODE_OPAQUE;
		fx.quality = wi::image::QUALITY_LINEAR;
		fx.enableFullScreen();
		wi::image::Draw(&eye.GetRenderResult3D(), fx, cmd);
	}
}
