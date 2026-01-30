--[[
	RoundService
	
	Server-side service for managing match rounds and scoring.
	
	Features:
	- Round loop management (first to X kills)
	- Score tracking per team
	- Player spawning at arena spawn points
	- Loadout selection between rounds
	- Match end and lobby return
	
	API:
	- RoundService:CreateMatch(matchData) -> void
	- RoundService:GetActiveMatch() -> matchData or nil
	- RoundService:GetScores() -> { Team1 = n, Team2 = n }
	- RoundService:OnPlayerKilled(killer, victim) -> void
	- RoundService:EndMatch(reason) -> void
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))

local RoundService = {}

function RoundService:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Active match state
	self._activeMatch = nil

	-- Listen for player death events
	self:_setupDeathListener()
end

function RoundService:Start() end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function RoundService:CreateMatch(matchData)
	if self._activeMatch then
		warn("[RoundService] Match already in progress, cannot create new match")
		return
	end

	local gamemodeId = matchData.gamemodeId or MatchmakingConfig.DefaultGamemode
	local gamemode = MatchmakingConfig.getGamemode(gamemodeId)

	self._activeMatch = {
		team1 = matchData.team1, -- { userId1, userId2, ... }
		team2 = matchData.team2,
		gamemodeId = gamemodeId,
		scoreToWin = gamemode.scoreToWin,
		scores = {
			Team1 = 0,
			Team2 = 0,
		},
		currentRound = 0,
		mapId = nil, -- Set after map selection
		state = "mapSelect", -- mapSelect, loadout, playing, ended
	}

	-- Map selection happens via existing UI flow
	-- The client will fire SubmitLoadout which includes mapId
	-- For now, we wait for loadout completion to start the round
end

function RoundService:GetActiveMatch()
	return self._activeMatch
end

function RoundService:GetScores()
	if not self._activeMatch then
		return nil
	end
	return {
		Team1 = self._activeMatch.scores.Team1,
		Team2 = self._activeMatch.scores.Team2,
	}
end

function RoundService:IsPlayerInMatch(player)
	if not self._activeMatch then
		return false
	end

	local userId = player.UserId
	return table.find(self._activeMatch.team1, userId) ~= nil or table.find(self._activeMatch.team2, userId) ~= nil
end

function RoundService:GetPlayerTeam(player)
	if not self._activeMatch then
		return nil
	end

	local userId = player.UserId

	if table.find(self._activeMatch.team1, userId) then
		return "Team1"
	elseif table.find(self._activeMatch.team2, userId) then
		return "Team2"
	end

	return nil
end

--------------------------------------------------------------------------------
-- MATCH FLOW
--------------------------------------------------------------------------------

function RoundService:StartMatch(mapId)
	if not self._activeMatch then
		return
	end

	self._activeMatch.mapId = mapId
	self._activeMatch.state = "playing"
	self._activeMatch.currentRound = 1

	-- Teleport players to arena
	self:_teleportPlayersToArena()

	-- Fire round start
	self:_fireRoundStart()
end

function RoundService:OnPlayerKilled(killerPlayer, victimPlayer)
	if not self._activeMatch or self._activeMatch.state ~= "playing" then
		return
	end

	-- Determine teams
	local killerTeam = self:GetPlayerTeam(killerPlayer)
	local victimTeam = self:GetPlayerTeam(victimPlayer)

	if not killerTeam or not victimTeam then
		return -- Players not in this match
	end

	-- Increment killer's team score
	self._activeMatch.scores[killerTeam] = self._activeMatch.scores[killerTeam] + 1

	-- Fire kill event
	self._net:FireAllClients("RoundKill", {
		killerId = killerPlayer.UserId,
		victimId = victimPlayer.UserId,
		killerTeam = killerTeam,
	})

	-- Fire score update
	self._net:FireAllClients("ScoreUpdate", {
		team1Score = self._activeMatch.scores.Team1,
		team2Score = self._activeMatch.scores.Team2,
	})

	-- Check win condition
	if self:_checkWinCondition() then
		self:_endMatchWithWinner()
	else
		self:_resetRound()
	end
end

function RoundService:EndMatch(reason)
	if not self._activeMatch then
		return
	end

	self._activeMatch.state = "ended"

	-- Fire match end event
	self._net:FireAllClients("MatchEnd", {
		reason = reason or "manual",
		finalScores = {
			Team1 = self._activeMatch.scores.Team1,
			Team2 = self._activeMatch.scores.Team2,
		},
	})

	-- Return players to lobby after delay
	task.delay(MatchmakingConfig.Match.LobbyReturnDelay, function()
		self:_returnPlayersToLobby()
		self._activeMatch = nil
	end)
end

--------------------------------------------------------------------------------
-- ROUND MANAGEMENT
--------------------------------------------------------------------------------

function RoundService:_fireRoundStart()
	self._net:FireAllClients("RoundStart", {
		roundNumber = self._activeMatch.currentRound,
		scores = {
			Team1 = self._activeMatch.scores.Team1,
			Team2 = self._activeMatch.scores.Team2,
		},
	})
end

function RoundService:_resetRound()
	self._activeMatch.state = "loadout"
	self._activeMatch.currentRound = self._activeMatch.currentRound + 1

	-- Wait for reset delay
	task.delay(MatchmakingConfig.Match.RoundResetDelay, function()
		if not self._activeMatch or self._activeMatch.state ~= "loadout" then
			return
		end

		-- Teleport players to spawns
		self:_teleportPlayersToArena()

		-- Show loadout UI if configured
		if MatchmakingConfig.Match.ShowLoadoutOnRoundReset then
			self._net:FireAllClients("ShowRoundLoadout", {
				duration = MatchmakingConfig.Match.LoadoutSelectionTime,
				scores = {
					Team1 = self._activeMatch.scores.Team1,
					Team2 = self._activeMatch.scores.Team2,
				},
				roundNumber = self._activeMatch.currentRound,
			})

			-- Wait for loadout time, then start round
			task.delay(MatchmakingConfig.Match.LoadoutSelectionTime, function()
				if self._activeMatch and self._activeMatch.state == "loadout" then
					self._activeMatch.state = "playing"
					self:_fireRoundStart()
				end
			end)
		else
			-- No loadout, start immediately
			self._activeMatch.state = "playing"
			self:_fireRoundStart()
		end
	end)
end

function RoundService:_checkWinCondition()
	if not self._activeMatch then
		return false
	end

	local scoreToWin = self._activeMatch.scoreToWin

	return self._activeMatch.scores.Team1 >= scoreToWin or self._activeMatch.scores.Team2 >= scoreToWin
end

function RoundService:_endMatchWithWinner()
	if not self._activeMatch then
		return
	end

	self._activeMatch.state = "ended"

	local winnerTeam
	local winnerId

	if self._activeMatch.scores.Team1 >= self._activeMatch.scoreToWin then
		winnerTeam = "Team1"
		winnerId = self._activeMatch.team1[1]
	else
		winnerTeam = "Team2"
		winnerId = self._activeMatch.team2[1]
	end

	-- Fire match end event
	self._net:FireAllClients("MatchEnd", {
		winnerId = winnerId,
		winnerTeam = winnerTeam,
		finalScores = {
			Team1 = self._activeMatch.scores.Team1,
			Team2 = self._activeMatch.scores.Team2,
		},
	})

	-- Return players to lobby after delay
	task.delay(MatchmakingConfig.Match.LobbyReturnDelay, function()
		self:_returnPlayersToLobby()
		self._activeMatch = nil
	end)
end

--------------------------------------------------------------------------------
-- SPAWNING
--------------------------------------------------------------------------------

function RoundService:_teleportPlayersToArena()
	if not self._activeMatch then
		return
	end

	local mapId = self._activeMatch.mapId

	-- Get spawn points
	local team1Spawns = self:_getSpawnsForTeam("Team1", mapId)
	local team2Spawns = self:_getSpawnsForTeam("Team2", mapId)

	-- Teleport Team 1
	self:_teleportTeamToSpawns(self._activeMatch.team1, team1Spawns)

	-- Teleport Team 2
	self:_teleportTeamToSpawns(self._activeMatch.team2, team2Spawns)
end

function RoundService:_getSpawnsForTeam(team, mapId)
	local tag = team == "Team1" and MatchmakingConfig.Spawns.Team1Tag or MatchmakingConfig.Spawns.Team2Tag

	local allSpawns = CollectionService:GetTagged(tag)
	local filteredSpawns = {}

	for _, spawn in allSpawns do
		local spawnMapId = spawn:GetAttribute("MapId")

		-- Include if mapId matches or if no mapId filter
		if not mapId or not spawnMapId or spawnMapId == mapId then
			-- Also check if spawn is under a model named mapId
			if not spawnMapId and mapId then
				local ancestor = spawn:FindFirstAncestor(mapId)
				if ancestor or not mapId then
					table.insert(filteredSpawns, spawn)
				end
			else
				table.insert(filteredSpawns, spawn)
			end
		end
	end

	-- If no filtered spawns found, use all spawns
	if #filteredSpawns == 0 then
		filteredSpawns = allSpawns
	end

	return filteredSpawns
end

function RoundService:_teleportTeamToSpawns(teamUserIds, spawns)
	if #spawns == 0 then
		warn("[RoundService] No spawns found for team")
		return
	end

	for i, userId in teamUserIds do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			continue
		end

		local character = player.Character
		if not character then
			continue
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		-- Cycle through spawns
		local spawnIndex = ((i - 1) % #spawns) + 1
		local spawn = spawns[spawnIndex]

		-- Teleport slightly above spawn
		local spawnCFrame = spawn.CFrame + Vector3.new(0, 3, 0)
		character:PivotTo(spawnCFrame)

		-- Reset velocity
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function RoundService:_returnPlayersToLobby()
	if not self._activeMatch then
		return
	end

	local lobbySpawns = CollectionService:GetTagged(MatchmakingConfig.Spawns.LobbyTag)

	if #lobbySpawns == 0 then
		warn("[RoundService] No lobby spawns found")
		return
	end

	-- Notify clients
	self._net:FireAllClients("ReturnToLobby", {})

	-- Teleport all match players
	local allPlayers = {}
	for _, userId in self._activeMatch.team1 do
		table.insert(allPlayers, userId)
	end
	for _, userId in self._activeMatch.team2 do
		table.insert(allPlayers, userId)
	end

	self:_teleportTeamToSpawns(allPlayers, lobbySpawns)
end

--------------------------------------------------------------------------------
-- DEATH LISTENER
--------------------------------------------------------------------------------

function RoundService:_setupDeathListener()
	-- Listen to the PlayerKilled event from combat system
	self._net:ConnectServer("PlayerKilled", function(player, data)
		-- This is a broadcast, not a request, so we check if we should handle it
		if self._activeMatch and data and data.killerId and data.victimId then
			local killer = Players:GetPlayerByUserId(data.killerId)
			local victim = Players:GetPlayerByUserId(data.victimId)

			if killer and victim then
				self:OnPlayerKilled(killer, victim)
			end
		end
	end)
end

return RoundService
