--[[
	KnockbackConfig.lua
	Configuration for the knockback system
	
	Presets can be used with:
		knockbackController:ApplyKnockbackPreset(character, "Fling", sourcePosition)
]]

local KnockbackConfig = {}

-- Global settings
KnockbackConfig.MaxMagnitude = 500          -- Increased cap for strong knockbacks
KnockbackConfig.DefaultMagnitude = 80
KnockbackConfig.MinVerticalRatio = 0.1      -- Minimum upward lift
KnockbackConfig.GroundedMultiplier = 1.0    -- No reduction when grounded
KnockbackConfig.AirborneMultiplier = 1.0    -- No reduction when airborne

-- =============================================================================
-- PRESETS
-- =============================================================================
-- Each preset defines knockback as DIRECT VELOCITY COMPONENTS (like JumpPads)
-- upwardVelocity: vertical velocity in studs/sec (e.g. JumpPad uses 125)
-- outwardVelocity: horizontal velocity in studs/sec away from source
-- preserveMomentum: how much existing velocity to keep (0-1)

KnockbackConfig.Presets = {
	-- Light push - subtle nudge
	Light = {
		upwardVelocity = 20,
		outwardVelocity = 40,
		preserveMomentum = 0.5,
	},
	
	-- Standard knockback - balanced up and out
	Standard = {
		upwardVelocity = 50,
		outwardVelocity = 60,
		preserveMomentum = 0.2,
	},
	
	-- Launch - strong upward focus (for updrafts)
	Launch = {
		upwardVelocity = 100,
		outwardVelocity = 40,
		preserveMomentum = 0.1,
	},
	
	-- Fling - WIND GALE: Strong push up AND out (like getting hit by a gust)
	-- Compare: JumpPad is 125 up, 0 out
	Fling = {
		upwardVelocity = 80,       -- Good lift (slightly less than jump pad)
		outwardVelocity = 180,     -- Strong horizontal push away
		preserveMomentum = 0.0,
	},
	
	-- Blast - explosive knockback, balanced but powerful
	Blast = {
		upwardVelocity = 100,
		outwardVelocity = 120,
		preserveMomentum = 0.0,
	},
	
	-- Slam - downward knockback (for ground pounds)
	Slam = {
		upwardVelocity = -80,
		outwardVelocity = 100,
		preserveMomentum = 0.0,
	},
	
	-- Uppercut - strong vertical launch
	Uppercut = {
		upwardVelocity = 140,
		outwardVelocity = 30,
		preserveMomentum = 0.0,
	},
}

return KnockbackConfig
