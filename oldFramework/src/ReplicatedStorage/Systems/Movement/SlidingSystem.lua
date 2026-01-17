local SlidingSystem = {}

-- Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local SoundManager = require(Locations.Modules.Systems.Core.SoundManager)
local SlideDirectionDetector = require(Locations.Modules.Utils.SlideDirectionDetector)

-- New modular systems
local SlidingBuffer = require(Locations.Modules.Systems.Movement.SlidingBuffer)
local SlidingPhysics = require(Locations.Modules.Systems.Movement.SlidingPhysics)
local SlidingState = require(Locations.Modules.Systems.Movement.SlidingState)
local RigRotationUtils = require(Locations.Modules.Systems.Character.RigRotationUtils)
local FOVController = require(Locations.Modules.Systems.Core.FOVController)
local VFXController = require(Locations.Modules.Systems.Core.VFXController)

-- State variables (managed by MovementStateManager, these are for internal physics only)
SlidingSystem.IsSliding = false
SlidingSystem.SlideVelocity = 0
SlidingSystem.SlideDirection = Vector3.new(0, 0, 0)
SlidingSystem.OriginalSlideDirection = Vector3.new(0, 0, 0)
SlidingSystem.LastSlideEndTime = 0
SlidingSystem.CurrentSlideSkipsCooldown = false
SlidingSystem.PreviousY = 0

-- Airborne tracking
SlidingSystem.AirborneStartTime = 0
SlidingSystem.AirborneStartY = 0
SlidingSystem.AirbornePeakY = 0
SlidingSystem.IsAirborne = false
SlidingSystem.WasAirborneLastFrame = false

-- Slide buffering (allows buffering slide during jump)
SlidingSystem.IsSlideBuffered = false
SlidingSystem.BufferedSlideDirection = Vector3.new(0, 0, 0)
SlidingSystem.SlideBufferStartTime = 0
SlidingSystem.IsSlideBufferFromJumpCancel = false -- Track if buffer came from jump cancel reset

-- Jump cancel buffering (allows buffering jump cancel during airborne)
SlidingSystem.IsJumpCancelBuffered = false
SlidingSystem.BufferedJumpCancelDirection = Vector3.new(0, 0, 0)
SlidingSystem.JumpCancelBufferStartTime = 0

-- Jump cancel teleport prevention (prevents teleport after landing from jump cancel)
SlidingSystem.JumpCancelPerformed = false
SlidingSystem.HasLandedAfterJumpCancel = false

-- Jump cancel coyote time tracking (allows jump cancel after slide stops)
SlidingSystem.LastSlideStopTime = 0
SlidingSystem.SlideStopDirection = Vector3.new(0, 0, 0)
SlidingSystem.SlideStopVelocity = 0

-- Cooldown system now uses direct reset instead of bypass

-- Character references
SlidingSystem.Character = nil
SlidingSystem.PrimaryPart = nil
SlidingSystem.AlignOrientation = nil
SlidingSystem.RaycastParams = nil
SlidingSystem.CameraController = nil
SlidingSystem.CharacterController = nil
SlidingSystem.LastCameraAngle = 0

-- Module references
SlidingSystem.SlidingBuffer = SlidingBuffer
SlidingSystem.SlidingPhysics = SlidingPhysics
SlidingSystem.SlidingState = SlidingState

-- Connections
SlidingSystem.SlideUpdateConnection = nil

-- Trail effect
SlidingSystem.SlideTrail = nil
SlidingSystem.TrailAttachment0 = nil
SlidingSystem.TrailAttachment1 = nil

-- Sound cooldown to prevent spam
SlidingSystem.LastLandingBoostSoundTime = 0
SlidingSystem.LandingBoostSoundCooldown = 0.1 -- 100ms cooldown

-- Track last known deltaTime for frame-rate independent initial velocity application
SlidingSystem.LastKnownDeltaTime = 1 / 60 -- Default to 60fps

function SlidingSystem:Init()
	-- Initialize modular systems with reference to main SlidingSystem
	SlidingBuffer:Init(self)
	SlidingPhysics:Init(self)
	SlidingState:Init(self)

	LogService:Info("SLIDING", "SlidingSystem initialized with modular architecture")
end

function SlidingSystem:CreateSlideTrail()
	-- Trail disabled
	return
end

function SlidingSystem:RemoveSlideTrail()
	-- Disconnect spawn connection
	if self.TrailSpawnConnection then
		self.TrailSpawnConnection:Disconnect()
		self.TrailSpawnConnection = nil
	end
	
	-- Clear last spawn time
	self.LastTrailSpawnTime = nil
	
	-- Clean up existing trail parts (let them fade naturally)
	-- Don't destroy folder immediately so parts can finish fading
	if self.TrailFolder then
		task.delay(12, function()
			if self.TrailFolder and self.TrailFolder.Parent then
				self.TrailFolder:Destroy()
			end
		end)
		self.TrailFolder = nil
	end
end

function SlidingSystem:PlayLandingBoostSound()
	local currentTime = tick()
	if currentTime - self.LastLandingBoostSoundTime >= self.LandingBoostSoundCooldown then
		self.LastLandingBoostSoundTime = currentTime

		-- Play landing boost sound locally (no 3D positioning for local client)
		SoundManager:PlaySound("Movement", "LandingBoost")

		-- Request sound replication to other players (with 3D positioning at player body)
		local bodyPart = CharacterLocations:GetBody(self.Character) or self.PrimaryPart
		if bodyPart then
			SoundManager:RequestSoundReplication("Movement", "LandingBoost", bodyPart.Position)
		end

		return true -- Sound was played
	end
	return false -- Sound was on cooldown
end

-- Delegate state management methods to SlidingState module
function SlidingSystem:IsCrouchCooldownActive(characterController)
	return SlidingState:IsCrouchCooldownActive(characterController)
end

function SlidingSystem:ResetCooldownsFromJumpCancel(characterController)
	return SlidingState:ResetCooldownsFromJumpCancel(characterController)
end

function SlidingSystem:CanStartSlide(movementInput, isCrouching, isGrounded)
	return SlidingState:CanStartSlide(movementInput, isCrouching, isGrounded)
end

function SlidingSystem:IsInJumpCancelCoyoteTime()
	return SlidingState:IsInJumpCancelCoyoteTime()
end

function SlidingSystem:CanJumpCancel()
	return SlidingState:CanJumpCancel()
end

function SlidingSystem:ExecuteJumpCancel(slideDirection, characterController)
	return SlidingState:ExecuteJumpCancel(slideDirection, characterController)
end

function SlidingSystem:CanUncrouchAfterJumpSlide()
	return SlidingState:CanUncrouchAfterJumpSlide()
end

-- Delegate buffering methods to SlidingBuffer module
function SlidingSystem:CanBufferSlide(movementInput, isCrouching, isGrounded, characterController)
	return SlidingBuffer:CanBufferSlide(movementInput, isCrouching, isGrounded, characterController)
end

function SlidingSystem:StartSlideBuffer(movementDirection, fromJumpCancel)
	return SlidingBuffer:StartSlideBuffer(movementDirection, fromJumpCancel)
end

function SlidingSystem:CancelSlideBuffer(reason)
	return SlidingBuffer:CancelSlideBuffer(reason)
end

function SlidingSystem:TransferSlideCooldownToCrouch(characterController)
	return SlidingBuffer:TransferSlideCooldownToCrouch(characterController)
end

function SlidingSystem:CanBufferJumpCancel()
	return SlidingBuffer:CanBufferJumpCancel()
end

function SlidingSystem:StartJumpCancelBuffer()
	return SlidingBuffer:StartJumpCancelBuffer()
end

function SlidingSystem:CancelJumpCancelBuffer()
	return SlidingBuffer:CancelJumpCancelBuffer()
end

-- Delegate physics methods to SlidingPhysics module
function SlidingSystem:GetInitialSlideDirection(originalDirection)
	return SlidingPhysics:GetInitialSlideDirection(originalDirection)
end

function SlidingSystem:GetInitialSlopeVelocityBoost()
	return SlidingPhysics:GetInitialSlopeVelocityBoost()
end

function SlidingSystem:CalculateSlopeMultiplierChange(deltaTime, slideConfig)
	return SlidingPhysics:CalculateSlopeMultiplierChange(deltaTime, slideConfig)
end

function SlidingSystem:ApplySlideVelocity(deltaTime)
	return SlidingPhysics:ApplySlideVelocity(deltaTime)
end

function SlidingSystem:UpdateSlideDirection()
	return SlidingPhysics:UpdateSlideDirection()
end

function SlidingSystem:CheckGroundedForSliding()
	return SlidingPhysics:CheckGroundedForSliding()
end

function SlidingSystem:UpdateSlideRotation()
	return SlidingPhysics:UpdateSlideRotation()
end

-- Character setup and main system orchestration methods (remain in main system)
function SlidingSystem:SetupCharacter(character, primaryPart, _vectorForce, alignOrientation, raycastParams)
	self.Character = character
	self.PrimaryPart = primaryPart
	-- We don't need VectorForce anymore - using direct velocity
	self.AlignOrientation = alignOrientation
	self.RaycastParams = raycastParams
end

function SlidingSystem:SetCameraController(cameraController)
	self.CameraController = cameraController
end

function SlidingSystem:SetCharacterController(characterController)
	self.CharacterController = characterController
end

function SlidingSystem:StartSlide(movementDirection, currentCameraAngle)
	if not self.PrimaryPart then
		LogService:Warn("SLIDING", "Cannot start slide - missing character components")
		return false
	end

	-- Use default responsiveness for slide rotation
	if self.AlignOrientation then
		self.AlignOrientation.Responsiveness = Config.Controls.Camera.Smoothness or 25
	end

	-- Check if this is a buffered slide landing
	local wasBuffered = self.IsSlideBuffered
	local airborneBonus = 0

	if wasBuffered then
		-- Calculate landing boost from buffered slide airborne time (if enabled)
		local landingBoostConfig = Config.Gameplay.Sliding.LandingBoost
		if landingBoostConfig.Enabled ~= false then -- Default to true for backwards compat
			local airTime = tick() - self.AirborneStartTime
			-- Use peak height for consistent boost calculation (same as active slides)
			local fallDistance = self.AirbornePeakY - self.PrimaryPart.Position.Y

			if
				airTime > landingBoostConfig.MinAirTime
				and fallDistance > landingBoostConfig.MinFallDistance
			then
				-- Check slope angle at landing position to determine boost multiplier
				local _, _, slopeDegrees =
					MovementUtils:CheckGroundedWithSlope(self.Character, self.PrimaryPart, self.RaycastParams)
				local slopeMultiplier
				if slopeDegrees >= landingBoostConfig.SlopeThreshold then
					-- Landing on a slope - use full boost
					slopeMultiplier = landingBoostConfig.SlopeBoostMultiplier
				else
					-- Landing on flat ground - use reduced boost
					slopeMultiplier = landingBoostConfig.FlatBoostMultiplier
				end

				local baseBonus = fallDistance * landingBoostConfig.BoostMultiplier
				airborneBonus = math.min(baseBonus * slopeMultiplier, landingBoostConfig.MaxBoost)
				LogService:Info("SLIDING", "Buffered slide landing boost", {
					AirTime = airTime,
					FallDistance = fallDistance,
					PeakY = self.AirbornePeakY,
					CurrentY = self.PrimaryPart.Position.Y,
					Bonus = airborneBonus,
					SlopeDegrees = math.floor(slopeDegrees * 10) / 10,
					SlopeMultiplier = slopeMultiplier,
				})
			end
		end

		-- Use current movement direction instead of buffered direction
		-- movementDirection is already passed in from current input, don't override it
	end

	-- Transition to sliding state
	if not MovementStateManager:TransitionTo(MovementStateManager.States.Sliding) then
		LogService:Warn("SLIDING", "Failed to transition to sliding state")
		return false
	end

	-- Set cooldown at slide START (not end) so holding doesn't extend cooldown
	self.LastSlideEndTime = tick()

	-- Preserve configured amount of current horizontal momentum
	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
	local currentHorizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local preservedMomentum = currentHorizontalVelocity.Magnitude * Config.Gameplay.Sliding.StartMomentumPreservation

	-- Determine slide direction based on movement direction (directional sliding enabled by default)
	local slideDirection
	if movementDirection.Magnitude < 0.001 then
		-- Use character facing direction if no valid movement input
		local lookVector = self.PrimaryPart.CFrame.LookVector
		slideDirection = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	else
		slideDirection = movementDirection.Unit
	end

	-- WALL CHECK: Prevent sliding into ANY wall from any direction at slide start
	local isHittingWall = MovementUtils:CheckWallStop(self.PrimaryPart, self.RaycastParams, slideDirection)
	if isHittingWall then
		LogService:Debug("SLIDING", "Slide cancelled - sliding into wall")
		return false
	end

	self.IsSliding = true
	self.SlideVelocity = Config.Gameplay.Sliding.InitialVelocity + airborneBonus + preservedMomentum
	self.SlideDirection = slideDirection
	self.OriginalSlideDirection = slideDirection
	
	-- STANDSTILL SLIDE FIX: Apply immediate velocity if starting without momentum
	-- Use BodyVelocity for network-friendly application (works in Team Test)
	if currentHorizontalVelocity.Magnitude < 5 then
		-- Check if we're at an edge (not fully grounded in the forward direction)
		local edgeCheckRay = workspace:Raycast(
			self.PrimaryPart.Position + slideDirection * 2,
			Vector3.new(0, -3, 0),
			self.RaycastParams
		)
		local isAtEdge = (edgeCheckRay == nil)
		
		local immediateVelocity = slideDirection * self.SlideVelocity
		
		-- Create temporary BodyVelocity to ensure velocity is applied across network
		local initVel = Instance.new("BodyVelocity")
		initVel.Name = "SlideInitVelocity"
		
		-- Allow Y movement at edges so player can slide off
		if isAtEdge then
			initVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge) -- Full 3D control at edges
			-- Add slight downward push at edge
			initVel.Velocity = Vector3.new(immediateVelocity.X, -10, immediateVelocity.Z)
		else
			initVel.MaxForce = Vector3.new(math.huge, 0, math.huge) -- Horizontal only on flat ground
			initVel.Velocity = Vector3.new(immediateVelocity.X, 0, immediateVelocity.Z)
		end
		initVel.Parent = self.PrimaryPart
		
		-- Also set AssemblyLinearVelocity for immediate effect
		if isAtEdge then
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
				immediateVelocity.X,
				math.min(self.PrimaryPart.AssemblyLinearVelocity.Y, -10),
				immediateVelocity.Z
			)
		else
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
				immediateVelocity.X,
				self.PrimaryPart.AssemblyLinearVelocity.Y,
				immediateVelocity.Z
			)
		end
		
		-- Remove after a short time (will be replaced by SlideBodyVelocity)
		task.delay(0.1, function()
			if initVel and initVel.Parent then
				initVel:Destroy()
			end
		end)
	end

	-- IMPULSE SLIDE: Apply explosive speed boost ("The Pop")
	-- Only apply when player has existing momentum (prevents glitch on standstill slides)
	local impulseConfig = Config.Gameplay.Sliding.ImpulseSlide
	local hasExistingMomentum = currentHorizontalVelocity.Magnitude > 5 -- Minimum speed to apply impulse
	if impulseConfig and impulseConfig.Enabled and hasExistingMomentum then
		local mass = self.PrimaryPart.AssemblyMass
		local impulseMagnitude = mass * impulseConfig.ImpulsePower
		local impulseVector = slideDirection * impulseMagnitude

		-- Apply instant physics burst
		self.PrimaryPart:ApplyImpulse(impulseVector)

		-- Zero friction for gliding
		local glideProps = PhysicalProperties.new(0.01, impulseConfig.SlideFriction, 0, 100, 100)
		self.PrimaryPart.CustomPhysicalProperties = glideProps

		-- Debug output
		print("Slide Impulse Applied:", impulseMagnitude)
	end

	-- Play landing boost sound if airborne bonus was applied
	if airborneBonus > 0 then
		self:PlayLandingBoostSound()
	end

	-- CREATE SLIDE TRAIL EFFECT
	self:CreateSlideTrail()

	-- START SLIDE VFX (continuous - follows player during slide)
	VFXController:StartContinuousVFXReplicated("Slide", self.PrimaryPart)

	-- TRIGGER SLIDE FOV EFFECT
	FOVController:AddEffect("Slide")

	-- Clear buffered state and set cooldown skip flag
	if wasBuffered then
		local wasFromJumpCancel = self.IsSlideBufferFromJumpCancel
		self.CurrentSlideSkipsCooldown = wasFromJumpCancel -- Track if current slide should skip cooldown
		self.IsSlideBuffered = false

		-- Clear bypass flags when slide actually starts (successful execution)
		if wasFromJumpCancel then
			self.SlideBypassCooldown = 0
		end
		self.BufferedSlideDirection = Vector3.new(0, 0, 0)
		self.SlideBufferStartTime = 0
		self.IsSlideBufferFromJumpCancel = false
	end

	-- Store initial camera angle for relative steering and Y position for slope detection
	if currentCameraAngle then
		self.LastCameraAngle = currentCameraAngle
	elseif self.CameraController then
		local cameraAngles = self.CameraController:GetCameraAngles()
		self.LastCameraAngle = cameraAngles.X
	end
	self.PreviousY = self.PrimaryPart.Position.Y

	-- Keep original direction - no forcing

	-- Apply initial slide velocity immediately with frame-rate independent deltaTime
	local estimatedDeltaTime = 1 / 60 -- Default to 60fps assumption if no history
	if self.SlideUpdateConnection then
		-- Use last known deltaTime from previous slide if available
		estimatedDeltaTime = self.LastKnownDeltaTime or (1 / 60)
	end
	self:ApplySlideVelocity(estimatedDeltaTime)

	-- Start slide update loop
	self:StartSlideUpdate()

	return true
end

function SlidingSystem:StopSlide(transitionToCrouch, _removeVisualCrouchImmediately)
	-- Store slide stop info for coyote time jump cancel
	self.LastSlideStopTime = tick()
	self.SlideStopDirection = self.SlideDirection
	self.SlideStopVelocity = self.SlideVelocity

	-- Don't set cooldown on slide end - cooldown is set at slide START (line 329)
	-- This prevents holding slide from extending the cooldown duration

	-- Clear slide physics
	local slideBodyVel = self.PrimaryPart and self.PrimaryPart:FindFirstChild("SlideBodyVelocity")
	if slideBodyVel then
		slideBodyVel:Destroy()
	end

	-- Clear state
	self.IsSliding = false
	self.SlideVelocity = 0
	self.SlideDirection = Vector3.new(0, 0, 0)
	self.OriginalSlideDirection = Vector3.new(0, 0, 0)

	-- RESET friction after slide ends (stop gliding)
	if self.PrimaryPart then
		self.PrimaryPart.CustomPhysicalProperties = nil -- Resets to default
	end

	-- Reset airborne tracking
	self.IsAirborne = false
	self.AirborneStartTime = 0
	self.AirborneStartY = 0
	self.AirbornePeakY = 0
	self.WasAirborneLastFrame = false

	-- Reset rig rotation smoothly
	RigRotationUtils:ResetRigRotation(self.Character, self.PrimaryPart, true)

	-- Stop update loop
	if self.SlideUpdateConnection then
		self.SlideUpdateConnection:Disconnect()
		self.SlideUpdateConnection = nil
	end

	-- REMOVE SLIDE TRAIL EFFECT
	self:RemoveSlideTrail()

	-- STOP SLIDE VFX
	VFXController:StopContinuousVFX("Slide")

	-- REMOVE SLIDE FOV EFFECT
	FOVController:RemoveEffect("Slide")

	-- Restore default responsiveness after slide ends
	if self.AlignOrientation then
		self.AlignOrientation.Responsiveness = Config.Controls.Camera.Smoothness or 25
	end

	-- Force rotation update to camera direction when slide ends
	if self.CharacterController then
		-- Clear last camera angles cache to force rotation update on next frame
		self.CharacterController.LastCameraAngles = nil
		self.CharacterController.CameraRotationChanged = true
	end

	-- Update movement state (visual crouch handled automatically by state manager)
	if transitionToCrouch then
		MovementStateManager:TransitionTo(MovementStateManager.States.Crouching)
	else
		-- FORCE VISUAL CROUCH REMOVAL: Always remove crouch visuals when transitioning to standing
		local CrouchUtils = require(Locations.Modules.Systems.Character.CrouchUtils)
		if self.Character then
			CrouchUtils:Uncrouch(self.Character) -- Reset internal state
			CrouchUtils:RemoveVisualCrouch(self.Character) -- Reset visuals
		end
		
		-- Check if player is still holding sprint key or has auto-sprint enabled
		local shouldRestoreSprint = false
		if self.CharacterController then
			local autoSprint = Config.Gameplay.Character.AutoSprint
			shouldRestoreSprint = self.CharacterController.IsSprinting or autoSprint
		end

		if shouldRestoreSprint then
			MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
		else
			MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
		end
	end

	-- Don't clear character references during slide stop - keep them for next slide
	-- References should only be cleared during character cleanup, not individual slide stops
end

function SlidingSystem:StartSlideUpdate()
	if self.SlideUpdateConnection then
		self.SlideUpdateConnection:Disconnect()
	end

	self.SlideUpdateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:UpdateSlide(deltaTime)
	end)
end

function SlidingSystem:UpdateSlide(deltaTime)
	-- Store deltaTime for frame-rate independent initial velocity application
	self.LastKnownDeltaTime = deltaTime

	-- While buffering, only update airborne peak height tracking - skip slide physics
	if self.IsSlideBuffered then
		-- Still need to track peak height for landing boost during buffering
		if self.IsAirborne and self.PrimaryPart then
			self.AirbornePeakY = math.max(self.AirbornePeakY, self.PrimaryPart.Position.Y)
		end
		
		-- RIVALS-STYLE AIRBORNE BUFFER: Floating phase then heavy pull-down
		if self.PrimaryPart and not self:CheckGroundedForSliding() then
			local airborneTime = tick() - self.AirborneStartTime
			local baseDownforce = Config.Gameplay.Character.AirborneSlideDownforce or 600
			local floatDuration = Config.Gameplay.Sliding.FloatDuration or 0.7
			local effectiveDownforce
			
			if airborneTime < floatDuration then
				-- FLOATING PHASE: Light gravity for hang time feel
				local floatMultiplier = Config.Gameplay.Sliding.FloatGravityMultiplier or 0.3
				effectiveDownforce = baseDownforce * floatMultiplier
			else
				-- HEAVY PHASE: After float duration, slam down hard
				local timeAfterFloat = airborneTime - floatDuration
				local progressiveMultiplier = 2 + (timeAfterFloat * 8) -- Starts at 2x, ramps up 8x per second
				effectiveDownforce = baseDownforce * math.min(progressiveMultiplier, 10) -- Cap at 10x
			end
			
			local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
			local newYVelocity = currentVelocity.Y - (effectiveDownforce * deltaTime)
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, newYVelocity, currentVelocity.Z)
		end
		
		return
	end

	-- Check if we're still sliding using internal state (don't rely on state manager during update)
	-- The state manager can be externally modified, causing premature slide stops
	if not self.IsSliding or not self.PrimaryPart then
		self:StopSlide(false) -- false = transition to standing (not crouch)
		return
	end

	-- WALL CHECK: Stop slide if hitting a wall from any direction during sliding
	local isHittingWall = MovementUtils:CheckWallStop(self.PrimaryPart, self.RaycastParams, self.SlideDirection)
	if isHittingWall then
		LogService:Debug("SLIDING", "Slide stopped - hitting wall during slide")
		self:StopSlide(false)
		return
	end

	-- Use sliding config
	local slideConfig = Config.Gameplay.Sliding

	-- UPDATE SLIDE VFX position and orientation to follow player
	if self.PrimaryPart and VFXController:IsContinuousVFXActive("Slide") then
		VFXController:UpdateContinuousVFXOrientation("Slide", self.SlideDirection and self.SlideDirection * 10 or self.PrimaryPart.CFrame.LookVector * 10, self.PrimaryPart)
	end

	-- Use deltaTime directly for consistent physics across all framerates
	local cappedDeltaTime = deltaTime

	-- Track if airborne state changed
	local wasAirborneLastFrame = self.WasAirborneLastFrame
	local isGrounded = self:CheckGroundedForSliding()
	local isAirborne = not isGrounded

	-- Update airborne tracking
	if isAirborne and not wasAirborneLastFrame then
		-- Just became airborne
		self.IsAirborne = true
		self.AirborneStartTime = tick()
		self.AirborneStartY = self.PrimaryPart.Position.Y
		self.AirbornePeakY = self.PrimaryPart.Position.Y
	elseif isAirborne and wasAirborneLastFrame then
		-- Continue tracking airborne
		self.AirbornePeakY = math.max(self.AirbornePeakY, self.PrimaryPart.Position.Y)
	elseif not isAirborne and wasAirborneLastFrame then
		-- Just landed - check for landing boost
		local airTime = tick() - self.AirborneStartTime
		local fallDistance = self.AirbornePeakY - self.PrimaryPart.Position.Y

		self.HasLandedAfterJumpCancel = self.JumpCancelPerformed

		-- Apply landing boost for active slides (only if enabled)
		local landingBoostConfig = Config.Gameplay.Sliding.LandingBoost
		if landingBoostConfig.Enabled ~= false then -- Default to true for backwards compat
			if
				airTime > landingBoostConfig.MinAirTime
				and fallDistance > landingBoostConfig.MinFallDistance
			then
				-- Check slope angle at landing position to determine boost multiplier
				local _, _, slopeDegrees =
					MovementUtils:CheckGroundedWithSlope(self.Character, self.PrimaryPart, self.RaycastParams)
				local slopeMultiplier
				if slopeDegrees >= landingBoostConfig.SlopeThreshold then
					-- Landing on a slope - use full boost
					slopeMultiplier = landingBoostConfig.SlopeBoostMultiplier
				else
					-- Landing on flat ground - use reduced boost
					slopeMultiplier = landingBoostConfig.FlatBoostMultiplier
				end

				local baseLandingBoost = fallDistance * landingBoostConfig.BoostMultiplier
				local landingBoost =
					math.min(baseLandingBoost * slopeMultiplier, landingBoostConfig.MaxBoost)

				-- Apply landing boost (momentum preservation only for slide start, not active slide landings)
				self.SlideVelocity = self.SlideVelocity + landingBoost

				-- Play landing boost sound
				self:PlayLandingBoostSound()
			end
		end
		
		-- ALWAYS preserve minimum velocity when landing from airborne slide
		-- This prevents sudden stops when sliding from edge onto flat ground
		local minLandingVelocity = Config.Gameplay.Sliding.MinLandingVelocity or 15
		if self.SlideVelocity < minLandingVelocity then
			self.SlideVelocity = minLandingVelocity
		end
	end

	self.WasAirborneLastFrame = isAirborne

	-- Handle airborne vs grounded physics differently
	if isAirborne then
		-- When airborne: skip friction and slope changes, maintain velocity for realistic momentum

		-- Continue sliding while airborne - no velocity restrictions!
		-- Update slide direction based on camera input
		self:UpdateSlideDirection()

		-- Apply air resistance to slide velocity while airborne (proportional to current velocity)
		-- NOTE: Use slide-specific air drag, NOT Config.Gameplay.Character.AirResistance
		-- AirResistance is VERY HIGH (25+) to prevent direction changes - it would destroy slide velocity instantly
		if self.SlideVelocity > 0 then
			local slideAirDrag = 0.12 -- Gentle slide-specific air drag (much lower than character AirResistance)
			self.SlideVelocity = self.SlideVelocity * (1 - slideAirDrag * cappedDeltaTime)
		end

		-- RIVALS-STYLE AIRBORNE SLIDE: Floating phase then heavy pull-down
		local airborneTime = tick() - self.AirborneStartTime
		local baseDownforce = Config.Gameplay.Character.AirborneSlideDownforce or 600
		local floatDuration = Config.Gameplay.Sliding.FloatDuration or 0.7
		local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
		local effectiveDownforce
		
		if airborneTime < floatDuration then
			-- FLOATING PHASE: Light gravity for hang time feel
			local floatMultiplier = Config.Gameplay.Sliding.FloatGravityMultiplier or 0.3
			effectiveDownforce = baseDownforce * floatMultiplier
		else
			-- HEAVY PHASE: After float duration, slam down hard
			local timeAfterFloat = airborneTime - floatDuration
			local progressiveMultiplier = 2 + (timeAfterFloat * 8) -- Starts at 2x, ramps up 8x per second
			effectiveDownforce = baseDownforce * math.min(progressiveMultiplier, 10) -- Cap at 10x
		end

		-- MOVEMENT CHECK: Cancel slide if not moving at all (only after float phase ends)
		-- Now checks TOTAL movement (including falling) not just horizontal
		local slideTimeoutConfig = Config.Gameplay.Sliding.SlideTimeout
		if slideTimeoutConfig and slideTimeoutConfig.Enabled and airborneTime > floatDuration then
			if not self.LastDistanceCheckTime or (tick() - self.LastDistanceCheckTime) > slideTimeoutConfig.DistanceCheckInterval then
				self.LastDistanceCheckTime = tick()
				
				local currentPos = self.PrimaryPart.Position
				if self.LastCheckPosition then
					-- Use FULL 3D distance (includes falling) instead of horizontal-only
					local distanceMoved = (currentPos - self.LastCheckPosition).Magnitude
					
					-- If barely moved at all (including vertically), cancel slide
					if distanceMoved < (slideTimeoutConfig.MinMovementDistance * slideTimeoutConfig.DistanceCheckInterval) then
						self:StopSlide(false)
						return
					end
				end
				self.LastCheckPosition = currentPos
			end
		end

		-- Apply downward force
		local newYVelocity = currentVelocity.Y - (effectiveDownforce * cappedDeltaTime)

		-- Preserve horizontal velocity, only modify vertical
		self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, newYVelocity, currentVelocity.Z)

		-- Update character rotation to face slide direction
		self:UpdateSlideRotation()

		-- Get camera direction for tilt calculation
		local cameraDirection
		if self.CameraController then
			local cameraAngles = self.CameraController:GetCameraAngles()
			local cameraDirAngle = math.rad(cameraAngles.X)
			cameraDirection = Vector3.new(math.sin(cameraDirAngle), 0, math.cos(cameraDirAngle))
		end

		-- Update rig rotation for airborne state (velocity-based tilt)
		RigRotationUtils:UpdateRigRotation(
			self.Character,
			self.PrimaryPart,
			self.SlideDirection,
			self.RaycastParams,
			cappedDeltaTime,
			cameraDirection
		)

		-- Apply velocity directly to maintain momentum while airborne
		self:ApplySlideVelocity(cappedDeltaTime)

		-- Skip the rest of ground-based sliding logic
		return
	end

	-- We're grounded - apply normal ground-based physics

	-- Apply friction as multiplier reduction (like original working version)
	-- Convert velocity to multiplier, apply friction, then convert back
	local currentMultiplier = self.SlideVelocity / slideConfig.InitialVelocity
	local frictionAmount = slideConfig.FrictionRate * cappedDeltaTime
	currentMultiplier = math.max(0, currentMultiplier - frictionAmount)
	self.SlideVelocity = currentMultiplier * slideConfig.InitialVelocity

	-- Calculate and apply slope-based multiplier changes (like reference implementation)
	local multiplierChange = self:CalculateSlopeMultiplierChange(cappedDeltaTime, slideConfig)

	-- Apply multiplier change to current velocity (like reference system)
	if multiplierChange ~= 0 then
		-- Convert current velocity to a "multiplier" relative to initial velocity
		currentMultiplier = self.SlideVelocity / slideConfig.InitialVelocity
		local newMultiplier =
			math.clamp(currentMultiplier + multiplierChange, 0, slideConfig.MaxVelocity / slideConfig.InitialVelocity)
		self.SlideVelocity = newMultiplier * slideConfig.InitialVelocity
	end

	-- Clamp velocity to reasonable bounds
	self.SlideVelocity = math.clamp(self.SlideVelocity, 0, slideConfig.MaxVelocity)

	-- Update slide direction for steering
	self:UpdateSlideDirection()

	-- Update character rotation to face slide direction
	self:UpdateSlideRotation()

	-- Get camera direction for tilt calculation
	local cameraDirection
	if self.CameraController then
		local cameraAngles = self.CameraController:GetCameraAngles()
		local cameraDirAngle = math.rad(cameraAngles.X)
		cameraDirection = Vector3.new(math.sin(cameraDirAngle), 0, math.cos(cameraDirAngle))
	end

	-- Update rig rotation to tilt on slopes
	RigRotationUtils:UpdateRigRotation(
		self.Character,
		self.PrimaryPart,
		self.SlideDirection,
		self.RaycastParams,
		cappedDeltaTime,
		cameraDirection
	)

	-- Apply velocity
	self:ApplySlideVelocity(cappedDeltaTime)

	-- Stop slide if too slow - ALWAYS stand up (never transition to crouch)
	if self.SlideVelocity <= slideConfig.MinVelocity then
		self:StopSlide(false) -- false = transition to standing (user request: "stand up when slide ends")
		return
	end
end

function SlidingSystem:GetSlideInfo()
	return {
		IsSliding = self.IsSliding,
		IsSlideBuffered = self.IsSlideBuffered,
		SlideVelocity = self.SlideVelocity,
		SlideDirection = self.SlideDirection,
		BufferedSlideDirection = self.BufferedSlideDirection,
		IsAirborne = self.IsAirborne,
		LastSlideEndTime = self.LastSlideEndTime,
		JumpCancelPerformed = self.JumpCancelPerformed,
	}
end

function SlidingSystem:GetCurrentSlideAnimationName()
	if not self.CameraController or not self.IsSliding then
		return "SlidingForward" -- Default fallback
	end

	-- Get camera direction
	local cameraAngles = self.CameraController:GetCameraAngles()
	local cameraDirAngle = math.rad(cameraAngles.X)
	local cameraDirection = Vector3.new(math.sin(cameraDirAngle), 0, math.cos(cameraDirAngle))

	-- Get appropriate animation name based on slide direction
	local animationName = SlideDirectionDetector:GetSlideAnimationName(cameraDirection, self.SlideDirection)

	return animationName
end

function SlidingSystem:Cleanup()
	-- Stop any active slides and cancel any buffers
	if self.IsSliding then
		self:StopSlide(false, true) -- false = don't transition to crouch, true = remove visual
	end

	-- Cancel any active buffers
	if self.IsSlideBuffered then
		self:CancelSlideBuffer("Character cleanup/despawn")
	end
	if self.IsJumpCancelBuffered then
		self:CancelJumpCancelBuffer()
	end

	-- Reset jump cancel flags
	self.JumpCancelPerformed = false
	self.HasLandedAfterJumpCancel = false

	-- Reset coyote time tracking
	self.LastSlideStopTime = 0
	self.SlideStopDirection = Vector3.new(0, 0, 0)
	self.SlideStopVelocity = 0

	-- Cleanup rig rotation state
	if self.Character then
		RigRotationUtils:Cleanup(self.Character)
	end

	-- Clear character references
	self.Character = nil
	self.PrimaryPart = nil
	self.VectorForce = nil
	self.AlignOrientation = nil
	self.RaycastParams = nil
	self.CharacterController = nil
end

return SlidingSystem
