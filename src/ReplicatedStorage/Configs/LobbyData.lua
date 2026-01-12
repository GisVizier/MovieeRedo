local LobbyData = {}

LobbyData.Players = {
	[3227875212] = {
		displayName = "Player1",
		wins = 152,
		streak = 5,
		level = 45,
	},
	[9124290782] = {
		displayName = "Player2",
		wins = 89,
		streak = 2,
		level = 32,
	},
	[1565898941] = {
		displayName = "Player3",
		wins = 234,
		streak = 12,
		level = 67,
	},
	[204471960] = {
		displayName = "Player4",
		wins = 45,
		streak = 0,
		level = 18,
	},
}

function LobbyData.getPlayer(userId)
	return LobbyData.Players[userId]
end

function LobbyData.getPlayerWins(userId)
	local player = LobbyData.Players[userId]
	if player then
		return player.wins or 0
	end
	return 0
end

function LobbyData.getPlayerStreak(userId)
	local player = LobbyData.Players[userId]
	if player then
		return player.streak or 0
	end
	return 0
end

function LobbyData.getPlayerLevel(userId)
	local player = LobbyData.Players[userId]
	if player then
		return player.level or 1
	end
	return 1
end

function LobbyData.getAllPlayerIds()
	local ids = {}
	for userId in LobbyData.Players do
		table.insert(ids, userId)
	end
	return ids
end

function LobbyData.setPlayerData(userId, data)
	if not LobbyData.Players[userId] then
		LobbyData.Players[userId] = {}
	end

	for key, value in data do
		LobbyData.Players[userId][key] = value
	end
end

function LobbyData.addPlayer(userId, displayName, wins, streak, level)
	LobbyData.Players[userId] = {
		displayName = displayName or "Unknown",
		wins = wins or 0,
		streak = streak or 0,
		level = level or 1,
	}
end

function LobbyData.removePlayer(userId)
	LobbyData.Players[userId] = nil
end

return LobbyData
