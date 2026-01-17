local SlidingBuffer = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local TestMode = require(ReplicatedStorage.TestMode)

-- Reference to main SlidingSystem (will be set by SlidingSystem:Init)
SlidingBuffer.SlidingSystem = nil

function SlidingBuffer:Init(slidingSystem)
	self.SlidingSystem = slidingSystem
	LogService:Info("SLIDING", "SlidingBuffer initialized")
end

function SlidingBuffer:CanBufferSlide(movementInput, isCrouching, isGrounded, characterController)
	-- Check slide cooldown (simple and direct)
	local currentTime = tick()
	local timeSinceLastSlide = currentTime - self.SlidingSystem.LastSlideEndTime

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "CanBufferSlide CHECK", {
			TimeSinceLastSlide = string.format("%.3f", timeSinceLastSlide),
			CooldownRequired = Config.Gameplay.Cooldowns.Slide,
			CooldownOK = timeSinceLastSlide >= Config.Gameplay.Cooldowns.Slide,
			IsGrounded = isGrounded,
			IsCrouching = isCrouching,
			MovementMagnitude = movementInput.Magnitude,
			IsSliding = self.SlidingSystem.IsSliding,
			IsSlideBuffered = self.SlidingSystem.IsSlideBuffered,
			AlreadyActive = self.SlidingSystem.IsSliding or self.SlidingSystem.IsSlideBuffered,
		})
	end

	-- Check cooldown
	if timeSinceLastSlide < Config.Gameplay.Cooldowns.Slide then
		return false,
			"Cooldown active ("
				.. string.format("%.3f", timeSinceLastSlide)
				.. "s < "
				.. Config.Gameplay.Cooldowns.Slide
				.. "s)"
	end

	-- Must not be grounded (airborne)
	if isGrounded then
		return false, "Must be airborne to buffer slide"
	end

	-- Must be crouching
	if not isCrouching then
		return false, "Not crouching"
	end

	-- Must not be in uncrouch checking loop (prevents buffering while trying to uncrouch under obstruction)
	if characterController and characterController.WantsToUncrouch then
		return false, "In uncrouch check - cannot buffer slide while trying to uncrouch"
	end

	-- Movement input is always allowed for slide buffering (no speed requirement)

	-- Must not already be sliding or buffering
	if self.SlidingSystem.IsSliding or self.SlidingSystem.IsSlideBuffered then
		return false,
			"Already sliding (" .. tostring(self.SlidingSystem.IsSliding) .. ") or buffered (" .. tostring(
				self.SlidingSystem.IsSlideBuffered
			) .. ")"
	end

	return true, "Can buffer slide"
end


function SlidingBuffer:StartSlideBuffer(movementDirection, fromJumpCancel)
	if not self.SlidingSystem.PrimaryPart then
		LogService:Warn("SLIDING", "Cannot start slide buffer - missing character components")
		return false
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "SLIDE BUFFER STARTED", {
			BufferedDirection = movementDirection.Unit,
			PreviousBufferState = self.SlidingSystem.IsSlideBuffered,
			AirbornePosition = self.SlidingSystem.PrimaryPart.Position.Y,
			Timestamp = tick(),
		})
	end

	self.SlidingSystem.IsSlideBuffered = true
	self.SlidingSystem.BufferedSlideDirection = movementDirection.Unit
	self.SlidingSystem.SlideBufferStartTime = tick()
	self.SlidingSystem.IsSlideBufferFromJumpCancel = fromJumpCancel or false

	-- Apply visual crouch during buffer for better player feedback
	local CrouchUtils = require(Locations.Modules.Systems.Character.CrouchUtils)
	local character = self.SlidingSystem.Character
	if character and not CrouchUtils:IsVisuallycrouched(character) then
		CrouchUtils:ApplyVisualCrouch(character, true) -- Skip clearance check during buffer
		local RemoteEvents = require(Locations.Modules.RemoteEvents)
		RemoteEvents:FireServer("CrouchStateChanged", true)
	end

	-- Start airborne tracking immediately for potential landing boost
	self.SlidingSystem.IsAirborne = true
	self.SlidingSystem.AirborneStartTime = tick()
	self.SlidingSystem.AirborneStartY = self.SlidingSystem.PrimaryPart.Position.Y
	self.SlidingSystem.AirbornePeakY = self.SlidingSystem.PrimaryPart.Position.Y

	-- START THE SLIDE UPDATE LOOP: This is critical for progressive downforce to run during buffer
	-- Without this, UpdateSlide() never runs and the player just falls with normal gravity
	self.SlidingSystem:StartSlideUpdate()

	return true
end

function SlidingBuffer:CancelSlideBuffer(reason)
	if not self.SlidingSystem.IsSlideBuffered then
		return false, "No slide buffer active"
	end

	local cancellationReason = reason or "Manual cancellation or timeout"
	LogService:Info("SLIDING", "SLIDE BUFFER CANCELLED", {
		BufferDuration = tick() - self.SlidingSystem.SlideBufferStartTime,
		BufferedDirection = self.SlidingSystem.BufferedSlideDirection,
		Reason = cancellationReason,
		CallStack = debug.traceback("", 2),
	})

	-- Check if we borrowed a cooldown that needs to be restored
	local currentTime = tick()
	local slideAge = currentTime - self.SlidingSystem.LastSlideEndTime

	if slideAge < 5 then -- We borrowed this cooldown recently
		-- Restore the borrowed cooldown to a safe old time (consistent with jump cancel reset)
		local resetTime = currentTime - 15
		self.SlidingSystem.LastSlideEndTime = resetTime
		LogService:Debug("SLIDING", "Restored borrowed slide cooldown on buffer cancel", {
			SlideAge = slideAge,
			RestoredTime = resetTime,
		})
	end

	self.SlidingSystem.IsSlideBuffered = false
	self.SlidingSystem.BufferedSlideDirection = Vector3.new(0, 0, 0)
	self.SlidingSystem.SlideBufferStartTime = 0
	self.SlidingSystem.IsSlideBufferFromJumpCancel = false

	-- Remove visual crouch when buffer is cancelled
	local CrouchUtils = require(Locations.Modules.Systems.Character.CrouchUtils)
	local character = self.SlidingSystem.Character
	if character and CrouchUtils:IsVisuallycrouched(character) then
		CrouchUtils:RemoveVisualCrouch(character)
		local RemoteEvents = require(Locations.Modules.RemoteEvents)
		RemoteEvents:FireServer("CrouchStateChanged", false)
	end

	-- Transition to appropriate state (restore sprint if still held)
	local shouldRestoreSprint = false
	if self.SlidingSystem.CharacterController then
		local autoSprint = Config.Gameplay.Character.AutoSprint
		shouldRestoreSprint = self.SlidingSystem.CharacterController.IsSprinting or autoSprint
	end

	if shouldRestoreSprint then
		MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
	else
		MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
	end

	-- Reset airborne tracking and wall detection
	self.SlidingSystem.IsAirborne = false
	self.SlidingSystem.AirborneStartTime = 0
	self.SlidingSystem.AirborneStartY = 0
	self.SlidingSystem.AirbornePeakY = 0
	self.SlidingSystem.WallDetectionActive = false
	self.SlidingSystem.WasAirborneLastFrame = false

	-- STOP the slide update loop that was started with the buffer
	if self.SlidingSystem.SlideUpdateConnection then
		self.SlidingSystem.SlideUpdateConnection:Disconnect()
		self.SlidingSystem.SlideUpdateConnection = nil
	end

	return true, "Slide buffer canceled"
end

function SlidingBuffer:TransferSlideCooldownToCrouch(characterController)
	-- For buffering system: always allow transfer since slide cooldown was "borrowed"
	-- The actual slide cooldown time becomes the crouch cooldown
	local slideEndTime = self.SlidingSystem.LastSlideEndTime

	-- Only transfer if we actually have a borrowed cooldown (not the reset value)
	local currentTime = tick()
	local slideAge = currentTime - slideEndTime

	if slideAge < 5 then -- Only transfer if cooldown was recently borrowed (not reset)
		-- Transfer successful - reset slide cooldown and apply crouch cooldown with same timestamp
		local resetTime = currentTime - 15 -- Reset slide cooldown to old time (consistent with jump cancel reset)
		self.SlidingSystem.LastSlideEndTime = resetTime
		characterController.LastCrouchTime = slideEndTime -- Apply crouch cooldown with borrowed time

		LogService:Info("SLIDING", "Slide cooldown transferred to crouch", {
			TransferTime = slideEndTime,
			CurrentTime = currentTime,
			SlideAge = slideAge,
		})
	else
		-- Cooldown was already reset, no need to transfer
		LogService:Debug("SLIDING", "Slide cooldown already reset, no transfer needed", {
			SlideAge = slideAge,
		})
	end

	return true -- Transfer always successful for buffering
end

function SlidingBuffer:CanBufferJumpCancel()
	-- Check if jump cancel is enabled
	if not Config.Gameplay.Sliding.JumpCancel.Enabled then
		return false, "Jump cancel is disabled"
	end

	-- Must be currently sliding
	if not MovementStateManager:IsSliding() then
		return false, "Not sliding"
	end

	-- Immediate buffering allowed with cooldown transfer system

	-- Must not already be buffering jump cancel
	if self.SlidingSystem.IsJumpCancelBuffered then
		return false, "Already buffering jump cancel"
	end

	return true, "Can buffer jump cancel"
end

function SlidingBuffer:StartJumpCancelBuffer()
	if not self.SlidingSystem.PrimaryPart then
		LogService:Warn("SLIDING", "Cannot start jump cancel buffer - missing character components")
		return false
	end

	self.SlidingSystem.IsJumpCancelBuffered = true
	self.SlidingSystem.BufferedJumpCancelDirection = self.SlidingSystem.SlideDirection
	self.SlidingSystem.JumpCancelBufferStartTime = tick()

	-- Start airborne tracking for potential landing
	self.SlidingSystem.IsAirborne = true
	self.SlidingSystem.AirborneStartTime = tick()
	self.SlidingSystem.AirborneStartY = self.SlidingSystem.PrimaryPart.Position.Y
	self.SlidingSystem.AirbornePeakY = self.SlidingSystem.PrimaryPart.Position.Y

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "JUMP CANCEL BUFFERED", {
			Direction = self.SlidingSystem.BufferedJumpCancelDirection,
			AirborneStartY = self.SlidingSystem.AirborneStartY,
			BufferStartTime = self.SlidingSystem.JumpCancelBufferStartTime,
			SlideVelocity = self.SlidingSystem.SlideVelocity,
			IsSliding = MovementStateManager:IsSliding(),
		})
	end

	return true
end

function SlidingBuffer:CancelJumpCancelBuffer()
	if not self.SlidingSystem.IsJumpCancelBuffered then
		return
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("SLIDING", "JUMP CANCEL BUFFER CANCELLED", {
			BufferDuration = tick() - self.SlidingSystem.JumpCancelBufferStartTime,
			BufferedDirection = self.SlidingSystem.BufferedJumpCancelDirection,
			CallStack = debug.traceback("", 2),
		})
	end

	self.SlidingSystem.IsJumpCancelBuffered = false
	self.SlidingSystem.BufferedJumpCancelDirection = Vector3.new(0, 0, 0)
	self.SlidingSystem.JumpCancelBufferStartTime = 0
end

return SlidingBuffer
