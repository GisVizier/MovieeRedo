-- =============================================================================
-- CONSOLIDATED CHARACTER CONTROLLER
-- Merged: CharacterMovement, CharacterInput, CharacterState into single file
-- All functionality preserved, complexity reduced
-- =============================================================================

local CharacterController = {}

-- Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CharacterSetup = require(Locations.Client.Controllers.CharacterSetup)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local ValidationUtils = require(Locations.Modules.Utils.ValidationUtils)
local Config = require(Locations.Modules.Config)
local ConfigCache = require(Locations.Modules.Systems.Core.ConfigCache)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local SlidingSystem = require(Locations.Modules.Systems.Movement.SlidingSystem)
local WallJumpUtils = require(Locations.Modules.Systems.Movement.WallJumpUtils)
local CrouchUtils = require(Locations.Modules.Systems.Character.CrouchUtils)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local TestMode = require(Locations.Modules.TestMode)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
local MovementInputProcessor = require(script.Parent.Parent.Input.MovementInputProcessor)
local FOVController = require(Locations.Modules.Systems.Core.FOVController)
local VFXController = require(Locations.Modules.Systems.Core.VFXController)

-- Performance optimizations
local math_rad = math.rad
local math_deg = math.deg
local vector2_new = Vector2.new
local vector3_new = Vector3.new

-- =============================================================================
-- STATE PROPERTIES
-- =============================================================================

CharacterController.Character = nil
CharacterController.PrimaryPart = nil
CharacterController.IsGrounded = false
CharacterController.WasGrounded = false
CharacterController.LastGroundedTime = 0
CharacterController.LastCrouchTime = 0
CharacterController.LastSlopeLogTime = 0

CharacterController.MovementInput = vector2_new(0, 0)
CharacterController.IsSprinting = false
CharacterController.IsCrouching = false
CharacterController.WantsToUncrouch = false
CharacterController.UncrouchCheckConnection = nil

CharacterController.AirborneStartTime = 0
CharacterController.CrouchCancelUsedThisJump = false
CharacterController.JustLanded = false
CharacterController.LandingVelocity = Vector3.new(0, 0, 0)

CharacterController.InputManager = nil
CharacterController.CameraController = nil
CharacterController.InputsConnected = false
CharacterController.ConnectionCount = 0

CharacterController.CachedCameraYAngle = 0
CharacterController.LastCameraAngles = nil
CharacterController.CameraRotationChanged = false

CharacterController.VectorForce = nil
CharacterController.AlignOrientation = nil
CharacterController.Attachment0 = nil
CharacterController.Attachment1 = nil
CharacterController.RaycastParams = nil
CharacterController.FeetPart = nil

CharacterController.MovementInputProcessor = nil
CharacterController.LastUpdateTime = 0
CharacterController.MinFrameTime = 0
CharacterController.Connection = nil

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function CharacterController:Init()
	self.CharacterSetup = CharacterSetup
	self.CharacterSetup:Init(self)
	self.CharacterSetup:InitializeController()
end

function CharacterController:ConnectToInputs(inputManager, cameraController)
	self.CharacterSetup:ConnectToInputs(inputManager, cameraController)
end

function CharacterController:OnCharacterSpawned(character)
	self.CharacterSetup:OnCharacterSpawned(character)
end

function CharacterController:SetupCharacterComponents()
	self.CharacterSetup:SetupCharacterComponents()
end

function CharacterController:OnCharacterRemoving(character)
	self.CharacterSetup:OnCharacterRemoving(character)
end

function CharacterController:SetupModernPhysics()
	self.CharacterSetup:SetupModernPhysics()
end

function CharacterController:SetupRaycast()
	self.CharacterSetup:SetupRaycast()
end

function CharacterController:CleanupCharacter()
	self.CharacterSetup:CleanupCharacter()
end

function CharacterController:ConfigureCharacterParts()
	self.CharacterSetup:ConfigureCharacterParts()
end

function CharacterController:HideCharacterParts()
	self.CharacterSetup:HideCharacterParts()
end

-- =============================================================================
-- MOVEMENT LOOP
-- =============================================================================

function CharacterController:StartMovementLoop()
	LogService:Debug("CHARACTER", "StartMovementLoop called", {
		HasExistingConnection = self.Connection ~= nil,
		CallStack = debug.traceback("", 2),
	})

	if self.Connection then
		LogService:Debug("CHARACTER", "Disconnecting existing movement loop")
		self.Connection:Disconnect()
	end

	self.Connection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		local deltaTime = currentTime - self.LastUpdateTime

		if deltaTime >= self.MinFrameTime then
			self.LastUpdateTime = currentTime
			self:UpdateMovement(deltaTime)
		end
	end)

	LogService:Debug("CHARACTER", "Movement loop started successfully")
end

function CharacterController:UpdateMovement(_deltaTime)
	if not ValidationUtils:IsPrimaryPartValid(self.PrimaryPart) or not self.VectorForce then
		return
	end

	-- Check for death (falling off map)
	self:CheckDeath()

	-- Update cached camera rotation
	self:UpdateCachedCameraRotation()

	-- Cancel jump velocity while buffered slide is active
	if SlidingSystem.IsSlideBuffered and not self.IsGrounded then
		local primaryPart = self.PrimaryPart
		if primaryPart then
			local currentVelocity = primaryPart.AssemblyLinearVelocity
			if currentVelocity.Y > 0 then
				primaryPart.AssemblyLinearVelocity = Vector3.new(
					currentVelocity.X,
					math.min(currentVelocity.Y * 0.5, 0),
					currentVelocity.Z
				)
			end
		end
	end

	self:CheckGrounded()

	-- Track airborne time for crouch-cancel
	if not self.IsGrounded and self.WasGrounded then
		self.AirborneStartTime = tick()
		self.CrouchCancelUsedThisJump = false
	elseif self.IsGrounded then
		self.AirborneStartTime = 0
		self.CrouchCancelUsedThisJump = false
	end

	-- Crouch-cancel jump detection
	self:CheckCrouchCancelJump()

	-- STATE PRIORITY SYSTEM:
	-- Frame 1: Jump handled by input processor (highest priority)
	-- Frame 2: Slope Magnet - snap to ground if near and not jumping
	-- Frame 3: Floaty Fall - only if not grounded/magnetized

	-- Store LastJumpTime for magnet cooldown
	self.LastJumpTime = self.MovementInputProcessor and self.MovementInputProcessor.LastJumpTime or 0

	-- Priority 2: Slope Magnet (snap to ground on downhill)
	local wasMagnetized = self:ApplySlopeMagnet()

	-- Priority 3: Floaty Fall (only if not grounded and not magnetized)
	-- SKIP when slide is buffered - slide system handles its own airborne physics
	if not wasMagnetized and not SlidingSystem.IsSlideBuffered then
		self:ApplyAirborneDownforce(_deltaTime)
	end

	-- Log slope angle every second
	self:LogSlopeAngle()

	-- Check for buffered slide landing
	if SlidingSystem.IsSlideBuffered and self.IsGrounded then
		local primaryPart = self.PrimaryPart
		if primaryPart then
			local currentVelocity = primaryPart.AssemblyLinearVelocity
			primaryPart.AssemblyLinearVelocity = Vector3.new(
				currentVelocity.X,
				-50,
				currentVelocity.Z
			)
			if TestMode.Logging.LogSlidingSystem then
				LogService:Debug("SLIDING", "Applied grounding force on buffered landing", {
					OriginalY = currentVelocity.Y,
					NewY = -50,
				})
			end
		end

		local currentDirection = self:CalculateMovementDirection()
		local currentCameraAngle = math_deg(self.CachedCameraYAngle)

		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("CHARACTER", "SLIDE BUFFER LANDING DETECTED", {
				BufferDuration = tick() - SlidingSystem.SlideBufferStartTime,
				HasMovementInput = currentDirection.Magnitude > 0,
				MovementMagnitude = currentDirection.Magnitude,
				LandingPosition = self.PrimaryPart.Position.Y,
			})
		end

		if currentDirection.Magnitude > 0 then
			if TestMode.Logging.LogSlidingSystem then
				LogService:Info("SLIDING", "SLIDE BUFFER EXECUTED SUCCESSFULLY", {
					BufferDuration = tick() - SlidingSystem.SlideBufferStartTime,
					ExecutionTrigger = "Player landed with movement input",
					MovementMagnitude = currentDirection.Magnitude,
				})
			end
			SlidingSystem:StartSlide(currentDirection, currentCameraAngle)
		else
			if TestMode.Logging.LogSlidingSystem then
				LogService:Info("CHARACTER", "Cancelling slide buffer - no movement input")
			end
			SlidingSystem:CancelSlideBuffer("No movement input at landing")
		end
	end

	-- Check for buffered jump cancel landing
	if SlidingSystem.IsJumpCancelBuffered and self.IsGrounded then
		local bufferedDirection = SlidingSystem.BufferedJumpCancelDirection
		SlidingSystem:ExecuteJumpCancel(bufferedDirection, self)
		SlidingSystem:CancelJumpCancelBuffer()
	end

	-- Update rotation and apply movement based on state
	if not MovementStateManager:IsSliding() then
		self:UpdateRotation()
		self:ApplyMovement()
	end

	-- Update autojump state
	if self.MovementInputProcessor then
		self.MovementInputProcessor:UpdateAutoJump()
	end

	-- Process pending jump inputs
	if self.MovementInputProcessor and self.MovementInputProcessor:ShouldProcessJump() then
		self.MovementInputProcessor:ProcessJumpInput()
	end

	-- Update momentum FOV based on current velocity (vertical contributes for jumping/falling feel)
	local fullVelocity = self.PrimaryPart and self.PrimaryPart.AssemblyLinearVelocity or Vector3.zero
	local horizontalSpeed = Vector3.new(fullVelocity.X, 0, fullVelocity.Z).Magnitude
	local verticalSpeed = math.abs(fullVelocity.Y) * 0.5 -- 50% vertical contribution for jumping/falling FOV
	local effectiveSpeed = math.sqrt(horizontalSpeed * horizontalSpeed + verticalSpeed * verticalSpeed)
	FOVController:UpdateMomentum(effectiveSpeed)

	-- SPEED FX (continuous effect - triggers on fast horizontal movement OR falling, NOT during slide)
	local speedFXConfig = Config.Gameplay.VFX and Config.Gameplay.VFX.SpeedFX
	local isSliding = MovementStateManager:IsSliding()
	
	if speedFXConfig and speedFXConfig.Enabled and self.PrimaryPart and not isSliding then
		local speedThreshold = speedFXConfig.Threshold or 80
		local fallThreshold = speedFXConfig.FallThreshold or 70
		local fallSpeed = math.abs(fullVelocity.Y)
		
		-- Trigger on fast horizontal movement OR fast falling (but not sliding)
		local shouldShowSpeedFX = horizontalSpeed >= speedThreshold or fallSpeed >= fallThreshold
		
		if shouldShowSpeedFX then
			if not VFXController:IsContinuousVFXActive("SpeedFX") then
				VFXController:StartContinuousVFXReplicated("SpeedFX", self.PrimaryPart)
			end
			-- Update position AND orientation to follow velocity direction
			VFXController:UpdateContinuousVFXOrientation("SpeedFX", fullVelocity, self.PrimaryPart)
		else
			if VFXController:IsContinuousVFXActive("SpeedFX") then
				VFXController:StopContinuousVFX("SpeedFX")
			end
		end
	elseif isSliding and VFXController:IsContinuousVFXActive("SpeedFX") then
		-- Stop SpeedFX if sliding
		VFXController:StopContinuousVFX("SpeedFX")
	end
end

-- =============================================================================
-- CAMERA & ROTATION
-- =============================================================================

function CharacterController:UpdateCachedCameraRotation()
	if not self.CameraController then
		return
	end

	local cameraAngles = self.CameraController:GetCameraAngles()
	local threshold = MovementStateManager:IsSliding() and 0.01 or 0

	if not self.LastCameraAngles or math.abs(self.LastCameraAngles.X - cameraAngles.X) > threshold then
		self.CachedCameraYAngle = math_rad(cameraAngles.X)
		self.LastCameraAngles = cameraAngles
		self.CameraRotationChanged = true
	else
		self.CameraRotationChanged = false
	end
end

function CharacterController:UpdateRotation()
	if not self.CameraController or not self.CameraRotationChanged then
		return
	end

	MovementUtils:SetCharacterRotation(self.AlignOrientation, self.CachedCameraYAngle)
end

-- =============================================================================
-- GROUND DETECTION
-- =============================================================================

function CharacterController:CheckGrounded()
	if not self.Character or not self.PrimaryPart or not self.RaycastParams then
		self.IsGrounded = false
		return
	end

	self.WasGrounded = self.IsGrounded
	self.IsGrounded = MovementUtils:CheckGrounded(self.Character, self.PrimaryPart, self.RaycastParams)

	MovementStateManager:UpdateGroundedState(self.IsGrounded)

	-- LANDING DETECTION (for momentum preservation)
	if not self.WasGrounded and self.IsGrounded then
		self.JustLanded = true
		-- Use velocity from PREVIOUS frame (before ground stopped the fall)
		self.LandingVelocity = self.LastFrameVelocity or self.PrimaryPart.AssemblyLinearVelocity
		
		-- TRIGGER LANDING VFX at feet position (only for significant landings)
		local landConfig = Config.Gameplay.VFX and Config.Gameplay.VFX.Land
		local minFallVelocity = landConfig and landConfig.MinFallVelocity or 60
		local fallSpeed = math.abs(self.LandingVelocity.Y)
		
		if fallSpeed >= minFallVelocity then
			local feetPosition = self.FeetPart and self.FeetPart.Position or self.PrimaryPart.Position
			VFXController:PlayVFXReplicated("Land", feetPosition)
		end
	else
		self.JustLanded = false
	end
	
	-- Track velocity for next frame's landing detection
	self.LastFrameVelocity = self.PrimaryPart.AssemblyLinearVelocity

	if self.IsGrounded then
		self.LastGroundedTime = tick()
		WallJumpUtils:ResetCharges()
	end

	-- Detect landing after jump
	local lastJumpTime = self.MovementInputProcessor and self.MovementInputProcessor.LastJumpTime or 0
	if not self.WasGrounded and self.IsGrounded and lastJumpTime > 0 then
		local timeSinceJump = tick() - lastJumpTime
		if timeSinceJump < 10 then
			LogService:Debug("CHARACTER", "Landing detected after recorded jump", {
				TimeSinceJump = timeSinceJump,
			})
		end
	end

	if Config.System.Debug.LogGroundDetection and self.WasGrounded ~= self.IsGrounded then
		LogService:Debug("GROUND", "Ground state changed", {
			IsGrounded = self.IsGrounded,
			WasGrounded = self.WasGrounded,
		})
	end
end

function CharacterController:IsInCoyoteTime()
	if self.IsGrounded then
		return true
	end

	local currentTime = tick()
	local timeSinceGrounded = currentTime - self.LastGroundedTime
	return timeSinceGrounded <= Config.Gameplay.Character.CoyoteTime
end

function CharacterController:IsCharacterGrounded()
	return self.IsGrounded
end

-- =============================================================================
-- MOVEMENT APPLICATION
-- =============================================================================

function CharacterController:ApplyMovement()
	local moveVector = self:CalculateMovement()
	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
	local isMoving = self.MovementInput.Magnitude > 0

	MovementUtils:UpdateStandingFriction(self.Character, self.PrimaryPart, self.RaycastParams, isMoving)

	local targetSpeed = nil
	if MovementStateManager:IsSprinting() then
		targetSpeed = Config.Gameplay.Character.SprintSpeed
	elseif MovementStateManager:IsCrouching() then
		targetSpeed = Config.Gameplay.Character.CrouchSpeed
	end

	local weightMultiplier = 1.0

	-- WALL STOP: Check if trying to move into a wall (using input direction) and stop completely
	-- SKIP if recently wall jumped (prevents WallStop from zeroing velocity right after wall jump)
	local WallJumpUtils = require(Locations.Modules.Systems.Movement.WallJumpUtils)
	local timeSinceWallJump = tick() - WallJumpUtils.LastWallJumpTime
	local wallJumpImmunity = 0.5 -- 500ms immunity after wall jump (increased for safety)
	
	local isHittingWall = false
	local wallNormal = nil
	if timeSinceWallJump > wallJumpImmunity then
		isHittingWall, wallNormal = MovementUtils:CheckWallStopWithNormal(self.PrimaryPart, self.RaycastParams, moveVector)
	end
	local finalMoveVector = moveVector
	
	if isHittingWall then
		-- Only apply wall stop when GROUNDED - don't interfere with airborne physics
		if self.IsGrounded then
			-- GROUNDED: Stop horizontal movement completely when hitting wall
			finalMoveVector = Vector3.new(0, 0, 0)
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
			currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
		end
		-- AIRBORNE: Don't stop or push - let natural physics handle it
	end
	
	-- ANTI-STUCK DETECTION: Track if player is stuck against wall while airborne
	local horizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local horizontalSpeed = horizontalVelocity.Magnitude
	
	-- Check for walls in multiple directions (look direction and velocity direction)
	local isNearWallLook = MovementUtils:CheckWallStop(self.PrimaryPart, self.RaycastParams, self.PrimaryPart.CFrame.LookVector)
	local isNearWallVel = horizontalSpeed > 0.1 and MovementUtils:CheckWallStop(self.PrimaryPart, self.RaycastParams, horizontalVelocity.Unit)
	local isNearWall = isNearWallLook or isNearWallVel
	
	-- STUCK IN AIR DETECTION (separate from wall stuck)
	-- If airborne with very low velocity (both horizontal and vertical), apply downward force
	local totalSpeed = currentVelocity.Magnitude
	local isAirborneStuck = not self.IsGrounded and totalSpeed < 3 and timeSinceWallJump > 0.3
	
	if isAirborneStuck then
		if not self.AirborneStuckStartTime then
			self.AirborneStuckStartTime = tick()
		end
		
		local airborneStuckDuration = tick() - self.AirborneStuckStartTime
		if airborneStuckDuration > 0.1 then
			-- STUCK IN AIR: Apply strong downward force to break free
			LogService:Warn("AIR_STUCK", "Player stuck in air - applying gravity", {
				Duration = airborneStuckDuration,
				Velocity = currentVelocity,
				Position = self.PrimaryPart.Position,
			})
			
			-- Apply downward velocity to break free
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
				currentVelocity.X,
				math.min(currentVelocity.Y, -30), -- Force downward
				currentVelocity.Z
			)
			currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
			self.AirborneStuckStartTime = nil
		end
	else
		self.AirborneStuckStartTime = nil
	end
	
	-- WALL STUCK condition: airborne, low speed, near a wall
	local isStuckCondition = not self.IsGrounded and horizontalSpeed < 5 and isNearWall
	
	if isStuckCondition then
		-- Initialize stuck timer if not set
		if not self.WallStuckStartTime then
			self.WallStuckStartTime = tick()
			LogService:Debug("WALL_STUCK", "Potential stuck detected - starting timer", {
				HorizontalSpeed = horizontalSpeed,
				IsAirborne = not self.IsGrounded,
				TimeSinceWallJump = timeSinceWallJump,
			})
		end
		
		-- Reduced stuck duration threshold for faster escape (was 0.3)
		local stuckDuration = tick() - self.WallStuckStartTime
		if stuckDuration > 0.15 then
			-- STUCK FOR TOO LONG: Apply escape force
			LogService:Warn("WALL_STUCK", "Player stuck against wall - applying escape", {
				StuckDuration = stuckDuration,
				Position = self.PrimaryPart.Position,
				Velocity = currentVelocity,
			})
			
			-- Get wall normal from look direction check and push away
			local _, stuckWallNormal = MovementUtils:CheckWallStopWithNormal(self.PrimaryPart, self.RaycastParams, self.PrimaryPart.CFrame.LookVector)
			if not stuckWallNormal and horizontalSpeed > 0.1 then
				_, stuckWallNormal = MovementUtils:CheckWallStopWithNormal(self.PrimaryPart, self.RaycastParams, horizontalVelocity.Unit)
			end
			
			if stuckWallNormal then
				local escapeDir = Vector3.new(stuckWallNormal.X, 0, stuckWallNormal.Z)
				if escapeDir.Magnitude > 0.01 then
					escapeDir = escapeDir.Unit
					-- Stronger escape force (was 20)
					self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
						escapeDir.X * 30,
						math.max(currentVelocity.Y, 5), -- Add slight upward push
						escapeDir.Z * 30
					)
					currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
				end
			else
				-- No wall normal found, just push up and backward from look direction
				local backDir = -self.PrimaryPart.CFrame.LookVector
				self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
					backDir.X * 25,
					math.max(currentVelocity.Y, 10),
					backDir.Z * 25
				)
				currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
			end
			self.WallStuckStartTime = nil -- Reset timer
		end
	else
		-- Not stuck, reset timer
		self.WallStuckStartTime = nil
	end

	local moveForce = MovementUtils:CalculateMovementForce(
		finalMoveVector,
		currentVelocity,
		self.IsGrounded,
		self.Character,
		self.PrimaryPart,
		self.RaycastParams,
		targetSpeed,
		weightMultiplier
	)

	-- Calculate vertical force
	local verticalForce = 0
	local mass = self.PrimaryPart.AssemblyMass
	
	-- STICKY GROUND: Only apply when SLIDING (not walking/running)
	if MovementStateManager:IsSliding() then
		local lastJumpTime = self.MovementInputProcessor and self.MovementInputProcessor.LastJumpTime or 0
		local stickyForce, groundY = MovementUtils:ApplyStickyGround(self.PrimaryPart, self.RaycastParams, lastJumpTime)
		
		if stickyForce > 0 then
			verticalForce = -stickyForce
		end
	end
	
	-- AIR PHYSICS (only if sticky not active and airborne)
	if verticalForce == 0 and ConfigCache.FALL_SPEED_ENABLED and not self.IsGrounded then
		local currentYVelocity = currentVelocity.Y
		local absYVelocity = math.abs(currentYVelocity)

		if currentYVelocity > 0 then
			-- ASCENDING: Apply gravity reduction for slower rise (hang longer in air)
			local ascentGravityReduction = Config.Gameplay.Character.FallSpeed.AscentGravityReduction or 0.4
			-- Counteract gravity by this percentage during ascent
			verticalForce = ConfigCache.WORLD_GRAVITY * mass * ascentGravityReduction
			
		elseif absYVelocity < ConfigCache.HANG_TIME_THRESHOLD then
			-- HANG TIME: Near peak of jump, small upward force
			local hangDrag = ConfigCache.HANG_TIME_DRAG or 0.05
			local hangForce = ConfigCache.WORLD_GRAVITY * mass * hangDrag
			verticalForce = hangForce
			
		else
			-- FALLING: Apply additional downward force for faster falling
			local fallAcceleration = Config.Gameplay.Character.FallSpeed.FallAcceleration or 40
			local maxFallSpeed = ConfigCache.MAX_FALL_SPEED

			if absYVelocity > maxFallSpeed then
				-- Cap at terminal velocity
				local terminalForce = ConfigCache.WORLD_GRAVITY * mass
				local damping = (absYVelocity - maxFallSpeed) * ConfigCache.FALL_DRAG_MULTIPLIER * mass
				verticalForce = terminalForce + damping
			else
				-- Accelerate falling with additional downward force
				verticalForce = -fallAcceleration * mass
			end
		end
	end

	local finalForce = vector3_new(moveForce.X, verticalForce, moveForce.Z)
	self.VectorForce.Force = finalForce
end

function CharacterController:CalculateMovement()
	if not self.CameraController then
		return vector3_new(0, 0, 0)
	end

	return MovementUtils:CalculateWorldMovementDirection(
		self.MovementInput,
		self.CachedCameraYAngle,
		true
	)
end

function CharacterController:CalculateMovementDirection()
	return self:CalculateMovement()
end

function CharacterController:GetRelativeMovementDirection()
	local input = self.MovementInput
	if input.Magnitude < 0.01 then
		return Vector2.new(0, 0), 0
	end

	local normalized = input.Unit
	return Vector2.new(normalized.X, normalized.Y), input.Magnitude
end

function CharacterController:IsMoving()
	return self.MovementInput.Magnitude > 0.01
end

function CharacterController:GetCurrentSpeed()
	if not self.PrimaryPart then
		return 0
	end

	local velocity = self.PrimaryPart.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

-- =============================================================================
-- INPUT HANDLING
-- =============================================================================

function CharacterController:HandleCrouch(isCrouching)
	if not self.Character then
		return
	end

	if isCrouching then
		self:StopUncrouchChecking()
		CrouchUtils:Crouch(self.Character)
		MovementStateManager:TransitionTo(MovementStateManager.States.Crouching)
	else
		if CrouchUtils:IsVisuallycrouched(self.Character) then
			self:StartUncrouchChecking()
			return
		end
		self:StopUncrouchChecking()
		CrouchUtils:Uncrouch(self.Character)

		local shouldRestoreSprint = self.IsSprinting or Config.Gameplay.Character.AutoSprint
		if shouldRestoreSprint then
			MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
		else
			MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
		end
	end
end

function CharacterController:HandleSlideInput(isSliding)
	if not self.Character then
		return
	end

	if isSliding then
		local movementDirection
		if self.MovementInput.Magnitude < 0.01 then
			movementDirection = MovementUtils:CalculateWorldMovementDirection(
				vector2_new(0, 1),
				self.CachedCameraYAngle,
				true
			)
		else
			movementDirection = self:CalculateMovementDirection()
		end

		local canSlide, reason = SlidingSystem:CanStartSlide(
			vector2_new(0, 1),
			true,
			self.IsGrounded
		)

		if canSlide then
			local currentCameraAngle = math_deg(self.CachedCameraYAngle)
			SlidingSystem:StartSlide(movementDirection, currentCameraAngle)
		elseif not self.IsGrounded then
			-- AIRBORNE BUFFERING: Buffer the slide to execute on landing
			local canBuffer = SlidingSystem:CanBufferSlide(
				self.MovementInput,
				true,
				self.IsGrounded,
				self
			)
			if canBuffer then
				SlidingSystem:StartSlideBuffer(movementDirection, false)
				LogService:Debug("SLIDING", "Slide buffered while airborne")
			end
		else
			LogService:Debug("SLIDING", "Slide attempt failed in HandleSlideInput", {
				Reason = reason,
				IsGrounded = self.IsGrounded,
				TimeSinceLastSlide = tick() - SlidingSystem.LastSlideEndTime,
			})
		end
	else
		-- V released - stop slide if active
		if SlidingSystem.IsSliding then
			SlidingSystem:StopSlide(false, true)
		end
		
		-- ALWAYS clear crouch state when V is released (even if slide already ended)
		self:StopUncrouchChecking()
		self.IsCrouching = false
		if self.InputManager then
			self.InputManager.IsCrouching = false
		end
		
		-- Force visual uncrouch ONLY if actually visually crouched (prevents collision issues)
		if self.Character and CrouchUtils:IsVisuallycrouched(self.Character) then
			CrouchUtils:Uncrouch(self.Character)
			CrouchUtils:RemoveVisualCrouch(self.Character)
		end
		
		-- FORCE state to Walking to ensure no stuck states
		local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
		if not MovementStateManager:IsWalking() and not MovementStateManager:IsSprinting() then
			MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
		end
	end
end

function CharacterController:HandleCrouchWithSlidePriority(isCrouching)
	if not self.Character then
		return
	end

	if isCrouching then
		local currentTime = tick()
		local timeSinceLastCrouch = currentTime - self.LastCrouchTime
		local isSprinting = MovementStateManager:IsSprinting()
		local hasMovementInput = self.MovementInput.Magnitude > 0
		local autoSlideEnabled = Config.Gameplay.Sliding.AutoSlide

		local shouldApplyCooldown = timeSinceLastCrouch >= (Config.Gameplay.Cooldowns.Crouch - 0.001)
		local isCrouchCooldownActive = SlidingSystem:IsCrouchCooldownActive(self)

		if TestMode.Logging.LogSlidingSystem then
			LogService:Debug("SLIDING", "Cooldown evaluation during crouch input", {
				TimeSinceLastCrouch = string.format("%.3f", timeSinceLastCrouch),
				ShouldApplyCooldown = shouldApplyCooldown,
				IsCrouchCooldownActive = isCrouchCooldownActive,
				AutoSlideEnabled = autoSlideEnabled,
			})
		end

		if shouldApplyCooldown then
			self.LastCrouchTime = currentTime
		end

		local timeSinceLastSlide = tick() - SlidingSystem.LastSlideEndTime
		local isLikelyTryingToCrouchAfterSlide = timeSinceLastSlide < 0.5 and timeSinceLastCrouch < 0.3

		if autoSlideEnabled and isSprinting and hasMovementInput and not isLikelyTryingToCrouchAfterSlide then
			local movementDirection = self:CalculateMovementDirection()
			local canSlide, reason = SlidingSystem:CanStartSlide(
				self.MovementInput,
				isCrouching,
				self.IsGrounded
			)

			if canSlide then
				if TestMode.Logging.LogSlidingSystem then
					LogService:Debug("SLIDING", "Using auto-slide (sprint + crouch)", {
						TimeSinceLastSlide = tick() - SlidingSystem.LastSlideEndTime,
						CooldownRequired = Config.Gameplay.Cooldowns.Slide,
					})
				end
				local currentCameraAngle = math_deg(self.CachedCameraYAngle)
				SlidingSystem:StartSlide(movementDirection, currentCameraAngle)
				return
			else
				LogService:Debug("SLIDING", "Auto-slide attempt failed", {
					Reason = reason,
					MovementMagnitude = self.MovementInput.Magnitude,
					IsGrounded = self.IsGrounded,
					TimeSinceLastSlide = tick() - SlidingSystem.LastSlideEndTime,
				})
			end
		end

		if autoSlideEnabled and not self.IsGrounded and isSprinting and hasMovementInput then
			local canBuffer, reason = SlidingSystem:CanBufferSlide(
				self.MovementInput,
				isCrouching,
				self.IsGrounded,
				self
			)

			if canBuffer then
				if TestMode.Logging.LogSlidingSystem then
					LogService:Debug("SLIDING", "Buffering auto-slide", {
						MovementMagnitude = self.MovementInput.Magnitude,
						IsAirborne = not self.IsGrounded,
					})
				end
				local movementDirection = self:CalculateMovementDirection()
				if movementDirection.Magnitude > 0 then
					SlidingSystem:StartSlideBuffer(movementDirection, false)
				end
				return
			else
				LogService:Debug("CHARACTER", "Cannot buffer slide", {
					Reason = reason,
					MovementMagnitude = self.MovementInput.Magnitude,
					IsGrounded = self.IsGrounded,
					IsCrouching = isCrouching,
				})
			end
		end

		self:HandleCrouch(isCrouching)
	else
		if SlidingSystem.IsSliding then
			if CrouchUtils:IsVisuallycrouched(self.Character) and not self:CanUncrouch() then
				SlidingSystem:StopSlide(true, false)
				self:StartUncrouchChecking()
				return
			else
				SlidingSystem:StopSlide(false, true)
				self:StopUncrouchChecking()
			end
		elseif SlidingSystem.IsSlideBuffered then
			SlidingSystem:CancelSlideBuffer("Crouch input released during buffer")
			SlidingSystem:TransferSlideCooldownToCrouch(self)
		elseif MovementStateManager:IsCrouching() then
			self:HandleCrouch(isCrouching)
		end
	end
end

-- =============================================================================
-- STATE MANAGEMENT
-- =============================================================================

function CharacterController:GetCharacter()
	return self.Character
end

function CharacterController:GetPrimaryPart()
	return self.PrimaryPart
end

function CharacterController:IsCharacterCrouching()
	return self.IsCrouching
end

function CharacterController:IsVisuallycrouched()
	return CrouchUtils:IsVisuallycrouched(self.Character)
end

function CharacterController:CanUncrouch()
	if not self.Character then
		return false
	end

	local collisionHead = CharacterLocations:GetCollisionHead(self.Character)
	local collisionBody = CharacterLocations:GetCollisionBody(self.Character)

	if not collisionHead or not collisionBody then
		return false
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { self.Character }
	overlapParams.RespectCanCollide = false
	overlapParams.MaxParts = 20

	local headObstructions = workspace:GetPartsInPart(collisionHead, overlapParams)
	local bodyObstructions = workspace:GetPartsInPart(collisionBody, overlapParams)

	local function hasCollidableObstruction(parts)
		for _, part in ipairs(parts) do
			if part.CanCollide then
				return true
			end
		end
		return false
	end

	return not hasCollidableObstruction(headObstructions) and not hasCollidableObstruction(bodyObstructions)
end

function CharacterController:StartUncrouchChecking()
	self.WantsToUncrouch = true

	if self.UncrouchCheckConnection then
		self.UncrouchCheckConnection:Disconnect()
	end

	self.UncrouchCheckConnection = RunService.Heartbeat:Connect(function()
		if not self.WantsToUncrouch or not CrouchUtils:IsVisuallycrouched(self.Character) or not self.Character then
			self:StopUncrouchChecking()
			return
		end

		if self:CanUncrouch() then
			CrouchUtils:Uncrouch(self.Character)

			local shouldRestoreSprint = self.IsSprinting or Config.Gameplay.Character.AutoSprint
			if shouldRestoreSprint then
				MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
			else
				MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
			end
			self:StopUncrouchChecking()
		end
	end)
end

function CharacterController:StopUncrouchChecking()
	self.WantsToUncrouch = false
	if self.UncrouchCheckConnection then
		self.UncrouchCheckConnection:Disconnect()
		self.UncrouchCheckConnection = nil
	end
end

function CharacterController:HandleAutomaticCrouchAfterSlide()
	if not self.Character then
		return
	end

	self.IsCrouching = true

	if not CrouchUtils.CharacterCrouchState[self.Character] then
		CrouchUtils.CharacterCrouchState[self.Character] = {
			IsCrouched = true,
		}
	else
		CrouchUtils.CharacterCrouchState[self.Character].IsCrouched = true
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("CHARACTER", "Automatic crouch after slide - crouch state set up")
	end
end

function CharacterController:LogSlopeAngle()
	local currentTime = tick()
	if currentTime - self.LastSlopeLogTime < 1.0 then
		return
	end
	self.LastSlopeLogTime = currentTime

	if not self.IsGrounded or not self.Character or not self.PrimaryPart or not self.RaycastParams then
		return
	end

	local _, slopeDegrees = MovementUtils:IsSlopeWalkable(self.Character, self.PrimaryPart, self.RaycastParams)

	if Config.System.Debug.LogSlopeAngles and slopeDegrees > 1 then
		LogService:Debug("MOVEMENT", "Current slope angle", {
			SlopeDegrees = string.format("%.1f", slopeDegrees),
			CharacterPosition = self.PrimaryPart.Position,
			IsGrounded = self.IsGrounded,
		})
	end
end

-- =============================================================================
-- DEATH DETECTION
-- =============================================================================

function CharacterController:CheckDeath()
	local currentPosition = self.PrimaryPart.Position
	local deathThreshold = Config.Gameplay.Character.DeathYThreshold

	if currentPosition.Y < deathThreshold then
		LogService:Info("CHARACTER", "Death detected (fell off map)", {
			Position = currentPosition,
			Threshold = deathThreshold,
		})

		local player = game.Players.LocalPlayer
		if player and player.Character then
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end
	end
end

function CharacterController:CheckCrouchCancelJump()
	if not self.Character or not self.PrimaryPart then
		return
	end

	if self.IsGrounded then
		return
	end

	local jumpConfig = Config.Gameplay.Character.Jump
	if not jumpConfig or not jumpConfig.CrouchCancel or not jumpConfig.CrouchCancel.Enabled then
		return
	end

	if self.CrouchCancelUsedThisJump then
		return
	end

	local airborneTime = tick() - self.AirborneStartTime
	if airborneTime < jumpConfig.CrouchCancel.MinAirborneTime then
		return
	end

	if not self.IsCrouching then
		return
	end

	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
	if currentVelocity.Y <= 0 then
		return
	end

	self.CrouchCancelUsedThisJump = true

	local cancelMultiplier = jumpConfig.CrouchCancel.VelocityCancelMultiplier
	local downforce = jumpConfig.CrouchCancel.DownforceOnCancel

	local newYVelocity = currentVelocity.Y * cancelMultiplier
	self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		newYVelocity - downforce * 0.1,
		currentVelocity.Z
	)

	-- Force uncrouch when jumping out of slide  
	self.IsCrouching = false
	CrouchUtils:Uncrouch(self.Character)
	CrouchUtils:RemoveVisualCrouch(self.Character)
	if self.InputManager then
		self.InputManager.IsCrouching = false
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("CHARACTER", "CROUCH CANCEL JUMP EXECUTED", {
			OldYVelocity = currentVelocity.Y,
			NewYVelocity = newYVelocity,
			AirborneTime = airborneTime,
			DownforceApplied = downforce,
		})
	end
end

function CharacterController:ApplyAirborneDownforce(deltaTime)
	-- BUTTER SMOOTH GRAVITY: Uses lerped gravity multiplier for smooth transitions
	if not self.Character or not self.PrimaryPart then
		return
	end

	if self.IsGrounded then
		-- Reset when grounded
		self.FloatDecayStartTime = nil
		self.SmoothedGravityMultiplier = nil
		return
	end

	local gravityConfig = Config.Gameplay.Character.GravityDamping
	if not gravityConfig or not gravityConfig.Enabled then
		return
	end

	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
	
	-- Initialize smoothed gravity multiplier if not set
	if not self.SmoothedGravityMultiplier then
		self.SmoothedGravityMultiplier = 0.1 -- Start very floaty
	end

	-- Calculate TARGET gravity multiplier based on state
	local targetGravityMultiplier
	
	if currentVelocity.Y > 2 then
		-- ASCENDING: Very low gravity (floaty rise)
		targetGravityMultiplier = 0.1
		self.FloatDecayStartTime = tick() -- Reset decay timer
	elseif currentVelocity.Y > -2 then
		-- PEAK ZONE: Hang time - stay floaty
		targetGravityMultiplier = 0.15
		if not self.FloatDecayStartTime then
			self.FloatDecayStartTime = tick()
		end
	else
		-- FALLING: Gradually increase gravity based on time falling
		if not self.FloatDecayStartTime then
			self.FloatDecayStartTime = tick()
		end
		
		local floatDecayConfig = Config.Gameplay.Character.FloatDecay
		local airborneTime = tick() - self.FloatDecayStartTime
		local horizontalSpeed = Vector3.new(currentVelocity.X, 0, currentVelocity.Z).Magnitude
		
		-- Base target: reduced damping (more gravity)
		local baseDamping = gravityConfig.DampingFactor -- 0.60
		
		if floatDecayConfig and floatDecayConfig.Enabled then
			local baseFloatDuration = floatDecayConfig.FloatDuration or 0.6
			local velocityThreshold = floatDecayConfig.VelocityThreshold or 0.5
			local shrinkRate = floatDecayConfig.ThresholdShrinkRate or 0.005
			
			-- Dynamic float based on speed
			local effectiveFloatDuration = baseFloatDuration * math.max(velocityThreshold, 1 - (horizontalSpeed * shrinkRate))
			
			if airborneTime > effectiveFloatDuration then
				local decayTime = airborneTime - effectiveFloatDuration
				local decay = decayTime * floatDecayConfig.DecayRate
				decay = decay + (horizontalSpeed * floatDecayConfig.MomentumFactor)
				baseDamping = math.max(floatDecayConfig.MinDampingFactor, baseDamping - decay)
			end
		end
		
		targetGravityMultiplier = baseDamping
	end

	-- LINEAR SMOOTH: Move toward target at constant rate (not exponential)
	-- This creates a straight-line ramp instead of curved arc
	local linearRate = 0.5 -- Units per second to move toward target
	local difference = targetGravityMultiplier - self.SmoothedGravityMultiplier
	local maxChange = linearRate * deltaTime
	
	if math.abs(difference) <= maxChange then
		self.SmoothedGravityMultiplier = targetGravityMultiplier
	elseif difference > 0 then
		self.SmoothedGravityMultiplier = self.SmoothedGravityMultiplier + maxChange
	else
		self.SmoothedGravityMultiplier = self.SmoothedGravityMultiplier - maxChange
	end

	-- Apply the smoothed gravity damping
	local mass = self.PrimaryPart.AssemblyMass
	local gravity = workspace.Gravity
	local dampingForce = mass * gravity * self.SmoothedGravityMultiplier

	local newYVelocity = currentVelocity.Y + (dampingForce / mass * deltaTime)

	-- HARD CLAMP at MaxFallSpeed
	newYVelocity = math.max(newYVelocity, -gravityConfig.MaxFallSpeed)

	self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		newYVelocity,
		currentVelocity.Z
	)
end

function CharacterController:ApplySlopeMagnet()
	-- Slope Magnet: Only snap when slightly airborne (about to launch off ramp)
	if not self.Character or not self.PrimaryPart then
		return false
	end

	local magnetConfig = Config.Gameplay.Character.SlopeMagnet
	if not magnetConfig or not magnetConfig.Enabled then
		return false
	end

	-- CRITICAL: Only apply when NOT grounded (slightly airborne)
	if self.IsGrounded then
		return false
	end

	-- Don't apply magnet if recently jumped
	if self.LastJumpTime and (tick() - self.LastJumpTime) < magnetConfig.JumpCooldown then
		return false
	end

	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity

	-- Only apply when not jumping up
	if currentVelocity.Y > 0 then
		return false
	end

	-- Cast ray downward to find ground
	local rayOrigin = self.PrimaryPart.Position
	local rayDirection = Vector3.new(0, -magnetConfig.RayLength, 0)
	local rayResult = workspace:Raycast(rayOrigin, rayDirection, self.RaycastParams)

	if not rayResult then
		return false
	end

	-- Check minimum height above ground (only activate when about to launch)
	local groundDistance = rayResult.Distance
	local minHeight = magnetConfig.MinAirborneHeight or 0.5
	
	if groundDistance < minHeight then
		return false -- Too close to ground, normal physics handles this
	end

	-- We're slightly airborne and close to ground - apply magnet pull
	self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		magnetConfig.SnapVelocity,
		currentVelocity.Z
	)
	return true
end

-- TryVault removed: Vaulting system disabled pending rework

return CharacterController
