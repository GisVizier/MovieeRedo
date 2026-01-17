local RoundConfig = {}

-- =============================================================================
-- SYSTEM CONTROL
-- =============================================================================

RoundConfig.Enabled = false -- Set to false to disable round system entirely

-- =============================================================================
-- PHASE TIMERS (All in seconds)
-- =============================================================================

RoundConfig.Timers = {
	Intermission = 10, -- Lobby phase: wait for players, select map, convert to Runners, teleport
	RoundStart = 3, -- Countdown before round begins (players frozen on map)
	Round = 30, -- Active gameplay time (3 minutes)
	RoundEnd = 10, -- Results display before next round or intermission
}

-- =============================================================================
-- PLAYER REQUIREMENTS
-- =============================================================================

RoundConfig.Players = {
	MinPlayers = 2, -- Minimum players to start a match
	SmallMapThreshold = 8, -- Players <= this use Small maps, > this use Large maps
}

-- =============================================================================
-- MAP SELECTION SYSTEM
-- =============================================================================

RoundConfig.Maps = {
	-- Weight system
	BaseWeight = 100, -- Initial weight for all maps
	PlayedWeight = 20, -- Weight after being played
	WeightIncrement = 20, -- Added to non-played maps each round

	-- History tracking
	HistorySize = 4, -- Number of recent maps to track (last 3-5 recommended)

	-- Folder structure
	SmallMapsFolder = "Small", -- Folder name in ServerStorage.Maps
	LargeMapsFolder = "Large", -- Folder name in ServerStorage.Maps
}

-- =============================================================================
-- SPAWN CONFIGURATION
-- =============================================================================

RoundConfig.Spawns = {
	-- Lobby spawning (random positions on Spawn part)
	LobbySpawnHeightOffset = 1, -- Studs above Spawn part surface
	LobbySpawnRandomization = true, -- Randomize X/Z positions

	-- Map spawning (one spawn part per player)
	SpawnsFolderName = "Spawns", -- Folder in map model for player spawns
	GhostSpawnsFolderName = "GhostSpawns", -- Folder in map model for ghost spawns

	-- Spawn validation
	RequireUniqueSpawns = true, -- Each player gets different spawn
	FallbackToLobby = true, -- If map spawns fail, spawn in lobby
}

-- =============================================================================
-- ROUND GAMEPLAY
-- =============================================================================

RoundConfig.Gameplay = {
	-- Tagger selection
	TaggerRatio = 0.5, -- floor(runner_count * this) = tagger_count
	MinTaggers = 1, -- Minimum taggers per round
	MaxTaggers = nil, -- Maximum taggers (nil = no limit)

	-- Death/tagging behavior
	RespawnTaggedPlayers = false, -- Tagged players become ghosts, don't respawn
	GhostSpectateMode = true, -- Ghosts can spectate the round

	-- Round end conditions
	TimerEnd = true, -- Round ends when timer expires
	LastManStanding = true, -- Round ends when one runner remains
}

-- =============================================================================
-- DISCONNECT PROTECTION
-- =============================================================================

RoundConfig.DisconnectBuffer = {
	TrackingWindow = 30, -- Seconds to track recent disconnects
	CascadeThreshold = 3, -- Number of disconnects in window to predict more
	ThresholdBuffer = 1, -- Extra players above threshold before using larger map

	-- Phase-specific handling
	IntermissionRecalculate = true, -- Recalculate map continuously during intermission
	IntermissionLockPlayers = true, -- Lock participant list before teleport at end of intermission
	RoundTreatAsTagged = true, -- Disconnected runners count as tagged
}

-- =============================================================================
-- UI CONFIGURATION
-- =============================================================================

RoundConfig.UI = {
	ShowPhaseTimer = true, -- Display countdown timer
	ShowPlayerCounts = true, -- Show runner/tagger counts
	ShowMapName = true, -- Announce selected map
	ShowPlayerState = true, -- Display current state (Runner/Tagger/Ghost)

	-- Phase announcements
	AnnouncePhaseChanges = true,
	AnnounceMapSelection = true,
	AnnounceRoundResults = true,
}

-- =============================================================================
-- DEBUG SETTINGS
-- =============================================================================

RoundConfig.Debug = {
	LogPhaseTransitions = true,
	LogMapSelection = true,
	LogPlayerStateChanges = true,
	LogSpawnAssignments = true,
	SkipTimers = false, -- WARNING: Only for testing, skips all phase timers
}

return RoundConfig
