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

		-- ADS settings
		adsFOV = 55,
		adsSpeedMultiplier = 0.7,

		-- Weapon ballistics
		damage = 15, -- Per pellet
		pelletsPerShot = 8,
		headshotMultiplier = 1.5,
		range = 50,
		fireRate = 75, -- Rounds per minute
		projectileSpeed = nil, -- Hitscan
		bulletDrop = false,
		spread = 0.15, -- Spread angle in radians
		minRange = 5,
		maxRange = 50,
		minDamage = 5, -- Per pellet at max range
		tracerColor = Color3.fromRGB(255, 150, 50),
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

		-- ADS settings
		adsFOV = 55,
		adsSpeedMultiplier = 0.75,

		-- Weapon ballistics
		damage = 45,
		headshotMultiplier = 2.0,
		range = 200,
		fireRate = 120, -- Rounds per minute
		projectileSpeed = nil, -- Hitscan
		bulletDrop = false,
		minRange = 30,
		maxRange = 200,
		minDamage = 20,
		tracerColor = Color3.fromRGB(255, 100, 50),
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
		attackCooldown = 0.6,
		specialCooldown = 5.0,
		isAbility = false,

		-- Melee stats
		damage = 50,
		range = 8,
		specialDamage = 100,
		specialRange = 12,
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
