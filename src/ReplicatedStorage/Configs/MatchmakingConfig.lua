--[[
	MatchmakingConfig
	
	Central configuration for the matchmaking and round system.
	Supports both Training (infinite) and Competitive (lives) modes.
]]

local MatchmakingConfig = {}

--------------------------------------------------------------------------------
-- QUEUE SETTINGS (for competitive modes)
--------------------------------------------------------------------------------

MatchmakingConfig.Queue = {
	-- Seconds to count down before match starts (when all pads occupied)
	CountdownDuration = 5,

	-- CollectionService tag for queue pads
	PadTag = "QueuePad",

	-- How often to check zone occupancy (seconds)
	ZoneCheckInterval = 0.2,

	-- Default detection zone size if pad doesn't have ZoneSize attribute
	DefaultZoneSize = Vector3.new(8, 6, 8),

	-- Vertical tolerance (studs) for root-based checks
	VerticalTolerance = 10,

	-- Debug settings
	Debug = {
		ShowZones = false,
		ZoneColor = Color3.fromRGB(0, 200, 255),
		ZoneTransparency = 0.7,
	},
}

--------------------------------------------------------------------------------
-- PAD VISUALS
--------------------------------------------------------------------------------

MatchmakingConfig.PadVisuals = {
	-- Pad color when no player is standing on it
	EmptyColor = Color3.fromRGB(100, 100, 100),

	-- Pad color when a player is standing on it
	OccupiedColor = Color3.fromRGB(50, 200, 50),

	-- Pad color during countdown
	CountdownColor = Color3.fromRGB(255, 200, 50),

	-- Pad color when match is about to start
	ReadyColor = Color3.fromRGB(50, 150, 255),
}

--------------------------------------------------------------------------------
-- SPAWN TAGS
--------------------------------------------------------------------------------

MatchmakingConfig.Spawns = {
	-- Tag for Team 1 arena spawn points (competitive)
	Team1Tag = "ArenaSpawn_Team1",

	-- Tag for Team 2 arena spawn points (competitive)
	Team2Tag = "ArenaSpawn_Team2",

	-- Tag for training spawn points
	TrainingTag = "TrainingSpawn",

	-- Tag for lobby return spawn point
	LobbyTag = "LobbySpawn",
}

--------------------------------------------------------------------------------
-- MODES
-- Each mode defines how the round system behaves
--------------------------------------------------------------------------------

MatchmakingConfig.Modes = {
	-- Training: No teams, no scoring, respawn forever, join anytime
	Training = {
		name = "Training",
		hasTeams = false,
		hasScoring = false,
		allowJoinMidway = true,
		allowLoadoutReselect = true,
		respawnDelay = 2,
		returnToLobbyOnEnd = false,
	},

	-- Duel: 1v1, elimination rounds
	Duel = {
		name = "1v1 Duel",
		hasTeams = true,
		hasScoring = true,
		elimination = true,
		playersPerTeam = 1,
		scoreToWin = 5,
		allowJoinMidway = false,
		allowLoadoutReselect = false,
		mapSelectionTime = 20,
		loadoutSelectionTime = 15, -- Round 1: 15 seconds to pick loadout
		postKillDelay = 5, -- Seconds to wait after a kill before round reset begins
		roundResetDelay = 10, -- Between-round phase: 10 seconds to swap loadout
		roundDuration = 60, -- 1 minute per round before storm phase
		showMapSelection = true,
		showLoadoutOnMatchStart = true,
		showLoadoutOnRoundReset = false, -- Only reselect loadout on M key during between-round phase
		preserveUltOnRoundReset = true,
		earlyConfirmHalvesTimer = false, -- Disable halving - we use ready checks instead
		freezeDuringLoadout = true,
		freezeDuringRoundReset = true, -- Players can move/fight during between-round phase
		lobbyReturnDelay = 5,
		returnToLobbyOnEnd = true,
		-- Storm settings
		stormEnabled = true, -- Enable storm phase when round timer expires
		stormShrinkDuration = 45, -- Seconds for storm to fully close
		stormFinalRadius = 15, -- Final safe zone radius in studs
		stormDPS = 8, -- Damage per second while in storm
	},

	-- 2v2
	TwoVTwo = {
		name = "2v2",
		hasTeams = true,
		hasScoring = true,
		elimination = true,
		playersPerTeam = 2,
		scoreToWin = 5,
		allowJoinMidway = false,
		allowLoadoutReselect = false,
		mapSelectionTime = 20,
		loadoutSelectionTime = 15,
		postKillDelay = 5,
		roundResetDelay = 10,
		roundDuration = 60,
		showMapSelection = true,
		showLoadoutOnMatchStart = true,
		showLoadoutOnRoundReset = false,
		preserveUltOnRoundReset = true,
		earlyConfirmHalvesTimer = false,
		freezeDuringLoadout = true,
		freezeDuringRoundReset = true,
		lobbyReturnDelay = 5,
		returnToLobbyOnEnd = true,
		stormEnabled = true,
		stormShrinkDuration = 45,
		stormFinalRadius = 15,
		stormDPS = 8,
	},

	-- 3v3
	ThreeVThree = {
		name = "3v3",
		hasTeams = true,
		hasScoring = true,
		elimination = true,
		playersPerTeam = 3,
		scoreToWin = 5,
		allowJoinMidway = false,
		allowLoadoutReselect = false,
		mapSelectionTime = 20,
		loadoutSelectionTime = 15,
		postKillDelay = 5,
		roundResetDelay = 10,
		roundDuration = 60,
		showMapSelection = true,
		showLoadoutOnMatchStart = true,
		showLoadoutOnRoundReset = false,
		preserveUltOnRoundReset = true,
		earlyConfirmHalvesTimer = false,
		freezeDuringLoadout = true,
		freezeDuringRoundReset = true,
		lobbyReturnDelay = 5,
		returnToLobbyOnEnd = true,
		stormEnabled = true,
		stormShrinkDuration = 45,
		stormFinalRadius = 15,
		stormDPS = 8,
	},

	-- 4v4
	FourVFour = {
		name = "4v4",
		hasTeams = true,
		hasScoring = true,
		elimination = true,
		playersPerTeam = 4,
		scoreToWin = 5,
		allowJoinMidway = false,
		allowLoadoutReselect = false,
		mapSelectionTime = 20,
		loadoutSelectionTime = 15,
		postKillDelay = 5,
		roundResetDelay = 10,
		roundDuration = 60,
		showMapSelection = true,
		showLoadoutOnMatchStart = true,
		showLoadoutOnRoundReset = false,
		preserveUltOnRoundReset = true,
		earlyConfirmHalvesTimer = false,
		freezeDuringLoadout = true,
		freezeDuringRoundReset = true,
		lobbyReturnDelay = 5,
		returnToLobbyOnEnd = true,
		stormEnabled = true,
		stormShrinkDuration = 45,
		stormFinalRadius = 15,
		stormDPS = 8,
	},
}

-- Default mode
MatchmakingConfig.DefaultMode = "Duel"

--------------------------------------------------------------------------------
-- MODE NAME MAPPING
-- Maps queue pad names to mode IDs
--------------------------------------------------------------------------------

MatchmakingConfig.ModeNameMapping = {
	["1v1"] = "Duel",
	["2v2"] = "TwoVTwo",
	["3v3"] = "ThreeVThree",
	["4v4"] = "FourVFour",
}

--------------------------------------------------------------------------------
-- MAP POSITIONING
-- Settings for placing cloned maps far from lobby
--------------------------------------------------------------------------------

MatchmakingConfig.MapPositioning = {
	StartOffset = Vector3.new(5000, 0, 0),
	Increment = Vector3.new(2000, 0, 0),
	MaxConcurrentMaps = 10,
}

--------------------------------------------------------------------------------
-- MAP SELECTION
-- Default map for competitive matches
--------------------------------------------------------------------------------

MatchmakingConfig.DefaultMap = "Map"

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

function MatchmakingConfig.getMode(modeId)
	return MatchmakingConfig.Modes[modeId or MatchmakingConfig.DefaultMode]
end

function MatchmakingConfig.isTrainingMode(modeId)
	local mode = MatchmakingConfig.getMode(modeId)
	return mode and not mode.hasScoring
end

function MatchmakingConfig.isCompetitiveMode(modeId)
	local mode = MatchmakingConfig.getMode(modeId)
	return mode and mode.hasScoring
end

function MatchmakingConfig.getScoreToWin(modeId)
	local mode = MatchmakingConfig.getMode(modeId)
	return mode and mode.scoreToWin or 5
end

function MatchmakingConfig.getPlayersPerTeam(modeId)
	local mode = MatchmakingConfig.getMode(modeId)
	return mode and mode.playersPerTeam or 1
end

function MatchmakingConfig.getModeFromPadName(padName)
	return MatchmakingConfig.ModeNameMapping[padName] or MatchmakingConfig.DefaultMode
end

return MatchmakingConfig
