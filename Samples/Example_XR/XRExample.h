#pragma once
#include "WickedEngine.h"

// A minimal virtual reality application:
//	- renders a small scene to the headset with wi::RenderPath3D_XR
//	- shows the controllers as cubes
//	- the left thumbstick moves the player, the triggers make the controllers vibrate
class XRExample : public wi::Application
{
public:
	XRExample()
	{
		xr_requested = true;
	}

	void Update(float dt) override
	{
		wi::scene::Scene& scene = wi::scene::GetScene();

		if (!scene_created)
		{
			// Update() is called for the first time when the engine initialization was finished, so resources can be created here:
			scene_created = true;
			CreateScene(scene);
			if (wi::arguments::HasArgument("multipass"))
			{
				// The eyes are rendered one after the other instead of in a single pass, this is slower but can be used for comparison:
				path.single_pass_stereo = false;
			}
			path.SetScene(&scene);
			ActivatePath(&path);
		}

		// Move the player (the tracking origin) on the ground with the left thumbstick, relative to the view direction:
		const wi::xr::ControllerState& left = wi::xr::GetControllerState(wi::xr::Hand::Left);
		const wi::xr::ControllerState& right = wi::xr::GetControllerState(wi::xr::Hand::Right);
		const XMVECTOR head_forward = XMVector3Rotate(XMVectorSet(0, 0, 1, 0), XMLoadFloat4(&wi::xr::GetHeadPose().orientation));
		const float heading = std::atan2(XMVectorGetX(head_forward), XMVectorGetZ(head_forward));
		const XMVECTOR movement = XMVector3Rotate(
			XMVectorSet(left.thumbstick.x, 0, left.thumbstick.y, 0) * move_speed * dt,
			XMQuaternionRotationRollPitchYaw(0, heading, 0)
		);
		XMStoreFloat3(&player_position, XMLoadFloat3(&player_position) + movement);
		wi::xr::SetTrackingOrigin(XMMatrixTranslationFromVector(XMLoadFloat3(&player_position)));

		// Visualize the controllers and give haptic feedback for the triggers:
		UpdateController(scene, controller_entities[0], left, wi::xr::Hand::Left);
		UpdateController(scene, controller_entities[1], right, wi::xr::Hand::Right);

		wi::Application::Update(dt);
	}

	wi::RenderPath3D_XR path;

private:
	bool scene_created = false;
	wi::ecs::Entity controller_entities[2] = { wi::ecs::INVALID_ENTITY, wi::ecs::INVALID_ENTITY };
	XMFLOAT3 player_position = XMFLOAT3(0, 0, 0);
	float move_speed = 2.0f; // meters per second

	wi::ecs::Entity CreateBox(wi::scene::Scene& scene, const char* name, const XMFLOAT3& position, const XMFLOAT3& scale, const XMFLOAT4& color)
	{
		const wi::ecs::Entity entity = scene.Entity_CreateCube(name);
		wi::scene::TransformComponent& transform = *scene.transforms.GetComponent(entity);
		transform.Scale(scale);
		transform.Translate(position);
		transform.UpdateTransform();
		wi::scene::MaterialComponent& material = *scene.materials.GetComponent(entity);
		material.SetBaseColor(color);
		return entity;
	}

	void CreateScene(wi::scene::Scene& scene)
	{
		scene.weather = {};
		scene.weather.ambient = XMFLOAT3(0.3f, 0.3f, 0.35f);
		scene.weather.horizon = XMFLOAT3(0.4f, 0.5f, 0.7f);
		scene.weather.zenith = XMFLOAT3(0.1f, 0.2f, 0.5f);

		const wi::ecs::Entity sun = scene.Entity_CreateLight("sun", XMFLOAT3(0, 10, 0), XMFLOAT3(1, 0.95f, 0.9f), 8, 100, wi::scene::LightComponent::DIRECTIONAL);
		wi::scene::TransformComponent& sun_transform = *scene.transforms.GetComponent(sun);
		sun_transform.RotateRollPitchYaw(XMFLOAT3(XM_PIDIV4, XM_PIDIV4 * 0.5f, 0));
		scene.lights.GetComponent(sun)->SetCastShadow(true);

		// Floor (the top is at height 0, that is the floor of the play area):
		CreateBox(scene, "floor", XMFLOAT3(0, -0.1f, 0), XMFLOAT3(10, 0.1f, 10), XMFLOAT4(0.5f, 0.5f, 0.5f, 1));

		// Some objects around the player to have a reference for depth perception:
		const XMFLOAT4 colors[] = {
			XMFLOAT4(0.9f, 0.2f, 0.2f, 1),
			XMFLOAT4(0.2f, 0.9f, 0.2f, 1),
			XMFLOAT4(0.2f, 0.3f, 0.9f, 1),
			XMFLOAT4(0.9f, 0.8f, 0.2f, 1),
		};
		const int count = 8;
		for (int i = 0; i < count; ++i)
		{
			const float angle = XM_2PI * float(i) / float(count);
			const XMFLOAT3 position = XMFLOAT3(std::sin(angle) * 2.5f, 0.75f + 0.25f * float(i % 3), std::cos(angle) * 2.5f);
			CreateBox(scene, "box", position, XMFLOAT3(0.25f, 0.25f, 0.25f), colors[i % arraysize(colors)]);
		}

		controller_entities[0] = CreateBox(scene, "controller_left", XMFLOAT3(0, -10, 0), XMFLOAT3(1, 1, 1), XMFLOAT4(1, 1, 1, 1));
		controller_entities[1] = CreateBox(scene, "controller_right", XMFLOAT3(0, -10, 0), XMFLOAT3(1, 1, 1), XMFLOAT4(1, 1, 1, 1));
	}

	void UpdateController(wi::scene::Scene& scene, wi::ecs::Entity entity, const wi::xr::ControllerState& controller, wi::xr::Hand hand)
	{
		wi::scene::TransformComponent* transform = scene.transforms.GetComponent(entity);
		if (transform == nullptr || !controller.grip.valid)
			return;
		transform->ClearTransform();
		transform->Scale(XMFLOAT3(0.03f, 0.03f, 0.08f));
		transform->Rotate(controller.grip.orientation);
		transform->Translate(controller.grip.position);
		transform->UpdateTransform();

		if (controller.trigger > 0.1f)
		{
			wi::xr::Vibrate(hand, controller.trigger, 0.05f);
		}
	}
};
