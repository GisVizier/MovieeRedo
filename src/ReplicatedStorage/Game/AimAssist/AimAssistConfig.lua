--[[
	AimAssistConfig.lua
	
	Configuration for the Aim Assist system.
	Contains global settings, defaults, and constants.
]]

local AimAssistConfig = {}

-- =============================================================================
-- GLOBAL SETTINGS
-- =============================================================================
AimAssistConfig.Enabled = true

-- Debug mode (shows FOV cone and target dots)
-- Set to true to see the aim assist visualization
AimAssistConfig.Debug = true  -- TESTING: Set to false for production

-- Allow aim assist for mouse users (for testing only)
AimAssistConfig.AllowMouseInput = true  -- TESTING: Set to false for production

-- =============================================================================
-- INPUT ELIGIBILITY
-- =============================================================================
AimAssistConfig.Input = {
	-- Gamepad deadzone (stick must move more than this to be eligible)
	GamepadDeadzone = 0.1,
	
	-- Touch inactivity timeout (seconds since last touch to remain eligible)
	TouchInactivityTimeout = 0.5,
}

-- =============================================================================
-- DEFAULT VALUES (used when weapon doesn't specify)
-- =============================================================================
AimAssistConfig.Defaults = {
	-- Target selection
	Range = 150,          -- Max distance to targets (studs)
	FieldOfView = 25,     -- Cone angle (degrees)
	SortingBehavior = "angle",  -- "angle" or "distance"
	IgnoreLineOfSight = false,
	MinRange = 5,         -- No aim assist closer than this
	
	-- Method strengths (0-1)
	Friction = 0.25,      -- Slowdown near targets
	Tracking = 0.35,      -- Follow moving targets
	Centering = 0.1,      -- Pull toward target center
	
	-- ADS (Aim Down Sights) boost multipliers
	ADSBoost = {
		Friction = 1.4,   -- 40% stronger during ADS
		Tracking = 1.3,   -- 30% stronger during ADS
		Centering = 1.2,  -- 20% stronger during ADS
	},
	
	-- Target bones (CollectionService tags on character parts)
	TargetBones = { "Head", "UpperTorso", "Torso" },
}

-- =============================================================================
-- PLAYER SETTINGS (defaults, can be overridden per-player)
-- =============================================================================
AimAssistConfig.PlayerDefaults = {
	-- Overall strength multiplier (0-1, applied to all methods)
	-- Player can adjust this in settings UI
	Strength = 1.0,
	
	-- Individual method toggles (player can disable specific methods)
	FrictionEnabled = true,
	TrackingEnabled = true,
	CenteringEnabled = true,
}

-- Player attribute names (stored on LocalPlayer)
AimAssistConfig.PlayerAttributes = {
	Strength = "AimAssistStrength",
	FrictionEnabled = "AimAssistFriction",
	TrackingEnabled = "AimAssistTracking",
	CenteringEnabled = "AimAssistCentering",
}

-- =============================================================================
-- TARGET TAGS
-- =============================================================================
AimAssistConfig.TargetTags = {
	-- Main tag for aim assist targets (dummies, NPCs, etc.)
	Primary = "AimAssistTarget",
	
	-- Bone tags (parts within targets that can be aimed at)
	Head = "AimAssistHead",
	Torso = "AimAssistTorso",
	Body = "AimAssistBody",
}

-- =============================================================================
-- RENDER STEP BINDING
-- =============================================================================
AimAssistConfig.BindNames = {
	Start = "AimAssist_Start",
	Apply = "AimAssist_Apply",
}

return AimAssistConfig
