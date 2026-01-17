local AnimationConfig = {}

-- =============================================================================
-- ANIMATION ENUM (For Network Replication)
-- =============================================================================

-- Maps animation names to unique IDs for efficient network transmission
-- Uses 1 byte (Uint8) instead of 10-20 byte strings = 90-95% bandwidth reduction
AnimationConfig.AnimationEnum = {
	IdleStanding = 1,
	IdleCrouching = 2,
	CrouchWalking = 4, -- DEPRECATED - Kept for network compatibility only, use CrouchWalking[Forward/Left/Right/Backward]
	SlidingForward = 5,
	SlidingLeft = 6,
	SlidingRight = 7,
	SlidingBackward = 8,
	Jump = 9,
	JumpCancel1 = 10,
	JumpCancel2 = 11,
	JumpCancel3 = 12,
	Falling = 13,
	WalkingForward = 14,
	WalkingLeft = 15,
	WalkingRight = 16,
	WalkingBackward = 17,
	CrouchWalkingForward = 18,
	CrouchWalkingLeft = 19,
	CrouchWalkingRight = 20,
	CrouchWalkingBackward = 21,
	WallBoostForward = 22,
	WallBoostLeft = 23,
	WallBoostRight = 24,
	-- Add new animations here, max 255 (Uint8)
}

-- Reverse lookup: AnimationId -> AnimationName
AnimationConfig.AnimationNames = {}
for name, id in pairs(AnimationConfig.AnimationEnum) do
	AnimationConfig.AnimationNames[id] = name
end

-- =============================================================================
-- ANIMATION ASSET IDS
-- =============================================================================

-- All animation asset IDs stored in one place for easy management
-- Replace these placeholder IDs with your actual animation asset IDs
AnimationConfig.AnimationIds = {
	-- Movement States
	IdleStanding = "rbxassetid://92194161569395",
	IdleCrouching = "rbxassetid://122269586055321",

	-- Walking animations (directional)
	WalkingForward = "rbxassetid://104179648114065",
	WalkingLeft = "rbxassetid://73744005075678", -- TODO: Replace with actual left walk animation
	WalkingRight = "rbxassetid://131678368784485", -- TODO: Replace with actual right walk animation
	WalkingBackward = "rbxassetid://126175043706435", -- TODO: Replace with actual backward walk animation

	-- Crouch walking animations (directional)
	CrouchWalkingForward = "rbxassetid://138993574248187",
	CrouchWalkingLeft = "rbxassetid://109158532090510", -- TODO: Replace with actual left crouch walk animation
	CrouchWalkingRight = "rbxassetid://138975677882947", -- TODO: Replace with actual right crouch walk animation
	CrouchWalkingBackward = "rbxassetid://97177625696162", -- TODO: Replace with actual backward crouch walk animation

	-- Sliding animations (directional)
	SlidingForward = "rbxassetid://118234102824832",
	SlidingLeft = "rbxassetid://72860596067472",
	SlidingRight = "rbxassetid://72860596067472",
	SlidingBackward = "rbxassetid://72860596067472",

	-- Airborne
	Jump = "rbxassetid://130318594637679",
	JumpCancel = {
        "http://www.roblox.com/asset/?id=75738868462620",
        "http://www.roblox.com/asset/?id=75738868462620",
        "http://www.roblox.com/asset/?id=75738868462620",
    },

	-- Wall Boost (deprecated, replaced by directional versions)
	WallBoost = "rbxassetid://91422190532199",

	-- Wall Boost animations (directional)
	WallBoostForward = "rbxassetid://91422190532199", -- Forward/backward wall boost (TODO: Replace with actual animation)
	WallBoostLeft = "rbxassetid://90421525780071", -- Left wall boost (TODO: Replace with actual animation)
	WallBoostRight = "rbxassetid://111217739777976", -- Right wall boost (TODO: Replace with actual animation)

	Falling = "rbxassetid://180436148",
}

-- =============================================================================
-- ANIMATION DEFINITIONS
-- =============================================================================

-- Define animation properties: looping, weight, fade times, blending
AnimationConfig.Animations = {
	-- Movement State Animations (these loop and transition based on MovementStateManager)
	IdleStanding = {
		Id = AnimationConfig.AnimationIds.IdleStanding,
		Loop = true,
		Weight = 1.0, -- Default weight (1.0 = full strength)
		FadeInTime = 0.2, -- Time to fade in when starting
		FadeOutTime = 0.2, -- Time to fade out when stopping
		Priority = Enum.AnimationPriority.Core, -- Animation priority for blending
		Category = "Idle", -- Animation category for replication
		Description = "Idle animation when standing still (not moving)",
	},

	IdleCrouching = {
		Id = AnimationConfig.AnimationIds.IdleCrouching,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.2,
		FadeOutTime = 0.2,
		Priority = Enum.AnimationPriority.Core,
		Category = "Idle",
		Description = "Idle animation when crouched (not moving)",
	},

	-- Directional Walking Animations
	WalkingForward = {
		Id = AnimationConfig.AnimationIds.WalkingForward,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.3,
		FadeOutTime = 0.5,
		Priority = Enum.AnimationPriority.Core,
		Category = "State",
		Description = "Forward walk animation (0° to ~60° from camera direction)",
	},

	WalkingLeft = {
		Id = AnimationConfig.AnimationIds.WalkingLeft,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.3,
		FadeOutTime = 0.5,
		Priority = Enum.AnimationPriority.Core,
		Category = "State",
		Description = "Left walk animation (~60° to ~120° left of camera)",
	},

	WalkingRight = {
		Id = AnimationConfig.AnimationIds.WalkingRight,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.3,
		FadeOutTime = 0.5,
		Priority = Enum.AnimationPriority.Core,
		Category = "State",
		Description = "Right walk animation (~60° to ~120° right of camera)",
	},

	WalkingBackward = {
		Id = AnimationConfig.AnimationIds.WalkingBackward,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.3,
		FadeOutTime = 0.5,
		Priority = Enum.AnimationPriority.Core,
		Category = "State",
		Description = "Backward walk animation (~120° to ~240° behind camera)",
	},

	-- Directional Crouch Walking Animations
	CrouchWalkingForward = {
		Id = AnimationConfig.AnimationIds.CrouchWalkingForward,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.2,
		FadeOutTime = 0.2,
		Priority = Enum.AnimationPriority.Core,
		Category = "State",
		Description = "Forward crouch walk animation (0° to ~60° from camera direction)",
	},

	CrouchWalkingLeft = {
		Id = AnimationConfig.AnimationIds.CrouchWalkingLeft,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.2,
		FadeOutTime = 0.2,
		Priority = Enum.AnimationPriority.Core,
		Category = "State",
		Description = "Left crouch walk animation (~60° to ~120° left of camera)",
	},

	CrouchWalkingRight = {
		Id = AnimationConfig.AnimationIds.CrouchWalkingRight,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.2,
		FadeOutTime = 0.2,
		Priority = Enum.AnimationPriority.Core,
		Category = "State",
		Description = "Right crouch walk animation (~60° to ~120° right of camera)",
	},

	CrouchWalkingBackward = {
		Id = AnimationConfig.AnimationIds.CrouchWalkingBackward,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.2,
		FadeOutTime = 0.2,
		Priority = Enum.AnimationPriority.Core,
		Category = "State",
		Description = "Backward crouch walk animation (~120° to ~240° behind camera)",
	},

	-- Directional Sliding Animations
	SlidingForward = {
		Id = AnimationConfig.AnimationIds.SlidingForward,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.1, -- Faster transition for sliding
		FadeOutTime = 0.15,
		Priority = Enum.AnimationPriority.Movement,
		Category = "State",
		Description = "Forward slide animation (0° to ~60° from camera direction)",
	},

	SlidingLeft = {
		Id = AnimationConfig.AnimationIds.SlidingLeft,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.1,
		FadeOutTime = 0.15,
		Priority = Enum.AnimationPriority.Movement,
		Category = "State",
		Description = "Left slide animation (~60° to ~120° left of camera)",
	},

	SlidingRight = {
		Id = AnimationConfig.AnimationIds.SlidingRight,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.1,
		FadeOutTime = 0.15,
		Priority = Enum.AnimationPriority.Movement,
		Category = "State",
		Description = "Right slide animation (~60° to ~120° right of camera)",
	},

	SlidingBackward = {
		Id = AnimationConfig.AnimationIds.SlidingBackward,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.1,
		FadeOutTime = 0.15,
		Priority = Enum.AnimationPriority.Movement,
		Category = "State",
		Description = "Backward slide animation (~120° to ~240°, player faces opposite of slide direction)",
	},

	-- Airborne Animations
	Jump = {
		Id = AnimationConfig.AnimationIds.Jump,
		Loop = false,
		Weight = 1.0,
		FadeInTime = 0.05, -- Very fast for responsive feel
		FadeOutTime = 0.15, -- Smooth blend to falling
		Priority = Enum.AnimationPriority.Core,
		Category = "Airborne",
		Description = "Jump animation (plays once when jumping)",
	},

	JumpCancel = {
		Ids = AnimationConfig.AnimationIds.JumpCancel, -- Array of animation IDs for random selection
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.05, -- Very fast for responsive feel
		FadeOutTime = 0.2, -- Smooth blend to falling
		Priority = Enum.AnimationPriority.Core,
		Category = "Airborne",
		Description = "Jump cancel animation (plays once when canceling jump, randomly selected)",
	},

	-- Wall Boost animations (deprecated, kept for compatibility)
	WallBoost = {
		Id = AnimationConfig.AnimationIds.WallBoost,
		Loop = false,
		Weight = 1.0,
		FadeInTime = 0.05, -- Very fast for responsive feel
		FadeOutTime = 0.15, -- Smooth blend to falling
		Priority = Enum.AnimationPriority.Core,
		Category = "Airborne",
		Description = "Wall boost animation (deprecated, use directional versions)",
	},

	-- Directional Wall Boost Animations
	WallBoostForward = {
		Id = AnimationConfig.AnimationIds.WallBoostForward,
		Loop = false,
		Weight = 1.0,
		FadeInTime = 0.05, -- Very fast for responsive feel
		FadeOutTime = 0.15, -- Smooth blend to falling
		Priority = Enum.AnimationPriority.Core,
		Category = "Airborne",
		Description = "Wall boost animation when moving forward/backward relative to camera",
	},

	WallBoostLeft = {
		Id = AnimationConfig.AnimationIds.WallBoostLeft,
		Loop = false,
		Weight = 1.0,
		FadeInTime = 0.05,
		FadeOutTime = 0.15,
		Priority = Enum.AnimationPriority.Core,
		Category = "Airborne",
		Description = "Wall boost animation when moving left relative to camera",
	},

	WallBoostRight = {
		Id = AnimationConfig.AnimationIds.WallBoostRight,
		Loop = false,
		Weight = 1.0,
		FadeInTime = 0.05,
		FadeOutTime = 0.15,
		Priority = Enum.AnimationPriority.Core,
		Category = "Airborne",
		Description = "Wall boost animation when moving right relative to camera",
	},

	Falling = {
		Id = AnimationConfig.AnimationIds.Falling,
		Loop = true,
		Weight = 1.0,
		FadeInTime = 0.2, -- Smooth transition from jump/jump cancel
		FadeOutTime = 0.15, -- Clean blend to grounded animations
		Priority = Enum.AnimationPriority.Core,
		Category = "Airborne",
		Description = "Falling animation (loops while airborne, not sliding)",
	},
}

-- =============================================================================
-- MOVEMENT STATE MAPPING
-- =============================================================================

-- Maps MovementStateManager states to animation names
-- These animations play automatically when the state changes
AnimationConfig.StateAnimations = {
	Walking = "WalkingForward", -- Deprecated, directional animations handled dynamically
	Sprinting = "WalkingForward", -- Deprecated, directional animations handled dynamically
	Crouching = "CrouchWalkingForward", -- Deprecated, directional crouch animations handled dynamically
	-- Walking/Sprinting states use directional animations (handled dynamically by AnimationController)
	-- Walking = "WalkingForward" | "WalkingLeft" | "WalkingRight" | "WalkingBackward" (determined by movement direction)
	-- Crouching states use directional animations (handled dynamically by AnimationController)
	-- Crouching = "CrouchWalkingForward" | "CrouchWalkingLeft" | "CrouchWalkingRight" | "CrouchWalkingBackward" (determined by movement direction)
	-- Sliding states use directional animations (handled dynamically by AnimationController)
	-- Sliding = "SlidingForward" | "SlidingLeft" | "SlidingRight" | "SlidingBackward" (determined by slide direction)

	-- Idle animations (when not moving in a state)
	IdleStanding = "IdleStanding", -- Playing when Walking/Sprinting state + not moving
	IdleCrouching = "IdleCrouching", -- Playing when Crouching state + not moving
}

-- =============================================================================
-- PRELOADING SETTINGS
-- =============================================================================

AnimationConfig.Preloading = {
	-- Preload animations on client join for instant playback
	PreloadOnJoin = true,

	-- Animations to preload (all by default)
	PreloadList = {
		"IdleStanding",
		"IdleCrouching",
		"WalkingForward",
		"WalkingLeft",
		"WalkingRight",
		"WalkingBackward",
		"CrouchWalkingForward",
		"CrouchWalkingLeft",
		"CrouchWalkingRight",
		"CrouchWalkingBackward",
		"SlidingForward",
		"SlidingLeft",
		"SlidingRight",
		"SlidingBackward",
		"Jump",
		"JumpCancel",
		"WallBoostForward",
		"WallBoostLeft",
		"WallBoostRight",
		"Falling",
	},
}

-- =============================================================================
-- REPLICATION SETTINGS
-- =============================================================================

AnimationConfig.Replication = {
	-- Whether to replicate movement state animations to other players
	ReplicateMovementStates = true,

	-- Whether to replicate action animations (like Hit) to other players
	ReplicateActions = true,

	-- Update rate for animation state replication (seconds)
	-- Lower = more responsive, higher = less network usage
	UpdateRate = 0.1, -- 10 times per second
}

-- =============================================================================
-- PERFORMANCE SETTINGS
-- =============================================================================

AnimationConfig.Performance = {
	-- Maximum distance to play animations for other players (studs)
	MaxAnimationDistance = 200,

	-- Stop animations when character is too far away
	CullDistantAnimations = true,

	-- Maximum animation speed multipliers (prevents animations from playing too fast)
	MaxWalkAnimationSpeed = 2.0, -- Max speed for walk/sprint animations (2.0 = animations can play up to 2x speed)
	MaxCrouchAnimationSpeed = 1.5, -- Max speed for crouch animations (1.5 = animations can play up to 1.5x speed)
}

return AnimationConfig