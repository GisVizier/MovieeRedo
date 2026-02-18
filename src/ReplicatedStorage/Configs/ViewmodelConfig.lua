--[[
	ViewmodelConfig.lua

	Central configuration for first-person-only viewmodels.
	- Maps weapon IDs (LoadoutConfig) -> model paths under ReplicatedStorage.Assets.ViewModels
	- Defines per-weapon offsets, animation asset IDs, and effect tuning.

	Notes:
	- All animation IDs are placeholders unless you set them.
	- Ability/Ultimate currently reuse the Fists viewmodel and play kit-defined animations when present.
]]

local ViewmodelConfig = {}

-- Root location: ReplicatedStorage.Assets.ViewModels
-- ModelPath format: "Folder/ModelName" (nested folders allowed)
ViewmodelConfig.Models = {
	Fists = "Fist/Fist_Default",
	ByWeaponId = {
		-- Weapons (from LoadoutConfig)
		Shotgun = "Shotguns/Shotgun_Default",
		Sniper = "Snipers/SniperRifle_Default",
		AssaultRifle = "Rifles/AssaultRifle_Default",
		Revolver = "Revolver/Revolver_Default",
		Shorty = "Shorty/Shorty_Default",
		DualPistols = "DualPistols/DaulPistols_Default",

		-- Melee (add when model exists)
		Tomahawk = "Melee/Tomahawk_Default", -- Uses knife model/animations
		ExecutionerBlade = "Melee/ExecutionerBlade_Default",
	},
}

-- Global offsets/effects (feel). Keep these minimal; tune per weapon via Weapons[weaponId].Effects.
ViewmodelConfig.Effects = {
	MouseSway = {
		Enabled = true,
		MouseSensitivity = 0.15,
		MaxAngleDeg = 12,
		ReturnSpeed = 14,
	},

	MovementSmoothing = {
		SpeedSmoothness = 12,
		DirectionSmoothness = 14,
		BobBlendSpeed = 10,
		MoveStartSpeed = 1.25,
		MoveStopSpeed = 0.75,
	},

	WalkBob = {
		Enabled = true,
		Amplitude = Vector3.new(0.035, 0.045, 0),
		Frequency = 6,
	},

	RunBob = {
		Enabled = true,
		Amplitude = Vector3.new(0.05, 0.1, 0),
		Frequency = 9,
	},

	SlideTilt = {
		Enabled = true,
		AngleDeg = 18, -- roll
		Offset = Vector3.new(0.14, -0.12, 0.06),
		RotationDeg = Vector3.new(8, 30, 0), -- Y = 30 degrees turn right
		TransitionSpeed = 10,
	},

	Impulse = {
		Enabled = true,
		Stiffness = 80,
		Damping = 18,
		MaxOffset = 0.22,
		SlideKick = Vector3.new(0, -0.05, 0.06),
		JumpCancelKick = Vector3.new(0, 0.08, 0.12),
	},
}

-- Per-weapon viewmodel settings.
-- Each entry is optional; missing fields fall back to sane defaults in code.
ViewmodelConfig.Weapons = {
	Fists = {
		ModelPath = ViewmodelConfig.Models.Fists,
		Offset = CFrame.new(0, 0, 0),
		Replication = {
			Scale = 1,
			Offset = CFrame.new(0, 0, 0.65),
			LeftAttachment = CFrame.new(-1, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)),
			RightAttachment = CFrame.new(1, 0.5, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		},
		Animations = {
			Idle = "rbxassetid://116832822109675",
			Walk = "rbxassetid://116832822109675", -- Reuse Idle
			Run = "rbxassetid://116832822109675", -- Reuse Idle
			ZiplineHold = "rbxassetid://76927446014111",
			ZiplineHookUp = "rbxassetid://123241316387450",
			ZiplineFastHookUp = "rbxassetid://123241316387450",
		},
	},

	Shotgun = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.Shotgun,
		Offset = CFrame.new(-0.2, -0.15, -0.5),
		Replication = {
			Scale = 0.475,
			Offset = CFrame.new(),
			LeftAttachment = CFrame.new(-1, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)),
			RightAttachment = CFrame.new(1, 0.5, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		},
		Animations = {
			-- Using Animation instances from Assets/Animations/ViewModel/Shotgun/Viewmodel/
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			ADS = "Aim", -- Maps to your "Aim" animation
			Fire = "Fire",
			-- Reload = "Reload",
			Equip = "Equip",
			Start = "Start",
			Action = "Action",
			End = "End",
			Inspect = "Inspect",
		},
	},

	Revolver = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.Revolver,
		Offset = CFrame.new(0, 0, 0.4),
		Replication = {
			Scale = 0.5725,
			Offset = CFrame.new(),
			LeftAttachment = CFrame.new(-1, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)),
			RightAttachment = CFrame.new(1, 0.5, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		},
		Animations = {
			-- Using legacy asset IDs (can be migrated to Animation instances later)
			Idle = "rbxassetid://109130838280246",
			Walk = "rbxassetid://109130838280246",
			Run = "rbxassetid://70374674712630",
			ADS = "rbxassetid://109130838280246",
			Fire = "rbxassetid://116676760515163",
			Reload = "rbxassetid://128494876463082",
			Equip = "rbxassetid://0",
			Inspect = "rbxassetid://129139579437341",
		},
	},

	Shorty = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.Shorty,
		Offset = CFrame.new(-0.2, -0.15, -0.5),
		Replication = {
			Scale = 0.5725,
			Offset = CFrame.new(),
			LeftAttachment = CFrame.new(-1, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)),
			RightAttachment = CFrame.new(1, 0.5, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		},
		Animations = {
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			ADS = "Aim",
			Fire = "Fire",
			Equip = "Equip",
			Reload1 = "Reload1",
			Reload2 = "Reload2",
			Inspect = "Inspect",
		},
		Sounds = {
			Equip = "rbxassetid://105676081627742",
			Inspect = "rbxassetid://83079135649283",
			Fire = "rbxassetid://97613244290752",
			Reload1 = "rbxassetid://136295131631464",
			Reload2 = "rbxassetid://102765790878168",
			Special = "rbxassetid://125241317241678",
		},
	},

	DualPistols = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.DualPistols,
		Offset = CFrame.new(0, -0.12, -0.35),

		Replication = {
			Scale = 0.5725,
			Offset = CFrame.new(0, 0, 0.756),

			LeftAttachment = CFrame.new(-1, 0.5, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
			RightAttachment = CFrame.new(1.15, 0.5, -0.25) * CFrame.Angles(0, 0, math.rad(90)),
		},
		Animations = {
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			Fire1 = "Fire1",
			Fire2 = "Fire2",
			SpecailLeft = "SpecailLeft",
			SpecailRight = "SpecailRight",
			SpecailLeftFire = "SpecailLeftFire",
			SpecailRightFire = "SpecailRightFire",
			Reload = "Reload",
			Equip = "Equip",
			Inspect = "Inspect",
			Inspect2 = "Inspect2",
		},
		Sounds = {
			Equip = "rbxassetid://138534048244630",
			Inspect = "rbxassetid://126105109221911",
			Inspect2 = "rbxassetid://134105504947632",
			Reload = "rbxassetid://84543989926006",
			Fire = "rbxassetid://83734415633853",
		},
	},

	AssaultRifle = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.AssaultRifle,
		Offset = CFrame.new(0, 0, 0.15),
		Replication = {
			Scale = 0.5725,
			Offset = CFrame.new(0, 0, 0.85),

			LeftAttachment = CFrame.new(-1, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)),
			RightAttachment = CFrame.new(1, 0.5, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		},
		Animations = {
			-- Using Animation instances from Assets/Animations/ViewModel/Shotgun/Viewmodel/
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			ADS = "Aim", -- Maps to your "Aim" animation
			Fire = "Fire",
			Reload = "Reload",
			Equip = "Equip",
			--Start = "Start",
			--Action = "Action",
			--End = "End",
			Inspect = "Inspect",
		},
		Sounds = {
			Equip = "rbxassetid://120459334890171",
			AimIn = "rbxassetid://92425294852292",
			AimOut = "rbxassetid://104612592617107",
			Reload = "rbxassetid://112402862376895",
			Inspect = "rbxassetid://101418042135086",
			Fire = "rbxassetid://139606755957140",
		},
	},

	Sniper = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.Sniper,
		Offset = CFrame.new(0, -0.3, 0.7) * CFrame.Angles(math.rad(5), math.rad(0), math.rad(-9)),
		Replication = {
			Scale = 0.5725,
			Offset = CFrame.new(),
			LeftAttachment = CFrame.new(-1, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)),
			RightAttachment = CFrame.new(1, 0.5, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		},
		Animations = {
			-- Using Animation instances from Assets/Animations/ViewModel/Sniper/Viewmodel/
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			Equip = "Equip",
			Inspect = "Inspect",
			Fire = "Fire",
			Reload = "Reload",
			ADS = "Idle", -- Uses Idle pose for ADS (add dedicated ADS animation if available)
		},
	},

	Tomahawk = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.Tomahawk,
		Offset = CFrame.new(0, 0, 0),
		Replication = {
			Scale = 0.5725,
			Offset = CFrame.new(),
			LeftAttachment = CFrame.new(-1, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)),
			RightAttachment = CFrame.new(1, 0.5, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		},
		Animations = {
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			Inspect = "Inspect",
			-- Attack = "Attack",
			-- Special = "Special",
			Equip = "Equip",
		},
	},

	ExecutionerBlade = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.ExecutionerBlade,
		Offset = CFrame.new(0, 0, 0),
		Replication = {
			Scale = 0.5725,
			Offset = CFrame.new(),
			LeftAttachment = CFrame.new(-1, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)),
			RightAttachment = CFrame.new(1, 0.5, 0.5) * CFrame.Angles(0, 0, math.rad(90)),
		},
		Animations = {
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			Inspect = "Inspect",
			Equip = "Equip",
			Slash1 = "Slash1",
			Slash2 = "Slash2",
		},
	},
}

-- Kit animations (played on fists viewmodel).
-- Keep names generic (Moviee-style) to stay flexible:
-- Ability: "Charge" -> on Begin, "Release" -> on End
-- Ultimate: "Activate" -> on Begin, optionally also on End
ViewmodelConfig.Kits = {
	-- Pulled from Moviee-Proj: Kits/WhiteBeard/Config.lua
	WhiteBeard = {
		Ability = {
			Charge = "rbxassetid://117704637566986",
			Release = "rbxassetid://122490395544502",
		},
		Ultimate = {
			Activate = "rbxassetid://116014965112574",
		},
	},
}

--[[
	Skin overrides for viewmodels.
	Skins can override ModelPath, Animations, and Sounds from the base weapon config.
	Only specify properties that change - rest inherited from base weapon.

	Animation lookup order:
	1. ViewmodelConfig.Skins[WeaponId][SkinId].Animations[AnimName] (if defined)
	2. Assets/Animations/ViewModel/{WeaponId}/{SkinId}/{AnimName} (skin folder)
	3. ViewmodelConfig.Weapons[WeaponId].Animations[AnimName] (base weapon config)
	4. Assets/Animations/ViewModel/{WeaponId}/Viewmodel/{AnimName} (base folder)

	This allows skins to:
	- Use custom models with default animations (just set ModelPath)
	- Use custom animations with default model (just set Animations)
	- Use both custom model and animations (set both)
	- Only override specific animations (partial Animations table)
	- Override specific sounds (partial Sounds table)
]]
ViewmodelConfig.Skins = {
	Shotgun = {
		OGPump = {
			-- OG Pump model under Shotguns folder
			ModelPath = "Shotguns/OGPump",
		},
	},

	Tomahawk = {
		Cleaver = {
			ModelPath = "Melee/Tomahawk_Cleaver",
		},
		ForestAxe = {
			ModelPath = "Melee/Tomahawk_ForestAxe",
		},
		BasicAxe = {
			ModelPath = "Melee/Tomahawk_BsicAxe",
		},
	},
}

return ViewmodelConfig
