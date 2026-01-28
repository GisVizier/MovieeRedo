local Camera = {}

-- =============================================================================
-- CAMERA MODES
-- =============================================================================
Camera.Modes = {
	Orbit = "Orbit",           -- Mode A: Default Roblox orbit camera
	Shoulder = "Shoulder",     -- Mode B: Over-the-shoulder (Fortnite-like)
	FirstPerson = "FirstPerson", -- Mode C: First person
}

Camera.DefaultMode = "Orbit"

-- Order for cycling with T key
Camera.CycleOrder = { "Orbit", "Shoulder", "FirstPerson" }

-- =============================================================================
-- SENSITIVITY SETTINGS
-- =============================================================================
Camera.Sensitivity = {
	Mouse = 0.4,
	Touch = 1.0,
	MobileHorizontal = 3.75,
	MobileVertical = 1.0,
	ControllerX = 6,
	ControllerY = 6,
}

-- =============================================================================
-- ANGLE LIMITS
-- =============================================================================
Camera.AngleLimits = {
	MinVertical = -80,
	MaxVertical = 80,
}

-- =============================================================================
-- SMOOTHING 2
-- =============================================================================
Camera.Smoothing = {
	AngleSmoothness = 50,       -- Higher = smoother (less responsive)
	CrouchTransitionSpeed = 12,
	EnableCrouchTransition = true,
	ModeTransitionTime = 0.067,  -- Seconds to blend between camera modes
}

-- =============================================================================
-- MODE A: ORBIT CAMERA (Default Roblox-like)
-- =============================================================================
Camera.Orbit = {
	Distance = 12,              -- Default distance from character
	MinDistance = 2,            -- Minimum zoom distance
	MaxDistance = 25,           -- Maximum zoom distance
	Height = 2,                 -- Height offset above character
	RotateCharacter = false,    -- Do NOT auto-rotate character to camera yaw
	CollisionRadius = 0.5,      -- Sphere cast radius for collision
	CollisionBuffer = 0.5,      -- Buffer distance from collision point
}

-- =============================================================================
-- MODE B: OVER-THE-SHOULDER (v1 values)
-- =============================================================================
Camera.Shoulder = {
	Distance = 10,              -- v1: ThirdPersonDistance = 10
	Height = 0,                 -- v1: ThirdPersonHeight = 0 (orbit around head level)
	ShoulderOffsetX = 1.75,     -- Right shoulder offset (+X = right)
	ShoulderOffsetY = 0.15,     -- Vertical offset from shoulder
	RotateCharacter = true,     -- Auto-rotate character to camera yaw
	CollisionRadius = 0.5,      -- Sphere cast radius for collision
	CollisionBuffer = 1.0,      -- Buffer distance from collision point
	MinCollisionDistance = 0.5, -- Minimum distance to maintain
}

-- =============================================================================
-- MODE C: FIRST PERSON (Ported from v1)
-- =============================================================================
Camera.FirstPerson = {
	-- X = left/right (0 = centered)
	-- Y = up/down (negative = lower, closer to eye level)
	-- Z = forward/back
	Offset = Vector3.new(0, .4, 0),  -- Lowered significantly for realistic eye level

	-- Use humanoid Head position (not the visual Rig's head)
	FollowHead = false,
	HeadOffset = Vector3.new(0, -.15, 0),
	HeadRotationOffset = Vector3.new(0, 0, 0), -- degrees (X,Y,Z)

	RotateCharacter = true,     -- Auto-rotate character to camera yaw

	-- Disable ground clamping in first person (prevents camera being forced above ceilings)
	DisableGroundClamp = true,
}

-- =============================================================================
-- FOV SYSTEM
-- =============================================================================
Camera.FOV = {
	Base = 70,                  -- Base field of view
	
	-- Velocity-based FOV
	Velocity = {
		Enabled = true,
		MinSpeed = 10,          -- Speed threshold to start FOV increase
		MaxSpeed = 140,         -- Speed at max FOV boost
		
		MinBoost = 0,           -- FOV boost at min speed
		MaxBoost = 45,          -- FOV boost at max speed
	},
	
	-- State-based FOV effects
	Effects = {
		Enabled = true,
		Slide = 5,              -- FOV increase during slide
		Sprint = 3,             -- FOV increase during sprint
	},
	
	-- Smoothing
		LerpAlpha = 0.08,           -- Higher = faster transitions, Lower = smoother
}

-- =============================================================================
-- SCREEN SHAKE
-- =============================================================================
Camera.ScreenShake = {
	Enabled = true,
	WallJump = {
		Intensity = 0.3,
		Duration = 0.2,
		Frequency = 15,
	},
	Land = {
		Enabled = true,
		IntensityMultiplier = 0.01,
		MaxIntensity = 0.5,
		Duration = 0.15,
		Frequency = 20,
	},
}

-- =============================================================================
-- SLIDE CAMERA EFFECTS
-- =============================================================================
Camera.SlideEffects = {
	FOV = 85,
	FOVTweenTime = 0.1,
	CameraDrop = 2,
	CameraDropTime = 0.1,
}

return Camera
