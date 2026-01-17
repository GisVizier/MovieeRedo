local SlidingState = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local SoundManager = require(Locations.Modules.Systems.Core.SoundManager)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local TestMode = require(ReplicatedStorage.TestMode)
local VFXController = require(Locations.Modules.Systems.Core.VFXController)

-- Reference to main SlidingSystem (will be set by SlidingSystem:Init)
SlidingState.SlidingSystem = nil

function SlidingState:Init(slidingSystem)
	self.SlidingSystem = slidingSystem
	LogService:Info("SLIDING", "SlidingState initialized")
end

function SlidingState:IsCrouchCooldownActive(characterController)
	if not characterController then
		return false
	end

	-- Check crouch cooldown normally (don't bypass this - it determines slide type)
	local currentTime = tick()
	local timeSinceLastCrouch = currentTime - characterController.LastCrouchTime
	local epsilon = 0.001

	local isCrouchCooldownActive = timeSinceLastCrouch < (Config.Gameplay.Cooldowns.Crouch - epsilon)

	-- Debug logging for timing
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
	-- Reset slide cooldown by setting it to an old timestamp
	local currentTime = tick()
	local resetTime = currentTime - 15 -- 15 seconds ago, well beyond any cooldown

	-- Reset slide cooldown
	self.SlidingSystem.LastSlideEndTime = resetTime

	-- Reset crouch cooldown if we have access to character controller
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
	-- Check cooldown
	local timeSinceLastSlide = tick() - self.SlidingSystem.LastSlideEndTime
	if timeSinceLastSlide < Config.Gameplay.Cooldowns.Slide then
		return false, "Cooldown active"
	end

	-- Must be grounded
	if not isGrounded then
		return false, "Not grounded"
	end

	-- Check slope angle (use same limits as walking/jumping)
	local isWalkable, slopeDegrees = MovementUtils:IsSlopeWalkable(
		self.SlidingSystem.Character,
		self.SlidingSystem.PrimaryPart,
		self.SlidingSystem.RaycastParams
	)
	if not isWalkable then
		return false, string.format("Slope too steep (%.1f°)", slopeDegrees)
	end

	-- Must be crouching
	if not isCrouching then
		return false, "Not crouching"
	end

	-- Movement input is always allowed (no speed requirement)

	-- Must not already be sliding
	if self.SlidingSystem.IsSliding then
		return false, "Already sliding"
	end

	-- Check if can transition to sliding state
	if not MovementStateManager:CanTransitionTo(MovementStateManager.States.Sliding) then
		return false, "Cannot transition to sliding state"
	end

	return true, "Can slide"
end

function SlidingState:IsInJumpCancelCoyoteTime()
	-- Check if we're within the coyote time after a slide stop
	local currentTime = tick()
	local timeSinceSlideStop = currentTime - self.SlidingSystem.LastSlideStopTime
	local coyoteTime = Config.Gameplay.Sliding.JumpCancel.CoyoteTime

	return timeSinceSlideStop <= coyoteTime and timeSinceSlideStop > 0
end

function SlidingState:CanJumpCancel()
	-- Check if jump cancel is enabled
	if not Config.Gameplay.Sliding.JumpCancel.Enabled then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("SLIDING", "❌ Jump cancel check failed - disabled", {
				JumpCancelEnabled = Config.Gameplay.Sliding.JumpCancel.Enabled,
			})
		end
		return false, "Jump cancel is disabled"
	end

	-- Check if currently sliding OR in coyote time after slide stop
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

	-- Use provided direction (for buffered), current slide direction, or stopped slide direction for coyote time
	local direction = slideDirection or self.SlidingSystem.SlideDirection
	local isCurrentlySliding = MovementStateManager:IsSliding()
	local isInCoyoteTime = self:IsInJumpCancelCoyoteTime()

	if not isCurrentlySliding and isInCoyoteTime then
		-- Use the direction and velocity from when the slide stopped
		direction = self.SlidingSystem.SlideStopDirection
	end

	-- Get current velocity to preserve momentum
	local currentVelocity = self.SlidingSystem.PrimaryPart.AssemblyLinearVelocity
	local currentHorizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)

	-- Use sliding jump cancel config
	local config = Config.Gameplay.Sliding.JumpCancel

	-- Check for uphill boost conditions
	local isUphillBoost = false
	local verticalBoost = config.JumpHeight
	local horizontalPower = 0

	if config.UphillBoost.Enabled then
		-- Get slope information at current position
		local isGrounded, groundNormal, slopeDegrees =
			MovementUtils:CheckGroundedWithSlope(self.SlidingSystem.Character, self.SlidingSystem.PrimaryPart, self.SlidingSystem.RaycastParams)

		if isGrounded and groundNormal then
			-- Calculate slope angle in radians for comparison
			local worldUp = Vector3.new(0, 1, 0)
			local slopeAngle = math.acos(math.clamp(groundNormal:Dot(worldUp), -1, 1))

			-- Check if slope is steep enough to be considered a slope (not flat ground)
			if slopeAngle > config.UphillBoost.SlopeThreshold then
				-- Calculate downhill direction from slope gradient
				local gravity = Vector3.new(0, -1, 0)
				local slopeDownhillDirection = (gravity - gravity:Dot(groundNormal) * groundNormal)

				-- Only proceed if downhill direction is valid (not zero vector)
				if slopeDownhillDirection.Magnitude > 0.01 then
					slopeDownhillDirection = slopeDownhillDirection.Unit

					-- Determine if sliding uphill by checking alignment with downhill direction
					-- Negative alignment means moving opposite to downhill (i.e., moving uphill)
					local movementAlignment = direction:Dot(slopeDownhillDirection)

					-- Check if player is moving uphill AND nearly directly up the slope
					-- MinUphillAlignment is negative (e.g., -0.7 means must be within ~45° of directly uphill)
					-- This prevents getting boost from moving sideways across a ramp
					if movementAlignment < 0 and movementAlignment <= config.UphillBoost.MinUphillAlignment then
						-- Player is sliding nearly directly uphill! Apply uphill boost
						isUphillBoost = true

						-- Calculate slope steepness factor (0 to 1) based on slope angle
						local maxSlopeRadians = math.rad(config.UphillBoost.MaxSlopeAngle)
						local slopeStrength = math.clamp(slopeAngle / maxSlopeRadians, 0, 1)

						-- Apply scaling curve (configurable exponent)
						slopeStrength = slopeStrength ^ config.UphillBoost.ScalingExponent

						-- For uphill slopes: use FORWARD force along the slope direction, not vertical
						-- Project the direction onto the slope surface for a forward launch
						local slopeForwardDirection = (direction - direction:Dot(groundNormal) * groundNormal)
						if slopeForwardDirection.Magnitude > 0.01 then
							slopeForwardDirection = slopeForwardDirection.Unit
							-- Blend between flat forward and slope-aligned forward based on steepness
							direction = (direction * (1 - slopeStrength) + slopeForwardDirection * slopeStrength).Unit
						end

						-- Scale vertical boost LOWER for steeper slopes (more horizontal launch)
						-- Steeper slope = more forward, less up
						verticalBoost = config.UphillBoost.MinVerticalBoost
							+ (config.UphillBoost.MaxVerticalBoost - config.UphillBoost.MinVerticalBoost) * (1 - slopeStrength)

						-- Calculate horizontal velocity as percentage of current slide velocity
						local velocityForScaling = isCurrentlySliding and self.SlidingSystem.SlideVelocity
							or (isInCoyoteTime and self.SlidingSystem.SlideStopVelocity or self.SlidingSystem.SlideVelocity)
						-- Increase horizontal power for steeper slopes
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

	-- If not uphill boost, use normal jump cancel logic
	if not isUphillBoost then
		-- Calculate scaled horizontal power based on current slide velocity or stopped slide velocity for coyote time
		local velocityForScaling = isCurrentlySliding and self.SlidingSystem.SlideVelocity
			or (isInCoyoteTime and self.SlidingSystem.SlideStopVelocity or self.SlidingSystem.SlideVelocity)
		local scaledPower = velocityForScaling * config.VelocityScaling

		-- Clamp the power between min and max values
		horizontalPower = math.clamp(scaledPower, config.MinHorizontalPower, config.MaxHorizontalPower)
	end

	-- Create new horizontal velocity in slide direction
	local newHorizontalVelocity = direction * horizontalPower

	-- Preserve some existing momentum for smoother transition (only for normal jump cancel)
	local finalHorizontalVelocity = newHorizontalVelocity
	if not isUphillBoost then
		local preservedMomentum = currentHorizontalVelocity * config.MomentumPreservation
		finalHorizontalVelocity = newHorizontalVelocity + preservedMomentum
	end

	-- Combine with jump height (use calculated vertical boost)
	local finalVelocity = Vector3.new(
		finalHorizontalVelocity.X,
		verticalBoost,
		finalHorizontalVelocity.Z
	)

	-- Apply the velocity
	self.SlidingSystem.PrimaryPart.AssemblyLinearVelocity = finalVelocity

	-- TRIGGER SLIDE CANCEL VFX at player position
	VFXController:PlayVFXReplicated("SlideCancel", self.SlidingSystem.PrimaryPart.Position)

	-- Trigger jump cancel animation
	local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
	local animationController = ServiceRegistry:GetController("AnimationController")
	if animationController and animationController.TriggerJumpCancelAnimation then
		animationController:TriggerJumpCancelAnimation()
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("SLIDING", "Triggered JumpCancel animation")
		end
	end

	-- Log the actual velocity applied for debugging
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

	-- Mark that jump cancel was performed (prevents teleport on release after landing)
	self.SlidingSystem.JumpCancelPerformed = true

	-- Reset cooldowns directly - much simpler than bypass system
	self:ResetCooldownsFromJumpCancel(characterController)
	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "JUMP CANCEL COOLDOWNS RESET", {
			PreviousSlideEndTime = self.SlidingSystem.LastSlideEndTime,
			NewSlideEndTime = self.SlidingSystem.LastSlideEndTime,
			PreviousCrouchTime = characterController and characterController.LastCrouchTime or "N/A",
			NewCrouchTime = characterController and characterController.LastCrouchTime or "N/A",
		})
	end

	-- Handle slide stopping based on whether we're currently sliding or in coyote time
	if isCurrentlySliding then
		-- Stop the slide after jump cancel
		-- Check if we can uncrouch before stopping slide (using collision parts like CharacterController)
		local canUncrouch = self:CanUncrouchAfterJumpSlide()
		if canUncrouch then
			self.SlidingSystem:StopSlide(false, true)
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
			self.SlidingSystem:StopSlide(true, false)
			if TestMode.Logging.LogSlidingSystem then
				LogService:Info(
					"SLIDING",
					"Jump cancel: slide stopped, staying crouched due to overhead obstruction"
				)
			end
		end
	elseif isInCoyoteTime then
		-- Jump cancel after slide stop - player is already in post-slide state, just apply the jump
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

	-- Create OverlapParams to exclude character parts and respect actual geometry
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { self.SlidingSystem.Character }
	overlapParams.RespectCanCollide = true -- Only detect collidable parts (ignore CanCollide = false)
	overlapParams.MaxParts = 20 -- Reasonable limit for performance

	-- Use GetPartsInPart for accurate geometry collision detection using collision parts
	local headObstructions = workspace:GetPartsInPart(collisionHead, overlapParams)
	local bodyObstructions = workspace:GetPartsInPart(collisionBody, overlapParams)

	-- If any parts found, there's an obstruction
	return #headObstructions == 0 and #bodyObstructions == 0
end

return SlidingState
