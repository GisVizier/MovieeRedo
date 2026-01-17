--[[
	ViewmodelConfig.lua

	Central configuration for the first-person viewmodel system.
	Controls weapon positioning, procedural effects, animations, and sounds.

	=== HOW TO USE ===
	1. Each weapon needs an entry in ViewmodelConfig.Weapons
	2. Set ModelPath to match your viewmodel folder structure in ReplicatedFirst/ViewModels/
	3. Adjust Offset/ADSOffset for positioning relative to camera
	4. Tune Sway/Bob multipliers per weapon for feel
	5. Add animation IDs and sound IDs

	=== VIEWMODEL HIERARCHY (in ReplicatedFirst/ViewModels/) ===
	WeaponFolder/
	├── Humanoid (will be replaced with AnimationController)
	├── Camera (Part) - Attachment point for camera following
	├── HumanoidRootPart (Part) - Root for animations
	├── LeftArm (MeshPart) - Left arm with ShirtTexture decal
	├── RightArm (MeshPart) - Right arm with ShirtTexture decal
	└── WeaponModel (Model)
	    └── Primary (Part)
	        ├── Aim (Attachment) - ADS alignment point
	        ├── Center (Attachment) - Center of weapon
	        └── Grip (Attachment) - Where hands attach
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ViewmodelConfig = {}

--============================================================================
-- GLOBAL SETTINGS
-- These affect ALL weapons unless overridden per-weapon
--============================================================================
ViewmodelConfig.Global = {
	-- Default camera field of view (degrees)
	-- Higher = wider view, Lower = zoomed in
	DefaultFOV = 70,

	-- ADS (Aim Down Sights) transition speeds
	-- Separate enter/exit speeds for asymmetric feel
	ADS = {
		-- Speed when entering ADS (aiming in)
		EnterSpeed = 12,

		-- Speed when exiting ADS (aiming out)
		ExitSpeed = 15,

		-- Exit ADS when shooting (useful for high recoil weapons)
		-- Can be overridden per-weapon in weapon config
		UnADSOnShoot = false,
	},

	-- How quickly mouse sway responds to input
	-- Higher = more responsive/snappy, Lower = more floaty/delayed
	SwaySmoothing = 1.5,

	-- Delay factor for sway return (creates trailing effect when looking around)
	-- Higher = more delay/trailing, Lower = more responsive
	-- 0 = instant response, 1 = very delayed
	SwayDelay = 0.67,

	-- How quickly walk/run bob responds to movement
	-- Higher = immediate bob changes, Lower = gradual bob transitions
	BobSmoothing = 5,
}

--============================================================================
-- PROCEDURAL EFFECTS
-- These create dynamic movement based on player actions
-- All effects combine together for final viewmodel position
--============================================================================
ViewmodelConfig.Effects = {
	--========================================
	-- MOUSE SWAY
	-- Viewmodel tilts when moving mouse
	--========================================
	Sway = {
		-- How much mouse movement affects sway (0.0 - 1.0)
		-- Higher = more reactive to mouse, Lower = subtle/minimal sway
		MouseSensitivity = 0.15,

		-- Maximum sway angle in degrees
		-- Limits how far viewmodel can tilt from mouse input
		MaxAngle = 45,

		-- Speed at which sway returns to center when mouse stops
		-- Higher = snaps back quickly, Lower = slowly drifts back
		ReturnSpeed = .5,

		-- Additional sway from character velocity (strafing/moving)
		-- Creates "inertia" feel when changing direction
		VelocitySway = 0.02,

		-- Maximum velocity-based sway angle
		MaxVelocitySway = 5,
	},

	--========================================
	-- WALK BOB
	-- Subtle bounce when walking (speed < 20 studs/s)
	--========================================
	WalkBob = {
		-- Position offset amplitude (X = horizontal, Y = vertical, Z = forward/back)
		-- X: Side-to-side sway, Y: Up-down bounce, Z: Forward push (usually 0)
		Amplitude = Vector3.new(0.03, 0.04, 0),

		-- Bob cycles per second (higher = faster stepping)
		-- Should roughly match walk animation speed
		Frequency = 5,

		-- Rotation amplitude in degrees (X = pitch, Y = yaw, Z = roll)
		-- X: Nod up/down, Y: Turn left/right, Z: Tilt side-to-side
		RotationAmplitude = Vector3.new(.5, 1, 1),
	},

	--========================================
	-- RUN BOB
	-- More pronounced bounce when sprinting (speed > 20 studs/s)
	--========================================
	RunBob = {
		-- Larger amplitude than walk for more noticeable movement
		Amplitude = Vector3.new(0.05, 0.1, 0),

		-- Faster frequency to match sprint animation
		Frequency = 8,

		-- More rotation for dramatic sprint feel
		RotationAmplitude = Vector3.new(1, 1.5, 1.5),
	},
	
	--========================================
	-- CROUCH BOB
	-- Minimal bounce when crouched (slow, tactical movement)
	--========================================
	CrouchBob = {
		-- Very subtle for stealth feel
		Amplitude = Vector3.new(0.015, 0.02, 0),

		-- Slow, deliberate pacing
		Frequency = 2.5,

		-- Minimal rotation
		RotationAmplitude = Vector3.new(0.3, 0.2, 0.5),
	},

	--========================================
	-- JUMP OFFSET
	-- Viewmodel reacts to jumping/falling
	--========================================
	JumpBob = {
		-- Offset when jumping upward (rising)
		-- Pushes viewmodel down slightly to simulate upward momentum
		UpOffset = Vector3.new(0, 0.35, 0),

		-- Rotation when jumping (X = pitch back slightly)
		UpRotation = Vector3.new(-10, 0, 0),

		-- Offset when falling (descending)
		-- Pushes viewmodel up slightly
		DownOffset = Vector3.new(0, .5, 0),

		-- Rotation when falling
		DownRotation = Vector3.new(10.5, 0, 0),

		-- How fast the jump offset transitions
		TransitionSpeed = 2.5,

		-- Velocity threshold for "peak" detection (apex of jump)
		-- When vertical velocity is within this range of 0, player is at peak
		-- Set to 0 to disable peak detection (instant transition from jump to fall)
		PeakVelocityThreshold = 2,

		-- How long to hold at peak before transitioning to fall pose (seconds)
		-- Creates a "hang time" effect at the apex of the jump
		-- Set to 0 for instant transition
		PeakHoldTime = 0.3,

		-- Peak offset (neutral position during hang time)
		-- Usually between Up and Down, or just neutral
		PeakOffset = Vector3.new(0, .2, 0),
		PeakRotation = Vector3.new(2, 0, 0),
	},

	--========================================
	-- LAND OFFSET (DISABLED by default)
	-- Impact shake when landing - set to 0 for smooth wobble flow
	-- Enable by setting Enabled = true
	--========================================
	LandBob = {
		-- Set to false to disable land shake entirely
		-- When disabled, the viewmodel flows smoothly back to idle
		Enabled = false,

		-- Position offset on landing impact (only used if Enabled = true)
		Offset = Vector3.new(0, -0.15, 0.05),

		-- Rotation on impact (only used if Enabled = true)
		Rotation = Vector3.new(5, 0, 2),

		-- Duration of the impact effect in seconds
		Duration = 0.2,

		-- Speed of recovery back to normal position
		RecoverySpeed = 10,
	},

	--========================================
	-- SPRINT TUCK
	-- Gun tucks in/down when sprinting
	-- Creates "running with weapon lowered" feel
	--========================================
	SprintTuck = {
		-- Set to false to disable sprint tuck entirely
		Enabled = false,

		-- Position offset when sprinting (X = right, Y = down, Z = back)
		-- Typical: pull weapon down and slightly back
		Offset = Vector3.new(0.05, -0.08, 0.03),

		-- Rotation when sprinting (degrees)
		-- X = pitch down, Y = yaw, Z = roll tilt
		Rotation = Vector3.new(10, 5, 3),

		-- Transition speed into/out of sprint tuck
		TransitionSpeed = 8,
	},

	--========================================
	-- SLIDE TILT
	-- Gun tucks to the side when sliding
	-- EDIT THESE VALUES to adjust slide angle
	--========================================
	SlideTilt = {
		-- Roll angle when sliding (degrees)
		-- Positive = tilt right, Negative = tilt left
		-- Direction is determined by slide direction relative to camera
		Angle = 0,

		-- Position offset when sliding (X = right, Y = down, Z = back)
		-- Creates "tucking gun to side" effect
		Offset = Vector3.new(0.15, -0.12, 0.05),

		-- Additional rotation (X = pitch, Y = yaw, Z = roll)
		-- Use for fine-tuning the slide pose
		Rotation = Vector3.new(8, 10, 0),

		-- How fast the slide tilt transitions
		TransitionSpeed = 10,
	},

	--========================================
	-- TURN SWAY
	-- Viewmodel tilts when turning camera (separate from mouse sway)
	-- Creates rotational inertia effect
	--========================================
	TurnSway = {
		-- How much camera rotation affects tilt
		Sensitivity = 2.5,

		-- Maximum roll angle from turning
		MaxAngle = 15,

		-- Return speed to neutral
		ReturnSpeed = 2,
	},

	--========================================
	-- MOVEMENT TILT
	-- Viewmodel tilts based on movement direction
	-- Creates leaning effect when strafing or moving
	--========================================
	MovementTilt = {
		-- Enable/disable movement tilt
		Enabled = true,

		-- Roll angle when strafing left/right (degrees)
		-- Positive = tilt right when moving right
		StrafeAngle = 25,

		-- Pitch angle when moving forward/backward (degrees)
		-- Positive = tilt down when moving forward
		ForwardAngle = 2.5,

		-- How fast the tilt responds to movement changes
		TransitionSpeed = 3.5,

		-- Reduce tilt when ADS (0-1)
		ADSMultiplier = 0.15,
	},
}

--============================================================================
-- ARM REPLICATION SETTINGS
-- Controls how arms/head are oriented for other players to see
-- Fixes backwards arm/head orientation issues
--============================================================================
ViewmodelConfig.ArmReplication = {
	-- Neck/Head orientation fix
	-- Adjust if head appears backwards on other players' screens
	Neck = {
		-- Rotation offset applied to neck Motor6D (radians)
		-- Adjust X/Y/Z to correct backwards head
		RotationOffset = CFrame.Angles(math.rad(90), math.rad(180), 0),

		-- Maximum pitch angle for looking up/down (radians)
		MaxPitch = math.rad(75),
		MinPitch = math.rad(-85),
	},

	-- Right arm orientation fix
	RightShoulder = {
		-- Base rotation offset (fix backwards arm)
		-- Default R6 right shoulder points out, so we add 90 degrees
		RotationOffset = CFrame.Angles(0, math.rad(90), math.rad(0)),

		-- How much arm follows head pitch (0.0 - 1.0)
		PitchFollow = -1,

		-- Max pitch for arm movement
		MaxPitch = math.rad(75),
		MinPitch = math.rad(-85),
	},

	-- Left arm orientation fix
	LeftShoulder = {
		-- Base rotation offset (fix backwards arm)
		-- Default R6 right shoulder points out, so we add 90 degrees
		RotationOffset = CFrame.Angles(0, math.rad(-90), math.rad(-0)),

		-- How much arm follows head pitch (0.0 - 1.0)
		PitchFollow = -1,

		-- Max pitch for arm movement
		MaxPitch = math.rad(75),
		MinPitch = math.rad(-85),
	},
}

--============================================================================
-- IDLE ACTIONS SETTINGS
-- Global settings for the idle actions system
-- Per-weapon idle actions are defined in each weapon's Animations.IdleActions
--============================================================================
ViewmodelConfig.IdleActions = {
	-- Minimum time between idle action attempts (seconds)
	MinInterval = 5,

	-- Maximum time between idle action attempts (seconds)
	MaxInterval = 15,

	-- Chance to play idle action when interval is reached (0.0 - 1.0)
	Chance = 0.3,

	-- Reset timer when player moves (walk/run)
	-- If true, idle actions only play when player has been standing still
	ResetOnMovement = true,
}

--============================================================================
-- VIEWMODEL HIGHLIGHT SETTINGS
-- Highlight applied to viewmodel for visibility
--============================================================================
ViewmodelConfig.Highlight = {
    Enabled = true,
    FillColor = Color3.fromRGB(255, 255, 255),
    FillTransparency = 0.99,
    OutlineColor = Color3.fromRGB(0, 0, 0),
    OutlineTransparency = 0.95,
    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
}

--============================================================================
-- AIR MOVEMENT ANIMATION SETTINGS
-- Settings for running animation while airborne
--============================================================================
ViewmodelConfig.AirMovement = {
	-- Allow running animation to play while in the air
	AllowAirRunning = true,

	-- Animation speed when airborne (slower for floaty feel)
	AirAnimationSpeed = 0.45,

	-- Normal grounded animation speed
	GroundedAnimationSpeed = 1.0,
}

--============================================================================
-- DEFAULT CHARACTER ANIMATIONS
-- Animations for 3rd-person rig (falls back if weapon has no CharacterAnimations)
--============================================================================
ViewmodelConfig.DefaultCharacterAnimations = {
	Idle = "rbxassetid://0",
	Walk = "rbxassetid://0",
	Run = "rbxassetid://0",
	Crouch = "rbxassetid://0",
	CrouchWalk = "rbxassetid://0",
	Jump = "rbxassetid://0",
	Fall = "rbxassetid://0",
}

--============================================================================
-- WEAPON DEFINITIONS
-- Individual settings for each weapon type
-- Per-weapon settings override global Effects values
--============================================================================
ViewmodelConfig.Weapons = {
	--========================================
	-- FIST (DEFAULT VIEWMODEL)
	--========================================
	Fist = {
		ModelPath = "Fist/Fist_Default",
		Weight = 1.0,
		CanFireDuringEquip = true,
		Offset = CFrame.new(0, 0, 0),
		ADSOffset = CFrame.new(0, 0, 0),
		ADSFOV = 70,

		ADS = {
			EnterSpeed = 12,
			ExitSpeed = 15,
			UnADSOnShoot = false,
		},

		Sway = {
			Multiplier = 1.0,
			ADSMultiplier = 0.5,
		},

		Bob = {
			WalkMultiplier = 1.0,
			RunMultiplier = 1.0,
			ADSMultiplier = 0.5,
		},

		Effects = {},

		Animations = {
			Idle = "rbxassetid://0",
			Walk = "rbxassetid://0",
			Run = "rbxassetid://0",
			ADS = "rbxassetid://0",
			Fire = "rbxassetid://0",
			Reload = "rbxassetid://0",
			Equip = "rbxassetid://0",
		},

		Sounds = {},
	},

	--========================================
	-- SHOTGUN
	--========================================
	Shotgun = {
		-- Path to viewmodel in ReplicatedFirst/ViewModels/
		-- Format: "FolderName/ModelName"
		ModelPath = "Shotguns/Shotgun_Default",

		-- Weight affects character movement speed (0.0 - 1.0)
		-- Lower = heavier weapon = slower movement
		-- 0.9 = 90% of normal movement speed
		Weight = 0.9,

		-- Can the player fire while equip animation is playing?
		-- true = cancel equip by shooting, false = must wait for equip to finish
		CanFireDuringEquip = true,

		-- Hip-fire position offset from camera
		-- CFrame.new(X, Y, Z) where:
		-- X = right (+) / left (-)
		-- Y = up (+) / down (-)
		-- Z = back (+) / forward (-)
		Offset = CFrame.new(0, 0, 0.5),

		-- ADS position offset (usually centered)
		ADSOffset = CFrame.new(0, 0, 0),

		-- Field of view when aiming down sights
		ADSFOV = 55,

		-- ADS settings (per-weapon, falls back to Global.ADS)
		ADS = {
			EnterSpeed = 12,    -- Speed when aiming in
			ExitSpeed = 15,     -- Speed when aiming out
			UnADSOnShoot = false, -- Exit ADS when shooting (for high recoil weapons)
		},

		-- Sway multipliers (multiply global Sway values)
		Sway = {
			-- Hip-fire sway amount (1.0 = normal, 2.0 = double)
			Multiplier = 1.0,

			-- ADS sway reduction (0.3 = 30% of hip-fire sway)
			ADSMultiplier = 0.3,

			-- Per-weapon sway delay (falls back to Global.SwayDelay)
			-- Delay = 0.3,
		},

		-- Bob multipliers (multiply global Bob values)
		Bob = {
			-- Walking bob intensity
			WalkMultiplier = 1.0,

			-- Running bob intensity
			RunMultiplier = 1.2,

			-- ADS bob reduction (minimal for steadier aim)
			ADSMultiplier = 0.2,
		},

		-- Per-weapon effect overrides (optional, falls back to global Effects)
		-- Uncomment and adjust to customize this weapon's effects
		Effects = {
			-- SlideTilt = {
			--     Angle = 12,
			--     Offset = Vector3.new(0.12, -0.1, 0.04),
			--     Rotation = Vector3.new(6, 8, 0),
			--     TransitionSpeed = 10,
			-- },
			-- SprintTuck = {
			--     Enabled = true,
			--     Offset = Vector3.new(0.05, -0.08, 0.03),
			--     Rotation = Vector3.new(10, 5, 3),
			--     TransitionSpeed = 8,
			-- },
		},

		-- Animation IDs for this weapon's viewmodel
		-- Replace "rbxassetid://0" with actual animation IDs
		Animations = {
			-- Looping animations (play continuously)
			Idle = "rbxassetid://105684508981313",    -- Standing still
			Walk = "rbxassetid://105684508981313",    -- Walking (speed < 20)
			Run = "rbxassetid://107238400783744",     -- Sprinting (speed > 20)

			-- Action animations (play once)
			ADS = "rbxassetid://105684508981313",     -- Aim down sights pose
			Fire = "rbxassetid://103738677784397",    -- Shooting
			Reload = "rbxassetid://0",  -- Reloading magazine
			Equip = "rbxassetid://0",   -- Drawing weapon
			Inspect = "rbxassetid://90823849535495", -- Inspecting weapon (optional)

			-- Idle actions (random animations during idle)
			-- These play randomly while in Idle state
			IdleActions = {
				{ Name = "Fidget", AnimationId = "rbxassetid://105684508981313", Weight = .67 },
				--{ Name = "CheckAmmo", AnimationId = "rbxassetid://105684508981313", Weight = 0.5 },
				{ Name = "LookAround", AnimationId = "rbxassetid://129184527759903", Weight = 0.8 },
			},
		},

		-- Sound IDs for weapon actions
		Sounds = {
			Equip = "rbxassetid://0",
			Fire = "rbxassetid://0",
			Reload = "rbxassetid://0",
			ADSIn = "rbxassetid://0",   -- Sound when entering ADS
			ADSOut = "rbxassetid://0",  -- Sound when exiting ADS
		},

		-- 3rd-person character animations (plays on R6 rig in workspace/Rigs)
		-- These are separate from viewmodel animations and visible to other players
		CharacterAnimations = {
			Idle = "rbxassetid://78361474116976",
			Walk = "rbxassetid://78361474116976",
			Run = "rbxassetid://78361474116976",
			Fire = "rbxassetid://78361474116976",
			Reload = "rbxassetid://783614741169760",
		},
	},

	--========================================
	-- REVOLVER
	--========================================
	Revolver = {
		ModelPath = "Revolver/Revolver_Default",
		Weight = 0.95,  -- Light weapon, minimal speed penalty
		CanFireDuringEquip = true,

		Offset = CFrame.new(0, 0, 0.4),
		ADSOffset = CFrame.new(0, 0, 0),
		ADSFOV = 60,

		ADS = {
			EnterSpeed = 14,    -- Faster for light weapon
			ExitSpeed = 16,
		},

		Sway = {
			Multiplier = 1.2,      -- More sway (lighter = more movement)
			ADSMultiplier = 0.4,
		},

		Bob = {
			WalkMultiplier = 0.8,  -- Less bob (lighter weapon)
			RunMultiplier = 1.0,
			ADSMultiplier = 0.15,
		},

		Effects = {},  -- Uses global effects

		Animations = {
			Idle = "rbxassetid://109130838280246",
			Walk = "rbxassetid://109130838280246",
			Run = "rbxassetid://70374674712630",
			ADS = "rbxassetid://109130838280246",
			Fire = "rbxassetid://116676760515163",
			Reload = "rbxassetid://128494876463082",
			Equip = "rbxassetid://0",
			Inspect = "rbxassetid://129139579437341",

			IdleActions = {
				{ Name = "SpinCylinder", AnimationId = "rbxassetid://0", Weight = 1.0 },
				{ Name = "Fidget", AnimationId = "rbxassetid://0", Weight = 0.7 },
			},
		},

		Sounds = {
			Equip = "rbxassetid://0",
			Fire = "rbxassetid://0",
			Reload = "rbxassetid://0",
			ADSIn = "rbxassetid://0",
			ADSOut = "rbxassetid://0",
		},
	},

	--========================================
	-- ASSAULT RIFLE
	--========================================
	AssaultRifle = {
		ModelPath = "Rifles/AssaultRifle_Default",
		Weight = 0.85,  -- Medium-heavy, moderate speed penalty
		CanFireDuringEquip = true,

		Offset = CFrame.new(0, 0, 0.5),
		ADSOffset = CFrame.new(0, 0, 0),
		ADSFOV = 50,  -- More zoom than pistol

		ADS = {
			EnterSpeed = 11,
			ExitSpeed = 14,
		},

		Sway = {
			Multiplier = 0.9,      -- Less sway (steadier grip)
			ADSMultiplier = 0.25,  -- Very stable when ADS
		},

		Bob = {
			WalkMultiplier = 0.9,
			RunMultiplier = 1.1,
			ADSMultiplier = 0.1,   -- Minimal bob when aiming
		},

		Effects = {},  -- Uses global effects

		Animations = {
			Idle = "rbxassetid://0",
			Walk = "rbxassetid://0",
			Run = "rbxassetid://0",
			ADS = "rbxassetid://0",
			Fire = "rbxassetid://0",
			Reload = "rbxassetid://0",
			Equip = "rbxassetid://0",
			Inspect = "rbxassetid://0",

			IdleActions = {
				{ Name = "CheckMag", AnimationId = "rbxassetid://0", Weight = 1.0 },
				{ Name = "Fidget", AnimationId = "rbxassetid://0", Weight = 0.8 },
			},
		},

		Sounds = {
			Equip = "rbxassetid://0",
			Fire = "rbxassetid://0",
			Reload = "rbxassetid://0",
			ADSIn = "rbxassetid://0",
			ADSOut = "rbxassetid://0",
		},
	},

	--========================================
	-- SNIPER RIFLE
	--========================================
	SniperRifle = {
		ModelPath = "Snipers/SniperRifle_Default",
		Weight = 0.75,  -- Heavy, significant speed penalty
		CanFireDuringEquip = false,  -- Must wait for equip animation

		Offset = CFrame.new(0, 0, 0.6),
		ADSOffset = CFrame.new(0, 0, 0),
		ADSFOV = 30,  -- High zoom for precision

		ADS = {
			EnterSpeed = 8,    -- Slower for heavy weapon
			ExitSpeed = 12,
		},

		Sway = {
			Multiplier = 0.7,      -- Less hip sway (heavy = stable)
			ADSMultiplier = 0.5,   -- Some scope sway for balance
		},

		Bob = {
			WalkMultiplier = 0.7,  -- Minimal bob (heavy)
			RunMultiplier = 0.9,
			ADSMultiplier = 0.05,  -- Almost no bob when scoped
		},

		Effects = {},  -- Uses global effects

		Animations = {
			Idle = "rbxassetid://0",
			Walk = "rbxassetid://0",
			Run = "rbxassetid://0",
			ADS = "rbxassetid://0",
			Fire = "rbxassetid://0",
			Reload = "rbxassetid://0",
			Equip = "rbxassetid://0",
			Inspect = "rbxassetid://0",

			IdleActions = {
				{ Name = "ScopeCheck", AnimationId = "rbxassetid://0", Weight = 1.0 },
				{ Name = "Fidget", AnimationId = "rbxassetid://0", Weight = 0.6 },
			},
		},

		Sounds = {
			Equip = "rbxassetid://0",
			Fire = "rbxassetid://0",
			Reload = "rbxassetid://0",
			ADSIn = "rbxassetid://0",
			ADSOut = "rbxassetid://0",
		},
	},

	--========================================
	-- KNIFE (Melee)
	--========================================
	Knife = {
		ModelPath = "Melee/Knife_Default",
		Weight = 1.0,  -- No speed penalty
		CanFireDuringEquip = true,

		-- Offset to the side for melee stance
		Offset = CFrame.new(0.2, -0.1, 0.3),
		ADSOffset = CFrame.new(0, 0, 0),
		ADSFOV = 70,  -- No zoom

		ADS = {
			EnterSpeed = 15,
			ExitSpeed = 15,
		},

		Sway = {
			Multiplier = 1.5,      -- More sway (light, loose grip)
			ADSMultiplier = 1.0,   -- No ADS reduction for melee
		},

		Bob = {
			WalkMultiplier = 1.2,  -- More bounce (running animation)
			RunMultiplier = 1.5,   -- Exaggerated sprint bob
			ADSMultiplier = 1.0,
		},

		-- Disable sprint tuck for melee
		Effects = {
			SprintTuck = {
				Enabled = false,
			},
		},

		-- Melee uses Attack instead of Fire
		Animations = {
			Idle = "rbxassetid://0",
			Walk = "rbxassetid://0",
			Run = "rbxassetid://0",
			Attack = "rbxassetid://0",  -- Swing/stab animation
			Equip = "rbxassetid://0",
			Inspect = "rbxassetid://0",

			IdleActions = {
				{ Name = "FlipKnife", AnimationId = "rbxassetid://0", Weight = 1.0 },
				{ Name = "Fidget", AnimationId = "rbxassetid://0", Weight = 0.5 },
			},
		},

		Sounds = {
			Equip = "rbxassetid://0",
			Attack = "rbxassetid://0",  -- Swing sound
			Hit = "rbxassetid://0",     -- Hit confirmation sound
		},
	},
}

--============================================================================
-- SKIN OVERRIDES
-- Skins can override any property from the base weapon config
-- Only specify properties that change - rest inherited from base
--============================================================================
ViewmodelConfig.Skins = {
	Shotgun = {
		Golden = {
			-- Different model for golden skin
			ModelPath = "Shotguns/Shotgun_Golden",

			-- Can override specific animations
			Animations = {
				Fire = "rbxassetid://0",  -- Unique fire animation
			},
		},
	},
	-- Add more weapon skins here:
	-- Revolver = { Legendary = { ModelPath = "...", }, },
}

--============================================================================
-- LOGGING SETTINGS
-- Enable/disable debug logging for viewmodel system
--============================================================================
ViewmodelConfig.Debug = {
	-- Log when viewmodel is created/destroyed
	LogLifecycle = false,

	-- Log animation state changes
	LogAnimations = false,

	-- Log effect calculations (very verbose)
	LogEffects = false,

	-- Log config resolution (base + skin merging)
	LogConfigResolution = false,

	-- Log arm replication updates
	LogArmReplication = false,

	-- Log idle action selections
	LogIdleActions = false,
}

--============================================================================
-- UTILITY FUNCTIONS
--============================================================================

-- Get logging service for debug output
local function getLog()
	local success, Locations = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Modules", 1).Locations)
	end)
	if success and Locations then
		local logSuccess, Log = pcall(function()
			return require(Locations.Modules.Systems.Core.LogService)
		end)
		if logSuccess then
			return Log
		end
	end
	return nil
end

-- Debug log helper
local function debugLog(category, message, data)
	if not ViewmodelConfig.Debug["Log" .. category] then
		return
	end

	local Log = getLog()
	if Log then
		Log:Debug("VIEWMODEL_CONFIG", message, data)
	else
		print("[VIEWMODEL_CONFIG]", message, data and game:GetService("HttpService"):JSONEncode(data) or "")
	end
end

--[[
	Get base weapon configuration
	@param weaponName string - Name of weapon (e.g., "Shotgun")
	@return table|nil - Weapon config or nil if not found
]]
function ViewmodelConfig:GetWeaponConfig(weaponName)
	local config = self.Weapons[weaponName]
	debugLog("ConfigResolution", "GetWeaponConfig", { Weapon = weaponName, Found = config ~= nil })
	return config
end

--[[
	Get skin-specific overrides for a weapon
	@param weaponName string - Name of weapon
	@param skinName string - Name of skin (or nil/"Default" for base)
	@return table|nil - Skin overrides or nil
]]
function ViewmodelConfig:GetSkinConfig(weaponName, skinName)
	if not skinName or skinName == "Default" then
		return nil
	end

	local weaponSkins = self.Skins[weaponName]
	if weaponSkins then
		local skinConfig = weaponSkins[skinName]
		debugLog("ConfigResolution", "GetSkinConfig", {
			Weapon = weaponName,
			Skin = skinName,
			Found = skinConfig ~= nil
		})
		return skinConfig
	end

	return nil
end

--[[
	Get fully resolved config with skin overrides applied
	@param weaponName string - Name of weapon
	@param skinName string|nil - Name of skin (optional)
	@return table|nil - Merged config or nil
]]
function ViewmodelConfig:GetResolvedConfig(weaponName, skinName)
	local baseConfig = self:GetWeaponConfig(weaponName)
	if not baseConfig then
		debugLog("ConfigResolution", "Base config not found", { Weapon = weaponName })
		return nil
	end

	local skinConfig = self:GetSkinConfig(weaponName, skinName)
	if not skinConfig then
		debugLog("ConfigResolution", "Using base config (no skin)", { Weapon = weaponName })
		return baseConfig
	end

	-- Deep merge skin overrides onto base config
	local resolved = {}
	for key, value in pairs(baseConfig) do
		resolved[key] = value
	end

	for key, value in pairs(skinConfig) do
		if type(value) == "table" and type(resolved[key]) == "table" then
			resolved[key] = {}
			for subKey, subValue in pairs(baseConfig[key]) do
				resolved[key][subKey] = subValue
			end
			for subKey, subValue in pairs(value) do
				resolved[key][subKey] = subValue
			end
		else
			resolved[key] = value
		end
	end

	debugLog("ConfigResolution", "Resolved config with skin", {
		Weapon = weaponName,
		Skin = skinName
	})

	return resolved
end

--[[
	Get model path for weapon/skin combination
	@param weaponName string
	@param skinName string|nil
	@return string|nil - Model path or nil
]]
function ViewmodelConfig:GetModelPath(weaponName, skinName)
	local config = self:GetResolvedConfig(weaponName, skinName)
	if config then
		return config.ModelPath
	end
	return nil
end

--[[
	Get weapon weight (movement speed multiplier)
	@param weaponName string
	@return number - Weight value (0.0 - 1.0)
]]
function ViewmodelConfig:GetWeight(weaponName)
	local config = self:GetWeaponConfig(weaponName)
	if config then
		return config.Weight or 1.0
	end
	return 1.0
end

--[[
	Get idle actions for a weapon (from Animations.IdleActions)
	@param weaponName string
	@return table - Array of idle action definitions
]]
function ViewmodelConfig:GetIdleActions(weaponName)
	local config = self:GetWeaponConfig(weaponName)
	if config and config.Animations and config.Animations.IdleActions then
		return config.Animations.IdleActions
	end
	return {}
end

--[[
	Pick a random idle action based on weights
	@param weaponName string
	@return table|nil - Selected idle action or nil
]]
function ViewmodelConfig:PickRandomIdleAction(weaponName)
	local actions = self:GetIdleActions(weaponName)
	if #actions == 0 then
		return nil
	end

	-- Calculate total weight
	local totalWeight = 0
	for _, action in ipairs(actions) do
		totalWeight = totalWeight + (action.Weight or 1.0)
	end

	-- Pick random based on weight
	local random = math.random() * totalWeight
	local cumulative = 0

	for _, action in ipairs(actions) do
		cumulative = cumulative + (action.Weight or 1.0)
		if random <= cumulative then
			debugLog("IdleActions", "Selected idle action", {
				Weapon = weaponName,
				Action = action.Name
			})
			return action
		end
	end

	return actions[1]
end

--[[
	Get effect value with weapon override -> global fallback
	@param weaponConfig table - Resolved weapon config
	@param effectName string - Name of effect (e.g., "SlideTilt", "SprintTuck")
	@param property string - Property name within the effect
	@return any - The effect value (weapon override or global fallback)
]]
function ViewmodelConfig:GetEffectValue(weaponConfig, effectName, property)
	-- Check weapon-specific override first
	if weaponConfig and weaponConfig.Effects and weaponConfig.Effects[effectName] then
		local weaponEffect = weaponConfig.Effects[effectName]
		if weaponEffect[property] ~= nil then
			return weaponEffect[property]
		end
	end

	-- Fall back to global effect
	local globalEffect = self.Effects[effectName]
	if globalEffect and globalEffect[property] ~= nil then
		return globalEffect[property]
	end

	return nil
end

--[[
	Get full effect config with weapon overrides merged onto global
	@param weaponConfig table - Resolved weapon config
	@param effectName string - Name of effect (e.g., "SlideTilt", "SprintTuck")
	@return table - Merged effect config
]]
function ViewmodelConfig:GetMergedEffect(weaponConfig, effectName)
	local globalEffect = self.Effects[effectName]
	if not globalEffect then
		return {}
	end

	-- Start with a copy of global effect
	local merged = table.clone(globalEffect)

	-- Override with weapon-specific values
	if weaponConfig and weaponConfig.Effects and weaponConfig.Effects[effectName] then
		for key, value in pairs(weaponConfig.Effects[effectName]) do
			merged[key] = value
		end
	end

	return merged
end

--[[
	Get ADS speed (enter or exit) with weapon override -> global fallback
	@param weaponConfig table - Resolved weapon config
	@param entering boolean - true for enter speed, false for exit speed
	@return number - ADS transition speed
]]
function ViewmodelConfig:GetADSSpeed(weaponConfig, entering)
	local property = entering and "EnterSpeed" or "ExitSpeed"

	-- Check weapon-specific ADS settings first
	if weaponConfig and weaponConfig.ADS and weaponConfig.ADS[property] then
		return weaponConfig.ADS[property]
	end

	-- Fall back to global ADS settings
	if self.Global.ADS and self.Global.ADS[property] then
		return self.Global.ADS[property]
	end

	-- Ultimate fallback
	return 12
end

--[[
	Get sway delay with weapon override -> global fallback
	@param weaponConfig table - Resolved weapon config
	@return number - Sway delay factor
]]
function ViewmodelConfig:GetSwayDelay(weaponConfig)
	-- Check weapon-specific sway delay first
	if weaponConfig and weaponConfig.Sway and weaponConfig.Sway.Delay then
		return weaponConfig.Sway.Delay
	end

	-- Fall back to global
	return self.Global.SwayDelay or 0.3
end

--[[
	Get UnADSOnShoot setting with weapon override -> global fallback
	@param weaponConfig table - Resolved weapon config
	@return boolean - Whether to exit ADS when shooting
]]
function ViewmodelConfig:GetUnADSOnShoot(weaponConfig)
	-- Check weapon-specific ADS settings first
	if weaponConfig and weaponConfig.ADS and weaponConfig.ADS.UnADSOnShoot ~= nil then
		return weaponConfig.ADS.UnADSOnShoot
	end

	-- Fall back to global ADS settings
	if self.Global.ADS and self.Global.ADS.UnADSOnShoot ~= nil then
		return self.Global.ADS.UnADSOnShoot
	end

	-- Default to false
	return false
end

--[[
	Get character animation ID for a weapon
	Gets from weapon's CharacterAnimations, falls back to DefaultCharacterAnimations
	@param weaponName string - Name of weapon
	@param animationName string - Name of animation (Idle, Walk, Fire, etc.)
	@return string - Animation ID or nil
]]
function ViewmodelConfig:GetCharacterAnimation(weaponName, animationName)
	-- Try weapon-specific CharacterAnimations first
	local weaponConfig = self:GetWeaponConfig(weaponName)
	if weaponConfig and weaponConfig.CharacterAnimations then
		local animId = weaponConfig.CharacterAnimations[animationName]
		if animId and animId ~= "rbxassetid://0" then
			return animId
		end
	end

	-- Fall back to default character animations
	local defaultAnims = self.DefaultCharacterAnimations
	if defaultAnims and defaultAnims[animationName] and defaultAnims[animationName] ~= "rbxassetid://0" then
		return defaultAnims[animationName]
	end

	return nil
end

--[[
	Get all character animations for a weapon (merged with defaults)
	@param weaponName string - Name of weapon
	@return table - Merged animation table
]]
function ViewmodelConfig:GetCharacterAnimations(weaponName)
	local merged = {}

	-- Start with defaults
	local defaultAnims = self.DefaultCharacterAnimations
	if defaultAnims then
		for animName, animId in pairs(defaultAnims) do
			merged[animName] = animId
		end
	end

	-- Override with weapon-specific CharacterAnimations
	local weaponConfig = self:GetWeaponConfig(weaponName)
	if weaponConfig and weaponConfig.CharacterAnimations then
		for animName, animId in pairs(weaponConfig.CharacterAnimations) do
			merged[animName] = animId
		end
	end

	return merged
end

return ViewmodelConfig
