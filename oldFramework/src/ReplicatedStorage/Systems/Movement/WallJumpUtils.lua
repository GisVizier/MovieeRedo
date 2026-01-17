local WallJumpUtils = {}

print("========================================")
print("[WALL_JUMP] WallJumpUtils module loaded!")
print("========================================")

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local WallDetectionUtils = require(Locations.Modules.Utils.WallDetectionUtils)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local TestMode = require(ReplicatedStorage.TestMode)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local VFXController = require(Locations.Modules.Systems.Core.VFXController)

--[[
	WallJumpUtils - Utility for wall jumping mechanics

	This module provides wall jump functionality that allows players to jump off walls
	when airborne. The wall jump applies a vertical boost and horizontal boost away from
	the wall, plus an additional boost in the camera direction.

	Usage:
		local success = WallJumpUtils:AttemptWallJump(character, primaryPart, raycastParams, cameraYAngle)
]]

-- Charge system tracking (Rivals-style: limited charges + cooldown)
WallJumpUtils.RemainingCharges = 3 -- Start with full charges (matches config: 3 charges)
WallJumpUtils.HasResetThisLanding = true -- Track if charges were already reset this landing
WallJumpUtils.LastWallJumpTime = 0 -- Track last wall jump for cooldown
WallJumpUtils.LastLandingTime = 0 -- Track when player last landed (for edge stick prevention)

--[[
	Attempts to perform a wall jump

	@param character - The character model
	@param primaryPart - The character's primary part (Root)
	@param raycastParams - RaycastParams for wall detection
	@param cameraAngles - Vector2(yaw, pitch) in degrees from CameraController
	@param characterController - Character controller for accessing sprint state and movement direction (optional)

	@return success (boolean) - True if wall jump was executed, false otherwise
	@return wallData (table or nil) - Wall detection data if wall was found
]]
function WallJumpUtils:AttemptWallJump(character, primaryPart, raycastParams, cameraAngles, characterController)
	-- Check if wall jumping is enabled
	if not Config.Gameplay.Character.WallJump.Enabled then
		print("[WALL_JUMP] Wall jumping is disabled in config")
		return false, nil
	end

	-- Validate inputs
	if not character or not primaryPart or not raycastParams then
		print("[WALL_JUMP] Invalid inputs:", character ~= nil, primaryPart ~= nil, raycastParams ~= nil)
		if TestMode.Logging.LogSlidingSystem then
			LogService:Warn("WALL_JUMP", "Invalid inputs for wall jump", {
				HasCharacter = character ~= nil,
				HasPrimaryPart = primaryPart ~= nil,
				HasRaycastParams = raycastParams ~= nil,
			})
		end
		return false, nil
	end

	print("[WALL_JUMP] AttemptWallJump called - starting validation")

	-- RIVALS: Check cooldown between wall jumps (prevent spam)
	local currentTime = tick()
	local cooldown = Config.Gameplay.Character.WallJump.CooldownBetweenJumps or 0.15
	local timeSinceLastJump = currentTime - self.LastWallJumpTime

	if timeSinceLastJump < cooldown then
		print("[WALL_JUMP] On cooldown - wait", string.format("%.2f", cooldown - timeSinceLastJump), "seconds")
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "Wall jump on cooldown", {
				TimeSinceLastJump = timeSinceLastJump,
				Cooldown = cooldown,
			})
		end
		return false, nil
	end

	-- EDGE STICK PREVENTION: Add grace period after landing before wall jumps can trigger
	-- This prevents getting stuck on walls when landing near edges
	local landingGracePeriod = 0.15 -- 150ms grace after landing
	local timeSinceLanding = currentTime - self.LastLandingTime
	if timeSinceLanding < landingGracePeriod then
		print("[WALL_JUMP] Landing grace period - wait", string.format("%.2f", landingGracePeriod - timeSinceLanding), "seconds")
		return false, nil
	end

	-- Check if we have charges available
	if self.RemainingCharges <= 0 then
		print("[WALL_JUMP] No charges remaining - must land to reset")
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "No wall jump charges remaining", {
				RemainingCharges = self.RemainingCharges,
			})
		end
		return false, nil
	end

	-- Check if player is grounded (wall jump only works when airborne)
	local isGrounded = self:IsCharacterGrounded(character, primaryPart, raycastParams)
	print("[WALL_JUMP] Grounded check:", isGrounded, "RequireAirborne:", Config.Gameplay.Character.WallJump.RequireAirborne)
	if Config.Gameplay.Character.WallJump.RequireAirborne and isGrounded then
		print("[WALL_JUMP] Rejected - player is grounded")
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "Wall jump requires airborne state", {
				IsGrounded = isGrounded,
			})
		end
		return false, nil
	end

	-- Check if player is sprinting (wall jump requires sprint)
	if Config.Gameplay.Character.WallJump.RequireSprinting then
		local isSprinting = characterController and characterController.IsSprinting or false
		print("[WALL_JUMP] Sprint check:", isSprinting, "RequireSprinting:", Config.Gameplay.Character.WallJump.RequireSprinting)
		if not isSprinting then
			print("[WALL_JUMP] Rejected - player is not sprinting")
			if TestMode.Logging.LogSlidingSystem then
				LogService:Debug("WALL_JUMP", "Wall jump requires sprinting", {
					IsSprinting = isSprinting,
				})
			end
			return false, nil
		end
	end

	-- Check if player is in sliding state (wall jump disabled during slide)
	local isSliding = MovementStateManager:IsSliding()
	print("[WALL_JUMP] Sliding check:", isSliding, "ExcludeDuringSlide:", Config.Gameplay.Character.WallJump.ExcludeDuringSlide)
	if Config.Gameplay.Character.WallJump.ExcludeDuringSlide and isSliding then
		print("[WALL_JUMP] Rejected - player is sliding")
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "Wall jump disabled during slide", {
				CurrentState = MovementStateManager:GetCurrentState(),
			})
		end
		return false, nil
	end

	-- Detect walls using 360° radial raycast pattern (same as wall boost system)
	local wallDetected, wallData = self:DetectWallRadial(character, primaryPart, raycastParams)

	if not wallDetected then
		print("[WALL_JUMP] No wall detected using radial detection")
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "No wall detected for wall jump", {
				CameraAngles = cameraAngles,
			})
		end
		return false, nil
	end

	print("[WALL_JUMP] Wall detected! Part:", wallData.Part.Name, "Distance:", wallData.Distance)

	-- Execute wall jump (pass characterController for movement direction)
	self:ExecuteWallJump(primaryPart, wallData, cameraAngles, characterController)

	return true, wallData
end

--[[
	Executes the wall jump by applying velocity

	@param primaryPart - The character's primary part
	@param wallData - Wall detection data from WallDetectionUtils
	@param cameraAngles - Vector2(yaw, pitch) in degrees from CameraController
	@param characterController - Character controller for accessing movement direction (optional)
]]
function WallJumpUtils:ExecuteWallJump(primaryPart, wallData, cameraAngles, characterController)
	local config = Config.Gameplay.Character.WallJump

	-- Convert angles from degrees to radians
	local yaw = math.rad(cameraAngles.X)

	-- Calculate horizontal direction from camera yaw (where player is looking)
	local cameraDirection = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))

	-- Wall normal (direction away from wall)
	local wallNormal = wallData.Normal
	local wallNormalHorizontal = Vector3.new(wallNormal.X, 0, wallNormal.Z)
	if wallNormalHorizontal.Magnitude > 0.01 then
		wallNormalHorizontal = wallNormalHorizontal.Unit
	else
		wallNormalHorizontal = cameraDirection
	end

	-- ANGLED PUSH-OFF: Calculate push direction based on incoming approach velocity
	-- This creates a bounce-like effect where the exit angle depends on entry angle
	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local incomingHorizontal = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local angleMultiplier = config.AnglePushMultiplier or 1.5
	
	local pushDirection
	if incomingHorizontal.Magnitude > 1 then
		-- Normalize incoming direction
		local incomingDir = incomingHorizontal.Unit
		
		-- Reflect off wall: reflection = incoming - 2 * (incoming · normal) * normal
		local dotProduct = incomingDir:Dot(wallNormalHorizontal)
		local reflection = incomingDir - 2 * dotProduct * wallNormalHorizontal
		
		-- Blend reflection with pure wall normal based on angleMultiplier
		-- Higher multiplier = more angle-based, lower = more straight push-off
		local blendedDirection = (reflection * angleMultiplier + wallNormalHorizontal)
		if blendedDirection.Magnitude > 0.01 then
			pushDirection = blendedDirection.Unit
		else
			pushDirection = wallNormalHorizontal
		end
		
		print("[WALL_JUMP] Angled push-off - IncomingDot:", dotProduct, "ReflectionAngle:", math.deg(math.acos(reflection:Dot(wallNormalHorizontal))))
	else
		-- No significant incoming velocity, push straight away from wall
		pushDirection = wallNormalHorizontal
		print("[WALL_JUMP] No incoming velocity - straight push-off from wall")
	end

	-- Calculate final horizontal velocity
	local wallPushVelocity = pushDirection * config.WallPushForce
	local cameraPushVelocity = cameraDirection * config.HorizontalBoost

	-- Combine: Angled wall push is PRIMARY, camera direction is secondary
	local horizontalVelocity = wallPushVelocity + cameraPushVelocity

	-- Vertical boost
	local verticalVelocity = config.VerticalBoost

	-- Combine into final velocity
	local newVelocity = Vector3.new(
		horizontalVelocity.X,
		verticalVelocity,
		horizontalVelocity.Z
	)

	-- Apply velocity
	primaryPart.AssemblyLinearVelocity = newVelocity

	-- Consume a charge and update cooldown timer
	self.RemainingCharges = self.RemainingCharges - 1
	self.HasResetThisLanding = false -- Mark that we've used a charge, allow reset on next landing
	self.LastWallJumpTime = tick() -- RIVALS: Start cooldown timer

	print("[WALL_JUMP] ✓ WALL JUMP EXECUTED! Charges remaining:", self.RemainingCharges, "NewVelocity:", newVelocity, "Wall:", wallData.Part.Name)

	-- TRIGGER SCREEN SHAKE for wall jump impact feel
	local screenShakeModule = Locations.Client and Locations.Client.Controllers and Locations.Client.Controllers.ScreenShakeController
	if screenShakeModule then
		local success, screenShake = pcall(function()
			return require(screenShakeModule)
		end)
		if success and screenShake and screenShake.ShakeWallJump then
			screenShake:ShakeWallJump()
		end
	end

	-- TRIGGER WALL JUMP VFX at wall contact point
	VFXController:PlayVFXReplicated("WallJump", wallData.Position)

	-- Trigger wall boost animation (directional based on wall jump direction)
	local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
	local animationController = ServiceRegistry:GetController("AnimationController")
	
	-- If this was the last charge, trigger falling animation after a brief delay
	-- This puts the player in a visible "falling" state when charges are depleted
	if self.RemainingCharges <= 0 and animationController then
		-- Short delay so the wall boost animation plays briefly first, then transitions to falling
		task.delay(0.3, function()
			-- Only play falling if still airborne and no wall jump happened since
			if self.RemainingCharges <= 0 and animationController.PlayFallingAnimation then
				print("[WALL_JUMP] All charges depleted - triggering falling animation")
				animationController:PlayFallingAnimation()
			end
		end)
	end
	
	if animationController and animationController.TriggerWallBoostAnimation then
		-- Calculate the angle between camera direction and wall normal to determine jump direction
		local cameraDirXZ = Vector3.new(cameraDirection.X, 0, cameraDirection.Z)
		local wallNormalXZ = Vector3.new(wallNormal.X, 0, wallNormal.Z)

		local animationName
		
		if cameraDirXZ.Magnitude < 0.01 or wallNormalXZ.Magnitude < 0.01 then
			-- Can't determine direction - pick random left or right
			animationName = math.random() > 0.5 and "WallBoostRight" or "WallBoostLeft"
		else
			cameraDirXZ = cameraDirXZ.Unit
			wallNormalXZ = wallNormalXZ.Unit

			local crossProduct = cameraDirXZ:Cross(wallNormalXZ)
			if crossProduct.Y > 0 then
				animationName = "WallBoostRight"
			else
				animationName = "WallBoostLeft"
			end
		end
		
		animationController:PlayAirborneAnimation(animationName)
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("WALL_JUMP", "Wall jump executed", {
			WallNormal = wallData.Normal,
			WallPart = wallData.Part.Name,
			WallPushVelocity = wallPushVelocity,
			CameraPushVelocity = cameraPushVelocity,
			HorizontalVelocity = horizontalVelocity,
			VerticalVelocity = verticalVelocity,
			NewVelocity = newVelocity,
			RemainingCharges = self.RemainingCharges,
		})
	end
end

--[[
	Detects walls using 360° radial raycast pattern (same method as wall boost system)

	@param character - The character model
	@param primaryPart - The character's primary part
	@param raycastParams - RaycastParams for wall detection

	@return detected (boolean), wallData (table or nil)
]]
function WallJumpUtils:DetectWallRadial(character, primaryPart, raycastParams)
	-- Get Body part for raycasting
	local bodyPart = CharacterLocations:GetBody(character)
	if not bodyPart then
		return false, nil
	end

	-- Ray origin: bottom of body (prevents false positives from walls above head)
	local bodyPosition = bodyPart.Position
	local bodySize = bodyPart.Size
	local rayOrigin = bodyPosition - Vector3.new(0, bodySize.Y / 2, 0)

	-- Detection settings
	local detectionRadius = Config.Gameplay.Character.WallJump.WallDetectionDistance
	local numDirections = 16 -- Number of rays in 360° pattern
	local MIN_WALL_ANGLE = Config.Gameplay.Character.WallJump.MinWallAngle -- Use config value instead of hardcoded

	-- Generate 360° radial directions
	local directions = {}
	for i = 1, numDirections do
		local angle = (i - 1) * (360 / numDirections) -- Evenly spaced: 0°, 22.5°, 45°, etc.
		local radians = math.rad(angle)
		table.insert(directions, Vector3.new(math.sin(radians), 0, math.cos(radians)))
	end

	-- Cast rays in all directions
	for _, direction in ipairs(directions) do
		local ray = workspace:Raycast(rayOrigin, direction * detectionRadius, raycastParams)

		-- Check if we hit something valid
		if ray and not ray.Instance:IsDescendantOf(character) and ray.Instance.CanCollide then
			-- Validate it's actually a wall (vertical surface)
			local surfaceNormal = ray.Normal
			local worldUp = Vector3.new(0, 1, 0)
			local angleFromVertical = math.acos(math.clamp(math.abs(surfaceNormal:Dot(worldUp)), 0, 1))
			local degreesFromVertical = math.deg(angleFromVertical)

			-- Only consider surfaces 60° or more from vertical (excludes slopes, floors, ceilings)
			if degreesFromVertical >= MIN_WALL_ANGLE then
				local wallData = {
					Hit = true,
					Distance = ray.Distance,
					Position = ray.Position,
					Normal = surfaceNormal,
					Part = ray.Instance,
				}

				if TestMode.Logging.LogSlidingSystem then
					LogService:Info("WALL_JUMP", "Wall detected via radial raycast", {
						Distance = ray.Distance,
						Direction = direction,
						HitPart = ray.Instance.Name,
						VerticalAngle = degreesFromVertical,
					})
				end

				return true, wallData
			end
		end
	end

	return false, nil
end

--[[
	Checks if character is grounded using raycast

	@param character - The character model
	@param primaryPart - The character's primary part
	@param raycastParams - RaycastParams for ground detection

	@return isGrounded (boolean)
]]
function WallJumpUtils:IsCharacterGrounded(character, primaryPart, raycastParams)
	local feetPart = CharacterLocations:GetFeet(character)
	if not feetPart then
		return false
	end

	-- Use same ground detection logic as character controller
	local rayOrigin = feetPart.Position - Vector3.new(0, feetPart.Size.Y / 2, 0)
	local rayDirection = Vector3.new(0, -1, 0)
	local rayDistance = Config.Gameplay.Character.GroundRayDistance + Config.Gameplay.Character.GroundRayOffset

	local ray = workspace:Raycast(rayOrigin, rayDirection * rayDistance, raycastParams)

	return ray ~= nil
end

--[[
	Resets wall jump charges when landing on the ground
	This should be called when the character becomes grounded
]]
function WallJumpUtils:ResetCharges()
	-- Only reset once per landing to prevent spam
	if self.HasResetThisLanding then
		return
	end

	local config = Config.Gameplay.Character.WallJump
	self.RemainingCharges = config.MaxCharges
	self.HasResetThisLanding = true
	self.LastLandingTime = tick() -- Track landing time for edge stick prevention
	print("[WALL_JUMP] Charges reset - player landed. Full charges:", self.RemainingCharges)
end

return WallJumpUtils
