local Controls = {}

-- =============================================================================
-- KEYBOARD INPUT BINDINGS (Legacy - use CustomizableKeybinds instead)
-- =============================================================================
Controls.Input = {
	-- Movement
	MoveForward = Enum.KeyCode.W,
	MoveBackward = Enum.KeyCode.S,
	MoveLeft = Enum.KeyCode.A,
	MoveRight = Enum.KeyCode.D,
	Jump = Enum.KeyCode.Space,
	Run = Enum.KeyCode.LeftShift,
	Slide = Enum.KeyCode.V,
	Crouch = Enum.KeyCode.C,
	
	-- Combat
	Fire = Enum.UserInputType.MouseButton1,
	Special = Enum.UserInputType.MouseButton2,  -- ADS
	Reload = Enum.KeyCode.R,
	Inspect = Enum.KeyCode.F,
	Ability = Enum.KeyCode.E,
	Ultimate = Enum.KeyCode.Q,
	
	-- Camera & UI
	ToggleCameraMode = Enum.KeyCode.T,
	ToggleRagdollTest = Enum.KeyCode.G,

	-- Controller defaults
	ControllerJump = Enum.KeyCode.ButtonA,
	ControllerCrouch = Enum.KeyCode.ButtonB,
	ControllerFire = Enum.KeyCode.ButtonR2,
	ControllerSpecial = Enum.KeyCode.ButtonL2,  -- ADS
	ControllerReload = Enum.KeyCode.ButtonX,
	ControllerAbility = Enum.KeyCode.ButtonL1,
	ControllerUltimate = Enum.KeyCode.ButtonY,

	-- Mobile settings
	ShowMobileControls = true,
	MobileJoystickSize = 150,
	MobileButtonSize = 80,
}

-- =============================================================================
-- CUSTOMIZABLE KEYBOARD KEYBINDS
-- =============================================================================
Controls.CustomizableKeybinds = {
	{
		Key = "MoveForward",
		Label = "Move Forward",
		DefaultPrimary = Enum.KeyCode.W,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "MoveLeft",
		Label = "Move Left",
		DefaultPrimary = Enum.KeyCode.A,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "MoveBackward",
		Label = "Move Backward",
		DefaultPrimary = Enum.KeyCode.S,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "MoveRight",
		Label = "Move Right",
		DefaultPrimary = Enum.KeyCode.D,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "Jump",
		Label = "Jump",
		DefaultPrimary = Enum.KeyCode.Space,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "Sprint",
		Label = "Sprint",
		DefaultPrimary = Enum.KeyCode.LeftShift,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "Slide",
		Label = "Slide",
		DefaultPrimary = Enum.KeyCode.V,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "Crouch",
		Label = "Crouch",
		DefaultPrimary = Enum.KeyCode.C,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "Fire",
		Label = "Fire / Attack",
		DefaultPrimary = Enum.UserInputType.MouseButton1,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Special",
		Label = "ADS / Special",
		DefaultPrimary = Enum.UserInputType.MouseButton2,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Reload",
		Label = "Reload",
		DefaultPrimary = Enum.KeyCode.R,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Inspect",
		Label = "Inspect Weapon",
		DefaultPrimary = Enum.KeyCode.F,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Ability",
		Label = "Use Ability",
		DefaultPrimary = Enum.KeyCode.E,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Ultimate",
		Label = "Use Ultimate",
		DefaultPrimary = Enum.KeyCode.Q,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "ToggleCameraMode",
		Label = "Toggle Camera",
		DefaultPrimary = Enum.KeyCode.T,
		DefaultSecondary = nil,
		Category = "Camera",
	},
	{
		Key = "Settings",
		Label = "Open Settings",
		DefaultPrimary = Enum.KeyCode.O,
		DefaultSecondary = nil,
		Category = "UI",
	},
	{
		Key = "ToggleRagdollTest",
		Label = "Toggle Ragdoll (Test)",
		DefaultPrimary = Enum.KeyCode.G,
		DefaultSecondary = nil,
		Category = "Debug",
	},
}

-- =============================================================================
-- CUSTOMIZABLE CONTROLLER KEYBINDS
-- =============================================================================
Controls.CustomizableControllerKeybinds = {
	-- Movement
	{
		Key = "Jump",
		Label = "Jump",
		DefaultPrimary = Enum.KeyCode.ButtonA,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "Sprint",
		Label = "Sprint",
		DefaultPrimary = Enum.KeyCode.ButtonL3,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "Slide",
		Label = "Slide",
		DefaultPrimary = Enum.KeyCode.ButtonR3,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "Crouch",
		Label = "Crouch",
		DefaultPrimary = Enum.KeyCode.ButtonB,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	
	-- Combat
	{
		Key = "Fire",
		Label = "Fire / Attack",
		DefaultPrimary = Enum.KeyCode.ButtonR2,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Special",
		Label = "ADS / Special",
		DefaultPrimary = Enum.KeyCode.ButtonL2,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Reload",
		Label = "Reload",
		DefaultPrimary = Enum.KeyCode.ButtonX,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Inspect",
		Label = "Inspect Weapon",
		DefaultPrimary = Enum.KeyCode.DPadRight,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Ability",
		Label = "Use Ability",
		DefaultPrimary = Enum.KeyCode.ButtonL1,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Ultimate",
		Label = "Use Ultimate",
		DefaultPrimary = Enum.KeyCode.ButtonY,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	
	-- Camera & UI
	{
		Key = "ToggleCameraMode",
		Label = "Toggle Camera",
		DefaultPrimary = Enum.KeyCode.DPadLeft,
		DefaultSecondary = nil,
		Category = "Camera",
	},
	{
		Key = "Settings",
		Label = "Open Settings",
		DefaultPrimary = Enum.KeyCode.DPadUp,
		DefaultSecondary = nil,
		Category = "UI",
	},
}

return Controls
