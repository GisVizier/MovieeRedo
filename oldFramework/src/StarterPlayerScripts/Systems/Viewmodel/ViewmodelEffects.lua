--[[
	ViewmodelEffects.lua

	Handles all procedural effects for the viewmodel:
	- Mouse sway (viewmodel tilts with mouse movement)
	- Turn sway (viewmodel rolls when turning)
	- Movement bob (walk, run, crouch bounce)
	- Jump offset (viewmodel reacts to jumping/falling)
	- Sprint tuck (gun lowers when sprinting)
	- Slide tilt (gun tucks to side when sliding)
	- Land impact (optional shake on landing - disabled by default)

	All effects combine together for final viewmodel offset.
]]

local ViewmodelEffects = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local Log = require(Locations.Modules.Systems.Core.LogService)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Controller reference (set during Init)
ViewmodelEffects.Controller = nil

--============================================================================
-- EFFECT STATE TRACKING
-- Current values for each effect (lerped toward targets)
--============================================================================
ViewmodelEffects.BobTime = 0
ViewmodelEffects.CurrentSwayOffset = CFrame.new()
ViewmodelEffects.CurrentBobOffset = CFrame.new()
ViewmodelEffects.CurrentTurnSway = CFrame.new()
ViewmodelEffects.CurrentJumpOffset = CFrame.new()
ViewmodelEffects.CurrentSprintTuck = CFrame.new()
ViewmodelEffects.CurrentSlideOffset = CFrame.new()
ViewmodelEffects.CurrentLandOffset = CFrame.new()
ViewmodelEffects.CurrentMovementTilt = CFrame.new()

-- Target values (what we're lerping toward)
ViewmodelEffects.JumpOffsetTarget = CFrame.new()
ViewmodelEffects.SprintTuckTarget = CFrame.new()
ViewmodelEffects.SlideOffsetTarget = CFrame.new()
ViewmodelEffects.MovementTiltTarget = CFrame.new()

-- Tracking values
ViewmodelEffects.LastCameraLook = Vector3.new(0, 0, -1)
ViewmodelEffects.LastMouseDelta = Vector2.new(0, 0)
ViewmodelEffects.SwayCurrent = Vector2.new(0, 0)
ViewmodelEffects.TurnSwayCurrent = 0

-- Land detection
ViewmodelEffects.WasGrounded = true
ViewmodelEffects.LandTime = 0
ViewmodelEffects.IsLanding = false

-- Jump peak detection (for smooth jump->fall transition)
ViewmodelEffects.JumpState = "grounded" -- "grounded", "rising", "peak", "falling"
ViewmodelEffects.PeakStartTime = 0
ViewmodelEffects.WasRising = false

--============================================================================
-- INITIALIZATION
--============================================================================

function ViewmodelEffects:Init(controller)
	self.Controller = controller
	Log:Debug("VIEWMODEL", "ViewmodelEffects initialized")
end

function ViewmodelEffects:Reset()
	self.BobTime = 0
	self.CurrentSwayOffset = CFrame.new()
	self.CurrentBobOffset = CFrame.new()
	self.CurrentTurnSway = CFrame.new()
	self.CurrentJumpOffset = CFrame.new()
	self.CurrentSprintTuck = CFrame.new()
	self.CurrentSlideOffset = CFrame.new()
	self.CurrentLandOffset = CFrame.new()
	self.LastCameraLook = Camera.CFrame.LookVector
	self.LastMouseDelta = Vector2.new(0, 0)
	self.SwayCurrent = Vector2.new(0, 0)
	self.TurnSwayCurrent = 0
	self.WasGrounded = true
	self.LandTime = 0
	self.IsLanding = false
	self.JumpOffsetTarget = CFrame.new()
	self.SprintTuckTarget = CFrame.new()
	self.SlideOffsetTarget = CFrame.new()
	self.MovementTiltTarget = CFrame.new()
	self.CurrentMovementTilt = CFrame.new()
	self.JumpState = "grounded"
	self.PeakStartTime = 0
	self.WasRising = false
end

--============================================================================
-- MAIN UPDATE - Combines all effects
--============================================================================

function ViewmodelEffects:GetCombinedOffset(deltaTime, adsAlpha, weaponConfig)
	local effects = ViewmodelConfig.Effects

	-- Update each effect
	self:UpdateMouseSway(deltaTime, adsAlpha, weaponConfig, effects)
	self:UpdateTurnSway(deltaTime, adsAlpha, effects)
	self:UpdateMovementBob(deltaTime, adsAlpha, weaponConfig, effects)
	self:UpdateJumpOffset(deltaTime, weaponConfig)
	self:UpdateSprintTuck(deltaTime, adsAlpha, weaponConfig)
	self:UpdateSlideOffset(deltaTime, adsAlpha, weaponConfig)
	self:UpdateLandOffset(deltaTime, effects)
	self:UpdateMovementTilt(deltaTime, adsAlpha, weaponConfig)

	-- Combine all effects (order matters for visual result)
	-- Sway and turn sway first (rotational)
	-- Then positional offsets (bob, jump, sprint, slide, land)
	-- Movement tilt last for subtle lean effect
	local combinedOffset = self.CurrentSwayOffset
		* self.CurrentTurnSway
		* self.CurrentBobOffset
		* self.CurrentJumpOffset
		* self.CurrentSprintTuck
		* self.CurrentSlideOffset
		* self.CurrentLandOffset
		* self.CurrentMovementTilt

	return combinedOffset
end

--============================================================================
-- MOUSE SWAY
-- Viewmodel tilts when moving mouse
--============================================================================

function ViewmodelEffects:UpdateMouseSway(deltaTime, adsAlpha, weaponConfig, effects)
	local mouseDelta = UserInputService:GetMouseDelta()

	local sensitivity = effects.Sway.MouseSensitivity
	local maxAngle = effects.Sway.MaxAngle
	local returnSpeed = effects.Sway.ReturnSpeed

	-- Apply weapon-specific multipliers
	local swayMultiplier = weaponConfig.Sway.Multiplier
	local adsMultiplier = weaponConfig.Sway.ADSMultiplier
	local finalMultiplier = swayMultiplier * (1 - adsAlpha) + (swayMultiplier * adsMultiplier) * adsAlpha

	-- Get sway delay (creates trailing effect when looking around)
	local swayDelay = ViewmodelConfig:GetSwayDelay(weaponConfig)

	-- Calculate target sway from mouse input
	local targetSway = Vector2.new(
		math.clamp(-mouseDelta.X * sensitivity * finalMultiplier, -maxAngle, maxAngle),
		math.clamp(-mouseDelta.Y * sensitivity * finalMultiplier, -maxAngle, maxAngle)
	)

	-- Smooth toward target with delay factor
	-- Higher delay = slower response = more trailing effect
	local smoothing = ViewmodelConfig.Global.SwaySmoothing
	local delayedSmoothing = smoothing * (1 - swayDelay * 0.8) -- Reduce smoothing based on delay
	self.SwayCurrent = self.SwayCurrent:Lerp(targetSway, math.min(deltaTime * delayedSmoothing, 1))

	-- Return to center when no input (also affected by delay)
	local delayedReturnSpeed = returnSpeed * (1 - swayDelay * 0.5)
	self.SwayCurrent = self.SwayCurrent:Lerp(Vector2.new(0, 0), math.min(deltaTime * delayedReturnSpeed, 1))

	-- Convert to CFrame rotation
	self.CurrentSwayOffset = CFrame.Angles(math.rad(self.SwayCurrent.Y), math.rad(self.SwayCurrent.X), 0)
end

--============================================================================
-- TURN SWAY
-- Viewmodel rolls when turning camera
--============================================================================

function ViewmodelEffects:UpdateTurnSway(deltaTime, adsAlpha, effects)
	local currentLook = Camera.CFrame.LookVector
	local lastLook = self.LastCameraLook

	-- Calculate turn delta using cross product
	local turnDelta = currentLook:Cross(lastLook).Y

	self.LastCameraLook = currentLook

	local sensitivity = effects.TurnSway.Sensitivity
	local maxAngle = effects.TurnSway.MaxAngle
	local returnSpeed = effects.TurnSway.ReturnSpeed

	-- Calculate target turn sway
	local targetTurnSway = math.clamp(turnDelta * sensitivity * 100, -maxAngle, maxAngle)
	targetTurnSway = targetTurnSway * (1 - adsAlpha * 0.7) -- Reduce during ADS

	-- Smooth toward target
	local smoothing = 8
	self.TurnSwayCurrent = self.TurnSwayCurrent + (targetTurnSway - self.TurnSwayCurrent) * math.min(deltaTime * smoothing, 1)

	-- Return to center
	self.TurnSwayCurrent = self.TurnSwayCurrent * (1 - deltaTime * returnSpeed)

	-- Convert to roll rotation
	self.CurrentTurnSway = CFrame.Angles(0, 0, math.rad(self.TurnSwayCurrent))
end

--============================================================================
-- MOVEMENT BOB
-- Bounce effect when walking/running/crouching
--============================================================================

function ViewmodelEffects:UpdateMovementBob(deltaTime, adsAlpha, weaponConfig, effects)
	local character = LocalPlayer.Character
	if not character then
		self.CurrentBobOffset = CFrame.new()
		return
	end

	local root = character:FindFirstChild("Root")
	if not root then
		self.CurrentBobOffset = CFrame.new()
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	local isGrounded = MovementStateManager:GetIsGrounded()
	local currentState = MovementStateManager:GetCurrentState()

	-- Detect landing for land effect trigger (only if enabled)
	if not self.WasGrounded and isGrounded and horizontalSpeed < 5 then
		if effects.LandBob.Enabled then
			self.IsLanding = true
			self.LandTime = 0
		end
	end
	self.WasGrounded = isGrounded

	-- No bob when airborne or stationary
	if not isGrounded or horizontalSpeed < 0.5 then
		self.BobTime = 0
		self.CurrentBobOffset = self.CurrentBobOffset:Lerp(CFrame.new(), math.min(deltaTime * 10, 1))
		return
	end

	-- Select bob config based on movement state
	local bobConfig
	local bobMultiplier = 1.0

	if currentState == "Crouching" then
		bobConfig = effects.CrouchBob
		bobMultiplier = weaponConfig.Bob.WalkMultiplier
	elseif currentState == "Sprinting" or horizontalSpeed > 20 then
		bobConfig = effects.RunBob
		bobMultiplier = weaponConfig.Bob.RunMultiplier
	else
		bobConfig = effects.WalkBob
		bobMultiplier = weaponConfig.Bob.WalkMultiplier
	end

	-- Apply ADS reduction
	local adsMultiplier = weaponConfig.Bob.ADSMultiplier
	local finalMultiplier = bobMultiplier * (1 - adsAlpha) + (bobMultiplier * adsMultiplier) * adsAlpha

	-- Progress bob cycle based on speed
	local speedFactor = math.clamp(horizontalSpeed / 15, 0.5, 1.5)
	self.BobTime = self.BobTime + deltaTime * bobConfig.Frequency * speedFactor

	-- Calculate bob using sine/cosine for smooth oscillation
	local sinValue = math.sin(self.BobTime)
	local cosValue = math.cos(self.BobTime * 2)

	-- Position offset (side-to-side and up-down)
	local posOffset = Vector3.new(
		sinValue * bobConfig.Amplitude.X * finalMultiplier,
		math.abs(cosValue) * bobConfig.Amplitude.Y * finalMultiplier,
		0
	)

	-- Rotation offset
	local rotOffset = Vector3.new(
		cosValue * bobConfig.RotationAmplitude.X * finalMultiplier,
		sinValue * bobConfig.RotationAmplitude.Y * finalMultiplier,
		sinValue * bobConfig.RotationAmplitude.Z * finalMultiplier
	)

	-- Combine into target CFrame
	local targetBob = CFrame.new(posOffset)
		* CFrame.Angles(math.rad(rotOffset.X), math.rad(rotOffset.Y), math.rad(rotOffset.Z))

	-- Smooth toward target
	local smoothing = ViewmodelConfig.Global.BobSmoothing
	self.CurrentBobOffset = self.CurrentBobOffset:Lerp(targetBob, math.min(deltaTime * smoothing, 1))
end

--============================================================================
-- JUMP OFFSET
-- Viewmodel reacts to jumping/falling with smooth peak transition
--============================================================================

function ViewmodelEffects:UpdateJumpOffset(deltaTime, weaponConfig)
	local isGrounded = MovementStateManager:GetIsGrounded()

	-- Get merged jump config (weapon override or global)
	local jumpConfig = ViewmodelConfig:GetMergedEffect(weaponConfig, "JumpBob")

	-- Get vertical velocity
	local character = LocalPlayer.Character
	local verticalVelocity = 0
	if character then
		local root = character:FindFirstChild("Root")
		if root then
			verticalVelocity = root.AssemblyLinearVelocity.Y
		end
	end

	-- Get peak detection settings
	local peakThreshold = jumpConfig.PeakVelocityThreshold or 5
	local peakHoldTime = jumpConfig.PeakHoldTime or 0.15

	-- Update jump state machine
	if isGrounded then
		self.JumpState = "grounded"
		self.WasRising = false
	else
		-- Determine current velocity state
		local isRising = verticalVelocity > peakThreshold
		local isFalling = verticalVelocity < -peakThreshold
		local isAtPeak = math.abs(verticalVelocity) <= peakThreshold

		-- State transitions
		if self.JumpState == "grounded" then
			-- Just left ground
			if isRising then
				self.JumpState = "rising"
				self.WasRising = true
			elseif isFalling then
				self.JumpState = "falling"
			end
		elseif self.JumpState == "rising" then
			-- Currently rising
			if isAtPeak then
				-- Entering peak (apex of jump)
				self.JumpState = "peak"
				self.PeakStartTime = tick()
			elseif isFalling then
				-- Skipped peak (fast transition)
				self.JumpState = "falling"
			end
		elseif self.JumpState == "peak" then
			-- At peak - wait for hold time before transitioning to fall
			local peakElapsed = tick() - self.PeakStartTime
			if peakElapsed >= peakHoldTime then
				-- Hold time complete, transition to falling
				self.JumpState = "falling"
			elseif isRising then
				-- Still rising (edge case: upward boost at peak)
				self.JumpState = "rising"
			end
		elseif self.JumpState == "falling" then
			-- Currently falling
			if isRising then
				-- Somehow started rising again (wall jump, etc)
				self.JumpState = "rising"
				self.WasRising = true
			end
		end
	end

	-- Set target based on current state
	if self.JumpState == "grounded" then
		self.JumpOffsetTarget = CFrame.new()
	elseif self.JumpState == "rising" then
		-- Rising (jumping up)
		self.JumpOffsetTarget = CFrame.new(jumpConfig.UpOffset)
			* CFrame.Angles(
				math.rad(jumpConfig.UpRotation.X),
				math.rad(jumpConfig.UpRotation.Y),
				math.rad(jumpConfig.UpRotation.Z)
			)
	elseif self.JumpState == "peak" then
		-- At peak - neutral/hang position
		local peakOffset = jumpConfig.PeakOffset or Vector3.new(0, 0, 0)
		local peakRotation = jumpConfig.PeakRotation or Vector3.new(0, 0, 0)
		self.JumpOffsetTarget = CFrame.new(peakOffset)
			* CFrame.Angles(
				math.rad(peakRotation.X),
				math.rad(peakRotation.Y),
				math.rad(peakRotation.Z)
			)
	elseif self.JumpState == "falling" then
		-- Falling - gun points up
		self.JumpOffsetTarget = CFrame.new(jumpConfig.DownOffset)
			* CFrame.Angles(
				math.rad(jumpConfig.DownRotation.X),
				math.rad(jumpConfig.DownRotation.Y),
				math.rad(jumpConfig.DownRotation.Z)
			)
	end

	-- Smooth transition
	local transitionSpeed = jumpConfig.TransitionSpeed
	self.CurrentJumpOffset = self.CurrentJumpOffset:Lerp(self.JumpOffsetTarget, math.min(deltaTime * transitionSpeed, 1))
end

--============================================================================
-- SPRINT TUCK
-- Gun lowers/tucks when sprinting
--============================================================================

function ViewmodelEffects:UpdateSprintTuck(deltaTime, adsAlpha, weaponConfig)
	-- Check if sprint tuck is enabled (weapon override or global)
	local sprintConfig = ViewmodelConfig:GetMergedEffect(weaponConfig, "SprintTuck")
	if not sprintConfig.Enabled then
		self.SprintTuckTarget = CFrame.new()
		self.CurrentSprintTuck = self.CurrentSprintTuck:Lerp(self.SprintTuckTarget, math.min(deltaTime * 10, 1))
		return
	end

	local currentState = MovementStateManager:GetCurrentState()
	local isSprinting = currentState == "Sprinting"

	-- Don't tuck if ADS
	if adsAlpha > 0.5 then
		isSprinting = false
	end

	if isSprinting then
		self.SprintTuckTarget = CFrame.new(sprintConfig.Offset)
			* CFrame.Angles(
				math.rad(sprintConfig.Rotation.X),
				math.rad(sprintConfig.Rotation.Y),
				math.rad(sprintConfig.Rotation.Z)
			)
	else
		self.SprintTuckTarget = CFrame.new()
	end

	-- Smooth transition
	local transitionSpeed = sprintConfig.TransitionSpeed
	self.CurrentSprintTuck = self.CurrentSprintTuck:Lerp(self.SprintTuckTarget, math.min(deltaTime * transitionSpeed, 1))
end

--============================================================================
-- SLIDE OFFSET
-- Gun tucks to the side when sliding
--============================================================================

function ViewmodelEffects:UpdateSlideOffset(deltaTime, adsAlpha, weaponConfig)
	local currentState = MovementStateManager:GetCurrentState()
	local isSliding = currentState == "Sliding"

	-- Get merged slide config (weapon override or global)
	local slideConfig = ViewmodelConfig:GetMergedEffect(weaponConfig, "SlideTilt")

	-- Reduce slide tilt during ADS
	local slideMultiplier = 1 - (adsAlpha * 0.7)

	if isSliding then
		-- Fixed slide direction - always tilt right (positive)
		-- No camera-relative calculation so it doesn't turn when looking around
		local slideDirection = 1

		-- Calculate roll angle (fixed tilt)
		local tiltAngle = slideConfig.Angle * slideDirection * slideMultiplier

		-- Calculate position offset (tuck to the side)
		local offsetX = slideConfig.Offset.X * slideDirection * slideMultiplier
		local offsetY = slideConfig.Offset.Y * slideMultiplier
		local offsetZ = slideConfig.Offset.Z * slideMultiplier

		-- Additional rotation from config
		local rotX = slideConfig.Rotation.X * slideMultiplier
		local rotY = slideConfig.Rotation.Y * slideDirection * slideMultiplier
		local rotZ = slideConfig.Rotation.Z * slideMultiplier

		self.SlideOffsetTarget = CFrame.new(offsetX, offsetY, offsetZ)
			* CFrame.Angles(
				math.rad(rotX),
				math.rad(rotY),
				math.rad(tiltAngle + rotZ)
			)
	else
		self.SlideOffsetTarget = CFrame.new()
	end

	-- Smooth transition
	local transitionSpeed = slideConfig.TransitionSpeed
	self.CurrentSlideOffset = self.CurrentSlideOffset:Lerp(self.SlideOffsetTarget, math.min(deltaTime * transitionSpeed, 1))
end

--============================================================================
-- LAND OFFSET
-- Optional impact shake when landing (disabled by default for smooth flow)
--============================================================================

function ViewmodelEffects:UpdateLandOffset(deltaTime, effects)
	-- Check if land effect is enabled
	if not effects.LandBob.Enabled then
		-- Smoothly return to neutral (no jarring snap)
		self.CurrentLandOffset = self.CurrentLandOffset:Lerp(CFrame.new(), math.min(deltaTime * 10, 1))
		self.IsLanding = false
		return
	end

	if self.IsLanding then
		local landConfig = effects.LandBob

		self.LandTime = self.LandTime + deltaTime

		if self.LandTime < landConfig.Duration then
			-- Calculate eased alpha (sine curve for smooth in/out)
			local alpha = self.LandTime / landConfig.Duration
			local easedAlpha = math.sin(alpha * math.pi)

			-- Apply land offset
			self.CurrentLandOffset = CFrame.new(landConfig.Offset * easedAlpha)
				* CFrame.Angles(
					math.rad(landConfig.Rotation.X * easedAlpha),
					math.rad(landConfig.Rotation.Y * easedAlpha),
					math.rad(landConfig.Rotation.Z * easedAlpha)
				)
		else
			-- Effect complete
			self.IsLanding = false
			self.CurrentLandOffset = CFrame.new()
		end
	else
		-- Recover to neutral
		local recoverySpeed = effects.LandBob.RecoverySpeed
		self.CurrentLandOffset = self.CurrentLandOffset:Lerp(CFrame.new(), math.min(deltaTime * recoverySpeed, 1))
	end
end

--============================================================================
-- MOVEMENT TILT
-- Viewmodel tilts based on strafe/forward movement direction
--============================================================================

function ViewmodelEffects:UpdateMovementTilt(deltaTime, adsAlpha, weaponConfig)
	-- Get merged movement tilt config (weapon override or global)
	local tiltConfig = ViewmodelConfig:GetMergedEffect(weaponConfig, "MovementTilt")

	-- Check if movement tilt is enabled
	if not tiltConfig.Enabled then
		self.MovementTiltTarget = CFrame.new()
		self.CurrentMovementTilt = self.CurrentMovementTilt:Lerp(self.MovementTiltTarget, math.min(deltaTime * 10, 1))
		return
	end

	-- Get movement direction from CharacterController
	local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
	local characterController = ServiceRegistry:GetController("CharacterController")

	local strafeDirection = 0
	local forwardDirection = 0

	if characterController and characterController.GetRelativeMovementDirection then
		local moveDir, magnitude = characterController:GetRelativeMovementDirection()
		if magnitude > 0.01 then
			strafeDirection = moveDir.X  -- Left/right strafe
			forwardDirection = moveDir.Y  -- Forward/backward
		end
	end

	-- Apply ADS reduction
	local adsMultiplier = tiltConfig.ADSMultiplier or 0.3
	local adsFactor = 1 - (adsAlpha * (1 - adsMultiplier))

	-- Calculate roll from strafe (tilt toward movement direction)
	local rollAngle = strafeDirection * tiltConfig.StrafeAngle * adsFactor

	-- Calculate pitch from forward/back movement
	local pitchAngle = forwardDirection * tiltConfig.ForwardAngle * adsFactor

	-- Set target
	self.MovementTiltTarget = CFrame.Angles(
		math.rad(pitchAngle),
		0,
		math.rad(-rollAngle) -- Negative because we want to lean INTO the turn
	)

	-- Smooth transition
	local transitionSpeed = tiltConfig.TransitionSpeed
	self.CurrentMovementTilt = self.CurrentMovementTilt:Lerp(self.MovementTiltTarget, math.min(deltaTime * transitionSpeed, 1))
end

--============================================================================
-- MANUAL TRIGGERS
--============================================================================

-- Manually trigger land effect (can be called externally)
function ViewmodelEffects:TriggerLandEffect()
	if ViewmodelConfig.Effects.LandBob.Enabled then
		self.IsLanding = true
		self.LandTime = 0
	end
end

return ViewmodelEffects
