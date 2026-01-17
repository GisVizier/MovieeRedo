local Controls = {}

-- =============================================================================
-- KEYBOARD INPUT BINDINGS
-- =============================================================================
Controls.Input = {
	MoveForward = Enum.KeyCode.W,
	MoveBackward = Enum.KeyCode.S,
	MoveLeft = Enum.KeyCode.A,
	MoveRight = Enum.KeyCode.D,
	Jump = Enum.KeyCode.Space,
	Run = Enum.KeyCode.LeftShift,
	Slide = Enum.KeyCode.LeftShift,
	Crouch = Enum.KeyCode.C,
	ToggleCameraMode = Enum.KeyCode.T,  -- Cycles camera modes: Orbit -> Shoulder -> FirstPerson

	ControllerJump = Enum.KeyCode.ButtonA,
	ControllerCrouch = Enum.KeyCode.ButtonL2,

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
		DefaultPrimary = Enum.KeyCode.LeftControl,
		DefaultSecondary = nil,
		Category = "Movement",
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
}

-- =============================================================================
-- CUSTOMIZABLE CONTROLLER KEYBINDS
-- =============================================================================
Controls.CustomizableControllerKeybinds = {
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
		DefaultPrimary = Enum.KeyCode.ButtonR1,
		DefaultSecondary = nil,
		Category = "Movement",
	},
	{
		Key = "Crouch",
		Label = "Crouch",
		DefaultPrimary = Enum.KeyCode.ButtonL2,
		DefaultSecondary = nil,
		Category = "Movement",
	},
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
