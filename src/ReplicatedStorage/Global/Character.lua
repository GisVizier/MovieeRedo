local Character = {
	SprintSpeed = 24,
	WalkSpeed = 17,
	JumpPower = 45,
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
		VerticalBoost = 37.74,
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
	
	MovementForce = 500,
	FrictionMultiplier = 0.8,
	AirControlMultiplier = 2.8,
	AirResistance = 8,
	AirborneSlideDownforce = 420,
	
	FallSpeed = {
		Enabled = true,
		MaxFallSpeed = 70.75,             -- Down from 105 (much slower terminal velocity)
		DragMultiplier = 0.4,         -- Up from 0.32 (more air drag)
		
		AscentDrag = 0.008,  -- Slightly less ascent drag

		FallAcceleration = 21.75,-- Down from 24 (much slower fall)
		AscentGravityReduction = 0.425, -- Down from 0.42 (jump even higher)

		HangTimeThreshold = 6.75,         -- Down from 8 (hang time kicks in earlier)
		HangTimeDrag = 0.35,           -- Up from 0.18 (big float at apex)

		VerticalForceLerp = 8.5,         -- Down from 10 (smoother)
	},

	GravityDamping = {
		Enabled = true,
		DampingFactor = 0.3,          -- Down from 0.45 (much more damping = floatier)
		MaxFallSpeed = 70,
		ApplyOnlyWhenFalling = true,
	},
	
	FloatDecay = {
		Enabled = true,
		FloatDuration = 1.15,           -- Up from 1.3 (longer float)
		DecayRate = 0.035,             -- Down from 0.045 (slower decay)
		MinDampingFactor = 0.15,       -- Down from 0.20 (more damping)
		MomentumFactor = 0.004,        -- Down from 0.006 (less momentum kill)
		VelocityThreshold = 0.5,       -- Down from 0.6 (more forgiving)
		ThresholdShrinkRate = 0.0015,  -- Down from 0.002 (slower shrink)
	},
	LandingMomentum = {
		Enabled = true,
		PreservationMultiplier = 0.92,
		MinPreservationSpeed = 10,
		DecayRate = 0.92,
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
		BoostMultiplier = 0.65,    -- Multiplier for upward boost
	},
	-- Slope Walking Assist (extra push when walking uphill)
	SlopeWalkAssist = {
		Enabled = true,
		ForceMultiplier = 1.15,    -- Extra force when walking uphill
		MaxSlopeAngle = 50,        -- Don't assist past this angle
	},
	GroundRayOffset = 0.35,
	GroundRayDistance = 1.0,
	MaxWalkableSlopeAngle = 90,
	StandingFriction = {
		IdleFriction = 0.65,
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
