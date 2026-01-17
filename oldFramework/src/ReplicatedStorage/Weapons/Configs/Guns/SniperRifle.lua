local SniperRifleConfig = {}

-- =============================================================================
-- WEAPON IDENTIFICATION
-- =============================================================================

SniperRifleConfig.WeaponInfo = {
	Name = "SniperRifle",
	Type = "Gun",
	DisplayName = "Sniper Rifle",
	Description = "A high-precision rifle with extreme damage and long range",
}

-- =============================================================================
-- DAMAGE
-- =============================================================================

SniperRifleConfig.Damage = {
	-- Body damage is applied to any hitbox part other than the head
	BodyDamage = 70,

	-- Headshot damage is applied when hitting the head hitbox
	HeadshotDamage = 150,

	-- Minimal damage falloff (snipers are effective at long range)
	MinRange = 100,           -- Range where damage starts falling off
	MaxRange = 1000,         -- Range where damage reaches minimum
	MinDamageMultiplier = 0.8, -- Minimum damage multiplier at max range (still powerful)
}

-- =============================================================================
-- AMMO & RELOADING
-- =============================================================================

SniperRifleConfig.Ammo = {
	-- Magazine capacity
	MagSize = 5,

	-- Starting ammo in reserve
	DefaultReserveAmmo = 25,

	-- Maximum reserve ammo
	MaxReserveAmmo = 40,

	-- Reload time (seconds)
	ReloadTime = 3.0,

	-- Whether reload can be interrupted
	CanInterruptReload = false,

	-- Auto reload when magazine is empty
	AutoReload = true,
}

-- =============================================================================
-- FIRE RATE & BEHAVIOR
-- =============================================================================

SniperRifleConfig.FireRate = {
	-- Shots per second (how many times the gun can fire per second)
	ShotsPerSecond = 1.2,

	-- Fire mode: "Semi" (single shot), "Auto" (hold to shoot), "Burst" (3-round burst)
	FireMode = "Semi",

	-- Burst settings (only used if FireMode = "Burst")
	BurstCount = 3, -- Shots per burst
	BurstDelay = 0.1, -- Delay between shots in a burst (seconds)
}

-- =============================================================================
-- ACCURACY & RECOIL
-- =============================================================================

SniperRifleConfig.Accuracy = {
	-- Hip fire spread (degrees)
	HipFireSpread = 5.0,

	-- Aim down sights spread (degrees)
	ADSSpread = 0.1,

	-- Recoil per shot (degrees)
	VerticalRecoil = 15,
	HorizontalRecoil = 5,

	-- Recoil recovery speed (degrees per second)
	RecoilRecovery = 8,
}

return SniperRifleConfig
