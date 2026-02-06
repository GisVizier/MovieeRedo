--[[
	CombatConfig.lua
	Configuration values for the Combat Resource System
]]

local CombatConfig = {}

-- Default resource values
CombatConfig.DefaultMaxHealth = 150
CombatConfig.DefaultMaxShield = 100
CombatConfig.DefaultMaxOvershield = 50
CombatConfig.DefaultMaxUltimate = 100

-- Ultimate gain rates
CombatConfig.UltGain = {
	DamageDealt = 0.15,    -- 15% of damage dealt becomes ult
	DamageTaken = 0.10,    -- 10% of damage taken becomes ult
	Kill = 25,             -- Flat 25 ult per kill
	Assist = 10,           -- Flat 10 ult per assist
}

-- Shield settings (disabled by default)
CombatConfig.Shield = {
	Enabled = false,       -- Set to true to enable shield system
	RegenDelay = 3.0,      -- Seconds after damage before regen starts
	RegenRate = 15,        -- Shield per second during regen
	DamageBreaksRegen = true,
}

-- Overshield settings
CombatConfig.Overshield = {
	DecayEnabled = false,  -- Whether overshield decays over time
	DecayDelay = 5.0,      -- Seconds before decay starts
	DecayRate = 5,         -- Overshield lost per second
}

-- I-Frame settings
CombatConfig.IFrames = {
	DefaultDuration = 0.2, -- Default i-frame duration in seconds
}

-- Status effect settings
CombatConfig.StatusEffects = {
	TickRate = 0.1,        -- Default tick rate (10 ticks per second)
	MaxActiveEffects = 10, -- Max concurrent effects per player
}

-- Death settings
CombatConfig.Death = {
	DefaultKillEffect = "Ragdoll",
	RagdollDuration = 3,   -- Seconds ragdoll plays before respawn
	RespawnDelay = 0,      -- Additional delay after ragdoll (handled by game controller)
}

-- Damage numbers display settings
CombatConfig.DamageNumbers = {
	Enabled = true,
	HeadshotScale = 1.3,   -- Scale multiplier for headshots
	CriticalScale = 1.5,   -- Scale multiplier for criticals
	FloatSpeed = 2,        -- Studs per second upward
	FadeTime = 1.0,        -- Seconds before fade out
	FadeDuration = 0.3,    -- Duration of fade animation
	
	Colors = {
		Normal = Color3.fromRGB(233, 233, 233),
		Headshot = Color3.fromRGB(255, 200, 50),
		Critical = Color3.fromRGB(255, 80, 80),
		Heal = Color3.fromRGB(100, 255, 100),
	},
}

return CombatConfig
