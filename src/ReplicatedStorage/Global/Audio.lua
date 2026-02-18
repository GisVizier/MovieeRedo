local Audio = {}

Audio.SoundIds = {
	Jump = "rbxassetid://78776477559246",
	Land = "rbxassetid://81823741300483",
	Falling = "rbxassetid://76517117304992",
	Crouch = "rbxassetid://98414795058042",
	Slide = "rbxassetid://102823249876612",
	SlideLaunch = "rbxassetid://92797238261614",
	WallJump = "rbxassetid://92914028303623",

	FootstepPlastic = "rbxassetid://7326203155",
	-- Temporary fallback while 507863105 is inaccessible to this experience.
	FootstepGrass = "rbxassetid://7326203155",
	FootstepMetal = "rbxassetid://6876957898",
	FootstepWood = "rbxassetid://507863457",
	FootstepConcrete = "rbxassetid://5761648082",
	FootstepFabric = "rbxassetid://6240702531",
	FootstepSand = "rbxassetid://265653329",
	FootstepGlass = "rbxassetid://9117949159",
}

Audio.Sounds = {
	Movement = {
		Jump = { Id = Audio.SoundIds.Jump, Volume = 0.3, Pitch = 1.0 },
		Land = { Id = Audio.SoundIds.Land, Volume = 0.6, Pitch = 1.0 },
		Falling = { Id = Audio.SoundIds.Falling, Volume = 0.6, Pitch = 1.0 },
		Crouch = { Id = Audio.SoundIds.Crouch, Volume = 0.5, Pitch = 1.0 },
		Slide = { Id = Audio.SoundIds.Slide, Volume = 0.6, Pitch = 1.0 },
		SlideLaunch = { Id = Audio.SoundIds.SlideLaunch, Volume = 0.6, Pitch = 1.0 },
		WallJump = { Id = Audio.SoundIds.WallJump, Volume = 0.6, Pitch = 1.0 },

		FootstepPlastic = {
			Id = Audio.SoundIds.FootstepPlastic,
			Volume = 0.2,
			Pitch = 1.0,
			MinDistance = 5,
			MaxDistance = 50,
		},
		FootstepGrass = {
			Id = Audio.SoundIds.FootstepGrass,
			Volume = 0.2,
			Pitch = 1.0,
			MinDistance = 5,
			MaxDistance = 50,
		},
		FootstepMetal = {
			Id = Audio.SoundIds.FootstepMetal,
			Volume = 0.2,
			Pitch = 1.0,
			MinDistance = 5,
			MaxDistance = 50,
		},
		FootstepWood = {
			Id = Audio.SoundIds.FootstepWood,
			Volume = 0.2,
			Pitch = 1.0,
			MinDistance = 5,
			MaxDistance = 50,
		},
		FootstepConcrete = {
			Id = Audio.SoundIds.FootstepConcrete,
			Volume = 0.2,
			Pitch = 1.0,
			MinDistance = 5,
			MaxDistance = 50,
		},
		FootstepFabric = {
			Id = Audio.SoundIds.FootstepFabric,
			Volume = 0.16,
			Pitch = 1.0,
			MinDistance = 5,
			MaxDistance = 50,
		},
		FootstepSand = {
			Id = Audio.SoundIds.FootstepSand,
			Volume = 0.2,
			Pitch = 1.0,
			MinDistance = 5,
			MaxDistance = 50,
		},
		FootstepGlass = {
			Id = Audio.SoundIds.FootstepGlass,
			Volume = 0.16,
			Pitch = 1.0,
			MinDistance = 5,
			MaxDistance = 50,
		},
	},
}

Audio.Groups = {
	Movement = {
		Volume = 0.6,
		Effects = {},
	},
	SFX = {
		Volume = 0.8,
		Effects = {},
	},
	Music = {
		Volume = 0.7,
		Effects = {},
	},
	Voice = {
		Volume = 1.0,
		Effects = {},
	},
	UI = {
		Volume = 0.5,
		Effects = {},
	},
}

Audio.Footsteps = {
	Factor = 8.1,
	CrouchFactor = 12.0,
	SprintFactor = 6.0,
	MinSpeed = 2,

	MaterialMap = {
		Plastic = "FootstepPlastic",
		SmoothPlastic = "FootstepPlastic",
		ForceField = "FootstepPlastic",
		Foil = "FootstepPlastic",

		Wood = "FootstepWood",
		WoodPlanks = "FootstepWood",

		Ground = "FootstepFabric",
		Fabric = "FootstepFabric",
		Carpet = "FootstepFabric",

		Metal = "FootstepMetal",
		DiamondPlate = "FootstepMetal",
		CorrodedMetal = "FootstepMetal",

		Grass = "FootstepGrass",
		LeafyGrass = "FootstepGrass",
		Mud = "FootstepGrass",
		Snow = "FootstepGrass",
		Glacier = "FootstepGrass",

		Concrete = "FootstepConcrete",
		Pavement = "FootstepConcrete",
		Limestone = "FootstepConcrete",
		Salt = "FootstepConcrete",
		Asphalt = "FootstepConcrete",
		Neon = "FootstepConcrete",
		CrackedLava = "FootstepConcrete",
		Basalt = "FootstepConcrete",
		Sandstone = "FootstepConcrete",
		Rock = "FootstepConcrete",
		Cobblestone = "FootstepConcrete",
		Pebble = "FootstepConcrete",
		Brick = "FootstepConcrete",
		Granite = "FootstepConcrete",
		Marble = "FootstepConcrete",
		Ice = "FootstepConcrete",
		Slate = "FootstepConcrete",

		Sand = "FootstepSand",
		Glass = "FootstepGlass",
	},

	DefaultSound = "FootstepConcrete",
}

return Audio
