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
Settings.DebrisReset = 3

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

return Settings
