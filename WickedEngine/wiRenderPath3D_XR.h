#pragma once
#include "wiRenderPath3D.h"
#include "wiXR.h"

namespace wi
{
	// Renders a scene for a head mounted display with the wi::xr system
	//	Every eye has its own RenderPath3D, so every rendering feature can be configured like with a regular RenderPath3D
	//	The cameras of the eyes are driven by head tracking, the player can be moved with wi::xr::SetTrackingOrigin()
	//	The desktop window shows a mirror image of one eye
	class RenderPath3D_XR : public RenderPath
	{
	public:
		RenderPath3D_XR();

		// The render paths of the eyes can be accessed to change rendering settings:
		RenderPath3D eyes[wi::xr::EYE_COUNT];
		wi::scene::CameraComponent cameras[wi::xr::EYE_COUNT];

		// Calls a function for the render path of every eye, to apply the same settings for both. Example:
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
		void UpdateEyeResolution();
		void UpdateCameras();
	};
}
