local IntermissionPhase = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local RoundConfig = require(Locations.Modules.Config.RoundConfig)
local RemoteEvents = require(Locations.Modules.RemoteEvents)

-- Dependencies (injected by RoundService)
local PlayerStateManager = nil
local CombinedStateManager = nil
local MapSelector = nil
local MapLoader = nil
local SpawnManager = nil
local DisconnectBuffer = nil

-- State
IntermissionPhase.Timer = 0
IntermissionPhase.SelectedMap = nil
IntermissionPhase.IsRunning = false
IntermissionPhase.LastRecalculatedCount = nil -- Last player count when map was selected/swapped
IntermissionPhase.HasSwappedMap = false -- Prevents multiple swaps in one intermission
IntermissionPhase.LastSwapTime = 0 -- Debouncing timer

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function IntermissionPhase:Init(dependencies)
	PlayerStateManager = dependencies.PlayerStateManager
	CombinedStateManager = dependencies.CombinedStateManager
	MapSelector = dependencies.MapSelector
	MapLoader = dependencies.MapLoader
	SpawnManager = dependencies.SpawnManager
	DisconnectBuffer = dependencies.DisconnectBuffer

	Log:RegisterCategory("INTERMISSION", "Intermission phase logic")
	Log:Info("INTERMISSION", "IntermissionPhase initialized")
end

-- =============================================================================
-- PHASE LIFECYCLE
-- =============================================================================

function IntermissionPhase:Start()
	self.IsRunning = true
	self.Timer = RoundConfig.Timers.Intermission
	self.HasSwappedMap = false -- Reset swap tracking
	self.LastSwapTime = 0

	Log:Info("INTERMISSION", "Phase started", { Duration = self.Timer })

	-- Transition all non-Lobby/AFK players and NPCs to Lobby
	local transitioned = 0
	transitioned = transitioned
		+ CombinedStateManager:TransitionAll(PlayerStateManager.States.Runner, PlayerStateManager.States.Lobby)
	transitioned = transitioned
		+ CombinedStateManager:TransitionAll(PlayerStateManager.States.Tagger, PlayerStateManager.States.Lobby)
	transitioned = transitioned
		+ CombinedStateManager:TransitionAll(PlayerStateManager.States.Ghost, PlayerStateManager.States.Lobby)
	transitioned = transitioned
		+ CombinedStateManager:TransitionAll(PlayerStateManager.States.Spectator, PlayerStateManager.States.Lobby)

	Log:Info("INTERMISSION", "Transitioned players and NPCs to Lobby", { Count = transitioned })

	-- Respawn players to lobby
	self:RespawnPlayersToLobby()

	-- Clean up existing map
	MapLoader:UnloadCurrentMap()

	-- Select and load new map
	local lobbyCount = CombinedStateManager:GetLobbyCount()
	self:SelectAndLoadMap()
	self.LastRecalculatedCount = lobbyCount -- Track initial count

	-- Broadcast phase change
	RemoteEvents:FireAllClients(
		"PhaseChanged",
		"Intermission",
		self.Timer,
		self.SelectedMap and self.SelectedMap.Name or "Unknown"
	)
end

function IntermissionPhase:Update(deltaTime)
	if not self.IsRunning then
		return false
	end

	-- Check if we have enough players + NPCs (excluding AFK) BEFORE decrementing timer
	local lobbyCount = CombinedStateManager:GetLobbyCount()
	local afkCount = PlayerStateManager:CountPlayersByState(PlayerStateManager.States.AFK)

	-- Check if all players are AFK
	if lobbyCount == 0 and afkCount > 0 then
		-- All players are AFK - keep timer paused
		self.Timer = RoundConfig.Timers.Intermission
		return false
	end

	-- Check if we have enough players to start countdown
	if lobbyCount < RoundConfig.Players.MinPlayers then
		-- Keep timer reset while waiting for minimum players
		self.Timer = RoundConfig.Timers.Intermission
		return false
	end

	-- Only decrement timer if we have enough players
	self.Timer = self.Timer - deltaTime

	-- Dynamic map recalculation if enabled
	if RoundConfig.DisconnectBuffer.IntermissionRecalculate then
		self:CheckAndRecalculateMap()
	end

	-- Timer expired - transition to next phase
	if self.Timer <= 0 then
		-- Convert Lobby players to Runners and teleport to map spawns
		local success = self:TransitionToRunners()
		if not success then
			-- If transition failed (e.g., map not loaded), extend intermission
			self.Timer = 5
			Log:Warn("INTERMISSION", "Extended intermission - transition to runners failed")
			return false
		end

		-- Confirm map usage NOW (when round actually starts)
		-- This applies the weight penalty and adds to history
		if self.SelectedMap and not MapLoader:IsMapWeightApplied() then
			MapSelector:ConfirmMapUsed(self.SelectedMap)
			MapLoader:SetMapWeightApplied()
		end

		return true -- Signal phase complete
	end

	return false
end

function IntermissionPhase:End()
	self.IsRunning = false
	self.LastRecalculatedCount = nil -- Reset tracking
	self.HasSwappedMap = false
	self.LastSwapTime = 0
	Log:Info("INTERMISSION", "Phase ended")
end

-- =============================================================================
-- PHASE LOGIC
-- =============================================================================

function IntermissionPhase:RespawnPlayersToLobby()
	local lobbySpawn = MapLoader:GetLobbySpawn()
	if not lobbySpawn then
		Log:Error("INTERMISSION", "Cannot respawn - lobby spawn not found")
		return
	end

	-- Get all lobby entities (players and NPCs)
	local lobbyEntities = CombinedStateManager:GetCombinedEntitiesByState(PlayerStateManager.States.Lobby)

	-- Filter entities that have characters
	local entitiesWithCharacters = {}
	for _, entity in ipairs(lobbyEntities) do
		local hasCharacter = false

		if entity.Type == "Player" then
			hasCharacter = entity.Entity.Character and entity.Entity.Character.Parent
		elseif entity.Type == "NPC" then
			-- Check NPC has character via NPCService
			local NPCService = require(game:GetService("ServerScriptService").Services.NPCService)
			local npcData = NPCService:GetNPC(entity.Entity)
			hasCharacter = npcData and npcData.Character and npcData.Character.Parent
		end

		if hasCharacter then
			table.insert(entitiesWithCharacters, entity)
		end
	end

	if #entitiesWithCharacters > 0 then
		SpawnManager:SpawnEntitiesInLobby(entitiesWithCharacters, lobbySpawn)
	end

	Log:Debug("INTERMISSION", "Respawned entities to lobby", {
		Total = #lobbyEntities,
		WithCharacters = #entitiesWithCharacters,
	})
end

function IntermissionPhase:SelectAndLoadMap()
	-- Count lobby players + NPCs for map sizing
	local lobbyCount = CombinedStateManager:GetLobbyCount()

	-- Select map with disconnect protection
	self.SelectedMap = MapSelector:SelectMap(lobbyCount, DisconnectBuffer)

	if not self.SelectedMap then
		Log:Error("INTERMISSION", "Failed to select map", { LobbyCount = lobbyCount })
		return false
	end

	-- Load the selected map
	local loaded = MapLoader:LoadMap(self.SelectedMap)

	if loaded then
		Log:Info("INTERMISSION", "Map selected and loaded", {
			MapName = self.SelectedMap.Name,
			LobbyCount = lobbyCount,
		})
	else
		Log:Error("INTERMISSION", "Failed to load selected map", {
			MapName = self.SelectedMap.Name,
		})
	end

	return loaded
end

function IntermissionPhase:CheckAndRecalculateMap()
	-- Don't recalculate if we've already swapped once
	if self.HasSwappedMap then
		return
	end

	-- Require at least 3 seconds remaining to prevent last-second swaps
	if self.Timer < 3 then
		return
	end

	-- Debouncing: minimum 2 seconds between checks
	local currentTime = tick()
	if currentTime - self.LastSwapTime < 2 then
		return
	end

	-- Get current lobby count
	local currentCount = CombinedStateManager:GetLobbyCount()

	-- Check if we need to recalculate (threshold crossing detected)
	if self:ShouldRecalculateMap(currentCount) then
		self:RecalculateAndSwapMap(currentCount)
	end
end

function IntermissionPhase:ShouldRecalculateMap(currentCount)
	if not self.LastRecalculatedCount then
		return false
	end

	local threshold = RoundConfig.Players.SmallMapThreshold

	-- Determine what map size we currently have loaded
	local wasSmallMap = self.LastRecalculatedCount <= threshold
	-- Determine what map size we should have
	local shouldBeSmallMap = currentCount <= threshold

	-- Check for threshold crossing
	if wasSmallMap ~= shouldBeSmallMap then
		Log:Info("INTERMISSION", "Detected map size threshold crossing", {
			PreviousCount = self.LastRecalculatedCount,
			CurrentCount = currentCount,
			Threshold = threshold,
			WasSmall = wasSmallMap,
			ShouldBeSmall = shouldBeSmallMap,
		})
		return true
	end

	return false
end

function IntermissionPhase:RecalculateAndSwapMap(newCount)
	Log:Info("INTERMISSION", "Recalculating and swapping map", {
		OldCount = self.LastRecalculatedCount,
		NewCount = newCount,
		TimeRemaining = self.Timer,
	})

	-- Unload current map
	MapLoader:UnloadCurrentMap()

	-- Select and load new map based on current count
	self.SelectedMap = MapSelector:SelectMap(newCount, DisconnectBuffer)

	if not self.SelectedMap then
		Log:Error("INTERMISSION", "Failed to select new map during recalculation", {
			PlayerCount = newCount,
		})
		-- Try to reload the old map as fallback
		self:SelectAndLoadMap()
		return false
	end

	-- Load the new map
	local loaded = MapLoader:LoadMap(self.SelectedMap)

	if loaded then
		Log:Info("INTERMISSION", "Successfully swapped to new map", {
			MapName = self.SelectedMap.Name,
			NewCount = newCount,
		})

		-- Update tracking
		self.LastRecalculatedCount = newCount
		self.HasSwappedMap = true
		self.LastSwapTime = tick()

		-- Broadcast map change to clients
		RemoteEvents:FireAllClients("MapRecalculated", self.SelectedMap.Name, newCount)

		return true
	else
		Log:Error("INTERMISSION", "Failed to load new map during recalculation", {
			MapName = self.SelectedMap.Name,
		})
		return false
	end
end

function IntermissionPhase:TransitionToRunners()
	-- Get all lobby entities (players and NPCs)
	local lobbyEntities = CombinedStateManager:GetCombinedEntitiesByState(PlayerStateManager.States.Lobby)

	Log:Info("INTERMISSION", "Converting Lobby entities to Runners", {
		Count = #lobbyEntities,
	})

	-- Convert all Lobby entities to Runner state
	for _, entity in ipairs(lobbyEntities) do
		if entity.Type == "Player" then
			PlayerStateManager:SetState(entity.Entity, PlayerStateManager.States.Runner)
		elseif entity.Type == "NPC" then
			CombinedStateManager.NPCStateManager:SetState(entity.Entity, PlayerStateManager.States.Runner)
		end
	end

	-- Verify map is loaded
	if not MapLoader:IsMapLoaded() then
		Log:Error("INTERMISSION", "Cannot teleport - no map loaded")
		return false
	end

	-- Assign spawns to runners
	local spawnsFolder = MapLoader:GetSpawnsFolder()
	if not spawnsFolder then
		Log:Error("INTERMISSION", "Cannot teleport - no spawns folder")
		return false
	end

	local spawnAssignments = SpawnManager:AssignMapSpawns(lobbyEntities, spawnsFolder)

	-- Teleport runners to their spawns
	local teleported = SpawnManager:TeleportPlayersToSpawns(spawnAssignments)

	Log:Info("INTERMISSION", "Teleported Runners to map spawns", {
		Total = #lobbyEntities,
		Successful = teleported,
	})

	return true
end

-- =============================================================================
-- GETTERS
-- =============================================================================

function IntermissionPhase:GetTimer()
	return self.Timer
end

function IntermissionPhase:GetSelectedMap()
	return self.SelectedMap
end

return IntermissionPhase
