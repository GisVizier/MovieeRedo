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
		imageId = "rbxassetid://118913007185209",
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

		speedMultiplier = 0.72,

		adsFOV = 30,
		adsSpeedMultiplier = 0.4,

		damage = 50,
		headshotMultiplier = 3.0,
		ignoreGlobalDamageMultiplier = true,
		range = 650,
		fireRate = 90,
		disableDamageFalloff = true,
		adsAnimationDuration = 0.5,
		
		-- Wall destruction pressure (higher = bigger holes)
		destructionPressure = 100, -- Sniper makes big holes
		projectileSpeed = nil,
		bulletDrop = false,
		spread = 0.11,
		tracer = {
			trailScale = 1.45,
			muzzleScale = 2.7,
		},
		tracerColor = Color3.fromRGB(255, 200, 100),

		recoil = {
			pitchUp = 15.25,
			yawRandom = 1.9,
			recoverySpeed = 2.4,
			adsMultiplier = 1.1,
			kickPos = Vector3.new(0, 0, -0.16),
			kickRot = Vector3.new(-0.2, 0.02, 0),
			screenShakeMultiplier = 1.75,
			screenShakeDuration = 0.12,
			screenShakeFrequency = 18,
		},

		crosshair = {
			type = "Default",
			spreadX = 4.6,
			spreadY = 4.6,
			recoilMultiplier = 5.6,
			-- Sniper: very inaccurate in hipfire, pinpoint while ADS
			crouchMult = 0.9,
			sprintMult = 3.2,
			airMult = 4.0,
			adsMult = 0.02,
			baseGap = 10, -- Base gap
		},

		-- Aim Assist settings (sniper: precise, narrow FOV, smooth pull)
		aimAssist = {
			enabled = true,
			range = 500,
			minRange = 10,
			fov = 20, -- Narrow cone for precision
			sortingBehavior = "angle",
			friction = 0.3, -- Moderate slowdown
			tracking = 0.4, -- Moderate tracking
			centering = 0.7, -- Strong magnetic pull
			adsBoost = {
				Friction = 1.6,
				Tracking = 1.5,
				Centering = 2.0, -- Strong centering during scope
			},
			adsSnap = {
				enabled = false, -- DISABLED - no snap, smooth pull only
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
		rarity = "Rare",
		instance = nil,
		skins = {
			OGPump = {
				id = "OGPump",
				name = "OG Pump",
				description = "The legendary pump that started it all. One shot, one elimination. Where we droppin'?",
				imageId = "rbxassetid://114063003316618",
				rarity = "Legendary",
				instance = nil,
			},
		},
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
		range = 250,
		fireRate = 75, -- Rounds per minute
		minRange = 5,
		maxRange = 200,
		minDamage = 2,
		tracerColor = Color3.fromRGB(255, 150, 50),
		
		-- Wall destruction (per pellet, uses cluster mode)
		destructionPressure = 30,

		recoil = {
			pitchUp = 5,
			yawRandom = 2,
			recoverySpeed = 8,
		},

		crosshair = {
			type = "Shotgun",
			spreadX = 3.5,
			spreadY = 3.5,
			recoilMultiplier = 3.0,
			-- Shotgun: naturally wide, visible movement reactions
			crouchMult = 0.5, -- 50% reduction when crouching
			sprintMult = 1.8, -- 80% more spread when sprinting
			airMult = 2.0, -- 100% more spread in air
			adsMult = 0.4, -- 60% reduction when ADS
			baseGap = 8, -- Base gap for shotgun
		},

		-- Aim Assist settings (shotgun: close range, wide FOV, strong smooth pull)
		aimAssist = {
			enabled = true,
			range = 100,
			minRange = 2,
			fov = 45, -- Wide cone for close combat
			sortingBehavior = "distance",
			friction = 0.5, -- Strong friction
			tracking = 0.5, -- Strong tracking
			centering = 0.85, -- Very strong magnetic pull for close range
			adsBoost = {
				Friction = 1.3,
				Tracking = 1.2,
				Centering = 1.5,
			},
			adsSnap = {
				enabled = false, -- DISABLED - no snap, smooth pull only
				strength = 0,
				maxAngle = 0,
			},
		},

		-- PROJECTILE CONFIG (fast pellets, near-hitscan at close range)
		projectile = {
			-- Core physics
			speed = 600, -- studs/second (fast, near-instant at close range)
			gravity = 0, -- no drop at shotgun distances
			drag = 0, -- no air resistance
			lifetime = 1, -- full lifetime
			inheritVelocity = 0,

			-- Pellet spread
			spreadMode = "Cone",
			baseSpread = 0.06,
			crosshairSpreadScale = 0.03,
			movementSpreadMult = 1.1,
			hipfireSpreadMult = 1.0,
			airSpreadMult = 1.2,
			crouchSpreadMult = 0.9,
			slideSpreadMult = 1.0,

			-- Multi-pellet config
			pelletsPerShot = 8,
			pelletDamage = 15,

			-- Damage falloff (per pellet)
			minRange = 5,
			maxRange = 200,
			minDamage = 2,

			-- Behaviors
			pierce = 0,
			pierceDamageMult = 1.0,
			ricochet = 0,
			ricochetDamageMult = 0.7,
			ricochetSpeedMult = 0.9,

			aoe = nil,
			charge = nil,

			-- Visual
			visual = "Pellet",
			tracerColor = Color3.fromRGB(255, 150, 50),
			tracerLength = 2,
			trailEnabled = true,
		},
	},

	AssaultRifle = {
		id = "AssaultRifle",
		name = "Assault Rifle",
		description = "Versatile automatic rifle for all ranges.",
		imageId = "rbxassetid://128585915261145",
		weaponType = "Primary",
		rarity = "Common",
		instance = nil,
		skins = {},
		actions = {
			canQuickUseMelee = true,
			canQuickUseAblility = true,
		},
		maxAmmo = 120,
		clipSize = 24,
		reloadTime = 1.8,
		isAbility = false,

		fireProfile = {
			mode = "Auto",
			autoReloadOnEmpty = true,
			spread = 0.01,
		},

		-- Optional tracer VFX tuning (consumed by Tracers system)
		tracer = {
			trailScale = 1.0,
			muzzleScale = 0.45,
		},

		-- Speed settings
		speedMultiplier = 1.1, -- 5% slower when holding

		-- ADS settings
		adsFOV = 40,
		adsSpeedMultiplier = 0.7,

		-- Weapon ballistics
		damage = 25,
		headshotMultiplier = 1.75,
		range = 300,
		fireRate = 520, -- Rounds per minute (automatic)
		projectileSpeed = nil, -- Hitscan
		bulletDrop = false,
		spread = 0.01,
		-- Optional spread tuning (consumed by WeaponController:_performRaycast)
		-- If omitted, runtime falls back to existing hardcoded/crosshair defaults.
		spreadFactors = {
			speedReference = 5,
			speedMaxBonus = 0.2,
			adsSpeedReference = 16,
			adsSpeedMaxBonus = 0.06,
			hipfireMult = .5,
			crouchMult = 0.115,
			slideMult = 1.0,
			sprintMult = 2.2,
			airMult = 2.5,
			adsMult = 0.01,
			minMultiplier = 0,
			maxMultiplier = 1.25,
		},

		minRange = 15,
		maxRange = 250,
		minDamage = 18.24,
		tracerColor = Color3.fromRGB(255, 230, 150),
		
		-- Wall destruction pressure
		destructionPressure = 20,

		recoil = {
			pitchUp = 1.2,
			yawRandom = 0.6,
			recoverySpeed = 10,
		},

		crosshair = {
			type = "Default",
			spreadX = 3.5,
			spreadY = 3.5,
			recoilMultiplier = 2.0,
			-- Movement state spread modifiers (VERY NOTICEABLE)
			crouchMult = 0.115, -- 75% reduction when crouching
			sprintMult = 2.2, -- 120% more spread when sprinting
			airMult = 2.5, -- 150% more spread in air
			adsMult = 0.01, -- 85% reduction when ADS
			adsVelocitySensitivityMult = 0.45,
			adsVelocityRecoveryMult = 0.8,
			adsSpreadResponseMult = 0.85,
			baseGap = 10, -- Base gap for crosshair
		},

		-- Aim Assist settings (assault rifle: balanced, medium range)
		aimAssist = {
			enabled = true,
			range = 200,
			minRange = 3,
			fov = 35, -- Medium cone
			sortingBehavior = "angle",
			friction = 0.4, -- Balanced friction
			tracking = 0.4, -- Balanced tracking
			centering = 0.8, -- Strong magnetic pull
			adsBoost = {
				Friction = 1.4,
				Tracking = 1.3,
				Centering = 1.5,
			},
			adsSnap = {
				enabled = false, -- DISABLED - no snap, smooth pull only
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
			Sheriff = {
				id = "Sheriff",
				name = "Sheriff",
				description = "Frontier-issued revolver skin.",
				imageId = "rbxassetid://121217546077252",
				rarity = "Legendary",
				instance = nil,
			},
		},
		actions = {
			canQuickUseMelee = true,
			canQuickUseAblility = true,
		},
		maxAmmo = 40,
		clipSize = 8,
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

		damage = 35.3,
		headshotMultiplier = 3.0,
		range = 240,
		fireRate = 421,
		spread = 0.008,
		spreadFactors = {
			speedReference = 6,
			speedMaxBonus = 1.4,
			hipfireMult = 0.45,
			crouchMult = 0.08,
			slideMult = 1.25,
			sprintMult = 2.2,
			airMult = 2.5,
			adsMult = 0.02,
			minMultiplier = 0.05,
			maxMultiplier = 2.5,
		},
		minRange = 15,
		maxRange = 220,
		minDamage = 23.53,
		tracerColor = Color3.fromRGB(255, 100, 50),
		
		-- Wall destruction pressure (high caliber)
		destructionPressure = 40,

		recoil = {
			pitchUp = 5.8,
			yawRandom = 0.2,
			recoverySpeed = 4.5,
		},

		crosshair = {
			type = "Default",
			spreadX = 0.9,
			spreadY = 0.9,
			recoilMultiplier = 3.2,
			crouchMult = 0.08,
			sprintMult = 2.2,
			airMult = 2.5,
			adsMult = 0.02,
			baseGap = 10,
		},

		-- Aim Assist settings (revolver: precise secondary with smooth pull)
		aimAssist = {
			enabled = true,
			range = 150,
			minRange = 3,
			fov = 25, -- Medium cone
			sortingBehavior = "angle",
			friction = 0.35, -- Moderate friction
			tracking = 0.4, -- Moderate tracking
			centering = 0.7, -- Strong magnetic pull
			adsBoost = {
				Friction = 1.5,
				Tracking = 1.4,
				Centering = 1.6,
			},
			adsSnap = {
				enabled = false, -- DISABLED - no snap, smooth pull only
				strength = 0,
				maxAngle = 0,
			},
		},
	},

	Shorty = {
		id = "Shorty",
		name = "Shorty",
		description = "Compact short-range secondary shotgun with two heavy shots.",
		imageId = "rbxassetid://88488566734338",
		weaponType = "Secondary",
		rarity = "Rare",
		instance = nil,
		skins = {},
		actions = {
			canQuickUseMelee = true,
			canQuickUseAblility = true,
		},
		maxAmmo = 20,
		clipSize = 2,
		reloadTime = 1.6,
		isAbility = false,
		fireProfile = {
			mode = "Shotgun",
			autoReloadOnEmpty = false,
			pelletsPerShot = 6,
			spread = 0.13,
		},

		speedMultiplier = 1.2,

		adsFOV = 55,
		adsSpeedMultiplier = 0.7,
		adsEffectsMultiplier = 0.25,

		damage = 20,
		pelletsPerShot = 6,
		headshotMultiplier = 1.35,
		range = 180,
		fireRate = 760,
		minRange = 5,
		maxRange = 120,
		minDamage = 4,
		tracerColor = Color3.fromRGB(255, 170, 90),
		
		-- Wall destruction (SHREDS walls - per pellet, uses cluster mode)
		destructionPressure = 50,

		recoil = {
			pitchUp = 7.25,
			yawRandom = 2.4,
			recoverySpeed = 7.5,
		},

		crosshair = {
			type = "DoubleBarrel",
			spreadX = 3.1,
			spreadY = 3.1,
			recoilMultiplier = 3.2,
			crouchMult = 0.55,
			sprintMult = 1.9,
			airMult = 2.2,
			adsMult = 0.45,
			baseGap = 9,
		},

		aimAssist = {
			enabled = false,
		},

		projectile = {
			speed = 600,
			gravity = 0,
			drag = 0,
			lifetime = 1,
			inheritVelocity = 0,

			spreadMode = "Cone",
			baseSpread = 0.055,
			crosshairSpreadScale = 0.03,
			movementSpreadMult = 1.15,
			hipfireSpreadMult = 1.0,
			airSpreadMult = 1.25,
			crouchSpreadMult = 0.9,
			slideSpreadMult = 1.0,

			pelletsPerShot = 6,
			pelletDamage = 20,

			minRange = 5,
			maxRange = 120,
			minDamage = 4,

			pierce = 0,
			pierceDamageMult = 1.0,
			ricochet = 0,
			ricochetDamageMult = 0.7,
			ricochetSpeedMult = 0.9,

			aoe = nil,
			charge = nil,

			visual = "Pellet",
			tracerColor = Color3.fromRGB(255, 170, 90),
			tracerLength = 2,
			trailEnabled = true,
		},
	},

	DualPistols = {
		id = "DualPistols",
		name = "Dual Pistols",
		description = "Dual sidearms that fire a tight 3-round burst with aggressive recoil and fast follow-up pressure.",
		imageId = "rbxassetid://96293877653846",
		weaponType = "Secondary",
		rarity = "Epic",
		instance = nil,
		skins = {},
		actions = {
			canQuickUseMelee = true,
			canQuickUseAblility = true,
		},
		maxAmmo = 64,
		clipSize = 16,
		reloadTime = 1.6,
		isAbility = false,
		fireProfile = {
			mode = "Semi",
			autoReloadOnEmpty = true,
			spread = 0.019,
		},
		burstProfile = {
			shots = 3,
			shotInterval = 0.07,
			burstCooldown = 0.24,
		},

		speedMultiplier = 1.28,

		damage = 15.5,
		headshotMultiplier = 1.5,
		range = 180,
		fireRate = 700,
		projectileSpeed = nil,
		bulletDrop = false,
		spread = 0.019,
		minRange = 14,
		maxRange = 220,
		minDamage = 9,
		tracerColor = Color3.fromRGB(255, 230, 170),
		
		-- Wall destruction (fast fire = lots of small holes)
		destructionPressure = 15,

			recoil = {
				pitchUp = 4.6,
				yawRandom = 0.9,
				recoverySpeed = 6.1,
			},

		crosshair = {
			type = "Default",
			spreadX = 1.85,
			spreadY = 1.85,
			recoilMultiplier = 2.35,
			crouchMult = 0.6,
			sprintMult = 1.8,
			airMult = 2.1,
			adsMult = 0.92,
			baseGap = 9,
		},

		aimAssist = {
			enabled = false,
		},
	},

	Tomahawk = {
		id = "Tomahawk",
		name = "Tomahawk",
		description = "A razor-sharp throwing axe that cuts through the air and your enemies. Lethal at close range, devastating from a distance.",
		imageId = "rbxassetid://75818313709174",
		weaponType = "Melee",
		rarity = "Epic",
		instance = nil,
		skins = {
			Cleaver = {
				id = "Cleaver",
				name = "Cleaver",
				description = "A brutal, oversized blade forged for one purpose—cleaving through anything in its path.",
				imageId = "rbxassetid://80948127232506",
				rarity = "Mythic",
				instance = nil,
				path = "Tomahawk_Cleaver",
			},
			ForestAxe = {
				id = "ForestAxe",
				name = "Forest Axe",
				description = "An ancient axe reclaimed from the deepest woods. Nature bends to its swing.",
				imageId = "rbxassetid://83918781392532",
				rarity = "Legendary",
				instance = nil,
				path = "Tomahawk_ForestAxe",
			},
			BasicAxe = {
				id = "BasicAxe",
				name = "Warden's Edge",
				description = "A battle-worn axe carried by the wardens of old. Simple, balanced, deadly.",
				imageId = "rbxassetid://117377765137152",
				rarity = "Rare",
				instance = nil,
				path = "Tomahawk_BsicAxe",
			},
		},
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
			-- Melee: minimal spread changes
			crouchMult = 0.8,
			sprintMult = 1.0,
			airMult = 1.0,
			adsMult = 1.0,
			baseGap = 8,
		},

		-- Aim Assist settings (tomahawk: light melee assist, no snap)
		aimAssist = {
			enabled = true,
			range = 15, -- Melee range only
			minRange = 0,
			fov = 60, -- Wide cone for melee
			sortingBehavior = "distance",
			friction = 0.3,
			tracking = 0.4,
			centering = 0.2,
			adsSnap = {
				enabled = false, -- No ADS for melee
			},
		},
	},

	ExecutionerBlade = {
		id = "ExecutionerBlade",
		name = "Executioner's Blade",
		description = "A devastating blade forged for swift judgment.",
		imageId = "rbxassetid://104262440201752", -- Using knife image temporarily
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
			-- Melee: minimal spread changes
			crouchMult = 0.8,
			sprintMult = 1.0,
			airMult = 1.0,
			adsMult = 1.0,
			baseGap = 8,
		},

		-- Aim Assist settings (blade: melee-focused, no snap)
		aimAssist = {
			enabled = true,
			range = 25, -- Melee range
			minRange = 0,
			fov = 55, -- Wide cone for melee
			sortingBehavior = "distance",
			friction = 0.4,
			tracking = 0.5,
			centering = 0.3,
			adsSnap = {
				enabled = false, -- No ADS for melee
			},
		},
	},
}

LoadoutConfig.Crosshair = {
	HideInADS = false,
	DefaultCustomization = {
		showDot = true,
		showTopLine = true,
		showBottomLine = true,
		showLeftLine = true,
		showRightLine = true,
		lineThickness = 2,
		lineLength = 6, -- Shorter lines for cleaner look
		gapFromCenter = 10, -- Wider gap - more spread out
		dotSize = 3, -- Small centered dot
		rotation = 0,
		cornerRadius = 0,
		mainColor = Color3.fromRGB(255, 255, 255),
		outlineColor = Color3.fromRGB(0, 0, 0),
		outlineThickness = 0, -- NO outline for cleaner look
		opacity = 0.95,
		scale = 1,
		dynamicSpreadEnabled = true,
	},
}

LoadoutConfig.Balance = {
	-- Global weapon damage tuning for guns only (Primary/Secondary).
	-- Set to 1 to disable scaling.
	GunDamageMultiplier = 0.85,
}

local function applyGlobalGunDamageBalance()
	local multiplier = LoadoutConfig.Balance and LoadoutConfig.Balance.GunDamageMultiplier or 1
	if type(multiplier) ~= "number" or multiplier <= 0 or multiplier == 1 then
		return
	end

	for _, weapon in pairs(LoadoutConfig.Weapons) do
		if weapon and (weapon.weaponType == "Primary" or weapon.weaponType == "Secondary") then
			if weapon.ignoreGlobalDamageMultiplier == true then
				continue
			end

			if type(weapon.damage) == "number" then
				weapon.damage = weapon.damage * multiplier
			end
			if type(weapon.minDamage) == "number" then
				weapon.minDamage = weapon.minDamage * multiplier
			end

			local projectile = weapon.projectile
			if type(projectile) == "table" then
				if type(projectile.pelletDamage) == "number" then
					projectile.pelletDamage = projectile.pelletDamage * multiplier
				end
				if type(projectile.minDamage) == "number" then
					projectile.minDamage = projectile.minDamage * multiplier
				end
			end
		end
	end
end

applyGlobalGunDamageBalance()

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
