local CharacterController = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local CharacterUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterUtils"))
local MovementUtils = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementUtils"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local SlidingSystem = require(Locations.Game:WaitForChild("Movement"):WaitForChild("SlidingSystem"))
local WallJumpUtils = require(Locations.Game:WaitForChild("Movement"):WaitForChild("WallJumpUtils"))
local CrouchUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("CrouchUtils"))
local MovementInputProcessor = require(script.Parent:WaitForChild("MovementInputProcessor"))
local ValidationUtils = require(Locations.Shared.Util:WaitForChild("ValidationUtils"))
local ConfigCache = require(Locations.Shared.Util:WaitForChild("ConfigCache"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local Net = require(Locations.Shared:WaitForChild("Net"):WaitForChild("Net"))

local math_rad = math.rad
local math_deg = math.deg
local vector2_new = Vector2.new
local vector3_new = Vector3.new

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

CharacterController.SmoothedVerticalForce = 0
CharacterController.LastDeltaTime = 1 / 60

CharacterController.LastFootstepTime = 0
CharacterController.LastJumpSoundTime = 0
CharacterController.FallSound = nil
CharacterController.LastGroundDebugTime = 0
CharacterController.LastMovementDebugTime = 0

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

-- Respawn / reset reliability
CharacterController.RespawnRequested = false
CharacterController.StepUpRemaining = 0
CharacterController.LastStepUpTime = 0
CharacterController.StepUpBoostTime = 0
CharacterController.StepUpRequiredVelocity = 0

function CharacterController:Init(registry, net)
	self._registry = registry
	self._net = net

	ServiceRegistry:SetRegistry(registry)
	ServiceRegistry:RegisterController("CharacterController", self)
	ServiceRegistry:RegisterController("MovementController", self)

	local currentTime = tick()
	self.LastCrouchTime = currentTime - 1
	self.LastGroundedTime = currentTime

	self.MovementInputProcessor = MovementInputProcessor
	self.MovementInputProcessor:Init(self)

	SlidingSystem:Init()
	VFXRep:Init(net, false)

	MovementStateManager:ConnectToStateChange(function(previousState, newState)
		if previousState == MovementStateManager.States.Sliding and newState == MovementStateManager.States.Crouching then
			self:HandleAutomaticCrouchAfterSlide()
		end
	end)

	self._net:ConnectClient("CrouchStateChanged", function(otherPlayer, isCrouching)
		local localPlayer = game:GetService("Players").LocalPlayer
		if otherPlayer ~= localPlayer then
			local otherCharacter = otherPlayer and otherPlayer.Character
			if otherCharacter then
				if isCrouching then
					CrouchUtils:ApplyVisualCrouch(otherCharacter, true)
				else
					CrouchUtils:RemoveVisualCrouch(otherCharacter)
				end
			end
		end
	end)

end

function CharacterController:Start()
	local inputController = self._registry:TryGet("Input")
	local cameraController = self._registry:TryGet("Camera")
	self:ConnectToInputs(inputController, cameraController)
end

function CharacterController:OnLocalCharacterReady(character)
	if not character then
		return
	end

	self.Character = character
	self.PrimaryPart = character.PrimaryPart or CharacterLocations:GetRoot(character)
	if not self.PrimaryPart then
		return
	end

	self.FeetPart = CharacterLocations:GetFeet(character) or self.PrimaryPart

	self:SetupModernPhysics()
	self:SetupRaycast()
	self:ConfigureCharacterParts()
	CharacterUtils:ConfigurePhysicsProperties(character)

	MovementStateManager:SetCharacter(character)

	SlidingSystem:SetupCharacter(
		self.Character,
		self.PrimaryPart,
		self.VectorForce,
		self.AlignOrientation,
		self.RaycastParams
	)

	if self.CameraController then
		SlidingSystem:SetCameraController(self.CameraController)
	end
	SlidingSystem:SetCharacterController(self)

	if self.InputManager then
		self.InputManager:ResetInputState()
	end

	self.RespawnRequested = false
	MovementStateManager:Reset()

	if self.CameraController then
		local cameraAngles = self.CameraController:GetCameraAngles()
		local cameraYAngle = math.rad(cameraAngles.X)
		self.CachedCameraYAngle = cameraYAngle
		self.LastCameraAngles = cameraAngles
	end

	self:StartMovementLoop()

	-- Pre-create looped sounds so they play instantly
	self:EnsureFallSound()
end

function CharacterController:OnLocalCharacterRemoving()
	self:StopUncrouchChecking()
	SlidingSystem:Cleanup()

	if self.FallSound then
		self.FallSound:Stop()
		self.FallSound:Destroy()
		self.FallSound = nil
	end

	self.Character = nil
	self.PrimaryPart = nil
	self.FeetPart = nil
	self.VectorForce = nil
	self.AlignOrientation = nil
	self.Attachment0 = nil
	self.Attachment1 = nil
	self.RaycastParams = nil
	self.IsGrounded = false
	self.WasGrounded = false
	self.IsSprinting = false
	self.IsCrouching = false
	self.RespawnRequested = false
	self.StepUpRemaining = 0
	self.LastStepUpTime = 0
	self.StepUpBoostTime = 0
	self.StepUpRequiredVelocity = 0
	self.JumpExecutedThisInput = false
	self.LastGroundedTime = 0

	self.InputsConnected = false

	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	if self._debugConnections then
		for _, conn in ipairs(self._debugConnections) do
			conn:Disconnect()
		end
		self._debugConnections = nil
	end
end

function CharacterController:ConnectToInputs(inputManager, cameraController)
	self.ConnectionCount = self.ConnectionCount + 1

	if self.InputsConnected then
		return
	end

	self.InputManager = inputManager
	self.CameraController = cameraController

	if not self.InputManager then
		return
	end

	self.InputManager:ConnectToInput("Movement", function(movement)
		local wasMoving = self.MovementInput.Magnitude > 0
		self.MovementInput = movement
		local isMoving = movement.Magnitude > 0
		if ConfigCache.DEBUG_MOVEMENT_INPUT and wasMoving ~= isMoving then
			self:DebugMovementInput(wasMoving, isMoving, movement)
		end
		MovementStateManager:UpdateMovementState(isMoving)
		
		-- When starting to move with AutoSprint enabled, transition to Sprinting
		if not wasMoving and isMoving then
			local autoSprint = Config.Gameplay.Character.AutoSprint
			if autoSprint and MovementStateManager:IsWalking() then
				MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
			end
		end
	end)

	self.InputManager:ConnectToInput("Jump", function(isJumping)
		if isJumping then
			self.MovementInputProcessor:OnJumpPressed()
		else
			self.MovementInputProcessor:OnJumpReleased()
		end
	end)

	self.InputManager:ConnectToInput("Sprint", function(isSprinting)
		self.IsSprinting = isSprinting
		self:HandleSprint(isSprinting)
	end)

	self.InputManager:ConnectToInput("Crouch", function(isCrouching)
		self.IsCrouching = isCrouching
		self:HandleCrouchWithSlidePriority(isCrouching)
	end)

	self.InputManager:ConnectToInput("Slide", function(isSliding)
		self:HandleSlideInput(isSliding)
	end)

	-- Camera mode toggle is now handled directly in CameraController via T key

	self.InputsConnected = true
end

function CharacterController:SetupModernPhysics()
	if not self.PrimaryPart then
		return
	end

	self.VectorForce = self.PrimaryPart:FindFirstChild("VectorForce")
	self.AlignOrientation = self.PrimaryPart:FindFirstChild("AlignOrientation")
	self.Attachment0 = self.PrimaryPart:FindFirstChild("MovementAttachment0")
	self.Attachment1 = self.PrimaryPart:FindFirstChild("MovementAttachment1")

	if self.VectorForce and self.AlignOrientation and self.Attachment0 and self.Attachment1 then
		return
	end

	local timeout = 2
	local startTime = tick()

	while (tick() - startTime) < timeout do
		if not self.VectorForce then
			self.VectorForce = self.PrimaryPart:FindFirstChild("VectorForce")
		end
		if not self.AlignOrientation then
			self.AlignOrientation = self.PrimaryPart:FindFirstChild("AlignOrientation")
		end
		if not self.Attachment0 then
			self.Attachment0 = self.PrimaryPart:FindFirstChild("MovementAttachment0")
		end
		if not self.Attachment1 then
			self.Attachment1 = self.PrimaryPart:FindFirstChild("MovementAttachment1")
		end

		if self.VectorForce and self.AlignOrientation and self.Attachment0 and self.Attachment1 then
			return
		end

		task.wait(0.1)
	end

	if not self.VectorForce or not self.AlignOrientation or not self.Attachment0 or not self.Attachment1 then
		local alignOrientation, vectorForce = MovementUtils:SetupPhysicsConstraints(self.PrimaryPart)
		self.AlignOrientation = self.AlignOrientation or alignOrientation
		self.VectorForce = self.VectorForce or vectorForce
		self.Attachment0 = self.Attachment0 or self.PrimaryPart:FindFirstChild("MovementAttachment0")
		self.Attachment1 = self.Attachment1 or self.PrimaryPart:FindFirstChild("MovementAttachment1")
	end
end

function CharacterController:SetupRaycast()
	self.RaycastParams = RaycastParams.new()
	self.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = { self.Character }
	local rig = CharacterLocations:GetRig(self.Character)
	if rig then
		table.insert(excluded, rig)
	end
	local rigsFolder = workspace:FindFirstChild("Rigs")
	if rigsFolder then
		table.insert(excluded, rigsFolder)
	end
	self.RaycastParams.FilterDescendantsInstances = excluded
	self.RaycastParams.RespectCanCollide = true
	self.RaycastParams.CollisionGroup = "Players"
end

function CharacterController:ConfigureCharacterParts()
	if not self.Character or not self.PrimaryPart then
		return
	end

	for _, part in pairs(self.Character:GetChildren()) do
		if part:IsA("BasePart") and part ~= self.PrimaryPart then
			if part.Name ~= "HumanoidRootPart" and part.Name ~= "Head" then
				part.CanCollide = true
				part.CanTouch = true
			end
		end
	end
end

function CharacterController:StartMovementLoop()
	if self.Connection then
		self.Connection:Disconnect()
	end

	self.Connection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		local deltaTime = currentTime - self.LastUpdateTime

		-- Clamp deltaTime to prevent physics explosion on first frame
		-- (LastUpdateTime starts at 0, so first deltaTime would be huge)
		deltaTime = math.min(deltaTime, 0.1)

		if deltaTime >= self.MinFrameTime then
			self.LastUpdateTime = currentTime
			self:UpdateMovement(deltaTime)
		end
	end)
end

-- =============================================================================
-- MOVEMENT UPDATE
-- =============================================================================

function CharacterController:UpdateMovement(deltaTime)
	if self.Character then
		if not self._missingRootLogged and not CharacterLocations:GetRoot(self.Character) then
			self._missingRootLogged = true
		end
		if not self._missingColliderLogged and not self.Character:FindFirstChild("Collider") then
			self._missingColliderLogged = true
		end
	end

	if not ValidationUtils:IsPrimaryPartValid(self.PrimaryPart) or not self.VectorForce then
		if not self._missingPrimaryLogged then
			self._missingPrimaryLogged = true
		end
		return
	end

	if self.RespawnRequested then
		self.VectorForce.Force = Vector3.zero
		return
	end

	self.LastDeltaTime = deltaTime

	self:CheckDeath()
	self:UpdateCachedCameraRotation()

	-- Ragdoll interaction: disable client movement forces while ragdolled.
	-- The server ragdoll system welds the character root to a ragdoll; movement forces fighting
	-- that will look choppy. Keep it simple: zero forces and let ragdoll drive motion.
	if self.Character and self.Character:GetAttribute("RagdollActive") == true then
		if not self._ragdollLogged then
			self._ragdollLogged = true
		end
		if SlidingSystem and SlidingSystem.IsSliding then
			SlidingSystem:StopSlide(false, true, "Ragdoll")
		end
		if self.VectorForce then
			self.VectorForce.Force = Vector3.zero
		end
		return
	end

	-- Frozen status effect: disable all player-controlled movement, allow physics (sliding)
	if self.Character and self.Character:GetAttribute("Frozen") == true then
		if SlidingSystem and SlidingSystem.IsSliding then
			SlidingSystem:StopSlide(false, true, "Frozen")
		end
		if self.VectorForce then
			self.VectorForce.Force = Vector3.zero
		end
		return
	end

	if self.Character and not self._missingColliderPartLogged then
		local body = CharacterLocations:GetBody(self.Character)
		local feet = CharacterLocations:GetFeet(self.Character)
		if not body or not feet then
			self._missingColliderPartLogged = true
		end
	end

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

	if self.IsGrounded and not self.WasGrounded then
		local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
		self.PrimaryPart.AssemblyLinearVelocity = currentVelocity * 0.5
	end

	self:TryStepUp(deltaTime)

	self:UpdateFootsteps()
	self:UpdateMovementAudio()

	-- Slope Magnet (ported from Moviee-Proj):
	-- If we are slightly airborne over sloped ground (common at ramp seams/crests),
	-- snap downward so "grounded" doesn't flicker and uphill walking remains responsive.
	local wasMagnetized = self:ApplySlopeMagnet()

	if not self.IsGrounded and self.WasGrounded then
		self.AirborneStartTime = tick()
		self.CrouchCancelUsedThisJump = false
	elseif self.IsGrounded then
		self.AirborneStartTime = 0
		self.CrouchCancelUsedThisJump = false
	end

	self:CheckCrouchCancelJump()

	self.LastJumpTime = self.MovementInputProcessor and self.MovementInputProcessor.LastJumpTime or 0

	if not wasMagnetized and not SlidingSystem.IsSlideBuffered then
		self:ApplyAirborneDownforce(deltaTime)
	end

	self:LogSlopeAngle()

	if SlidingSystem.IsSlideBuffered and self.IsGrounded then
		local primaryPart = self.PrimaryPart
		if primaryPart then
			local currentVelocity = primaryPart.AssemblyLinearVelocity
			primaryPart.AssemblyLinearVelocity = Vector3.new(
				currentVelocity.X,
				-50,
				currentVelocity.Z
			)
		end

		local currentDirection = self:CalculateMovementDirection()
		local currentCameraAngle = math_deg(self.CachedCameraYAngle)

		if currentDirection.Magnitude > 0 then
			SlidingSystem:StartSlide(currentDirection, currentCameraAngle)
		else
			SlidingSystem:CancelSlideBuffer("No movement input at landing")
		end
	end

	if SlidingSystem.IsJumpCancelBuffered and self.IsGrounded then
		local bufferedDirection = SlidingSystem.BufferedJumpCancelDirection
		SlidingSystem:ExecuteJumpCancel(bufferedDirection, self)
		SlidingSystem:CancelJumpCancelBuffer()
	end

	if not MovementStateManager:IsSliding() then
		self:UpdateRotation()
		self:ApplyMovement()
	else
		-- Sliding movement is handled by SlidingSystem; ensure walking VectorForce can't "push" during slide.
		if self.VectorForce then
			self.VectorForce.Force = Vector3.zero
		end
	end

	if self.MovementInputProcessor then
		self.MovementInputProcessor:UpdateAutoJump()
	end

	if self.MovementInputProcessor and self.MovementInputProcessor:ShouldProcessJump() then
		self.MovementInputProcessor:ProcessJumpInput()
	end

	local fullVelocity = self.PrimaryPart and self.PrimaryPart.AssemblyLinearVelocity or Vector3.zero
	local horizontalSpeed = Vector3.new(fullVelocity.X, 0, fullVelocity.Z).Magnitude
	local verticalSpeed = math.abs(fullVelocity.Y) * 0.5
	local effectiveSpeed = math.sqrt(horizontalSpeed * horizontalSpeed + verticalSpeed * verticalSpeed)
	FOVController:UpdateMomentum(effectiveSpeed)

	if self.PrimaryPart then
		local fallSpeed = math.abs(fullVelocity.Y)
		local speedForFx = math.max(horizontalSpeed, fallSpeed)

		if not MovementStateManager:IsSliding() then
			VFXRep:Fire("Others", { Module = "Speed" }, {
				direction = fullVelocity,
				speed = speedForFx,
			})
		else
			VFXRep:Fire("Others", { Module = "Speed" }, {
				direction = Vector3.zero,
				speed = 0,
			})
		end
	end
end

function CharacterController:ApplySlopeMagnet()
	if not self.Character or not self.PrimaryPart or not self.RaycastParams then
		return false
	end

	local magnetConfig = Config.Gameplay.Character.SlopeMagnet
	if not magnetConfig or not magnetConfig.Enabled then
		return false
	end

	-- Only apply when NOT grounded (slightly airborne) and not ascending.
	if self.IsGrounded then
		return false
	end

	local lastJumpTime = self.MovementInputProcessor and self.MovementInputProcessor.LastJumpTime or 0
	if lastJumpTime > 0 and (tick() - lastJumpTime) < (magnetConfig.JumpCooldown or 0.25) then
		return false
	end

	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
	if currentVelocity.Y > 0 then
		return false
	end

	local rayOrigin = self.PrimaryPart.Position
	local rayDirection = Vector3.new(0, -(magnetConfig.RayLength or 3.0), 0)
	local rayResult = workspace:Raycast(rayOrigin, rayDirection, self.RaycastParams)
	if not rayResult then
		return false
	end

	local groundDistance = rayResult.Distance
	local minHeight = magnetConfig.MinAirborneHeight or 0.5
	if groundDistance < minHeight then
		return false
	end

	self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		magnetConfig.SnapVelocity or -80,
		currentVelocity.Z
	)

	return true
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
	if not self.CameraController then
		return
	end

	-- Check if camera mode wants character to rotate to camera yaw
	local shouldRotateToCamera = true
	if self.CameraController.ShouldRotateCharacterToCamera then
		shouldRotateToCamera = self.CameraController:ShouldRotateCharacterToCamera()
	end

	if shouldRotateToCamera then
		-- Shoulder/FirstPerson: Rotate character to face camera direction
		if self.CameraRotationChanged then
			MovementUtils:SetCharacterRotation(self.AlignOrientation, self.CachedCameraYAngle)
		end
	else
		-- Orbit mode: Rotate character to face MOVEMENT direction (if moving)
		if self.MovementInput.Magnitude > 0.1 then
			local movementDirection = self:CalculateMovement()
			if movementDirection.Magnitude > 0.1 then
				local targetYAngle = math.atan2(-movementDirection.X, -movementDirection.Z)
				MovementUtils:SetCharacterRotation(self.AlignOrientation, targetYAngle)
			end
		end
	end
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
	local graceTime = Config.Gameplay.Sliding.JumpCancel.GroundedGraceTime or 0
	if graceTime > 0 and SlidingSystem and SlidingSystem.LastJumpCancelTime and SlidingSystem.LastJumpCancelTime > 0 then
		local age = tick() - SlidingSystem.LastJumpCancelTime
		if age >= 0 and age < graceTime then
			self.IsGrounded = false
			MovementStateManager:UpdateGroundedState(false)
			self:DebugGroundDetection()
			return
		end
	end

	self.IsGrounded = MovementUtils:CheckGrounded(self.Character, self.PrimaryPart, self.RaycastParams)

	MovementStateManager:UpdateGroundedState(self.IsGrounded)
	self:DebugGroundDetection()

	if not self.WasGrounded and self.IsGrounded then
		self.JustLanded = true
		self.LandingVelocity = self.LastFrameVelocity or self.PrimaryPart.AssemblyLinearVelocity

		local landConfig = Config.Gameplay.VFX and Config.Gameplay.VFX.Land
		local minFallVelocity = landConfig and landConfig.MinFallVelocity or 60
		local fallSpeed = math.abs(self.LandingVelocity.Y)

		if fallSpeed >= minFallVelocity then
			local feetPosition = self.FeetPart and self.FeetPart.Position or self.PrimaryPart.Position
			VFXRep:Fire("All", { Module = "Land" }, { position = feetPosition })
		end
	else
		self.JustLanded = false
	end

	self.LastFrameVelocity = self.PrimaryPart.AssemblyLinearVelocity

	if self.IsGrounded then
		self.LastGroundedTime = tick()
		WallJumpUtils:ResetCharges()
		
		-- Reset crouch state on landing if crouch isn't held
		if self.JustLanded then
			self:_handleLandingCrouchReset()
		end
	end

	local lastJumpTime = self.MovementInputProcessor and self.MovementInputProcessor.LastJumpTime or 0
end

-- Handle crouch state reset when landing
function CharacterController:_handleLandingCrouchReset()
	-- Skip if sliding (slide handles its own state)
	if MovementStateManager:IsSliding() then
		return
	end
	
	local isCrouchHeld = self.InputManager and self.InputManager:IsCrouchHeld()
	local isVisuallyCrouched = self.Character and CrouchUtils:IsVisuallycrouched(self.Character)
	
	-- If we're visually crouched but not holding crouch, uncrouch
	if isVisuallyCrouched and not isCrouchHeld then
		self.IsCrouching = false
		if self.InputManager then
			self.InputManager.IsCrouching = false
		end
		
		if self:CanUncrouch() then
			CrouchUtils:Uncrouch(self.Character)
			CrouchUtils:RemoveVisualCrouch(self.Character)
			Net:FireServer("CrouchStateChanged", false)
			
			local shouldRestoreSprint = Config.Gameplay.Character.AutoSprint
			if shouldRestoreSprint then
				MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
			else
				MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
			end
		else
			-- Can't uncrouch (blocked), start checking
			self:StartUncrouchChecking()
		end
	elseif isCrouchHeld and not isVisuallyCrouched then
		-- Player is holding crouch but not visually crouched (started crouch in air)
		-- Apply crouch now that we've landed
		self.IsCrouching = true
		if self.InputManager then
			self.InputManager.IsCrouching = true
		end
		CrouchUtils:Crouch(self.Character)
		MovementStateManager:TransitionTo(MovementStateManager.States.Crouching)
	end
end

function CharacterController:DebugMovementInput(wasMoving, isMoving, movement)
	if not ConfigCache.DEBUG_MOVEMENT_INPUT then
		return
	end

	local now = tick()
	local minInterval = 0.2
	if (now - (self.LastMovementDebugTime or 0)) < minInterval and wasMoving == isMoving then
		return
	end

	self.LastMovementDebugTime = now
end

function CharacterController:DebugGroundDetection()
	local showRaycast = Config.System.Debug.ShowGroundRaycast == true
	if not ConfigCache.DEBUG_GROUND_DETECTION and not showRaycast then
		return
	end

	local now = tick()
	local minInterval = 0.25
	local stateChanged = self.WasGrounded ~= self.IsGrounded
	if not stateChanged and (now - (self.LastGroundDebugTime or 0)) < minInterval then
		return
	end

	self.LastGroundDebugTime = now

	local info = MovementUtils:GetGroundCheckDebugInfo(self.Character, self.PrimaryPart, self.RaycastParams)
	if not info then
		if ConfigCache.DEBUG_GROUND_DETECTION then
			warn("[MOVEMENT][GROUND] debug skipped - missing ground info")
		end
		return
	end

	local hitCount = 0
	local hitParts = {}
	for _, ray in ipairs(info.rays or {}) do
		if ray.hit and ray.instance then
			hitCount += 1
			table.insert(hitParts, string.format("%s(%s)", ray.instance.Name, ray.instance.CollisionGroup))
		end
	end

	local params = info.params or {}
	local nonCollideNote = ""
	if info.nonCollideHit and info.nonCollideHit.instance then
		nonCollideNote = string.format(" nonCollideHit=%s", info.nonCollideHit.instance.Name)
	end

	if stateChanged or hitCount == 0 then
		local hitSummary = (#hitParts > 0) and table.concat(hitParts, ", ") or "none"
	end

	if showRaycast then
		self:UpdateGroundRayDebugVisual(info)
	else
		self:ClearGroundRayDebugVisual()
	end
end

function CharacterController:UpdateGroundRayDebugVisual(info)
	if not info then
		return
	end

	local folder = self.GroundRayDebugFolder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		local playerId = Players.LocalPlayer and Players.LocalPlayer.UserId or "Local"
		folder.Name = "GroundRayDebug_" .. tostring(playerId)
		folder.Parent = workspace
		self.GroundRayDebugFolder = folder
		self.GroundRayDebugParts = {}
	end

	local rays = info.rays or {}
	for index, ray in ipairs(rays) do
		local debugSet = self.GroundRayDebugParts[index]
		if not debugSet then
			debugSet = {}

			local rayPart = Instance.new("Part")
			rayPart.Name = "Ray" .. tostring(index)
			rayPart.Anchored = true
			rayPart.CanCollide = false
			rayPart.CanQuery = false
			rayPart.CanTouch = false
			rayPart.CastShadow = false
			rayPart.Material = Enum.Material.Neon
			rayPart.Transparency = 0.35
			rayPart.Parent = folder
			debugSet.rayPart = rayPart

			local hitPart = Instance.new("Part")
			hitPart.Name = "Hit" .. tostring(index)
			hitPart.Shape = Enum.PartType.Ball
			hitPart.Anchored = true
			hitPart.CanCollide = false
			hitPart.CanQuery = false
			hitPart.CanTouch = false
			hitPart.CastShadow = false
			hitPart.Material = Enum.Material.Neon
			hitPart.Size = Vector3.new(0.2, 0.2, 0.2)
			hitPart.Parent = folder
			debugSet.hitPart = hitPart

			self.GroundRayDebugParts[index] = debugSet
		end

		local origin = ray.origin
		local direction = info.rayDirection
		local length = direction.Magnitude
		if ray.hit and ray.distance then
			length = ray.distance
		end

		local rayPart = debugSet.rayPart
		if rayPart then
			rayPart.Size = Vector3.new(0.08, 0.08, math.max(length, 0.05))
			rayPart.CFrame = CFrame.new(origin, origin + direction) * CFrame.new(0, 0, -length / 2)
			rayPart.Color = ray.hit and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 80, 80)
			rayPart.Transparency = ray.hit and 0.2 or 0.45
		end

		local hitPart = debugSet.hitPart
		if hitPart then
			if ray.hit and ray.position then
				hitPart.CFrame = CFrame.new(ray.position)
				hitPart.Color = Color3.fromRGB(0, 255, 0)
				hitPart.Transparency = 0
				hitPart.Size = Vector3.new(0.2, 0.2, 0.2)
			else
				hitPart.Transparency = 1
			end
		end
	end
end

function CharacterController:ClearGroundRayDebugVisual()
	if self.GroundRayDebugFolder and self.GroundRayDebugFolder.Parent then
		self.GroundRayDebugFolder:Destroy()
	end
	self.GroundRayDebugFolder = nil
	self.GroundRayDebugParts = nil
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

function CharacterController:TryStepUp(deltaTime)
	if not self.PrimaryPart or not self.FeetPart or not self.RaycastParams then
		return
	end

	local stepHeight = 1.1
	local forwardDistance = 2.0
	local cooldown = 0.12

	local moveVector = self:CalculateMovement()
	local horizontal = Vector3.new(moveVector.X, 0, moveVector.Z)
	if horizontal.Magnitude < 0.05 then
		return
	end

	local forward = horizontal.Unit
	local feet = self.FeetPart
	local feetSize = feet.Size
	local feetBottomY = feet.Position.Y - (feetSize.Y * 0.5)

	local midOrigin = Vector3.new(feet.Position.X, feetBottomY + 0.9, feet.Position.Z)

	local hitLow = workspace:Raycast(midOrigin, forward * forwardDistance, self.RaycastParams)
	if hitLow then
		local highOrigin = Vector3.new(feet.Position.X, feetBottomY + stepHeight, feet.Position.Z)
		local hitHigh = workspace:Raycast(highOrigin, forward * forwardDistance, self.RaycastParams)
		if not hitHigh then
			local downOrigin = Vector3.new(
				feet.Position.X,
				feetBottomY + stepHeight + 0.5,
				feet.Position.Z
			) + (forward * forwardDistance)
			local downDistance = stepHeight + 1
			local hitDown = workspace:Raycast(
				downOrigin,
				Vector3.new(0, -downDistance, 0),
				self.RaycastParams
			)
			if hitDown and hitDown.Normal.Y >= 0.6 then
				local stepDelta = hitDown.Position.Y - feetBottomY
				if stepDelta > 0.05 and stepDelta <= stepHeight then
					local now = tick()
					if (now - (self.LastStepUpTime or 0)) >= cooldown then
						self.StepUpRemaining = math.max(self.StepUpRemaining or 0, stepDelta)
						self.LastStepUpTime = now
						local gravity = workspace.Gravity
						self.StepUpRequiredVelocity = math.sqrt(2 * gravity * stepDelta) * 0.6
						self.StepUpBoostTime = 0.07
					end
				end
			end
		end
	end

	if self.StepUpBoostTime and self.StepUpBoostTime > 0 then
		local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
		local required = self.StepUpRequiredVelocity or 0
		if currentVelocity.Y < 0 then
			required = required + 1
		end
		if required > 0 then
			local newY = math.max(currentVelocity.Y, required)
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
				currentVelocity.X,
				newY,
				currentVelocity.Z
			)
		end
		self.StepUpBoostTime = math.max(0, self.StepUpBoostTime - deltaTime)
		if self.StepUpBoostTime == 0 then
			self.StepUpRemaining = 0
			self.StepUpRequiredVelocity = 0
		end
	end
end

function CharacterController:ApplyMovement()
	local moveVector = self:CalculateMovement()
	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
	local isMoving = self.MovementInput.Magnitude > 0

	MovementUtils:UpdateStandingFriction(self.Character, self.PrimaryPart, self.RaycastParams, isMoving)

	local targetSpeed = Config.Gameplay.Character.WalkSpeed
	if MovementStateManager:IsSprinting() then
		targetSpeed = Config.Gameplay.Character.SprintSpeed
	elseif MovementStateManager:IsCrouching() then
		targetSpeed = Config.Gameplay.Character.CrouchSpeed
	end

	-- Apply weapon speed multipliers only when not sprinting
	local localPlayer = Players.LocalPlayer
	local weaponMult = localPlayer and localPlayer:GetAttribute("WeaponSpeedMultiplier") or 1
	local adsMult = localPlayer and localPlayer:GetAttribute("ADSSpeedMultiplier") or 1
	if not MovementStateManager:IsSprinting() then
		local weaponSpeedModifier = weaponMult * adsMult
		targetSpeed = targetSpeed * weaponSpeedModifier
	end
	
	-- Apply emote speed multiplier (always applies, even when sprinting)
	local emoteMult = localPlayer and localPlayer:GetAttribute("EmoteSpeedMultiplier") or 1
	targetSpeed = targetSpeed * emoteMult

	local weightMultiplier = 1.0

	local timeSinceWallJump = tick() - WallJumpUtils.LastWallJumpTime
	local wallJumpImmunity = 0.5

	local isHittingWall = false
	local wallNormal = nil
	if timeSinceWallJump > wallJumpImmunity then
		isHittingWall, wallNormal = MovementUtils:CheckWallStopWithNormal(self.PrimaryPart, self.RaycastParams, moveVector)
	end
	local finalMoveVector = moveVector

	if isHittingWall then
		if not self._wallHitLogged then
			self._wallHitLogged = true
		end
		if self.IsGrounded then
			-- Don't hard-stop (feels like an invisible force). Instead, remove the into-wall component
			-- so the player can slide along geometry and still mount ramps/steps.
			local horizontalNormal = wallNormal and Vector3.new(wallNormal.X, 0, wallNormal.Z) or nil
			if horizontalNormal and horizontalNormal.Magnitude > 0.01 then
				horizontalNormal = horizontalNormal.Unit

				-- Remove into-wall component from desired move vector.
				finalMoveVector = finalMoveVector - (finalMoveVector:Dot(horizontalNormal)) * horizontalNormal

				-- Remove into-wall component from current horizontal velocity.
				local hv = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
				local into = hv:Dot(horizontalNormal)
				if into < 0 then
					hv = hv - horizontalNormal * into
					self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(hv.X, currentVelocity.Y, hv.Z)
					currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
				end
			else
				-- Fallback: if no normal, just stop pushing into it.
				finalMoveVector = Vector3.new(0, 0, 0)
			end
		end
	end
	if not isHittingWall then
		self._wallHitLogged = nil
	end

	local horizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local horizontalSpeed = horizontalVelocity.Magnitude

	local isNearWallLook = MovementUtils:CheckWallStop(self.PrimaryPart, self.RaycastParams, self.PrimaryPart.CFrame.LookVector)
	local isNearWallVel = horizontalSpeed > 0.1 and MovementUtils:CheckWallStop(self.PrimaryPart, self.RaycastParams, horizontalVelocity.Unit)
	local isNearWall = isNearWallLook or isNearWallVel

	local totalSpeed = currentVelocity.Magnitude
	local isAirborneStuck = not self.IsGrounded and totalSpeed < 3 and timeSinceWallJump > 0.3

	if isAirborneStuck then
		if not self.AirborneStuckStartTime then
			self.AirborneStuckStartTime = tick()
		end

		local airborneStuckDuration = tick() - self.AirborneStuckStartTime
		if airborneStuckDuration > 0.1 then
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
				currentVelocity.X,
				math.min(currentVelocity.Y, -30),
				currentVelocity.Z
			)
			currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
			self.AirborneStuckStartTime = nil
		end
	else
		self.AirborneStuckStartTime = nil
	end

	local isStuckCondition = not self.IsGrounded and horizontalSpeed < 5 and isNearWall

	if isStuckCondition then
		if not self.WallStuckStartTime then
			self.WallStuckStartTime = tick()
		end

		local stuckDuration = tick() - self.WallStuckStartTime
		if stuckDuration > 0.15 then
			local _, stuckWallNormal = MovementUtils:CheckWallStopWithNormal(
				self.PrimaryPart,
				self.RaycastParams,
				self.PrimaryPart.CFrame.LookVector
			)
			if not stuckWallNormal and horizontalSpeed > 0.1 then
				_, stuckWallNormal = MovementUtils:CheckWallStopWithNormal(
					self.PrimaryPart,
					self.RaycastParams,
					horizontalVelocity.Unit
				)
			end

			if not self._wallStuckLogged then
				self._wallStuckLogged = true
			end

			if stuckWallNormal then
				local escapeDir = Vector3.new(stuckWallNormal.X, 0, stuckWallNormal.Z)
				if escapeDir.Magnitude > 0.01 then
					escapeDir = escapeDir.Unit
					self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
						escapeDir.X * 30,
						math.max(currentVelocity.Y, 5),
						escapeDir.Z * 30
					)
					currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
				end
			else
				local backDir = -self.PrimaryPart.CFrame.LookVector
				self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
					backDir.X * 25,
					math.max(currentVelocity.Y, 10),
					backDir.Z * 25
				)
				currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
			end
			self.WallStuckStartTime = nil
			self._wallStuckLogged = nil
		end
	else
		self.WallStuckStartTime = nil
		self._wallStuckLogged = nil
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

	local verticalForce = 0
	local mass = self.PrimaryPart.AssemblyMass

	if ConfigCache.FALL_SPEED_ENABLED and not self.IsGrounded then
		local currentYVelocity = currentVelocity.Y
		local absYVelocity = math.abs(currentYVelocity)

		if currentYVelocity > 0 then
			local ascentGravityReduction = Config.Gameplay.Character.FallSpeed.AscentGravityReduction or 0.4
			verticalForce = ConfigCache.WORLD_GRAVITY * mass * ascentGravityReduction
		elseif absYVelocity < ConfigCache.HANG_TIME_THRESHOLD then
			local hangDrag = ConfigCache.HANG_TIME_DRAG or 0.05
			local hangForce = ConfigCache.WORLD_GRAVITY * mass * hangDrag
			verticalForce = hangForce
		else
			local fallAcceleration = Config.Gameplay.Character.FallSpeed.FallAcceleration or 40
			local maxFallSpeed = ConfigCache.MAX_FALL_SPEED

			if absYVelocity > maxFallSpeed then
				local terminalForce = ConfigCache.WORLD_GRAVITY * mass
				local damping = (absYVelocity - maxFallSpeed) * ConfigCache.FALL_DRAG_MULTIPLIER * mass
				verticalForce = terminalForce + damping
			else
				verticalForce = -fallAcceleration * mass
			end
		end
	end

	-- Simple force application (like Moviee-Proj):
	-- NO adhesion, NO surface projection for normal walking.
	-- Roblox physics handles ground contact naturally.
	-- Adhesion/sticky ground is ONLY used during sliding (handled by SlidingSystem).
	-- NOTE: We *do* allow a slope-tangent Y component while grounded (computed in MovementUtils),
	-- but still keep airborne vertical forces driven by fall tuning.
	local appliedY = verticalForce
	if self.IsGrounded then
		appliedY = moveForce.Y
	end

	-- WEDGE / RAMP ASSIST:
	-- Cancel the component of gravity that acts *along* the slope so:
	-- - standing mid-ramp doesn't slowly slide back
	-- - moving uphill doesn't feel like slow motion (you aren't fighting gravity every frame)
	-- We do NOT cancel gravity into the surface (normal component), so the character still
	-- stays pressed into the ramp naturally.
	local slopeAssistForce = Vector3.zero
	if self.IsGrounded and self.Character and self.PrimaryPart and self.RaycastParams then
		local grounded, groundNormal, slopeDegrees =
			MovementUtils:CheckGroundedWithSlope(self.Character, self.PrimaryPart, self.RaycastParams)

		if grounded and groundNormal then
			local maxWalkableAngle = Config.Gameplay.Character.MaxWalkableSlopeAngle
			if slopeDegrees > 0.5 and slopeDegrees <= maxWalkableAngle then
				local gravityAccel = ConfigCache.WORLD_GRAVITY or workspace.Gravity
				local gravity = Vector3.new(0, -gravityAccel, 0)
				local gravityParallel = gravity - (gravity:Dot(groundNormal)) * groundNormal
				slopeAssistForce = -gravityParallel * mass
			end
		end
	end

	local dt = self.LastDeltaTime or (1 / 60)
	local smoothing = Config.Gameplay.Character.FallSpeed.VerticalForceLerp or 12
	self.SmoothedVerticalForce = self.SmoothedVerticalForce
		+ (appliedY - self.SmoothedVerticalForce) * math.clamp(smoothing * dt, 0, 1)

	local finalForce = vector3_new(moveForce.X, self.SmoothedVerticalForce, moveForce.Z) + slopeAssistForce
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

function CharacterController:PlayMovementSound(soundName, _position, pitch)
	if not soundName then
		return
	end

	SoundManager:PlaySound("Movement", soundName, self.PrimaryPart, pitch)
end

function CharacterController:UpdateFootsteps()
	if not self.Character or not self.PrimaryPart then
		return
	end

	if not self.IsGrounded or MovementStateManager:IsSliding() then
		return
	end

	local velocity = self.PrimaryPart.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	local footstepConfig = Config.Audio and Config.Audio.Footsteps
	if not footstepConfig then
		return
	end

	local minSpeed = footstepConfig.MinSpeed or 2
	if horizontalSpeed < minSpeed then
		return
	end

	local factor = footstepConfig.Factor or 8.1
	if MovementStateManager:IsCrouching() then
		factor = footstepConfig.CrouchFactor or 12.0
	elseif MovementStateManager:IsSprinting() then
		factor = footstepConfig.SprintFactor or 6.0
	end

	local walkSpeed = Config.Gameplay.Character.WalkSpeed or 16
	local effectiveSpeed = math.max(horizontalSpeed, walkSpeed * 0.5)
	local footstepInterval = factor / effectiveSpeed

	local now = tick()
	if (now - self.LastFootstepTime) < footstepInterval then
		return
	end

	self.LastFootstepTime = now

	local grounded, materialName = MovementUtils:CheckGroundedWithMaterial(
		self.Character,
		self.PrimaryPart,
		self.RaycastParams
	)

	if not grounded or not materialName then
		return
	end

	local soundName = (footstepConfig.MaterialMap and footstepConfig.MaterialMap[materialName])
		or footstepConfig.DefaultSound
		or "FootstepConcrete"

	local feetPart = CharacterLocations:GetFeet(self.Character) or self.PrimaryPart
	local pitch = 0.9 + math.random() * 0.2
	self:PlayMovementSound(soundName, feetPart.Position, pitch)
end

function CharacterController:UpdateMovementAudio()
	if not self.PrimaryPart then
		return
	end

	local movementSounds = Config.Audio and Config.Audio.Sounds and Config.Audio.Sounds.Movement
	if not movementSounds then
		return
	end

	-- Jump / SlideLaunch / WallJump sound
	local lastJumpTime = self.MovementInputProcessor and self.MovementInputProcessor.LastJumpTime or 0
	if lastJumpTime > self.LastJumpSoundTime then
		self.LastJumpSoundTime = lastJumpTime

		local isSlideLaunch = math.abs(lastJumpTime - SlidingSystem.LastJumpCancelTime) < 0.05
		local lastWallJumpTime = self.MovementInputProcessor.LastWallJumpTime or 0
		local isWallJump = math.abs(lastJumpTime - lastWallJumpTime) < 0.05

		if isSlideLaunch then
			self:PlayMovementSound("SlideLaunch", self.PrimaryPart.Position, movementSounds.SlideLaunch and movementSounds.SlideLaunch.Pitch)
			VFXRep:Fire("Others", { Module = "Sound" }, { sound = "SlideLaunch", pitch = movementSounds.SlideLaunch and movementSounds.SlideLaunch.Pitch })
		elseif isWallJump then
			self:PlayMovementSound("WallJump", self.PrimaryPart.Position, movementSounds.WallJump and movementSounds.WallJump.Pitch)
			VFXRep:Fire("Others", { Module = "Sound" }, { sound = "WallJump", pitch = movementSounds.WallJump and movementSounds.WallJump.Pitch })
		else
			self:PlayMovementSound("Jump", self.PrimaryPart.Position, movementSounds.Jump and movementSounds.Jump.Pitch)
			VFXRep:Fire("Others", { Module = "Sound" }, { sound = "Jump", pitch = movementSounds.Jump and movementSounds.Jump.Pitch })
		end
	end

	-- Falling looped sound
	local velocity = self.PrimaryPart.AssemblyLinearVelocity
	if not self.IsGrounded then
		if velocity.Y < -80 then
			if not self.FallSound or not self.FallSound.IsPlaying then
				self:StartFallSound()
			end
		end
	else
		if self.FallSound and self.FallSound.IsPlaying then
			self:StopFallSound()
		end
	end

	-- Landing: play footstep for the material you land on
	if self.IsGrounded and not self.WasGrounded then
		-- Stop fall sound immediately on landing
		if self.FallSound and self.FallSound.IsPlaying then
			self:StopFallSound()
		end

		local footstepConfig = Config.Audio and Config.Audio.Footsteps
		if footstepConfig then
			local _, materialName = MovementUtils:CheckGroundedWithMaterial(
				self.Character,
				self.PrimaryPart,
				self.RaycastParams
			)
			local soundName = (materialName and footstepConfig.MaterialMap and footstepConfig.MaterialMap[materialName])
				or footstepConfig.DefaultSound
				or "FootstepConcrete"
			local pitch = 0.9 + math.random() * 0.2
			self:PlayMovementSound(soundName, self.PrimaryPart.Position, pitch)
			VFXRep:Fire("Others", { Module = "Sound" }, { sound = soundName, pitch = pitch })
		end
	end
end

function CharacterController:EnsureFallSound()
	if self.FallSound and self.FallSound.Parent then
		return self.FallSound
	end

	if not self.PrimaryPart then
		return nil
	end

	local definition = Config.Audio and Config.Audio.Sounds and Config.Audio.Sounds.Movement
		and Config.Audio.Sounds.Movement.Falling
	if not definition or not definition.Id then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "FallLoop"
	sound.SoundId = definition.Id
	sound.Volume = 0
	sound.PlaybackSpeed = definition.Pitch or 1.0
	sound.RollOffMode = definition.RollOffMode or Enum.RollOffMode.Linear
	sound.EmitterSize = definition.EmitterSize or 10
	sound.MinDistance = definition.MinDistance or 5
	sound.MaxDistance = definition.MaxDistance or 30
	sound.Looped = true

	local soundGroup = game:GetService("SoundService"):FindFirstChild("Movement")
	if soundGroup and soundGroup:IsA("SoundGroup") then
		sound.SoundGroup = soundGroup
	end

	sound.Parent = self.PrimaryPart
	self.FallSound = sound
	self.FallSoundTargetVolume = definition.Volume or 0.6
	return sound
end

function CharacterController:StartFallSound()
	local sound = self:EnsureFallSound()
	if not sound then
		return
	end

	if not sound.IsPlaying then
		sound.Volume = 0
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = self.FallSoundTargetVolume or 0.6,
		}):Play()
		VFXRep:Fire("Others", { Module = "Sound" }, { sound = "Falling", action = "start" })
	end
end

function CharacterController:StopFallSound()
	if self.FallSound and self.FallSound.IsPlaying then
		self.FallSound:Stop()
		self.FallSound.Volume = 0
		VFXRep:Fire("Others", { Module = "Sound" }, { sound = "Falling", action = "stop" })
	end
end

-- =============================================================================
-- INPUT HANDLING
-- =============================================================================

function CharacterController:HandleSprint(isSprinting)
	if not self.Character then
		return
	end

	-- Bleed status effect: force walk speed (disable sprinting)
	if self.Character:GetAttribute("Bleed") == true then
		if MovementStateManager:IsSprinting() then
			MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
		end
		return
	end

	local autoSprint = Config.Gameplay.Character.AutoSprint

	if isSprinting or autoSprint then
		if MovementStateManager:IsWalking() then
			MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
		end
	else
		if MovementStateManager:IsSprinting() then
			MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
		end
	end
end

function CharacterController:HandleCrouch(isCrouching)
	if not self.Character then
		return
	end

	if isCrouching then
		self:StopUncrouchChecking()
		CrouchUtils:Crouch(self.Character)
		local movementSounds = Config.Audio and Config.Audio.Sounds and Config.Audio.Sounds.Movement
		if movementSounds and movementSounds.Crouch and self.PrimaryPart then
			local pitch = movementSounds.Crouch.Pitch
			self:PlayMovementSound("Crouch", self.PrimaryPart.Position, pitch)
			VFXRep:Fire("Others", { Module = "Sound" }, { sound = "Crouch", pitch = pitch })
		end
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
			local canBuffer = SlidingSystem:CanBufferSlide(
				self.MovementInput,
				true,
				self.IsGrounded,
				self
			)
			if canBuffer then
				SlidingSystem:StartSlideBuffer(movementDirection, false)
			end
		end
	else
		if SlidingSystem.IsSliding then
			SlidingSystem:StopSlide(false, true, "ManualRelease")
		end

		self:StopUncrouchChecking()
		self.IsCrouching = false
		if self.InputManager then
			self.InputManager.IsCrouching = false
		end

		if self.Character and CrouchUtils:IsVisuallycrouched(self.Character) then
			CrouchUtils:Uncrouch(self.Character)
			CrouchUtils:RemoveVisualCrouch(self.Character)
			Net:FireServer("CrouchStateChanged", false)
		end

		if not MovementStateManager:IsWalking() and not MovementStateManager:IsSprinting() then
			local shouldSprint = self.IsSprinting or Config.Gameplay.Character.AutoSprint
			if shouldSprint then
				MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
			else
				MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
			end
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
				local currentCameraAngle = math_deg(self.CachedCameraYAngle)
				SlidingSystem:StartSlide(movementDirection, currentCameraAngle)
				return
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
				local movementDirection = self:CalculateMovementDirection()
				if movementDirection.Magnitude > 0 then
					SlidingSystem:StartSlideBuffer(movementDirection, false)
				end
				return
			end
		end

		self:HandleCrouch(isCrouching)
	else
		if SlidingSystem.IsSliding then
			if CrouchUtils:IsVisuallycrouched(self.Character) and not self:CanUncrouch() then
				SlidingSystem:StopSlide(true, false, "ManualUncrouchRelease")
				self:StartUncrouchChecking()
				return
			else
				SlidingSystem:StopSlide(false, true, "ManualUncrouchRelease")
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

	local excluded = { self.Character }
	local rig = CharacterLocations:GetRig(self.Character)
	if rig then
		table.insert(excluded, rig)
	end
	local rigsFolder = workspace:FindFirstChild("Rigs")
	if rigsFolder then
		table.insert(excluded, rigsFolder)
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = excluded
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

	-- Check if player is still holding crouch
	local isCrouchHeld = self.InputManager and self.InputManager:IsCrouchHeld()
	
	if isCrouchHeld then
		-- Player is holding crouch, stay crouched
		self.IsCrouching = true
		if not CrouchUtils.CharacterCrouchState[self.Character] then
			CrouchUtils.CharacterCrouchState[self.Character] = {
				IsCrouched = true,
			}
		else
			CrouchUtils.CharacterCrouchState[self.Character].IsCrouched = true
		end
	else
		-- Player released crouch, start uncrouch process
		self.IsCrouching = false
		if self.InputManager then
			self.InputManager.IsCrouching = false
		end
		
		-- Check if we can uncrouch immediately or need to wait
		if self:CanUncrouch() then
			CrouchUtils:Uncrouch(self.Character)
			CrouchUtils:RemoveVisualCrouch(self.Character)
			Net:FireServer("CrouchStateChanged", false)
			
			local shouldRestoreSprint = Config.Gameplay.Character.AutoSprint
			if shouldRestoreSprint then
				MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
			else
				MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
			end
		else
			-- Can't uncrouch yet (something above), start checking
			self:StartUncrouchChecking()
		end
	end
end

function CharacterController:LogSlopeAngle() end

-- =============================================================================
-- DEATH DETECTION
-- =============================================================================

function CharacterController:CheckDeath()
	local currentPosition = self.PrimaryPart.Position
	local deathThreshold = Config.Gameplay.Character.DeathYThreshold

	if currentPosition.Y < deathThreshold then
		if self.RespawnRequested then
			return
		end

		warn(("[CHAR_DEATH] below_threshold y=%.2f threshold=%.2f"):format(currentPosition.Y, deathThreshold))
		self.RespawnRequested = true

		-- Clear local movement forces/state immediately; server will handle respawn.
		if SlidingSystem and SlidingSystem.IsSliding then
			SlidingSystem:StopSlide(false, true, "Death")
		end
		SlidingSystem:Cleanup()
		MovementStateManager:Reset()

		if self.InputManager then
			self.InputManager:ResetInputState()
		end

		if self.VectorForce then
			self.VectorForce.Force = Vector3.zero
		end

		if self._net then
			self._net:FireServer("RequestRespawn")
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

	self.IsCrouching = false
	CrouchUtils:Uncrouch(self.Character)
	CrouchUtils:RemoveVisualCrouch(self.Character)
	Net:FireServer("CrouchStateChanged", false)
	if self.InputManager then
		self.InputManager.IsCrouching = false
	end

end

function CharacterController:ApplyAirborneDownforce(deltaTime)
	if not self.Character or not self.PrimaryPart then
		return
	end

	if self.IsGrounded then
		self.FloatDecayStartTime = nil
		self.SmoothedGravityMultiplier = nil
		return
	end

	local gravityConfig = Config.Gameplay.Character.GravityDamping
	if not gravityConfig or not gravityConfig.Enabled then
		return
	end

	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity

	if not self.SmoothedGravityMultiplier then
		self.SmoothedGravityMultiplier = 0.1
	end

	local targetGravityMultiplier

	if currentVelocity.Y > 2 then
		targetGravityMultiplier = 0.1
		self.FloatDecayStartTime = tick()
	elseif currentVelocity.Y > -2 then
		targetGravityMultiplier = 0.15
		if not self.FloatDecayStartTime then
			self.FloatDecayStartTime = tick()
		end
	else
		if not self.FloatDecayStartTime then
			self.FloatDecayStartTime = tick()
		end

		local floatDecayConfig = Config.Gameplay.Character.FloatDecay
		local airborneTime = tick() - self.FloatDecayStartTime
		local horizontalSpeed = Vector3.new(currentVelocity.X, 0, currentVelocity.Z).Magnitude

		local baseDamping = gravityConfig.DampingFactor

		if floatDecayConfig and floatDecayConfig.Enabled then
			local baseFloatDuration = floatDecayConfig.FloatDuration or 0.6
			local velocityThreshold = floatDecayConfig.VelocityThreshold or 0.5
			local shrinkRate = floatDecayConfig.ThresholdShrinkRate or 0.005

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

	local linearRate = 0.5
	local difference = targetGravityMultiplier - self.SmoothedGravityMultiplier
	local maxChange = linearRate * deltaTime

	if math.abs(difference) <= maxChange then
		self.SmoothedGravityMultiplier = targetGravityMultiplier
	elseif difference > 0 then
		self.SmoothedGravityMultiplier = self.SmoothedGravityMultiplier + maxChange
	else
		self.SmoothedGravityMultiplier = self.SmoothedGravityMultiplier - maxChange
	end

	local mass = self.PrimaryPart.AssemblyMass
	local gravity = workspace.Gravity
	local dampingForce = mass * gravity * self.SmoothedGravityMultiplier
	if currentVelocity.Y < 0 then
		dampingForce = dampingForce * 1.35
	end

	local newYVelocity = currentVelocity.Y + (dampingForce / mass * deltaTime)

	newYVelocity = math.max(newYVelocity, -gravityConfig.MaxFallSpeed)

	self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		newYVelocity,
		currentVelocity.Z
	)
end

return CharacterController
