local MovementInputProcessor = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local SlidingSystem = require(Locations.Modules.Systems.Movement.SlidingSystem)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local WallJumpUtils = require(Locations.Modules.Systems.Movement.WallJumpUtils)
local Config = require(Locations.Modules.Config)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local TestMode = require(Locations.Modules.TestMode)

-- Input state tracking
MovementInputProcessor.JumpPressed = false
MovementInputProcessor.JumpExecuted = false
MovementInputProcessor.LastJumpTime = 0
MovementInputProcessor.WasGroundedLastFrame = false -- Track grounded state for autojump

-- Reference to character controller
MovementInputProcessor.CharacterController = nil

function MovementInputProcessor:Init(characterController)
	self.CharacterController = characterController
	self.LastJumpTime = tick() - 1 -- Initialize to allow first jump

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
	-- Only reset JumpExecuted if this is a NEW press (wasn't already pressed)
	-- This prevents held inputs from re-triggering wall jumps
	local wasAlreadyPressed = self.JumpPressed
	self.JumpPressed = true

	-- Only reset executed state on a fresh press, not while holding
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

	-- Immediate grounded/coyote time check for PC/Controller (but allow jump cancels during active slides and wall jumps)
	-- NOTE: We allow airborne jumps to pass through for wall jump detection
	if self.CharacterController and self.CharacterController.InputManager then
		local inputMode = self.CharacterController.InputManager.InputMode
		if (inputMode == "PC" or inputMode == "Controller") and not self.CharacterController:IsInCoyoteTime() then
			-- Only allow if we're in an ACTIVE sliding state (for jump cancel)
			-- OR if wall jumping is enabled (for wall jump detection)
			-- NOTE: We removed the early rejection here to allow wall jump attempts
			if MovementStateManager:IsSliding() then
				if TestMode.Logging.LogSlidingSystem then
					LogService:Info("INPUT", "Jump input allowed for jump cancel while airborne", {
						InputMode = inputMode,
						IsGrounded = self.CharacterController.IsGrounded,
						CurrentState = MovementStateManager:GetCurrentState(),
					})
				end
			else
				-- Not sliding and not in coyote time - might be wall jump attempt
				-- Let it pass through to ProcessJumpInput which will handle wall jump logic
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

	-- Only process jump if this is a new press (not a held repeat)
	if not wasAlreadyPressed then
		-- Process jump immediately based on current state
		-- Wall jumps are handled here only (not in continuous ProcessJumpInput loop)
		self:ProcessJumpInput(true) -- true = immediate press, allows wall jump
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
	-- Check if this is mobile autojump
	local isMobileAutoJump = false
	if
		self.CharacterController
		and self.CharacterController.InputManager
		and self.CharacterController.InputManager.MobileControls
	then
		isMobileAutoJump = self.CharacterController.InputManager.MobileControls:IsAutoJumpActive()
	end

	if not isMobileAutoJump then
		return
	end

	-- Detect landing: was airborne last frame, grounded this frame
	local isGroundedNow = self.CharacterController.IsGrounded
	if not self.WasGroundedLastFrame and isGroundedNow and self.JumpExecuted then
		-- Just landed and jump is held - reset state to allow immediate next jump
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

	-- isImmediatePress is true only when called from OnJumpPressed (not from update loop)
	isImmediatePress = isImmediatePress or false

	-- Route to appropriate handler based on current state
	local currentState = MovementStateManager:GetCurrentState()

	if currentState == MovementStateManager.States.Sliding then
		self:HandleSlidingJump()
	elseif SlidingSystem:IsInJumpCancelCoyoteTime() then
		-- Handle jump cancel during coyote time after slide stops
		self:HandleCoyoteTimeJumpCancel()
	else
		-- Handle all other states (Walking, Crouching, or airborne with buffered slides) as normal jump
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

	-- Execute jump cancel
	local jumpCancelExecuted = SlidingSystem:ExecuteJumpCancel(nil, self.CharacterController)
	if jumpCancelExecuted then
		self:MarkJumpExecuted()
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Jump cancel executed successfully")
		end
	else
		-- Jump cancel failed, fall back to stopping slide
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Jump cancel failed, stopping slide")
		end

		SlidingSystem:StopSlide(false) -- false = manual stop, remove visual

		-- Don't mark as executed so normal jump can process after state change
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

	-- Execute jump cancel using stored slide information
	local jumpCancelExecuted = SlidingSystem:ExecuteJumpCancel(nil, self.CharacterController)
	if jumpCancelExecuted then
		self:MarkJumpExecuted()
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Coyote time jump cancel executed successfully")
		end
	else
		-- Jump cancel failed, fall back to normal jump
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Coyote time jump cancel failed, falling back to normal jump")
		end

		-- Don't mark as executed so normal jump can process
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
			PrimaryPartPosition = self.CharacterController.PrimaryPart
					and self.CharacterController.PrimaryPart.Position
				or nil,
		})
	end

	-- Check if this is a wall jump attempt (immediate press while airborne, NOT during coyote time)
	-- Wall jumps only trigger when player is truly airborne (not in coyote time grace period)
	local isInCoyoteTime = self.CharacterController:IsInCoyoteTime()

	-- CRITICAL: Never allow wall jump on same press as normal jump
	-- Wall jump should only happen if player was ALREADY airborne when they pressed jump
	local shouldAttemptWallJump = isImmediatePress and not self.CharacterController.IsGrounded and not isInCoyoteTime

	if TestMode.Logging.LogSlidingSystem then
		LogService:Debug("INPUT", "HandleNormalJump - Jump type decision", {
			IsGrounded = self.CharacterController.IsGrounded,
			IsInCoyoteTime = isInCoyoteTime,
			IsImmediatePress = isImmediatePress,
			ShouldAttemptWallJump = shouldAttemptWallJump,
		})
	end

	-- Execute if grounded OR in coyote time (but not if attempting wall jump)
	if isInCoyoteTime and not shouldAttemptWallJump then
		-- Check jump cooldown for grounded/coyote jumps only
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
			return -- Exit immediately after successful normal jump to prevent wall jump on same frame
		else
			if TestMode.Logging.LogSlidingSystem then
				LogService:Info("INPUT", "Normal jump failed")
			end
		end
	elseif shouldAttemptWallJump then
		-- Wall jump attempt (immediate press while airborne) - no cooldown, bypasses coyote time
		self:HandleWallJump()
	end
end

function MovementInputProcessor:HandleWallJump()
	print("[INPUT] HandleWallJump called - player pressed jump while airborne")

	if TestMode.Logging.LogSlidingSystem then
		LogService:Debug("INPUT", "Normal jump not available, attempting wall jump", {
			IsGrounded = self.CharacterController.IsGrounded,
			TimeSinceGrounded = tick() - self.CharacterController.LastGroundedTime,
		})
	end

	-- Attempt wall jump (pass full camera angles for 3D direction and character controller for sprint check)
	local cameraAngles = self.CharacterController.LastCameraAngles or Vector2.new(0, 0)
	local wallJumpSucceeded, wallData = WallJumpUtils:AttemptWallJump(
		self.CharacterController.Character,
		self.CharacterController.PrimaryPart,
		self.CharacterController.RaycastParams,
		cameraAngles,
		self.CharacterController
	)

	if wallJumpSucceeded then
		-- Only mark as executed if wall jump actually succeeded
		-- This prevents failed wall jump attempts from starting the jump cooldown
		self:MarkJumpExecuted()

		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("INPUT", "Wall jump executed successfully", {
				WallDistance = wallData and wallData.Distance or nil,
				WallPart = wallData and wallData.Part.Name or nil,
			})
		end
	else
		-- Wall jump failed - ALWAYS mark as executed to prevent continuous attempts
		-- This ensures we don't keep trying wall jumps while holding the button
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

-- Check if jump input should be processed (called from update loop)
function MovementInputProcessor:ShouldProcessJump()
	return self.JumpPressed and not self.JumpExecuted
end

-- Force clear jump state (for emergency cleanup)
function MovementInputProcessor:ClearJumpState()
	self.JumpPressed = false
	self.JumpExecuted = false

	if TestMode.Logging.LogSlidingSystem then
		LogService:Debug("INPUT", "Jump state cleared")
	end
end

return MovementInputProcessor