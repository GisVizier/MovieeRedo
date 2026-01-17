local ShotgunConfig = {}

-- =============================================================================
-- WEAPON IDENTIFICATION
-- =============================================================================

ShotgunConfig.WeaponInfo = {
	Name = "Shotgun",
	Type = "Gun",
	DisplayName = "Shotgun",
	Description = "A powerful pump-action shotgun with wide spread and high close-range damage",
}

-- =============================================================================
-- DAMAGE
-- =============================================================================

ShotgunConfig.Damage = {
	-- Body damage is applied to any hitbox part other than the head
	-- NOTE: This damage is divided among all pellets in shotgun mode
	-- With 8 pellets, each pellet does 80 / 8 = 10 damage
	BodyDamage = 80,

	-- Headshot damage is applied when hitting the head hitbox
	-- With 8 pellets, each pellet headshot does 160 / 8 = 20 damage
	HeadshotDamage = 160,

	-- No damage falloff (always full damage at any range)
	-- MinRange, MaxRange, MinDamageMultiplier intentionally omitted
}

-- =============================================================================
-- AMMO & RELOADING
-- =============================================================================

ShotgunConfig.Ammo = {
	-- Magazine capacity
	MagSize = 8,

	-- Starting ammo in reserve
	DefaultReserveAmmo = 32,

	-- Maximum reserve ammo
	MaxReserveAmmo = 64,

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

ShotgunConfig.FireRate = {
	-- Shots per second (how many times the gun can fire per second)
	ShotsPerSecond = 1.0, -- Slow fire rate (pump action)

	-- Fire mode: "Semi" (single shot), "Auto" (hold to shoot), "Burst" (3-round burst)
	FireMode = "Semi",

	-- Burst settings (only used if FireMode = "Burst")
	BurstCount = 3, -- Shots per burst
	BurstDelay = 0.1, -- Delay between shots in a burst (seconds)
}

-- =============================================================================
-- ACCURACY & RECOIL
-- =============================================================================

ShotgunConfig.Accuracy = {
	-- Hip fire spread (degrees) - shotguns have high base spread
	HipFireSpread = 5.0,

	-- Aim down sights spread (degrees)
	ADSSpread = 2.0,

	-- Recoil per shot (degrees) - high recoil for shotgun
	VerticalRecoil = 15,
	HorizontalRecoil = 5,

	-- Recoil recovery speed (degrees per second)
	RecoilRecovery = 10,
}

-- =============================================================================
-- SHOTGUN MODE
-- =============================================================================

ShotgunConfig.Shotgun = {
	-- Number of pellets to fire per shot
	PelletCount = 8,

	-- Spread angle for pellets (degrees) - pellets randomly spread within this cone
	PelletSpread = 5,

	-- NOTE: Damage is automatically divided among pellets
	-- If BodyDamage = 80 and PelletCount = 8, each pellet does 10 damage (80 / 8)
	-- If HeadshotDamage = 160 and PelletCount = 8, each pellet headshot does 20 damage (160 / 8)
	-- All 8 pellets hitting the body = 80 total damage
	-- All 8 pellets hitting the head = 160 total damage
}

return ShotgunConfig
