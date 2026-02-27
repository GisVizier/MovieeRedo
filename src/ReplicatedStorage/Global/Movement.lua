local Movement = {}

Movement.Cooldowns = {
	Crouch = 0.35,
	Jump = 0.12,
	Slide = 0.85,          -- Slightly reduced for faster re-slide
	WorldGravity = 196.2,  -- Keep default (float is handled by Character.lua)
}

Movement.Sliding = {
	AutoSlide = true,
	InitialVelocity = 50,  -- Nerfed from 62
	MinVelocity = 5,
	MaxVelocity = 110,     -- Down from 120
	FrictionRate = 1.25,   -- Down from 0.9 (slightly more friction)
	ImpulseSlide = {
		Enabled = true,
		ImpulsePower = 50,  -- Nerfed from 62
		SlideFriction = 0,
		NormalFriction = 2,
		DecayTime = 0.7,    -- Down from 0.8
	},
	SlideTimeout = {
		Enabled = true,
		AirborneThreshold = 0.65,
		DownForce = -120,
		DistanceCheckInterval = 0.65,
		MinMovementDistance = 3,
		CancelIfStuck = true,
	},
	SurfaceAdhesion = {
		Enabled = true,
		AdhesionStrength = 120,
		LaunchPreventionForce = 250,
		LaunchThreshold = 2,
		MinSlopeAngle = 5,
		MaxSlopeAngle = 65,
	},
	Steering = {
		Enabled = false,
		Responsiveness = 0.12,
		VelocityPenalty = 0.88,
		MinAlignment = 0.55,
	},
	SpeedChangeRates = {
		Forward = 0.21,
		Upward = 0.7,
		Downward = 2.0,        -- Nerfed from 2.5 (orig 1.8)
		CrossSlope = 0.55,
	},
	SlopeThreshold = 0.02,
	SlopeSteepnessScaling = {
		Uphill = 20,
		Downhill = 12,
	},
	GroundCheckDistance = 10,
	GroundCheckOffset = 0.5,
	WallDetection = {
		RayDistance = 2.2,
		MinWallAngle = 60,
		MaxSlidingAngle = 60,
	},
	DirectionalAnimations = {
		ForwardAngle = 60,
		LateralStartAngle = 60,
		LateralEndAngle = 120,
		BackwardStartAngle = 120,
		BackwardEndAngle = 240,
	},

	FloatDuration = 0.17,           -- (Legacy - actual float handled by Character.FloatDecay)
	FloatGravityMultiplier = 0.03,  -- (Legacy - actual float handled by Character.FloatDecay)

	LandingBoost = {
		Enabled = true,
		MinAirTime = 0.3,
		MinFallDistance = 10,
		BoostMultiplier = 0.8,
		MaxBoost = 14,                  -- Nerfed from 18 (orig 12)
		RayDistance = 3,
		RayOffset = 0.5,
		SlopeBoostMultiplier = 1.15,    -- Nerfed from 1.4 (orig 1.0)
		FlatBoostMultiplier = 0.6,
		SlopeThreshold = 5,
	},

	MinLandingVelocity = 15,
	StartMomentumPreservation = 1.15,
	SlideBuffer = {},
	JumpCancel = {
		Enabled = true,
		JumpHeight = 38,
		MinHorizontalPower = 18,
		MaxHorizontalPower = 34,
		VelocityScaling = 0.65,
		MomentumPreservation = 0.45,
		CoyoteTime = 0.1,
		GroundedGraceTime = 0.1,
		AnimationGraceTime = 0.15,
		GroundRayDistance = 0.5,
		
		UphillBoost = {
			Enabled = true,
			SlopeThreshold = 0.14,      -- Nerfed from 0.12 (orig 0.15)
			MinVerticalBoost = 45,
			MaxVerticalBoost = 100,
			MaxSlopeAngle = 60,
			ScalingExponent = 1.4,      -- Nerfed from 1.3 (orig 1.5)

			HorizontalVelocityScale = 0.9,  -- Nerfed from 1.0 (orig 0.85)
			MinHorizontalVelocity = 18,     -- Nerfed from 22 (orig 15)
			MinUphillAlignment = -0.25,
		},
	},
}

Movement.VFX = {
	WallJump = {
		Enabled = true,
		Lifetime = 0.5,
	},
	Land = {
		Enabled = true,
		Lifetime = 0.3,
		MinFallVelocity = 45,
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
		FallThreshold = 50,
	},
}

return Movement
