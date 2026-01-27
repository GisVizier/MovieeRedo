local CameraController = {}

function CameraController:SetGameplayEnabled(_enabled: boolean)
	-- No-op; UpdateCamera checks InputController.Manager.GameplayEnabled.
end

-- Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Module references
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))
local ScreenShakeController = require(script.Parent:WaitForChild("ScreenShakeController"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local function debugPrint(...) end
local function agentLog(...) end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================
local function clamp(value, minValue, maxValue)
	return math.max(minValue, math.min(maxValue, value))
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function getCurrentCamera()
	return workspace.CurrentCamera
end

-- =============================================================================
-- CAMERA SAFETY (Prevent camera going below ground)
-- =============================================================================
local CAMERA_GROUND_CLAMP_CLEARANCE = 0.35
local CAMERA_GROUND_CLAMP_RAY_UP = 6
local CAMERA_GROUND_CLAMP_RAY_DOWN = 80

function CameraController:_getEnvironmentRaycastParams()
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {}

	if self.Character then
		table.insert(raycastParams.FilterDescendantsInstances, self.Character)
	end
	if self.Rig then
		table.insert(raycastParams.FilterDescendantsInstances, self.Rig)
	end

	-- IMPORTANT: Never let camera collision hit any rigs or ragdolls
	local rigsFolder = workspace:FindFirstChild("Rigs")
	if rigsFolder then
		table.insert(raycastParams.FilterDescendantsInstances, rigsFolder)
	end
	local ragdollsFolder = workspace:FindFirstChild("Ragdolls")
	if ragdollsFolder then
		table.insert(raycastParams.FilterDescendantsInstances, ragdollsFolder)
	end
	local entitiesFolder = workspace:FindFirstChild("Entities")
	if entitiesFolder then
		table.insert(raycastParams.FilterDescendantsInstances, entitiesFolder)
	end

	return raycastParams
end

function CameraController:_clampPositionAboveGround(pos: Vector3, clearance: number?): Vector3
	local padding = clearance or CAMERA_GROUND_CLAMP_CLEARANCE
	local origin = pos + Vector3.new(0, CAMERA_GROUND_CLAMP_RAY_UP, 0)
	local dir = Vector3.new(0, -CAMERA_GROUND_CLAMP_RAY_DOWN, 0)

	local result = workspace:Raycast(origin, dir, self:_getEnvironmentRaycastParams())
	if not result then
		return pos
	end

	local minY = result.Position.Y + padding
	if pos.Y < minY then
		return Vector3.new(pos.X, minY, pos.Z)
	end

	return pos
end

-- =============================================================================
-- STATE
-- =============================================================================
CameraController.Character = nil
CameraController.PrimaryPart = nil
CameraController.Head = nil
CameraController.Rig = nil
CameraController.RigHead = nil

-- Connections
CameraController.Connection = nil
CameraController.InputConnection = nil
CameraController.InputBeganConnection = nil
CameraController.InputEndedConnection = nil

-- Camera angles (yaw/pitch)
CameraController.AngleX = 0       -- Pitch (vertical)
CameraController.AngleY = 0       -- Yaw (horizontal)
CameraController.TargetAngleX = 0
CameraController.TargetAngleY = 0

-- Controller stick input
CameraController.RightStickX = 0
CameraController.RightStickY = 0

-- Mobile camera input
CameraController.MobileCameraX = 0
CameraController.MobileCameraY = 0

-- Timing
CameraController.LastFrameTime = 0

-- Crouch transition
CameraController.IsCrouching = false
CameraController.LastCrouchState = false
CameraController.CurrentCrouchOffset = 0
CameraController.IsTransitioning = false

-- Camera mode system
CameraController.CurrentMode = nil
CameraController.CurrentModeIndex = 1

-- Camera mode transition
CameraController.IsModeTransitioning = false
CameraController.ModeTransitionStartT = 0
CameraController.ModeTransitionDuration = 0.15
CameraController.ModeTransitionStartCFrame = nil
CameraController.ModeTransitionStartFocus = nil

-- Orbit mode specific
CameraController.OrbitDistance = 12
CameraController.OrbitTargetDistance = 12
CameraController.IsOrbitDragging = false

-- Character rotation control (checked by MovementController)
CameraController.ShouldRotateCharacter = false

-- Ragdoll camera state
CameraController.IsRagdollActive = false
CameraController.RagdollSubject = nil
CameraController.PreRagdollMode = nil

-- Debug state for detecting camera override by other scripts
CameraController._LastAppliedCFrame = nil
CameraController._LastAgentUpdateLogT = 0
CameraController._LastRenderCompareLogT = 0

-- =============================================================================
-- INITIALIZATION
-- =============================================================================
function CameraController:Init(registry, net)
	self._registry = registry
	self._net = net
	
	local camera = getCurrentCamera()
	local cameraConfig = Config.Camera
	
	-- Set initial mode from config
	self.CurrentMode = cameraConfig.DefaultMode or "Orbit"
	self.CurrentModeIndex = 1
	for i, mode in ipairs(cameraConfig.CycleOrder) do
		if mode == self.CurrentMode then
			self.CurrentModeIndex = i
			break
		end
	end
	
	debugPrint("Initializing CameraController, DefaultMode:", self.CurrentMode)
	
	-- Set camera to scriptable
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = cameraConfig.FOV.Base
		debugPrint("Camera set to Scriptable, FOV:", cameraConfig.FOV.Base)
		self._LastSeenCameraType = camera.CameraType
	end
	
	-- Initialize FOVController
	if FOVController.Init then
		FOVController:Init()
	end
	
	-- Initialize ScreenShakeController
	if ScreenShakeController and ScreenShakeController.Init then
		ScreenShakeController:Init()
	end
	
	self:SetupInput()
	self:StartCameraLoop()
	
	-- Apply initial mode settings
	self:ApplyCameraModeSettings()
	
	-- Connect to character events
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		-- Snapshot PlayerScripts contents to identify PlayerModule / other scripts that may overwrite camera settings
		local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
		if playerScripts then
			local childNames = {}
			for _, child in ipairs(playerScripts:GetChildren()) do
				table.insert(childNames, child.Name .. ":" .. child.ClassName)
			end
		else
		end

		localPlayer.CharacterAdded:Connect(function(character)
			self:OnCharacterSpawned(character)
		end)
		
		localPlayer.CharacterRemoving:Connect(function(character)
			self:OnCharacterRemoving(character)
		end)
		
		if localPlayer.Character then
			self:OnCharacterSpawned(localPlayer.Character)
		end
	end
	
	-- Register with ServiceRegistry so other modules can access CameraController
	ServiceRegistry:RegisterController("CameraController", self)
	
	debugPrint("CameraController initialized successfully")

	-- Detect if some other script overrides Camera.CFrame after we set it (often on RenderStepped)
	RunService.RenderStepped:Connect(function()
		local cam = getCurrentCamera()
		if not cam or not self._LastAppliedCFrame then
			return
		end

		-- Detect if some other script flips CameraType away from Scriptable (commonly PlayerModule/CameraModule)
		local currentType = cam.CameraType
		if self._LastSeenCameraType ~= currentType then
			self._LastSeenCameraType = currentType
		end

		local diffPos = (cam.CFrame.Position - self._LastAppliedCFrame.Position).Magnitude
		if diffPos > 0.25 and (tick() - (self._LastRenderCompareLogT or 0)) > 0.75 then
			self._LastRenderCompareLogT = tick()
		end
	end)
end

function CameraController:Start()
	-- No-op for registry pattern
end

-- =============================================================================
-- CHARACTER LIFECYCLE
-- =============================================================================
function CameraController:OnCharacterSpawned(character)
	if character.Name ~= Players.LocalPlayer.Name then
		return
	end
	
	debugPrint("Character spawned:", character.Name)
	self.Character = character
	
	local function waitForCharacterParts()
		self.PrimaryPart = CharacterLocations:GetRoot(character)
		self.Head = CharacterLocations:GetHumanoidHead(character)
		self.Rig = CharacterLocations:GetRig(character)
		
		debugPrint("Looking for rig... Found:", self.Rig ~= nil)
		
		if self.Rig then
			self.RigHead = self.Rig:FindFirstChild("Head")
			debugPrint("Rig head found:", self.RigHead ~= nil)
		end
		
		if self.PrimaryPart and self.Head then
			debugPrint("Character parts ready - PrimaryPart:", self.PrimaryPart.Name, "Head:", self.Head.Name)
			
			-- Reset crouch state
			self.IsCrouching = false
			self.LastCrouchState = false
			self.CurrentCrouchOffset = 0
			self.IsTransitioning = false
			
			self:InitializeCameraAngles()
			self:ApplyCameraModeSettings()
			self:ApplyRigVisibility()
			self:HideColliderParts()  -- Hide the bean/collider parts
			return
		end
		
		task.wait(0.1)
		waitForCharacterParts()
	end
	
	waitForCharacterParts()
end

function CameraController:OnCharacterRemoving(character)
	if self.Character ~= character then
		return
	end
	
	debugPrint("Character removing")

	-- Stop camera loop
	pcall(function()
		RunService:UnbindFromRenderStep("MovieeV2CameraController")
	end)
	
	self.Character = nil
	self.PrimaryPart = nil
	self.Head = nil
	self.Rig = nil
	self.RigHead = nil
	
	self.IsCrouching = false
	self.LastCrouchState = false
	self.CurrentCrouchOffset = 0
	self.IsTransitioning = false
	
	self.MobileCameraX = 0
	self.MobileCameraY = 0
end

-- =============================================================================
-- INPUT SETUP
-- =============================================================================
function CameraController:SetupInput()
	local cameraConfig = Config.Camera
	
	-- Mouse movement and scroll
	self.InputConnection = UserInputService.InputChanged:Connect(function(inputObject, gameProcessed)
		if gameProcessed then
			return
		end
		
		-- Mouse movement for camera rotation
		if inputObject.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = inputObject.Delta
			local sensitivity = cameraConfig.Sensitivity.Mouse
			
			-- For Orbit mode, only rotate when right mouse is held
			if self.CurrentMode == "Orbit" then
				if self.IsOrbitDragging then
					local targetX = self.TargetAngleX - delta.Y * sensitivity
					self.TargetAngleX = clamp(
						targetX,
						cameraConfig.AngleLimits.MinVertical,
						cameraConfig.AngleLimits.MaxVertical
					)
					self.TargetAngleY = self.TargetAngleY - delta.X * sensitivity
				end
			else
				-- Shoulder and FirstPerson modes: always rotate
				local targetX = self.TargetAngleX - delta.Y * sensitivity
				self.TargetAngleX = clamp(
					targetX,
					cameraConfig.AngleLimits.MinVertical,
					cameraConfig.AngleLimits.MaxVertical
				)
				self.TargetAngleY = self.TargetAngleY - delta.X * sensitivity
			end
		end
		
		-- Controller stick
		if inputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
			self.RightStickX = inputObject.Position.X
			self.RightStickY = inputObject.Position.Y
			
			-- Update aim assist gamepad eligibility
			self:_updateAimAssistGamepadInput(inputObject.KeyCode, inputObject.Position)
		end
		
		-- Mouse wheel for zoom (all modes)
		if inputObject.UserInputType == Enum.UserInputType.MouseWheel then
			local zoomDelta = -inputObject.Position.Z * 2
			
			if self.CurrentMode == "Orbit" then
				local orbitConfig = cameraConfig.Orbit
				self.OrbitTargetDistance = clamp(
					self.OrbitTargetDistance + zoomDelta,
					orbitConfig.MinDistance,
					orbitConfig.MaxDistance
				)
				debugPrint("Orbit zoom:", self.OrbitTargetDistance)
			end
		end
	end)
	
	-- Mouse button press/release
	self.InputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		
		-- Right mouse button for orbit dragging
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self.CurrentMode == "Orbit" then
				self.IsOrbitDragging = true
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			end
		end
		
		-- T key to cycle camera modes
		if input.KeyCode == Config.Controls.Input.ToggleCameraMode then
			self:CycleCameraMode()
		end
		
		-- G key to toggle ragdoll (test)
		if input.KeyCode == Config.Controls.Input.ToggleRagdollTest then
			if self._net then
				self._net:FireServer("ToggleRagdollTest")
			end
		end
	end)
	
	self.InputEndedConnection = UserInputService.InputEnded:Connect(function(input)
		-- Right mouse button release
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if self.CurrentMode == "Orbit" then
				self.IsOrbitDragging = false
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
		end
		
		-- Controller stick release
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			self.RightStickX = 0
			self.RightStickY = 0
		end
	end)
	
	self:SetupTouchCamera()
end

function CameraController:SetupTouchCamera()
	if not UserInputService.TouchEnabled then
		return
	end
	
	local starterScripts = Locations.Services.StarterPlayerScripts
	local uiFolder = starterScripts and starterScripts:FindFirstChild("UI")
	if not uiFolder then
		return
	end
	
	local success, mobileControlsModule = pcall(function()
		return require(uiFolder:WaitForChild("MobileControls"))
	end)
	
	if not success then
		return
	end
	
	mobileControlsModule:ConnectToInput("Camera", function(cameraVector)
		self.MobileCameraX = cameraVector.X
		self.MobileCameraY = cameraVector.Y
	end)
	
	local cameraTouches = {}
	local cameraConfig = Config.Camera
	
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		
		if mobileControlsModule:IsTouchClaimed(input) then
			cameraTouches[input] = nil
			return
		end
		
		local delta = input.Delta
		if delta.Magnitude > 0 then
			local lastPosition = cameraTouches[input]
			if lastPosition then
				local sensitivity = cameraConfig.Sensitivity.Touch
				local targetX = self.TargetAngleX - delta.Y * sensitivity
				self.TargetAngleX = clamp(
					targetX,
					cameraConfig.AngleLimits.MinVertical,
					cameraConfig.AngleLimits.MaxVertical
				)
				self.TargetAngleY = self.TargetAngleY - delta.X * sensitivity
				
				-- Update aim assist touch eligibility
				self:_updateAimAssistTouchInput()
			else
				cameraTouches[input] = Vector2.new(input.Position.X, input.Position.Y)
				mobileControlsModule.CameraTouches[input] = true
			end
		end
	end)
	
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			cameraTouches[input] = nil
			mobileControlsModule.CameraTouches[input] = nil
		end
	end)
end

-- =============================================================================
-- CAMERA MODE MANAGEMENT
-- =============================================================================
function CameraController:CycleCameraMode()
	local cameraConfig = Config.Camera
	local cycleOrder = cameraConfig.CycleOrder
	
	self.CurrentModeIndex = self.CurrentModeIndex + 1
	if self.CurrentModeIndex > #cycleOrder then
		self.CurrentModeIndex = 1
	end
	
	self.CurrentMode = cycleOrder[self.CurrentModeIndex]
	self:ApplyCameraModeSettings()
	self:ApplyRigVisibility()
	self:HideColliderParts()
	self:_startModeTransition()
	
	debugPrint("=== CAMERA MODE CHANGED ===")
	debugPrint("New mode:", self.CurrentMode, "Index:", self.CurrentModeIndex)
	debugPrint("ShouldRotateCharacter:", self.ShouldRotateCharacter)
end

-- Alias for compatibility
function CameraController:ToggleCameraMode()
	self:CycleCameraMode()
end

function CameraController:ApplyCameraModeSettings()
	local cameraConfig = Config.Camera
	
	debugPrint("Applying settings for mode:", self.CurrentMode)
	
	if self.CurrentMode == "Orbit" then
		-- Orbit mode: Free cursor, right-click drag to rotate
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		self.ShouldRotateCharacter = false  -- Character rotates to movement, NOT camera
		self.OrbitDistance = cameraConfig.Orbit.Distance
		self.OrbitTargetDistance = cameraConfig.Orbit.Distance
		self.IsOrbitDragging = false
		debugPrint("Orbit mode - MouseBehavior: Default, ShouldRotateCharacter: false")
		
	elseif self.CurrentMode == "Shoulder" then
		-- Shoulder mode: Locked cursor, character faces camera
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		self.ShouldRotateCharacter = true
		debugPrint("Shoulder mode - MouseBehavior: LockCenter, ShouldRotateCharacter: true")
		
	elseif self.CurrentMode == "FirstPerson" then
		-- First person mode: Locked cursor, character faces camera
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		self.ShouldRotateCharacter = true
		debugPrint("FirstPerson mode - MouseBehavior: LockCenter, ShouldRotateCharacter: true")
	end
end

function CameraController:_startModeTransition()
	local camera = getCurrentCamera()
	if not camera then
		return
	end

	local duration = (Config.Camera.Smoothing and Config.Camera.Smoothing.ModeTransitionTime) or 0.15
	self.IsModeTransitioning = duration > 0
	self.ModeTransitionStartT = tick()
	self.ModeTransitionDuration = duration
	self.ModeTransitionStartCFrame = camera.CFrame
	self.ModeTransitionStartFocus = camera.Focus
end

function CameraController:GetCurrentMode()
	return self.CurrentMode
end

function CameraController:SetMode(modeName)
	local cameraConfig = Config.Camera
	for i, mode in ipairs(cameraConfig.CycleOrder) do
		if mode == modeName then
			self.CurrentMode = modeName
			self.CurrentModeIndex = i
			self:ApplyCameraModeSettings()
			self:ApplyRigVisibility()
			self:_startModeTransition()
			return true
		end
	end
	return false
end

-- Public method for MovementController to check
function CameraController:ShouldRotateCharacterToCamera()
	return self.ShouldRotateCharacter
end

-- Alias for SetMode for consistency with CharacterController
function CameraController:SetCameraMode(modeName)
	return self:SetMode(modeName)
end

-- =============================================================================
-- RAGDOLL CAMERA
-- =============================================================================

function CameraController:SetRagdollFocus(ragdollHead)
	if not ragdollHead then
		return
	end

	debugPrint("=== RAGDOLL FOCUS STARTED ===")
	debugPrint("Ragdoll head:", ragdollHead:GetFullName())

	-- Save current mode
	self.PreRagdollMode = self.CurrentMode
	self.IsRagdollActive = true
	self.RagdollSubject = ragdollHead

	-- Force to Orbit mode
	self:SetMode("Orbit")

	-- Reset orbit distance to something reasonable for watching ragdoll
	local cameraConfig = Config.Camera
	self.OrbitDistance = cameraConfig.Orbit.DefaultDistance or 12
	self.OrbitTargetDistance = self.OrbitDistance

	debugPrint("Ragdoll focus set, mode:", self.CurrentMode)
end

function CameraController:ClearRagdollFocus()
	debugPrint("=== RAGDOLL FOCUS CLEARED ===")

	self.IsRagdollActive = false
	self.RagdollSubject = nil

	-- Mode restoration is handled by CharacterController calling SetCameraMode
	self.PreRagdollMode = nil

	debugPrint("Ragdoll focus cleared")
end

function CameraController:GetRagdollSubject()
	return self.RagdollSubject
end

-- =============================================================================
-- RIG VISIBILITY
-- =============================================================================
function CameraController:ApplyRigVisibility()
	debugPrint("=== APPLYING RIG VISIBILITY ===")
	debugPrint("CurrentMode:", self.CurrentMode)
	debugPrint("Rig exists:", self.Rig ~= nil)
	
	if not self.Rig then
		debugPrint("No rig found - skipping visibility")
		return
	end
	
	local isFirstPerson = (self.CurrentMode == "FirstPerson")
	
	if isFirstPerson then
		-- First person: Use v1 transparency logic (called every frame in UpdateFirstPersonCamera)
		-- Just call it once here for mode switch
		debugPrint("First person mode - applying v1 transparency")
		self:ApplyFirstPersonTransparency()
	else
		-- Third person modes: Show entire rig
		debugPrint("Third person mode - showing entire rig")
		self:ShowEntireRig()
	end
end

function CameraController:ShowEntireRig()
	if not self.Rig then
		return
	end
	
	-- Show all rig parts
	for _, part in ipairs(self.Rig:GetDescendants()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 0
		end
	end
	
	-- Show accessories
	local rigHumanoid = self.Rig:FindFirstChildOfClass("Humanoid")
	if rigHumanoid then
		for _, accessory in pairs(rigHumanoid:GetAccessories()) do
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.LocalTransparencyModifier = 0
			end
		end
	end
	
	debugPrint("Rig visibility set to VISIBLE (transparency = 0)")
end

-- =============================================================================
-- HIDE COLLIDER PARTS (Bean/Physics shapes)
-- =============================================================================
function CameraController:HideColliderParts()
	if not self.Character then
		return
	end
	
	local collider = self.Character:FindFirstChild("Collider")
	if not collider then
		debugPrint("No Collider found on character")
		return
	end
	
	-- Hide ALL parts in Collider (Default, Crouch, UncrouchCheck folders)
	local hiddenCount = 0
	for _, descendant in ipairs(collider:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 1
			hiddenCount += 1
			debugPrint("Hiding collider part:", descendant.Name)
		end
	end

	debugPrint("Collider parts hidden")
end

-- =============================================================================
-- CAMERA ANGLE INITIALIZATION
-- =============================================================================
function CameraController:InitializeCameraAngles()
	local camera = getCurrentCamera()
	if not camera then
		return
	end
	
	local cameraConfig = Config.Camera
	local lookVector = camera.CFrame.LookVector
	
	self.TargetAngleY = math.deg(math.atan2(-lookVector.X, -lookVector.Z))
	self.TargetAngleX = math.deg(math.asin(lookVector.Y))
	
	self.TargetAngleX = clamp(
		self.TargetAngleX,
		cameraConfig.AngleLimits.MinVertical,
		cameraConfig.AngleLimits.MaxVertical
	)
	
	self.AngleX = self.TargetAngleX
	self.AngleY = self.TargetAngleY
	
	self.LastFrameTime = tick()
	
	debugPrint("Camera angles initialized - AngleX:", self.AngleX, "AngleY:", self.AngleY)
end

-- =============================================================================
-- MAIN CAMERA LOOP
-- =============================================================================
function CameraController:StartCameraLoop()
	-- Ensure we run AFTER any default camera scripts (RenderPriority.Camera) so nothing can overwrite us.
	pcall(function()
		RunService:UnbindFromRenderStep("MovieeV2CameraController")
	end)

	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	RunService:BindToRenderStep("MovieeV2CameraController", Enum.RenderPriority.Camera.Value + 10, function()
		self:UpdateCamera()
	end)
end

function CameraController:UpdateCamera()
	-- Gameplay gating: UI flow disables gameplay until StartMatch.
	if self._registry then
		local inputController = self._registry:TryGet("Input")
		if inputController and inputController.Manager and inputController.Manager.GameplayEnabled == false then
			return
		end
	end

	if not self.Character or not self.Character.Parent then
		return
	end
	
	local camera = getCurrentCamera()
	if not camera then
		return
	end

	-- Hard-enforce scriptable every frame; some other script is flipping us to Custom (runtime logs confirm this).
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		local prevType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable
	end
	
	-- Auto-initialize camera if character parts become available
	if not self.PrimaryPart or not self.Head then
		self.PrimaryPart = CharacterLocations:GetRoot(self.Character)
		self.Head = CharacterLocations:GetHumanoidHead(self.Character)
		self.Rig = CharacterLocations:GetRig(self.Character)
		if self.Rig then
			self.RigHead = self.Rig:FindFirstChild("Head")
		end
		if self.PrimaryPart and self.Head then
			self.IsCrouching = false
			self.LastCrouchState = false
			self.CurrentCrouchOffset = 0
			self.IsTransitioning = false
			self:InitializeCameraAngles()
			self:ApplyRigVisibility()
		else
			return
		end
	end
	
	local cameraConfig = Config.Camera
	
	-- Update crouch state
	self.IsCrouching = self:GetCrouchState()
	
	-- Calculate delta time
	local currentTime = tick()
	local deltaTime = currentTime - self.LastFrameTime
	self.LastFrameTime = currentTime
	
	-- Process controller input (works in all modes)
	if math.abs(self.RightStickX) > 0.1 or math.abs(self.RightStickY) > 0.1 then
		local horizontalInput = -self.RightStickX * cameraConfig.Sensitivity.ControllerX * deltaTime * 60
		local verticalInput = self.RightStickY * cameraConfig.Sensitivity.ControllerY * deltaTime * 60
		
		self.TargetAngleY = self.TargetAngleY + horizontalInput
		local newAngleX = self.TargetAngleX + verticalInput
		self.TargetAngleX = clamp(
			newAngleX,
			cameraConfig.AngleLimits.MinVertical,
			cameraConfig.AngleLimits.MaxVertical
		)
	end
	
	-- Process mobile input
	if math.abs(self.MobileCameraX) > 0.05 or math.abs(self.MobileCameraY) > 0.05 then
		local horizontalInput = self.MobileCameraX * cameraConfig.Sensitivity.MobileHorizontal * deltaTime * 60
		local verticalInput = self.MobileCameraY * cameraConfig.Sensitivity.MobileVertical * deltaTime * 60
		
		self.TargetAngleY = self.TargetAngleY + horizontalInput
		local newAngleX = self.TargetAngleX + verticalInput
		self.TargetAngleX = clamp(
			newAngleX,
			cameraConfig.AngleLimits.MinVertical,
			cameraConfig.AngleLimits.MaxVertical
		)
	end
	
	-- Smooth camera angles
	local angleSmoothness = cameraConfig.Smoothing.AngleSmoothness
	local smoothFactor = math.exp(-angleSmoothness * deltaTime)
	
	self.AngleX = lerp(self.TargetAngleX, self.AngleX, smoothFactor)
	self.AngleY = lerp(self.TargetAngleY, self.AngleY, smoothFactor)
	
	-- Update crouch offset
	self:UpdateCrouchOffset(deltaTime)
	
	-- Update camera based on current mode
	local desiredCFrame = nil
	local desiredFocus = nil
	if self.CurrentMode == "Orbit" then
		desiredCFrame, desiredFocus = self:UpdateOrbitCamera(camera, deltaTime)
		-- Orbit mode: ensure rig is visible
		self:ShowEntireRig()
	elseif self.CurrentMode == "Shoulder" then
		desiredCFrame, desiredFocus = self:UpdateShoulderCamera(camera, deltaTime)
		-- Shoulder mode: ensure rig is visible
		self:ShowEntireRig()
	elseif self.CurrentMode == "FirstPerson" then
		-- FirstPerson handles its own transparency via ApplyFirstPersonTransparency
		desiredCFrame, desiredFocus = self:UpdateFirstPersonCamera(camera, deltaTime)
	end

	if desiredCFrame and desiredFocus then
		if self.IsModeTransitioning and self.ModeTransitionStartCFrame and self.ModeTransitionStartFocus then
			local elapsed = tick() - self.ModeTransitionStartT
			local alpha = math.clamp(elapsed / math.max(self.ModeTransitionDuration, 1e-3), 0, 1)

			local blendedCFrame = self.ModeTransitionStartCFrame:Lerp(desiredCFrame, alpha)
			local startFocusPos = self.ModeTransitionStartFocus.Position
			local targetFocusPos = desiredFocus.Position
			local blendedFocus = CFrame.new(startFocusPos:Lerp(targetFocusPos, alpha))

			camera.CFrame = blendedCFrame
			camera.Focus = blendedFocus

			if alpha >= 1 then
				self.IsModeTransitioning = false
			end
		else
			camera.CFrame = desiredCFrame
			camera.Focus = desiredFocus
		end
	end

	-- Save last applied CFrame for override detection (checked on RenderStepped)
	self._LastAppliedCFrame = camera.CFrame

	if (tick() - (self._LastAgentUpdateLogT or 0)) > 0.75 then
		self._LastAgentUpdateLogT = tick()
	end
	
	-- Update FOV based on velocity
	self:UpdateFOV()
end

-- =============================================================================
-- MODE A: ORBIT CAMERA
-- =============================================================================
function CameraController:UpdateOrbitCamera(camera, deltaTime)
	local cameraConfig = Config.Camera
	local orbitConfig = cameraConfig.Orbit
	
	-- Smooth zoom
	self.OrbitDistance = lerp(self.OrbitDistance, self.OrbitTargetDistance, deltaTime * 10)
	
	-- Get pivot point - use ragdoll subject if active, otherwise character position
	local basePivot
	if self.IsRagdollActive and self.RagdollSubject and self.RagdollSubject.Parent then
		basePivot = self.RagdollSubject.Position
	elseif self.PrimaryPart then
		basePivot = self.PrimaryPart.Position
	else
		return -- No valid pivot
	end
	
	local pivotPosition = basePivot + Vector3.new(0, orbitConfig.Height + self.CurrentCrouchOffset, 0)
	
	-- Calculate camera position based on angles
	local wrappedAngleY = self.AngleY % 360
	local yawCF = CFrame.Angles(0, math.rad(wrappedAngleY), 0)
	local pitchCF = CFrame.Angles(math.rad(self.AngleX), 0, 0)
	
	-- Camera orbits around pivot
	local orbitCF = CFrame.new(pivotPosition) * yawCF * pitchCF
	local desiredPosition = orbitCF * CFrame.new(0, 0, self.OrbitDistance)
	
	-- Collision detection
	local rayOrigin = pivotPosition
	local rayDirection = desiredPosition.Position - rayOrigin
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { self.Character }
	if self.Rig then
		table.insert(raycastParams.FilterDescendantsInstances, self.Rig)
	end
	-- IMPORTANT: Never let camera collision hit any rigs or ragdolls
	local rigsFolder = workspace:FindFirstChild("Rigs")
	if rigsFolder then
		table.insert(raycastParams.FilterDescendantsInstances, rigsFolder)
	end
	local ragdollsFolder = workspace:FindFirstChild("Ragdolls")
	if ragdollsFolder then
		table.insert(raycastParams.FilterDescendantsInstances, ragdollsFolder)
	end
	local entitiesFolder = workspace:FindFirstChild("Entities")
	if entitiesFolder then
		table.insert(raycastParams.FilterDescendantsInstances, entitiesFolder)
	end
	
	local spherecastResult = workspace:Spherecast(rayOrigin, orbitConfig.CollisionRadius, rayDirection, raycastParams)
	
	local finalPosition
	if spherecastResult then
		local hitDistance = (spherecastResult.Position - rayOrigin).Magnitude
		local safeDistance = math.max(hitDistance - orbitConfig.CollisionBuffer, orbitConfig.MinDistance)
		finalPosition = rayOrigin + (rayDirection.Unit * safeDistance)
	else
		finalPosition = desiredPosition.Position
	end

	-- Keep camera above ground (prevents crouch/slide dip under terrain)
	finalPosition = self:_clampPositionAboveGround(finalPosition)
	
	-- Look at pivot point
	local desiredCFrame = CFrame.lookAt(finalPosition, pivotPosition)
	local desiredFocus = CFrame.new(pivotPosition)
	return desiredCFrame, desiredFocus
end

-- =============================================================================
-- MODE B: SHOULDER CAMERA (Exact v1 port)
-- =============================================================================
function CameraController:UpdateShoulderCamera(camera, deltaTime)
	local cameraConfig = Config.Camera
	local shoulderConfig = cameraConfig.Shoulder
	
	-- V1 USES HEAD POSITION, NOT PRIMARY PART
	if not self.Head then
		debugPrint("Shoulder: No head found!")
		return
	end
	
	-- POSITION AT HEAD (same as v1)
	local baseHeadPosition = self.Head.Position
	local headCFrame = CFrame.new(baseHeadPosition + Vector3.new(0, self.CurrentCrouchOffset, 0))
	
	local wrappedAngleY = self.AngleY % 360
	
	-- V1 config values
	local distance = shoulderConfig.Distance
	local height = shoulderConfig.Height
	local shoulderX = shoulderConfig.ShoulderOffsetX
	local shoulderY = shoulderConfig.ShoulderOffsetY
	
	-- Base pivot near head (plus crouch offset) and height
	local pivotCF = headCFrame + Vector3.new(0, height, 0)
	
	-- Build aim rotation from yaw + pitch (v1: yaw then pitch)
	local yawCF = CFrame.Angles(0, math.rad(wrappedAngleY), 0)
	local pitchCF = CFrame.Angles(math.rad(self.AngleX), 0, 0)
	local aimCF = pivotCF * yawCF * pitchCF
	
	-- Camera offset in aim space:
	-- +X = right shoulder, +Y = up, +Z = backwards
	local desiredCameraCF = aimCF * CFrame.new(shoulderX, shoulderY, distance)
	local desiredCameraPosition = desiredCameraCF.Position
	
	-- Spherecast collision from pivot to desired camera position
	local rayOrigin = pivotCF.Position
	local rayDirection = desiredCameraPosition - rayOrigin
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { self.Character }
	if self.Rig then
		table.insert(raycastParams.FilterDescendantsInstances, self.Rig)
	end
	-- IMPORTANT: Never let camera collision hit any rigs or ragdolls
	local rigsFolder = workspace:FindFirstChild("Rigs")
	if rigsFolder then
		table.insert(raycastParams.FilterDescendantsInstances, rigsFolder)
	end
	local ragdollsFolder = workspace:FindFirstChild("Ragdolls")
	if ragdollsFolder then
		table.insert(raycastParams.FilterDescendantsInstances, ragdollsFolder)
	end
	local entitiesFolder = workspace:FindFirstChild("Entities")
	if entitiesFolder then
		table.insert(raycastParams.FilterDescendantsInstances, entitiesFolder)
	end
	
	local cameraRadius = shoulderConfig.CollisionRadius or 0.5
	local spherecastResult = workspace:Spherecast(rayOrigin, cameraRadius, rayDirection, raycastParams)
	
	local finalCameraPosition
	if spherecastResult then
		local hitDistance = (spherecastResult.Position - rayOrigin).Magnitude
		local safeDistance = math.max(hitDistance - 1, 0.5)
		finalCameraPosition = rayOrigin + (rayDirection.Unit * safeDistance)
	else
		finalCameraPosition = desiredCameraPosition
	end

	-- Keep camera above ground (prevents crouch/slide dip under terrain)
	finalCameraPosition = self:_clampPositionAboveGround(finalCameraPosition)
	
	-- Look forward along aim direction (NOT at the head)
	local lookDir = aimCF.LookVector
	local desiredCFrame = CFrame.lookAt(finalCameraPosition, finalCameraPosition + lookDir)
	
	-- Distance-based transparency
	local isRagdolled = self.Character and self.Character:GetAttribute("RagdollActive")
	if not isRagdolled and self.PrimaryPart then
		local characterBodyPosition = self.PrimaryPart.Position
		local cameraDistance = (finalCameraPosition - characterBodyPosition).Magnitude
		self:UpdateDistanceBasedTransparency(cameraDistance)
	end
	
	-- CRITICAL: Update Camera.Focus
	local desiredFocus = CFrame.new(baseHeadPosition)
	return desiredCFrame, desiredFocus
end

-- =============================================================================
-- MODE C: FIRST PERSON CAMERA (Ported from v1)
-- =============================================================================
function CameraController:UpdateFirstPersonCamera(camera, deltaTime)
	local cameraConfig = Config.Camera
	local fpConfig = cameraConfig.FirstPerson
	
	-- Use humanoid head as the base (v1 behavior)
	if not self.Head then
		debugPrint("FirstPerson: No head found!")
		return
	end

	local rigHeadName = self.RigHead and self.RigHead.Name or "nil"
	local humanoidHeadName = self.Head and self.Head.Name or "nil"
	
	-- POSITION AT HEAD (with crouch offset)
	-- v2 option: follow the visual Rig's Head (requested), otherwise fall back to v1 humanoid-head base.
	local followRigHead = fpConfig.FollowHead == true and self.RigHead ~= nil
	local baseHeadPosition = (followRigHead and self.RigHead.Position or self.Head.Position)
	local headCFrame = CFrame.new(baseHeadPosition + Vector3.new(0, self.CurrentCrouchOffset, 0))
	
	-- Apply horizontal rotation (character facing direction) to position the offset correctly
	-- Wrap AngleY to 0-360 range for rendering
	local wrappedAngleY = self.AngleY % 360
	
	-- FIRST PERSON: v1 behavior, but optionally pivoting from Rig.Head (for "in front of rig head part")
	local characterRotation = headCFrame * CFrame.Angles(0, math.rad(wrappedAngleY), 0)
	local cameraOffset = followRigHead and (fpConfig.HeadOffset or fpConfig.Offset) or fpConfig.Offset
	local rotOffset = fpConfig.HeadRotationOffset or Vector3.zero
	
	-- Debug: Print offset being used (remove after testing)
	if not self._fpOffsetPrinted then
		print("[CameraController] FirstPerson offset:", cameraOffset, "FollowHead:", followRigHead)
		self._fpOffsetPrinted = true
	end
	
	-- Apply offset in character's local space (so it moves with character facing)
	local offsetPosition = characterRotation * CFrame.new(cameraOffset)
	if followRigHead and rotOffset.Magnitude > 0.0001 then
		offsetPosition = offsetPosition
			* CFrame.Angles(math.rad(rotOffset.X), math.rad(rotOffset.Y), math.rad(rotOffset.Z))
	end
	
	-- Apply screen shake offset if active
	if ScreenShakeController then
		local shakeOffset = ScreenShakeController:GetOffset()
		local shakeRotation = ScreenShakeController:GetRotation()
		if shakeOffset.Magnitude > 0.001 then
			offsetPosition = offsetPosition * CFrame.new(shakeOffset)
			offsetPosition = offsetPosition * CFrame.Angles(
				math.rad(shakeRotation.X),
				math.rad(shakeRotation.Y),
				math.rad(shakeRotation.Z)
			)
		end
	end
	
	-- Camera looks around from this offset position (apply vertical rotation)
	local desiredCF = offsetPosition * CFrame.Angles(math.rad(self.AngleX), 0, 0)

	-- Keep camera above ground (prevents slide/crouch putting camera under terrain)
	-- Skip clamping if DisableGroundClamp is set (fixes camera being forced above low ceilings)
	local desiredPos = desiredCF.Position
	local clampedPos = desiredPos
	if not fpConfig.DisableGroundClamp then
		clampedPos = self:_clampPositionAboveGround(desiredPos)
	end
	local desiredCFrame = CFrame.new(clampedPos) * desiredCF.Rotation
	
	-- CRITICAL: Update Camera.Focus to tell Roblox where to prioritize rendering
	-- This controls shadow distance, LOD, dynamic lighting, and other rendering optimizations
	-- Without this, rendering is centered at world origin (0,0,0) instead of the player
	local desiredFocus = CFrame.new(baseHeadPosition)
	
	-- Apply first person transparency (hide rig)
	-- Skip transparency updates if character is ragdolled
	local isRagdolled = self.Character and self.Character:GetAttribute("RagdollActive")
	if self.Rig and not isRagdolled then
		self:ApplyFirstPersonTransparency()
	end

	return desiredCFrame, desiredFocus
end

-- =============================================================================
-- FIRST PERSON TRANSPARENCY (Ported from v1)
-- =============================================================================
-- Whitelist: ONLY show these parts in first person (requested)
local FIRST_PERSON_VISIBLE = { Torso = true, ["Left Leg"] = true, ["Right Leg"] = true }

-- Helper: Apply first person transparency (hide rig, show test limbs if enabled)
function CameraController:ApplyFirstPersonTransparency()
	if not self.Rig then
		return
	end

	local charCfg = Config.Gameplay.Character
	local showRigForTesting = charCfg.ShowRigForTesting

	-- If the game wants the rig visible (testing), do not hide anything.
	if showRigForTesting then
		self:ShowEntireRig()
	else
		CharacterLocations:ForEachRigPart(self.Character, function(rigPart)
			rigPart.LocalTransparencyModifier = 1
		end)

		local head = CharacterLocations:GetHumanoidHead(self.Character)
		if head then
			head.LocalTransparencyModifier = 1
		end

		local colliderHead = CharacterLocations:GetHead(self.Character)
		if colliderHead then
			colliderHead.LocalTransparencyModifier = 1
		end
	end

	-- Always hide accessories in first person
	local rigHumanoid = self.Rig:FindFirstChildOfClass("Humanoid")
	if rigHumanoid then
		for _, accessory in pairs(rigHumanoid:GetAccessories()) do
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.LocalTransparencyModifier = showRigForTesting and 0 or 1
			end
		end
	end
end

-- Helper: Apply transparency to rig parts and accessories (for third person distance-based transparency)
function CameraController:ApplyRigTransparency(transparency)
	if not self.Rig then
		return
	end

	CharacterLocations:ForEachRigPart(self.Character, function(rigPart)
		rigPart.LocalTransparencyModifier = transparency
	end)

	local rigHumanoid = self.Rig:FindFirstChildOfClass("Humanoid")
	if rigHumanoid then
		for _, accessory in pairs(rigHumanoid:GetAccessories()) do
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.LocalTransparencyModifier = transparency
			end
		end
	end
end

function CameraController:UpdateDistanceBasedTransparency(cameraDistance)
	if not self.Rig then
		return
	end

	-- Calculate transparency: <2 studs = transparent, 2-4 = fade, >4 = opaque
	local transparency
	if cameraDistance <= 2 then
		transparency = 1
	elseif cameraDistance >= 4 then
		transparency = 0
	else
		transparency = 1 - ((cameraDistance - 2) / 2)
	end

	self:ApplyRigTransparency(transparency)
end

-- =============================================================================
-- CROUCH HANDLING
-- =============================================================================
function CameraController:GetCrouchState()
	if MovementStateManager and MovementStateManager:IsSliding() then
		return true
	end

	if not self.Character then
		return false
	end
	
	local normalHead = CharacterLocations:GetHead(self.Character)
	local crouchHead = CharacterLocations:GetCrouchHead(self.Character)
	
	if not normalHead or not crouchHead then
		return false
	end
	
	local normalHeadVisible = normalHead.Transparency < 1
	local crouchHeadVisible = crouchHead.Transparency < 1
	
	if crouchHeadVisible and not normalHeadVisible then
		return true
	end
	
	return false
end

function CameraController:UpdateCrouchOffset(deltaTime)
	local cameraConfig = Config.Camera
	local crouchReduction = Config.Gameplay.Character.CrouchHeightReduction
	
	if self.IsCrouching ~= self.LastCrouchState then
		if cameraConfig.Smoothing.EnableCrouchTransition then
			self.IsTransitioning = true
		else
			self.IsTransitioning = false
			self.CurrentCrouchOffset = self.IsCrouching and -crouchReduction or 0
		end
		self.LastCrouchState = self.IsCrouching
	end
	
	if cameraConfig.Smoothing.EnableCrouchTransition then
		local targetOffset = self.IsCrouching and -crouchReduction or 0
		self.CurrentCrouchOffset = lerp(
			self.CurrentCrouchOffset,
			targetOffset,
			clamp(cameraConfig.Smoothing.CrouchTransitionSpeed * deltaTime, 0, 1)
		)
		
		local offsetDifference = math.abs(self.CurrentCrouchOffset - targetOffset)
		if offsetDifference < 0.05 then
			self.IsTransitioning = false
		end
	else
		self.CurrentCrouchOffset = self.IsCrouching and -crouchReduction or 0
	end
end

-- =============================================================================
-- FOV SYSTEM
-- =============================================================================
function CameraController:UpdateFOV()
	if not self.PrimaryPart then
		return
	end
	
	local velocity = self.PrimaryPart.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local verticalSpeed = math.abs(velocity.Y) * 0.5  -- 50% vertical contribution
	local effectiveSpeed = math.sqrt(horizontalSpeed * horizontalSpeed + verticalSpeed * verticalSpeed)
	
	FOVController:UpdateMomentum(effectiveSpeed)
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================
function CameraController:GetCameraAngles()
	return Vector2.new(self.AngleY, self.AngleX)
end

function CameraController:SetFOV(fov)
	local camera = getCurrentCamera()
	if camera then
		camera.FieldOfView = fov
	end
end

-- =============================================================================
-- AIM ASSIST INPUT HELPERS
-- =============================================================================

function CameraController:_updateAimAssistGamepadInput(keyCode: Enum.KeyCode, position: Vector3)
	local weaponController = self._registry and self._registry:TryGet("Weapon")
	if weaponController and weaponController.UpdateAimAssistGamepadEligibility then
		weaponController:UpdateAimAssistGamepadEligibility(keyCode, position)
	end
end

function CameraController:_updateAimAssistTouchInput()
	local weaponController = self._registry and self._registry:TryGet("Weapon")
	if weaponController and weaponController.UpdateAimAssistTouchEligibility then
		weaponController:UpdateAimAssistTouchEligibility()
	end
end

function CameraController:Cleanup()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	
	if self.InputConnection then
		self.InputConnection:Disconnect()
		self.InputConnection = nil
	end
	
	if self.InputBeganConnection then
		self.InputBeganConnection:Disconnect()
		self.InputBeganConnection = nil
	end
	
	if self.InputEndedConnection then
		self.InputEndedConnection:Disconnect()
		self.InputEndedConnection = nil
	end
	
	self.Character = nil
	self.PrimaryPart = nil
	self.Head = nil
	self.Rig = nil
	self.RigHead = nil
	
	self.IsCrouching = false
	self.LastCrouchState = false
	self.CurrentCrouchOffset = 0
	self.IsTransitioning = false
	
	self.MobileCameraX = 0
	self.MobileCameraY = 0
end

return CameraController
