local MobileControls = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)

local LogService = nil
local function getLogService()
	if not LogService then
		LogService = require(Locations.Modules.Systems.Core.LogService)
	end
	return LogService
end

local LocalPlayer = Players.LocalPlayer

MobileControls.ScreenGui = nil
MobileControls.MovementStick = nil
MobileControls.CameraStick = nil
MobileControls.JumpButton = nil
MobileControls.HitButton = nil

MobileControls.MovementVector = Vector2.new(0, 0)
MobileControls.CameraVector = Vector2.new(0, 0)
MobileControls.ClaimedTouches = {} -- Track touches claimed by UI elements
MobileControls.CameraTouches = {} -- Track touches being used for camera movement
MobileControls.IsAutoJumping = false -- Track if auto jump is enabled (button held)
MobileControls.AutoJumpConnection = nil -- Connection for auto jump loop
MobileControls.IsMenuOpen = false -- Track if Roblox menu is open

-- Track active touch inputs across all controls (need to be accessible for menu cleanup)
MobileControls.ActiveTouches = {
	Movement = nil,
	Camera = nil,
	Jump = nil,
	Hit = nil,
}

MobileControls.Callbacks = {
	Movement = {},
	Jump = {},
	Sprint = {},
	Crouch = {},
	Camera = {},
	Hit = {},
}

function MobileControls:Init()
	if not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then
		return -- Not a mobile device
	end

	self:SetupMenuDetection()
	self:CreateMobileUI()

	-- Mobile always auto-sprints (no manual sprint button)
	self:FireCallbacks("Sprint", true)

	local log = getLogService()
	log:Debug("MOBILE_UI", "MobileControls initialized with auto-sprint enabled")
end

function MobileControls:SetupMenuDetection()
	GuiService.MenuOpened:Connect(function()
		self.IsMenuOpen = true
		self:StopAllTouches()
	end)

	GuiService.MenuClosed:Connect(function()
		self.IsMenuOpen = false
	end)
end

function MobileControls:StopAllTouches()
	-- Reset movement stick
	if self.MovementStick then
		self.MovementStick.IsDragging = false
		self.MovementStick.Stick.Position = self.MovementStick.CenterPosition
		self.MovementVector = Vector2.new(0, 0)
		self:FireCallbacks("Movement", self.MovementVector)
	end

	-- Reset camera stick
	if self.CameraStick then
		self.CameraStick.IsDragging = false
		self.CameraStick.Stick.Position = self.CameraStick.CenterPosition
		self.CameraVector = Vector2.new(0, 0)

		-- Release crouch if camera stick had triggered it
		if self.CameraStick.HasTriggeredCrouch then
			self:FireCallbacks("Crouch", false)
			self.CameraStick.HasTriggeredCrouch = false
		end

		self:FireCallbacks("Camera", self.CameraVector)
	end

	-- Stop auto jump and reset button visual state
	self:StopAutoJump()
	if self.JumpButton then
		-- Force button to reset its visual state by toggling Active
		self.JumpButton.Active = true
		self.JumpButton.Active = false
	end

	-- Reset hit button state
	self.ActiveTouches.Hit = nil

	-- Clear all active touch references so new touches can be registered
	self.ActiveTouches.Movement = nil
	self.ActiveTouches.Camera = nil
	self.ActiveTouches.Jump = nil

	-- Clear all claimed touches
	self.ClaimedTouches = {}
end

function MobileControls:CreateMobileUI()
	-- Create ScreenGui
	self.ScreenGui = Instance.new("ScreenGui")
	self.ScreenGui.Name = "MobileControls"
	self.ScreenGui.ResetOnSpawn = false
	self.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	-- Create movement thumbstick
	self:CreateMovementStick()

	-- Create camera thumbstick
	self:CreateCameraStick()

	-- Create action buttons
	self:CreateActionButtons()
end

function MobileControls:CreateMovementStick()
	local stickContainer = Instance.new("Frame")
	stickContainer.Name = "MovementStickContainer"
	stickContainer.Size = UDim2.fromOffset(150, 150)
	stickContainer.Position = UDim2.new(0, 50, 1, -200)
	stickContainer.BackgroundTransparency = 0.5
	stickContainer.BackgroundColor3 = Color3.new(0, 0, 0)
	stickContainer.BorderSizePixel = 0
	stickContainer.Parent = self.ScreenGui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0.5, 0)
	containerCorner.Parent = stickContainer

	local stick = Instance.new("Frame")
	stick.Name = "MovementStick"
	stick.Size = UDim2.fromOffset(60, 60)
	stick.Position = UDim2.new(0.5, -30, 0.5, -30)
	stick.BackgroundColor3 = Color3.new(1, 1, 1)
	stick.BackgroundTransparency = 0.3
	stick.BorderSizePixel = 0
	stick.Parent = stickContainer

	local stickCorner = Instance.new("UICorner")
	stickCorner.CornerRadius = UDim.new(0.5, 0)
	stickCorner.Parent = stick

	self.MovementStick = {
		Container = stickContainer,
		Stick = stick,
		CenterPosition = UDim2.new(0.5, -30, 0.5, -30),
		MaxRadius = 45,
		IsDragging = false,
	}

	self:SetupStickInput()
end

function MobileControls:CreateCameraStick()
	local stickContainer = Instance.new("Frame")
	stickContainer.Name = "CameraStickContainer"
	stickContainer.Size = UDim2.fromOffset(150, 150)
	stickContainer.Position = UDim2.new(1, -200, 1, -200) -- Right side, same height as movement stick
	stickContainer.BackgroundTransparency = 0.5
	stickContainer.BackgroundColor3 = Color3.new(0, 0, 0)
	stickContainer.BorderSizePixel = 0
	stickContainer.Parent = self.ScreenGui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0.5, 0)
	containerCorner.Parent = stickContainer

	local stick = Instance.new("Frame")
	stick.Name = "CameraStick"
	stick.Size = UDim2.fromOffset(60, 60)
	stick.Position = UDim2.new(0.5, -30, 0.5, -30)
	stick.BackgroundColor3 = Color3.new(1, 1, 1)
	stick.BackgroundTransparency = 0.3
	stick.BorderSizePixel = 0
	stick.Parent = stickContainer

	local stickCorner = Instance.new("UICorner")
	stickCorner.CornerRadius = UDim.new(0.5, 0)
	stickCorner.Parent = stick

	self.CameraStick = {
		Container = stickContainer,
		Stick = stick,
		CenterPosition = UDim2.new(0.5, -30, 0.5, -30),
		MaxRadius = 45,
		IsDragging = false,
		HasTriggeredCrouch = false, -- Track if this touch has already triggered crouch
	}

	self:SetupCameraStickInput()
end

function MobileControls:CreateActionButtons()
	-- Jump button
	local jumpButton = Instance.new("TextButton")
	jumpButton.Name = "JumpButton"
	jumpButton.Size = UDim2.fromOffset(105, 105)
	jumpButton.Position = UDim2.new(1, -177, 1, -330)
	jumpButton.BackgroundColor3 = Color3.new(0, 0, 0)
	jumpButton.BackgroundTransparency = 0.5
	jumpButton.BorderSizePixel = 0
	jumpButton.Text = "Boing"
	jumpButton.Active = false -- Don't absorb input events, we'll handle them manually
	jumpButton.TextColor3 = Color3.new(1, 1, 1)
	jumpButton.TextScaled = false
	jumpButton.TextSize = 36
	jumpButton.Font = Enum.Font.SourceSansBold
	jumpButton.Parent = self.ScreenGui

	local jumpCorner = Instance.new("UICorner")
	jumpCorner.CornerRadius = UDim.new(0.5, 0)
	jumpCorner.Parent = jumpButton

	self.JumpButton = jumpButton

	-- Hit button (positioned above jump button)
	local hitButton = Instance.new("TextButton")
	hitButton.Name = "HitButton"
	hitButton.Size = UDim2.fromOffset(105, 105)
	hitButton.Position = UDim2.new(1, -177, 1, -455) -- Above jump button
	hitButton.BackgroundColor3 = Color3.new(0.8, 0.2, 0.2) -- Red color
	hitButton.BackgroundTransparency = 0.5
	hitButton.BorderSizePixel = 0
	hitButton.Text = "Hit"
	hitButton.Active = false -- Don't absorb input events, we'll handle them manually
	hitButton.TextColor3 = Color3.new(1, 1, 1)
	hitButton.TextScaled = false
	hitButton.TextSize = 36
	hitButton.Font = Enum.Font.SourceSansBold
	hitButton.Parent = self.ScreenGui

	local hitCorner = Instance.new("UICorner")
	hitCorner.CornerRadius = UDim.new(0.5, 0)
	hitCorner.Parent = hitButton

	self.HitButton = hitButton

	self:SetupButtonInput()
end

function MobileControls:SetupStickInput()
	local stick = self.MovementStick

	local function updateStickPosition(input)
		if not stick.IsDragging then
			return
		end

		local containerSize = stick.Container.AbsoluteSize
		local containerCenter = stick.Container.AbsolutePosition + containerSize / 2

		local inputPosition = Vector2.new(input.Position.X, input.Position.Y)
		local deltaFromCenter = inputPosition - containerCenter

		-- KEEP STICK IN CIRCLE
		local distance = math.min(deltaFromCenter.Magnitude, stick.MaxRadius)
		local direction = deltaFromCenter.Unit

		if deltaFromCenter.Magnitude > 0 then
			local finalPosition = direction * distance
			stick.Stick.Position =
				UDim2.fromOffset(containerSize.X / 2 + finalPosition.X - 30, containerSize.Y / 2 + finalPosition.Y - 30)

			-- Apply deadzone to movement vector
			local deadzone = 0.15 -- 15% deadzone
			local normalizedDistance = distance / stick.MaxRadius
			if normalizedDistance > deadzone then
				-- Scale from deadzone to full range
				local scaledDistance = (normalizedDistance - deadzone) / (1 - deadzone)
				self.MovementVector = Vector2.new(
					(finalPosition.X / stick.MaxRadius) * scaledDistance,
					(-finalPosition.Y / stick.MaxRadius) * scaledDistance
				)
			else
				self.MovementVector = Vector2.new(0, 0)
			end
		else
			stick.Stick.Position = stick.CenterPosition
			self.MovementVector = Vector2.new(0, 0)
		end

		self:FireCallbacks("Movement", self.MovementVector)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or self.IsMenuOpen then
			return
		end

		if input.UserInputType == Enum.UserInputType.Touch and not self.ActiveTouches.Movement then
			local inputPosition = Vector2.new(input.Position.X, input.Position.Y)
			local containerPosition = stick.Container.AbsolutePosition
			local containerSize = stick.Container.AbsoluteSize

			if
				inputPosition.X >= containerPosition.X
				and inputPosition.X <= containerPosition.X + containerSize.X
				and inputPosition.Y >= containerPosition.Y
				and inputPosition.Y <= containerPosition.Y + containerSize.Y
			then
				self.ActiveTouches.Movement = input
				stick.IsDragging = true
				self.ClaimedTouches[input] = "movement" -- Claim this touch
				updateStickPosition(input)
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input, _gameProcessed)
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Movement then
			updateStickPosition(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Movement then
			self.ActiveTouches.Movement = nil
			stick.IsDragging = false
			stick.Stick.Position = stick.CenterPosition
			self.MovementVector = Vector2.new(0, 0)
			self.ClaimedTouches[input] = nil -- Release this touch
			self:FireCallbacks("Movement", self.MovementVector)
		end
	end)
end

function MobileControls:SetupCameraStickInput()
	local stick = self.CameraStick

	local function updateCameraStickPosition(input)
		if not stick.IsDragging then
			return
		end

		local containerSize = stick.Container.AbsoluteSize
		local containerCenter = stick.Container.AbsolutePosition + containerSize / 2

		local inputPosition = Vector2.new(input.Position.X, input.Position.Y)
		local deltaFromCenter = inputPosition - containerCenter

		-- KEEP STICK IN CIRCLE
		local distance = math.min(deltaFromCenter.Magnitude, stick.MaxRadius)
		local direction = deltaFromCenter.Unit

		if deltaFromCenter.Magnitude > 0 then
			local finalPosition = direction * distance
			stick.Stick.Position =
				UDim2.fromOffset(containerSize.X / 2 + finalPosition.X - 30, containerSize.Y / 2 + finalPosition.Y - 30)

			-- Apply deadzone to camera vector (but crouch is still active regardless)
			local deadzone = 0.2 -- 20% deadzone for camera looking
			local normalizedDistance = distance / stick.MaxRadius
			if normalizedDistance > deadzone then
				-- Scale from deadzone to full range
				local scaledDistance = (normalizedDistance - deadzone) / (1 - deadzone)
				self.CameraVector = Vector2.new(
					(-finalPosition.X / stick.MaxRadius) * scaledDistance,
					(-finalPosition.Y / stick.MaxRadius) * scaledDistance
				)
			else
				self.CameraVector = Vector2.new(0, 0) -- No camera movement in deadzone, but crouch is still active
			end
		else
			stick.Stick.Position = stick.CenterPosition
			self.CameraVector = Vector2.new(0, 0)
		end

		self:FireCallbacks("Camera", self.CameraVector)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or self.IsMenuOpen then
			return
		end

		if input.UserInputType == Enum.UserInputType.Touch and not self.ActiveTouches.Camera then
			local inputPosition = Vector2.new(input.Position.X, input.Position.Y)
			local containerPosition = stick.Container.AbsolutePosition
			local containerSize = stick.Container.AbsoluteSize

			if
				inputPosition.X >= containerPosition.X
				and inputPosition.X <= containerPosition.X + containerSize.X
				and inputPosition.Y >= containerPosition.Y
				and inputPosition.Y <= containerPosition.Y + containerSize.Y
			then
				self.ActiveTouches.Camera = input
				stick.IsDragging = true
				stick.HasTriggeredCrouch = false
				self.ClaimedTouches[input] = "camera" -- Claim this touch

				-- Trigger crouch on any touch of the camera stick
				self:FireCallbacks("Crouch", true)
				stick.HasTriggeredCrouch = true

				updateCameraStickPosition(input)
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input, _gameProcessed)
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Camera then
			updateCameraStickPosition(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Camera then
			self.ActiveTouches.Camera = nil
			stick.IsDragging = false
			stick.Stick.Position = stick.CenterPosition
			self.CameraVector = Vector2.new(0, 0)
			self.ClaimedTouches[input] = nil -- Release this touch

			-- Release crouch when camera stick is released
			if stick.HasTriggeredCrouch then
				self:FireCallbacks("Crouch", false)
				stick.HasTriggeredCrouch = false
			end

			self:FireCallbacks("Camera", self.CameraVector)
		end
	end)
end

function MobileControls:SetupButtonInput()
	-- Use manual touch detection to avoid GUI interference with camera swiping
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or self.IsMenuOpen then
			return
		end

		if input.UserInputType == Enum.UserInputType.Touch then
			local inputPosition = Vector2.new(input.Position.X, input.Position.Y)

			-- Check hit button first (positioned above jump button)
			if not self.ActiveTouches.Hit then
				local hitButtonPosition = self.HitButton.AbsolutePosition
				local hitButtonSize = self.HitButton.AbsoluteSize
				local hitButtonCenter = hitButtonPosition + hitButtonSize / 2
				local hitButtonRadius = hitButtonSize.X / 2

				local distanceFromHitButton = (inputPosition - hitButtonCenter).Magnitude
				if distanceFromHitButton <= hitButtonRadius then
					if not self:IsTouchBeingUsedForCamera(input) then
						self.ActiveTouches.Hit = input
						self.ClaimedTouches[input] = "hit"
						self:FireCallbacks("Hit", true)
						return -- Don't check jump button
					end
				end
			end

			-- Check jump button
			if not self.ActiveTouches.Jump then
				local buttonPosition = self.JumpButton.AbsolutePosition
				local buttonSize = self.JumpButton.AbsoluteSize
				local buttonCenter = buttonPosition + buttonSize / 2
				local buttonRadius = buttonSize.X / 2

				-- Check if touch is within circular button bounds
				local distanceFromCenter = (inputPosition - buttonCenter).Magnitude
				if distanceFromCenter <= buttonRadius then
					-- Don't trigger jump if this touch is already being used for camera movement
					if not self:IsTouchBeingUsedForCamera(input) then
						self.ActiveTouches.Jump = input
						self.ClaimedTouches[input] = "jump" -- Claim this touch
						self:StartAutoJump()
					end
				end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _gameProcessed)
		-- Handle hit button release
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Hit then
			self.ActiveTouches.Hit = nil
			self.ClaimedTouches[input] = nil
			-- Hit is a single action, no release callback needed
		end

		-- Handle jump button release
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Jump then
			self.ActiveTouches.Jump = nil
			self.ClaimedTouches[input] = nil -- Release this touch
			self:StopAutoJump()
		end
	end)
end

function MobileControls:ConnectToInput(inputType, callback)
	if not self.Callbacks[inputType] then
		self.Callbacks[inputType] = {}
	end

	table.insert(self.Callbacks[inputType], callback)
end

function MobileControls:FireCallbacks(inputType, ...)
	if self.Callbacks[inputType] then
		for _, callback in pairs(self.Callbacks[inputType]) do
			callback(...)
		end
	end
end

function MobileControls:GetMovementVector()
	return self.MovementVector
end

function MobileControls:GetCameraVector()
	return self.CameraVector
end

function MobileControls:IsTouchClaimed(input)
	return self.ClaimedTouches[input] ~= nil
end

function MobileControls:IsTouchBeingUsedForCamera(input)
	-- This will be set by the camera controller when tracking touches
	return self.CameraTouches and self.CameraTouches[input] ~= nil
end

function MobileControls:StartAutoJump()
	if self.IsAutoJumping then
		return -- Already auto jumping
	end

	self.IsAutoJumping = true
	local log = getLogService()
	log:Debug("MOBILE_UI", "Auto jump started")

	-- Just hold jump - the movement system will handle it
	self:FireCallbacks("Jump", true)
end

function MobileControls:StopAutoJump()
	if not self.IsAutoJumping then
		return -- Not auto jumping
	end

	self.IsAutoJumping = false
	local log = getLogService()
	log:Debug("MOBILE_UI", "Auto jump stopped")

	-- Fire final jump release to ensure clean state
	self:FireCallbacks("Jump", false)
end

function MobileControls:IsAutoJumpActive()
	return self.IsAutoJumping
end

return MobileControls
