--[[
	RoundService
	
	Server-side service for managing matches and rounds.
	Supports both Training (infinite) and Competitive (lives) modes.
	
	API:
	- RoundService:StartMatch(options) -> void
	- RoundService:EndMatch() -> void
	- RoundService:StartRound() -> void
	- RoundService:EndRound() -> void
	- RoundService:AddPlayer(player) -> void (training mode)
	- RoundService:RemovePlayer(player) -> void
	- RoundService:OnPlayerKilled(killer, victim) -> void
	- RoundService:GetActiveMatch() -> matchData or nil
	- RoundService:GetScores() -> { Team1 = n, Team2 = n } or nil
	- RoundService:GetPlayers() -> { player1, player2, ... }
	- RoundService:GetMode() -> modeId or nil
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

	-- Setup listeners
	self:_setupPlayerRemoving()
	
	-- Hook into player deaths for respawn handling in training mode
	net:ConnectServer("PlayerDied", function(player)
		if self:IsPlayerInMatch(player) then
			self:OnPlayerKilled(nil, player)
		end
	end)
end

function RoundService:Start()
	-- Start Training match immediately when server starts
	-- Players join via AreaTeleport gadget
	self:StartMatch({
		mode = "Training",
		players = {},
	})
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
	StartMatch - Begin a new match
	
	Options:
	- mode: string ("Training", "Duel", "TwoVTwo", etc.)
	- mapId: string (optional)
	- team1: { userId, ... } (required for competitive modes)
	- team2: { userId, ... } (required for competitive modes)
	- players: { userId, ... } (for training mode, optional)
]]
function RoundService:StartMatch(options)
	if self._activeMatch then
		warn("[RoundService] Match already in progress")
		return
	end

	local modeId = options.mode or MatchmakingConfig.DefaultMode
	local modeConfig = MatchmakingConfig.getMode(modeId)

	if not modeConfig then
		warn("[RoundService] Invalid mode:", modeId)
		return
	end

	self._activeMatch = {
		mode = modeId,
		modeConfig = modeConfig,
		mapId = options.mapId,
		state = "playing", -- "playing", "loadout", "ended"
		currentRound = 1,

		-- Players (for training mode - no teams)
		players = {},

		-- Teams (for competitive modes)
		team1 = options.team1 or {},
		team2 = options.team2 or {},

		-- Scores (only for competitive)
		scores = {
			Team1 = 0,
			Team2 = 0,
		},
	}

	-- For training mode, add initial players
	if not modeConfig.hasTeams then
		if options.players then
			for _, userId in options.players do
				table.insert(self._activeMatch.players, userId)
			end
		end
	end

	-- Teleport players to arena/training area
	self:_teleportAllPlayers()

	-- Fire match start
	self:_fireMatchStart()
end

function RoundService:EndMatch()
	if not self._activeMatch then
		return
	end

	local modeConfig = self._activeMatch.modeConfig
	self._activeMatch.state = "ended"

	-- Fire match end event
	self._net:FireAllClients("MatchEnd", {
		mode = self._activeMatch.mode,
		finalScores = modeConfig.hasScoring and {
			Team1 = self._activeMatch.scores.Team1,
			Team2 = self._activeMatch.scores.Team2,
		} or nil,
	})

	-- Return to lobby if configured
	if modeConfig.returnToLobbyOnEnd then
		local delay = modeConfig.lobbyReturnDelay or 5
		task.delay(delay, function()
			self:_returnPlayersToLobby()
			self._activeMatch = nil
		end)
	else
		self._activeMatch = nil
	end
end

function RoundService:StartRound()
	if not self._activeMatch then
		return
	end

	self._activeMatch.state = "playing"
	self:_fireRoundStart()
end

function RoundService:EndRound()
	if not self._activeMatch then
		return
	end

	local modeConfig = self._activeMatch.modeConfig

	if modeConfig.hasScoring then
		-- Competitive: check win condition
		if self:_checkWinCondition() then
			self:_endMatchWithWinner()
		else
			self:_resetRound()
		end
	end
	-- Training mode: rounds don't really end, just continue
end

-- Add player to training match (join midway)
function RoundService:AddPlayer(player)
	if not self._activeMatch then
		return false
	end

	local modeConfig = self._activeMatch.modeConfig
	if not modeConfig.allowJoinMidway then
		return false
	end

	local userId = player.UserId

	-- Check if already in match
	if table.find(self._activeMatch.players, userId) then
		return false
	end

	table.insert(self._activeMatch.players, userId)

	-- Teleport to training spawn
	self:_teleportPlayerToSpawn(player)

	-- Notify
	self._net:FireAllClients("PlayerJoinedMatch", {
		playerId = userId,
	})

	return true
end

function RoundService:RemovePlayer(player)
	if not self._activeMatch then
		return
	end

	local userId = player.UserId
	local modeConfig = self._activeMatch.modeConfig

	if modeConfig.hasTeams then
		-- Remove from teams
		local index1 = table.find(self._activeMatch.team1, userId)
		if index1 then
			table.remove(self._activeMatch.team1, index1)
		end

		local index2 = table.find(self._activeMatch.team2, userId)
		if index2 then
			table.remove(self._activeMatch.team2, index2)
		end
	else
		-- Remove from players list
		local index = table.find(self._activeMatch.players, userId)
		if index then
			table.remove(self._activeMatch.players, index)
		end
	end

	self._net:FireAllClients("PlayerLeftMatch", {
		playerId = userId,
	})
end

function RoundService:OnPlayerKilled(killerPlayer, victimPlayer)
	if not self._activeMatch or self._activeMatch.state ~= "playing" then
		return
	end

	local modeConfig = self._activeMatch.modeConfig

	-- Fire kill event
	self._net:FireAllClients("RoundKill", {
		killerId = killerPlayer and killerPlayer.UserId or nil,
		victimId = victimPlayer.UserId,
	})

	if modeConfig.hasScoring then
		-- Competitive mode: score point, reset round
		local killerTeam = self:GetPlayerTeam(killerPlayer)

		if killerTeam then
			self._activeMatch.scores[killerTeam] = self._activeMatch.scores[killerTeam] + 1

			-- Fire score update
			self._net:FireAllClients("ScoreUpdate", {
				team1Score = self._activeMatch.scores.Team1,
				team2Score = self._activeMatch.scores.Team2,
			})

			-- Check win or reset
			if self:_checkWinCondition() then
				self:_endMatchWithWinner()
			else
				self:_resetRound()
			end
		end
	else
		-- Training mode: just respawn the victim
		local respawnDelay = modeConfig.respawnDelay or 2
		task.delay(respawnDelay, function()
			if self._activeMatch and victimPlayer and victimPlayer.Parent then
				self:_respawnPlayer(victimPlayer)
			end
		end)
	end
end

function RoundService:GetActiveMatch()
	return self._activeMatch
end

function RoundService:GetScores()
	if not self._activeMatch then
		return nil
	end

	local modeConfig = self._activeMatch.modeConfig
	if not modeConfig.hasScoring then
		return nil
	end

	return {
		Team1 = self._activeMatch.scores.Team1,
		Team2 = self._activeMatch.scores.Team2,
	}
end

function RoundService:GetPlayers()
	if not self._activeMatch then
		return {}
	end

	local modeConfig = self._activeMatch.modeConfig
	local result = {}

	if modeConfig.hasTeams then
		for _, userId in self._activeMatch.team1 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				table.insert(result, player)
			end
		end
		for _, userId in self._activeMatch.team2 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				table.insert(result, player)
			end
		end
	else
		for _, userId in self._activeMatch.players do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				table.insert(result, player)
			end
		end
	end

	return result
end

function RoundService:GetMode()
	if not self._activeMatch then
		return nil
	end
	return self._activeMatch.mode
end

function RoundService:GetPlayerTeam(player)
	if not self._activeMatch then
		return nil
	end

	if not player then
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

function RoundService:IsPlayerInMatch(player)
	if not self._activeMatch then
		return false
	end

	local userId = player.UserId
	local modeConfig = self._activeMatch.modeConfig

	if modeConfig.hasTeams then
		return table.find(self._activeMatch.team1, userId) ~= nil or table.find(self._activeMatch.team2, userId) ~= nil
	else
		return table.find(self._activeMatch.players, userId) ~= nil
	end
end

--------------------------------------------------------------------------------
-- INTERNAL: ROUND MANAGEMENT
--------------------------------------------------------------------------------

function RoundService:_fireMatchStart()
	self._net:FireAllClients("MatchStart", {
		mode = self._activeMatch.mode,
		mapId = self._activeMatch.mapId,
	})

	self:_fireRoundStart()
end

function RoundService:_fireRoundStart()
	self._net:FireAllClients("RoundStart", {
		roundNumber = self._activeMatch.currentRound,
		scores = self._activeMatch.modeConfig.hasScoring and {
			Team1 = self._activeMatch.scores.Team1,
			Team2 = self._activeMatch.scores.Team2,
		} or nil,
	})
end

function RoundService:_resetRound()
	local modeConfig = self._activeMatch.modeConfig
	self._activeMatch.state = "loadout"
	self._activeMatch.currentRound = self._activeMatch.currentRound + 1

	-- Wait for reset delay
	local resetDelay = modeConfig.roundResetDelay or 2
	task.delay(resetDelay, function()
		if not self._activeMatch or self._activeMatch.state ~= "loadout" then
			return
		end

		-- Teleport players to spawns
		self:_teleportAllPlayers()

		-- Show loadout UI if configured
		if modeConfig.showLoadoutOnRoundReset then
			self._net:FireAllClients("ShowRoundLoadout", {
				duration = modeConfig.loadoutSelectionTime or 15,
				scores = {
					Team1 = self._activeMatch.scores.Team1,
					Team2 = self._activeMatch.scores.Team2,
				},
				roundNumber = self._activeMatch.currentRound,
			})

			-- Wait for loadout time, then start round
			local loadoutTime = modeConfig.loadoutSelectionTime or 15
			task.delay(loadoutTime, function()
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

	local modeConfig = self._activeMatch.modeConfig
	if not modeConfig.hasScoring then
		return false
	end

	local scoreToWin = modeConfig.scoreToWin or 5

	return self._activeMatch.scores.Team1 >= scoreToWin or self._activeMatch.scores.Team2 >= scoreToWin
end

function RoundService:_endMatchWithWinner()
	if not self._activeMatch then
		return
	end

	local modeConfig = self._activeMatch.modeConfig
	self._activeMatch.state = "ended"

	local winnerTeam
	local winnerId

	if self._activeMatch.scores.Team1 >= (modeConfig.scoreToWin or 5) then
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
	local delay = modeConfig.lobbyReturnDelay or 5
	task.delay(delay, function()
		self:_returnPlayersToLobby()
		self._activeMatch = nil
	end)
end

--------------------------------------------------------------------------------
-- INTERNAL: SPAWNING
--------------------------------------------------------------------------------

function RoundService:_teleportAllPlayers()
	if not self._activeMatch then
		return
	end

	local modeConfig = self._activeMatch.modeConfig

	if modeConfig.hasTeams then
		-- Competitive: spawn teams at team spawns
		local team1Spawns = self:_getSpawns(MatchmakingConfig.Spawns.Team1Tag)
		local team2Spawns = self:_getSpawns(MatchmakingConfig.Spawns.Team2Tag)

		self:_teleportTeamToSpawns(self._activeMatch.team1, team1Spawns)
		self:_teleportTeamToSpawns(self._activeMatch.team2, team2Spawns)
	else
		-- Training: spawn everyone at training spawns
		local spawns = self:_getSpawns(MatchmakingConfig.Spawns.TrainingTag)
		self:_teleportTeamToSpawns(self._activeMatch.players, spawns)
	end
end

function RoundService:_teleportPlayerToSpawn(player)
	if not self._activeMatch then
		return
	end

	local modeConfig = self._activeMatch.modeConfig
	local spawnTag

	if modeConfig.hasTeams then
		local team = self:GetPlayerTeam(player)
		if team == "Team1" then
			spawnTag = MatchmakingConfig.Spawns.Team1Tag
		else
			spawnTag = MatchmakingConfig.Spawns.Team2Tag
		end
	else
		spawnTag = MatchmakingConfig.Spawns.TrainingTag
	end

	local spawns = self:_getSpawns(spawnTag)
	if #spawns == 0 then
		return
	end

	local spawn = spawns[math.random(1, #spawns)]
	local character = player.Character

	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function RoundService:_respawnPlayer(player)
	-- Respawn character and teleport to spawn
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	end

	self:_teleportPlayerToSpawn(player)

	self._net:FireClient(player, "PlayerRespawned", {})
end

function RoundService:_getSpawns(tag)
	local spawns = CollectionService:GetTagged(tag)
	local mapId = self._activeMatch and self._activeMatch.mapId

	if not mapId then
		return spawns
	end

	-- Filter by map if mapId is set
	local filtered = {}
	for _, spawn in spawns do
		local spawnMapId = spawn:GetAttribute("MapId")
		if not spawnMapId or spawnMapId == mapId then
			table.insert(filtered, spawn)
		end
	end

	return #filtered > 0 and filtered or spawns
end

function RoundService:_teleportTeamToSpawns(userIds, spawns)
	if #spawns == 0 then
		warn("[RoundService] No spawns found")
		return
	end

	for i, userId in userIds do
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

		character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function RoundService:_returnPlayersToLobby()
	local lobbySpawns = CollectionService:GetTagged(MatchmakingConfig.Spawns.LobbyTag)

	if #lobbySpawns == 0 then
		warn("[RoundService] No lobby spawns found")
		return
	end

	self._net:FireAllClients("ReturnToLobby", {})

	-- Get all players in match
	local allUserIds = {}
	if self._activeMatch then
		if self._activeMatch.modeConfig.hasTeams then
			for _, userId in self._activeMatch.team1 do
				table.insert(allUserIds, userId)
			end
			for _, userId in self._activeMatch.team2 do
				table.insert(allUserIds, userId)
			end
		else
			for _, userId in self._activeMatch.players do
				table.insert(allUserIds, userId)
			end
		end
	end

	self:_teleportTeamToSpawns(allUserIds, lobbySpawns)
end

--------------------------------------------------------------------------------
-- INTERNAL: PLAYER HANDLING
--------------------------------------------------------------------------------

function RoundService:_setupPlayerRemoving()
	Players.PlayerRemoving:Connect(function(player)
		self:RemovePlayer(player)
	end)
end

return RoundService
