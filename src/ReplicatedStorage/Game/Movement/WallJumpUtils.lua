local WallJumpUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local VFXController = require(Locations.Shared.Util:WaitForChild("VFXController"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

WallJumpUtils.RemainingCharges = 3
WallJumpUtils.HasResetThisLanding = true
WallJumpUtils.LastWallJumpTime = 0
WallJumpUtils.LastLandingTime = 0

function WallJumpUtils:AttemptWallJump(character, primaryPart, raycastParams, cameraAngles, characterController)
	if not Config.Gameplay.Character.WallJump.Enabled then
		return false, nil
	end

	if not character or not primaryPart or not raycastParams then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Warn("WALL_JUMP", "Invalid inputs for wall jump", {
				HasCharacter = character ~= nil,
				HasPrimaryPart = primaryPart ~= nil,
				HasRaycastParams = raycastParams ~= nil,
			})
		end
		return false, nil
	end

	local currentTime = tick()
	local cooldown = Config.Gameplay.Character.WallJump.CooldownBetweenJumps or 0.15
	local timeSinceLastJump = currentTime - self.LastWallJumpTime

	if timeSinceLastJump < cooldown then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "Wall jump on cooldown", {
				TimeSinceLastJump = timeSinceLastJump,
				Cooldown = cooldown,
			})
		end
		return false, nil
	end

	local landingGracePeriod = 0.15
	local timeSinceLanding = currentTime - self.LastLandingTime
	if timeSinceLanding < landingGracePeriod then
		return false, nil
	end

	if self.RemainingCharges <= 0 then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "No wall jump charges remaining", {
				RemainingCharges = self.RemainingCharges,
			})
		end
		return false, nil
	end

	local isGrounded = self:IsCharacterGrounded(character, primaryPart, raycastParams)
	if Config.Gameplay.Character.WallJump.RequireAirborne and isGrounded then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "Wall jump requires airborne state", {
				IsGrounded = isGrounded,
			})
		end
		return false, nil
	end

	if Config.Gameplay.Character.WallJump.RequireSprinting then
		local isSprinting = characterController and characterController.IsSprinting or false
		if not isSprinting then
			if TestMode.Logging.LogSlidingSystem then
				LogService:Debug("WALL_JUMP", "Wall jump requires sprinting", {
					IsSprinting = isSprinting,
				})
			end
			return false, nil
		end
	end

	local isSliding = MovementStateManager:IsSliding()
	if Config.Gameplay.Character.WallJump.ExcludeDuringSlide and isSliding then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "Wall jump disabled during slide", {
				CurrentState = MovementStateManager:GetCurrentState(),
			})
		end
		return false, nil
	end

	local wallDetected, wallData = self:DetectWallRadial(character, primaryPart, raycastParams)
	if not wallDetected then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("WALL_JUMP", "No wall detected for wall jump", {
				CameraAngles = cameraAngles,
			})
		end
		return false, nil
	end

	self:ExecuteWallJump(primaryPart, wallData, cameraAngles, characterController)

	return true, wallData
end

function WallJumpUtils:ExecuteWallJump(primaryPart, wallData, cameraAngles, _characterController)
	local config = Config.Gameplay.Character.WallJump

	local yaw = math.rad(cameraAngles.X)
	local cameraDirection = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))

	local wallNormal = wallData.Normal
	local wallNormalHorizontal = Vector3.new(wallNormal.X, 0, wallNormal.Z)
	if wallNormalHorizontal.Magnitude > 0.01 then
		wallNormalHorizontal = wallNormalHorizontal.Unit
	else
		wallNormalHorizontal = cameraDirection
	end

	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local incomingHorizontal = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local angleMultiplier = config.AnglePushMultiplier or 1.5

	local pushDirection
	if incomingHorizontal.Magnitude > 1 then
		local incomingDir = incomingHorizontal.Unit
		local dotProduct = incomingDir:Dot(wallNormalHorizontal)
		local reflection = incomingDir - 2 * dotProduct * wallNormalHorizontal
		local blendedDirection = (reflection * angleMultiplier + wallNormalHorizontal)
		if blendedDirection.Magnitude > 0.01 then
			pushDirection = blendedDirection.Unit
		else
			pushDirection = wallNormalHorizontal
		end
	else
		pushDirection = wallNormalHorizontal
	end

	local wallPushVelocity = pushDirection * config.WallPushForce
	local cameraPushVelocity = cameraDirection * config.HorizontalBoost

	local horizontalVelocity = wallPushVelocity + cameraPushVelocity
	local verticalVelocity = config.VerticalBoost

	local newVelocity = Vector3.new(
		horizontalVelocity.X,
		verticalVelocity,
		horizontalVelocity.Z
	)

	primaryPart.AssemblyLinearVelocity = newVelocity

	self.RemainingCharges = self.RemainingCharges - 1
	self.HasResetThisLanding = false
	self.LastWallJumpTime = tick()

	VFXController:PlayVFXReplicated("WallJump", wallData.Position)

	local animationController = ServiceRegistry:GetController("AnimationController")

	if self.RemainingCharges <= 0 and animationController then
		task.delay(0.3, function()
			if self.RemainingCharges <= 0 and animationController.PlayFallingAnimation then
				animationController:PlayFallingAnimation()
			end
		end)
	end

	if animationController and animationController.TriggerWallBoostAnimation then
		local cameraDirXZ = Vector3.new(cameraDirection.X, 0, cameraDirection.Z)
		local wallNormalXZ = Vector3.new(wallNormal.X, 0, wallNormal.Z)

		local animationName

		if cameraDirXZ.Magnitude < 0.01 or wallNormalXZ.Magnitude < 0.01 then
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

function WallJumpUtils:DetectWallRadial(character, primaryPart, raycastParams)
	local bodyPart = CharacterLocations:GetBody(character)
	if not bodyPart then
		return false, nil
	end

	local bodyPosition = bodyPart.Position
	local bodySize = bodyPart.Size
	local rayOrigin = bodyPosition - Vector3.new(0, bodySize.Y / 2, 0)

	local detectionRadius = Config.Gameplay.Character.WallJump.WallDetectionDistance
	local numDirections = 16
	local minWallAngle = Config.Gameplay.Character.WallJump.MinWallAngle

	local directions = {}
	for i = 1, numDirections do
		local angle = (i - 1) * (360 / numDirections)
		local radians = math.rad(angle)
		table.insert(directions, Vector3.new(math.sin(radians), 0, math.cos(radians)))
	end

	for _, direction in ipairs(directions) do
		local ray = workspace:Raycast(rayOrigin, direction * detectionRadius, raycastParams)

		if ray and not ray.Instance:IsDescendantOf(character) and ray.Instance.CanCollide then
			local surfaceNormal = ray.Normal
			local worldUp = Vector3.new(0, 1, 0)
			local angleFromVertical = math.acos(math.clamp(math.abs(surfaceNormal:Dot(worldUp)), 0, 1))
			local degreesFromVertical = math.deg(angleFromVertical)

			if degreesFromVertical >= minWallAngle then
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

function WallJumpUtils:IsCharacterGrounded(character, primaryPart, raycastParams)
	local feetPart = CharacterLocations:GetFeet(character)
	if not feetPart then
		return false
	end

	local rayOrigin = feetPart.Position - Vector3.new(0, feetPart.Size.Y / 2, 0)
	local rayDirection = Vector3.new(0, -1, 0)
	local rayDistance = Config.Gameplay.Character.GroundRayDistance + Config.Gameplay.Character.GroundRayOffset

	local ray = workspace:Raycast(rayOrigin, rayDirection * rayDistance, raycastParams)

	return ray ~= nil
end

function WallJumpUtils:ResetCharges()
	if self.HasResetThisLanding then
		return
	end

	local config = Config.Gameplay.Character.WallJump
	self.RemainingCharges = config.MaxCharges
	self.HasResetThisLanding = true
	self.LastLandingTime = tick()
end

return WallJumpUtils
