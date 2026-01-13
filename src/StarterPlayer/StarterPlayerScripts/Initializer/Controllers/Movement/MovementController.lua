local CharacterController = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local function getMovementTemplate(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	-- Prefer new layout if present: Assets/VFX/MovementFX/<Name>
	local vfx = assets:FindFirstChild("VFX")
	local movement = vfx and vfx:FindFirstChild("MovementFX")
	local fromNew = movement and movement:FindFirstChild(name)
	if fromNew then
		return fromNew
	end
	-- Legacy: Assets/MovementFX/<Name>
	local legacy = assets:FindFirstChild("MovementFX")
	return legacy and legacy:FindFirstChild(name) or nil
end

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

CharacterController.GameplayEnabled = false

-- Vaulting (short movement override)
CharacterController.IsVaulting = false
CharacterController.VaultEndTime = 0

-- Respawn / reset reliability
CharacterController.RespawnRequested = false

function CharacterController:SetGameplayEnabled(enabled: boolean)
	self.GameplayEnabled = enabled == true
	if not self.GameplayEnabled then
		-- Clear any residual input so the character won't drift.
		if self.InputManager then
			self.InputManager:ResetInputState()
		end
	end
end

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
	self.IsVaulting = false
	self.VaultEndTime = 0
	MovementStateManager:Reset()

	if self.CameraController then
		local cameraAngles = self.CameraController:GetCameraAngles()
		local cameraYAngle = math.rad(cameraAngles.X)
		self.CachedCameraYAngle = cameraYAngle
		self.LastCameraAngles = cameraAngles
	end

	self:StartMovementLoop()

end

function CharacterController:OnLocalCharacterRemoving()
	self:StopUncrouchChecking()
	SlidingSystem:Cleanup()

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
	self.IsVaulting = false
	self.VaultEndTime = 0
	self.RespawnRequested = false
	self.JumpExecutedThisInput = false
	self.LastGroundedTime = 0

	self.InputsConnected = false

	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
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
		self.MovementInput = movement
		local isMoving = movement.Magnitude > 0
		MovementStateManager:UpdateMovementState(isMoving)
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
	-- Gameplay gating: do not run movement simulation until StartMatch.
	if self.GameplayEnabled == false then
		return
	end

	if not ValidationUtils:IsPrimaryPartValid(self.PrimaryPart) or not self.VectorForce then
		return
	end

	if self.RespawnRequested then
		self.VectorForce.Force = Vector3.zero
		return
	end

	self:CheckDeath()
	self:UpdateCachedCameraRotation()

	-- Ragdoll interaction: disable client movement forces while ragdolled.
	-- The server ragdoll system welds the character root to a ragdoll; movement forces fighting
	-- that will look choppy. Keep it simple: zero forces and let ragdoll drive motion.
	if self.Character and self.Character:GetAttribute("RagdollActive") == true then
		if SlidingSystem and SlidingSystem.IsSliding then
			SlidingSystem:StopSlide(false, true, "Ragdoll")
		end
		self.IsVaulting = false
		if self.VectorForce then
			self.VectorForce.Force = Vector3.zero
		end
		return
	end

	-- Vaulting lock: briefly disable movement forces so the throw feels intentional.
	if self.IsVaulting then
		if tick() >= (self.VaultEndTime or 0) then
			self.IsVaulting = false
		else
			if self.VectorForce then
				self.VectorForce.Force = Vector3.zero
			end
			return
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

	if SlidingSystem.IsJumpCancelBuffered and self.IsGrounded then
		local bufferedDirection = SlidingSystem.BufferedJumpCancelDirection
		SlidingSystem:ExecuteJumpCancel(bufferedDirection, self)
		SlidingSystem:CancelJumpCancelBuffer()
	end

	if not MovementStateManager:IsSliding() then
		self:UpdateRotation()
		self:ApplyMovement()
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

	local speedFXConfig = Config.Gameplay.VFX and Config.Gameplay.VFX.SpeedFX
	local isSliding = MovementStateManager:IsSliding()

	if speedFXConfig and speedFXConfig.Enabled and self.PrimaryPart and not isSliding then
		local speedThreshold = speedFXConfig.Threshold or 80
		local fallThreshold = speedFXConfig.FallThreshold or 70
		local fallSpeed = math.abs(fullVelocity.Y)

		local shouldShowSpeedFX = horizontalSpeed >= speedThreshold or fallSpeed >= fallThreshold

		if shouldShowSpeedFX then
			if not VFXPlayer:IsActive("SpeedFX") then
				local template = getMovementTemplate("SpeedFX")
				if template then
					VFXPlayer:Start("SpeedFX", template, self.PrimaryPart)
				end
			end
			VFXPlayer:UpdateYaw("SpeedFX", fullVelocity)
		else
			if VFXPlayer:IsActive("SpeedFX") then
				VFXPlayer:Stop("SpeedFX")
			end
		end
	elseif isSliding and VFXPlayer:IsActive("SpeedFX") then
		VFXPlayer:Stop("SpeedFX")
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
	self.IsGrounded = MovementUtils:CheckGrounded(self.Character, self.PrimaryPart, self.RaycastParams)

	MovementStateManager:UpdateGroundedState(self.IsGrounded)

	if not self.WasGrounded and self.IsGrounded then
		self.JustLanded = true
		self.LandingVelocity = self.LastFrameVelocity or self.PrimaryPart.AssemblyLinearVelocity

		local landConfig = Config.Gameplay.VFX and Config.Gameplay.VFX.Land
		local minFallVelocity = landConfig and landConfig.MinFallVelocity or 60
		local fallSpeed = math.abs(self.LandingVelocity.Y)

		if fallSpeed >= minFallVelocity then
			local feetPosition = self.FeetPart and self.FeetPart.Position or self.PrimaryPart.Position
			local template = getMovementTemplate("Land")
			if template then
				VFXPlayer:Play(template, feetPosition)
			end
		end
	else
		self.JustLanded = false
	end

	self.LastFrameVelocity = self.PrimaryPart.AssemblyLinearVelocity

	if self.IsGrounded then
		self.LastGroundedTime = tick()
		WallJumpUtils:ResetCharges()
	end

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

	local timeSinceWallJump = tick() - WallJumpUtils.LastWallJumpTime
	local wallJumpImmunity = 0.5

	local isHittingWall = false
	local wallNormal = nil
	if timeSinceWallJump > wallJumpImmunity then
		isHittingWall, wallNormal = MovementUtils:CheckWallStopWithNormal(self.PrimaryPart, self.RaycastParams, moveVector)
	end
	local finalMoveVector = moveVector

	if isHittingWall then
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
			LogService:Warn("AIR_STUCK", "Player stuck in air - applying gravity", {
				Duration = airborneStuckDuration,
				Velocity = currentVelocity,
				Position = self.PrimaryPart.Position,
			})

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
			LogService:Debug("WALL_STUCK", "Potential stuck detected - starting timer", {
				HorizontalSpeed = horizontalSpeed,
				IsAirborne = not self.IsGrounded,
				TimeSinceWallJump = timeSinceWallJump,
			})
		end

		local stuckDuration = tick() - self.WallStuckStartTime
		if stuckDuration > 0.15 then
			LogService:Warn("WALL_STUCK", "Player stuck against wall - applying escape", {
				StuckDuration = stuckDuration,
				Position = self.PrimaryPart.Position,
				Velocity = currentVelocity,
			})

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
		end
	else
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
			local wallStopConfig = Config.Gameplay.Character.WallStop
			local minWallAngle = (wallStopConfig and wallStopConfig.MinWallAngle) or 70

			if slopeDegrees > 0.5 and slopeDegrees <= maxWalkableAngle and slopeDegrees < minWallAngle then
				local gravityAccel = ConfigCache.WORLD_GRAVITY or workspace.Gravity
				local gravity = Vector3.new(0, -gravityAccel, 0)
				local gravityParallel = gravity - (gravity:Dot(groundNormal)) * groundNormal
				slopeAssistForce = -gravityParallel * mass
			end
		end
	end

	local finalForce = vector3_new(moveForce.X, appliedY, moveForce.Z) + slopeAssistForce
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

function CharacterController:HandleSprint(isSprinting)
	if not self.Character then
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
		end

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
		if self.RespawnRequested then
			return
		end

		self.RespawnRequested = true

		LogService:Info("CHARACTER", "Death detected (fell off map) - requesting respawn", {
			Position = currentPosition,
			Threshold = deathThreshold,
		})

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

	local newYVelocity = currentVelocity.Y + (dampingForce / mass * deltaTime)

	newYVelocity = math.max(newYVelocity, -gravityConfig.MaxFallSpeed)

	self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		newYVelocity,
		currentVelocity.Z
	)
end

return CharacterController
