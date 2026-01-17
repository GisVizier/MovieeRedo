local RoundStartPhase = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local RoundConfig = require(Locations.Modules.Config.RoundConfig)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local MapSelector = require(ServerStorage:WaitForChild("Modules").MapSelector)

-- Dependencies (injected by RoundService)
local PlayerStateManager = nil
local CombinedStateManager = nil
local MapLoader = nil
local SpawnManager = nil

-- State
RoundStartPhase.Timer = 0
RoundStartPhase.IsRunning = false
RoundStartPhase.SpawnAssignments = {} -- Track spawn assignments for disconnect handling
RoundStartPhase.DisconnectCallbackCleanup = nil -- Cleanup function for disconnect callback

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function RoundStartPhase:Init(dependencies)
	PlayerStateManager = dependencies.PlayerStateManager
	CombinedStateManager = dependencies.CombinedStateManager
	MapLoader = dependencies.MapLoader
	SpawnManager = dependencies.SpawnManager

	Log:RegisterCategory("ROUNDSTART", "Round start phase logic")
	Log:Info("ROUNDSTART", "RoundStartPhase initialized")

	-- Setup disconnect handling during RoundStart
	self:SetupDisconnectHandling()
end

-- =============================================================================
-- PHASE LIFECYCLE
-- =============================================================================

function RoundStartPhase:Start()
	self.IsRunning = true
	self.Timer = RoundConfig.Timers.RoundStart

	Log:Info("ROUNDSTART", "Phase started", { Duration = self.Timer })

	-- Keep current map (loaded in Intermission or RoundEnd)
	-- Confirm map usage now (if loaded by RoundEnd, weight wasn't applied yet)
	local currentMap = MapLoader:GetCurrentMapModel()
	if currentMap and not MapLoader:IsMapWeightApplied() then
		MapSelector:ConfirmMapUsed(currentMap)
		MapLoader:SetMapWeightApplied()
	end

	-- All Runners stay at their current spawn positions

	-- Store current spawn assignments for disconnect handling
	local runnerEntities = CombinedStateManager:GetCombinedEntitiesByState(PlayerStateManager.States.Runner)
	local spawnsFolder = MapLoader:GetSpawnsFolder()

	if spawnsFolder then
		self.SpawnAssignments = SpawnManager:AssignMapSpawns(runnerEntities, spawnsFolder)
	end

	-- Freeze all Runners
	local runners = PlayerStateManager:GetPlayersByState(PlayerStateManager.States.Runner)
	SpawnManager:FreezePlayers(runners)

	-- Convert all Spectators to Ghosts
	PlayerStateManager:TransitionPlayers(PlayerStateManager.States.Spectator, PlayerStateManager.States.Ghost)

	-- Spawn Ghosts at GhostSpawns
	local ghosts = PlayerStateManager:GetPlayersByState(PlayerStateManager.States.Ghost)
	local ghostSpawnsFolder = MapLoader:GetGhostSpawnsFolder()

	if ghostSpawnsFolder then
		SpawnManager:SpawnGhosts(ghosts, ghostSpawnsFolder)
		Log:Info("ROUNDSTART", "Spawned ghosts", { Count = #ghosts })
	else
		Log:Warn("ROUNDSTART", "No ghost spawns folder found")
	end

	-- Broadcast phase change
	RemoteEvents:FireAllClients("PhaseChanged", "RoundStart", self.Timer, MapLoader:GetMapName())
end

function RoundStartPhase:Update(deltaTime)
	if not self.IsRunning then
		return false
	end

	self.Timer = self.Timer - deltaTime

	if self.Timer <= 0 then
		return true -- Signal phase complete
	end

	return false
end

function RoundStartPhase:End()
	self.IsRunning = false
	self.SpawnAssignments = {} -- Clear spawn assignments

	-- Cleanup disconnect callback
	if self.DisconnectCallbackCleanup then
		self.DisconnectCallbackCleanup()
		self.DisconnectCallbackCleanup = nil
	end

	Log:Info("ROUNDSTART", "Phase ended")
end

-- =============================================================================
-- DISCONNECT HANDLING
-- =============================================================================

function RoundStartPhase:SetupDisconnectHandling()
	-- Register callback for player state changes (includes disconnects)
	self.DisconnectCallbackCleanup = PlayerStateManager:RegisterStateChangeCallback(
		function(_player, oldState, newState)
			-- Only handle during RoundStart phase
			if not self.IsRunning then
				return
			end

			-- If a Runner disconnects during RoundStart, reassign spawns
			if oldState == PlayerStateManager.States.Runner and newState == nil then
				self:ReassignSpawnsAfterDisconnect()
			end
		end
	)
end

function RoundStartPhase:ReassignSpawnsAfterDisconnect()
	-- Get remaining runners
	local runnerEntities = CombinedStateManager:GetCombinedEntitiesByState(PlayerStateManager.States.Runner)

	if #runnerEntities == 0 then
		Log:Warn("ROUNDSTART", "No runners remaining after disconnect")
		return
	end

	-- Get spawns folder
	local spawnsFolder = MapLoader:GetSpawnsFolder()
	if not spawnsFolder then
		Log:Error("ROUNDSTART", "Cannot reassign spawns - no spawns folder")
		return
	end

	-- Reassign spawns to remaining runners
	self.SpawnAssignments = SpawnManager:AssignMapSpawns(runnerEntities, spawnsFolder)

	-- Teleport runners to new spawn assignments
	SpawnManager:TeleportPlayersToSpawns(self.SpawnAssignments)

	Log:Info("ROUNDSTART", "Reassigned spawns after disconnect", {
		RemainingRunners = #runnerEntities,
	})
end

-- =============================================================================
-- GETTERS
-- =============================================================================

function RoundStartPhase:GetTimer()
	return self.Timer
end

return RoundStartPhase
