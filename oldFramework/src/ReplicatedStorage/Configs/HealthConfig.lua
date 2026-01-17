local HealthConfig = {}

-- =============================================================================
-- PLAYER HEALTH (Using Humanoid.Health)
-- =============================================================================
-- This config now uses Roblox's built-in Humanoid health system instead of
-- a custom health system. Health is managed via Humanoid.MaxHealth and
-- Humanoid.Health, with damage applied via Humanoid:TakeDamage().
-- Regeneration is disabled by removing the default Health script from Humanoid.
-- =============================================================================

HealthConfig.Player = {
	MaxHealth = 150, -- Maximum player health (sets Humanoid.MaxHealth)
	StartHealth = 150, -- Health when spawning (sets Humanoid.Health)
	RespawnDelay = 0, -- Delay before respawn after death (seconds) - 0 = instant
}

-- =============================================================================
-- HEALTH REGENERATION (Disabled)
-- =============================================================================
-- Health regeneration is DISABLED for this game. The default Humanoid Health
-- script is removed in CharacterService:SetupHumanoid() to prevent automatic
-- regeneration. If you want to enable regeneration in the future, you'll need
-- to create a custom regeneration script.
-- =============================================================================

HealthConfig.Regeneration = {
	Enabled = false, -- Health regeneration is disabled (Humanoid Health script is removed)
	Rate = 5, -- Health regenerated per interval (not used)
	Interval = 1, -- How often to regenerate (seconds) (not used)
	Delay = 5, -- Delay before regeneration starts after taking damage (seconds) (not used)
	MaxHealthPercent = 100, -- Max health % that can be regenerated to (100 = full health) (not used)
}

-- =============================================================================
-- DAMAGE MODIFIERS
-- =============================================================================

HealthConfig.Damage = {
	-- Damage multipliers for different body parts (if implemented)
	HeadshotMultiplier = 2.0, -- 2x damage for headshots
	BodyshotMultiplier = 1.0, -- Normal damage for body shots
	LimbshotMultiplier = 0.75, -- 0.75x damage for limb shots

	-- Fall damage settings
	FallDamage = {
		Enabled = false, -- Enable fall damage
		MinHeight = 30, -- Minimum fall height to take damage (studs)
		DamagePerStud = 2, -- Damage per stud fallen above MinHeight
		MaxDamage = 100, -- Maximum fall damage possible
	},
}

-- =============================================================================
-- DEATH SETTINGS
-- =============================================================================

HealthConfig.Death = {
	FallOffMapYThreshold = -100, -- Y position where player dies from falling off map (handled in GameplayConfig.Character.DeathYThreshold)
	RespawnAtSpawnPoint = true, -- Respawn at spawn point vs where player died
	KeepWeaponOnRespawn = true, -- Keep equipped weapon after respawn
}

-- =============================================================================
-- SHIELDS/ARMOR (For future implementation)
-- =============================================================================

HealthConfig.Shield = {
	Enabled = false, -- Enable shield/armor system
	MaxShield = 100, -- Maximum shield value
	ShieldRegenRate = 10, -- Shield regenerated per interval
	ShieldRegenInterval = 1, -- How often shield regenerates (seconds)
	ShieldRegenDelay = 3, -- Delay before shield starts regenerating after damage (seconds)
	ShieldAbsorbsAllDamage = false, -- true = shield takes all damage first, false = damage splits between shield and health
}

return HealthConfig
