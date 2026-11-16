#pragma once
#include "wiRenderPath3D.h"
#include "wiXR.h"

namespace wi
{
	// Renders a scene for a head mounted display with the wi::xr system
	//	Every eye has its own RenderPath3D, so every rendering feature can be configured like with a regular RenderPath3D
	//	The eyes are linked for single pass stereo rendering (see RenderPath3D::SetStereoSecondary()), so they must have the same settings
	//	That means the geometry is rendered only once for both eyes, and culling, shadow maps etc. are shared
	//	The cameras of the eyes are driven by head tracking, the player can be moved with wi::xr::SetTrackingOrigin()
	//	The desktop window shows a mirror image of one eye, or both eyes side by side when there is no headset
	class RenderPath3D_XR : public RenderPath
	{
	public:
		RenderPath3D_XR();

		// The render paths of the eyes can be accessed to change rendering settings:
		RenderPath3D eyes[wi::xr::EYE_COUNT];
		wi::scene::CameraComponent cameras[wi::xr::EYE_COUNT];
		wi::scene::CameraComponent culling_camera; // contains the view of both eyes, used for culling and shadow cascades

		// Calls a function for the render path of every eye, to apply the same settings for both
		//	Note: the same settings must be applied to both eyes
		//	Note: occlusion culling must stay disabled for eyes[1], because the occlusion queries of the scene can only be used by one render path
		//	Example:
		//	path.ForEachEye([](wi::RenderPath3D& eye) { eye.setBloomEnabled(false); });
		template<typename Func>
		void ForEachEye(Func&& func)
		{
			for (RenderPath3D& eye : eyes)
			{
				func(eye);
			}
		}

		void SetScene(wi::scene::Scene* scene);
		wi::scene::Scene* GetScene() const { return eyes[0].scene; }

		float znear = 0.1f;
		float zfar = 5000.0f;

		// Used when no headset is available, then a standing player is simulated:
		float fallback_eye_height = 1.7f; // meters
		float fallback_fov = XM_PI / 3.0f; // vertical field of view in radians

		// Single pass stereo rendering: the geometry is rendered only once for both eyes, and culling, shadow maps etc. are shared
		//	If this is disabled or not supported by the graphics device, the eyes are rendered completely one after the other
		bool single_pass_stereo = true;

		// Which eye is shown in the desktop window:
		uint32_t mirror_eye = 0;

		void Load() override;
		void Start() override;
		void Stop() override;
		void PreUpdate() override;
		void FixedUpdate() override;
		void Update(float dt) override;
		void PostUpdate() override;
		void PreRender() override;
		void Render() const override;
		void PostRender() override;
		void Compose(wi::graphics::CommandList cmd) const override;

	private:
		int logged_stereo_mode = -1;
		void UpdateEyeResolution();
		void UpdateCameras();
	};
}
