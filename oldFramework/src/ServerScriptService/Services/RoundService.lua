local RoundService = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)

-- Systems
local PlayerStateManager = require(Locations.Modules.Systems.Round.PlayerStateManager)

-- Server modules (loaded dynamically)
local CombinedStateManager = nil
local MapSelector = nil
local MapLoader = nil
local SpawnManager = nil
local DisconnectBuffer = nil

-- Phase modules (loaded dynamically)
local IntermissionPhase = nil
local RoundStartPhase = nil
local RoundPhase = nil
local RoundEndPhase = nil

-- State
RoundService.CurrentPhase = nil
RoundService.PhaseNames = {
	Intermission = "Intermission",
	RoundStart = "RoundStart",
	Round = "Round",
	RoundEnd = "RoundEnd",
}
RoundService.IsRunning = false
RoundService.HeartbeatConnection = nil

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function RoundService:Init()
	Log:RegisterCategory("ROUNDSERVICE", "Round system orchestration")

	-- Check if round system is enabled
	local RoundConfig = require(Locations.Modules.Config.RoundConfig)
	if not RoundConfig.Enabled then
		Log:Info("ROUNDSERVICE", "Round system disabled in config - skipping initialization")
		return
	end

	-- Load systems
	CombinedStateManager = require(ReplicatedStorage.Systems.Round.CombinedStateManager)

	-- Load server modules
	MapSelector = require(ServerStorage.Modules.MapSelector)
	MapLoader = require(ServerStorage.Modules.MapLoader)
	SpawnManager = require(ServerStorage.Modules.SpawnManager)
	DisconnectBuffer = require(ServerStorage.Modules.DisconnectBuffer)

	-- Load phase modules
	local phasesFolder = ServerStorage.Modules.Phases
	IntermissionPhase = require(phasesFolder.IntermissionPhase)
	RoundStartPhase = require(phasesFolder.RoundStartPhase)
	RoundPhase = require(phasesFolder.RoundPhase)
	RoundEndPhase = require(phasesFolder.RoundEndPhase)

	-- Initialize systems
	PlayerStateManager:Init()
	MapSelector:Init()
	MapLoader:Init()
	SpawnManager:Init()
	DisconnectBuffer:Init()

	-- Create dependencies table for phases
	local dependencies = {
		PlayerStateManager = PlayerStateManager,
		CombinedStateManager = CombinedStateManager,
		MapSelector = MapSelector,
		MapLoader = MapLoader,
		SpawnManager = SpawnManager,
		DisconnectBuffer = DisconnectBuffer,
	}

	-- Initialize phases
	IntermissionPhase:Init(dependencies)
	RoundStartPhase:Init(dependencies)
	RoundPhase:Init(dependencies)
	RoundEndPhase:Init(dependencies)

	-- Validate lobby exists
	if not MapLoader:ValidateLobbyExists() then
		Log:Error("ROUNDSERVICE", "CRITICAL: Lobby validation failed - round system cannot start")
		return
	end

	Log:Info("ROUNDSERVICE", "RoundService initialized")

	-- Start the round system
	self:StartRoundSystem()
end

-- =============================================================================
-- ROUND SYSTEM CONTROL
-- =============================================================================

function RoundService:StartRoundSystem()
	if self.IsRunning then
		Log:Warn("ROUNDSERVICE", "Round system already running")
		return
	end

	self.IsRunning = true

	-- Start with Intermission phase
	self:TransitionToPhase(self.PhaseNames.Intermission)

	-- Setup heartbeat for phase updates
	self.HeartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:UpdateCurrentPhase(deltaTime)
	end)

	Log:Info("ROUNDSERVICE", "Round system started")
end

function RoundService:StopRoundSystem()
	if not self.IsRunning then
		return
	end

	self.IsRunning = false

	-- Disconnect heartbeat
	if self.HeartbeatConnection then
		self.HeartbeatConnection:Disconnect()
		self.HeartbeatConnection = nil
	end

	-- End current phase
	if self.CurrentPhase then
		self.CurrentPhase:End()
	end

	Log:Info("ROUNDSERVICE", "Round system stopped")
end

-- =============================================================================
-- PHASE MANAGEMENT
-- =============================================================================

function RoundService:TransitionToPhase(phaseName)
	-- End current phase
	if self.CurrentPhase then
		self.CurrentPhase:End()
	end

	-- Get new phase module
	local newPhase = self:GetPhaseModule(phaseName)

	if not newPhase then
		Log:Error("ROUNDSERVICE", "Invalid phase name", { Phase = phaseName })
		return false
	end

	-- Set as current phase
	self.CurrentPhase = newPhase

	Log:Info("ROUNDSERVICE", "Transitioning to phase", { Phase = phaseName })

	-- Start new phase
	newPhase:Start()

	return true
end

function RoundService:UpdateCurrentPhase(deltaTime)
	if not self.CurrentPhase then
		return
	end

	-- Update phase and check if complete
	local isComplete = self.CurrentPhase:Update(deltaTime)

	if isComplete then
		-- Determine next phase
		local nextPhase = self:DetermineNextPhase()

		if nextPhase then
			self:TransitionToPhase(nextPhase)
		else
			Log:Error("ROUNDSERVICE", "Could not determine next phase")
		end
	end
end

function RoundService:DetermineNextPhase()
	local currentPhaseName = self:GetCurrentPhaseName()

	if currentPhaseName == self.PhaseNames.Intermission then
		return self.PhaseNames.RoundStart
	elseif currentPhaseName == self.PhaseNames.RoundStart then
		return self.PhaseNames.Round
	elseif currentPhaseName == self.PhaseNames.Round then
		return self.PhaseNames.RoundEnd
	elseif currentPhaseName == self.PhaseNames.RoundEnd then
		-- Check RoundEndPhase to determine next
		return RoundEndPhase:GetNextPhase()
	end

	return nil
end

function RoundService:GetPhaseModule(phaseName)
	if phaseName == self.PhaseNames.Intermission then
		return IntermissionPhase
	elseif phaseName == self.PhaseNames.RoundStart then
		return RoundStartPhase
	elseif phaseName == self.PhaseNames.Round then
		return RoundPhase
	elseif phaseName == self.PhaseNames.RoundEnd then
		return RoundEndPhase
	end

	return nil
end

function RoundService:GetCurrentPhaseName()
	if self.CurrentPhase == IntermissionPhase then
		return self.PhaseNames.Intermission
	elseif self.CurrentPhase == RoundStartPhase then
		return self.PhaseNames.RoundStart
	elseif self.CurrentPhase == RoundPhase then
		return self.PhaseNames.Round
	elseif self.CurrentPhase == RoundEndPhase then
		return self.PhaseNames.RoundEnd
	end

	return "Unknown"
end

-- =============================================================================
-- GETTERS
-- =============================================================================

function RoundService:GetCurrentPhase()
	return self:GetCurrentPhaseName()
end

function RoundService:GetPhaseTimer()
	if self.CurrentPhase and self.CurrentPhase.GetTimer then
		return self.CurrentPhase:GetTimer()
	end
	return 0
end

function RoundService:IsSystemRunning()
	return self.IsRunning
end

-- =============================================================================
-- DEBUG FUNCTIONS
-- =============================================================================

function RoundService:ForcePhaseTransition(phaseName)
	Log:Warn("ROUNDSERVICE", "Forcing phase transition (DEBUG)", { Phase = phaseName })
	self:TransitionToPhase(phaseName)
end

function RoundService:GetDebugInfo()
	return {
		IsRunning = self.IsRunning,
		CurrentPhase = self:GetCurrentPhaseName(),
		PhaseTimer = self:GetPhaseTimer(),
		LobbyPlayers = PlayerStateManager:CountPlayersByState(PlayerStateManager.States.Lobby),
		Runners = PlayerStateManager:CountPlayersByState(PlayerStateManager.States.Runner),
		Taggers = PlayerStateManager:CountPlayersByState(PlayerStateManager.States.Tagger),
		Ghosts = PlayerStateManager:CountPlayersByState(PlayerStateManager.States.Ghost),
		MapLoaded = MapLoader:IsMapLoaded(),
		MapName = MapLoader:GetMapName(),
	}
end

return RoundService
