local AssaultRifleConfig = {}

-- =============================================================================
-- WEAPON IDENTIFICATION
-- =============================================================================

AssaultRifleConfig.WeaponInfo = {
	Name = "AssaultRifle",
	Type = "Gun",
	DisplayName = "Assault Rifle",
	Description = "A fully automatic rifle with high fire rate and moderate damage",
}

-- =============================================================================
-- DAMAGE
-- =============================================================================

AssaultRifleConfig.Damage = {
	-- Body damage is applied to any hitbox part other than the head
	BodyDamage = 25,

	-- Headshot damage is applied when hitting the head hitbox
	HeadshotDamage = 50,

	-- No damage falloff (always full damage at any range)
	-- MinRange, MaxRange, MinDamageMultiplier intentionally omitted
}

-- =============================================================================
-- AMMO & RELOADING
-- =============================================================================

AssaultRifleConfig.Ammo = {
	-- Magazine capacity
	MagSize = 30,

	-- Starting ammo in reserve
	DefaultReserveAmmo = 120,

	-- Maximum reserve ammo
	MaxReserveAmmo = 180,

	-- Reload time (seconds)
	ReloadTime = 2.2,

	-- Whether reload can be interrupted
	CanInterruptReload = false,

	-- Auto reload when magazine is empty
	AutoReload = true,
}

-- =============================================================================
-- FIRE RATE & BEHAVIOR
-- =============================================================================

AssaultRifleConfig.FireRate = {
	-- Shots per second (how many times the gun can fire per second)
	ShotsPerSecond = 11,

	-- Fire mode: "Semi" (single shot), "Auto" (hold to shoot), "Burst" (3-round burst)
	FireMode = "Auto",

	-- Burst settings (only used if FireMode = "Burst")
	BurstCount = 3, -- Shots per burst
	BurstDelay = 0.1, -- Delay between shots in a burst (seconds)
}

-- =============================================================================
-- ACCURACY & RECOIL
-- =============================================================================

AssaultRifleConfig.Accuracy = {
	-- Hip fire spread (degrees)
	HipFireSpread = 3.0,

	-- Aim down sights spread (degrees)
	ADSSpread = 0.4,

	-- Recoil per shot (degrees)
	VerticalRecoil = 4,
	HorizontalRecoil = 2,

	-- Recoil recovery speed (degrees per second)
	RecoilRecovery = 12,
}

return AssaultRifleConfig
