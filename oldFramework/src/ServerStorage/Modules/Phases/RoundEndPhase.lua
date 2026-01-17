local RoundEndPhase = {}

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
RoundEndPhase.Timer = 0
RoundEndPhase.IsRunning = false
RoundEndPhase.NextPhase = nil -- "RoundStart" or "Intermission"
RoundEndPhase.Winners = {}
RoundEndPhase.NewMapLoaded = false

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function RoundEndPhase:Init(dependencies)
	PlayerStateManager = dependencies.PlayerStateManager
	CombinedStateManager = dependencies.CombinedStateManager
	MapSelector = dependencies.MapSelector
	MapLoader = dependencies.MapLoader
	SpawnManager = dependencies.SpawnManager
	DisconnectBuffer = dependencies.DisconnectBuffer

	Log:RegisterCategory("ROUNDEND", "Round end phase logic")
	Log:Info("ROUNDEND", "RoundEndPhase initialized")
end

-- =============================================================================
-- PHASE LIFECYCLE
-- =============================================================================

function RoundEndPhase:Start()
	self.IsRunning = true
	self.Timer = RoundConfig.Timers.RoundEnd
	self.NewMapLoaded = false

	Log:Info("ROUNDEND", "Phase started", { Duration = self.Timer })

	-- Transition all Taggers to Spectators
	PlayerStateManager:TransitionPlayers(PlayerStateManager.States.Tagger, PlayerStateManager.States.Spectator)

	-- Determine winners and next phase
	local remainingRunners = PlayerStateManager:GetPlayersByState(PlayerStateManager.States.Runner)
	self.Winners = table.clone(remainingRunners)

	if #remainingRunners == 1 then
		-- Single winner - go to Intermission
		self.NextPhase = "Intermission"
		Log:Info("ROUNDEND", "Single winner - next phase Intermission", {
			Winner = remainingRunners[1].Name,
		})
	elseif #remainingRunners > 1 then
		-- Multiple survivors - continue with new round
		self.NextPhase = "RoundStart"
		Log:Info("ROUNDEND", "Multiple survivors - next phase RoundStart", {
			SurvivorCount = #remainingRunners,
		})

		-- Select and load new map for next round
		self:SelectAndLoadNewMap(#remainingRunners)
	else
		-- No survivors (all tagged) - go to Intermission
		self.NextPhase = "Intermission"
		Log:Info("ROUNDEND", "No survivors - next phase Intermission")
	end

	-- Increment non-played map weights
	MapSelector:IncrementNonPlayedWeights()

	-- Broadcast results
	self:BroadcastResults()

	-- Broadcast phase change
	RemoteEvents:FireAllClients("PhaseChanged", "RoundEnd", self.Timer)
end

function RoundEndPhase:Update(deltaTime)
	if not self.IsRunning then
		return false
	end

	self.Timer = self.Timer - deltaTime

	if self.Timer <= 0 then
		return true -- Signal phase complete
	end

	return false
end

function RoundEndPhase:End()
	self.IsRunning = false
	Log:Info("ROUNDEND", "Phase ended", { NextPhase = self.NextPhase })
end

-- =============================================================================
-- PHASE LOGIC
-- =============================================================================

function RoundEndPhase:SelectAndLoadNewMap(runnerCount)
	-- Select new map based on remaining runner count
	local selectedMap = MapSelector:SelectMap(runnerCount, DisconnectBuffer)

	if not selectedMap then
		Log:Error("ROUNDEND", "Failed to select new map", { RunnerCount = runnerCount })
		-- Fallback to Intermission if map selection fails
		self.NextPhase = "Intermission"
		return false
	end

	-- Unload old map
	MapLoader:UnloadCurrentMap()

	-- Load new map
	local loaded = MapLoader:LoadMap(selectedMap)

	if loaded then
		self.NewMapLoaded = true
		Log:Info("ROUNDEND", "New map loaded for next round", {
			MapName = selectedMap.Name,
			RunnerCount = runnerCount,
		})

		-- Teleport existing Runners to new map spawns
		self:TeleportRunnersToNewMap()
	else
		Log:Error("ROUNDEND", "Failed to load new map", {
			MapName = selectedMap.Name,
		})
		-- Fallback to Intermission if map loading fails
		self.NextPhase = "Intermission"
		return false
	end

	return true
end

function RoundEndPhase:TeleportRunnersToNewMap()
	-- Get all current Runners (survivors)
	local runnerEntities = CombinedStateManager:GetCombinedEntitiesByState(PlayerStateManager.States.Runner)

	if #runnerEntities == 0 then
		Log:Warn("ROUNDEND", "No runners to teleport to new map")
		return
	end

	-- Get spawns folder from newly loaded map
	local spawnsFolder = MapLoader:GetSpawnsFolder()
	if not spawnsFolder then
		Log:Error("ROUNDEND", "Cannot teleport runners - no spawns folder in new map")
		return
	end

	-- Assign spawns to runners
	local spawnAssignments = SpawnManager:AssignMapSpawns(runnerEntities, spawnsFolder)

	-- Teleport runners to their new spawns
	local teleported = SpawnManager:TeleportPlayersToSpawns(spawnAssignments)

	Log:Info("ROUNDEND", "Teleported Runners to new map", {
		Total = #runnerEntities,
		Successful = teleported,
	})
end

function RoundEndPhase:BroadcastResults()
	local runners = PlayerStateManager:GetPlayersByState(PlayerStateManager.States.Runner)
	local ghosts = PlayerStateManager:GetPlayersByState(PlayerStateManager.States.Ghost)
	local spectators = PlayerStateManager:GetPlayersByState(PlayerStateManager.States.Spectator)

	local results = {
		Winners = {},
		Tagged = {},
		Taggers = {},
	}

	-- Gather winner names
	for _, player in ipairs(runners) do
		table.insert(results.Winners, player.Name)
	end

	-- Gather tagged player names
	for _, player in ipairs(ghosts) do
		table.insert(results.Tagged, player.Name)
	end

	-- Gather tagger names
	for _, player in ipairs(spectators) do
		table.insert(results.Taggers, player.Name)
	end

	-- Broadcast to all clients
	RemoteEvents:FireAllClients("RoundResults", results)

	Log:Info("ROUNDEND", "Results broadcasted", {
		Winners = #results.Winners,
		Tagged = #results.Tagged,
		Taggers = #results.Taggers,
	})
end

-- =============================================================================
-- GETTERS
-- =============================================================================

function RoundEndPhase:GetTimer()
	return self.Timer
end

function RoundEndPhase:GetNextPhase()
	return self.NextPhase
end

function RoundEndPhase:GetWinners()
	return table.clone(self.Winners)
end

function RoundEndPhase:IsNewMapLoaded()
	return self.NewMapLoaded
end

return RoundEndPhase
