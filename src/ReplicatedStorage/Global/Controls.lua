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
	Special = Enum.UserInputType.MouseButton2, -- ADS
	Reload = Enum.KeyCode.R,
	QuickMelee = Enum.KeyCode.F,
	Inspect = Enum.KeyCode.T,
	Ability = Enum.KeyCode.E,
	Ultimate = Enum.KeyCode.Q,

	-- Camera & UI
	ToggleCameraMode = Enum.KeyCode.Y,

	-- Controller defaults
	ControllerJump = Enum.KeyCode.ButtonA,
	ControllerCrouch = Enum.KeyCode.ButtonB,
	ControllerFire = Enum.KeyCode.ButtonR2,
	ControllerSpecial = Enum.KeyCode.ButtonL2, -- ADS
	ControllerReload = Enum.KeyCode.ButtonX,
	ControllerQuickMelee = Enum.KeyCode.ButtonY,
	ControllerAbility = Enum.KeyCode.ButtonL1,
	ControllerUltimate = Enum.KeyCode.ButtonY,

	-- Mobile settings
	ShowMobileControls = true,
}

-- =============================================================================
-- MOBILE DEFAULT POSITIONS
-- =============================================================================
-- Single source of truth for every mobile UI element's layout.
-- MobileControls.lua reads from this table instead of hardcoding positions.
--
-- Action buttons use:  Size, RightOffset, BottomOffset, Label
-- Sticks use:          Position (UDim2), Size (px), ThumbSize (px)
-- WeaponSlots uses:    Position (UDim2), ButtonWidth, ButtonHeight, Gap
-- AmmoDisplay uses:    Position (UDim2), Size (UDim2)
-- =============================================================================
Controls.DefaultPositions = {
	-- Movement stick (bottom-left)
	MovementStick = {
		Position = UDim2.new(0, 14, 1, -176),
		Size = 130,
		ThumbSize = 52,
	},

	-- Camera stick (right side, left of action cluster)
	CameraStick = {
		Position = UDim2.new(1, -326, 1, -166),
		Size = 120,
		ThumbSize = 46,
	},

	-- Action cluster buttons (anchored from bottom-right)
	--  Layout (right-anchored, from bottom up):
	--    Row 3:         [E]  [Q]
	--    Row 2:   [R] [ADS]  [FIRE]
	--    Row 1:        [C/S]  [JUMP]
	Jump = {
		Size = 86,
		RightOffset = 14,
		BottomOffset = 46,
		Label = "JUMP",
	},
	CrouchSlide = {
		Size = 48,
		RightOffset = 110,
		BottomOffset = 65,
		Label = "C",
	},
	Fire = {
		Size = 66,
		RightOffset = 24,
		BottomOffset = 142,
		Label = "FIRE",
	},
	ADS = {
		Size = 48,
		RightOffset = 100,
		BottomOffset = 151,
		Label = "ADS",
	},
	Reload = {
		Size = 48,
		RightOffset = 158,
		BottomOffset = 151,
		Label = "R",
	},
	Ability = {
		Size = 48,
		RightOffset = 33,
		BottomOffset = 218,
		Label = "E",
	},
	Ultimate = {
		Size = 48,
		RightOffset = 91,
		BottomOffset = 218,
		Label = "Q",
	},

	-- Weapon slot bar (top-right)
	WeaponSlots = {
		Position = UDim2.new(1, -14, 0, 8),
		ButtonWidth = 72,
		ButtonHeight = 56,
		Gap = 6,
	},

	-- Ammo display (bottom-right corner)
	AmmoDisplay = {
		Position = UDim2.new(1, 0, 1, -28),
		Size = UDim2.fromOffset(56, 32),
	},
}

-- =============================================================================
-- CUSTOMIZABLE KEYBOARD KEYBINDS
-- =============================================================================
-- DefaultPositions: mobile UI layout (MobileControls.lua). Action buttons use
-- Size/RightOffset/BottomOffset/Label; Sticks use Position/Size/ThumbSize;
-- WeaponSlots uses Position/ButtonWidth/ButtonHeight/Gap; AmmoDisplay uses Position/Size.
-- =============================================================================
Controls.CustomizableKeybinds = {
	DefaultPositions = {
		MovementStick = {
			Position = UDim2.new(0, 14, 1, -176),
			Size = 130,
			ThumbSize = 52,
		},
		Emote = { LeftOffset = 14, BottomOffset = 200, Size = 48, Label = "B" },
		CameraStick = {
			Position = UDim2.new(1, -326, 1, -166),
			Size = 120,
			ThumbSize = 46,
		},
		Jump = { Size = 86, RightOffset = 14, BottomOffset = 46, Label = "JUMP" },
		CrouchSlide = { Size = 48, RightOffset = 110, BottomOffset = 65, Label = "C" },
		Fire = { Size = 66, RightOffset = 24, BottomOffset = 142, Label = "FIRE" },
		ADS = { Size = 48, RightOffset = 100, BottomOffset = 151, Label = "ADS" },
		Reload = { Size = 48, RightOffset = 158, BottomOffset = 151, Label = "R" },
		Ability = { Size = 48, RightOffset = 33, BottomOffset = 218, Label = "E" },
		Ultimate = { Size = 48, RightOffset = 91, BottomOffset = 218, Label = "Q" },
		WeaponSlots = {
			Position = UDim2.new(1, -14, 0, 8),
			ButtonWidth = 72,
			ButtonHeight = 56,
			Gap = 6,
		},
		AmmoDisplay = {
			Position = UDim2.new(1, 0, 1, -28),
			Size = UDim2.fromOffset(56, 32),
		},
	},
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
		Key = "QuickMelee",
		Label = "Quick Melee",
		DefaultPrimary = Enum.KeyCode.F,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Inspect",
		Label = "Inspect Weapon",
		DefaultPrimary = Enum.KeyCode.T,
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
		Key = "EquipPrimary",
		Label = "Equip Primary",
		DefaultPrimary = Enum.KeyCode.One,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "EquipSecondary",
		Label = "Equip Secondary",
		DefaultPrimary = Enum.KeyCode.Two,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "EquipMelee",
		Label = "Equip Melee",
		DefaultPrimary = Enum.KeyCode.Three,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "ToggleCameraMode",
		Label = "Toggle Camera",
		DefaultPrimary = Enum.KeyCode.Y,
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
		Key = "QuickMelee",
		Label = "Quick Melee",
		DefaultPrimary = Enum.KeyCode.ButtonY,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Inspect",
		Label = "Inspect Weapon",
		DefaultPrimary = nil,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "Ability",
		Label = "Use Ability",
		DefaultPrimary = Enum.KeyCode.DPadRight,
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
	{
		Key = "CycleWeaponLeft",
		Label = "Cycle Weapon Left",
		DefaultPrimary = Enum.KeyCode.ButtonL1,
		DefaultSecondary = nil,
		Category = "Combat",
	},
	{
		Key = "CycleWeaponRight",
		Label = "Cycle Weapon Right",
		DefaultPrimary = Enum.KeyCode.ButtonR1,
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
