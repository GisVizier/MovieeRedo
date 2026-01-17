local InteractableConfig = {}

-- =============================================================================
-- JUMP PADS
-- =============================================================================

InteractableConfig.JumpPads = {
	-- Jump physics
	UpwardForce = 125, -- Initial upward velocity
	Cooldown = 0.2, -- Seconds before pad can be used again by same player
	PreserveHorizontalMomentum = true, -- Keep horizontal velocity when jumping

	-- Visual feedback (optional)
	EnableParticles = true,
	EnableSound = true,
}

-- =============================================================================
-- LADDERS
-- =============================================================================

InteractableConfig.Ladders = {
	-- Climbing physics
	ClimbSpeed = 65, -- Vertical movement speed on ladders
	AllowHorizontalMovement = true, -- Can move side to side while on ladder

	-- Exit mechanics
	AutoExitAtTop = true, -- Automatically exit ladder when reaching top
}

-- =============================================================================
-- COLLECTION SERVICE TAGS & NAMING
-- =============================================================================

InteractableConfig.CollectionService = {
	-- Tags for CollectionService to find interactable folders/models
	JumpPadTag = "Jump Pads", -- Tag applied to folders/models containing jump pads
	LadderTag = "Ladders", -- Tag applied to folders/models containing ladders

	-- Part naming conventions
	HitboxName = "Hitbox", -- Name of the collision detection part in each model
}

-- =============================================================================
-- DETECTION & PERFORMANCE
-- =============================================================================

InteractableConfig.Detection = {
	-- Update frequency
	UpdateRate = 60, -- Hz - how often to check for overlaps (matches RunService.Heartbeat)

	-- Collision detection
	RespectCanCollide = false, -- Detect overlaps even with non-colliding parts
	UseClientSidePrediction = true, -- Apply effects immediately on client

	-- Performance optimization
	MaxDetectionDistance = 100, -- Only check interactables within this range
	EnableDistanceCulling = true, -- Skip distant interactables for performance
}

-- =============================================================================
-- VISUAL EFFECTS
-- =============================================================================

InteractableConfig.Effects = {
	-- Particle effects and other non-audio visual feedback
}

return InteractableConfig
