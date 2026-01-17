local InputManager = {}

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local Config = require(Locations.Modules.Config)

local LogService = nil
local function getLogService()
	if not LogService then
		LogService = require(Locations.Modules.Systems.Core.LogService)
	end
	return LogService
end

InputManager.Movement = Vector2.new(0, 0)
InputManager.LookDelta = Vector2.new(0, 0)
InputManager.IsJumping = false
InputManager.IsSprinting = false
InputManager.IsCrouching = false


InputManager.IsMenuOpen = false
InputManager.IsChatFocused = false
InputManager.IsSettingsOpen = false

InputManager.KeyStates = {
	W = false,
	A = false,
	S = false,
	D = false,
}

-- LAST KEY PRESSED WINS
InputManager.HorizontalPriority = nil
InputManager.VerticalPriority = nil

InputManager.InputMode = "Unknown"
InputManager.LastInputType = Enum.UserInputType.None

InputManager.Callbacks = {
	Movement = {},
	Jump = {},
	Look = {},
	Sprint = {},
	Crouch = {},
	Slide = {},
	ToggleCameraMode = {},
}

-- Helper function to check if input matches a single keybind value
local function CheckKeybindMatch(input, keybind)
	if not keybind then
		return false
	end

	-- Check if it's a UserInputType (mouse button)
	if typeof(keybind) == "EnumItem" and keybind.EnumType == Enum.UserInputType then
		return input.UserInputType == keybind
	end

	-- Check if it's a KeyCode
	return input.KeyCode == keybind
end

-- Helper function to check if input matches a keybind (checks both primary and secondary slots)
function InputManager:IsKeybind(input, keybindKey)
	-- Use controller keybinds if in controller mode, otherwise use keyboard keybinds
	local keyPrefix = (self.InputMode == "Controller") and "Controller_Keybind_" or "Keybind_"
	local keybindsArray = (self.InputMode == "Controller")
		and Config.Controls.CustomizableControllerKeybinds
		or Config.Controls.CustomizableKeybinds

	-- Find the default keybind config for this key
	local defaultConfig = nil
	for _, keybindInfo in ipairs(keybindsArray) do
		if keybindInfo.Key == keybindKey then
			defaultConfig = keybindInfo
			break
		end
	end

	-- Check primary keybind slot (use default from config)
	local primaryKeybind = defaultConfig and defaultConfig.DefaultPrimary
	if CheckKeybindMatch(input, primaryKeybind) then
		return true
	end

	-- Check secondary keybind slot (use default from config)
	local secondaryKeybind = defaultConfig and defaultConfig.DefaultSecondary
	if CheckKeybindMatch(input, secondaryKeybind) then
		return true
	end

	return false
end

-- Helper function to handle scroll wheel input matching (checks both primary and secondary slots)
function InputManager:CheckScrollWheelKeybind(keybindKey, scrollDirection)
	-- Use controller keybinds if in controller mode, otherwise use keyboard keybinds
	local keybindsArray = (self.InputMode == "Controller")
		and Config.Controls.CustomizableControllerKeybinds
		or Config.Controls.CustomizableKeybinds

	-- Find the default keybind config for this key
	local defaultConfig = nil
	for _, keybindInfo in ipairs(keybindsArray) do
		if keybindInfo.Key == keybindKey then
			defaultConfig = keybindInfo
			break
		end
	end

	-- Check primary keybind slot (use default from config)
	local primaryKeybind = defaultConfig and defaultConfig.DefaultPrimary
	if primaryKeybind == "ScrollWheelUp" and scrollDirection == "Up" then
		return true
	elseif primaryKeybind == "ScrollWheelDown" and scrollDirection == "Down" then
		return true
	end

	-- Check secondary keybind slot (use default from config)
	local secondaryKeybind = defaultConfig and defaultConfig.DefaultSecondary
	if secondaryKeybind == "ScrollWheelUp" and scrollDirection == "Up" then
		return true
	elseif secondaryKeybind == "ScrollWheelDown" and scrollDirection == "Down" then
		return true
	end

	return false
end

function InputManager:Init()
	self:DetectInputMode()
	self:SetupMenuDetection()
	self:SetupChatDetection()
	self:SetupKeyboardMouse()
	self:SetupTouch()
	self:SetupGamepad()

	UserInputService.LastInputTypeChanged:Connect(function(lastInputType)
		self.LastInputType = lastInputType
		self:DetectInputMode()
	end)
end

function InputManager:SetupMenuDetection()
	GuiService.MenuOpened:Connect(function()
		self.IsMenuOpen = true
		self:StopAllInputs()
	end)

	GuiService.MenuClosed:Connect(function()
		self.IsMenuOpen = false
	end)
end

function InputManager:SetupChatDetection()
	-- Wait for ChatInputBarConfiguration to be available
	local chatInputBar = TextChatService:WaitForChild("ChatInputBarConfiguration", 5)

	if chatInputBar then
		-- Monitor IsFocused property changes
		chatInputBar:GetPropertyChangedSignal("IsFocused"):Connect(function()
			local isFocused = chatInputBar.IsFocused
			self.IsChatFocused = isFocused

			-- Stop all inputs when chat becomes focused
			if isFocused then
				self:StopAllInputs()
			end

			local log = getLogService()
			log:Debug("INPUT", "Chat focus changed", {
				IsChatFocused = isFocused,
			})
		end)

		-- Set initial state
		self.IsChatFocused = chatInputBar.IsFocused
	else
		local log = getLogService()
		log:Warn("INPUT", "ChatInputBarConfiguration not found - chat detection disabled")
	end
end

function InputManager:StopAllInputs()
	self.KeyStates.W = false
	self.KeyStates.A = false
	self.KeyStates.S = false
	self.KeyStates.D = false
	self.HorizontalPriority = nil
	self.VerticalPriority = nil
	self.IsJumping = false
	self.IsSprinting = false
	self.IsCrouching = false

	self.Movement = Vector2.new(0, 0)
	self.LookDelta = Vector2.new(0, 0)

	self:FireCallbacks("Movement", self.Movement)
	self:FireCallbacks("Jump", false)
	self:FireCallbacks("Sprint", false)
	self:FireCallbacks("Crouch", false)
	self:FireCallbacks("Slide", false)
end

function InputManager:DetectInputMode()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		self.InputMode = "Mobile"
	elseif UserInputService.GamepadEnabled and (
		self.LastInputType == Enum.UserInputType.Gamepad1
		or self.LastInputType == Enum.UserInputType.Gamepad2
		or self.LastInputType == Enum.UserInputType.Gamepad3
		or self.LastInputType == Enum.UserInputType.Gamepad4
	) then
		self.InputMode = "Controller"
	elseif UserInputService.KeyboardEnabled then
		self.InputMode = "PC"
	else
		self.InputMode = "Unknown"
	end
end

function InputManager:SetupKeyboardMouse()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
			return
		end

		if self:IsKeybind(input, "MoveForward") then
			self.KeyStates.W = true
			self.VerticalPriority = "W"
			self:UpdateMovement()
		elseif self:IsKeybind(input, "MoveBackward") then
			self.KeyStates.S = true
			self.VerticalPriority = "S"
			self:UpdateMovement()
		elseif self:IsKeybind(input, "MoveLeft") then
			self.KeyStates.A = true
			self.HorizontalPriority = "A"
			self:UpdateMovement()
		elseif self:IsKeybind(input, "MoveRight") then
			self.KeyStates.D = true
			self.HorizontalPriority = "D"
			self:UpdateMovement()
		elseif self:IsKeybind(input, "Jump") then
			if not self.IsMenuOpen then
				self.IsJumping = true
				self:FireCallbacks("Jump", true)
			end
		elseif self:IsKeybind(input, "Sprint") then
			self.IsSprinting = true
			self:FireCallbacks("Sprint", true)
		elseif self:IsKeybind(input, "Slide") then
			self:FireCallbacks("Slide", true)
		elseif self:IsKeybind(input, "Crouch") then
			self.IsCrouching = true
			self:FireCallbacks("Crouch", true)
		elseif input.KeyCode == Enum.KeyCode.J then
			RemoteEvents:FireServer("RequestNPCSpawn")
		elseif input.KeyCode == Enum.KeyCode.K then
			RemoteEvents:FireServer("RequestNPCRemoveOne")
		elseif input.KeyCode == Enum.KeyCode.G then
			-- Toggle camera mode (first person / third person)
			self:FireCallbacks("ToggleCameraMode", true)
		end
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed or self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
			return
		end

		if self:IsKeybind(input, "MoveForward") then
			self.KeyStates.W = false
			if self.VerticalPriority == "W" then
				self.VerticalPriority = self.KeyStates.S and "S" or nil
			end
			self:UpdateMovement()
		elseif self:IsKeybind(input, "MoveBackward") then
			self.KeyStates.S = false
			if self.VerticalPriority == "S" then
				self.VerticalPriority = self.KeyStates.W and "W" or nil
			end
			self:UpdateMovement()
		elseif self:IsKeybind(input, "MoveLeft") then
			self.KeyStates.A = false
			if self.HorizontalPriority == "A" then
				self.HorizontalPriority = self.KeyStates.D and "D" or nil
			end
			self:UpdateMovement()
		elseif self:IsKeybind(input, "MoveRight") then
			self.KeyStates.D = false
			if self.HorizontalPriority == "D" then
				self.HorizontalPriority = self.KeyStates.A and "A" or nil
			end
			self:UpdateMovement()
		elseif self:IsKeybind(input, "Jump") then
			if not self.IsMenuOpen then
				self.IsJumping = false
				self:FireCallbacks("Jump", false)
			end
		elseif self:IsKeybind(input, "Sprint") then
			self.IsSprinting = false
			self:FireCallbacks("Sprint", false)
		elseif self:IsKeybind(input, "Slide") then
			self:FireCallbacks("Slide", false)
		elseif self:IsKeybind(input, "Crouch") then
			self.IsCrouching = false
			self:FireCallbacks("Crouch", false)
		end
	end)

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed or self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self.LookDelta = Vector2.new(input.Delta.X, input.Delta.Y)
			self:FireCallbacks("Look", self.LookDelta)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			-- Detect scroll wheel direction (Z > 0 = scroll up, Z < 0 = scroll down)
			local scrollDirection = input.Position.Z > 0 and "Up" or "Down"

			-- Check each action to see if it's bound to this scroll direction
			if self:CheckScrollWheelKeybind("Jump", scrollDirection) then
				self.IsJumping = true
				self:FireCallbacks("Jump", true)
				task.delay(0.05, function()
					self.IsJumping = false
					self:FireCallbacks("Jump", false)
				end)
			elseif self:CheckScrollWheelKeybind("Slide", scrollDirection) then
				self:FireCallbacks("Slide", true)
				task.delay(0.05, function()
					self:FireCallbacks("Slide", false)
				end)
			elseif self:CheckScrollWheelKeybind("Crouch", scrollDirection) then
				self.IsCrouching = true
				self:FireCallbacks("Crouch", true)
				task.delay(0.05, function()
					self.IsCrouching = false
					self:FireCallbacks("Crouch", false)
				end)
			end
		end
	end)
end

function InputManager:SetupTouch()
	if not UserInputService.TouchEnabled then
		return
	end

	local success, MobileControls = pcall(function()
		return require(Locations.Client.UI.MobileControls)
	end)

	if success then
		MobileControls:Init()
		self.MobileControls = MobileControls

		MobileControls:ConnectToInput("Movement", function(movement)
			if self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
				movement = Vector2.new(0, 0)
			end
			self.Movement = movement
			self:FireCallbacks("Movement", movement)
		end)

		MobileControls:ConnectToInput("Jump", function(isJumping)
			if self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
				isJumping = false
			end
			self.IsJumping = isJumping
			self:FireCallbacks("Jump", isJumping)
		end)

		MobileControls:ConnectToInput("Crouch", function(isCrouching)
			if self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
				isCrouching = false
			end
			self.IsCrouching = isCrouching
			self:FireCallbacks("Crouch", isCrouching)
		end)

		MobileControls:ConnectToInput("Slide", function(isSliding)
			if self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
				isSliding = false
			end
			self:FireCallbacks("Slide", isSliding)
		end)

	else
		local log = getLogService()
		log:Warn("INPUT", "Failed to load mobile controls", { Error = MobileControls })
	end
end

function InputManager:SetupGamepad()
	if not UserInputService.GamepadEnabled then
		return
	end

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		-- Don't filter gameProcessed for controller thumbstick input - Roblox ControlScript interferes
		if
			self.IsMenuOpen
			or self.IsChatFocused
			or self.IsSettingsOpen
			or (
				gameProcessed
				and input.KeyCode ~= Enum.KeyCode.Thumbstick1
				and input.KeyCode ~= Enum.KeyCode.Thumbstick2
			)
		then
			return
		end

		-- Detect any gamepad input, not just Gamepad1
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			-- Only process controller movement if we're in controller mode
			if self.InputMode ~= "Controller" then
				return
			end

			-- Left stick movement: X = left/right, Y = forward/back
			local rawMovement = Vector2.new(input.Position.X, input.Position.Y)

			if rawMovement.Magnitude > 0.1 then
				self.Movement = Vector2.new(rawMovement.X, rawMovement.Y)
			else
				self.Movement = Vector2.new(0, 0)
			end
			self:FireCallbacks("Movement", self.Movement)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			-- Only process controller look if we're in controller mode
			if self.InputMode ~= "Controller" then
				return
			end

			-- Right stick camera look - pass raw values to camera controller
			self.LookDelta = Vector2.new(input.Position.X * 2, -input.Position.Y * 2)
			self:FireCallbacks("Look", self.LookDelta)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- Only process controller inputs in controller mode
		if self.InputMode ~= "Controller" then
			return
		end

		-- Check for gamepad input type
		if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
			return
		end

		-- Don't process if menu/chat open or settings open
		if self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
			return
		end

		-- Use IsKeybind to check customizable controller keybinds
		if self:IsKeybind(input, "Jump") then
			if not self.IsMenuOpen then
				self.IsJumping = true
				self:FireCallbacks("Jump", true)
			end
		elseif self:IsKeybind(input, "Sprint") then
			self.IsSprinting = true
			self:FireCallbacks("Sprint", true)
		elseif self:IsKeybind(input, "Slide") then
			self:FireCallbacks("Slide", true)
		elseif self:IsKeybind(input, "Crouch") then
			self.IsCrouching = true
			self:FireCallbacks("Crouch", true)
		end
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		-- Only process controller inputs in controller mode
		if self.InputMode ~= "Controller" then
			return
		end

		-- Check for gamepad input type
		if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
			return
		end

		-- Don't process if menu/chat open or settings open
		if self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
			return
		end

		-- Use IsKeybind to check customizable controller keybinds
		if self:IsKeybind(input, "Jump") then
			if not self.IsMenuOpen then
				self.IsJumping = false
				self:FireCallbacks("Jump", false)
			end
		elseif self:IsKeybind(input, "Sprint") then
			self.IsSprinting = false
			self:FireCallbacks("Sprint", false)
		elseif self:IsKeybind(input, "Slide") then
			self:FireCallbacks("Slide", false)
		elseif self:IsKeybind(input, "Crouch") then
			self.IsCrouching = false
			self:FireCallbacks("Crouch", false)
		end
	end)
end

function InputManager:UpdateMovement()
	local x = 0
	local y = 0

	-- FIX STUCK MOVEMENT
	local dPressed = self.KeyStates.D
	local aPressed = self.KeyStates.A

	if (self.HorizontalPriority == "D" and dPressed) or (dPressed and not aPressed) then
		x = 1
	elseif (self.HorizontalPriority == "A" and aPressed) or (aPressed and not dPressed) then
		x = -1
	end

	local wPressed = self.KeyStates.W
	local sPressed = self.KeyStates.S

	if (self.VerticalPriority == "W" and wPressed) or (wPressed and not sPressed) then
		y = 1
	elseif (self.VerticalPriority == "S" and sPressed) or (sPressed and not wPressed) then
		y = -1
	end

	local newMovement = Vector2.new(x, y)

	if newMovement ~= self.Movement then
		self.Movement = newMovement
		self:FireCallbacks("Movement", self.Movement)
	end
end

function InputManager:ConnectToInput(inputType, callback)
	if not self.Callbacks[inputType] then
		self.Callbacks[inputType] = {}
	end

	table.insert(self.Callbacks[inputType], callback)
end

function InputManager:FireCallbacks(inputType, ...)
	local callbacks = self.Callbacks[inputType]
	if callbacks then
		for _, callback in ipairs(callbacks) do
			callback(...)
		end
	end
end

function InputManager:GetMovementVector()
	return self.Movement
end

function InputManager:GetLookDelta()
	local delta = self.LookDelta
	self.LookDelta = Vector2.new(0, 0)
	return delta
end

function InputManager:IsJumpHeld()
	return self.IsJumping
end

function InputManager:IsSprintHeld()
	return self.IsSprinting
end

function InputManager:IsCrouchHeld()
	return self.IsCrouching
end

function InputManager:ResetInputState()
	self.KeyStates.W = false
	self.KeyStates.A = false
	self.KeyStates.S = false
	self.KeyStates.D = false
	self.HorizontalPriority = nil
	self.VerticalPriority = nil
	self.IsJumping = false
	self.IsSprinting = false
	self.IsCrouching = false

	self.Movement = Vector2.new(0, 0)
	self.LookDelta = Vector2.new(0, 0)

	self:FireCallbacks("Movement", self.Movement)
	self:FireCallbacks("Jump", false)
	self:FireCallbacks("Sprint", false)
	self:FireCallbacks("Crouch", false)
	self:FireCallbacks("Slide", false)

	local log = getLogService()
	log:Info("INPUT", "Input state reset for character respawn")
end

return InputManager
