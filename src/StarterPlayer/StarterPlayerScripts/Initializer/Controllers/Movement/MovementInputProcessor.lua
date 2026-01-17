local MovementInputProcessor = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local SlidingSystem = require(Locations.Game:WaitForChild("Movement"):WaitForChild("SlidingSystem"))
local MovementUtils = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementUtils"))
local WallJumpUtils = require(Locations.Game:WaitForChild("Movement"):WaitForChild("WallJumpUtils"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))

MovementInputProcessor.JumpPressed = false
MovementInputProcessor.JumpExecuted = false
MovementInputProcessor.LastJumpTime = 0
MovementInputProcessor.WasGroundedLastFrame = false

MovementInputProcessor.CharacterController = nil

function MovementInputProcessor:Init(characterController)
	self.CharacterController = characterController
	self.LastJumpTime = tick() - 1

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("INPUT", "MovementInputProcessor initialized", {
			HasCharacterController = characterController ~= nil,
		})
	end
end

function MovementInputProcessor:IsJumping()
	return self.JumpPressed
end

function MovementInputProcessor:OnJumpPressed()
	local wasAlreadyPressed = self.JumpPressed
	self.JumpPressed = true

	if not wasAlreadyPressed then
		self.JumpExecuted = false
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("INPUT", "JUMP PRESSED", {
			CurrentState = MovementStateManager:GetCurrentState(),
			IsGrounded = self.CharacterController and self.CharacterController.IsGrounded or false,
			IsSliding = MovementStateManager:IsSliding(),
			IsSlideBuffered = SlidingSystem.IsSlideBuffered,
			WasAlreadyPressed = wasAlreadyPressed,
			WillProcess = not wasAlreadyPressed,
		})
	end

	if self.CharacterController and self.CharacterController.InputManager then
		local inputMode = self.CharacterController.InputManager.InputMode
		if (inputMode == "PC" or inputMode == "Controller") and not self.CharacterController:IsInCoyoteTime() then
			if MovementStateManager:IsSliding() then
				if TestMode.Logging.LogSlidingSystem then
					LogService:Info("INPUT", "Jump input allowed for jump cancel while airborne", {
						InputMode = inputMode,
						IsGrounded = self.CharacterController.IsGrounded,
						CurrentState = MovementStateManager:GetCurrentState(),
					})
				end
			else
				if TestMode.Logging.LogSlidingSystem then
					local timeSinceGrounded = tick() - self.CharacterController.LastGroundedTime
					LogService:Info("INPUT", "Jump input while airborne - will check for wall jump", {
						InputMode = inputMode,
						IsGrounded = self.CharacterController.IsGrounded,
						IsInCoyoteTime = self.CharacterController:IsInCoyoteTime(),
						TimeSinceGrounded = timeSinceGrounded,
						CoyoteTimeWindow = Config.Gameplay.Character.CoyoteTime,
						CurrentState = MovementStateManager:GetCurrentState(),
					})
				end
			end
		end
	end

	if not wasAlreadyPressed then
		self:ProcessJumpInput(true)
	end
end

function MovementInputProcessor:OnJumpReleased()
	self.JumpPressed = false
	self.JumpExecuted = false

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("INPUT", "JUMP RELEASED", {
			CurrentState = MovementStateManager:GetCurrentState(),
		})
	end
end

function MovementInputProcessor:UpdateAutoJump()
	local isMobileAutoJump = false
	if self.CharacterController and self.CharacterController.InputManager and self.CharacterController.InputManager.MobileControls then
		isMobileAutoJump = self.CharacterController.InputManager.MobileControls:IsAutoJumpActive()
	end

	if not isMobileAutoJump then
		return
	end

	local isGroundedNow = self.CharacterController.IsGrounded
	if not self.WasGroundedLastFrame and isGroundedNow and self.JumpExecuted then
		self.JumpExecuted = false

		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("INPUT", "Auto-jump: Landing detected, resetting jump state for next jump")
		end
	end

	self.WasGroundedLastFrame = isGroundedNow
end

function MovementInputProcessor:ProcessJumpInput(isImmediatePress)
	if not self.JumpPressed or self.JumpExecuted then
		return
	end

	if not self.CharacterController then
		return
	end

	isImmediatePress = isImmediatePress or false

	local currentState = MovementStateManager:GetCurrentState()

	if currentState == MovementStateManager.States.Sliding then
		self:HandleSlidingJump()
	elseif SlidingSystem:IsInJumpCancelCoyoteTime() then
		self:HandleCoyoteTimeJumpCancel()
	else
		self:HandleNormalJump(isImmediatePress)
	end
end

function MovementInputProcessor:HandleSlidingJump()
	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("INPUT", "PROCESSING SLIDING JUMP (Jump Cancel)", {
			IsSliding = MovementStateManager:IsSliding(),
			SlideVelocity = SlidingSystem.SlideVelocity,
		})
	end

	local jumpCancelExecuted = SlidingSystem:ExecuteJumpCancel(nil, self.CharacterController)
	if jumpCancelExecuted then
		self:MarkJumpExecuted()
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Jump cancel executed successfully")
		end
	else
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Jump cancel failed, stopping slide")
		end

		SlidingSystem:StopSlide(false, nil, "JumpCancelFailed")
	end
end

function MovementInputProcessor:HandleCoyoteTimeJumpCancel()
	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("INPUT", "PROCESSING COYOTE TIME JUMP CANCEL", {
			CurrentState = MovementStateManager:GetCurrentState(),
			TimeSinceSlideStop = tick() - SlidingSystem.LastSlideStopTime,
			CoyoteTime = Config.Gameplay.Sliding.JumpCancel.CoyoteTime,
			SlideStopVelocity = SlidingSystem.SlideStopVelocity,
			SlideStopDirection = SlidingSystem.SlideStopDirection,
		})
	end

	local jumpCancelExecuted = SlidingSystem:ExecuteJumpCancel(nil, self.CharacterController)
	if jumpCancelExecuted then
		self:MarkJumpExecuted()
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Coyote time jump cancel executed successfully")
		end
	else
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Coyote time jump cancel failed, falling back to normal jump")
		end
	end
end

function MovementInputProcessor:HandleNormalJump(isImmediatePress)
	if TestMode.Logging.LogSlidingSystem then
		local timeSinceGrounded = tick() - self.CharacterController.LastGroundedTime
		LogService:Info("INPUT", "PROCESSING NORMAL JUMP", {
			IsGrounded = self.CharacterController.IsGrounded,
			IsInCoyoteTime = self.CharacterController:IsInCoyoteTime(),
			TimeSinceGrounded = timeSinceGrounded,
			CoyoteTimeWindow = Config.Gameplay.Character.CoyoteTime,
			CurrentState = MovementStateManager:GetCurrentState(),
			IsImmediatePress = isImmediatePress,
			PrimaryPartPosition = self.CharacterController.PrimaryPart and self.CharacterController.PrimaryPart.Position or nil,
		})
	end

	local isInCoyoteTime = self.CharacterController:IsInCoyoteTime()
	local shouldAttemptWallJump = isImmediatePress and not self.CharacterController.IsGrounded and not isInCoyoteTime

	if TestMode.Logging.LogSlidingSystem then
		LogService:Debug("INPUT", "HandleNormalJump - Jump type decision", {
			IsGrounded = self.CharacterController.IsGrounded,
			IsInCoyoteTime = isInCoyoteTime,
			IsImmediatePress = isImmediatePress,
			ShouldAttemptWallJump = shouldAttemptWallJump,
		})
	end

	if isInCoyoteTime and not shouldAttemptWallJump then
		local currentTime = tick()
		local timeSinceLastJump = currentTime - self.LastJumpTime
		if timeSinceLastJump < Config.Gameplay.Cooldowns.Jump then
			if TestMode.Logging.LogSlidingSystem then
				LogService:Debug("INPUT", "Normal jump on cooldown", {
					TimeSinceLastJump = timeSinceLastJump,
					CooldownRequired = Config.Gameplay.Cooldowns.Jump,
				})
			end
			return
		end

		local jumpSucceeded = MovementUtils:ApplyJump(
			self.CharacterController.PrimaryPart,
			self.CharacterController.IsGrounded,
			self.CharacterController.Character,
			self.CharacterController.RaycastParams,
			self.CharacterController.MovementInput,
			self.CharacterController.CachedCameraYAngle
		)

		if jumpSucceeded then
			self:MarkJumpExecuted()
			if TestMode.Logging.LogSlidingSystem then
				LogService:Info("INPUT", "Normal jump executed successfully")
			end
			return
		else
			if TestMode.Logging.LogSlidingSystem then
				LogService:Info("INPUT", "Normal jump failed")
			end
		end
	elseif shouldAttemptWallJump then
		self:HandleWallJump()
	end
end

function MovementInputProcessor:HandleWallJump()
	if TestMode.Logging.LogSlidingSystem then
		LogService:Debug("INPUT", "Normal jump not available, attempting wall jump", {
			IsGrounded = self.CharacterController.IsGrounded,
			TimeSinceGrounded = tick() - self.CharacterController.LastGroundedTime,
		})
	end

	local cameraAngles = self.CharacterController.LastCameraAngles or Vector2.new(0, 0)
	local wallJumpSucceeded, wallData = WallJumpUtils:AttemptWallJump(
		self.CharacterController.Character,
		self.CharacterController.PrimaryPart,
		self.CharacterController.RaycastParams,
		cameraAngles,
		self.CharacterController
	)

	if wallJumpSucceeded then
		self:MarkJumpExecuted()

		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Wall jump executed successfully", {
				WallDistance = wallData and wallData.Distance or nil,
				WallPart = wallData and wallData.Part.Name or nil,
			})
		end
	else
		self:MarkJumpExecuted()

		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("INPUT", "Wall jump failed - no wall detected, marking as executed")
		end
	end
end

function MovementInputProcessor:MarkJumpExecuted()
	self.JumpExecuted = true
	self.LastJumpTime = tick()

	if TestMode.Logging.LogSlidingSystem then
		LogService:Debug("INPUT", "Jump marked as executed", {
			JumpTime = self.LastJumpTime,
		})
	end
end

function MovementInputProcessor:ShouldProcessJump()
	return self.JumpPressed and not self.JumpExecuted
end

function MovementInputProcessor:ClearJumpState()
	self.JumpPressed = false
	self.JumpExecuted = false

	if TestMode.Logging.LogSlidingSystem then
		LogService:Debug("INPUT", "Jump state cleared")
	end
end

return MovementInputProcessor
