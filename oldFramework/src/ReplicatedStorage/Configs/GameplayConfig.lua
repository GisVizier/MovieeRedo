local GameplayConfig = {}

-- ============================================================================
-- COOLDOWNS
-- ============================================================================
GameplayConfig.Cooldowns = {
	Crouch = 0.1,  -- Delay between crouch toggles
	Jump = 0.12,   -- Delay between jumps
	Slide = 0.55,  -- Delay between slides

	WorldGravity = 196.2, -- Roblox default gravity (studs/s²)
}

-- ============================================================================
-- CHARACTER MOVEMENT & PHYSICS
-- ============================================================================
GameplayConfig.Character = {

	-- Basic movement speeds
	SprintSpeed = 26,  -- Sprint speed
	WalkSpeed = 20,    -- Base walk speed
	JumpPower = 35,    -- Jump power

	-- Sprint settings
	AutoSprint = false, -- Auto sprinting disabled

	-- Coyote time (late jumps allowed after stepping off ledge)
	CoyoteTime = 0.12,

	-- Wall jump settings (Rivals-style: quick tap, instant response, limited charges)
	WallJump = {
		Enabled = true,             -- Enable/disable wall jumping
		VerticalBoost = 37.74,         -- RIVALS: Strong upward boost for chaining
		HorizontalBoost = 25,       -- RIVALS: Camera direction boost (reduced)
		WallPushForce = 35,         -- INCREASED: Strong push away from wall
		AnglePushMultiplier = 1.5,  -- NEW: Controls reflection angle (higher = more angle-based push)

		WallDetectionDistance = 3.0, -- RIVALS: Quick detection (3 studs = instant response)
		MinWallAngle = 30,           -- Lower threshold for easier wall detection
		RequireAirborne = true,      -- RIVALS: Must be airborne to wall jump
		RequireSprinting = false,    -- RIVALS: No sprint requirement (quick tap)
		ExcludeDuringSlide = true,   -- Prevent wall jump while sliding
		MaxCharges = 3,              -- INCREASED: 3 charges for more wall jump chains
		CooldownBetweenJumps = 0.3, -- RIVALS: Brief cooldown to prevent spam (0.15s)
	},

	Jump = {
		WallRaycast = {
			Enabled = true,
			RayDistance = 2.5,
			MinWallAngle = 75,
		},

		CrouchCancel = {
			Enabled = true,
			VelocityCancelMultiplier = 0.1,
			MinAirborneTime = 0.1,
			DownforceOnCancel = 80,
		},
	},

	-- Movement physics (Rivals-style: snappy ground, reduced air control)
	MovementForce = 500,          -- HIGH for instant acceleration
	FrictionMultiplier = 0.95,    -- HIGH friction for snappy stops
	AirControlMultiplier = 0.18,  -- VERY REDUCED: Much harder to switch directions airborne
	
	AirResistance = 25.12,         -- SIGNIFICANTLY INCREASED: Very hard to change direction in air
	AirborneSlideDownforce = 600, -- VERY STRONG: Rivals-style heavy pull-down when airborne sliding

	-- Fall speed control (GENTLE falling - gradual descent)
	FallSpeed = {
		Enabled = true,           -- ENABLED for controlled falling
		MaxFallSpeed = 150,       -- REDUCED: Lower terminal velocity for softer landing
		DragMultiplier = 0.15,    -- More drag near terminal velocity
		AscentDrag = 0.01,        -- Very light drag during ascent
		FallAcceleration = 40,    -- GENTLE: Soft downward acceleration (was 120)
		AscentGravityReduction = 0.50, -- 50% gravity reduction during ascent (more floaty rise)

		HangTimeThreshold = 8,    -- INCREASED: More hang time at peak
		HangTimeDrag = 0.05,      -- More hang at peak
	},

	-- Fall dampening (DISABLED - use standard gravity)
	FallDampening = {
		Enabled = false,         -- DISABLED for standard gravity feel
		Multiplier = 1.0,
		MaxFallSpeed = 60,
		MinHeightToApply = 999,
	},

	-- Gravity damping (Rivals-style BOUNCY - 60% gravity reduction when falling)
	GravityDamping = {
		Enabled = true,
		DampingFactor = 0.60,        -- Counteract 60% of gravity when FALLING (very bouncy)
		MaxFallSpeed = 200,          -- HIGH: Allow fast falling during airborne slides
		ApplyOnlyWhenFalling = true,
	},

	-- Float Decay (longer in air = faster fall, VELOCITY-BASED threshold)
	FloatDecay = {
		Enabled = true,
		FloatDuration = 0.8,         -- INCREASED: More float time before decay
		DecayRate = 0.08,            -- REDUCED: Slower gravity ramp-up (was 0.15)
		MinDampingFactor = 0.20,     -- Higher minimum = softer max fall (was 0.10)
		MomentumFactor = 0.010,      -- REDUCED: Less momentum impact
		VelocityThreshold = 0.6,     -- Higher minimum float
		ThresholdShrinkRate = 0.003, -- REDUCED: Speed affects float less
	},

	-- Landing Momentum Preservation (Rivals-style bouncy landings)
	LandingMomentum = {
		Enabled = true,
		PreservationMultiplier = 0.8, -- Keep 80% of landing velocity
		MinPreservationSpeed = 15,    -- Only preserve if landing faster than this
		DecayRate = 0.92,             -- Gradual deceleration per frame
	},

	-- Vaulting (push over head-height obstacles) - DISABLED pending rework
	Vaulting = {
		Enabled = false,
		DetectionHeight = 4.0,       -- Head-height for obstacle detection
		DetectionDistance = 2.0,     -- Forward raycast distance
		VaultForce = 50,             -- Upward force to push over
		ForwardBoost = 20,           -- Forward momentum during vault
		MinMoveSpeed = 5,            -- Minimum horizontal speed to trigger vault
	},

	-- Slope Magnet (snap to ground when about to launch off ramp)
	SlopeMagnet = {
		Enabled = true,
		RayLength = 3.0,             -- Shorter ray - only catch when close to ground
		SnapVelocity = -80,          -- Moderate pull (not too aggressive)
		JumpCooldown = 0.25,         -- Seconds after jump before magnet activates
		MinAirborneHeight = 0.5,     -- Only trigger when slightly above ground
	},

	-- Wall stop (complete stop when hitting walls) - replaces wall glancing
	WallStop = {
		Enabled = true,
		RayDistance = 1.5,       -- Raycast length in velocity direction
		MinWallAngle = 70,       -- Min angle to consider as wall (vs slope)
	},

	-- Wall glancing (anti-stick) - DISABLED, replaced by WallStop
	WallGlancing = {
		Enabled = false,
		RayDistance = 1.5,
		DeflectionStrength = 1.0,
	},

	-- Sticky ground system (keeps player attached to surface when moving)
	StickyGround = {
		Enabled = true,
		RayDistance = 8.0,       -- Ray distance to check for ground (long range)
		StickForce = 180,        -- Base downward velocity (moderate)
		MinSpeed = 5,            -- Minimum horizontal speed to activate
		MaxSpeed = 40,           -- MAX speed threshold - don't stick if moving faster than this
		JumpBreakTime = 0.15,    -- Seconds after jump before sticky reactivates
		SpeedMultiplier = 1.5,   -- Scale force by speed (reduced to prevent going too fast)
		MaxSpeedBonus = 80,      -- Max bonus force (reduced)
		-- HYBRID: Clamp Y position to not exceed ground + this height
		MaxHeightAboveGround = 3.0, -- Max studs above detected ground
		EnableYClamp = false,    -- DISABLED: Don't teleport
	},

	-- Ground detection raycast
	GroundRayOffset = 0.25,
	GroundRayDistance = 0.6,

	-- Max walkable slope degrees
	MaxWalkableSlopeAngle = 48,

	-- Standing friction
	StandingFriction = {
		IdleFriction = 0.65,     -- Ground friction when idle
		MinSlopeAngle = 1,       -- Min slope to apply slope friction
		SlopeFriction = 1.1,     -- Friction applied when standing on slope
	},

	-- Crouching stats
	CrouchHeightReduction = 2,
	CrouchSpeed = 8,
	CrouchSpeedReduction = 0.5, -- Speed multiplier when crouching (0.5 = 50% speed)

	-- Directional animations (camera relative)
	DirectionalAnimations = {
		ForwardAngle = 60,
		LateralStartAngle = 60,
		LateralEndAngle = 120,
		BackwardStartAngle = 120,
		BackwardEndAngle = 240,
	},

	-- VC / bubble chat head alignment
	HeadOffset = Vector3.new(0, 2, 0),

	-- First-person part hiding
	HideFromLocalPlayer = true,
	PartsToHide = { "Body", "Feet", "Head", "Root", "CrouchBody", "CrouchHead" },
	ShowRigForTesting = false,

	-- Physical property overrides applied to character rig
	CustomPhysicalProperties = {
		Density = 0.7,
		Elasticity = 0,
		ElasticityWeight = 100,
		Friction = 0,
		FrictionWeight = 100,
	},

	-- Kill floor Y threshold
	DeathYThreshold = -100,

	-- Rig tilt and rotation for slopes
	RigRotation = {
		Enabled = true,
		MaxTiltAngle = 55, -- Max tilt degrees on slopes
		Smoothness = 38,   -- Lerp smoothing strength
		MinSlopeForRotation = 3,

		Airborne = {
			Enabled = true,
			MaxTiltAngle = 18,
			MinVerticalVelocity = 6, -- Min velocity before tilting
			Smoothness = 10,
		},
	},

	-- Ragdoll system (visual R6 rig physics)
	Ragdoll = {
		-- Physics properties
		Physics = {
			Density = 0.7, -- Limb physics density
			Friction = 0.5, -- Surface friction for ragdoll parts
			Elasticity = 0, -- Bounciness (0 = no bounce)
			HeadDensity = 0.7, -- Head uses lighter physics for more natural movement
			HeadFriction = 0.3, -- Lower friction for head to reduce stiffness
		},

		-- Joint angle limits (in degrees)
		JointLimits = {
			Neck = {
				UpperAngle = 45, -- Max cone angle for head rotation
				TwistLowerAngle = -60, -- Left/right twist limits
				TwistUpperAngle = 60,
				MaxFrictionTorque = 10, -- Resistance to rotation (higher = stiffer neck)
			},
			Shoulder = {
				UpperAngle = 90,
				TwistLowerAngle = -75,
				TwistUpperAngle = 75,
				MaxFrictionTorque = 5,
			},
			Hip = {
				UpperAngle = 90,
				TwistLowerAngle = -45,
				TwistUpperAngle = 45,
				MaxFrictionTorque = 5,
			},
			RootJoint = {
				UpperAngle = 30,
				TwistLowerAngle = -45,
				TwistUpperAngle = 45,
				MaxFrictionTorque = 15, -- Stiffer spine
			},
		},

		-- Automatic ragdoll triggers
		AutoRagdoll = {
			OnDeath = true, -- Ragdoll on death
			OnExplosion = false, -- Ragdoll when hit by explosions
			OnHighVelocity = false, -- Ragdoll when hit with high force
			VelocityThreshold = 100, -- Minimum velocity to trigger auto-ragdoll (studs/s)
		},

		-- Dead ragdoll cleanup
		DeadRagdoll = {
			FadeTime = 5, -- Time in seconds before dead ragdoll fades away
			FadeDuration = 0.3, -- How long the fade transition takes (instant if 0)
		},
	},
}

-- ============================================================================
-- SLIDING SYSTEM
-- ============================================================================
GameplayConfig.Sliding = {

	-- Auto-slide: If true, sprinting + crouch will trigger slide. If false, use dedicated slide keybind only.
	AutoSlide = false,

	-- Slide physics (longer slides with less friction)
	InitialVelocity = 70,    -- Backup velocity system
	MinVelocity = 5,         -- LOWERED: Stop slide when very slow (longer slides)
	MaxVelocity = 80,
	FrictionRate = 1.5,      -- REDUCED: Less friction = longer slides

	-- IMPULSE SLIDE (The "Pop" - explosive speed boost)
	ImpulseSlide = {
		Enabled = true,
		ImpulsePower = 70,       -- Instant speed boost (LookVector * Mass * 70)
		SlideFriction = 0,       -- Zero friction during slide (glide)
		NormalFriction = 2,      -- Friction after slide ends
		DecayTime = 0.8,         -- Seconds before slide friction resets
	},

	-- Slide Timeout (airborne slide → force down to ground if not moving)
	SlideTimeout = {
		Enabled = true,
		AirborneThreshold = 0.65, -- Seconds airborne before checking movement
		DownForce = -120,         -- Force applied to push to ground
		DistanceCheckInterval = 0.65, -- MATCH airborne threshold for single check
		MinMovementDistance = 3,  -- Min distance to consider "moving" during threshold
		CancelIfStuck = true,     -- Cancel slide if not moving after threshold
	},

	-- Surface Adhesion (Rivals-style slope sticking - STRONG to prevent edge launches)
	SurfaceAdhesion = {
		Enabled = true,
		AdhesionStrength = 120,      -- INCREASED: Strong force to stick to edges
		LaunchPreventionForce = 250, -- INCREASED: Very strong counter-force when about to launch
		LaunchThreshold = 2,         -- LOWERED: Trigger prevention earlier (at 2 studs/sec upward)
		MinSlopeAngle = 5,           -- Min slope degrees to activate adhesion
		MaxSlopeAngle = 65,          -- Max slope degrees (can't stick to walls steeper than this)
	},

	-- Omni-Directional Steering (momentum-based)
	Steering = {
		Enabled = true,
		Responsiveness = 0.12,   -- Lerp factor per frame (0.12 = gradual)
		VelocityPenalty = 0.75,  -- Lose 25% speed on sharp turns
		MinAlignment = 0.7,      -- Penalty triggers when turning >45°
	},

	-- Slope math
	SpeedChangeRates = {
		Forward = 0.21,  -- Flat ground deceleration
		Upward = 0.7,    -- Uphill deceleration scaling
		Downward = 1.8,  -- Downhill acceleration scaling
		CrossSlope = 0.55,
	},

	SlopeThreshold = 0.02,
	SlopeSteepnessScaling = {
		Uphill = 20,
		Downhill = 12,
	},

	-- Ground checks
	GroundCheckDistance = 10,
	GroundCheckOffset = 0.5,

	WallDetection = {
		RayDistance = 2.2,
		MinWallAngle = 60,
		MaxSlidingAngle = 60,
	},

	-- Directional slide animations
	DirectionalAnimations = {
		ForwardAngle = 60,
		LateralStartAngle = 60,
		LateralEndAngle = 120,
		BackwardStartAngle = 120,
		BackwardEndAngle = 240,
	},

	-- Airborne Float Phase (brief hang time before heavy pull-down)
	FloatDuration = 0.7,             -- Seconds of floating before heavy gravity kicks in
	FloatGravityMultiplier = 0.3,    -- Gravity multiplier during float phase (0.3 = 30% gravity)

	-- Landing boost modifiers (DISABLED)
	LandingBoost = {
		Enabled = false,         -- DISABLED: Remove landing boost
		MinAirTime = 0.3,
		MinFallDistance = 10,
		BoostMultiplier = 0,
		MaxBoost = 0,
		RayDistance = 3,
		RayOffset = 0.5,
		SlopeBoostMultiplier = 0,
		FlatBoostMultiplier = 0,
		SlopeThreshold = 5,
	},

	MinLandingVelocity = 15,  -- Minimum velocity when landing from airborne slide

	StartMomentumPreservation = 1.5, -- Maintain speed when entering slide

	SlideBuffer = {}, -- Stores buffered slide input state

	-- Jump cancel system (Slide Jump - refined for cooler momentum-based feel)
	JumpCancel = {
		Enabled = true,
		JumpHeight = 40.75,           -- REDUCED: Lower jump for cooler horizontal focus
		MinHorizontalPower = 18,   -- INCREASED: More horizontal momentum
		MaxHorizontalPower = 32,   -- INCREASED: Higher cap for speed

		VelocityScaling = 0.6,    -- INCREASED: Better momentum transfer
		MomentumPreservation = 0.35, -- INCREASED: More slide momentum kept
		CoyoteTime = 0.1,

		-- Boost while jumping uphill
		UphillBoost = {
			Enabled = true,
			SlopeThreshold = 0.25,
			MinVerticalBoost = 50,   -- REDUCED: Lower uphill jumps too
			MaxVerticalBoost = 70,   -- REDUCED: Cap uphill boost
			MaxSlopeAngle = 50,
			ScalingExponent = 1.2,
			HorizontalVelocityScale = 0.35,  -- INCREASED: More forward momentum
			MinHorizontalVelocity = 8,       -- INCREASED: Higher minimum
			MinUphillAlignment = -0.4,
		},
	},
}

-- ============================================================================
-- VFX EFFECTS
-- ============================================================================
GameplayConfig.VFX = {
	WallJump = {
		Enabled = true,
		Lifetime = 0.5,
	},
	Land = {
		Enabled = true,
		Lifetime = 0.3,
		MinFallVelocity = 60,
	},
	Slide = {
		Enabled = true,
		Lifetime = 0.4,
		RotationOffset = 180,
	},
	SlideCancel = {
		Enabled = true,
		Lifetime = 0.3,
	},
	SpeedFX = {
		Enabled = true,
		Threshold = 80,
		FallThreshold = 70,
	},
}

return GameplayConfig
