local InputManager = {}

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextChatService = game:GetService("TextChatService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))
local DEBUG_QUICK_MELEE_INPUT = true

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

InputManager.HorizontalPriority = nil
InputManager.VerticalPriority = nil

InputManager.InputMode = "Unknown"
InputManager.LastInputType = Enum.UserInputType.None
InputManager.ActiveGamepadType = Enum.UserInputType.Gamepad1
InputManager.GamepadSetupComplete = false

InputManager.Callbacks = {
	Movement = {},
	Jump = {},
	Look = {},
	Sprint = {},
	Crouch = {},
	Slide = {},
	Ability = {},
	Ultimate = {},
	Fire = {},
	Reload = {},
	QuickMelee = {},
	Inspect = {},
	Special = {},
	Camera = {},
	ToggleCameraMode = {},
	Settings = {},
	Emotes = {},
	SlotChange = {},
}

local function CheckKeybindMatch(input, keybind)
	if not keybind then
		return false
	end

	if typeof(keybind) == "EnumItem" and keybind.EnumType == Enum.UserInputType then
		return input.UserInputType == keybind
	end

	return input.KeyCode == keybind
end

local function IsGamepadInputType(inputType)
	return inputType == Enum.UserInputType.Gamepad1
		or inputType == Enum.UserInputType.Gamepad2
		or inputType == Enum.UserInputType.Gamepad3
		or inputType == Enum.UserInputType.Gamepad4
end

function InputManager:IsKeybind(input, keybindKey)
	-- Determine which keybind array to use based on the actual input device,
	-- not self.InputMode, because InputBegan can fire before LastInputTypeChanged
	-- updates the mode.
	local inputType = input.UserInputType
	local isGamepadInput = IsGamepadInputType(inputType)

	local keybindsArray = isGamepadInput and Config.Controls.CustomizableControllerKeybinds
		or Config.Controls.CustomizableKeybinds

	local defaultConfig = nil
	for _, keybindInfo in ipairs(keybindsArray) do
		if keybindInfo.Key == keybindKey then
			defaultConfig = keybindInfo
			break
		end
	end

	local primaryKeybind = defaultConfig and defaultConfig.DefaultPrimary
	if CheckKeybindMatch(input, primaryKeybind) then
		return true
	end

	local secondaryKeybind = defaultConfig and defaultConfig.DefaultSecondary
	if CheckKeybindMatch(input, secondaryKeybind) then
		return true
	end

	return false
end

function InputManager:CheckScrollWheelKeybind(keybindKey, scrollDirection)
	local keybindsArray = (self.InputMode == "Controller") and Config.Controls.CustomizableControllerKeybinds
		or Config.Controls.CustomizableKeybinds

	local defaultConfig = nil
	for _, keybindInfo in ipairs(keybindsArray) do
		if keybindInfo.Key == keybindKey then
			defaultConfig = keybindInfo
			break
		end
	end

	local primaryKeybind = defaultConfig and defaultConfig.DefaultPrimary
	if primaryKeybind == "ScrollWheelUp" and scrollDirection == "Up" then
		return true
	elseif primaryKeybind == "ScrollWheelDown" and scrollDirection == "Down" then
		return true
	end

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
		local previousMode = self.InputMode
		self.LastInputType = lastInputType
		self:DetectInputMode()
		local newMode = self.InputMode
		if previousMode ~= newMode then
			self:HandlePlatformModeChanged(previousMode, newMode, lastInputType)
		end
	end)

	UserInputService.GamepadConnected:Connect(function(gamepad)
		self.ActiveGamepadType = gamepad
		self:SetupGamepad()
	end)

	UserInputService.GamepadDisconnected:Connect(function(gamepad)
		if self.ActiveGamepadType == gamepad then
			self.ActiveGamepadType = Enum.UserInputType.Gamepad1
		end
	end)
end

function InputManager:HandlePlatformModeChanged(previousMode, newMode, lastInputType)
	if not previousMode or previousMode == "Unknown" then
		return
	end

	self:StopAllInputs()

	if FOVController and FOVController.ResetToConfigBase then
		FOVController:ResetToConfigBase()
	elseif FOVController and FOVController.Reset then
		local baseFOV = Config.Camera and Config.Camera.FOV and Config.Camera.FOV.Base or 80
		if FOVController.SetBaseFOV then
			FOVController:SetBaseFOV(baseFOV)
		end
		FOVController:Reset()
	end

	if newMode == "Controller" then
		self:ResampleGamepadMovement()
	end

	LogService:Info("INPUT", "Input mode changed; reset held input and FOV", {
		FromMode = previousMode,
		ToMode = newMode,
		LastInputType = tostring(lastInputType),
	})
end

function InputManager:SetupMenuDetection()
	GuiService.MenuOpened:Connect(function()
		self.IsMenuOpen = true
		self:StopAllInputs()
	end)

	GuiService.MenuClosed:Connect(function()
		self.IsMenuOpen = false
		self:ResampleGamepadMovement()
	end)
end

function InputManager:SetupChatDetection()
	local chatInputBar = TextChatService:WaitForChild("ChatInputBarConfiguration", 5)

	if chatInputBar then
		chatInputBar:GetPropertyChangedSignal("IsFocused"):Connect(function()
			local isFocused = chatInputBar.IsFocused
			self.IsChatFocused = isFocused

			if isFocused then
				self:StopAllInputs()
			end

			LogService:Debug("INPUT", "Chat focus changed", { IsChatFocused = isFocused })
		end)

		self.IsChatFocused = chatInputBar.IsFocused
	else
		LogService:Warn("INPUT", "ChatInputBarConfiguration not found - chat detection disabled")
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

	-- Reset mobile touch UI state (stick positions, claimed touches)
	if self.MobileControls then
		self.MobileControls:ResetTouchState()
	end

	self:FireCallbacks("Movement", self.Movement)
	self:FireCallbacks("Jump", false)
	self:FireCallbacks("Sprint", false)
	self:FireCallbacks("Crouch", false)
	self:FireCallbacks("Slide", false)
	self:FireCallbacks("Fire", false)
	self:FireCallbacks("Special", false)
	self:FireCallbacks("QuickMelee", false)
	self:FireCallbacks("Camera", Vector2.new(0, 0))
end

function InputManager:DetectInputMode()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		self.InputMode = "Mobile"
	elseif
		UserInputService.GamepadEnabled
		and (
			self.LastInputType == Enum.UserInputType.Gamepad1
			or self.LastInputType == Enum.UserInputType.Gamepad2
			or self.LastInputType == Enum.UserInputType.Gamepad3
			or self.LastInputType == Enum.UserInputType.Gamepad4
		)
	then
		self.InputMode = "Controller"
	elseif UserInputService.KeyboardEnabled then
		self.InputMode = "PC"
	else
		self.InputMode = "Unknown"
	end
end

function InputManager:_handleCoreInputBegan(input, gameProcessed)
	if gameProcessed or self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
		return
	end

	if self:IsKeybind(input, "Fire") then
		self:FireCallbacks("Fire", true)
	elseif self:IsKeybind(input, "Special") then
		self:FireCallbacks("Special", true)
	elseif self:IsKeybind(input, "Reload") then
		self:FireCallbacks("Reload", true)
	elseif self:IsKeybind(input, "QuickMelee") then
		self:FireCallbacks("QuickMelee", true)
	elseif self:IsKeybind(input, "Inspect") then
		self:FireCallbacks("Inspect", true)
	elseif self:IsKeybind(input, "MoveForward") then
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
	elseif self:IsKeybind(input, "Ability") then
		self:FireCallbacks("Ability", input.UserInputState)
	elseif self:IsKeybind(input, "Ultimate") then
		self:FireCallbacks("Ultimate", input.UserInputState)
	elseif self:IsKeybind(input, "ToggleCameraMode") then
		self:FireCallbacks("ToggleCameraMode", true)
	elseif self:IsKeybind(input, "Settings") then
		self:FireCallbacks("Settings", true)
	end
end

function InputManager:_handleCoreInputEnded(input, gameProcessed)
	if gameProcessed or self.IsMenuOpen or self.IsChatFocused or self.IsSettingsOpen then
		return
	end

	if self:IsKeybind(input, "Fire") then
		self:FireCallbacks("Fire", false)
	elseif self:IsKeybind(input, "Special") then
		self:FireCallbacks("Special", false)
	elseif self:IsKeybind(input, "Reload") then
		self:FireCallbacks("Reload", false)
	elseif self:IsKeybind(input, "QuickMelee") then
		self:FireCallbacks("QuickMelee", false)
	elseif self:IsKeybind(input, "Inspect") then
		self:FireCallbacks("Inspect", false)
	elseif self:IsKeybind(input, "MoveForward") then
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
	elseif self:IsKeybind(input, "Ability") then
		self:FireCallbacks("Ability", input.UserInputState)
	elseif self:IsKeybind(input, "Ultimate") then
		self:FireCallbacks("Ultimate", input.UserInputState)
	end
end

function InputManager:SetupKeyboardMouse()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if IsGamepadInputType(input.UserInputType) then
			return
		end

		-- Emote wheel works regardless of gameplay state (but not during chat)
		if not gameProcessed and not self.IsChatFocused then
			if input.KeyCode == Enum.KeyCode.B then
				self:FireCallbacks("Emotes", true)
				return
			end
		end

		self:_handleCoreInputBegan(input, gameProcessed)
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if IsGamepadInputType(input.UserInputType) then
			return
		end

		-- Emote wheel release
		if input.KeyCode == Enum.KeyCode.B then
			self:FireCallbacks("Emotes", false)
			return
		end

		self:_handleCoreInputEnded(input, gameProcessed)
	end)

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if
			gameProcessed
			or self.IsMenuOpen
			or self.IsChatFocused
			or self.IsSettingsOpen
		then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self.LookDelta = Vector2.new(input.Delta.X, input.Delta.Y)
			self:FireCallbacks("Look", self.LookDelta)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			local scrollDirection = input.Position.Z > 0 and "Up" or "Down"

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

	local starterScripts = Locations.Services.StarterPlayerScripts
	local uiFolder = starterScripts and starterScripts:FindFirstChild("UI")
	if not uiFolder then
		return
	end

	local success, MobileControls = pcall(function()
		return require(uiFolder:WaitForChild("MobileControls"))
	end)

	if success then
		MobileControls:Init(self)
		self.MobileControls = MobileControls
	else
		LogService:Warn("INPUT", "Failed to load mobile controls", { Error = MobileControls })
	end
end

function InputManager:SetupGamepad()
	if self.GamepadSetupComplete then
		return
	end

	self.GamepadSetupComplete = true
	LogService:Info("INPUT", "Gamepad listeners initialized", {
		GamepadEnabledAtInit = UserInputService.GamepadEnabled,
	})

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
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

		if input.UserInputType == Enum.UserInputType.Gamepad1
			or input.UserInputType == Enum.UserInputType.Gamepad2
			or input.UserInputType == Enum.UserInputType.Gamepad3
			or input.UserInputType == Enum.UserInputType.Gamepad4
		then
			self.ActiveGamepadType = input.UserInputType
			self.InputMode = "Controller"
		end

		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local rawMovement = Vector2.new(input.Position.X, input.Position.Y)

			if rawMovement.Magnitude > 0.1 then
				self.Movement = Vector2.new(rawMovement.X, rawMovement.Y)
			else
				self.Movement = Vector2.new(0, 0)
			end
			self:FireCallbacks("Movement", self.Movement)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			self.LookDelta = Vector2.new(input.Position.X * 2, -input.Position.Y * 2)
			self:FireCallbacks("Look", self.LookDelta)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not IsGamepadInputType(input.UserInputType) then
			return
		end

		self.ActiveGamepadType = input.UserInputType
		self.InputMode = "Controller"

		-- Emote wheel works regardless of menu state (but not during chat)
		if not self.IsChatFocused and input.KeyCode == Enum.KeyCode.DPadDown then
			self:FireCallbacks("Emotes", true)
			return
		end

		if DEBUG_QUICK_MELEE_INPUT and input.KeyCode == Enum.KeyCode.ButtonY then
			LogService:Info("INPUT_QM", "ButtonY InputBegan", {
				gameProcessed = gameProcessed,
				isMenuOpen = self.IsMenuOpen,
				isChatFocused = self.IsChatFocused,
				isSettingsOpen = self.IsSettingsOpen,
				matchesQuickMelee = self:IsKeybind(input, "QuickMelee"),
				matchesUltimate = self:IsKeybind(input, "Ultimate"),
			})
		end

		self:_handleCoreInputBegan(input, gameProcessed)
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if not IsGamepadInputType(input.UserInputType) then
			return
		end

		self.ActiveGamepadType = input.UserInputType
		self.InputMode = "Controller"

		-- Emote wheel release
		if input.KeyCode == Enum.KeyCode.DPadDown then
			self:FireCallbacks("Emotes", false)
			return
		end

		if DEBUG_QUICK_MELEE_INPUT and input.KeyCode == Enum.KeyCode.ButtonY then
			LogService:Info("INPUT_QM", "ButtonY InputEnded", {
				gameProcessed = gameProcessed,
				isMenuOpen = self.IsMenuOpen,
				isChatFocused = self.IsChatFocused,
				isSettingsOpen = self.IsSettingsOpen,
				matchesQuickMelee = self:IsKeybind(input, "QuickMelee"),
				matchesUltimate = self:IsKeybind(input, "Ultimate"),
			})
		end

		self:_handleCoreInputEnded(input, gameProcessed)
	end)
end

function InputManager:ResampleGamepadMovement()
	if not UserInputService.GamepadEnabled then
		return
	end

	if self.InputMode ~= "Controller" then
		return
	end

	local gamepadType = self.ActiveGamepadType or Enum.UserInputType.Gamepad1
	local states = UserInputService:GetGamepadState(gamepadType)
	for _, state in ipairs(states) do
		if state.KeyCode == Enum.KeyCode.Thumbstick1 then
			local rawMovement = Vector2.new(state.Position.X, state.Position.Y)
			if rawMovement.Magnitude > 0.1 then
				self.Movement = Vector2.new(rawMovement.X, rawMovement.Y)
			else
				self.Movement = Vector2.new(0, 0)
			end
			self:FireCallbacks("Movement", self.Movement)
			break
		end
	end
end

function InputManager:UpdateMovement()
	local x = 0
	local y = 0

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

	LogService:Info("INPUT", "Input state reset for character respawn")
end

return InputManager
