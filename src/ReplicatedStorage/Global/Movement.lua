local Movement = {}

Movement.Cooldowns = {
	Crouch = 0.35,
	Jump = 0.12,
	Slide = 0.8,
	WorldGravity = 196.2,
}

Movement.Sliding = {
	AutoSlide = true,
	InitialVelocity = 70,
	MinVelocity = 5,
	MaxVelocity = 120,
	FrictionRate = 0.9,
	ImpulseSlide = {
		Enabled = true,
		ImpulsePower = 70,
		SlideFriction = 0,
		NormalFriction = 2,
		DecayTime = 0.8,
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
		VelocityPenalty = 0.75,
		MinAlignment = 0.7,
	},
	SpeedChangeRates = {
		Forward = 0.21,
		Upward = 0.7,
		Downward = 1.8,
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
	FloatDuration = 0.7,
	FloatGravityMultiplier = 0.3,
	LandingBoost = {
		Enabled = true,
		MinAirTime = 0.3,
		MinFallDistance = 10,
		BoostMultiplier = 0.8,
		MaxBoost = 25,
		RayDistance = 3,
		RayOffset = 0.5,
		SlopeBoostMultiplier = 1.0,
		FlatBoostMultiplier = 0.6,
		SlopeThreshold = 5,
	},
	MinLandingVelocity = 15,
	StartMomentumPreservation = 1.1,
	SlideBuffer = {},
	JumpCancel = {
		Enabled = true,
		JumpHeight = 40.75,
		MinHorizontalPower = 18,
		MaxHorizontalPower = 28,
		VelocityScaling = 0.55,
		MomentumPreservation = 0.2,
		CoyoteTime = 0.1,
		GroundedGraceTime = 0.1,
		AnimationGraceTime = 0.15,
		GroundRayDistance = 0.5,
		UphillBoost = {
			Enabled = true,
			SlopeThreshold = 0.25,
			MinVerticalBoost = 50,
			MaxVerticalBoost = 70,
			MaxSlopeAngle = 50,
			ScalingExponent = 1.2,
			HorizontalVelocityScale = 0.35,
			MinHorizontalVelocity = 8,
			MinUphillAlignment = -0.4,
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

return Movement
