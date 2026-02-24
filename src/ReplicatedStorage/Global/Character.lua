local Character = {
	SprintSpeed = 28,
	WalkSpeed = 19,
	JumpPower = 43,
	AutoSprint = false,
	CoyoteTime = 0.12,

	JumpFatigue = {
		Enabled = true,
		FreeJumps = 5,
		DecayPerJump = 0.03,
		MinMultiplier = 0.9,

		MinVerticalVelocity = 12.5,
		MinVerticalEnforceTime = 0.12,
		GroundResetTime = .85,
		RecoverWhileFalling = true,
	},


	WallJump = {
		Enabled = true,
		VerticalBoost = 46.74,
		HorizontalBoost = 25,
		WallPushForce = 35,
		AnglePushMultiplier = 1.5,
		WallDetectionDistance = 3.0,
		MinWallAngle = 30,
		RequireAirborne = true,
		RequireSprinting = false,
		ExcludeDuringSlide = true,
		MaxCharges = 3,
		CooldownBetweenJumps = 0.3,
	},
	
	Jump = {
		WallRaycast = {
			Enabled = false,
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
	
	MovementForce = 680,
	FrictionMultiplier = 0.88,
	AirControlMultiplier = 2.4,
	AirResistance = 5,
	AirborneSlideDownforce = 380,
	
	FallSpeed = {
		Enabled = true,
		MaxFallSpeed = 90,                -- Terminal velocity; hit in ~1s = natural acceleration feel
		DragMultiplier = 0.08,            -- Gentle brake approaching terminal

		AscentDrag = 0.004,               -- Floaty ascent

		FallAcceleration = 6,             -- Slight downward pull during descent
		AscentGravityReduction = 0.58,    -- Counteracts 58% of gravity going up = slow, low-gravity ascent

		HangTimeThreshold = 3,            -- Tight window; prevents hang firing during normal air movement
		HangTimeDrag = 0.40,              -- Reduced so force delta at hang-exit is smaller = smoother transition

		VerticalForceLerp = 8,            -- Faster lerp smooths the hang→descent force cliff
	},

	GravityDamping = {
		Enabled = true,
		DampingFactor = 0.42,             -- 0.42 × 1.35 = 0.567 (~57% counteracted, net ~43% gravity)
		MaxFallSpeed = 100,               -- Hard cap above FallSpeed terminal; out of the way in normal play
		ApplyOnlyWhenFalling = true,
	},

	FloatDecay = {
		Enabled = true,
		FloatDuration = 0.70,             -- Longer float at apex
		DecayRate = 0.05,                 -- Very slow decay = floatiness fades out gradually
		MinDampingFactor = 0.22,          -- Lower floor so fall accelerates naturally as arc completes
		MomentumFactor = 0.003,           -- Less momentum penalty
		VelocityThreshold = 0.6,          -- Threshold
		ThresholdShrinkRate = 0.003,      -- Faster shrink
	},
	
	LandingMomentum = {
		Enabled = true,
		PreservationMultiplier = 0.55,    -- Keep good momentum on landing
		MinPreservationSpeed = 12,
		DecayRate = 0.75,                 -- Faster decay = less slide
	},

	WallStop = {
		Enabled = true,
		RayDistance = 1.5,
		MinWallAngle = 70,
	},
	-- Slope Magnet (snap to ground when about to launch off ramps/slopes)
	-- Keeps grounded state stable on sloped collision seams so walking uphill doesn't "airborne flicker".
	SlopeMagnet = {
		Enabled = true,
		RayLength = 3.0,
		SnapVelocity = -80,
		JumpCooldown = 0.25,
		MinAirborneHeight = 0.5,
	},
	-- Step Assist (step over small obstacles when walking)
	StepAssist = {
		Enabled = true,
		StepHeight = 1.5,          -- Max height to step over (studs)
		ForwardDistance = 2.5,     -- How far ahead to check for obstacles
		Cooldown = 0.1,            -- Time between step-ups
		BoostMultiplier = 0.45,    -- Multiplier for upward boost
	},
	-- Slope Walking Assist (extra push when walking uphill)
	SlopeWalkAssist = {
		Enabled = false,
		ForceMultiplier = 1.15,    -- Extra force when walking uphill
		MaxSlopeAngle = 50,        -- Don't assist past this angle
	},
	GroundRayOffset = 0.35,
	GroundRayDistance = 1.0,
	MaxWalkableSlopeAngle = 90,
	StandingFriction = {
		IdleFriction = 1.25,
		MinSlopeAngle = 1,
		SlopeFriction = 1.1,
	},
	CrouchHeightReduction = 2,
	CrouchSpeed = 8,
	CrouchSpeedReduction = 0.5,
	DirectionalAnimations = {
		ForwardAngle = 60,
		LateralStartAngle = 60,
		LateralEndAngle = 120,
		BackwardStartAngle = 120,
		BackwardEndAngle = 240,
	},
	HeadOffset = Vector3.new(0, 2, 0),
	HideFromLocalPlayer = true,
	PartsToHide = { "Body", "Feet", "Head", "Root", "CrouchBody", "CrouchHead" },
	ShowRigForTesting = false,
	EnableRig = true,
	CustomPhysicalProperties = {
		Density = 0.7,
		Elasticity = 0,
		ElasticityWeight = 100,
		Friction = 0,
		FrictionWeight = 100,
	},
	DeathYThreshold = -100,
	RigRotation = {
		Enabled = true,
		MaxTiltAngle = 55,
		Smoothness = 38,
		MinSlopeForRotation = 3,
		Airborne = {
			Enabled = true,
			MaxTiltAngle = 18,
			MinVerticalVelocity = 6,
			Smoothness = 10,
		},
	},
	Ragdoll = {
		Physics = {
			Density = 0.7,
			Friction = 0.5,
			Elasticity = 0,
			HeadDensity = 0.7,
			HeadFriction = 0.3,
		},
		JointLimits = {
			Neck = {
				UpperAngle = 45,
				TwistLowerAngle = -60,
				TwistUpperAngle = 60,
				MaxFrictionTorque = 10,
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
				MaxFrictionTorque = 15,
			},
		},
		AutoRagdoll = {
			OnDeath = true,
			OnExplosion = false,
			OnHighVelocity = false,
			VelocityThreshold = 100,
		},
		DeadRagdoll = {
			FadeTime = 5,
			FadeDuration = 0.3,
		},
	},
}

return Character
