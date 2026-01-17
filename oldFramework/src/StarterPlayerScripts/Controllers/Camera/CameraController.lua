local CameraController = {}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local MathUtils = require(Locations.Modules.Utils.MathUtils)
local Config = require(Locations.Modules.Config)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local MouseLockManager = require(Locations.Modules.Systems.Core.MouseLockManager)
local FOVController = require(Locations.Modules.Systems.Core.FOVController)

local ScreenShakeController = nil

-- Constants
local Camera = workspace.CurrentCamera

-- Character references
CameraController.Character = nil
CameraController.PrimaryPart = nil
CameraController.Head = nil
CameraController.Rig = nil

-- Connections
CameraController.Connection = nil
CameraController.InputConnection = nil

-- Camera angles
CameraController.AngleX = 0
CameraController.AngleY = 0
CameraController.TargetAngleX = 0
CameraController.TargetAngleY = 0

-- Controller input
CameraController.RightStickX = 0
CameraController.RightStickY = 0

-- Mobile camera input
CameraController.MobileCameraX = 0
CameraController.MobileCameraY = 0

-- Timing
CameraController.LastFrameTime = 0

-- Crouch transition system
CameraController.IsCrouching = false
CameraController.LastCrouchState = false
CameraController.CurrentCrouchOffset = 0
CameraController.IsTransitioning = false

-- Camera mode system
CameraController.IsThirdPerson = false

function CameraController:Init()
	-- TAKE CAMERA CONTROL
	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.FieldOfView = Config.Controls.Camera.FieldOfView

	-- Initialize MouseLockManager and lock the mouse
	MouseLockManager:Init()
	MouseLockManager:ForceLock()

	-- Initialize FOV Controller
	FOVController:Init()

	-- Initialize Screen Shake Controller (lazy load to avoid circular deps)
	local screenShakeModule = Locations.Client.Controllers.ScreenShakeController
	if screenShakeModule then
		ScreenShakeController = require(screenShakeModule)
		ScreenShakeController:Init()
	end

	self:SetupInput()
	self:StartCameraLoop()
end

function CameraController:OnCharacterSpawned(character)
	if character.Name ~= Players.LocalPlayer.Name then
		return
	end

	self.Character = character

	-- Wait for character parts to load
	local function waitForCharacterParts()
		self.PrimaryPart = CharacterLocations:GetRoot(character)
		self.Head = CharacterLocations:GetHumanoidHead(character)
		self.Rig = CharacterLocations:GetRig(character)

		if self.PrimaryPart and self.Head then
			-- Character parts found, continue with camera setup

			-- Initialize camera state
			self.IsCrouching = false
			self.LastCrouchState = false
			self.CurrentCrouchOffset = 0
			self.IsTransitioning = false

			-- Reconnect input if it was disconnected during respawn
			if not self.InputConnection then
				LogService:Info("CAMERA", "Reconnecting camera input for respawned character")
				self:SetupInput()
			end

			self:InitializeFirstPerson()
			return
		end

		-- Wait 0.1 seconds and try again
		task.wait(0.1)
		waitForCharacterParts()
	end

	waitForCharacterParts()
end

function CameraController:OnCharacterRemoving(character)
	if self.Character == character then
		-- Cleanup connections if needed
		if self.InputConnection then
			self.InputConnection:Disconnect()
			self.InputConnection = nil
		end

		-- Clear character references
		self.Character = nil
		self.PrimaryPart = nil
		self.Head = nil
		self.Rig = nil

		-- Reset camera state
		self.IsCrouching = false
		self.LastCrouchState = false
		self.CurrentCrouchOffset = 0
		self.IsTransitioning = false

		-- Reset mobile camera input
		self.MobileCameraX = 0
		self.MobileCameraY = 0
	end
end

function CameraController:SetupInput()
	self.InputConnection = UserInputService.InputChanged:Connect(function(inputObject, gameProcessed)
		if gameProcessed then
			return
		end

		if inputObject.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = inputObject.Delta

			local X = self.TargetAngleX - delta.y * Config.Controls.Camera.MouseSensitivity
			self.TargetAngleX =
				math.max(Config.Controls.Camera.MinVerticalAngle, math.min(Config.Controls.Camera.MaxVerticalAngle, X))
			self.TargetAngleY = self.TargetAngleY - delta.x * Config.Controls.Camera.MouseSensitivity
		end

		if inputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
			self.RightStickX = inputObject.Position.X
			self.RightStickY = inputObject.Position.Y
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			self.RightStickX = 0
			self.RightStickY = 0
		end
	end)

	-- Add mobile touch camera support
	self:SetupTouchCamera()
end

function CameraController:SetupTouchCamera()
	if not UserInputService.TouchEnabled then
		return
	end

	-- Get MobileControls reference
	local success, mobileControlsModule = pcall(function()
		return require(Locations.Client.UI.MobileControls)
	end)

	if not success then
		return
	end

	-- Connect to camera joystick input
	mobileControlsModule:ConnectToInput("Camera", function(cameraVector)
		-- Store the current camera input values (similar to controller stick)
		self.MobileCameraX = cameraVector.X
		self.MobileCameraY = cameraVector.Y
	end)

	-- Add touch-anywhere camera control (fallback when joystick isn't being used)
	local cameraTouches = {}

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		-- Check if this touch is claimed by UI elements (joysticks/buttons)
		if mobileControlsModule:IsTouchClaimed(input) then
			-- Remove from camera tracking if it was there
			cameraTouches[input] = nil
			return
		end

		local delta = input.Delta
		if delta.Magnitude > 0 then
			-- Only use for camera if not currently tracked by camera system
			local lastPosition = cameraTouches[input]
			if lastPosition then
				-- Apply camera movement with mobile sensitivity
				local sensitivity = Config.Controls.Camera.TouchSensitivity
				local X = self.TargetAngleX - delta.Y * sensitivity
				self.TargetAngleX = math.max(
					Config.Controls.Camera.MinVerticalAngle,
					math.min(Config.Controls.Camera.MaxVerticalAngle, X)
				)
				self.TargetAngleY = self.TargetAngleY - delta.X * sensitivity
			else
				-- Start tracking this touch for camera if it's moving
				cameraTouches[input] = Vector2.new(input.Position.X, input.Position.Y)
				-- Also track it in MobileControls so the jump button knows not to respond
				mobileControlsModule.CameraTouches[input] = true
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.UserInputType == Enum.UserInputType.Touch then
			cameraTouches[input] = nil
			-- Clean up tracking in MobileControls too
			mobileControlsModule.CameraTouches[input] = nil
		end
	end)
end


function CameraController:InitializeFirstPerson()
	-- CONVERT CAMERA TO ANGLES
	local lookVector = Camera.CFrame.LookVector

	self.TargetAngleY = math.deg(math.atan2(-lookVector.X, -lookVector.Z))
	self.TargetAngleX = math.deg(math.asin(lookVector.Y))

	self.TargetAngleX = math.max(
		Config.Controls.Camera.MinVerticalAngle,
		math.min(Config.Controls.Camera.MaxVerticalAngle, self.TargetAngleX)
	)

	self.AngleX = self.TargetAngleX
	self.AngleY = self.TargetAngleY

	self.LastFrameTime = tick()
end

function CameraController:StartCameraLoop()
	if self.Connection then
		self.Connection:Disconnect()
	end

	self.Connection = RunService.Heartbeat:Connect(function()
		self:UpdateFirstPersonCamera()
	end)
end

function CameraController:GetCrouchState()
	if not self.Character then
		return false
	end

	local normalHead = CharacterLocations:GetHead(self.Character)
	local crouchHead = CharacterLocations:GetCrouchHead(self.Character)
	
	-- If parts are missing, default to standing
	if not normalHead or not crouchHead then
		return false
	end

	-- More robust crouch detection: crouch head visible AND normal head hidden
	local normalHeadVisible = normalHead.Transparency < 1
	local crouchHeadVisible = crouchHead.Transparency < 1

	-- Only consider crouching if crouch head is visible AND normal head is hidden
	-- This prevents false positives during transition states
	if crouchHeadVisible and not normalHeadVisible then
		return true -- Crouching
	end
	
	-- IMPORTANT: If normal head is visible OR both are hidden (transition state),
	-- always return false to ensure camera returns to standing height
	return false
end

function CameraController:ToggleCameraMode()
	self.IsThirdPerson = not self.IsThirdPerson
	LogService:Info("CAMERA", "Camera mode toggled", { IsThirdPerson = self.IsThirdPerson })

	-- Transparency is handled by the camera update loop (UpdateFirstPersonCamera)
	-- on the same frame the camera moves to prevent visible flashing
end

-- Limbs to show in first person testing mode
local FIRST_PERSON_LIMBS = { Torso = true, ["Left Leg"] = true, ["Right Leg"] = true }

-- Helper: Apply first person transparency (hide rig, show test limbs if enabled)
function CameraController:ApplyFirstPersonTransparency()
	if not self.Rig then
		return
	end

	local showTestLimbs = Config.Gameplay.Character.ShowRigForTesting
	CharacterLocations:ForEachRigPart(self.Character, function(rigPart)
		rigPart.LocalTransparencyModifier = (showTestLimbs and FIRST_PERSON_LIMBS[rigPart.Name]) and 0 or 1
	end)

	-- Always hide accessories in first person
	local rigHumanoid = self.Rig:FindFirstChildOfClass("Humanoid")
	if rigHumanoid then
		for _, accessory in pairs(rigHumanoid:GetAccessories()) do
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.LocalTransparencyModifier = 1
			end
		end
	end
end

-- Helper: Apply transparency to rig parts and accessories
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

function CameraController:UpdateFirstPersonCamera()
	if not self.Character or not self.Character.Parent then
		return
	end

	-- Auto-initialize camera if character parts become available
	if not self.PrimaryPart or not self.Head then
		self.PrimaryPart = CharacterLocations:GetRoot(self.Character)
		self.Head = CharacterLocations:GetHumanoidHead(self.Character)
		if self.PrimaryPart and self.Head then
			-- Initialize camera state
			self.IsCrouching = false
			self.LastCrouchState = false
			self.CurrentCrouchOffset = 0
			self.IsTransitioning = false
			self:InitializeFirstPerson()
		else
			return -- Still waiting for PrimaryPart
		end
	end

	-- Get crouch state instead of head part
	self.IsCrouching = self:GetCrouchState()

	local currentTime = tick()
	local deltaTime = currentTime - self.LastFrameTime
	self.LastFrameTime = currentTime

	if math.abs(self.RightStickX) > 0.1 or math.abs(self.RightStickY) > 0.1 then
		-- Controller camera input - revert to original working version
		local horizontalInput = -self.RightStickX * Config.Controls.Camera.ControllerSensitivityX * deltaTime * 60
		local verticalInput = self.RightStickY * Config.Controls.Camera.ControllerSensitivityY * deltaTime * 60

		self.TargetAngleY = self.TargetAngleY + horizontalInput
		local newAngleX = self.TargetAngleX + verticalInput
		self.TargetAngleX = math.max(
			Config.Controls.Camera.MinVerticalAngle,
			math.min(Config.Controls.Camera.MaxVerticalAngle, newAngleX)
		)
	end

	if math.abs(self.MobileCameraX) > 0.05 or math.abs(self.MobileCameraY) > 0.05 then
		-- Mobile camera joystick input - continuous like controller with separate H/V sensitivity
		local horizontalInput = self.MobileCameraX * Config.Controls.Camera.MobileCameraSensitivity * deltaTime * 60
		local verticalInput = self.MobileCameraY
			* Config.Controls.Camera.MobileCameraSensitivityVertical
			* deltaTime
			* 60

		self.TargetAngleY = self.TargetAngleY + horizontalInput
		local newAngleX = self.TargetAngleX + verticalInput
		self.TargetAngleX = math.max(
			Config.Controls.Camera.MinVerticalAngle,
			math.min(Config.Controls.Camera.MaxVerticalAngle, newAngleX)
		)
	end

	-- SMOOTH CAMERA MOVEMENT using exponential decay for constant smooth interpolation
	-- This creates a natural "easing" effect that feels smooth regardless of framerate
	-- Convert user-friendly Smoothing (0-10) to internal AngleSmoothness (35-5)
	local userSmoothness = Config.Controls.Camera.Smoothing or 0
	local angleSmoothness = 35 - (userSmoothness * 3)
	local smoothFactor = math.exp(-angleSmoothness * deltaTime)

	self.AngleX = MathUtils.Lerp(self.TargetAngleX, self.AngleX, smoothFactor)

	-- Smooth Y angle (both target and current are unwrapped, can be any value)
	self.AngleY = MathUtils.Lerp(self.TargetAngleY, self.AngleY, smoothFactor)

	-- CROUCH OFFSET
	-- Check if crouch state changed
	if self.IsCrouching ~= self.LastCrouchState then
		-- Crouch state changed! Start transition only if smoothing is enabled
		if Config.Controls.Camera.EnableCrouchTransitionSmoothing then
			self.IsTransitioning = true
		else
			-- Instant positioning - no transition
			self.IsTransitioning = false
			self.CurrentCrouchOffset = self.IsCrouching and -Config.Gameplay.Character.CrouchHeightReduction or 0
		end
		self.LastCrouchState = self.IsCrouching
	end

	-- Update crouch offset (always smooth to prevent snapping)
	if Config.Controls.Camera.EnableCrouchTransitionSmoothing then
		-- Always smoothly adjust offset towards target
		local targetOffset = self.IsCrouching and -Config.Gameplay.Character.CrouchHeightReduction or 0
		self.CurrentCrouchOffset = MathUtils.Lerp(
			self.CurrentCrouchOffset,
			targetOffset,
			MathUtils.Clamp(Config.Controls.Camera.CrouchTransitionSpeed * deltaTime, 0, 1)
		)

		-- Check if transition is complete (for state tracking only, doesn't affect smoothing)
		local offsetDifference = math.abs(self.CurrentCrouchOffset - targetOffset)
		if offsetDifference < 0.05 then
			self.IsTransitioning = false
		end
	else
		-- Instant positioning when smoothing is disabled or user disabled transitions
		self.CurrentCrouchOffset = self.IsCrouching and -Config.Gameplay.Character.CrouchHeightReduction or 0
	end

	-- POSITION AT HEAD
	local baseHeadPosition = self.Head.Position
	local headCFrame = CFrame.new(baseHeadPosition + Vector3.new(0, self.CurrentCrouchOffset, 0))

	-- Apply horizontal rotation (character facing direction) to position the offset correctly
	-- Wrap AngleY to 0-360 range for rendering
	local wrappedAngleY = self.AngleY % 360

	if self.IsThirdPerson then
        -- OVER-THE-SHOULDER THIRD PERSON
        local distance = Config.Controls.Camera.ThirdPersonDistance      -- e.g. 6
        local height   = Config.Controls.Camera.ThirdPersonHeight        -- e.g. 1.5

        -- New offsets (add these to your Config)
        local shoulderX = Config.Controls.Camera.ShoulderOffsetX or 1.75   -- +right shoulder, try 1.25 - 2.0
        local shoulderY = Config.Controls.Camera.ShoulderOffsetY or 0.15   -- small lift, try 0.25 - 1.0

        -- Base pivot near head (plus your crouch offset) and a little height
        local pivotCF = headCFrame + Vector3.new(0, height, 0)

        -- Build aim rotation from yaw + pitch
        local yawCF   = CFrame.Angles(0, math.rad(wrappedAngleY), 0)
        local pitchCF = CFrame.Angles(math.rad(self.AngleX), 0, 0)

        -- IMPORTANT: yaw then pitch for typical shoulder controls
        local aimCF = pivotCF * yawCF * pitchCF

        -- Camera offset in the aim space:
        -- +X = right shoulder, +Y = up, +Z = backwards (Roblox CFrame: +Z goes "back")
        local desiredCameraCF = aimCF * CFrame.new(shoulderX, shoulderY, distance)
        local desiredCameraPosition = desiredCameraCF.Position

        -- Spherecast collision from pivot to desired camera position
        local rayOrigin = pivotCF.Position
        local rayDirection = desiredCameraPosition - rayOrigin

        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = { self.Character }
        raycastParams.RespectCanCollide = true
        raycastParams.CollisionGroup = "Players"

        local cameraRadius = 0.5
        local spherecastResult = workspace:Spherecast(rayOrigin, cameraRadius, rayDirection, raycastParams)

        local finalCameraPosition
        if spherecastResult then
            local hitDistance = (spherecastResult.Position - rayOrigin).Magnitude
            local safeDistance = math.max(hitDistance - 1, 0.5)
            finalCameraPosition = rayOrigin + (rayDirection.Unit * safeDistance)
        else
            finalCameraPosition = desiredCameraPosition
        end

        -- Look forward along aim direction (NOT at the head)
        local lookDir = aimCF.LookVector
        Camera.CFrame = CFrame.lookAt(finalCameraPosition, finalCameraPosition + lookDir)

        -- Distance-based transparency (your existing logic)
        local isRagdolled = self.Character:GetAttribute("RagdollActive")
        if not isRagdolled then
            local characterBodyPosition = self.PrimaryPart.Position
            local cameraDistance = (finalCameraPosition - characterBodyPosition).Magnitude
            self:UpdateDistanceBasedTransparency(cameraDistance)
        end
    else
        -- FIRST PERSON: Original behavior
        local characterRotation = headCFrame * CFrame.Angles(0, math.rad(wrappedAngleY), 0)
        local cameraOffset = Config.Controls.Camera.FirstPersonOffset

        -- Apply offset in character's local space (so it moves with character facing)
        local offsetPosition = characterRotation * CFrame.new(cameraOffset)

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
        Camera.CFrame = offsetPosition * CFrame.Angles(math.rad(self.AngleX), 0, 0)

        -- In first person, hide rig (unless ShowRigForTesting enabled for specific limbs)
        -- Skip transparency updates if character is ragdolled
        local isRagdolled = self.Character:GetAttribute("RagdollActive")
        if self.Rig and not isRagdolled then
            self:ApplyFirstPersonTransparency()
        end
    end

	-- CRITICAL: Update Camera.Focus to tell Roblox where to prioritize rendering
	-- This controls shadow distance, LOD, dynamic lighting, and other rendering optimizations
	-- Without this, rendering is centered at world origin (0,0,0) instead of the player
	Camera.Focus = CFrame.new(baseHeadPosition)
end

function CameraController:GetCameraAngles()
	return Vector2.new(self.AngleY, self.AngleX)
end

-- Method to update FOV dynamically from settings
function CameraController:SetFOV(fov)
	Camera.FieldOfView = fov
	LogService:Debug("CAMERA", "FOV updated", { FOV = fov })
end

-- Method to update body transparency dynamically from settings
function CameraController:SetBodyTransparency(transparency)
	if not self.Rig then
		LogService:Warn("CAMERA", "Cannot set body transparency - Rig not found")
		return
	end

	-- Apply LocalTransparencyModifier to all limbs
	local limbs = { "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
	for _, limbName in ipairs(limbs) do
		local limb = self.Rig:FindFirstChild(limbName)
		if limb and limb:IsA("BasePart") then
			limb.LocalTransparencyModifier = transparency
		end
	end

	LogService:Debug("CAMERA", "Body transparency updated", { Transparency = transparency })
end

function CameraController:Cleanup()
	-- Disconnect camera loop
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	-- Disconnect input connection
	if self.InputConnection then
		self.InputConnection:Disconnect()
		self.InputConnection = nil
	end

	-- Clear all references
	self.Character = nil
	self.PrimaryPart = nil
	self.Head = nil
	self.Rig = nil

	-- Reset camera state
	self.IsCrouching = false
	self.LastCrouchState = false
	self.CurrentCrouchOffset = 0
	self.IsTransitioning = false

	-- Reset mobile camera input
	self.MobileCameraX = 0
	self.MobileCameraY = 0
end

return CameraController
