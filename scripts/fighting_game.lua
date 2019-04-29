-- Lua Fighting game sample script
--
-- README:
--
-- Structure of this script:
--	
--	**) Character "class"	- holds all character specific information, like hitboxes, moves, state machine, and Update(), Input() functions
--	***) ResolveCharacters() function	- updates the two players and checks for collision, moves the camera, etc.
--	****) Main loop process	- initialize script and do call update() in an infinite loop
--
--
-- The script is programmable using common fighting game "numpad notations" (read this if you are unfamiliar: http://www.dustloop.com/wiki/index.php/Notation )
-- There are four action buttons: A, B, C, D
--	So for example a forward motion combined with action D would look like this in code: "6D" 
--	A D action without motion (neutral D) would be: "5D"
--	A quarter circle forward + A would be "236A"
--	"Shoryuken" + A command would be: "623A"
--	For a full circle motion, the input would be: "23698741"
--		But because that full circle motion is difficult to execute properly, we can make it easier by accpeting similar inputs, like:
--			"2684" or "2369874"...
--	The require_input("inputstring") facility will help detect instant input execution
--	The require_input_window("inputstring", allowed_latency_window) facility can detect inputs that are executed over multiple frames
--	Neutral motion is "5", that is not necessary to put into input strings in most cases, but it can help, for example: double tap right button would need a neutral in between the two presses, like this: 656

local scene = GetScene()

-- **The character "class" is a wrapper function that returns a local internal table called "self"
local function Character(face, shirt_color)
	local self = {
		model = INVALID_ENTITY,
		effect_dust = INVALID_ENTITY,
		effect_hit = INVALID_ENTITY,
		effect_guard = INVALID_ENTITY,
		effect_spark = INVALID_ENTITY,
		face = 1, -- face direction (X)
		request_face = 1, -- the suggested facing of this player, it might not be the actual facing if the player haven't been able to turn yet (for example an other action hasn't finished yet)
		position = Vector(), -- the absolute position of this player in the world, a 2D Vector
		velocity = Vector(), -- velocity will affect position
		force = Vector(), -- force will affect velocity
		frame = 0, -- the current animation's elapsed frames starting from 0
		input_buffer = {}, -- list of input history
		clipbox = AABB(), -- AABB that makes the two players not clip into each other
		hurtboxes = {}, -- list of AABBs that the opponent can hit with a hitbox
		hitboxes = {}, -- list of AABBs that can hit the opponent's hurtboxes
		guardboxes = {}, -- list of AABBs that can indicate to the opponent that guarding can be started
		hitconfirm = false, -- will be true in this frame if this player hit the opponent
		hurt = false, -- will be true in a frame if this player was hit by the opponent
		jumps_remaining = 2, -- for double jump
		push = Vector(), -- will affect opponent's velocity
		can_guard = false, -- true when player is inside opponent's guard box and can initiate guarding state
		guarding = false, -- if true, player can't be hit
		hit_guard = false, -- true when opponent is guarding the attack

		-- Effect helpers:
		spawn_effect_hit = function(self, local_pos)

			-- depending on if the attack is guarded or not, we will spawn different effects:
			local emitter_entity = INVALID_ENTITY
			local burst_count = 0
			local spark_color = Vector()
			if(self.hit_guard) then
				emitter_entity = self.effect_guard
				burst_count = 4
				spark_color = Vector(0,0.5,1,1)
			else
				emitter_entity = self.effect_hit
				burst_count = 50
				spark_color = Vector(1,0.5,0,1)
			end

			scene.Component_GetEmitter(emitter_entity).Burst(burst_count)
			local transform_component = scene.Component_GetTransform(emitter_entity)
			transform_component.ClearTransform()
			transform_component.Translate(vector.Add(self.position, local_pos))

			scene.Component_GetEmitter(self.effect_spark).Burst(4)
			transform_component = scene.Component_GetTransform(self.effect_spark)
			transform_component.ClearTransform()
			transform_component.Translate(vector.Add(self.position, local_pos))
			local material_component_spark = scene.Component_GetMaterial(self.effect_spark)
			material_component_spark.SetBaseColor(spark_color)

			runProcess(function() -- this sub-process will spawn a light, wait a bit then remove it
				local entity = CreateEntity()
				local light_transform = scene.Component_CreateTransform(entity)
				light_transform.Translate(vector.Add(self.position, local_pos))
				local light_component = scene.Component_CreateLight(entity)
				light_component.SetType(POINT)
				light_component.SetRange(8)
				light_component.SetEnergy(4)
				if(self.hit_guard) then
					light_component.SetColor(Vector(0,0.5,1)) -- guarded attack emits blueish light
				else
					light_component.SetColor(Vector(1,0.5,0)) -- successful attack emits orangeish light
				end
				light_component.SetCastShadow(false)
				waitSeconds(0.1)
				scene.Entity_Remove(entity)
			end)
		end,
		spawn_effect_dust = function(self, local_pos)
			local emitter_component = scene.Component_GetEmitter(self.effect_dust).Burst(10)
			local transform_component = scene.Component_GetTransform(self.effect_dust)
			transform_component.ClearTransform()
			transform_component.Translate(self.position)
		end,

		-- Common requirement conditions for state transitions:
		require_input_window = function(self, inputString, window) -- player input notation with some tolerance to input execution window (in frames) (help: see readme on top of this file)
			-- reduce remaining input with non-expired commands:
			for i,element in ipairs(self.input_buffer) do
				if(element.age <= window and element.command == string.sub(inputString, 0, string.len(element.command))) then
					inputString = string.sub(inputString, string.len(element.command) + 1)
					if(inputString == "") then
						return true
					end
				end
			end
			return false -- match failure
		end,
		require_input = function(self, inputString) -- player input notation (immediate) (help: see readme on top of this file)
			return self:require_input_window(inputString, 0)
		end,
		require_frame = function(self, frame) -- specific frame
			return self.frame == frame
		end,
		require_window = function(self, frameStart,  frameEnd) -- frame window range
			return self.frame >= frameStart and self.frame <= frameEnd
		end,
		require_animationfinish = function(self) -- animation is finished
			return scene.Component_GetAnimation(self.states[self.state].anim).IsEnded()
		end,
		require_hitconfirm = function(self) -- true if this player hit the other
			return self.hitconfirm
		end,
		require_hitconfirm_guard = function(self) -- true if this player hit the opponent but the opponent guarded it
			return self.hitconfirm and self.hit_guard
		end,
		require_hurt = function(self) -- true if this player was hit by the other
			return self.hurt
		end,
		require_guard = function(self) -- true if player can start guarding
			return self.can_guard
		end,
		
		-- Common motion helpers:
		require_motion_qcf = function(self, button)
			local window = 20
			return 
				self:require_input_window("236" .. button, window) or
				self:require_input_window("26" .. button, window)
		end,
		require_motion_shoryuken = function(self, button)
			local window = 20
			return 
				self:require_input_window("623" .. button, window) or
				self:require_input_window("626" .. button, window)
		end,

		-- List all possible states:
		states = {
			-- Common states:
			--	anim_name			: name of the animation track in the model file
			--	anim				: this will be initialized automatically to animation entity reference if the animation track is found by name
			--	clipbox				: (optional) AABB that describes the clip area for the character in this state. Characters can not clip into each other's clip area
			--	hurtbox				: (optional) AABB that describes the area the character can be hit/hurt
			--	update_collision	: (optional) this function will be executed in the continuous collision detection phase, multiple times per frame. Describe the hitboxes here
			--	update				: (optional) this function will be executed once every frame
			Idle = {
				anim_name = "Idle",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					self.jumps_remaining = 2
				end,
			},
			Walk_Backward = {
				anim_name = "Back",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					self.force = vector.Add(self.force, Vector(-0.025 * self.face, 0))
				end,
			},
			Walk_Forward = {
				anim_name = "Forward",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					self.force = vector.Add(self.force, Vector(0.025 * self.face, 0))
				end,
			},
			Dash_Backward = {
				anim_name = "BDash",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_window(0,2)) then
						self.force = vector.Add(self.force, Vector(-0.07 * self.face, 0.1))
					end
					if(self:require_frame(14)) then
						self:spawn_effect_dust(Vector())
					end
				end,
			},
			RunStart = {
				anim_name = "RunStart",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-0.5), Vector(2, 5)),
				hurtbox = AABB(Vector(-0.7), Vector(2.2, 5.5)),
			},
			Run = {
				anim_name = "Run",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-0.5), Vector(2, 5)),
				hurtbox = AABB(Vector(-0.7), Vector(2.2, 5.5)),
				update = function(self)
					self.force = vector.Add(self.force, Vector(0.08 * self.face, 0))
					if(self.frame % 15 == 0) then
						self:spawn_effect_dust(Vector())
					end
				end,
			},
			RunEnd = {
				anim_name = "RunEnd",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-0.5), Vector(2, 5)),
				hurtbox = AABB(Vector(-0.7), Vector(2.2, 5.5)),
			},
			Jump = {
				anim_name = "Jump",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.frame == 0) then
						self.jumps_remaining = self.jumps_remaining - 1
						self.velocity.SetY(0)
						self.force = vector.Add(self.force, Vector(0, 0.8))
						if(self.position.GetY() == 0) then
							self:spawn_effect_dust(Vector())
						end
					end
				end,
			},
			JumpBack = {
				anim_name = "Jump",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.frame == 0) then
						self.jumps_remaining = self.jumps_remaining - 1
						self.velocity.SetY(0)
						self.force = vector.Add(self.force, Vector(-0.2 * self.face, 0.8))
						if(self.position.GetY() == 0) then
							self:spawn_effect_dust(Vector())
						end
					end
				end,
			},
			JumpForward = {
				anim_name = "Jump",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.frame == 0) then
						self.jumps_remaining = self.jumps_remaining - 1
						self.velocity.SetY(0)
						self.force = vector.Add(self.force, Vector(0.2 * self.face, 0.8))
						if(self.position.GetY() == 0) then
							self:spawn_effect_dust(Vector())
						end
					end
				end,
			},
			FallStart = {
				anim_name = "FallStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			Fall = {
				anim_name = "Fall",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			FallEnd = {
				anim_name = "FallEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self:require_frame(2)) then
						self:spawn_effect_dust(Vector())
					end
				end,
			},
			CrouchStart = {
				anim_name = "CrouchStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 3)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 3.5)),
			},
			Crouch = {
				anim_name = "Crouch",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 3)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 3.5)),
			},
			CrouchEnd = {
				anim_name = "CrouchEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			Turn = {
				anim_name = "Turn",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.frame == 0) then
						self.face = self.request_face
					end
				end,
			},
			Guard = {
				anim_name = "Block",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					self.guarding = true
				end,
			},
			LowGuard = {
				anim_name = "LowBlock",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 3)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 3.5)),
				update = function(self)
					self.guarding = true
				end,
			},
			
			-- Attack states:
			LightPunch = {
				anim_name = "LightPunch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,0),Vector(6,8)),
				update_collision = function(self)
					if(self:require_window(3,6)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,2), Vector(3,5)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
						self.push = Vector(0.1 * self.face)
					end
				end,
			},
			ForwardLightPunch = {
				anim_name = "FLightPunch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,0),Vector(6,8)),
				update_collision = function(self)
					if(self:require_window(12,14)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,2), Vector(3.5,6)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
						self.push = Vector(0.12 * self.face)
					end
				end,
			},
			HeavyPunch = {
				anim_name = "HeavyPunch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,0),Vector(8,10)),
				update_collision = function(self)
					if(self:require_window(3,6)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,2), Vector(3.5,5)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
						self.push = Vector(0.2 * self.face)
					end
				end,
			},
			LowPunch = {
				anim_name = "LowPunch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 3)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 3.5)),
				guardbox = AABB(Vector(-2,0),Vector(6,4)),
				update_collision = function(self)
					if(self:require_window(3,6)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,0), Vector(2.8,3)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,2,-1))
						self.push = Vector(0.1 * self.face)
					end
				end,
			},
			LightKick = {
				anim_name = "LightKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,0),Vector(6,8)),
				update_collision = function(self)
					if(self:require_window(6,8)) then
						table.insert(self.hitboxes, AABB(Vector(0,0), Vector(3,3)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2 * self.face,2,-1))
						self.push = Vector(0.1 * self.face)
					end
				end,
			},
			HeavyKick = {
				anim_name = "HeavyKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,0),Vector(6,8)),
				update_collision = function(self)
					if(self:require_window(8,13)) then
						table.insert(self.hitboxes, AABB(Vector(0,0), Vector(4,3)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.6 * self.face,1.4,-1))
						self.push = Vector(0.15 * self.face)
					end
				end,
			},
			AirKick = {
				anim_name = "AirKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,-6),Vector(6,8)),
				update_collision = function(self)
					if(self:require_window(6,8)) then
						table.insert(self.hitboxes, AABB(Vector(0,0), Vector(3,3)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2 * self.face,2,-1))
						self.push = Vector(0.2 * self.face)
					end
				end,
			},
			AirHeavyKick = {
				anim_name = "AirHeavyKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,-6),Vector(6,8)),
				update_collision = function(self)
					if(self:require_window(6,8)) then
						table.insert(self.hitboxes, AABB(Vector(0,0), Vector(3,3)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2 * self.face,2,-1))
						self.push = Vector(0.25 * self.face)
					end
				end,
			},
			LowKick = {
				anim_name = "LowKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 3)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 3.5)),
				guardbox = AABB(Vector(-2,0),Vector(6,4)),
				update_collision = function(self)
					if(self:require_window(3,6)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,0), Vector(3,3)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2 * self.face,1,-1))
						self.push = Vector(0.1 * self.face)
					end
				end,
			},
			ChargeKick = {
				anim_name = "ChargeKick",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(0), Vector(2, 5)),
				hurtbox = AABB(Vector(0), Vector(2.2, 5.5)),
				guardbox = AABB(Vector(-2,0),Vector(16,8)),
				update_collision = function(self)
					if(self:require_window(11,41)) then
						table.insert(self.hitboxes, AABB(Vector(0.5,0), Vector(5.6,3)) )
					end
				end,
				update = function(self)
					if(self:require_frame(4)) then
						self.force = vector.Add(self.force, Vector(0.9 * self.face))
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(5 * self.face,3,-1))
						if(self:require_hitconfirm_guard()) then
							self.push = Vector(0.8 * self.face, 0)
						else
							self.push = Vector(0.8 * self.face, 0.2)
						end
					end
				end,
			},
			Uppercut = {
				anim_name = "Uppercut",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,0),Vector(6,8)),
				update_collision = function(self)
					if(self:require_window(3,5)) then
						table.insert(self.hitboxes, AABB(Vector(0,3), Vector(2.3,7)) )
					end
				end,
				update = function(self)
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
						if(self:require_hitconfirm_guard()) then
							self.push = Vector(0.1 * self.face, 0) -- if guarded, don't push opponent up
						else
							self.push = Vector(0.1 * self.face, 0.5) -- if not guarded, push opponent up
						end
					end
				end,
			},
			SpearJaunt = {
				anim_name = "SpearJaunt",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1.5), Vector(1.5, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,0),Vector(16,8)),
				update_collision = function(self)
					if(self:require_window(17,40)) then
						table.insert(self.hitboxes, AABB(Vector(0,1), Vector(4.5,5)) )
					end
				end,
				update = function(self)
					if(self:require_frame(16)) then
						self.force = vector.Add(self.force, Vector(1.3 * self.face))
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(3 * self.face,3.6,-1))
						self.push = Vector(0.3 * self.face)
					end
				end,
			},
			Shoryuken = {
				anim_name = "Shoryuken",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				guardbox = AABB(Vector(-2,0),Vector(8,15)),
				update_collision = function(self)
					if(self:require_window(2,20)) then
						table.insert(self.hitboxes, AABB(Vector(0,2), Vector(2.3,7)) )
					end
				end,
				update = function(self)
					if(self:require_frame(0)) then
						self.force = vector.Add(self.force, Vector(0.3 * self.face, 0.9))
					end
					if(self:require_hitconfirm()) then
						self:spawn_effect_hit(Vector(2.5 * self.face,4,-1))
						if(self:require_window(2,3) and not self:require_hitconfirm_guard()) then
							self.push = Vector(0, 1)
						end
					end
				end,
			},
			
			-- Hurt states:
			StaggerStart = {
				anim_name = "StaggerStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			Stagger = {
				anim_name = "Stagger",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerEnd = {
				anim_name = "StaggerEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},

			StaggerCrouchStart = {
				anim_name = "StaggerCrouchStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerCrouch = {
				anim_name = "StaggerCrouch",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerCrouchEnd = {
				anim_name = "StaggerCrouchEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},

			StaggerAirStart = {
				anim_name = "StaggerAirStart",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerAir = {
				anim_name = "StaggerAir",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
			StaggerAirEnd = {
				anim_name = "StaggerAirEnd",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
				update = function(self)
					if(self.position.GetY() < 1 and self.velocity.GetY() < 0) then
						self:spawn_effect_dust(Vector())
					end
				end,
			},
			
			Downed = {
				anim_name = "Downed",
				anim = INVALID_ENTITY,
				clipbox = AABB(Vector(-1), Vector(1, 1)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 1)),
			},
			Getup = {
				anim_name = "Getup",
				anim = INVALID_ENTITY,
				looped = false,
				clipbox = AABB(Vector(-1), Vector(1, 5)),
				hurtbox = AABB(Vector(-1.2), Vector(1.2, 5.5)),
			},
		},

		-- State machine describes all possible state transitions (item order is priority high->low):
		--	StateFrom = {
		--		{ "StateTo1", condition = function(self) return [requirements that should be met] end },
		--		{ "StateTo2", condition = function(self) return [requirements that should be met] end },
		--	}
		statemachine = {
			Idle = { 
				{ "Guard", condition = function(self) return self:require_guard() and self:require_input("4") end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Shoryuken", condition = function(self) return self:require_motion_shoryuken("D") end, },
				{ "SpearJaunt", condition = function(self) return self:require_motion_qcf("D") end, },
				{ "Turn", condition = function(self) return self.request_face ~= self.face end, },
				{ "Walk_Forward", condition = function(self) return self:require_input("6") end, },
				{ "Walk_Backward", condition = function(self) return self:require_input("4") end, },
				{ "Jump", condition = function(self) return self:require_input("8") end, },
				{ "JumpBack", condition = function(self) return self:require_input("7") end, },
				{ "JumpForward", condition = function(self) return self:require_input("9") end, },
				{ "CrouchStart", condition = function(self) return self:require_input("1") or self:require_input("2") or self:require_input("3") end, },
				{ "ChargeKick", condition = function(self) return self:require_input_window("4444444444444444446C", 30) end, },
				{ "LightPunch", condition = function(self) return self:require_input("5A") end, },
				{ "HeavyPunch", condition = function(self) return self:require_input("5B") end, },
				{ "LightKick", condition = function(self) return self:require_input("5C") end, },
			},
			Walk_Backward = { 
				{ "Guard", condition = function(self) return self:require_guard() and self:require_input("4") end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Shoryuken", condition = function(self) return self:require_motion_shoryuken("D") end, },
				{ "CrouchStart", condition = function(self) return self:require_input("1") or self:require_input("2") or self:require_input("3") end, },
				{ "Walk_Forward", condition = function(self) return self:require_input("6") end, },
				{ "Dash_Backward", condition = function(self) return self:require_input_window("454", 7) end, },
				{ "JumpBack", condition = function(self) return self:require_input("7") end, },
				{ "Idle", condition = function(self) return self:require_input("5") end, },
				{ "ChargeKick", condition = function(self) return self:require_input_window("4444444444444444446C", 30) end, },
				{ "LightPunch", condition = function(self) return self:require_input("5A") end, },
				{ "HeavyPunch", condition = function(self) return self:require_input("5B") end, },
				{ "LightKick", condition = function(self) return self:require_input("5C") end, },
				{ "ForwardLightPunch", condition = function(self) return self:require_input("6A") end, },
				{ "HeavyKick", condition = function(self) return self:require_input("6C") end, },
			},
			Walk_Forward = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Shoryuken", condition = function(self) return self:require_motion_shoryuken("D") end, },
				{ "SpearJaunt", condition = function(self) return self:require_motion_qcf("D") end, },
				{ "CrouchStart", condition = function(self) return self:require_input("1") or self:require_input("2") or self:require_input("3") end, },
				{ "Walk_Backward", condition = function(self) return self:require_input("4") end, },
				{ "RunStart", condition = function(self) return self:require_input_window("656", 7) end, },
				{ "JumpForward", condition = function(self) return self:require_input("9") end, },
				{ "Idle", condition = function(self) return self:require_input("5") end, },
				{ "ChargeKick", condition = function(self) return self:require_input_window("4444444444444444446C", 30) end, },
				{ "LightPunch", condition = function(self) return self:require_input("5A") end, },
				{ "HeavyPunch", condition = function(self) return self:require_input("5B") end, },
				{ "LightKick", condition = function(self) return self:require_input("5C") end, },
				{ "ForwardLightPunch", condition = function(self) return self:require_input("6A") end, },
				{ "HeavyKick", condition = function(self) return self:require_input("6C") end, },
			},
			Dash_Backward = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			RunStart = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Run", condition = function(self) return self:require_animationfinish() end, },
			},
			Run = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Jump", condition = function(self) return self:require_input("8") end, },
				{ "JumpBack", condition = function(self) return self:require_input("7") end, },
				{ "JumpForward", condition = function(self) return self:require_input("9") end, },
				{ "RunEnd", condition = function(self) return not self:require_input("6") end, },
			},
			RunEnd = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			Jump = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
				{ "FallStart", condition = function(self) return self.velocity.GetY() <= 0 end, },
			},
			JumpForward = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
				{ "FallStart", condition = function(self) return self.velocity.GetY() <= 0 end, },
			},
			JumpBack = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
				{ "FallStart", condition = function(self) return self.velocity.GetY() <= 0 end, },
			},
			FallStart = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "FallEnd", condition = function(self) return self.position.GetY() <= 0.5 end, },
				{ "Fall", condition = function(self) return self:require_animationfinish() end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
			},
			Fall = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Jump", condition = function(self) return self.jumps_remaining > 0 and self:require_input_window("58", 7) end, },
				{ "JumpBack", condition = function(self) return self.jumps_remaining > 0 and self:require_input_window("57", 7) end, },
				{ "JumpForward", condition = function(self) return self.jumps_remaining > 0 and self:require_input_window("59", 7) end, },
				{ "FallEnd", condition = function(self) return self.position.GetY() <= 0.5 end, },
				{ "AirHeavyKick", condition = function(self) return self.position.GetY() > 4 and self:require_input("2C") end, },
				{ "AirKick", condition = function(self) return self.position.GetY() > 2 and self:require_input("C") end, },
			},
			FallEnd = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self.position.GetY() <= 0 and self:require_animationfinish() end, },
			},
			CrouchStart = { 
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_input("5") end, },
				{ "Crouch", condition = function(self) return (self:require_input("1") or self:require_input("2") or self:require_input("3")) and self:require_animationfinish() end, },
			},
			Crouch = { 
				{ "LowGuard", condition = function(self) return self:require_guard() and self:require_input("1") end, },
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "CrouchEnd", condition = function(self) return self:require_input("5") or self:require_input("4") or self:require_input("6") or self:require_input("7") or self:require_input("8") or self:require_input("9") end, },
				{ "LowPunch", condition = function(self) return self:require_input("2A") or self:require_input("1A") or self:require_input("3A") end, },
				{ "LowKick", condition = function(self) return self:require_input("2C") or self:require_input("1C") or self:require_input("3C") end, },
				{ "Uppercut", condition = function(self) return self:require_input("2B") or self:require_input("1B") or self:require_input("3B") end, },
			},
			CrouchEnd = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			Turn = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			Guard = { 
				{ "Idle", condition = function(self) return not self:require_input("4") end, },
			},
			LowGuard = { 
				{ "Crouch", condition = function(self) return not self:require_input("1") end, },
			},

			LightPunch = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			ForwardLightPunch = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			HeavyPunch = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			LowPunch = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Crouch", condition = function(self) return self:require_animationfinish() end, },
			},
			LightKick = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			HeavyKick = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			AirKick = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "Fall", condition = function(self) return self:require_animationfinish() end, },
			},
			AirHeavyKick = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "Fall", condition = function(self) return self:require_animationfinish() end, },
			},
			LowKick = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Crouch", condition = function(self) return self:require_animationfinish() end, },
			},
			ChargeKick = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			Uppercut = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			SpearJaunt = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			Shoryuken = { 
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "FallStart", condition = function(self) return self:require_animationfinish() end, },
			},
			
			StaggerStart = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Stagger", condition = function(self) return self:require_animationfinish() end, },
			},
			Stagger = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerEnd", condition = function(self) return not self:require_hurt() end, },
			},
			StaggerEnd = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerStart", condition = function(self) return self:require_hurt() end, },
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
			
			StaggerCrouchStart = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerCrouch", condition = function(self) return self:require_animationfinish() end, },
			},
			StaggerCrouch = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerCrouchEnd", condition = function(self) return not self:require_hurt() end, },
			},
			StaggerCrouchEnd = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() and self.position.GetY() > 0 end, },
				{ "StaggerCrouchStart", condition = function(self) return self:require_hurt() end, },
				{ "Crouch", condition = function(self) return self:require_animationfinish() end, },
			},
			
			StaggerAirStart = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerAir", condition = function(self) return self:require_animationfinish() end, },
			},
			StaggerAir = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "StaggerAirEnd", condition = function(self) return not self:require_hurt() end, },
			},
			StaggerAirEnd = { 
				{ "StaggerAirStart", condition = function(self) return self:require_hurt() end, },
				{ "Downed", condition = function(self) return self:require_animationfinish() and self.position.GetY() < 0.2 end, },
			},

			Downed = { 
				{ "Getup", condition = function(self) return self:require_input("A") or self:require_input("B") or self:require_input("C") or self.frame > 60 end, },
			},
			Getup = { 
				{ "Idle", condition = function(self) return self:require_animationfinish() end, },
			},
		},

		state = "Idle", -- starting state

	
		-- Ends the current state:
		EndState = function(self)
			scene.Component_GetAnimation(self.states[self.state].anim).Stop()
		end,
		-- Starts a new state:
		StartState = function(self, dst_state)
			scene.Component_GetAnimation(self.states[dst_state].anim).Play()
			self.frame = 0
			self.state = dst_state
		end,
		-- Step state machine and execute current state:
		ExecuteStateMachine = function(self)
			-- Parse state machine at current state and perform transition if applicable:
			local transition_candidates = self.statemachine[self.state]
			if(transition_candidates ~= nil) then
				for i,dst in pairs(transition_candidates) do
					-- check transition requirement conditions:
					local requirements_met = true
					if(dst.condition ~= nil) then
						requirements_met = dst.condition(self)
					end
					if(requirements_met) then
						-- transition to new state when all requirements are met:
						self:EndState()
						self:StartState(dst[1])
						break
					end
				end
			end

			-- Execute the currently active state:
			local current_state = self.states[self.state]
			if(current_state ~= nil) then
				if(current_state.update ~= nil) then
					current_state.update(self)
				end
			end

		end,
	

		Create = function(self, face, shirt_color)

			-- Load the model into a custom scene:
			--	We use a custom scene because if two models are loaded into the global scene, they will have name collisions
			--	and thus we couldn't properly query entities by name
			local model_scene = Scene()
			self.model = LoadModel(model_scene, "../models/havoc/havoc.wiscene")

			-- Place model according to starting facing direction:
			self.face = face
			self.request_face = face
			self.position = Vector(self.face * -4)

			-- Set shirt color todifferentiate between characters:
			local shirt_material_entity = model_scene.Entity_FindByName("material_shirt")
			model_scene.Component_GetMaterial(shirt_material_entity).SetBaseColor(shirt_color)
		
			-- Initialize states:
			for i,state in pairs(self.states) do
				state.anim = model_scene.Entity_FindByName(state.anim_name)
				if(state.looped ~= nil) then
					model_scene.Component_GetAnimation(state.anim).SetLooped(state.looped)
				end
			end

			-- Move the custom scene into the global scene:
			scene.Merge(model_scene)



			-- Load effects:
			local effect_scene = Scene()
			
			effect_scene.Clear()
			LoadModel(effect_scene, "../models/emitter_dust.wiscene")
			self.effect_dust = effect_scene.Entity_FindByName("dust")  -- query the emitter entity by name
			effect_scene.Component_GetEmitter(self.effect_dust).SetEmitCount(0)  -- don't emit continuously
			scene.Merge(effect_scene)

			effect_scene.Clear()
			LoadModel(effect_scene, "../models/emitter_hiteffect.wiscene")
			self.effect_hit = effect_scene.Entity_FindByName("hit")  -- query the emitter entity by name
			effect_scene.Component_GetEmitter(self.effect_hit).SetEmitCount(0)  -- don't emit continuously
			scene.Merge(effect_scene)

			effect_scene.Clear()
			LoadModel(effect_scene, "../models/emitter_guardeffect.wiscene")
			self.effect_guard = effect_scene.Entity_FindByName("guard")  -- query the emitter entity by name
			effect_scene.Component_GetEmitter(self.effect_guard).SetEmitCount(0)  -- don't emit continuously
			scene.Merge(effect_scene)

			effect_scene.Clear()
			LoadModel(effect_scene, "../models/emitter_spark.wiscene")
			self.effect_spark = effect_scene.Entity_FindByName("spark")  -- query the emitter entity by name
			effect_scene.Component_GetEmitter(self.effect_spark).SetEmitCount(0)  -- don't emit continuously
			scene.Merge(effect_scene)


			self:StartState(self.state)

		end,
	
		ai_state = "Idle",
		AI = function(self)
			-- todo some better AI bot behaviour
			if(self.ai_state == "Jump") then
				table.insert(self.input_buffer, {age = 0, command = "8"})
			elseif(self.ai_state == "Crouch") then
				table.insert(self.input_buffer, {age = 0, command = "2"})
			elseif(self.ai_state == "Guard" and self:require_guard()) then
				table.insert(self.input_buffer, {age = 0, command = "4"})
			else
				table.insert(self.input_buffer, {age = 0, command = "5"})
			end
		end,

		-- Read input and store in the buffer:
		Input = function(self)

			-- read input (todo gamepad/stick):
			local left = input.Down(string.byte('A'))
			local right = input.Down(string.byte('D'))
			local up = input.Down(string.byte('W'))
			local down = input.Down(string.byte('S'))
			local A = input.Press(VK_RIGHT)
			local B = input.Press(VK_UP)
			local C = input.Press(VK_LEFT)
			local D = input.Press(VK_DOWN)

			-- swap left and right if facing the opposite side:
			if(self.face < 0) then
				local tmp = right
				right = left
				left = tmp
			end

			if(up and left) then
				table.insert(self.input_buffer, {age = 0, command = "7"})
			elseif(up and right) then
				table.insert(self.input_buffer, {age = 0, command = "9"})
			elseif(up) then
				table.insert(self.input_buffer, {age = 0, command = "8"})
			elseif(down and left) then
				table.insert(self.input_buffer, {age = 0, command = "1"})
			elseif(down and right) then
				table.insert(self.input_buffer, {age = 0, command = "3"})
			elseif(down) then
				table.insert(self.input_buffer, {age = 0, command = "2"})
			elseif(left) then
				table.insert(self.input_buffer, {age = 0, command = "4"})
			elseif(right) then
				table.insert(self.input_buffer, {age = 0, command = "6"})
			else
				table.insert(self.input_buffer, {age = 0, command = "5"})
			end
			
			if(A) then
				table.insert(self.input_buffer, {age = 0, command = "A"})
			end
			if(B) then
				table.insert(self.input_buffer, {age = 0, command = "B"})
			end
			if(C) then
				table.insert(self.input_buffer, {age = 0, command = "C"})
			end
			if(D) then
				table.insert(self.input_buffer, {age = 0, command = "D"})
			end

		end,

		-- Update character state and forces once per frame:
		Update = function(self)
			self.frame = self.frame + 1
			self.guarding = false

			-- force from gravity:
			self.force = Vector(0,-0.04,0)

			self:ExecuteStateMachine()

			-- Manage input buffer:
			for i,element in pairs(self.input_buffer) do -- every input gets older by one frame
				element.age = element.age + 1
			end
			if(#self.input_buffer > 60) then -- only keep the last 60 inputs
				table.remove(self.input_buffer, 1)
			end

			-- apply force:
			self.velocity = vector.Add(self.velocity, self.force)

			-- aerial drag:
			self.velocity = vector.Multiply(self.velocity, 0.98)
		
		
			-- check if we are below or on the ground:
			if(self.position.GetY() <= 0 and self.velocity.GetY()<=0) then
				self.position.SetY(0) -- snap to ground
				self.velocity.SetY(0) -- don't fall below ground
				self.velocity = vector.Multiply(self.velocity, 0.86) -- ground drag
			end
		
		end,

		-- Updates the character bounding boxes that will be used for collision. This will be processed multiple times per frame:
		UpdateCollisionState = function(self, ccd_step)
		
			-- apply velocity:
			self.position = vector.Add(self.position, vector.Multiply(self.velocity, ccd_step))

			-- Reset collision boxes:
			self.clipbox = AABB()
			self.hurtboxes = {}
			self.hitboxes = {}
			self.guardboxes = {}
			
			-- Set collision boxes in local space:
			local current_state = self.states[self.state]
			if(current_state ~= nil) then
				if(current_state.update_collision ~= nil) then
					current_state.update_collision(self)
				end
				if(current_state.clipbox ~= nil) then
					self.clipbox = current_state.clipbox
				end
				if(current_state.hurtbox ~= nil) then
					table.insert(self.hurtboxes, current_state.hurtbox)
				end
				if(current_state.guardbox ~= nil) then
					table.insert(self.guardboxes, current_state.guardbox)
				end
			end
			
			-- Compute global transform for the model:
			local model_transform = scene.Component_GetTransform(self.model)
			model_transform.ClearTransform()
			model_transform.Translate(self.position)
			model_transform.Rotate(Vector(0, math.pi * ((self.face - 1) * 0.5)))
			model_transform.UpdateTransform()

			-- Update collision boxes with global model transform:
			local model_mat = model_transform.GetMatrix()
			self.clipbox = self.clipbox.Transform(model_mat)
			for i,hitbox in ipairs(self.hitboxes) do
				self.hitboxes[i] = hitbox.Transform(model_mat)
			end
			for i,hurtbox in ipairs(self.hurtboxes) do
				self.hurtboxes[i] = hurtbox.Transform(model_mat)
			end
			for i,guardbox in ipairs(self.guardboxes) do
				self.guardboxes[i] = guardbox.Transform(model_mat)
			end
		end,

		-- Draws the hitboxes, etc.
		DebugDraw = function(self)
			DrawPoint(self.position, 0.1, Vector(1,0,0,1))
			DrawLine(self.position,self.position:Add(self.velocity), Vector(0,1,0,10))
			DrawLine(vector.Add(self.position, Vector(0,1)),vector.Add(self.position, Vector(0,1)):Add(Vector(self.face)), Vector(0,0,1,1))
			DrawBox(self.clipbox.GetAsBoxMatrix(), Vector(1,1,0,1))
			for i,hitbox in ipairs(self.hitboxes) do
				DrawBox(self.hitboxes[i].GetAsBoxMatrix(), Vector(1,0,0,1))
			end
			for i,hurtbox in ipairs(self.hurtboxes) do
				DrawBox(self.hurtboxes[i].GetAsBoxMatrix(), Vector(0,1,0,1))
			end
			for i,guardbox in ipairs(self.guardboxes) do
				DrawBox(self.guardboxes[i].GetAsBoxMatrix(), Vector(0,0,1,1))
			end
		end,

	}

	self:Create(face, shirt_color)
	return self
end


-- script camera state:
local camera_position = Vector()
local camera_transform = TransformComponent()
local CAMERA_HEIGHT = 4 -- camera height from ground
local DEFAULT_CAMERADISTANCE = -9.5 -- the default camera distance when characters are close to each other
local MODIFIED_CAMERADISTANCE = -11.5 -- if the two players are far enough from each other, the camera will zoom out to this distance
local CAMERA_DISTANCE_MODIFIER = 10 -- the required distance between the characters when the camera should zoom out
local XBOUNDS = 20 -- play area horizontal bounds
local CAMERA_SIDE_LENGTH = 10 -- play area inside the camera (character can't move outside camera even if inside the play area)

-- ***Interaction between two characters:
local ResolveCharacters = function(player1, player2)
		
	player1:Input()
	player2:AI()

	player1:Update()
	player2:Update()

	-- Facing direction requests:
	if(player1.position.GetX() < player2.position.GetX()) then
		player1.request_face = 1
		player2.request_face = -1
	else
		player1.request_face = -1
		player2.request_face = 1
	end
	
	-- Camera bounds:
	local camera_side_left = camera_position.GetX() - CAMERA_SIDE_LENGTH
	local camera_side_right = camera_position.GetX() + CAMERA_SIDE_LENGTH

	-- Continuous collision detection will be iterated multiple times to avoid "bullet through paper problem":
	local iterations = 10
	local ccd_step = 1.0 / iterations
	for i=1,iterations, 1 do

		player1:UpdateCollisionState(ccd_step)
		player2:UpdateCollisionState(ccd_step)

		-- Hit/Hurt/Guard:
		player1.hitconfirm = false
		player1.hurt = false
		player1.hit_guard = false
		player2.hitconfirm = false
		player2.hurt = false
		player2.hit_guard = false
		-- player1 hits player2:
		for i,hitbox in pairs(player1.hitboxes) do
			for j,hurtbox in pairs(player2.hurtboxes) do
				if(hitbox.Intersects2D(hurtbox)) then
					player1.hitconfirm = true
					player2.hurt = true
					if(player2.guarding) then
						player1.hit_guard = true
					end
					break
				end
			end
		end
		-- player2 hits player1:
		for i,hitbox in ipairs(player2.hitboxes) do
			for j,hurtbox in ipairs(player1.hurtboxes) do
				if(hitbox.Intersects2D(hurtbox)) then
					player2.hitconfirm = true
					player1.hurt = true
					if(player1.guarding) then
						player2.hit_guard = true
					end
					break
				end
			end
		end

		player1.can_guard = false
		player2.can_guard = false
		-- player1 guardbox player2:
		for i,guardbox in pairs(player1.guardboxes) do
			for j,hurtbox in pairs(player2.hurtboxes) do
				if(guardbox.Intersects2D(hurtbox)) then
					player2.can_guard = true
					break
				end
			end
		end
		-- player2 guardbox player1:
		for i,guardbox in pairs(player2.guardboxes) do
			for j,hurtbox in pairs(player1.hurtboxes) do
				if(guardbox.Intersects2D(hurtbox)) then
					player1.can_guard = true
					break
				end
			end
		end

		-- Clipping:
		if(player1.clipbox.Intersects2D(player2.clipbox)) then
			local center1 = player1.clipbox.GetCenter().GetX()
			local center2 = player2.clipbox.GetCenter().GetX()
			local extent1 = player1.clipbox.GetHalfExtents().GetX()
			local extent2 = player2.clipbox.GetHalfExtents().GetX()
			local diff = math.abs(center2 - center1)
			local target_diff = math.abs(extent2 + extent1)
			local offset = (target_diff - diff) * 0.5
			offset = math.lerp( offset, math.min(offset, 0.3 * ccd_step), math.saturate(math.abs(player1.position.GetY() - player2.position.GetY())) ) -- smooth out clipping in mid-air
			player1.position.SetX(player1.position.GetX() - offset * player1.request_face)
			player2.position.SetX(player2.position.GetX() - offset * player2.request_face)
		end


		-- Clamp the players inside the camera:
		player1.position.SetX(math.clamp(player1.position.GetX(), camera_side_left, camera_side_right))
		player2.position.SetX(math.clamp(player2.position.GetX(), camera_side_left, camera_side_right))
	
		local camera_position_new = Vector()
		local distanceX = math.abs(player1.position.GetX() - player2.position.GetX())
		local distanceY = math.abs(player1.position.GetY() - player2.position.GetY())

		-- camera height:
		if(player1.position.GetY() > 4 or player2.position.GetY() > 4) then
			camera_position_new.SetY( math.min(player1.position.GetY(), player2.position.GetY()) + distanceY )
		else
			camera_position_new.SetY(CAMERA_HEIGHT)
		end

		-- camera distance:
		if(distanceX > CAMERA_DISTANCE_MODIFIER) then
			camera_position_new.SetZ(MODIFIED_CAMERADISTANCE)
		else
			camera_position_new.SetZ(DEFAULT_CAMERADISTANCE)
		end

		-- camera horizontal position:
		local centerX = math.clamp((player1.position.GetX() + player2.position.GetX()) * 0.5, -XBOUNDS, XBOUNDS)
		camera_position_new.SetX(centerX)

		-- smooth camera:
		camera_position = vector.Lerp(camera_position, camera_position_new, 0.1 * ccd_step)

	end

	-- Push:

	-- player on the edge of screen can initiate push transfer:
	--	it means that the player cannot be pushed further, so the opponent will be pushed back instead to compensate:
	if(player2.position.GetX() <= camera_side_left and player1.push.GetX() < 0) then
		player2.push.SetX(-player1.push.GetX())
	end
	if(player2.position.GetX() >= camera_side_right and player1.push.GetX() > 0) then
		player2.push.SetX(-player1.push.GetX())
	end
	if(player1.position.GetX() <= camera_side_left and player2.push.GetX() < 0) then
		player1.push.SetX(-player1.push.GetX())
	end
	if(player1.position.GetX() >= camera_side_right and player2.push.GetX() > 0) then
		player1.push.SetX(-player1.push.GetX())
	end

	-- apply push forces:
	if(player1.push.Length() > 0) then
		player2.velocity = player1.push
	end
	if(player2.push.Length() > 0) then
		player1.velocity = player2.push
	end

	-- reset push forces:
	player1.push = Vector()
	player2.push = Vector()

	-- Update collision state once more (but with ccd_step = 0) so that bounding boxes and system transform is up to date:
	player1:UpdateCollisionState(0)
	player2:UpdateCollisionState(0)

	-- Update the system global camera with current values:
	camera_transform.ClearTransform()
	camera_transform.Translate(camera_position)
	camera_transform.UpdateTransform()
	GetCamera().TransformCamera(camera_transform)

	player1:DebugDraw()
	player2:DebugDraw()

end

-- ****Main loop:
runProcess(function()

	ClearWorld() -- clears global scene and renderer
	SetProfilerEnabled(false) -- have a bit more screen space
	
	-- Fighting game needs stable frame rate and deterministic controls at all times. We will also refer to frames in this script instead of time units.
	--	We lock the framerate to 60 FPS, so if frame rate goes below, game will play slower
	--	
	--	There is also the possibility to implement game logic in fixed_update() instead, but that is not common for fighting games
	main.SetTargetFrameRate(60)
	main.SetFrameRateLock(true)

	-- We will override the render path so we can invoke the script from Editor and controls won't collide with editor scripts
	--	Also save the active component that we can restore when ESCAPE is pressed
	local prevPath = main.GetActivePath()
	local path = RenderPath3D_TiledForward()
	main.SetActivePath(path)

	local help_text = ""
	help_text = help_text .. "This script is showcasing how to write a simple fighting game."
	help_text = help_text .. "\nControls:\n#####################\nESCAPE key: quit\nR: reload script"
	help_text = help_text .. "\nWASD: move"
	help_text = help_text .. "\nRight: action A"
	help_text = help_text .. "\nUp: action B"
	help_text = help_text .. "\nLeft: action C"
	help_text = help_text .. "\nDown: action D"
	help_text = help_text .. "\nJ: player2 will always jump"
	help_text = help_text .. "\nC: player2 will always crouch"
	help_text = help_text .. "\nG: player2 will always guard"
	help_text = help_text .. "\nI: player2 will be idle"
	help_text = help_text .. "\n\nMovelist:"
	help_text = help_text .. "\n\t A : Light Punch"
	help_text = help_text .. "\n\t B : Heavy Punch"
	help_text = help_text .. "\n\t C : Light Kick"
	help_text = help_text .. "\n\t 6A : Forward Light Punch"
	help_text = help_text .. "\n\t 6C : Heavy Kick"
	help_text = help_text .. "\n\t 2A : Low Punch"
	help_text = help_text .. "\n\t 2B : Uppercut"
	help_text = help_text .. "\n\t 2C : Low Kick"
	help_text = help_text .. "\n\t 4(charge) 6C : Charge Kick"
	help_text = help_text .. "\n\t C : Air Kick (while jumping)"
	help_text = help_text .. "\n\t 2C : Air Heavy Kick (while jumping)"
	help_text = help_text .. "\n\t 623D: Shoryuken"
	help_text = help_text .. "\n\t 236D: Jaunt"
	local font = Font(help_text);
	font.SetSize(22)
	font.SetPos(Vector(10, GetScreenHeight() - 10))
	font.SetAlign(WIFALIGN_LEFT, WIFALIGN_BOTTOM)
	font.SetColor(0xFF4D21FF)
	font.SetShadowColor(Vector(0,0,0,1))
	path.AddFont(font)

	local info = Font("");
	info.SetSize(24)
	info.SetPos(Vector(GetScreenWidth() / 2, GetScreenHeight() * 0.9))
	info.SetAlign(WIFALIGN_LEFT, WIFALIGN_CENTER)
	info.SetShadowColor(Vector(0,0,0,1))
	path.AddFont(info)

	LoadModel("../models/dojo.wiscene")
	
	-- Create the two player characters. Parameters are facing direction and shirt material color to differentiate between them:
	local player1 = Character(1, Vector(1,1,1,1)) -- facing to right, white shirt
	local player2 = Character(-1, Vector(1,0,0,1)) -- facing to left, red shirt
	
	while true do

		ResolveCharacters(player1, player2)

		if(input.Press(string.byte('I'))) then
			player2.ai_state = "Idle"
		elseif(input.Press(string.byte('J'))) then
			player2.ai_state = "Jump"
		elseif(input.Press(string.byte('C'))) then
			player2.ai_state = "Crouch"
		elseif(input.Press(string.byte('G'))) then
			player2.ai_state = "Guard"
		end

		local inputString = "input: "
		for i,element in ipairs(player1.input_buffer) do
			if(element.command ~= "5") then
				inputString = inputString .. element.command
			end
		end
		info.SetText(inputString .. "\nstate = " .. player1.state .. "\nframe = " .. player1.frame)
		
		-- Wait for Engine update tick
		update()
		
	
		if(input.Press(VK_ESCAPE)) then
			-- restore previous component
			--	so if you loaded this script from the editor, you can go back to the editor with ESC
			backlog_post("EXIT")
			killProcesses()
			main.SetActivePath(prevPath)
			return
		end
		if(input.Press(string.byte('R'))) then
			-- reload script
			backlog_post("RELOAD")
			killProcesses()
			main.SetActivePath(prevPath)
			dofile("fighting_game.lua")
			return
		end
		
	end
end)
