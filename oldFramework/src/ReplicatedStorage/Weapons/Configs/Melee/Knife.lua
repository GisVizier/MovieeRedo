local KnifeConfig = {}

-- =============================================================================
-- WEAPON IDENTIFICATION
-- =============================================================================

KnifeConfig.WeaponInfo = {
	Name = "Knife",
	Type = "Melee",
	DisplayName = "Combat Knife",
	Description = "A quick melee weapon for close-quarters combat",
}

-- =============================================================================
-- DAMAGE
-- =============================================================================

KnifeConfig.Damage = {
	-- Body damage is applied to any hitbox part other than the head
	BodyDamage = 50,

	-- Headshot damage is applied when hitting the head hitbox
	HeadshotDamage = 100,

	-- Backstab damage (optional, for hitting from behind)
	BackstabDamage = 150,
	BackstabAngle = 90, -- Maximum angle from behind to count as backstab (degrees)
}

-- =============================================================================
-- ATTACK BEHAVIOR
-- =============================================================================

KnifeConfig.Attack = {
	-- Attack range (studs)
	Range = 5,

	-- Attack cooldown (seconds between attacks)
	AttackCooldown = 0.67,

	-- Attack types
	AttackTypes = {
		Light = {
			Damage = 50, -- Body damage
			HeadshotDamage = 100,
			Cooldown = 0.67, -- Time before next attack (seconds)
		},
		Heavy = {
			Damage = 85, -- Body damage
			HeadshotDamage = 150,
			Cooldown = 1.2, -- Time before next attack (seconds)
		},
	},
}

return KnifeConfig
