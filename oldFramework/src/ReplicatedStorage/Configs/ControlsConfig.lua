local ControlsConfig = {}

-- =============================================================================
-- INPUT BINDINGS
-- =============================================================================

ControlsConfig.Input = {
	-- Keyboard bindings
	MoveForward = Enum.KeyCode.W,
	MoveBackward = Enum.KeyCode.S,
	MoveLeft = Enum.KeyCode.A,
	MoveRight = Enum.KeyCode.D,
	Jump = Enum.KeyCode.Space,
	Run = Enum.KeyCode.LeftShift,
	Slide = Enum.KeyCode.LeftShift,
	Crouch = Enum.KeyCode.C,

	-- Controller bindings
	ControllerJump = Enum.KeyCode.ButtonA,
	ControllerCrouch = Enum.KeyCode.ButtonL2,

	-- Mobile controls
	ShowMobileControls = true,
	MobileJoystickSize = 150,
	MobileButtonSize = 80,
}

-- =============================================================================
-- CUSTOMIZABLE KEYBINDS
-- These keybinds can be changed by players in the settings menu
-- =============================================================================

-- PC/Keyboard keybinds (shown on PC only)
ControlsConfig.CustomizableKeybinds = {
	-- Movement keys (WASD order)
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
		DefaultSecondary = Enum.UserInputType.MouseButton2,
		Category = "Movement",
	},
	-- UI keys
	{
		Key = "Settings",
		Label = "Open Settings",
		DefaultPrimary = Enum.KeyCode.O,
		DefaultSecondary = nil, -- PC only has O
		Category = "UI",
	},
}

-- Controller keybinds (shown in settings UI when on Controller only)
ControlsConfig.CustomizableControllerKeybinds = {
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
		Key = "Settings",
		Label = "Open Settings",
		DefaultPrimary = Enum.KeyCode.DPadUp,
		DefaultSecondary = nil,
		Category = "UI",
	},
}

-- =============================================================================
-- CAMERA SYSTEM
-- =============================================================================

ControlsConfig.Camera = {
	-- Basic camera settings (Rivals-style)
	FieldOfView = 80, -- Default FOV
	SlideFOV = 85,    -- FOV during slide (speed simulation)
	SlideFOVTweenTime = 0.1, -- Time to tween FOV
	
	-- Slide camera drop (lower camera during slide)
	SlideCameraDrop = 2,     -- Studs to lower camera
	SlideCameraDropTime = 0.1, -- Tween time

	-- Character rotation settings (AlignOrientation)
	Smoothness = 50, -- AlignOrientation responsiveness for character rotation (higher = snappier, lower = smoother) - Max 100 for validation

	-- Input sensitivity
	MouseSensitivity = 0.4,
	TouchSensitivity = 1,
	MobileCameraSensitivity = 3.75, -- Camera joystick horizontal sensitivity for mobile
	MobileCameraSensitivityVertical = 1.0, -- Camera joystick vertical sensitivity for mobile (slower up/down)
	ControllerSensitivityX = 6,
	ControllerSensitivityY = 6,

	-- Angle limits and smoothing (unified - no more duplicate settings)
	MinVerticalAngle = -80,
	MaxVerticalAngle = 80,
	AngleSmoothness = 50, -- Lower = smoother but more lag, Higher = snappier but less smooth. Max 100 for validation

	-- First person positioning
	FirstPersonOffset = Vector3.new(0, 0.25, -1),

	-- Third person positioning
	ThirdPersonDistance = 10, -- Distance camera is behind the character
	ThirdPersonHeight = 0, -- Height offset above character head (0 = orbit around head level)

	-- Crouch camera settings (uses GameplayConfig.Character.CrouchHeightReduction for offset amount)
	EnableCrouchTransitionSmoothing = true, -- Set to false for instant positioning
	CrouchTransitionSpeed = 12, -- Speed of crouch transition when smoothing is enabled

	-- FOV Effects (all FOV changes go through FOVController)
	FOVEffects = {
		Enabled = true,           -- Master toggle for all FOV effects
		SlideFOV = 5,             -- FOV increase during slide
		SprintFOV = 3,            -- FOV increase during sprint
		LerpAlpha = 0.06,         -- SLOWER lerp for longer zoom effect
		
		-- Velocity-based FOV (continuous based on 3D movement speed including falling)
		VelocityFOV = {
			Enabled = true,
			MinSpeed = 18,        -- Higher threshold - minimal FOV change at walk speed
			MaxSpeed = 100,       -- Higher to account for falling velocity
			MinFOVBoost = 0,      -- FOV boost at min speed
			MaxFOVBoost = 30,     -- VERY obvious max FOV boost for fast falls/runs
		},
		
		-- Legacy momentum config (now uses VelocityFOV instead)
		MomentumFOV = {
			Enabled = false,      -- Disabled - use VelocityFOV instead
			MaxFOVBoost = 8,
			SpeedThreshold = 20,
			MaxSpeed = 60,
		},
		TweenTime = 0.15,         -- Fallback for legacy systems
	},

	-- Screen Shake
	ScreenShake = {
		Enabled = true,           -- Master toggle for screen shake
		WallJump = {
			Intensity = 0.3,      -- Shake intensity (camera offset in studs)
			Duration = 0.2,       -- Shake duration in seconds
			Frequency = 15,       -- Shake frequency (oscillations/sec)
		},
	},

	-- Body transparency settings
	BodyPartTransparency = 0.6, -- Transparency for arms/legs in first person (0 = opaque, 1 = invisible)
}

return ControlsConfig
