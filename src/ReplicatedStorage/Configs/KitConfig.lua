local KitConfig = {}

export type AbilityData = {
	Name: string,
	Description: string,
	Video: string?,
	Damage: number?,
	DamageType: string?,
	Destruction: string?,
	Cooldown: number,
}

export type PassiveData = {
	Name: string,
	Description: string,
	Video: string?,
	PassiveType: string?,
}

export type UltimateData = {
	Name: string,
	Description: string,
	Video: string?,
	Damage: number?,
	DamageType: string?,
	Destruction: string?,
	UltCost: number,
}

export type KitData = {
	Icon: string,
	Name: string,
	Description: string,
	Rarity: string,
	Price: number,
	Module: string,
	Ability: AbilityData,
	Passive: PassiveData,
	Ultimate: UltimateData,
}

export type KitRuntimeState = {
	abilityCooldownEndsAt: number?,
	ultimate: number?,
}

KitConfig.RarityInfo = {
	Legendary = {
		TEXT = "LEGENDARY",
		COLOR = Color3.fromRGB(255, 209, 43),
	},

	Mythic = {
		TEXT = "MYTHIC",
		COLOR = Color3.fromRGB(255, 67, 70),
	},

	Epic = {
		TEXT = "EPIC",
		COLOR = Color3.fromRGB(180, 76, 255),
	},

	Rare = {
		TEXT = "RARE",
		COLOR = Color3.fromRGB(125, 188, 255),
	},

	Common = {
		TEXT = "COMMON",
		COLOR = Color3.fromRGB(203, 208, 218),
	},
}

KitConfig.Kits = {
	WhiteBeard = {
		Icon = "rbxassetid://72158182932036",
		Name = "WHITE BEARD",
		Description = "A colossal warrior whose titan-hammer cracks the earth, creating earthquakes and disasters, a fortress to his crew and a living catastrophe to his enemies.",
		Rarity = "Legendary",
		Price = 1250,
		Module = "WhiteBeard",

		Ability = {
			Name = "QUAKE BALL",
			Description = "Condenses seismic energy into a crackling sphere and fires it straight ahead. It rips through terrain and structures, crushing enemies with a collapsing shockwave and flinging survivors back.",
			Video = "",
			Damage = 45,
			DamageType = "Projectile",
			Destruction = "Huge",
			Cooldown = 8,
		},

		Passive = {
			Name = "EARTHSHAKER",
			Description = "Your presence rattles the battlefield. Small tremors pulse near you during combat.",
			Video = "",
			PassiveType = "Aura",
		},

		Ultimate = {
			Name = "GURA GURA NO MI",
			Description = "Unleash the full power of the tremor fruit, shattering the battlefield with devastating quakes.",
			Video = "",
			Damage = 120,
			DamageType = "AOE",
			Destruction = "Mega",
			UltCost = 100,
		},
	},

	Mob = {
		Icon = "rbxassetid://88925605827431",
		Name = "MOB",
		Description = "A quiet student with sealed psychic power who avoids conflict, afraid it will surge out of control. When someone he cares about is threatened, that power erupts and changes everything.",
		Rarity = "Epic",
		Price = 450,
		Module = "Mob",

		Ability = {
			Name = "AEGIS WALL",
			Description = "Raise a massive wall that blocks bullets and abilities, protecting you and your allies. After 3 seconds, activate again while looking at your wall to launch it forward as deadly debris.",
			Video = "",
			Damage = 32.5,
			DamageType = "AOE",
			Destruction = "Big",
			Cooldown = 0.5,
		},

		Passive = {
			Name = "PSYCHIC PRESSURE",
			Description = "Your psychic energy builds under stress. Staying alive accelerates ultimate gain.",
			Video = "",
			PassiveType = "Charge",
		},

		Ultimate = {
			Name = "???",
			Description = "No one knows what you become when rage climbs this high.",
			Video = "",
			DamageType = "Grab",
			Destruction = "Mega",
			UltCost = 100,
		},
	},

	ChainsawMan = {
		Icon = "rbxassetid://81755505866630",
		Name = "CHAINSAW MAN",
		Description = "A feral fighter fused with a chainsaw engine spirit, sprouting blades as his heart revs. He fights to survive, and when pushed too far he becomes a whirlwind of burning steel.",
		Rarity = "Rare",
		Price = 570,
		Module = "ChainsawMan",

		Ability = {
			Name = "OVERDRIVE GUARD",
			Description = "Brace for impact and reduce incoming damage for a short moment.",
			Video = "",
			Damage = 32.5,
			DamageType = "AOE",
			Destruction = "Big",
			Cooldown = 6,
		},

		Passive = {
			Name = "BLOOD FUEL",
			Description = "When you fall below 50% health, you enter a Rage State with faster movement and boosted damage.",
			Video = "",
			PassiveType = "Heal",
		},

		Ultimate = {
			Name = "DEVIL TRIGGER",
			Description = "Transform into a full devil form, gaining massive damage and lifesteal for a short duration.",
			Video = "",
			Damage = 80,
			DamageType = "Melee",
			Destruction = "Huge",
			UltCost = 100,
		},
	},

	Genji = {
		Icon = "rbxassetid://107097170907543",
		Name = "GENJI",
		Description = "A fallen soul rebuilt with experimental robotics, moving with silent precision and impossible speed. A blur of steel and neon, he fights with honor, efficiency, and unbreakable resolve.",
		Rarity = "Common",
		Price = 12570,
		Module = "Genji",

		Ability = {
			Name = "DEFLECT",
			Description = "Deflect incoming projectiles back at enemies.",
			Video = "",
			Cooldown = 8,
		},

		Passive = {
			Name = "CYBER-AGILITY",
			Description = "Double jump and dashing.",
			Video = "",
			PassiveType = "Movement",
		},

		Ultimate = {
			Name = "DRAGONBLADE",
			Description = "Unsheathe the dragonblade for devastating melee attacks.",
			Video = "",
			Damage = 65,
			DamageType = "Melee",
			Destruction = "Big",
			UltCost = 100,
		},
	},

	Aki = {
		Icon = "rbxassetid://136186193137355",
		Name = "DEVIL HUNTER",
		Description = "A disciplined fighter who makes binding deals with spirits and devils, gaining power at the cost of pain, stamina, and pieces of his soul.",
		Rarity = "Epic",
		Price = 12570,
		Module = "Aki",

		Ability = {
			Name = "KON",
			Description = "Call your Devil to rush in, deliver a vicious bite, and then vanish in a burst of smoke.",
			Video = "",
			Damage = 32.5,
			DamageType = "AOE",
			Destruction = "Big",
			Cooldown = 7,
		},

		Passive = {
			Name = "TELEPORT",
			Description = "When you defeat a player, you may warp back to the marked site.",
			Video = "",
			PassiveType = "Movement",
		},

		Ultimate = {
			Name = "FATE",
			Description = "When you fall, time rewinds for you alone, restoring you to moments before death.",
			Video = "",
			UltCost = 100,
		},
	},

	HonoredOne = {
		Icon = "rbxassetid://106069283820738",
		Name = "HONORED ONE",
		Description = "A legendary sorcerer who bends space itself, untouchable in battle and overwhelming in power. Calm, confident, and unstoppable, he treats every fight like it's already won.",
		Rarity = "Mythic",
		Price = 12570,
		Module = "HonoredOne",
		Color = Color3.fromRGB(155, 89, 255),

		Ability = {
			Name = "DUALITY",
			Description = "Wield limitless force through two states, Pull to drag enemies in and Push to blast them away. Master both to control space, movement, and the fight itself.",
			Video = "",
			Cooldown = 0.5, -- TEST COOLDOWN (was 8)
			Destruction = "Big",
		},

		Passive = {
			Name = "SIX EYES",
			Description = "Enemies you damage are briefly revealed, and your cooldowns recover faster as you stay locked in. The more you fight, the sharper you become.",
			Video = "",
			PassiveType = "Focus",
		},

		Ultimate = {
			Name = "PURPLE SINGULARITY",
			Description = "Fuse Push and Pull into a single limitless blast that erases everything in its path. A straight-line shot of pure destruction that leaves nothing behind.",
			Video = "",
			UltCost = 100,
		},
	},

	Airborne = {
		Icon = "rbxassetid://80058231826369",
		Name = "AIRBORNE",
		Description = "He bends wind for speed and control, launching himself through the air with bursts of momentum. He wins fights by outmoving everyone.",
		Rarity = "Rare",
		Price = 570,
		Module = "Airborne",
		Color = Color3.fromRGB(100, 200, 235),

		Ability = {
			Name = "CLOUDSKIP",
			Description = "Use wind that boosts you, letting you cut angles fast and land in the perfect position.",
			Video = "",
			Cooldown = .5,
		},

		Passive = {
			Name = "AIR CUSHION",
			Description = "Slows your fall, letting you float down and land softly without taking heavy impact.",
			Video = "",
			PassiveType = "Movement",
		},

		Ultimate = {
			Name = "HURRICANE",
			Description = "Unleash a raging tornado that pulls in nearby enemies, spins them helplessly, then launches them outward to scatter the fight.",
			Video = "",
			DamageType = "AOE",
			Destruction = "Big",
			UltCost = 100,
		},
	},
}

KitConfig.Input = {
	AbilityKey = Enum.KeyCode.E,
	UltimateKey = Enum.KeyCode.Q,
}

function KitConfig.getKit(kitId: string): KitData?
	return KitConfig.Kits[kitId]
end

function KitConfig.getKitIds(): {string}
	local ids = {}
	for kitId in KitConfig.Kits do
		table.insert(ids, kitId)
	end
	return ids
end

function KitConfig.getAbilityCooldown(kitId: string): number
	local kit = KitConfig.getKit(kitId)
	if not kit then
		return 0
	end
	return kit.Ability and kit.Ability.Cooldown or 0
end

function KitConfig.getUltimateCost(kitId: string): number
	local kit = KitConfig.getKit(kitId)
	if not kit then
		return 0
	end
	return kit.Ultimate and kit.Ultimate.UltCost or 0
end

function KitConfig.buildKitData(kitId: string, state: KitRuntimeState?): {[string]: any}?
	local kit = KitConfig.getKit(kitId)
	if not kit then
		return nil
	end

	local now = os.clock()
	local endsAt = state and state.abilityCooldownEndsAt or 0
	local remaining = math.max(0, endsAt - now)

	return {
		KitId = kitId,
		KitName = kit.Name,
		Icon = kit.Icon,
		Rarity = kit.Rarity,

		AbilityName = kit.Ability.Name,
		AbilityCooldown = kit.Ability.Cooldown,
		AbilityOnCooldown = remaining > 0,
		AbilityCooldownRemaining = remaining,

		UltimateName = kit.Ultimate.Name,
		UltCost = kit.Ultimate.UltCost,

		HasPassive = kit.Passive ~= nil,
		PassiveName = kit.Passive and kit.Passive.Name or nil,
	}
end

return KitConfig
