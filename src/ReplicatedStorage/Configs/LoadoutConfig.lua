local LoadoutConfig = {}

LoadoutConfig.Rarities = {
	Common = {
		name = "Common",
		color = Color3.fromRGB(180, 180, 180),
		order = 1,
	},
	Uncommon = {
		name = "Uncommon",
		color = Color3.fromRGB(76, 175, 80),
		order = 2,
	},
	Rare = {
		name = "Rare",
		color = Color3.fromRGB(33, 150, 243),
		order = 3,
	},
	Epic = {
		name = "Epic",
		color = Color3.fromRGB(156, 39, 176),
		order = 4,
	},
	Legendary = {
		name = "Legendary",
		color = Color3.fromRGB(255, 193, 7),
		order = 5,
	},
}

LoadoutConfig.WeaponTypes = {
	Kit = {
		name = "Kit",
		order = 1,
	},
	Primary = {
		name = "Primary",
		order = 2,
	},
	Secondary = {
		name = "Secondary",
		order = 3,
	},
	Melee = {
		name = "Melee",
		order = 4,
	},
}

LoadoutConfig.Weapons = {
	Sniper = {
		id = "Sniper",
		name = "Sniper",
		description = "Long-range precision rifle with high damage.",
		imageId = "rbxassetid://73520188248516",
		weaponType = "Primary",
		rarity = "Rare",
		instance = nil,
		skins = {},
		actions = {
			canQuickUseMelee = true,
			canQuickUseAblility = true,
		},
		maxAmmo = 20,
		clipSize = 5,
		reloadTime = 2.5,
		isAbility = false,
		fireProfile = {
			mode = "Semi",
			autoReloadOnEmpty = true,
		},

		-- Speed settings
		speedMultiplier = 0.85, -- 15% slower when holding

		-- ADS settings
		adsFOV = 35,
		adsSpeedMultiplier = 0.5,

		-- Weapon ballistics
		damage = 80,
		headshotMultiplier = 2.0,
		range = 500,
		fireRate = 60, -- Rounds per minute
		projectileSpeed = 500, -- studs/second (nil = hitscan)
		bulletDrop = true,
		gravity = 196.2,
		minRange = 100, -- Full damage under this distance
		maxRange = 500,
		minDamage = 35, -- Damage at max range
		tracerColor = Color3.fromRGB(255, 200, 100),

		crosshair = {
			type = "Default",
			spreadX = 0.5,
			spreadY = 0.5,
			recoilMultiplier = 2.5,
		},

		-- Aim Assist settings (sniper: precise, narrow FOV, smooth pull)
		aimAssist = {
			enabled = true,
			range = 500,
			minRange = 10,
			fov = 20,                  -- Narrow cone for precision
			sortingBehavior = "angle",
			friction = 0.3,            -- Moderate slowdown
			tracking = 0.4,            -- Moderate tracking
			centering = 0.7,           -- Strong magnetic pull
			adsBoost = {
				Friction = 1.6,
				Tracking = 1.5,
				Centering = 2.0,       -- Strong centering during scope
			},
			adsSnap = {
				enabled = false,       -- DISABLED - no snap, smooth pull only
				strength = 0,
				maxAngle = 0,
			},
		},
	},

	Shotgun = {
		id = "Shotgun",
		name = "Shotgun",
		description = "Close-range powerhouse with spread damage.",
		imageId = "rbxassetid://90633003876805",
		weaponType = "Primary",
		rarity = "Common",
		instance = nil,
		skins = {},
		actions = {
			canQuickUseMelee = true,
			canQuickUseAblility = true,
		},
		maxAmmo = 32,
		clipSize = 8,
		reloadTime = 2.0,
		isAbility = false,
		fireProfile = {
			mode = "Shotgun",
			autoReloadOnEmpty = false,
			pelletsPerShot = 8,
			spread = 0.15,
		},

		-- Speed settings
		speedMultiplier = 0.9, -- 10% slower when holding

		-- ADS settings
		adsFOV = 55,
		adsSpeedMultiplier = 0.7,
		adsEffectsMultiplier = 0.25, -- 25% of normal sway/tilt/bob when ADS

		-- Weapon ballistics
		damage = 15, -- Per pellet
		pelletsPerShot = 8,
		headshotMultiplier = 1.5,
		range = 50,
		fireRate = 75, -- Rounds per minute
		tracerColor = Color3.fromRGB(255, 150, 50),

		crosshair = {
			type = "Shotgun",
			spreadX = 2.5,
			spreadY = 2.5,
			recoilMultiplier = 2.0,
		},

		-- Aim Assist settings (shotgun: close range, wide FOV, strong smooth pull)
		aimAssist = {
			enabled = true,
			range = 100,
			minRange = 2,
			fov = 45,                  -- Wide cone for close combat
			sortingBehavior = "distance",
			friction = 0.5,            -- Strong friction
			tracking = 0.5,            -- Strong tracking
			centering = 0.85,          -- Very strong magnetic pull for close range
			adsBoost = {
				Friction = 1.3,
				Tracking = 1.2,
				Centering = 1.5,
			},
			adsSnap = {
				enabled = false,       -- DISABLED - no snap, smooth pull only
				strength = 0,
				maxAngle = 0,
			},
		},

		-- PROJECTILE CONFIG (pellets with visible travel time)
		projectile = {
			-- Core physics (slower pellets for visible travel)
			speed = 200, -- studs/second (visible travel)
			gravity = 80, -- noticeable drop at range
			drag = 0.08, -- pellet air resistance
			lifetime = 1.0, -- 1 sec max flight
			inheritVelocity = 0, -- don't inherit shooter velocity

			-- Pellet spread (tighter spread)
			spreadMode = "Cone", -- Cone spread pattern
			baseSpread = 0.06, -- reduced spread angle (radians)
			crosshairSpreadScale = 0.03, -- alignment with crosshair visual
			movementSpreadMult = 1.1, -- 10% more spread while moving
			hipfireSpreadMult = 1.0, -- same spread hipfire
			airSpreadMult = 1.2, -- 20% more spread while airborne
			crouchSpreadMult = 0.9, -- 10% less spread while crouching
			slideSpreadMult = 1.0, -- normal spread while sliding

			-- Multi-pellet config
			pelletsPerShot = 8, -- 8 pellets per shot
			pelletDamage = 15, -- damage per pellet

			-- Behaviors (no pierce/ricochet by default)
			pierce = 0,
			pierceDamageMult = 1.0,
			ricochet = 0,
			ricochetDamageMult = 0.7,
			ricochetSpeedMult = 0.9,

			-- No AoE
			aoe = nil,

			-- No charge
			charge = nil,

			-- Visual
			visual = "Pellet",
			tracerColor = Color3.fromRGB(255, 150, 50),
			tracerLength = 1.5,
			trailEnabled = true,
		},
	},

	AssaultRifle = {
		id = "AssaultRifle",
		name = "Assault Rifle",
		description = "Versatile automatic rifle for all ranges.",
		imageId = "rbxassetid://128585915261145",
		weaponType = "Primary",
		rarity = "Uncommon",
		instance = nil,
		skins = {},
		actions = {
			canQuickUseMelee = true,
			canQuickUseAblility = true,
		},
		maxAmmo = 120,
		clipSize = 30,
		reloadTime = 1.8,
		isAbility = false,
		fireProfile = {
			mode = "Auto",
			autoReloadOnEmpty = true,
			spread = 0.02,
		},

		-- Speed settings
		speedMultiplier = 0.95, -- 5% slower when holding

		-- ADS settings
		adsFOV = 50,
		adsSpeedMultiplier = 0.7,

		-- Weapon ballistics
		damage = 25,
		headshotMultiplier = 1.75,
		range = 300,
		fireRate = 600, -- Rounds per minute (automatic)
		projectileSpeed = nil, -- Hitscan
		bulletDrop = false,
		spread = 0.02,
		minRange = 50,
		maxRange = 300,
		minDamage = 12,
		tracerColor = Color3.fromRGB(255, 230, 150),

		crosshair = {
			type = "Default",
			spreadX = 1.2,
			spreadY = 1.2,
			recoilMultiplier = 1.2,
		},

		-- Aim Assist settings (assault rifle: balanced, medium range)
		aimAssist = {
			enabled = true,
			range = 200,
			minRange = 3,
			fov = 35,                  -- Medium cone
			sortingBehavior = "angle",
			friction = 0.4,            -- Balanced friction
			tracking = 0.4,            -- Balanced tracking
			centering = 0.8,           -- Strong magnetic pull
			adsBoost = {
				Friction = 1.4,
				Tracking = 1.3,
				Centering = 1.5,
			},
			adsSnap = {
				enabled = false,       -- DISABLED - no snap, smooth pull only
				strength = 0,
				maxAngle = 0,
			},
		},
	},

	Revolver = {
		id = "Revolver",
		name = "Revolver",
		description = "High-powered secondary with precision shots.",
		imageId = "rbxassetid://102055799339005",
		weaponType = "Secondary",
		rarity = "Common",
		instance = nil,
		skins = {
			Classic = {
				id = "Classic",
				name = "Classic",
				description = "The original revolver skin.",
				imageId = "rbxassetid://94616470074926",
				rarity = "Common",
				instance = nil,
			},
			Saw = {
				id = "Saw",
				name = "Saw",
				description = "Industrial themed revolver skin.",
				imageId = "rbxassetid://113077522614979",
				rarity = "Rare",
				instance = nil,
			},
			Energy = {
				id = "Energy",
				name = "Energy",
				description = "Futuristic energy-infused revolver skin.",
				imageId = "rbxassetid://109214865844984",
				rarity = "Epic",
				instance = nil,
			},
		},
		actions = {
			canQuickUseMelee = true,
			canQuickUseAblility = true,
		},
		maxAmmo = 36,
		clipSize = 6,
		reloadTime = 1.5,
		isAbility = false,
		fireProfile = {
			mode = "Semi",
			autoReloadOnEmpty = true,
		},

		-- Speed settings
		speedMultiplier = 1.0, -- No speed penalty (light secondary)

		-- ADS settings
		adsFOV = 55,
		adsSpeedMultiplier = 0.75,

		-- Weapon ballistics
		damage = 45,
		headshotMultiplier = 2.0,
		range = 200,
		fireRate = 120, -- Rounds per minute
		tracerColor = Color3.fromRGB(255, 100, 50),

		crosshair = {
			type = "Default",
			spreadX = 1.5,
			spreadY = 1.5,
			recoilMultiplier = 1.8,
		},

		-- PROJECTILE CONFIG (single accurate bullet)
		projectile = {
			-- Core physics (fast bullet with slight drop)
			speed = 350, -- studs/second (fast but visible)
			gravity = 30, -- slight drop at range
			drag = 0.01, -- minimal air resistance
			lifetime = 2.0, -- 2 sec max flight
			inheritVelocity = 0,

			-- Spread (very accurate)
			spreadMode = "Cone",
			baseSpread = 0.015, -- tight spread
			crosshairSpreadScale = 0.01,
			movementSpreadMult = 1.1,
			hipfireSpreadMult = 1.3,
			airSpreadMult = 1.5,
			crouchSpreadMult = 0.8,
			slideSpreadMult = 1.2,

			-- Single bullet
			pelletsPerShot = 1,

			-- No pierce/ricochet
			pierce = 0,
			pierceDamageMult = 1.0,
			ricochet = 0,
			ricochetDamageMult = 0.7,
			ricochetSpeedMult = 0.9,

			-- No AoE/charge
			aoe = nil,
			charge = nil,

			-- Visual
			visual = "Bullet",
			tracerColor = Color3.fromRGB(255, 100, 50),
			tracerLength = 3,
			trailEnabled = true,
		},

		-- Aim Assist settings (revolver: precise secondary with smooth pull)
		aimAssist = {
			enabled = true,
			range = 150,
			minRange = 3,
			fov = 25,                  -- Medium cone
			sortingBehavior = "angle",
			friction = 0.35,           -- Moderate friction
			tracking = 0.4,            -- Moderate tracking
			centering = 0.7,           -- Strong magnetic pull
			adsBoost = {
				Friction = 1.5,
				Tracking = 1.4,
				Centering = 1.6,
			},
			adsSnap = {
				enabled = false,       -- DISABLED - no snap, smooth pull only
				strength = 0,
				maxAngle = 0,
			},
		},
	},

	Knife = {
		id = "Knife",
		name = "Knife",
		description = "Swift melee weapon for close encounters.",
		imageId = "rbxassetid://117216368976984",
		weaponType = "Melee",
		rarity = "Common",
		instance = nil,
		skins = {},
		actions = {
			canQuickUseMelee = true,
			canQuickUseAblility = true,
		},
		maxAmmo = 0,
		clipSize = 0,
		attackCooldown = 0.5,
		specialCooldown = 3.0,
		isAbility = false,

		-- Speed settings
		speedMultiplier = 1.1, -- 10% faster (light melee)

		crosshair = {
			type = "Default",
			spreadX = 0.5,
			spreadY = 0.5,
			recoilMultiplier = 0.3,
		},

		-- Aim Assist settings (knife: light melee assist, no snap)
		aimAssist = {
			enabled = true,
			range = 15,                -- Melee range only
			minRange = 0,
			fov = 60,                  -- Wide cone for melee
			sortingBehavior = "distance",
			friction = 0.3,
			tracking = 0.4,
			centering = 0.2,
			adsSnap = {
				enabled = false,       -- No ADS for melee
			},
		},
	},

	ExecutionerBlade = {
		id = "ExecutionerBlade",
		name = "Executioner's Blade",
		description = "A devastating blade forged for swift judgment.",
		imageId = "rbxassetid://117216368976984", -- Using knife image temporarily
		weaponType = "Melee",
		rarity = "Rare",
		instance = nil,
		skins = {},
		actions = {
			canQuickUseMelee = false,
			canQuickUseAblility = true,
		},
		maxAmmo = 0,
		clipSize = 0,
		attackCooldown = 1.0,
		specialCooldown = 5.0,
		isAbility = false,

		-- Speed settings
		speedMultiplier = 0.9, -- 10% slower (heavy blade)

		-- Melee stats
		damage = 50,
		range = 8,
		specialDamage = 100,
		specialRange = 12,

		crosshair = {
			type = "Default",
			spreadX = 0.5,
			spreadY = 0.5,
			recoilMultiplier = 0.3,
		},

		-- Aim Assist settings (blade: melee-focused, no snap)
		aimAssist = {
			enabled = true,
			range = 25,                -- Melee range
			minRange = 0,
			fov = 55,                  -- Wide cone for melee
			sortingBehavior = "distance",
			friction = 0.4,
			tracking = 0.5,
			centering = 0.3,
			adsSnap = {
				enabled = false,       -- No ADS for melee
			},
		},
	},
}

LoadoutConfig.Crosshair = {
	DefaultCustomization = {
		showDot = true,
		showTopLine = true,
		showBottomLine = true,
		showLeftLine = true,
		showRightLine = true,
		lineThickness = 2,
		lineLength = 10,
		gapFromCenter = 5,
		dotSize = 4,
		rotation = 0,
		cornerRadius = 0,
		mainColor = Color3.fromRGB(255, 255, 255),
		outlineColor = Color3.fromRGB(0, 0, 0),
		outlineThickness = 1,
		opacity = 1,
		scale = 1,
		dynamicSpreadEnabled = true,
	},
}

function LoadoutConfig.getWeapon(weaponId)
	return LoadoutConfig.Weapons[weaponId]
end

function LoadoutConfig.getWeaponsByType(weaponType)
	local weapons = {}
	for id, weapon in LoadoutConfig.Weapons do
		if weapon.weaponType == weaponType then
			table.insert(weapons, {
				id = id,
				data = weapon,
			})
		end
	end

	table.sort(weapons, function(a, b)
		local rarityA = LoadoutConfig.Rarities[a.data.rarity]
		local rarityB = LoadoutConfig.Rarities[b.data.rarity]
		return (rarityA and rarityA.order or 0) < (rarityB and rarityB.order or 0)
	end)

	return weapons
end

function LoadoutConfig.getAllWeapons()
	local weapons = {}
	for id, weapon in LoadoutConfig.Weapons do
		table.insert(weapons, {
			id = id,
			data = weapon,
		})
	end
	return weapons
end

function LoadoutConfig.getWeaponSkins(weaponId)
	local weapon = LoadoutConfig.Weapons[weaponId]
	if not weapon or not weapon.skins then
		return {}
	end

	local skins = {}
	for skinId, skin in weapon.skins do
		table.insert(skins, {
			id = skinId,
			data = skin,
			parentWeaponId = weaponId,
		})
	end

	table.sort(skins, function(a, b)
		local rarityA = LoadoutConfig.Rarities[a.data.rarity]
		local rarityB = LoadoutConfig.Rarities[b.data.rarity]
		return (rarityA and rarityA.order or 0) < (rarityB and rarityB.order or 0)
	end)

	return skins
end

function LoadoutConfig.getWeaponSkin(weaponId, skinId)
	local weapon = LoadoutConfig.Weapons[weaponId]
	if not weapon or not weapon.skins then
		return nil
	end
	return weapon.skins[skinId]
end

function LoadoutConfig.getRarityColor(rarityName)
	local rarity = LoadoutConfig.Rarities[rarityName]
	return rarity and rarity.color or Color3.fromRGB(255, 255, 255)
end

function LoadoutConfig.getWeaponType(typeName)
	return LoadoutConfig.WeaponTypes[typeName]
end

function LoadoutConfig.getAllWeaponTypes()
	local types = {}
	for typeName, typeData in LoadoutConfig.WeaponTypes do
		table.insert(types, {
			id = typeName,
			data = typeData,
		})
	end

	table.sort(types, function(a, b)
		return a.data.order < b.data.order
	end)

	return types
end

return LoadoutConfig
