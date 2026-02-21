local Settings = {}

Settings.Tag = "Breakable"

Settings.OnClient = true
Settings.OnServer = true
Settings.RecordDestruction = true

Settings.ResetModel = false
Settings.ResetYields = false
Settings.ResetDefault = 60
Settings.ResetMinimum = 3

Settings.CutoutSize = 1
Settings.GridLock = false

Settings.DebrisContainer = game:GetService("Workspace")
Settings.DebrisDefaultBehavior = true
Settings.DebrisAnchored = false
Settings.DebrisReset = 0.5

Settings.Relativity = true
Settings.VoxelRelative = 1 / 8
Settings.VoxelDefault = 1
Settings.VoxelMinimum = 1
Settings.HitboxRelative = 1 / 3

Settings.GreedyMeshing = true
Settings.RunService = false
Settings.PartCache = true
Settings.CachePrecreated = 10000
Settings.CacheExtra = 100

Settings.DestructionSounds = {
	Enabled = true,
	Replicate = true,
	BaseVolume = 1.2,
	VolumeJitterMin = 1.15,
	VolumeJitterMax = 1.25,
	PlaybackSpeedMin = 1,
	PlaybackSpeedMax = 1.1,
	TimePositionMin = 0.05,
	TimePositionMax = 0.0715,
	RollOffMinDistance = 8,
	RollOffMaxDistanceMin = 65,
	RollOffMaxDistanceMax = 90,
	FadeOutDelayMin = 0.65,
	FadeOutDelayMax = 0.75,
	FadeOutTimeMin = 0.7,
	FadeOutTimeMax = 0.8,
	EmitterLifetime = 2,
	SmallCutoffVolume = 24,
	MinIntervalPerWall = 0.08,
	MinIntervalGlobal = 0.02,
	MaxConcurrentEmitters = 6,
	MaxEventsPerBatch = 4,
	Material = {
		Concrete = { Enabled = true, Volume = 1 },
		Wood = { Enabled = true, Volume = 1 },
		Metal = { Enabled = true, Volume = 1 },
		Dirt = { Enabled = true, Volume = 1 },
		Neon = { Enabled = true, Volume = 1 },
		Glass = { Enabled = true, Volume = 1 },
	},
}

return Settings
