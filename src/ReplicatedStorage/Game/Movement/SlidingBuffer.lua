local SlidingBuffer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))
local Net = require(Locations.Shared:WaitForChild("Net"):WaitForChild("Net"))

SlidingBuffer.SlidingSystem = nil

function SlidingBuffer:Init(slidingSystem)
	self.SlidingSystem = slidingSystem
	LogService:Info("SLIDING", "SlidingBuffer initialized")
end

function SlidingBuffer:CanBufferSlide(movementInput, isCrouching, isGrounded, characterController)
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

	if timeSinceLastSlide < Config.Gameplay.Cooldowns.Slide then
		return false,
			"Cooldown active ("
				.. string.format("%.3f", timeSinceLastSlide)
				.. "s < "
				.. Config.Gameplay.Cooldowns.Slide
				.. "s)"
	end

	if isGrounded then
		return false, "Must be airborne to buffer slide"
	end

	if not isCrouching then
		return false, "Not crouching"
	end

	if characterController and characterController.WantsToUncrouch then
		return false, "In uncrouch check - cannot buffer slide while trying to uncrouch"
	end

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

	local CrouchUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("CrouchUtils"))
	local character = self.SlidingSystem.Character
	if character and not CrouchUtils:IsVisuallycrouched(character) then
		CrouchUtils:ApplyVisualCrouch(character, true)
		Net:FireServer("CrouchStateChanged", true)
	end

	self.SlidingSystem.IsAirborne = true
	self.SlidingSystem.AirborneStartTime = tick()
	self.SlidingSystem.AirborneStartY = self.SlidingSystem.PrimaryPart.Position.Y
	self.SlidingSystem.AirbornePeakY = self.SlidingSystem.PrimaryPart.Position.Y

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

	local currentTime = tick()
	local slideAge = currentTime - self.SlidingSystem.LastSlideEndTime

	if slideAge < 5 then
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

	local CrouchUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("CrouchUtils"))
	local character = self.SlidingSystem.Character
	if character and CrouchUtils:IsVisuallycrouched(character) then
		CrouchUtils:RemoveVisualCrouch(character)
		Net:FireServer("CrouchStateChanged", false)
	end

	local shouldRestoreSprint = false
	if self.SlidingSystem.CharacterController then
		local autoSprint = false
		if self.SlidingSystem.CharacterController.IsAutoSprintEnabled then
			autoSprint = self.SlidingSystem.CharacterController:IsAutoSprintEnabled()
		elseif self.SlidingSystem.CharacterController._isAutoSprintEnabled then
			autoSprint = self.SlidingSystem.CharacterController:_isAutoSprintEnabled()
		end
		shouldRestoreSprint = self.SlidingSystem.CharacterController.IsSprinting or autoSprint
	end

	if shouldRestoreSprint then
		MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
	else
		MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
	end

	self.SlidingSystem.IsAirborne = false
	self.SlidingSystem.AirborneStartTime = 0
	self.SlidingSystem.AirborneStartY = 0
	self.SlidingSystem.AirbornePeakY = 0
	self.SlidingSystem.WallDetectionActive = false
	self.SlidingSystem.WasAirborneLastFrame = false

	if self.SlidingSystem.SlideUpdateConnection then
		self.SlidingSystem.SlideUpdateConnection:Disconnect()
		self.SlidingSystem.SlideUpdateConnection = nil
	end

	return true, "Slide buffer canceled"
end

function SlidingBuffer:TransferSlideCooldownToCrouch(characterController)
	local slideEndTime = self.SlidingSystem.LastSlideEndTime
	local currentTime = tick()
	local slideAge = currentTime - slideEndTime

	if slideAge < 5 then
		local resetTime = currentTime - 15
		self.SlidingSystem.LastSlideEndTime = resetTime
		characterController.LastCrouchTime = slideEndTime

		LogService:Info("SLIDING", "Slide cooldown transferred to crouch", {
			TransferTime = slideEndTime,
			CurrentTime = currentTime,
			SlideAge = slideAge,
		})
	else
		LogService:Debug("SLIDING", "Slide cooldown already reset, no transfer needed", {
			SlideAge = slideAge,
		})
	end

	return true
end

function SlidingBuffer:CanBufferJumpCancel()
	if not Config.Gameplay.Sliding.JumpCancel.Enabled then
		return false, "Jump cancel is disabled"
	end

	if not MovementStateManager:IsSliding() then
		return false, "Not sliding"
	end

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
