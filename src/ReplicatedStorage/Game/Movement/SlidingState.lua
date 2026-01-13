local SlidingState = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local MovementUtils = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementUtils"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local function getMovementTemplate(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local vfx = assets:FindFirstChild("VFX")
	local movement = vfx and vfx:FindFirstChild("MovementFX")
	local fromNew = movement and movement:FindFirstChild(name)
	if fromNew then
		return fromNew
	end
	local legacy = assets:FindFirstChild("MovementFX")
	return legacy and legacy:FindFirstChild(name) or nil
end

SlidingState.SlidingSystem = nil

function SlidingState:Init(slidingSystem)
	self.SlidingSystem = slidingSystem
	LogService:Info("SLIDING", "SlidingState initialized")
end

function SlidingState:IsCrouchCooldownActive(characterController)
	if not characterController then
		return false
	end

	local currentTime = tick()
	local timeSinceLastCrouch = currentTime - characterController.LastCrouchTime
	local epsilon = 0.001

	local isCrouchCooldownActive = timeSinceLastCrouch < (Config.Gameplay.Cooldowns.Crouch - epsilon)

	if TestMode.Logging.LogSlidingSystem then
		LogService:Debug("SLIDING", "Crouch cooldown check", {
			CurrentTime = string.format("%.3f", currentTime),
			LastCrouchTime = string.format("%.3f", characterController.LastCrouchTime),
			TimeSinceLastCrouch = string.format("%.3f", timeSinceLastCrouch),
			CooldownTime = Config.Gameplay.Cooldowns.Crouch,
			IsActive = isCrouchCooldownActive,
			Note = "Crouch cooldown determines slide type - not bypassed",
		})
	end

	return isCrouchCooldownActive
end

function SlidingState:ResetCooldownsFromJumpCancel(characterController)
	local currentTime = tick()
	local resetTime = currentTime - 15

	self.SlidingSystem.LastSlideEndTime = resetTime

	if characterController then
		characterController.LastCrouchTime = resetTime
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "COOLDOWNS RESET FROM JUMP CANCEL", {
			ResetTime = string.format("%.3f", resetTime),
			CurrentTime = string.format("%.3f", currentTime),
			TimeOffset = 15,
			SlideEndTime = string.format("%.3f", self.SlidingSystem.LastSlideEndTime),
			CrouchTime = characterController and string.format("%.3f", characterController.LastCrouchTime) or "N/A",
		})
	end
end

function SlidingState:CanStartSlide(_movementInput, isCrouching, isGrounded)
	local timeSinceLastSlide = tick() - self.SlidingSystem.LastSlideEndTime
	if timeSinceLastSlide < Config.Gameplay.Cooldowns.Slide then
		return false, "Cooldown active"
	end

	if not isGrounded then
		return false, "Not grounded"
	end

	local isWalkable, slopeDegrees = MovementUtils:IsSlopeWalkable(
		self.SlidingSystem.Character,
		self.SlidingSystem.PrimaryPart,
		self.SlidingSystem.RaycastParams
	)
	if not isWalkable then
		return false, string.format("Slope too steep (%.1f°)", slopeDegrees)
	end

	if not isCrouching then
		return false, "Not crouching"
	end

	if self.SlidingSystem.IsSliding then
		return false, "Already sliding"
	end

	if not MovementStateManager:CanTransitionTo(MovementStateManager.States.Sliding) then
		return false, "Cannot transition to sliding state"
	end

	return true, "Can slide"
end

function SlidingState:IsInJumpCancelCoyoteTime()
	local currentTime = tick()
	local timeSinceSlideStop = currentTime - self.SlidingSystem.LastSlideStopTime
	local coyoteTime = Config.Gameplay.Sliding.JumpCancel.CoyoteTime

	return timeSinceSlideStop <= coyoteTime and timeSinceSlideStop > 0
end

function SlidingState:CanJumpCancel()
	if not Config.Gameplay.Sliding.JumpCancel.Enabled then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("SLIDING", "Jump cancel check failed - disabled", {
				JumpCancelEnabled = Config.Gameplay.Sliding.JumpCancel.Enabled,
			})
		end
		return false, "Jump cancel is disabled"
	end

	local isCurrentlySliding = MovementStateManager:IsSliding()
	local isInCoyoteTime = self:IsInJumpCancelCoyoteTime()

	if not isCurrentlySliding and not isInCoyoteTime then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("SLIDING", "Jump cancel check failed - not sliding and not in coyote time", {
				IsSliding = MovementStateManager:IsSliding(),
				CurrentState = MovementStateManager:GetCurrentState(),
				TimeSinceSlideStop = tick() - self.SlidingSystem.LastSlideStopTime,
				CoyoteTime = Config.Gameplay.Sliding.JumpCancel.CoyoteTime,
				IsInCoyoteTime = isInCoyoteTime,
			})
		end
		return false, "Not sliding and not in coyote time"
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "Jump cancel check passed", {
			IsSliding = MovementStateManager:IsSliding(),
			IsCurrentlySliding = isCurrentlySliding,
			IsInCoyoteTime = isInCoyoteTime,
			TimeSinceSlideStop = isInCoyoteTime and (tick() - self.SlidingSystem.LastSlideStopTime) or "N/A",
			SlideVelocity = isCurrentlySliding and self.SlidingSystem.SlideVelocity
				or self.SlidingSystem.SlideStopVelocity,
		})
	end

	return true, "Can jump cancel"
end

function SlidingState:ExecuteJumpCancel(slideDirection, characterController)
	if not self.SlidingSystem.PrimaryPart then
		LogService:Warn("SLIDING", "Cannot execute jump cancel - missing character components")
		return false
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "JUMP CANCEL EXECUTION STARTED", {
			ProvidedDirection = slideDirection,
			CurrentSlideDirection = self.SlidingSystem.SlideDirection,
			CurrentSlideVelocity = self.SlidingSystem.SlideVelocity,
			IsSliding = MovementStateManager:IsSliding(),
			PrimaryPartPosition = self.SlidingSystem.PrimaryPart.Position,
			CurrentVelocity = self.SlidingSystem.PrimaryPart.AssemblyLinearVelocity,
			HasCharacterController = characterController ~= nil,
			Timestamp = tick(),
		})
	end

	local direction = slideDirection or self.SlidingSystem.SlideDirection
	local isCurrentlySliding = MovementStateManager:IsSliding()
	local isInCoyoteTime = self:IsInJumpCancelCoyoteTime()

	if not isCurrentlySliding and isInCoyoteTime then
		direction = self.SlidingSystem.SlideStopDirection
	end

	local currentVelocity = self.SlidingSystem.PrimaryPart.AssemblyLinearVelocity
	local currentHorizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)

	local config = Config.Gameplay.Sliding.JumpCancel

	local isUphillBoost = false
	local verticalBoost = config.JumpHeight
	local horizontalPower = 0

	if config.UphillBoost.Enabled then
		local isGrounded, groundNormal, slopeDegrees =
			MovementUtils:CheckGroundedWithSlope(self.SlidingSystem.Character, self.SlidingSystem.PrimaryPart, self.SlidingSystem.RaycastParams)

		if isGrounded and groundNormal then
			local worldUp = Vector3.new(0, 1, 0)
			local slopeAngle = math.acos(math.clamp(groundNormal:Dot(worldUp), -1, 1))

			if slopeAngle > config.UphillBoost.SlopeThreshold then
				local gravity = Vector3.new(0, -1, 0)
				local slopeDownhillDirection = (gravity - gravity:Dot(groundNormal) * groundNormal)

				if slopeDownhillDirection.Magnitude > 0.01 then
					slopeDownhillDirection = slopeDownhillDirection.Unit

					local movementAlignment = direction:Dot(slopeDownhillDirection)

					if movementAlignment < 0 and movementAlignment <= config.UphillBoost.MinUphillAlignment then
						isUphillBoost = true

						local maxSlopeRadians = math.rad(config.UphillBoost.MaxSlopeAngle)
						local slopeStrength = math.clamp(slopeAngle / maxSlopeRadians, 0, 1)

						slopeStrength = slopeStrength ^ config.UphillBoost.ScalingExponent

						local slopeForwardDirection = (direction - direction:Dot(groundNormal) * groundNormal)
						if slopeForwardDirection.Magnitude > 0.01 then
							slopeForwardDirection = slopeForwardDirection.Unit
							direction = (direction * (1 - slopeStrength) + slopeForwardDirection * slopeStrength).Unit
						end

						verticalBoost = config.UphillBoost.MinVerticalBoost
							+ (config.UphillBoost.MaxVerticalBoost - config.UphillBoost.MinVerticalBoost) * (1 - slopeStrength)

						local velocityForScaling = isCurrentlySliding and self.SlidingSystem.SlideVelocity
							or (isInCoyoteTime and self.SlidingSystem.SlideStopVelocity or self.SlidingSystem.SlideVelocity)
						horizontalPower = math.max(
							velocityForScaling * config.UphillBoost.HorizontalVelocityScale * (1 + slopeStrength),
							config.UphillBoost.MinHorizontalVelocity
						)

						if TestMode.Logging.LogSlidingSystem then
							LogService:Info("SLIDING", "UPHILL JUMP CANCEL DETECTED - FORWARD LAUNCH", {
								SlopeDegrees = slopeDegrees,
								SlopeStrength = slopeStrength,
								MovementAlignment = movementAlignment,
								RequiredAlignment = config.UphillBoost.MinUphillAlignment,
								AlignmentAngleDegrees = math.deg(math.acos(math.clamp(-movementAlignment, 0, 1))),
								VerticalBoost = verticalBoost,
								HorizontalPower = horizontalPower,
								AdjustedDirection = direction,
							})
						end
					end
				end
			end
		end
	end

	if not isUphillBoost then
		local velocityForScaling = isCurrentlySliding and self.SlidingSystem.SlideVelocity
			or (isInCoyoteTime and self.SlidingSystem.SlideStopVelocity or self.SlidingSystem.SlideVelocity)
		local scaledPower = velocityForScaling * config.VelocityScaling

		horizontalPower = math.clamp(scaledPower, config.MinHorizontalPower, config.MaxHorizontalPower)
	end

	local newHorizontalVelocity = direction * horizontalPower

	local finalHorizontalVelocity = newHorizontalVelocity
	if not isUphillBoost then
		local preservedMomentum = currentHorizontalVelocity * config.MomentumPreservation
		finalHorizontalVelocity = newHorizontalVelocity + preservedMomentum
	end

	local finalVelocity = Vector3.new(
		finalHorizontalVelocity.X,
		verticalBoost,
		finalHorizontalVelocity.Z
	)

	self.SlidingSystem.PrimaryPart.AssemblyLinearVelocity = finalVelocity

	do
		local template = getMovementTemplate("SlideCancel")
		if template then
			VFXPlayer:Play(template, self.SlidingSystem.PrimaryPart.Position)
		end
	end

	local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
	local animationController = ServiceRegistry:GetController("AnimationController")
	if animationController and animationController.TriggerJumpCancelAnimation then
		animationController:TriggerJumpCancelAnimation()
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("SLIDING", "Triggered JumpCancel animation")
		end
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "JUMP CANCEL VELOCITY APPLIED", {
			AppliedVelocity = finalVelocity,
			HorizontalSpeed = finalHorizontalVelocity.Magnitude,
			VerticalSpeed = finalVelocity.Y,
			CharacterPosition = self.SlidingSystem.PrimaryPart.Position,
			IsUphillBoost = isUphillBoost,
			BoostType = isUphillBoost and "Uphill" or "Normal",
		})
	end

	self.SlidingSystem.JumpCancelPerformed = true

	self:ResetCooldownsFromJumpCancel(characterController)
	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "JUMP CANCEL COOLDOWNS RESET", {
			PreviousSlideEndTime = self.SlidingSystem.LastSlideEndTime,
			NewSlideEndTime = self.SlidingSystem.LastSlideEndTime,
			PreviousCrouchTime = characterController and characterController.LastCrouchTime or "N/A",
			NewCrouchTime = characterController and characterController.LastCrouchTime or "N/A",
		})
	end

	if isCurrentlySliding then
		local canUncrouch = self:CanUncrouchAfterJumpSlide()
		if canUncrouch then
			self.SlidingSystem:StopSlide(false, true, "JumpCancel")
			if characterController then
				characterController.IsCrouching = false
				if characterController.InputManager then
					characterController.InputManager.IsCrouching = false
				end
			end
			if TestMode.Logging.LogSlidingSystem then
				LogService:Info("SLIDING", "Jump cancel: slide stopped, crouch input cleared")
			end
		else
			self.SlidingSystem:StopSlide(true, false, "JumpCancel")
			if TestMode.Logging.LogSlidingSystem then
				LogService:Info(
					"SLIDING",
					"Jump cancel: slide stopped, staying crouched due to overhead obstruction"
				)
			end
		end
	elseif isInCoyoteTime then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info(
				"SLIDING",
				"Jump cancel during coyote time after slide stop - no additional slide state changes needed"
			)
		end
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "JUMP CANCEL EXECUTED SUCCESSFULLY", {
			SlideVelocity = self.SlidingSystem.SlideVelocity,
			IsCurrentlySliding = isCurrentlySliding,
			IsInCoyoteTime = isInCoyoteTime,
			FinalHorizontalPower = horizontalPower,
			FinalVelocity = finalVelocity,
			FinalHorizontalSpeed = finalHorizontalVelocity.Magnitude,
			SlideDirection = direction,
			JumpCancelPerformed = self.SlidingSystem.JumpCancelPerformed,
			IsUphillBoost = isUphillBoost,
			VerticalBoost = verticalBoost,
		})
	end

	return true
end

function SlidingState:CanUncrouchAfterJumpSlide()
	if not self.SlidingSystem.Character then
		return false
	end

	local collisionHead = CharacterLocations:GetCollisionHead(self.SlidingSystem.Character)
	local collisionBody = CharacterLocations:GetCollisionBody(self.SlidingSystem.Character)

	if not collisionHead or not collisionBody then
		return false
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { self.SlidingSystem.Character }
	overlapParams.RespectCanCollide = true
	overlapParams.MaxParts = 20

	local headObstructions = workspace:GetPartsInPart(collisionHead, overlapParams)
	local bodyObstructions = workspace:GetPartsInPart(collisionBody, overlapParams)

	return #headObstructions == 0 and #bodyObstructions == 0
end

return SlidingState
