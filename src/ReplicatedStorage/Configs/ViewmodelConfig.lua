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

		-- Melee (add when model exists)
		Knife = "Melee/Knife_Default",
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
		Animations = {
			Idle = "rbxassetid://116832822109675",
			Walk = "rbxassetid://116832822109675",  -- Reuse Idle
			Run = "rbxassetid://116832822109675",   -- Reuse Idle
			ZiplineHold = "rbxassetid://76927446014111",
			ZiplineHookUp = "rbxassetid://123241316387450",
			ZiplineFastHookUp = "rbxassetid://123241316387450",
		},
	},

	Shotgun = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.Shotgun,
		Offset = CFrame.new(-.2, -.15, -0.5),
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

	AssaultRifle = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.AssaultRifle,
		Offset = CFrame.new(0, 0, 0.5),
		Animations = {
			-- Placeholder animations (add real ones when available)
			Idle = "rbxassetid://0",
			Walk = "rbxassetid://0",
			Run = "rbxassetid://0",
			Equip = "rbxassetid://0",
			Inspect = "rbxassetid://0",
			Fire = "rbxassetid://0",
			Reload = "rbxassetid://0",
			ADS = "rbxassetid://0",
		},
	},

	Sniper = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.Sniper,
		Offset = CFrame.new(0, -0.3, .7) * CFrame.Angles(math.rad(5), math.rad(0), math.rad(-9)),
		Animations = {
			-- Using Animation instances from Assets/Animations/ViewModel/Sniper/Viewmodel/
			Idle = "Idle",
			Walk = "Walk",
			Run = "Run",
			Equip = "Equip",
			Inspect = "Inspect",
			Fire = "Fire",
			Reload = "Reload",
			ADS = "Idle",  -- Uses Idle pose for ADS (add dedicated ADS animation if available)
		},
	},

	Knife = {
		ModelPath = ViewmodelConfig.Models.ByWeaponId.Knife,
		Offset = CFrame.new(0, 0, 0),
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

return ViewmodelConfig
