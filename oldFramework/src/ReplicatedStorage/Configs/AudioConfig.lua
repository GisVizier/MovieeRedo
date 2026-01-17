local AudioConfig = {}

-- =============================================================================
-- SOUND IDS & ASSETS
-- =============================================================================

-- All sound asset IDs stored in one place for easy management
AudioConfig.SoundIds = {
	JumpPad = "rbxassetid://5356058949",
	LadderClimb = "rbxassetid://7131666931",
	LandingBoost = "rbxassetid://9120885468",
	
	FootstepPlastic = "rbxassetid://7326203155",
	
	FootstepGrass = "rbxassetid://507863105",
	FootstepMetal = "rbxassetid://6876957898",
	FootstepWood = "rbxassetid://507863457",
	FootstepConcite = "rbxassetid://5761648082",
	FootstepFabric = "rbxassetid://6240702531",
	FootstepSand = "rbxassetid://265653329",
	FootstepGlass = "rbxassetid://9117949159",
}

-- =============================================================================
-- SOUNDGROUP SETTINGS
-- =============================================================================

AudioConfig.Groups = {
	Music = {
		Volume = 0.7,
		Effects = {},
	},
	SFX = {
		Volume = 0.8,
		Effects = {},
	},
	Movement = {
		Volume = 0.6,
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

-- =============================================================================
-- SOUND DEFINITIONS
-- =============================================================================

AudioConfig.Sounds = {
	Movement = {
		-- Jump pad sound
		JumpPad = {
			Id = AudioConfig.SoundIds.JumpPad,
			Volume = 0.6,
			Pitch = 1.2,
			EmitterSize = 20,
			MinDistance = 10,
			MaxDistance = 60,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
		-- Ladder climbing sound
		LadderClimb = {
			Id = AudioConfig.SoundIds.LadderClimb,
			Volume = 0.4,
			Pitch = 1.0,
			EmitterSize = 15,
			MinDistance = 8,
			MaxDistance = 40,
			RollOffMode = Enum.RollOffMode.Linear,
			Looped = true, -- Should loop while climbing
			Effects = {},
		},
		-- Landing boost sound
		LandingBoost = {
			Id = AudioConfig.SoundIds.LandingBoost,
			Volume = 0.5,
			Pitch = 1.0,
			EmitterSize = 20,
			MinDistance = 10,
			MaxDistance = 50,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
		
		FootstepPlastic = {
			Id = AudioConfig.SoundIds.FootstepPlastic,
			Volume = 0.5,
			Pitch = 1.0,
			EmitterSize = 10,
			MinDistance = 5,
			MaxDistance = 30,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
		FootstepGrass = {
			Id = AudioConfig.SoundIds.FootstepGrass,
			Volume = 0.5,
			Pitch = 1.0,
			EmitterSize = 10,
			MinDistance = 5,
			MaxDistance = 30,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
		FootstepMetal = {
			Id = AudioConfig.SoundIds.FootstepMetal,
			Volume = 0.5,
			Pitch = 1.0,
			EmitterSize = 10,
			MinDistance = 5,
			MaxDistance = 30,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
		FootstepWood = {
			Id = AudioConfig.SoundIds.FootstepWood,
			Volume = 0.5,
			Pitch = 1.0,
			EmitterSize = 10,
			MinDistance = 5,
			MaxDistance = 30,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
		FootstepConcrete = {
			Id = AudioConfig.SoundIds.FootstepConcite,
			Volume = 0.5,
			Pitch = 1.0,
			EmitterSize = 10,
			MinDistance = 5,
			MaxDistance = 30,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
		FootstepFabric = {
			Id = AudioConfig.SoundIds.FootstepFabric,
			Volume = 0.4,
			Pitch = 1.0,
			EmitterSize = 10,
			MinDistance = 5,
			MaxDistance = 30,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
		FootstepSand = {
			Id = AudioConfig.SoundIds.FootstepSand,
			Volume = 0.5,
			Pitch = 1.0,
			EmitterSize = 10,
			MinDistance = 5,
			MaxDistance = 30,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
		FootstepGlass = {
			Id = AudioConfig.SoundIds.FootstepGlass,
			Volume = 0.4,
			Pitch = 1.0,
			EmitterSize = 10,
			MinDistance = 5,
			MaxDistance = 30,
			RollOffMode = Enum.RollOffMode.Linear,
			Effects = {},
		},
	},
}

AudioConfig.Footsteps = {
	Volume = 0.5,
	Factor = 8.1,
	CrouchFactor = 12.0,
	SprintFactor = 6.0,
	
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

-- =============================================================================
-- MASTER VOLUME SETTINGS
-- =============================================================================

AudioConfig.MasterVolume = 1.0

-- =============================================================================
-- PERFORMANCE SETTINGS
-- =============================================================================

AudioConfig.Performance = {
	-- Sound pool initial size per sound type
	InitialPoolSize = 3,
	-- Maximum sounds playing simultaneously per category
	MaxConcurrentSounds = {
		Movement = 8,
		SFX = 12,
		Music = 2,
		Voice = 4,
		UI = 6,
	},
	-- Distance culling - don't replicate sounds beyond this distance
	MaxReplicationDistance = 150,
	-- Rate limiting - max sound requests per player per second
	MaxSoundRequestsPerSecond = 10,
}

-- =============================================================================
-- REPLICATION SETTINGS
-- =============================================================================

AudioConfig.Replication = {
	-- Categories that should be replicated to other players
	ReplicatedCategories = {
		Movement = true,
		SFX = false, -- Most SFX are local-only
		Music = false, -- Music is typically synchronized differently
		Voice = true,
		UI = false, -- UI sounds are always local
	},
	-- Validation settings
	ValidatePlayerDistance = true, -- Check if player is in range before replicating
	RequireLineOfSight = false, -- Don't require line of sight for sound replication
}

return AudioConfig
