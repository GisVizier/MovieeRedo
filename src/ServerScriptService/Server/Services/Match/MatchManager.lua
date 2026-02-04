--[[
	MatchManager
	
	Server-side service for managing multiple concurrent matches.
	Handles match creation, lifecycle, map allocation, and cleanup.
	
	API:
	- MatchManager:CreateMatch(options) -> matchId
	- MatchManager:EndMatch(matchId) -> void
	- MatchManager:GetMatch(matchId) -> matchData
	- MatchManager:GetMatchForPlayer(player) -> matchData
	- MatchManager:OnPlayerKilled(killer, victim) -> void
	- MatchManager:GetActiveMatches() -> { matchId = matchData, ... }
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))

local MatchManager = {}

function MatchManager:Init(registry, net)
	self._registry = registry
	self._net = net
	
	self._matches = {}
	
	self._positionPool = {}
	self._usedPositions = {}
	self:_initializePositionPool()
	
	self._playerToMatch = {}
	
	self:_setupPlayerRemoving()
	self:_setupNetworkEvents()
end

function MatchManager:Start()
end

function MatchManager:_initializePositionPool()
	local config = MatchmakingConfig.MapPositioning or {
		StartOffset = Vector3.new(5000, 0, 0),
		Increment = Vector3.new(2000, 0, 0),
		MaxConcurrentMaps = 10,
	}
	
	for i = 0, config.MaxConcurrentMaps - 1 do
		local position = config.StartOffset + (config.Increment * i)
		table.insert(self._positionPool, position)
	end
end

function MatchManager:_allocatePosition()
	if #self._positionPool == 0 then
		warn("[MatchManager] No positions available in pool")
		return nil
	end
	
	local position = table.remove(self._positionPool, 1)
	table.insert(self._usedPositions, position)
	return position
end

function MatchManager:_releasePosition(position)
	local index = table.find(self._usedPositions, position)
	if index then
		table.remove(self._usedPositions, index)
		table.insert(self._positionPool, position)
	end
end

function MatchManager:_setupPlayerRemoving()
	Players.PlayerRemoving:Connect(function(player)
		local match = self:GetMatchForPlayer(player)
		if match then
			self:_handlePlayerLeft(match.id, player)
		end
	end)
end

function MatchManager:_setupNetworkEvents()
	self._net:ConnectServer("PlayerDied", function(player)
		local match = self:GetMatchForPlayer(player)
		if match and match.state == "playing" then
			self:OnPlayerKilled(nil, player)
		end
	end)
	
	-- Handle client teleport confirmations
	self._net:ConnectServer("MatchTeleportReady", function(player, data)
		local matchId = data and data.matchId
		if not matchId then return end
		
		local match = self._matches[matchId]
		if not match then return end
		
		-- Remove from pending teleports
		if match._pendingTeleports then
			match._pendingTeleports[player] = nil
			
			-- Check if all players have teleported
			local pendingCount = 0
			for _ in match._pendingTeleports do
				pendingCount = pendingCount + 1
			end
			
			if pendingCount == 0 then
				self:_onAllPlayersTeleported(match)
			end
		end
	end)
	
	-- Handle loadout submissions for matches
	self._net:ConnectServer("SubmitLoadout", function(player, payload)
		local match = self:GetMatchForPlayer(player)
		if not match then return end
		
		-- Only process during loadout selection phase
		if match.state ~= "loadout_selection" then return end
		
		-- Mark player as ready
		if match._pendingLoadouts then
			match._pendingLoadouts[player] = nil
			
			-- Check if all players have submitted loadouts
			local pendingCount = 0
			for _ in match._pendingLoadouts do
				pendingCount = pendingCount + 1
			end
			
			if pendingCount == 0 then
				self:_onAllLoadoutsSubmitted(match)
			end
		end
	end)
end

function MatchManager:CreateMatch(options)
	local modeId = options.mode or "Duel"
	local modeConfig = MatchmakingConfig.getMode(modeId)
	
	if not modeConfig then
		warn("[MatchManager] Invalid mode:", modeId)
		return nil
	end
	
	local position = self:_allocatePosition()
	if not position then
		warn("[MatchManager] Failed to allocate map position")
		return nil
	end
	
	local mapLoader = self._registry:TryGet("MapLoader")
	if not mapLoader then
		warn("[MatchManager] MapLoaderService not found")
		self:_releasePosition(position)
		return nil
	end
	
	local mapId = options.mapId or "Map"
	local mapData = mapLoader:LoadMap(mapId, position)
	
	if not mapData then
		warn("[MatchManager] Failed to load map:", mapId)
		self:_releasePosition(position)
		return nil
	end
	
	local matchId = HttpService:GenerateGUID(false)
	
	local match = {
		id = matchId,
		mode = modeId,
		modeConfig = modeConfig,
		mapId = mapId,
		mapInstance = mapData.instance,
		mapPosition = position,
		spawns = mapData.spawns,
		
		state = "starting",
		currentRound = 1,
		
		team1 = options.team1 or {},
		team2 = options.team2 or {},
		
		scores = {
			Team1 = 0,
			Team2 = 0,
		},
		
		createdAt = tick(),
	}
	
	self._matches[matchId] = match
	
	for _, userId in match.team1 do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self._playerToMatch[player] = match
		end
	end
	for _, userId in match.team2 do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self._playerToMatch[player] = match
		end
	end
	
	-- Teleport players (client-side) - MatchStart will fire after all confirm
	self:_teleportPlayers(match)
	
	return matchId
end

function MatchManager:_onAllPlayersTeleported(match)
	if match.state ~= "starting" then
		return
	end
	
	local modeConfig = match.modeConfig
	
	-- Check if we need to show loadout selection before starting
	if modeConfig.showLoadoutOnMatchStart then
		match.state = "loadout_selection"
		
		-- Initialize pending loadouts tracking
		match._pendingLoadouts = {}
		
		-- Add all match players to pending loadouts
		for _, userId in match.team1 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				match._pendingLoadouts[player] = true
			end
		end
		for _, userId in match.team2 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				match._pendingLoadouts[player] = true
			end
		end
		
		-- Fire ShowRoundLoadout to match players only
		local loadoutDuration = modeConfig.loadoutSelectionTime or 15
		
		for _, userId in match.team1 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self._net:FireClient("ShowRoundLoadout", player, {
					matchId = match.id,
					duration = loadoutDuration,
					roundNumber = 1,
					isMatchStart = true,
				})
			end
		end
		for _, userId in match.team2 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self._net:FireClient("ShowRoundLoadout", player, {
					matchId = match.id,
					duration = loadoutDuration,
					roundNumber = 1,
					isMatchStart = true,
				})
			end
		end
		
		-- Timeout fallback - start match after loadout time expires even if not all submitted
		task.delay(loadoutDuration + 1, function()
			if match.state == "loadout_selection" then
				warn("[MatchManager] Loadout selection timeout - starting match")
				self:_onAllLoadoutsSubmitted(match)
			end
		end)
	else
		-- No loadout selection - start immediately
		self:_startMatchRound(match)
	end
end

function MatchManager:_onAllLoadoutsSubmitted(match)
	if match.state ~= "loadout_selection" then
		return
	end
	
	self:_startMatchRound(match)
end

function MatchManager:_startMatchRound(match)
	match.state = "playing"
	match._pendingLoadouts = nil
	
	self._net:FireAllClients("MatchStart", {
		matchId = match.id,
		mode = match.mode,
		team1 = match.team1,
		team2 = match.team2,
	})
	
	self:_fireRoundStart(match)
end

function MatchManager:EndMatch(matchId, winnerTeam)
	local match = self._matches[matchId]
	if not match then
		return
	end
	
	match.state = "ended"
	
	local winnerId = nil
	if winnerTeam == "Team1" and #match.team1 > 0 then
		winnerId = match.team1[1]
	elseif winnerTeam == "Team2" and #match.team2 > 0 then
		winnerId = match.team2[1]
	end
	
	self._net:FireAllClients("MatchEnd", {
		matchId = matchId,
		winnerTeam = winnerTeam,
		winnerId = winnerId,
		finalScores = {
			Team1 = match.scores.Team1,
			Team2 = match.scores.Team2,
		},
	})
	
	local lobbyReturnDelay = match.modeConfig.lobbyReturnDelay or 5
	task.delay(lobbyReturnDelay, function()
		self:_cleanupMatch(matchId)
	end)
end

function MatchManager:_cleanupMatch(matchId)
	local match = self._matches[matchId]
	if not match then
		return
	end
	
	self:_returnPlayersToLobby(match)
	
	for _, userId in match.team1 do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self._playerToMatch[player] = nil
		end
	end
	for _, userId in match.team2 do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self._playerToMatch[player] = nil
		end
	end
	
	local mapLoader = self._registry:TryGet("MapLoader")
	if mapLoader and match.mapInstance then
		mapLoader:UnloadMap(match.mapInstance)
	end
	
	self:_releasePosition(match.mapPosition)
	
	self._matches[matchId] = nil
	
	self._net:FireAllClients("ReturnToLobby", {
		matchId = matchId,
	})
end

function MatchManager:GetMatch(matchId)
	return self._matches[matchId]
end

function MatchManager:GetMatchForPlayer(player)
	return self._playerToMatch[player]
end

function MatchManager:GetActiveMatches()
	return self._matches
end

function MatchManager:GetPlayerTeam(match, player)
	if not match or not player then
		return nil
	end
	
	local userId = player.UserId
	
	if table.find(match.team1, userId) then
		return "Team1"
	elseif table.find(match.team2, userId) then
		return "Team2"
	end
	
	return nil
end

function MatchManager:OnPlayerKilled(killerPlayer, victimPlayer)
	local match = self:GetMatchForPlayer(victimPlayer)
	if not match or match.state ~= "playing" then
		return
	end
	
	local modeConfig = match.modeConfig
	
	self._net:FireAllClients("RoundKill", {
		matchId = match.id,
		killerId = killerPlayer and killerPlayer.UserId or nil,
		victimId = victimPlayer.UserId,
	})
	
	if modeConfig.hasScoring then
		local killerTeam = killerPlayer and self:GetPlayerTeam(match, killerPlayer) or nil
		
		if not killerTeam then
			local victimTeam = self:GetPlayerTeam(match, victimPlayer)
			if victimTeam == "Team1" then
				killerTeam = "Team2"
			else
				killerTeam = "Team1"
			end
		end
		
		if killerTeam then
			match.scores[killerTeam] = match.scores[killerTeam] + 1
			
			self._net:FireAllClients("ScoreUpdate", {
				matchId = match.id,
				team1Score = match.scores.Team1,
				team2Score = match.scores.Team2,
			})
			
			if self:_checkWinCondition(match) then
				self:EndMatch(match.id, killerTeam)
			else
				self:_resetRound(match)
			end
		end
	end
end

function MatchManager:_checkWinCondition(match)
	local scoreToWin = match.modeConfig.scoreToWin or 5
	return match.scores.Team1 >= scoreToWin or match.scores.Team2 >= scoreToWin
end

function MatchManager:_resetRound(match)
	match.state = "resetting"
	match.currentRound = match.currentRound + 1
	
	local resetDelay = match.modeConfig.roundResetDelay or 2
	
	task.delay(resetDelay, function()
		if not self._matches[match.id] then
			return
		end
		
		self:_teleportPlayers(match)
		
		if match.modeConfig.showLoadoutOnRoundReset then
			self._net:FireAllClients("ShowRoundLoadout", {
				matchId = match.id,
				duration = match.modeConfig.loadoutSelectionTime or 15,
				scores = {
					Team1 = match.scores.Team1,
					Team2 = match.scores.Team2,
				},
				roundNumber = match.currentRound,
			})
			
			local loadoutTime = match.modeConfig.loadoutSelectionTime or 15
			task.delay(loadoutTime, function()
				if self._matches[match.id] and match.state == "resetting" then
					match.state = "playing"
					self:_fireRoundStart(match)
				end
			end)
		else
			match.state = "playing"
			self:_fireRoundStart(match)
		end
	end)
end

function MatchManager:_fireRoundStart(match)
	self._net:FireAllClients("RoundStart", {
		matchId = match.id,
		roundNumber = match.currentRound,
		scores = match.modeConfig.hasScoring and {
			Team1 = match.scores.Team1,
			Team2 = match.scores.Team2,
		} or nil,
	})
end

function MatchManager:_teleportPlayers(match)
	local spawn1 = match.spawns.Team1
	local spawn2 = match.spawns.Team2
	
	-- Initialize pending teleports tracking
	match._pendingTeleports = {}
	
	if spawn1 then
		for _, userId in match.team1 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:_requestPlayerTeleport(match, player, spawn1, "Team1")
			end
		end
	end
	
	if spawn2 then
		for _, userId in match.team2 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:_requestPlayerTeleport(match, player, spawn2, "Team2")
			end
		end
	end
	
	-- Timeout fallback - start match after 3 seconds even if clients don't confirm
	task.delay(3, function()
		if match._pendingTeleports then
			local pendingCount = 0
			for _ in match._pendingTeleports do
				pendingCount = pendingCount + 1
			end
			
			if pendingCount > 0 then
				warn("[MatchManager] Teleport timeout - starting match with", pendingCount, "pending teleports")
				match._pendingTeleports = {}
				self:_onAllPlayersTeleported(match)
			end
		end
	end)
end

function MatchManager:_requestPlayerTeleport(match, player, spawn, teamName)
	local spawnCFrame
	if spawn:IsA("SpawnLocation") or spawn:IsA("BasePart") then
		spawnCFrame = spawn.CFrame + Vector3.new(0, 3, 0)
	else
		spawnCFrame = CFrame.new(spawn.Position + Vector3.new(0, 3, 0))
	end
	
	-- Track this player as pending teleport
	match._pendingTeleports[player] = true
	
	-- Fire teleport event to client (signature: name, player, data)
	self._net:FireClient("MatchTeleport", player, {
		matchId = match.id,
		mode = match.mode,
		team = teamName,
		spawnPosition = spawnCFrame.Position,
		spawnLookVector = spawnCFrame.LookVector,
	})
	
	-- Also heal the player on server side
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	end
end

-- Legacy function for round resets and lobby returns (still uses server-side for simplicity)
function MatchManager:_teleportPlayerToSpawn(player, spawn)
	local spawnCFrame
	if spawn:IsA("SpawnLocation") or spawn:IsA("BasePart") then
		spawnCFrame = spawn.CFrame + Vector3.new(0, 3, 0)
	else
		spawnCFrame = CFrame.new(spawn.Position + Vector3.new(0, 3, 0))
	end
	
	-- Fire teleport event to client (for round resets too)
	self._net:FireClient("MatchTeleport", player, {
		matchId = "reset",
		spawnPosition = spawnCFrame.Position,
		spawnLookVector = spawnCFrame.LookVector,
	})
	
	-- Heal player
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	end
end

function MatchManager:_returnPlayersToLobby(match)
	local lobbySpawns = game:GetService("CollectionService"):GetTagged(MatchmakingConfig.Spawns.LobbyTag)
	
	if #lobbySpawns == 0 then
		warn("[MatchManager] No lobby spawns found")
		return
	end
	
	local allUserIds = {}
	for _, userId in match.team1 do
		table.insert(allUserIds, userId)
	end
	for _, userId in match.team2 do
		table.insert(allUserIds, userId)
	end
	
	for i, userId in allUserIds do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local spawnIndex = ((i - 1) % #lobbySpawns) + 1
			local spawn = lobbySpawns[spawnIndex]
			self:_teleportPlayerToSpawn(player, spawn)
		end
	end
end

function MatchManager:_handlePlayerLeft(matchId, player)
	local match = self._matches[matchId]
	if not match then
		return
	end
	
	self._playerToMatch[player] = nil
	
	local userId = player.UserId
	
	local index1 = table.find(match.team1, userId)
	if index1 then
		table.remove(match.team1, index1)
	end
	
	local index2 = table.find(match.team2, userId)
	if index2 then
		table.remove(match.team2, index2)
	end
	
	self._net:FireAllClients("PlayerLeftMatch", {
		matchId = matchId,
		playerId = userId,
	})
	
	if match.state == "playing" or match.state == "resetting" then
		if #match.team1 == 0 and #match.team2 > 0 then
			self:EndMatch(matchId, "Team2")
		elseif #match.team2 == 0 and #match.team1 > 0 then
			self:EndMatch(matchId, "Team1")
		elseif #match.team1 == 0 and #match.team2 == 0 then
			self:_cleanupMatch(matchId)
		end
	end
end

return MatchManager
