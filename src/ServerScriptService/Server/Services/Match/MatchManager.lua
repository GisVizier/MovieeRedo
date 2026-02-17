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

local function destroyMobWallsForUserIds(userIds)
	local userIdSet = {}
	for _, userId in userIds do
		userIdSet[userId] = true
	end

	local effectsFolder = workspace:FindFirstChild("Effects")
	local walls = CollectionService:GetTagged("MobWall")
	for _, wall in walls do
		local ownerId = wall:GetAttribute("OwnerUserId")
		if ownerId and userIdSet[ownerId] then
			if effectsFolder then
				local visualId = wall:GetAttribute("VisualId")
				if type(visualId) == "string" and visualId ~= "" then
					local visual = effectsFolder:FindFirstChild(visualId)
					if visual then
						visual:Destroy()
					end
				end
			end
			wall:Destroy()
		end
	end

	if effectsFolder then
		for _, userId in userIds do
			local orphanVisual = effectsFolder:FindFirstChild("MobWallVisual_" .. tostring(userId))
			if orphanVisual then
				orphanVisual:Destroy()
			end
		end
	end
end

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
		player:SetAttribute("MatchFrozen", false)
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
		if match and match.state == "playing" then
			self:OnPlayerKilled(nil, player)
		end
	end)

	self._net:ConnectServer("MatchTeleportReady", function(player, data)
		local matchId = data and data.matchId
		if not matchId then return end
		local match = self._matches[matchId]
		if not match or not match._pendingTeleports then return end

		match._pendingTeleports[player] = nil
		local pending = 0
		for _ in match._pendingTeleports do pending += 1 end
		if pending == 0 then
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
		self:_startMapSelection(match)
	else
		-- No map selection — load default map and go to loadout
		self:_loadMapAndTeleport(match, options.mapId or MatchmakingConfig.DefaultMap)
	end

	return matchId
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

function MatchManager:_loadMapAndTeleport(match, mapId)
	local position = self:_allocatePosition()
	if not position then
		self:_cleanupMatch(match.id)
		return
	end

	local mapLoader = self._registry:TryGet("MapLoader")
	if not mapLoader then
		self:_releasePosition(position)
		self:_cleanupMatch(match.id)
		return
	end

	local mapData = mapLoader:LoadMap(mapId, position)
	if not mapData then
		self:_releasePosition(position)
		self:_cleanupMatch(match.id)
		return
	end

	match.mapId = mapId
	match.mapInstance = mapData.instance
	match.mapPosition = position
	match.spawns = mapData.spawns
	match.state = "starting"

	self:_teleportPlayers(match)
end

--------------------------------------------------------------------------------
-- TELEPORT
--------------------------------------------------------------------------------

function MatchManager:_teleportPlayers(match)
	local spawn1 = match.spawns and match.spawns.Team1
	local spawn2 = match.spawns and match.spawns.Team2

	match._pendingTeleports = {}

	if spawn1 then
		for _, userId in match.team1 do
			local player = Players:GetPlayerByUserId(userId)
			if player then self:_requestPlayerTeleport(match, player, spawn1, "Team1") end
		end
	end
	if spawn2 then
		for _, userId in match.team2 do
			local player = Players:GetPlayerByUserId(userId)
			if player then self:_requestPlayerTeleport(match, player, spawn2, "Team2") end
		end
	end

	-- Timeout fallback
	task.delay(3, function()
		if match._pendingTeleports then
			local pending = 0
			for _ in match._pendingTeleports do pending += 1 end
			if pending > 0 then
				match._pendingTeleports = {}
				self:_onAllPlayersTeleported(match)
			end
		end
	end)
end

function MatchManager:_requestPlayerTeleport(match, player, spawn, teamName)
	local spawnCFrame
	if spawn:IsA("BasePart") then
		spawnCFrame = spawn.CFrame + Vector3.new(0, 3, 0)
	else
		spawnCFrame = CFrame.new(spawn.Position + Vector3.new(0, 3, 0))
	end

	match._pendingTeleports[player] = true

	self._net:FireClient("MatchTeleport", player, {
		matchId = match.id,
		mode = match.mode,
		team = teamName,
		spawnPosition = spawnCFrame.Position,
		spawnLookVector = spawnCFrame.LookVector,
	})

	-- Heal
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
	if match.state ~= "starting" and match.state ~= "resetting" then return end

	if match.modeConfig.showLoadoutOnMatchStart or (match.state == "resetting" and match.modeConfig.showLoadoutOnRoundReset) then
		self:_startLoadoutPhase(match)
	else
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
	if match.modeConfig.freezeDuringLoadout then
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

	-- Unfreeze movement + abilities
	self:_unfreezeMatchPlayers(match)

	-- Revive all players for the new round
	self:_reviveAllPlayers(match)

	print("[MATCHMANAGER] Firing MatchStart - team1:", match.team1, "team2:", match.team2)
	self._net:FireAllClients("MatchStart", {
		matchId = match.id,
		mode = match.mode,
		team1 = match.team1,
		team2 = match.team2,
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

	self._net:FireAllClients("RoundStart", {
		matchId = match.id,
		roundNumber = match.currentRound,
		duration = roundDuration,
		scores = match.modeConfig.hasScoring and {
			Team1 = match.scores.Team1,
			Team2 = match.scores.Team2,
		} or nil,
	})
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
	if not match or match.state ~= "playing" then return end

	-- Mark victim as dead this round
	match._deadThisRound[victimPlayer.UserId] = true

	self._net:FireAllClients("RoundKill", {
		matchId = match.id,
		killerId = killerPlayer and killerPlayer.UserId or nil,
		victimId = victimPlayer.UserId,
	})

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
					if match.state ~= "playing" then return end
					self:_resetRound(match)
				end)
			else
				-- Only victim's team is wiped - other team wins the round
				local winnerTeam = otherTeam
				match.scores[winnerTeam] = match.scores[winnerTeam] + 1

				self._net:FireAllClients("ScoreUpdate", {
					matchId = match.id,
					team1Score = match.scores.Team1,
					team2Score = match.scores.Team2,
				})
				
				-- Fire round outcome to each player (win/lose based on their team)
				self:_fireRoundOutcome(match, winnerTeam)

				task.delay(postKillDelay, function()
					if not self._matches[match.id] then return end
					if match.state ~= "playing" then return end
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

			self._net:FireAllClients("ScoreUpdate", {
				matchId = match.id,
				team1Score = match.scores.Team1,
				team2Score = match.scores.Team2,
			})

			task.delay(postKillDelay, function()
				if not self._matches[match.id] then return end
				if match.state ~= "playing" then return end -- Guard against double-fire
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

	-- Revive and teleport to spawn positions
	self:_reviveAllPlayers(match)
	self:_teleportMatchPlayersDirect(match)

	-- Clear SelectedLoadout to remove weapons/viewmodels during between-round phase
	for _, player in self:_getMatchPlayers(match) do
		pcall(function()
			player:SetAttribute("SelectedLoadout", nil)
		end)
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
		for _, userId in match.team1 do
			local player = Players:GetPlayerByUserId(userId)
			if player then self:_teleportPlayerDirect(match, player, spawn1) end
		end
	end
	if spawn2 then
		for _, userId in match.team2 do
			local player = Players:GetPlayerByUserId(userId)
			if player then self:_teleportPlayerDirect(match, player, spawn2) end
		end
	end
end

function MatchManager:_teleportPlayerDirect(match, player, spawn)
	local spawnCFrame
	if spawn:IsA("BasePart") then
		spawnCFrame = spawn.CFrame + Vector3.new(0, 3, 0)
	else
		spawnCFrame = CFrame.new(spawn.Position + Vector3.new(0, 3, 0))
	end

	-- Fire client teleport (MovementController handles position)
	-- roundReset = true so client does full character refresh (viewmodel, weapons, etc.)
	self._net:FireClient("MatchTeleport", player, {
		matchId = match.id,
		spawnPosition = spawnCFrame.Position,
		spawnLookVector = spawnCFrame.LookVector,
		roundReset = true,
	})

	-- Heal humanoid
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
	local match = self._matches[matchId]
	if not match then return end

	match.state = "ended"

	-- Unfreeze just in case
	self:_unfreezeMatchPlayers(match)

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
	if not match then return end

	-- Clear freeze state before returning to lobby
	self:_unfreezeMatchPlayers(match)

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

	self._net:FireAllClients("ReturnToLobby", { matchId = matchId })
end

function MatchManager:_returnPlayersToLobby(match)
	local userIds = {}
	for _, uid in match.team1 do table.insert(userIds, uid) end
	for _, uid in match.team2 do table.insert(userIds, uid) end
	destroyMobWallsForUserIds(userIds)

	local lobbySpawns = CollectionService:GetTagged(MatchmakingConfig.Spawns.LobbyTag)
	if #lobbySpawns == 0 then return end

	for i, userId in ipairs(userIds) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			-- Set PlayerState back to Lobby (overhead will reappear)
			player:SetAttribute("PlayerState", "Lobby")
			local spawnIndex = ((i - 1) % #lobbySpawns) + 1
			local spawn = lobbySpawns[spawnIndex]
			self:_teleportPlayerToSpawn(player, spawn)
		end
	end
end

function MatchManager:_teleportPlayerToSpawn(player, spawn)
	local spawnCFrame
	if spawn:IsA("BasePart") then
		spawnCFrame = spawn.CFrame + Vector3.new(0, 3, 0)
	else
		spawnCFrame = CFrame.new(spawn.Position + Vector3.new(0, 3, 0))
	end

	self._net:FireClient("MatchTeleport", player, {
		matchId = "reset",
		spawnPosition = spawnCFrame.Position,
		spawnLookVector = spawnCFrame.LookVector,
	})

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.Health = humanoid.MaxHealth end
	end
end

--------------------------------------------------------------------------------
-- PLAYER LEFT
--------------------------------------------------------------------------------

function MatchManager:_handlePlayerLeft(matchId, player)
	local match = self._matches[matchId]
	if not match then return end

	self._playerToMatch[player] = nil
	destroyMobWallsForUserIds({ player.UserId })

	local userId = player.UserId
	local idx1 = table.find(match.team1, userId)
	if idx1 then table.remove(match.team1, idx1) end
	local idx2 = table.find(match.team2, userId)
	if idx2 then table.remove(match.team2, idx2) end

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
