local RevolverConfig = {}

-- =============================================================================
-- WEAPON IDENTIFICATION
-- =============================================================================

RevolverConfig.WeaponInfo = {
	Name = "Revolver",
	Type = "Gun",
	DisplayName = "Revolver",
	Description = "A classic six-shooter with high damage and moderate fire rate",
}

-- =============================================================================
-- DAMAGE
-- =============================================================================

RevolverConfig.Damage = {
	-- Body damage is applied to any hitbox part other than the head
	BodyDamage = 35,

	-- Headshot damage is applied when hitting the head hitbox
	HeadshotDamage = 85,

	-- No damage falloff for revolver (always full damage at any range)
	-- MinRange, MaxRange, MinDamageMultiplier intentionally omitted
}

-- =============================================================================
-- AMMO & RELOADING
-- =============================================================================

RevolverConfig.Ammo = {
	-- Magazine capacity
	MagSize = 6,

	-- Starting ammo in reserve
	DefaultReserveAmmo = 36,

	-- Maximum reserve ammo
	MaxReserveAmmo = 60,

	-- Reload time (seconds)
	ReloadTime = 2.5,

	-- Whether reload can be interrupted
	CanInterruptReload = false,

	-- Auto reload when magazine is empty
	AutoReload = true,
}

-- =============================================================================
-- FIRE RATE & BEHAVIOR
-- =============================================================================

RevolverConfig.FireRate = {
	-- Shots per second (how many times the gun can fire per second)
	ShotsPerSecond = 3.67,

	-- Fire mode: "Semi" (single shot), "Auto" (hold to shoot), "Burst" (3-round burst)
	FireMode = "Auto",

	-- Burst settings (only used if FireMode = "Burst")
	BurstCount = 3, -- Shots per burst
	BurstDelay = 0.1, -- Delay between shots in a burst (seconds)
}

-- =============================================================================
-- ACCURACY & RECOIL
-- =============================================================================

RevolverConfig.Accuracy = {
	-- Hip fire spread (degrees)
	HipFireSpread = 2.5,

	-- Aim down sights spread (degrees)
	ADSSpread = 0.5,

	-- Recoil per shot (degrees)
	VerticalRecoil = 8,
	HorizontalRecoil = 3,

	-- Recoil recovery speed (degrees per second)
	RecoilRecovery = 15,
}

-- =============================================================================
-- SHOTGUN MODE (Optional)
-- =============================================================================
-- Uncomment and configure for shotgun-style weapons
-- RevolverConfig.Shotgun = {
-- 	-- Number of pellets to fire per shot
-- 	PelletCount = 8,
--
-- 	-- Spread angle for pellets (degrees) - pellets randomly spread within this cone
-- 	PelletSpread = 5,
--
-- 	-- NOTE: Damage is automatically divided among pellets
-- 	-- If BodyDamage = 80 and PelletCount = 8, each pellet does 10 damage (80 / 8)
-- 	-- If HeadshotDamage = 160 and PelletCount = 8, each pellet headshot does 20 damage (160 / 8)
-- }

return RevolverConfig
