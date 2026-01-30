--[[
	MatchmakingConfig
	
	Central configuration for the matchmaking and round system.
	Modify these values to tune queue behavior, match rules, and gamemodes.
]]

local MatchmakingConfig = {}

--------------------------------------------------------------------------------
-- QUEUE SETTINGS
--------------------------------------------------------------------------------

MatchmakingConfig.Queue = {
	-- Seconds to count down before match starts (when all pads occupied)
	CountdownDuration = 5,

	-- CollectionService tag for queue pads
	PadTag = "QueuePad",

	-- How often to check zone occupancy (seconds)
	ZoneCheckInterval = 0.2,

	-- Default detection zone size if pad doesn't have ZoneSize attribute
	DefaultZoneSize = Vector3.new(8, 10, 8),
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
-- MATCH / ROUND SETTINGS
--------------------------------------------------------------------------------

MatchmakingConfig.Match = {
	-- Score needed to win the match
	ScoreToWin = 5,

	-- Delay after a kill before showing loadout UI (seconds)
	RoundResetDelay = 2,

	-- Time for loadout selection between rounds (seconds)
	LoadoutSelectionTime = 15,

	-- Time on victory screen before returning to lobby (seconds)
	LobbyReturnDelay = 5,

	-- Whether to show loadout UI between rounds
	ShowLoadoutOnRoundReset = true,
}

--------------------------------------------------------------------------------
-- SPAWN TAGS
--------------------------------------------------------------------------------

MatchmakingConfig.Spawns = {
	-- Tag for Team 1 arena spawn points
	Team1Tag = "ArenaSpawn_Team1",

	-- Tag for Team 2 arena spawn points
	Team2Tag = "ArenaSpawn_Team2",

	-- Tag for lobby return spawn point
	LobbyTag = "LobbySpawn",
}

--------------------------------------------------------------------------------
-- GAMEMODES
--------------------------------------------------------------------------------

MatchmakingConfig.Gamemodes = {
	Duel = {
		name = "1v1 Duel",
		playersPerTeam = 1,
		teamCount = 2,
		scoreToWin = 5,
	},

	TwoVTwo = {
		name = "2v2",
		playersPerTeam = 2,
		teamCount = 2,
		scoreToWin = 10,
	},

	ThreeVThree = {
		name = "3v3",
		playersPerTeam = 3,
		teamCount = 2,
		scoreToWin = 15,
	},

	FourVFour = {
		name = "4v4",
		playersPerTeam = 4,
		teamCount = 2,
		scoreToWin = 20,
	},
}

-- Default gamemode when no specific one is selected
MatchmakingConfig.DefaultGamemode = "Duel"

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

function MatchmakingConfig.getGamemode(gamemodeId)
	return MatchmakingConfig.Gamemodes[gamemodeId or MatchmakingConfig.DefaultGamemode]
end

function MatchmakingConfig.getScoreToWin(gamemodeId)
	local gamemode = MatchmakingConfig.getGamemode(gamemodeId)
	return gamemode and gamemode.scoreToWin or MatchmakingConfig.Match.ScoreToWin
end

function MatchmakingConfig.getPlayersPerTeam(gamemodeId)
	local gamemode = MatchmakingConfig.getGamemode(gamemodeId)
	return gamemode and gamemode.playersPerTeam or 1
end

return MatchmakingConfig
