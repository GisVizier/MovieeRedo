--[[
	MatchManager
	
	Server-side service for managing multiple concurrent matches.
	Handles match creation, lifecycle, map allocation, and cleanup.
	
	Flow: Queue → MapSelection(20s) → MapLoad → Teleport → Loadout(30s,frozen) → Round → Kill(5s delay) → RoundReset(10s,unfrozen,M=reselect) → Round → … → Win(5 rounds) → Lobby
	
	API:
	- MatchManager:CreateMatch(options) -> matchId
	- MatchManager:EndMatch(matchId) -> void
	- MatchManager:GetMatch(matchId) -> matchData
	- MatchManager:GetMatchForPlayer(player) -> matchData
	- MatchManager:OnPlayerKilled(killer, victim) -> void
	- MatchManager:GetActiveMatches() -> { matchId = matchData, ... }
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))
local MapConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MapConfig"))
local VoxelDestruction = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("VoxelDestruction"))


--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local MatchManager = {}

function MatchManager:_getMatchPlayers(match)
	local result = {}
	for _, userId in match.team1 do
		local p = Players:GetPlayerByUserId(userId)
		if p then table.insert(result, p) end
	end
	for _, userId in match.team2 do
		local p = Players:GetPlayerByUserId(userId)
		if p then table.insert(result, p) end
	end
	return result
end

function MatchManager:_fireMatchClients(match, eventName, data)
	for _, player in self:_getMatchPlayers(match) do
		self._net:FireClient(eventName, player, data)
	end
end

function MatchManager:_fireMatchStatsUpdate(match)
	if not match._stats then return end
	local stats = {}
	for userId, s in pairs(match._stats) do
		stats[userId] = {
			kills = s.kills or 0,
			deaths = s.deaths or 0,
			damage = s.damage or 0,
		}
	end
	self:_fireMatchClients(match, "MatchStatsUpdate", {
		matchId = match.id,
		stats = stats,
	})
end

function MatchManager:_setMatchPlayersMovement(match, mult)
	for _, player in self:_getMatchPlayers(match) do
		player:SetAttribute("ExternalMoveMult", mult)
	end
end

function MatchManager:_freezeMatchPlayers(match)
	for _, player in self:_getMatchPlayers(match) do
		player:SetAttribute("ExternalMoveMult", 0)
		player:SetAttribute("MatchFrozen", true)
	end
end

function MatchManager:_unfreezeMatchPlayers(match)
	for _, player in self:_getMatchPlayers(match) do
		player:SetAttribute("ExternalMoveMult", 1)
		player:SetAttribute("MatchFrozen", nil)
	end
end

function MatchManager:_clearPlayerPositionHistory(player)
	-- Clear position history so projectile hit validation doesn't use stale pre-teleport positions
	local api = require(script.Parent.Parent.AntiCheat.HitDetectionAPI)
	if api and api.ClearPositionHistory then
		api:ClearPositionHistory(player)
	end
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

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

function MatchManager:Start() end

function MatchManager:_initializePositionPool()
	local config = MatchmakingConfig.MapPositioning or {
		StartOffset = Vector3.new(5000, 0, 0),
		Increment = Vector3.new(2000, 0, 0),
		MaxConcurrentMaps = 10,
	}
	for i = 0, config.MaxConcurrentMaps - 1 do
		table.insert(self._positionPool, config.StartOffset + (config.Increment * i))
	end
end

function MatchManager:_allocatePosition()
	if #self._positionPool == 0 then return nil end
	local pos = table.remove(self._positionPool, 1)
	table.insert(self._usedPositions, pos)
	return pos
end

function MatchManager:_releasePosition(position)
	local idx = table.find(self._usedPositions, position)
	if idx then
		table.remove(self._usedPositions, idx)
		table.insert(self._positionPool, position)
	end
end

--------------------------------------------------------------------------------
-- NETWORK
--------------------------------------------------------------------------------

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
		if match and (match.state == "playing" or match.state == "storm") then
			self:OnPlayerKilled(nil, player)
		end
	end)

	self._net:ConnectServer("MatchTeleportReady", function(player, data)
		print("[MATCHMANAGER] DEBUG: MatchTeleportReady received from:", player.Name, "data:", data)
		local matchId = data and data.matchId
		if not matchId then 
			print("[MATCHMANAGER] DEBUG: MatchTeleportReady - no matchId, ignoring")
			return 
		end
		local match = self._matches[matchId]
		if not match then
			print("[MATCHMANAGER] DEBUG: MatchTeleportReady - match not found for id:", matchId)
			return
		end
		if not match._pendingTeleports then
			print("[MATCHMANAGER] DEBUG: MatchTeleportReady - no _pendingTeleports table")
			return
		end
		
		print("[MATCHMANAGER] DEBUG: MatchTeleportReady - match.state:", match.state)

		match._pendingTeleports[player] = nil
		local pending = 0
		for _ in match._pendingTeleports do pending += 1 end
		print("[MATCHMANAGER] DEBUG: MatchTeleportReady - pending teleports remaining:", pending)
		if pending == 0 then
			print("[MATCHMANAGER] DEBUG: All teleports complete, calling _onAllPlayersTeleported")
			self:_onAllPlayersTeleported(match)
		end
	end)

	-- Map voting
	self._net:ConnectServer("SubmitMapVote", function(player, data)
		local match = self:GetMatchForPlayer(player)
		if not match or match.state ~= "map_selection" then return end
		if not data or type(data.mapId) ~= "string" then return end
		-- Reject votes for maps not in the pool
		if match._mapPool and not table.find(match._mapPool, data.mapId) then return end

		match._mapVotes[player.UserId] = data.mapId

		-- Broadcast to other match players
		self:_fireMatchClients(match, "MapVoteUpdate", {
			mapId = data.mapId,
			oduserId = player.UserId,
		})

		-- Check if all voted
		local allVoted = true
		for _, userId in match.team1 do
			if not match._mapVotes[userId] then allVoted = false; break end
		end
		if allVoted then
			for _, userId in match.team2 do
				if not match._mapVotes[userId] then allVoted = false; break end
			end
		end
		if allVoted then
			self:_onMapVotingComplete(match)
		end
	end)

	-- Loadout submission
	self._net:ConnectServer("SubmitLoadout", function(player, payload)
		local match = self:GetMatchForPlayer(player)
		if not match then 
			return 
		end
		
		-- Allow submission during loadout_selection OR early playing state (for between-round submissions)
		-- Between-round: client submits when RoundStart is received, but state may already be "playing"
		if match.state ~= "loadout_selection" and match.state ~= "playing" then 
			return 
		end

		-- Store SelectedLoadout attribute so ViewmodelController and HUD update automatically
		if typeof(payload) == "table" then
			pcall(function()
				player:SetAttribute("SelectedLoadout", HttpService:JSONEncode(payload))
			end)
		end

		-- If submitted during playing state (between-round submission after RoundStart),
		-- refresh the kit so the new loadout is actually applied
		if match.state == "playing" then
			local kitService = self._registry:TryGet("KitService")
			if kitService and kitService.OnPlayerRespawn then
				task.defer(function()
					kitService:OnPlayerRespawn(player)
				end)
			end
		end

		-- Only track pending loadouts during loadout_selection state
		if match.state == "loadout_selection" and match._pendingLoadouts then
			match._pendingLoadouts[player] = nil

			local pending = 0
			for _ in match._pendingLoadouts do pending += 1 end
			if pending == 0 then
				self:_onAllLoadoutsSubmitted(match)
			end
		end
	end)

	-- Player filled all 4 slots - track ready state
	self._net:ConnectServer("LoadoutReady", function(player, payload)
		local match = self:GetMatchForPlayer(player)
		if not match then 
			return 
		end
		if match.state ~= "loadout_selection" then 
			return 
		end
		if match._loadoutLocked then 
			return 
		end

		-- Initialize ready tracking
		if not match._readyPlayers then
			match._readyPlayers = {}
		end

		-- Mark player as ready
		match._readyPlayers[player] = true

		-- Check if all players are ready
		local allPlayers = self:_getMatchPlayers(match)
		local allReady = true
		local readyCount = 0
		local totalCount = #allPlayers
		for _, p in allPlayers do
			if match._readyPlayers[p] then
				readyCount = readyCount + 1
			else
				allReady = false
			end
		end
		if allReady then
			self:_onAllPlayersReadyLoadout(match)
		end
	end)
end

--------------------------------------------------------------------------------
-- CREATE MATCH
--------------------------------------------------------------------------------

function MatchManager:CreateMatch(options)
	local modeId = options.mode or "Duel"
	local modeConfig = MatchmakingConfig.getMode(modeId)
	if not modeConfig then return nil end

	local matchId = HttpService:GenerateGUID(false)

	local match = {
		id = matchId,
		mode = modeId,
		modeConfig = modeConfig,
		mapId = nil,
		mapInstance = nil,
		mapPosition = nil,
		spawns = nil,

		state = "created",
		currentRound = 0,

		team1 = options.team1 or {},
		team2 = options.team2 or {},

		scores = { Team1 = 0, Team2 = 0 },
		_deadThisRound = {},
		_mapVotes = {},
		_pendingLoadouts = nil,
		_pendingTeleports = nil,
		_loadoutStartTime = nil,
		_loadoutDuration = nil,
		_loadoutTimerThread = nil,

		createdAt = tick(),
	}

	self._matches[matchId] = match

	for _, userId in match.team1 do
		local p = Players:GetPlayerByUserId(userId)
		if p then self._playerToMatch[p] = match end
	end
	for _, userId in match.team2 do
		local p = Players:GetPlayerByUserId(userId)
		if p then self._playerToMatch[p] = match end
	end

	-- Start the match flow
	if modeConfig.showMapSelection then
		-- Teleport players to waiting room while they pick the map
		self:_teleportToWaitingRoom(match)
		-- Start map selection (players will be teleported after map is loaded)
		self:_startMapSelection(match)
	else
		-- No map selection — load default map and go to loadout
		self:_loadMapAndTeleport(match, options.mapId or MatchmakingConfig.DefaultMap)
	end

	return matchId
end

--------------------------------------------------------------------------------
-- WAITING ROOM PHASE
--------------------------------------------------------------------------------

function MatchManager:_teleportToWaitingRoom(match)
	-- Find waiting room spawn - check multiple locations
	local waitingRoomSpawn = nil

	-- 1. workspace.World.WaitingRoom.Spawn
	local world = workspace:FindFirstChild("World")
	if world then
		local waitingRoom = world:FindFirstChild("WaitingRoom")
		waitingRoomSpawn = waitingRoom and waitingRoom:FindFirstChild("Spawn")
	end

	-- 2. workspace.World.WaitingRoomSpawn (legacy)
	if not waitingRoomSpawn and world then
		waitingRoomSpawn = world:FindFirstChild("WaitingRoomSpawn")
	end

	-- 3. workspace["Waiting Room"] - Model/Folder with Spawn, SpawnLocation, or PrimaryPart
	if not waitingRoomSpawn then
		local waitingRoom = workspace:FindFirstChild("Waiting Room")
		if waitingRoom then
			waitingRoomSpawn = waitingRoom:FindFirstChild("Spawn")
				or waitingRoom:FindFirstChildOfClass("SpawnLocation")
				or (waitingRoom:IsA("Model") and waitingRoom.PrimaryPart)
				or waitingRoom:FindFirstChildWhichIsA("BasePart")
		end
	end

	-- 4. workspace.World["Waiting Room"]
	if not waitingRoomSpawn and world then
		local waitingRoom = world:FindFirstChild("Waiting Room")
		if waitingRoom then
			waitingRoomSpawn = waitingRoom:FindFirstChild("Spawn")
				or waitingRoom:FindFirstChildOfClass("SpawnLocation")
				or (waitingRoom:IsA("Model") and waitingRoom.PrimaryPart)
				or waitingRoom:FindFirstChildWhichIsA("BasePart")
		end
	end

	-- 5. Fallback: lobby spawn
	if not waitingRoomSpawn then
		local lobby = workspace:FindFirstChild("Lobby")
		waitingRoomSpawn = lobby and lobby:FindFirstChild("Spawn")
	end

	if not waitingRoomSpawn then
		warn("[MATCHMANAGER] No Waiting Room or WaitingRoomSpawn found, skipping waiting room teleport")
		return
	end
	
	local spawnPosition = waitingRoomSpawn.Position + Vector3.new(0, 3, 0)
	local spawnLookVector = waitingRoomSpawn.CFrame.LookVector
	
	local allPlayerIds = {}
	for _, uid in match.team1 do table.insert(allPlayerIds, uid) end
	for _, uid in match.team2 do table.insert(allPlayerIds, uid) end
	
	for _, userId in allPlayerIds do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:SetAttribute("InWaitingRoom", true)
			player:SetAttribute("MatchFrozen", true)
			
			-- Fire teleport with waiting room flag
			self._net:FireClient("MatchTeleport", player, {
				matchId = match.id,
				isWaitingRoom = true,
				spawnPosition = spawnPosition,
				spawnLookVector = spawnLookVector,
			})
		end
	end
end

function MatchManager:_releaseFromWaitingRoom(match)
	local allPlayerIds = {}
	for _, uid in match.team1 do table.insert(allPlayerIds, uid) end
	for _, uid in match.team2 do table.insert(allPlayerIds, uid) end
	
	for _, userId in allPlayerIds do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:SetAttribute("InWaitingRoom", nil)
			player:SetAttribute("MatchFrozen", nil)
		end
	end
end

--------------------------------------------------------------------------------
-- MAP SELECTION PHASE
--------------------------------------------------------------------------------

function MatchManager:_startMapSelection(match)
	match.state = "map_selection"
	match._mapVotes = {}

	local duration = match.modeConfig.mapSelectionTime or 20
	local playerCount = #match.team1 + #match.team2
	local mapPool = {}
	for _, mapInfo in MapConfig.getMapsForPlayerCount(playerCount) do
		table.insert(mapPool, mapInfo.id)
	end
	if #mapPool == 0 then
		for _, mapInfo in MapConfig.getAllMaps() do
			table.insert(mapPool, mapInfo.id)
		end
	end
	match._mapPool = mapPool

	self:_fireMatchClients(match, "ShowMapSelection", {
		matchId = match.id,
		duration = duration,
		mapPool = mapPool,
		team1 = match.team1,
		team2 = match.team2,
		players = {},
	})

	-- Fill players list for RoundCreateData compat
	local allPlayers = {}
	for _, uid in match.team1 do table.insert(allPlayers, uid) end
	for _, uid in match.team2 do table.insert(allPlayers, uid) end

	-- Timeout fallback
	match._mapVoteThread = task.delay(duration + 1, function()
		if match.state == "map_selection" then
			self:_onMapVotingComplete(match)
		end
	end)
end

function MatchManager:_onMapVotingComplete(match)
	if match.state ~= "map_selection" then return end

	-- Cancel timeout if it's still pending
	if match._mapVoteThread then
		pcall(task.cancel, match._mapVoteThread)
		match._mapVoteThread = nil
	end

	-- Tally votes
	local voteCounts = {}
	for _, mapId in match._mapVotes do
		voteCounts[mapId] = (voteCounts[mapId] or 0) + 1
	end

	local winningMapId = nil
	local maxVotes = 0
	for mapId, count in voteCounts do
		if count > maxVotes then
			maxVotes = count
			winningMapId = mapId
		end
	end

	-- Fallback: random from pool
	if not winningMapId and match._mapPool and #match._mapPool > 0 then
		winningMapId = match._mapPool[math.random(1, #match._mapPool)]
	end
	winningMapId = winningMapId or MatchmakingConfig.DefaultMap

	-- Notify clients of result
	self:_fireMatchClients(match, "MapVoteResult", {
		matchId = match.id,
		winningMapId = winningMapId,
	})

	-- Load map and teleport
	self:_loadMapAndTeleport(match, winningMapId)
end

--------------------------------------------------------------------------------
-- MAP LOAD + TELEPORT
--------------------------------------------------------------------------------

-- TESTING: Skip teleport entirely to debug hit detection
-- Set to false now that we have Collider refresh fix
local SKIP_TELEPORT_FOR_TESTING = false

function MatchManager:_loadMapAndTeleport(match, mapId)
	print("[MATCHMANAGER] _loadMapAndTeleport called - matchId:", match.id, "mapId:", mapId)
	
	-- Release players from waiting room if they were there
	self:_releaseFromWaitingRoom(match)
	
	-- TESTING: Skip map load and teleport - fight in lobby
	if SKIP_TELEPORT_FOR_TESTING then
		print("[MATCHMANAGER] TESTING: Skipping map load and teleport - staying in lobby")
		match.mapId = mapId
		match.state = "starting"
		-- Go straight to loadout phase without teleporting
		self:_startLoadoutPhase(match)
		return
	end
	
	local position = self:_allocatePosition()
	if not position then
		warn("[MATCHMANAGER] ERROR: Failed to allocate position")
		self:_cleanupMatch(match.id)
		return
	end
	print("[MATCHMANAGER] Allocated position:", position)

	local mapLoader = self._registry:TryGet("MapLoader")
	if not mapLoader then
		warn("[MATCHMANAGER] ERROR: MapLoader not found")
		self:_releasePosition(position)
		self:_cleanupMatch(match.id)
		return
	end

	local mapData = mapLoader:LoadMap(mapId, position)
	if not mapData then
		warn("[MATCHMANAGER] ERROR: mapLoader:LoadMap returned nil")
		self:_releasePosition(position)
		self:_cleanupMatch(match.id)
		return
	end
	print("[MATCHMANAGER] Map loaded successfully - instance:", mapData.instance and mapData.instance.Name or "nil")
	
	-- DEBUG: Log spawn details
	if mapData.spawns then
		if mapData.spawns.Team1 then
			local pos1 = mapData.spawns.Team1:IsA("BasePart") and mapData.spawns.Team1.Position or mapData.spawns.Team1:GetPivot().Position
			print("[MATCHMANAGER] DEBUG: Team1 spawn =", mapData.spawns.Team1:GetFullName(), "at position:", pos1)
		else
			warn("[MATCHMANAGER] DEBUG: Team1 spawn is NIL!")
		end
		if mapData.spawns.Team2 then
			local pos2 = mapData.spawns.Team2:IsA("BasePart") and mapData.spawns.Team2.Position or mapData.spawns.Team2:GetPivot().Position
			print("[MATCHMANAGER] DEBUG: Team2 spawn =", mapData.spawns.Team2:GetFullName(), "at position:", pos2)
		else
			warn("[MATCHMANAGER] DEBUG: Team2 spawn is NIL!")
		end
	else
		warn("[MATCHMANAGER] DEBUG: mapData.spawns is NIL!")
	end

	match.mapId = mapId
	match.mapInstance = mapData.instance
	match.mapPosition = position
	match.spawns = mapData.spawns
	match.state = "starting"
	print("[MATCHMANAGER] DEBUG: Match state changed to 'starting'")
	
	print("[MATCHMANAGER] Match spawns set - Team1:", match.spawns.Team1 and match.spawns.Team1.Name or "NIL",
		"Team2:", match.spawns.Team2 and match.spawns.Team2.Name or "NIL")

	self:_teleportPlayers(match)
end

--------------------------------------------------------------------------------
-- TELEPORT
--------------------------------------------------------------------------------

function MatchManager:_teleportPlayers(match)
	print("[MATCHMANAGER] _teleportPlayers called for match:", match.id)
	
	local spawn1 = match.spawns and match.spawns.Team1
	local spawn2 = match.spawns and match.spawns.Team2
	
	print("[MATCHMANAGER] Initial spawns - spawn1:", spawn1 and spawn1.Name or "NIL", "spawn2:", spawn2 and spawn2.Name or "NIL")
	
	-- Use single spawn for both teams if map only has one (e.g. TrainingGrounds)
	if spawn1 and not spawn2 then spawn2 = spawn1 end
	if spawn2 and not spawn1 then spawn1 = spawn2 end
	
	print("[MATCHMANAGER] After fallback - spawn1:", spawn1 and spawn1.Name or "NIL", "spawn2:", spawn2 and spawn2.Name or "NIL")

	match._pendingTeleports = {}

	if spawn1 then
		print("[MATCHMANAGER] Teleporting Team1 (" .. #match.team1 .. " players) to:", spawn1:GetFullName())
		for i, userId in match.team1 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:_requestPlayerTeleport(match, player, spawn1, "Team1", i, #match.team1)
			else
				warn("[MATCHMANAGER] Team1 player not found for userId:", userId)
			end
		end
	else
		warn("[MATCHMANAGER] WARNING: No spawn1 available for Team1!")
	end

	if spawn2 then
		print("[MATCHMANAGER] Teleporting Team2 (" .. #match.team2 .. " players) to:", spawn2:GetFullName())
		for i, userId in match.team2 do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:_requestPlayerTeleport(match, player, spawn2, "Team2", i, #match.team2)
			else
				warn("[MATCHMANAGER] Team2 player not found for userId:", userId)
			end
		end
	else
		warn("[MATCHMANAGER] WARNING: No spawn2 available for Team2!")
	end

	-- Timeout fallback
	task.delay(3, function()
		if match._pendingTeleports then
			local pending = 0
			for _ in match._pendingTeleports do pending += 1 end
			if pending > 0 then
				print("[MATCHMANAGER] Teleport timeout - forcing completion for", pending, "pending players")
				match._pendingTeleports = {}
				self:_onAllPlayersTeleported(match)
			end
		end
	end)
end

function MatchManager:_requestPlayerTeleport(match, player, spawn, teamName, playerIndex, teamSize)
	playerIndex = playerIndex or 1
	teamSize = teamSize or 1

	print("[MATCHMANAGER] _requestPlayerTeleport - player:", player.Name, "team:", teamName, "spawn:", spawn.Name, "index:", playerIndex, "/", teamSize)

	local spawnPosition, spawnLookVector

	if spawn:IsA("BasePart") then
		local size = spawn.Size
		local cf = spawn.CFrame
		local rightVec = cf.RightVector
		local lookVec = cf.LookVector

		-- For multiple players, spread them along the spawn's right axis to avoid overlap
		local offset
		if teamSize > 1 then
			local spread = math.min(size.X * 0.4, 6)
			local t = (playerIndex - 1) / math.max(1, teamSize - 1) - 0.5
			offset = rightVec * (t * spread) + Vector3.new(0, 3, 0)
		else
			offset = Vector3.new(
				(math.random() - 0.5) * size.X * 0.5,
				3,
				(math.random() - 0.5) * size.Z * 0.5
			)
		end
		spawnPosition = spawn.Position + offset
		spawnLookVector = lookVec
	else
		spawnPosition = spawn.Position + Vector3.new(0, 3, 0)
		spawnLookVector = Vector3.new(0, 0, -1)
	end

	-- Clear frozen state from waiting room
	player:SetAttribute("MatchFrozen", nil)
	player:SetAttribute("ExternalMoveMult", 1)

	match._pendingTeleports[player] = true

	print("[MATCHMANAGER] Firing MatchTeleport to", player.Name, "- position:", spawnPosition, "lookVector:", spawnLookVector)
	self._net:FireClient("MatchTeleport", player, {
		matchId = match.id,
		mode = match.mode,
		team = teamName,
		spawnPosition = spawnPosition,
		spawnLookVector = spawnLookVector,
	})

	-- Just heal the character - let CLIENT handle teleportation (like training grounds)
	-- Server-side CFrame manipulation conflicts with client teleport and breaks Colliders
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.Health = humanoid.MaxHealth end
	end
end

--------------------------------------------------------------------------------
-- AFTER TELEPORT → LOADOUT
--------------------------------------------------------------------------------

function MatchManager:_onAllPlayersTeleported(match)
	print("[MATCHMANAGER] DEBUG: _onAllPlayersTeleported called - match.state:", match.state)
	if match.state ~= "starting" and match.state ~= "resetting" then 
		print("[MATCHMANAGER] DEBUG: _onAllPlayersTeleported EARLY RETURN - state is not 'starting' or 'resetting'")
		return 
	end

	if match.modeConfig.showLoadoutOnMatchStart or (match.state == "resetting" and match.modeConfig.showLoadoutOnRoundReset) then
		print("[MATCHMANAGER] DEBUG: _onAllPlayersTeleported -> calling _startLoadoutPhase")
		self:_startLoadoutPhase(match)
	else
		print("[MATCHMANAGER] DEBUG: _onAllPlayersTeleported -> calling _startMatchRound")
		self:_startMatchRound(match)
	end
end

function MatchManager:_startLoadoutPhase(match)
	match.state = "loadout_selection"

	local duration = match.modeConfig.loadoutSelectionTime or 30

	-- Initialize pending loadouts
	match._pendingLoadouts = {}
	for _, player in self:_getMatchPlayers(match) do
		match._pendingLoadouts[player] = true
	end

	-- Freeze movement + abilities during loadout
	-- TESTING: Skip freeze when testing hit detection
	if match.modeConfig.freezeDuringLoadout and not SKIP_TELEPORT_FOR_TESTING then
		self:_freezeMatchPlayers(match)
	end

	match._loadoutStartTime = tick()
	match._loadoutDuration = duration
	match._isBetweenRoundLoadout = false -- This is initial loadout, not between-round
	match.currentRound = match.currentRound + 1

	-- Fire loadout UI to each player
	for _, player in self:_getMatchPlayers(match) do
		self._net:FireClient("ShowRoundLoadout", player, {
			matchId = match.id,
			duration = duration,
			roundNumber = match.currentRound,
			scores = { Team1 = match.scores.Team1, Team2 = match.scores.Team2 },
		})
	end

	-- Timeout fallback
	match._loadoutTimerThread = task.delay(duration + 1, function()
		if match.state == "loadout_selection" then
			self:_onLoadoutTimerExpired(match)
		end
	end)
end

function MatchManager:_onAllLoadoutsSubmitted(match)
	if match.state ~= "loadout_selection" then return end
	
	-- If loadout is already locked by _onAllPlayersReadyLoadout, don't interfere with its 5s timer
	if match._loadoutLocked then
		return
	end

	-- Early confirm: halve remaining timer instead of starting immediately
	if match.modeConfig.earlyConfirmHalvesTimer and match._loadoutStartTime and match._loadoutDuration then
		local elapsed = tick() - match._loadoutStartTime
		local remaining = match._loadoutDuration - elapsed
		if remaining > 1 then
			-- Cancel existing timer
			if match._loadoutTimerThread then
				pcall(task.cancel, match._loadoutTimerThread)
				match._loadoutTimerThread = nil
			end

			local halved = math.max(remaining / 2, 1)

			-- Notify clients so their timer UI updates to the new shorter duration
			self:_fireMatchClients(match, "LoadoutTimerHalved", {
				matchId = match.id,
				remaining = halved,
			})

			match._loadoutTimerThread = task.delay(halved, function()
				if match.state == "loadout_selection" then
					self:_onLoadoutTimerExpired(match)
				end
			end)
			return
		end
	end

	-- No time left or no halving — start immediately
	self:_onLoadoutTimerExpired(match)
end

function MatchManager:_onAllPlayersReadyLoadout(match)
	if match.state ~= "loadout_selection" then 
		return 
	end
	if match._loadoutLocked then 
		return 
	end

	-- Mark loadout as locked
	match._loadoutLocked = true

	-- Use explicit flag to differentiate initial loadout from between-round loadout
	-- (currentRound > 0 doesn't work because round is incremented in _startLoadoutPhase before this)
	local isBetweenRound = match._isBetweenRoundLoadout == true

	-- Cancel existing timer
	if match._loadoutTimerThread then
		pcall(task.cancel, match._loadoutTimerThread)
		match._loadoutTimerThread = nil
	end

	-- Calculate remaining time
	local elapsed = match._loadoutStartTime and (tick() - match._loadoutStartTime) or 0
	local originalDuration = match._loadoutDuration or 15
	local remainingTime = originalDuration - elapsed

	-- If ≤5 seconds remaining, start instantly instead of adding another 5 seconds
	if remainingTime <= 5 then
		-- Notify clients to lock UI with 0 remaining (instant start)
		self:_fireMatchClients(match, "LoadoutLocked", {
			matchId = match.id,
			remaining = 0,
		})
		
		-- Start immediately
		if isBetweenRound then
			self:_onBetweenRoundLoadoutExpired(match)
		else
			self:_onLoadoutTimerExpired(match)
		end
		return
	end

	-- Jump to 5 seconds
	local lockDuration = 5

	-- Notify all clients to lock their loadout UI
	self:_fireMatchClients(match, "LoadoutLocked", {
		matchId = match.id,
		remaining = lockDuration,
	})

	-- Start a new timer for 5 seconds
	match._loadoutTimerThread = task.delay(lockDuration, function()
		if match.state == "loadout_selection" then
			if isBetweenRound then
				self:_onBetweenRoundLoadoutExpired(match)
			else
				self:_onLoadoutTimerExpired(match)
			end
		end
	end)
end

function MatchManager:_onLoadoutTimerExpired(match)
	if match.state ~= "loadout_selection" then return end

	if match._loadoutTimerThread then
		pcall(task.cancel, match._loadoutTimerThread)
		match._loadoutTimerThread = nil
	end

	self:_startMatchRound(match)
end

--------------------------------------------------------------------------------
-- ROUND START
--------------------------------------------------------------------------------

function MatchManager:_startMatchRound(match)
	match.state = "playing"
	match._pendingLoadouts = nil
	match._deadThisRound = {}

	-- Init per-player stats for this match (kills, deaths, damage)
	if not match._stats then
		match._stats = {}
	end
	for _, userId in match.team1 do
		if not match._stats[userId] then
			match._stats[userId] = { kills = 0, deaths = 0, damage = 0 }
		end
	end
	for _, userId in match.team2 do
		if not match._stats[userId] then
			match._stats[userId] = { kills = 0, deaths = 0, damage = 0 }
		end
	end

	-- Unfreeze movement + abilities
	self:_unfreezeMatchPlayers(match)

	-- Revive all players for the new round
	self:_reviveAllPlayers(match)

	print("[MATCHMANAGER] Firing MatchStart - team1:", match.team1, "team2:", match.team2)
	local statsPayload = {}
	if match._stats then
		for userId, s in pairs(match._stats) do
			statsPayload[userId] = {
				kills = s.kills or 0,
				deaths = s.deaths or 0,
				damage = s.damage or 0,
			}
		end
	end
	self:_fireMatchClients(match, "MatchStart", {
		matchId = match.id,
		mode = match.mode,
		team1 = match.team1,
		team2 = match.team2,
		stats = statsPayload,
	})

	self:_fireRoundStart(match)
end

function MatchManager:_fireRoundStart(match)
	-- Set PlayerState to InMatch for all players in this match
	-- This ensures overhead is hidden during the match
	for _, player in self:_getMatchPlayers(match) do
		player:SetAttribute("PlayerState", "InMatch")
	end

	-- Get round duration from mode config (default 120 seconds / 2 minutes)
	local roundDuration = match.modeConfig.roundDuration or 120

	self:_fireMatchClients(match, "RoundStart", {
		matchId = match.id,
		roundNumber = match.currentRound,
		duration = roundDuration,
		scores = match.modeConfig.hasScoring and {
			Team1 = match.scores.Team1,
			Team2 = match.scores.Team2,
		} or nil,
	})
	
	-- Start round timer for storm phase
	self:_startRoundTimer(match)
end

--[[
	Starts the round timer. When it expires, the storm phase begins.
]]
function MatchManager:_startRoundTimer(match)
	-- Cancel any existing round timer
	if match._roundTimerThread then
		pcall(task.cancel, match._roundTimerThread)
		match._roundTimerThread = nil
	end
	
	local roundDuration = match.modeConfig.roundDuration or 120
	
	-- Only start timer if storm is enabled for this mode
	if not match.modeConfig.stormEnabled then
		return
	end
	
	match._roundTimerThread = task.delay(roundDuration, function()
		if not self._matches[match.id] then return end
		if match.state ~= "playing" then return end
		
		self:_onRoundTimerExpired(match)
	end)
	
	print("[MATCHMANAGER] Round timer started:", roundDuration, "seconds until storm")
end

--[[
	Called when the round timer expires. Transitions to storm phase.
]]
function MatchManager:_onRoundTimerExpired(match)
	if match.state ~= "playing" then return end
	
	print("[MATCHMANAGER] Round timer expired - entering storm phase for match", match.id)
	
	-- Transition to storm state
	match.state = "storm"
	
	-- Start the storm via StormService
	local stormService = self._registry:TryGet("StormService")
	if stormService then
		stormService:StartStorm(match)
	else
		warn("[MATCHMANAGER] StormService not found - cannot start storm")
	end
end

function MatchManager:_reviveAllPlayers(match)
	local combatService = self._registry:TryGet("CombatService")
	local kitService = self._registry:TryGet("KitService")

	for _, player in self:_getMatchPlayers(match) do
		-- Revive combat resource
		if combatService then
			local resource = combatService:GetResource(player)
			if resource and resource._isDead then
				resource:Revive()
				combatService._deathHandled[player] = false
				combatService:_syncCombatState(player)
			end
			-- Heal to full
			if resource then
				resource:SetHealth(resource:GetMaxHealth())
				combatService:_syncCombatState(player)
			end
		end

		-- Heal humanoid
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then humanoid.Health = humanoid.MaxHealth end
		end

		-- Refresh kit (re-create, reset cooldowns, reset weapons)
		if kitService and kitService.OnPlayerRespawn then
			kitService:OnPlayerRespawn(player)
		end
	end
end

--------------------------------------------------------------------------------
-- KILL HANDLING (ELIMINATION)
--------------------------------------------------------------------------------

function MatchManager:OnPlayerKilled(killerPlayer, victimPlayer)
	local match = self:GetMatchForPlayer(victimPlayer)
	-- Allow kills during both playing and storm phases
	if not match or (match.state ~= "playing" and match.state ~= "storm") then return end

	-- Mark victim as dead this round
	match._deadThisRound[victimPlayer.UserId] = true

	-- Update match stats (kills, deaths)
	match._stats = match._stats or {}
	local victimId = victimPlayer.UserId
	local killerId = killerPlayer and killerPlayer.UserId or nil
	if not match._stats[victimId] then match._stats[victimId] = { kills = 0, deaths = 0, damage = 0 } end
	match._stats[victimId].deaths = (match._stats[victimId].deaths or 0) + 1
	if killerId and killerId ~= victimId then
		if not match._stats[killerId] then match._stats[killerId] = { kills = 0, deaths = 0, damage = 0 } end
		match._stats[killerId].kills = (match._stats[killerId].kills or 0) + 1
	end

	self:_fireMatchClients(match, "RoundKill", {
		matchId = match.id,
		killerId = killerId,
		victimId = victimId,
	})
	self:_fireMatchStatsUpdate(match)

	-- Task system: record elimination for killer
	if killerPlayer and killerId and killerId ~= victimId then
		local taskService = self._registry:TryGet("DailyTaskService")
		if taskService then
			taskService:RecordEvent(killerPlayer, "ELIMINATION")
		end
	end

	local postKillDelay = match.modeConfig.postKillDelay or 5

	-- Elimination check: is victim's entire team wiped?
	if match.modeConfig.elimination then
		local victimTeam = self:GetPlayerTeam(match, victimPlayer)
		local otherTeam = (victimTeam == "Team1") and "Team2" or "Team1"
		
		local victimTeamWiped = self:_isTeamWiped(match, victimTeam)
		local otherTeamWiped = self:_isTeamWiped(match, otherTeam)

		if victimTeamWiped then
			-- Check for trade kill (both teams wiped) - no point awarded
			if otherTeamWiped then
				-- Trade kill - both teams dead, fire draw outcome to all
				self:_fireRoundOutcome(match, nil) -- nil = draw
				
				task.delay(postKillDelay, function()
					if not self._matches[match.id] then return end
					if match.state ~= "playing" and match.state ~= "storm" then return end
					self:_resetRound(match)
				end)
			else
				-- Only victim's team is wiped - other team wins the round
				local winnerTeam = otherTeam
				match.scores[winnerTeam] = match.scores[winnerTeam] + 1

				self:_fireMatchClients(match, "ScoreUpdate", {
					matchId = match.id,
					team1Score = match.scores.Team1,
					team2Score = match.scores.Team2,
				})
				
				-- Fire round outcome to each player (win/lose based on their team)
				self:_fireRoundOutcome(match, winnerTeam)

				task.delay(postKillDelay, function()
					if not self._matches[match.id] then return end
					if match.state ~= "playing" and match.state ~= "storm" then return end
					if self:_checkWinCondition(match) then
						self:EndMatch(match.id, winnerTeam)
					else
						self:_resetRound(match)
					end
				end)
			end
		end
		-- Not wiped → continue, dead player stays dead
	else
		-- Legacy scoring: per-kill points
		local killerTeam = killerPlayer and self:GetPlayerTeam(match, killerPlayer) or nil
		if not killerTeam then
			local victimTeam = self:GetPlayerTeam(match, victimPlayer)
			killerTeam = (victimTeam == "Team1") and "Team2" or "Team1"
		end

		if killerTeam then
			match.scores[killerTeam] = match.scores[killerTeam] + 1

			self:_fireMatchClients(match, "ScoreUpdate", {
				matchId = match.id,
				team1Score = match.scores.Team1,
				team2Score = match.scores.Team2,
			})

			task.delay(postKillDelay, function()
				if not self._matches[match.id] then return end
				if match.state ~= "playing" and match.state ~= "storm" then return end -- Guard against double-fire
				if self:_checkWinCondition(match) then
					self:EndMatch(match.id, killerTeam)
				else
					self:_resetRound(match)
				end
			end)
		end
	end
end

function MatchManager:_isTeamWiped(match, teamName)
	if not teamName then return false end
	local teamList = (teamName == "Team1") and match.team1 or match.team2
	for _, userId in teamList do
		if not match._deadThisRound[userId] then
			return false
		end
	end
	return true
end

function MatchManager:_checkWinCondition(match)
	local scoreToWin = match.modeConfig.scoreToWin or 5
	return match.scores.Team1 >= scoreToWin or match.scores.Team2 >= scoreToWin
end

--[[
	Fires the RoundOutcome event to each player with their personal outcome.
	@param match The match object
	@param winnerTeam "Team1" or "Team2" or nil (nil = draw/trade kill)
]]
function MatchManager:_fireRoundOutcome(match, winnerTeam)
	for _, player in self:_getMatchPlayers(match) do
		local playerTeam = self:GetPlayerTeam(match, player)
		local outcome
		
		if winnerTeam == nil then
			-- Trade kill / draw
			outcome = "draw"
		elseif playerTeam == winnerTeam then
			outcome = "win"
		else
			outcome = "lose"
		end
		
		self._net:FireClient("RoundOutcome", player, {
			matchId = match.id,
			outcome = outcome,
			winnerTeam = winnerTeam,
			roundNumber = match.currentRound,
			scores = {
				Team1 = match.scores.Team1,
				Team2 = match.scores.Team2,
			},
		})
	end
end

--------------------------------------------------------------------------------
-- ROUND RESET
--------------------------------------------------------------------------------

function MatchManager:_resetRound(match)
	match._deadThisRound = {}

	-- Reset voxel destruction: repair map, clear server state, tell clients to clear debris
	if match.mapInstance then
		VoxelDestruction.ResetAll(match.mapInstance)
	end
	self:_fireMatchClients(match, "VoxelReset", {})

	-- Stop the round timer
	if match._roundTimerThread then
		pcall(task.cancel, match._roundTimerThread)
		match._roundTimerThread = nil
	end
	
	-- Stop any active storm
	local stormService = self._registry:TryGet("StormService")
	if stormService then
		stormService:StopStorm(match.id)
	end
	match.storm = nil

	local resetDelay = match.modeConfig.roundResetDelay or 10
	local shouldFreeze = match.modeConfig.freezeDuringRoundReset ~= false

	-- Freeze FIRST so players can't shoot/damage while being revived
	if shouldFreeze then
		self:_freezeMatchPlayers(match)
	end

	-- Unragdoll all players before revive/teleport (MatchManager owns this for competitive)
	local characterService = self._registry:TryGet("CharacterService")
	if characterService then
		for _, player in self:_getMatchPlayers(match) do
			pcall(function() characterService:Unragdoll(player) end)
		end
	end

	-- Signal clients to keep their weapons alive during between-round.
	-- The ViewmodelController will ignore SelectedLoadout changes while
	-- BetweenRoundActive is true, so OnPlayerRespawn's force-refresh of
	-- SelectedLoadout won't destroy the player's viewmodel.
	for _, player in self:_getMatchPlayers(match) do
		pcall(function()
			player:SetAttribute("BetweenRoundActive", true)
			player:SetAttribute("AttackDisabled", true)
		end)
	end

	-- Revive and teleport to spawn positions.
	-- OnPlayerRespawn will force-refresh SelectedLoadout but the client
	-- ignores it (BetweenRoundActive guard), so weapons persist.
	self:_reviveAllPlayers(match)
	self:_teleportMatchPlayersDirect(match)

	-- DESTROY kit instances + clear server-side kit state (ability, cooldowns, ultimate)
	-- so players start the between-round picker with a completely clean slate
	local kitService = self._registry:TryGet("KitService")
	if kitService and kitService.ClearKit then
		for _, player in self:_getMatchPlayers(match) do
			pcall(function() kitService:ClearKit(player) end)
		end
	end

	-- CRITICAL: Enter loadout_selection state so SubmitLoadout/LoadoutReady handlers work
	match.state = "loadout_selection"
	match._readyPlayers = {}
	match._loadoutLocked = false
	match._isBetweenRoundLoadout = true -- This IS a between-round loadout phase
	match._loadoutStartTime = tick()
	match._loadoutDuration = resetDelay
	match._pendingLoadouts = {}
	for _, player in self:_getMatchPlayers(match) do
		match._pendingLoadouts[player] = true
	end

	-- Tell clients about the between-round phase (loadout selection)
	self:_fireMatchClients(match, "BetweenRoundFreeze", {
		matchId = match.id,
		duration = resetDelay,
		roundNumber = match.currentRound + 1,
		scores = { Team1 = match.scores.Team1, Team2 = match.scores.Team2 },
		frozen = shouldFreeze,
	})

	-- Cancel any existing timer
	if match._loadoutTimerThread then
		pcall(task.cancel, match._loadoutTimerThread)
		match._loadoutTimerThread = nil
	end

	-- Start loadout selection timer - when it expires, start the round
	match._loadoutTimerThread = task.delay(resetDelay, function()
		if not self._matches[match.id] then return end
		if match.state ~= "loadout_selection" then return end
		self:_onBetweenRoundLoadoutExpired(match)
	end)
end

function MatchManager:_onBetweenRoundLoadoutExpired(match)
	if match.state ~= "loadout_selection" then 
		return 
	end

	if match._loadoutTimerThread then
		pcall(task.cancel, match._loadoutTimerThread)
		match._loadoutTimerThread = nil
	end

	match.currentRound = match.currentRound + 1
	match._deadThisRound = {}
	match.state = "playing"
	match._pendingLoadouts = nil

	-- Clear between-round flags so the client's viewmodel & weapon systems
	-- react normally again from this point forward.
	for _, player in self:_getMatchPlayers(match) do
		pcall(function()
			player:SetAttribute("BetweenRoundActive", nil)
			player:SetAttribute("AttackDisabled", nil)
		end)
	end
	
	self:_unfreezeMatchPlayers(match)
	-- Revive again in case anyone died during the between-round phase
	self:_reviveAllPlayers(match)
	self:_teleportMatchPlayersDirect(match)
	self:_fireRoundStart(match)
end

function MatchManager:_teleportMatchPlayersDirect(match)
	local spawn1 = match.spawns and match.spawns.Team1
	local spawn2 = match.spawns and match.spawns.Team2

	if spawn1 then
		for i, userId in match.team1 do
			local player = Players:GetPlayerByUserId(userId)
			if player then self:_teleportPlayerDirect(match, player, spawn1, i, #match.team1) end
		end
	end
	if spawn2 then
		for i, userId in match.team2 do
			local player = Players:GetPlayerByUserId(userId)
			if player then self:_teleportPlayerDirect(match, player, spawn2, i, #match.team2) end
		end
	end
end

function MatchManager:_teleportPlayerDirect(match, player, spawn, playerIndex, teamSize)
	playerIndex = playerIndex or 1
	teamSize = teamSize or 1

	local spawnPosition, spawnLookVector

	if spawn:IsA("BasePart") then
		local size = spawn.Size
		local cf = spawn.CFrame
		local rightVec = cf.RightVector
		local lookVec = cf.LookVector

		local offset
		if teamSize > 1 then
			local spread = math.min(size.X * 0.4, 6)
			local t = (playerIndex - 1) / math.max(1, teamSize - 1) - 0.5
			offset = rightVec * (t * spread) + Vector3.new(0, 3, 0)
		else
			offset = Vector3.new(
				(math.random() - 0.5) * size.X * 0.5,
				3,
				(math.random() - 0.5) * size.Z * 0.5
			)
		end
		spawnPosition = spawn.Position + offset
		spawnLookVector = lookVec
	else
		spawnPosition = spawn.Position + Vector3.new(0, 3, 0)
		spawnLookVector = Vector3.new(0, 0, -1)
	end

	-- Fire client teleport (MovementController handles position)
	-- roundReset = true so client does full character refresh (viewmodel, weapons, etc.)
	self._net:FireClient("MatchTeleport", player, {
		matchId = match.id,
		spawnPosition = spawnPosition,
		spawnLookVector = spawnLookVector,
		roundReset = true,
	})

	-- Just heal - let CLIENT handle teleportation (like training grounds)
	-- Server-side CFrame manipulation conflicts with client teleport and breaks Colliders
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.Health = humanoid.MaxHealth end
	end
end

--------------------------------------------------------------------------------
-- MATCH END
--------------------------------------------------------------------------------

function MatchManager:EndMatch(matchId, winnerTeam)
	print("[MATCHMANAGER] DEBUG: EndMatch called - matchId:", matchId, "winnerTeam:", winnerTeam)
	print("[MATCHMANAGER] DEBUG: EndMatch traceback:", debug.traceback())
	
	local match = self._matches[matchId]
	if not match then return end

	match.state = "ended"
	print("[MATCHMANAGER] DEBUG: Match state changed to 'ended'")

	-- Stop the round timer
	if match._roundTimerThread then
		pcall(task.cancel, match._roundTimerThread)
		match._roundTimerThread = nil
	end
	
	-- Stop any active storm
	local stormService = self._registry:TryGet("StormService")
	if stormService then
		stormService:StopStorm(matchId)
	end
	match.storm = nil

	-- Unfreeze just in case
	self:_unfreezeMatchPlayers(match)

	local winnerId = nil
	if winnerTeam == "Team1" and #match.team1 > 0 then
		winnerId = match.team1[1]
	elseif winnerTeam == "Team2" and #match.team2 > 0 then
		winnerId = match.team2[1]
	end

	self:_fireMatchClients(match, "MatchEnd", {
		matchId = matchId,
		winnerTeam = winnerTeam,
		winnerId = winnerId,
		finalScores = {
			Team1 = match.scores.Team1,
			Team2 = match.scores.Team2,
		},
	})

	-- Task system: DUEL_PLAYED for all participants, DUEL_WON for winners
	local taskService = self._registry:TryGet("DailyTaskService")
	if taskService then
		for _, player in self:_getMatchPlayers(match) do
			taskService:RecordEvent(player, "DUEL_PLAYED")
		end

		local winnerUserIds = (winnerTeam == "Team1") and match.team1 or match.team2
		for _, userId in winnerUserIds do
			local winner = Players:GetPlayerByUserId(userId)
			if winner then
				taskService:RecordEvent(winner, "DUEL_WON")
			end
		end
	end

	local lobbyReturnDelay = match.modeConfig.lobbyReturnDelay or 5
	task.delay(lobbyReturnDelay, function()
		self:_cleanupMatch(matchId)
	end)
end

function MatchManager:_cleanupMatch(matchId)
	print("[MATCHMANAGER] DEBUG: _cleanupMatch called - matchId:", matchId)
	print("[MATCHMANAGER] DEBUG: _cleanupMatch traceback:", debug.traceback())
	
	local match = self._matches[matchId]
	if not match then return end
	
	print("[MATCHMANAGER] DEBUG: _cleanupMatch - match.state was:", match.state)

	-- Cancel all pending threads to prevent leaks
	if match._mapVoteThread then
		pcall(task.cancel, match._mapVoteThread)
		match._mapVoteThread = nil
	end
	if match._loadoutTimerThread then
		pcall(task.cancel, match._loadoutTimerThread)
		match._loadoutTimerThread = nil
	end
	if match._roundTimerThread then
		pcall(task.cancel, match._roundTimerThread)
		match._roundTimerThread = nil
	end

	-- Clear freeze state before returning to lobby
	self:_unfreezeMatchPlayers(match)

	-- Fire ReturnToLobby BEFORE removing match (so we can scope it)
	self:_fireMatchClients(match, "ReturnToLobby", { matchId = matchId })

	self:_returnPlayersToLobby(match)

	for _, player in self:_getMatchPlayers(match) do
		self._playerToMatch[player] = nil
	end

	local mapLoader = self._registry:TryGet("MapLoader")
	if mapLoader and match.mapInstance then
		mapLoader:UnloadMap(match.mapInstance)
	end

	if match.mapPosition then
		self:_releasePosition(match.mapPosition)
	end

	self._matches[matchId] = nil
end

function MatchManager:_returnPlayersToLobby(match)
	local userIds = {}
	for _, uid in match.team1 do table.insert(userIds, uid) end
	for _, uid in match.team2 do table.insert(userIds, uid) end

	local lobbySpawns = CollectionService:GetTagged(MatchmakingConfig.Spawns.LobbyTag)
	if #lobbySpawns == 0 then return end

	-- CRITICAL: Unragdoll all players before teleport (last killed player may be ragdolled with invisible parts)
	local characterService = self._registry:TryGet("CharacterService")
	if characterService then
		for _, player in self:_getMatchPlayers(match) do
			pcall(function() characterService:Unragdoll(player) end)
		end
	end

	-- Revive dead players (CombatResource, humanoid, kit) so they're fully restored before teleport
	self:_reviveAllPlayers(match)

	-- Get kit service to destroy kits
	local kitService = self._registry:TryGet("KitService")
	-- Get weapon service to clear weapons
	local weaponService = self._registry:TryGet("WeaponService")

	for i, userId in ipairs(userIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			-- DESTROY KIT and clear all server-side kit state when returning to lobby
			if kitService and kitService.ClearKit then
				pcall(function() kitService:ClearKit(player) end)
			end
			
			-- Clear all match/loadout related attributes
			player:SetAttribute("SelectedLoadout", nil)
			player:SetAttribute("KitData", nil)
			player:SetAttribute("PrimaryData", nil)
			player:SetAttribute("SecondaryData", nil)
			player:SetAttribute("MeleeData", nil)
			player:SetAttribute("EquippedSlot", nil)
			player:SetAttribute("LastEquippedSlot", nil)
			player:SetAttribute("MatchFrozen", nil)
			player:SetAttribute("InWaitingRoom", nil)
			player:SetAttribute("ExternalMoveMult", 1)
			player:SetAttribute("BetweenRoundActive", nil)
			player:SetAttribute("AttackDisabled", nil)
			
			-- Clear movement/ability attributes that could linger
			player:SetAttribute("ForceUncrouch", nil)
			player:SetAttribute("BlockCrouchWhileAbility", nil)
			player:SetAttribute("DisplaySlot", nil)
			player:SetAttribute("blue_projectile_activeCFR", nil)
			player:SetAttribute("red_charge", nil)
			player:SetAttribute("red_projectile_activeCFR", nil)
			player:SetAttribute("red_explosion_pivot", nil)
			player:SetAttribute("cleanupblueFX", nil)
			
			-- Clear weapons
			if weaponService and weaponService.ClearWeapons then
				pcall(function()
					weaponService:ClearWeapons(player)
				end)
			end
			
			-- Set PlayerState back to Lobby (overhead will reappear)
			player:SetAttribute("PlayerState", "Lobby")
			
			local spawnIndex = ((i - 1) % #lobbySpawns) + 1
			local spawn = lobbySpawns[spawnIndex]
			self:_teleportPlayerToSpawn(player, spawn)
		end
	end
end

function MatchManager:_teleportPlayerToSpawn(player, spawn)
	local spawnPosition, spawnLookVector
	
	if spawn:IsA("BasePart") then
		-- Get random position within spawn bounds
		local size = spawn.Size
		local randomOffset = Vector3.new(
			(math.random() - 0.5) * size.X,
			3, -- Height above spawn
			(math.random() - 0.5) * size.Z
		)
		spawnPosition = spawn.Position + randomOffset
		spawnLookVector = spawn.CFrame.LookVector
	else
		spawnPosition = spawn.Position + Vector3.new(0, 3, 0)
		spawnLookVector = Vector3.new(0, 0, -1)
	end

	-- If player has no character (edge case), spawn one at lobby position
	local character = player.Character
	if not character or not character.Parent then
		local characterService = self._registry:TryGet("CharacterService")
		if characterService then
			characterService:SpawnCharacter(player, { spawnPosition = spawnPosition })
		end
		return
	end

	self._net:FireClient("MatchTeleport", player, {
		matchId = "reset",
		spawnPosition = spawnPosition,
		spawnLookVector = spawnLookVector,
		roundReset = true, -- Full character refresh (viewmodel, weapons, animations) so last-killed player displays correctly
	})

	-- Just heal - let CLIENT handle teleportation (like training grounds)
	-- Server-side CFrame manipulation conflicts with client teleport and breaks Colliders
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.Health = humanoid.MaxHealth end
end

--------------------------------------------------------------------------------
-- PLAYER LEFT
--------------------------------------------------------------------------------

function MatchManager:_handlePlayerLeft(matchId, player)
	local match = self._matches[matchId]
	if not match then return end

	local userId = player.UserId

	-- Determine which team the leaver was on BEFORE removing them
	local leaverTeam = nil
	if table.find(match.team1, userId) then
		leaverTeam = "Team1"
	elseif table.find(match.team2, userId) then
		leaverTeam = "Team2"
	end

	self:_fireMatchClients(match, "PlayerLeftMatch", {
		matchId = matchId,
		playerId = userId,
	})

	self._playerToMatch[player] = nil

	local idx1 = table.find(match.team1, userId)
	if idx1 then table.remove(match.team1, idx1) end
	local idx2 = table.find(match.team2, userId)
	if idx2 then table.remove(match.team2, idx2) end

	-- Mark leaver as dead this round so _isTeamWiped accounts for them being gone
	match._deadThisRound[userId] = true

	local partyService = self._registry:TryGet("PartyService")
	if partyService and partyService:IsInParty(player) then
		partyService:RemoveFromParty(player)
	end

	-- Both teams empty in any state — silent cleanup
	if #match.team1 == 0 and #match.team2 == 0 then
		self:_cleanupMatch(matchId)
		return
	end

	local isActiveGameplay = (match.state == "playing" or match.state == "storm")
	local isBetweenRound = (match.state == "loadout_selection" and match._isBetweenRoundLoadout == true)
	local isPreGame = (match.state == "map_selection" or match.state == "starting"
		or (match.state == "loadout_selection" and not match._isBetweenRoundLoadout))

	if isActiveGameplay or isBetweenRound then
		-- ACTIVE GAMEPLAY: check if the leaver's team is now effectively wiped
		-- (all remaining members are dead this round, or team is empty)
		if leaverTeam and match.modeConfig.elimination then
			local otherTeam = (leaverTeam == "Team1") and "Team2" or "Team1"
			local leaverTeamWiped = self:_isTeamWiped(match, leaverTeam)

			if leaverTeamWiped then
				local winnerTeam = otherTeam
				match.scores[winnerTeam] = match.scores[winnerTeam] + 1

				self:_fireMatchClients(match, "ScoreUpdate", {
					matchId = match.id,
					team1Score = match.scores.Team1,
					team2Score = match.scores.Team2,
				})

				self:_fireRoundOutcome(match, winnerTeam)

				local postKillDelay = match.modeConfig.postKillDelay or 5
				task.delay(postKillDelay, function()
					if not self._matches[match.id] then return end
					if self:_checkWinCondition(match) then
						self:EndMatch(match.id, winnerTeam)
					else
						self:_resetRound(match)
					end
				end)
				return
			end
		end

		-- Team not wiped — check if an entire team is now empty (all members left)
		if #match.team1 == 0 and #match.team2 > 0 then
			self:EndMatch(matchId, "Team2")
		elseif #match.team2 == 0 and #match.team1 > 0 then
			self:EndMatch(matchId, "Team1")
		end

	elseif isPreGame then
		-- PRE-GAME: 1v1 forfeit or team-mode validity check
		local isDuel = (match.modeConfig.playersPerTeam == 1)

		if isDuel then
			-- 1v1: any leave during pre-game = silent forfeit, no winner
			self:_cleanupMatch(matchId)
		else
			-- Team modes: match is still valid if each team has at least 1 player
			if #match.team1 == 0 or #match.team2 == 0 then
				self:_cleanupMatch(matchId)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- QUERIES
--------------------------------------------------------------------------------

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
	if not match or not player then return nil end
	local userId = player.UserId
	if table.find(match.team1, userId) then return "Team1" end
	if table.find(match.team2, userId) then return "Team2" end
	return nil
end

--[[
	Called by CombatService when a player deals damage to another in a match.
	Tracks damage for leaderboard and fires MatchStatsUpdate.
]]
function MatchManager:NotifyDamageDealt(attacker, victim, damage)
	if not attacker or not victim or not damage or damage <= 0 then return end
	local match = self:GetMatchForPlayer(victim)
	if not match or (match.state ~= "playing" and match.state ~= "storm") then return end
	-- Both must be in the match
	if self:GetPlayerTeam(match, attacker) == nil then return end
	if self:GetPlayerTeam(match, victim) == nil then return end

	match._stats = match._stats or {}
	local attackerId = attacker.UserId
	if not match._stats[attackerId] then
		match._stats[attackerId] = { kills = 0, deaths = 0, damage = 0 }
	end
	match._stats[attackerId].damage = (match._stats[attackerId].damage or 0) + math.floor(damage + 0.5)

	self:_fireMatchStatsUpdate(match)
end

--[[
	Returns all Player objects in the same game context as the given player.
	Match context: team1 + team2 players.
	Training: delegates to RoundService.
	Lobby: everyone not in a match or training.
]]
function MatchManager:GetPlayersInMatch(player)
	local match = self._playerToMatch[player]
	if match then
		return self:_getMatchPlayers(match)
	end

	local roundService = self._registry:TryGet("Round") or self._registry:TryGet("RoundService")
	if roundService and roundService:IsPlayerInTraining(player) then
		return roundService:GetPlayersInSameArea(player)
	end

	local players = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local inMatch = self._playerToMatch[p] ~= nil
		local inTraining = roundService and roundService:IsPlayerInTraining(p) or false
		if not inMatch and not inTraining then
			table.insert(players, p)
		end
	end
	return players
end

return MatchManager
