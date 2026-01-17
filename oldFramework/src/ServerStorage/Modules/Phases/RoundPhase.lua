local RoundPhase = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local RoundConfig = require(Locations.Modules.Config.RoundConfig)
local RemoteEvents = require(Locations.Modules.RemoteEvents)

-- Dependencies (injected by RoundService)
local PlayerStateManager = nil
local CombinedStateManager = nil
local SpawnManager = nil

-- State
RoundPhase.Timer = 0
RoundPhase.IsRunning = false
RoundPhase.SelectedTaggers = {} -- List of players selected as taggers

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function RoundPhase:Init(dependencies)
	PlayerStateManager = dependencies.PlayerStateManager
	CombinedStateManager = dependencies.CombinedStateManager
	SpawnManager = dependencies.SpawnManager

	Log:RegisterCategory("ROUND", "Active round phase logic")

	-- Setup disconnect handling during Round phase
	Players.PlayerRemoving:Connect(function(player)
		if self.IsRunning then
			self:HandleDisconnect(player)
		end
	end)

	Log:Info("ROUND", "RoundPhase initialized")
end

-- =============================================================================
-- PHASE LIFECYCLE
-- =============================================================================

function RoundPhase:Start()
	self.IsRunning = true
	self.Timer = RoundConfig.Timers.Round
	self.SelectedTaggers = {} -- Clear previous taggers

	Log:Info("ROUND", "Phase started", { Duration = self.Timer })

	-- Unfreeze all Runners (players only, NPCs don't need unfreezing)
	local runnerPlayers = PlayerStateManager:GetPlayersByState(PlayerStateManager.States.Runner)
	SpawnManager:UnfreezePlayers(runnerPlayers)

	-- Get all runner entities (players AND NPCs) for tagger calculation
	local runnerEntities = CombinedStateManager:GetCombinedEntitiesByState(PlayerStateManager.States.Runner)
	local totalRunnerCount = #runnerEntities

	-- Calculate tagger count based on total runners
	local taggerCount = math.floor(totalRunnerCount * RoundConfig.Gameplay.TaggerRatio)

	-- Apply min/max constraints
	taggerCount = math.max(taggerCount, RoundConfig.Gameplay.MinTaggers or 1)
	if RoundConfig.Gameplay.MaxTaggers then
		taggerCount = math.min(taggerCount, RoundConfig.Gameplay.MaxTaggers)
	end

	-- Randomly select taggers from all runner entities
	local selectedTaggerEntities = self:SelectRandomTaggers(runnerEntities, taggerCount)

	-- Transition selected entities to Tagger state
	for _, taggerEntity in ipairs(selectedTaggerEntities) do
		if taggerEntity.Type == "Player" then
			PlayerStateManager:SetState(taggerEntity.Entity, PlayerStateManager.States.Tagger)
			table.insert(self.SelectedTaggers, taggerEntity.Entity) -- Track player taggers for events
		elseif taggerEntity.Type == "NPC" then
			CombinedStateManager.NPCStateManager:SetState(taggerEntity.Entity, PlayerStateManager.States.Tagger)
		end
	end

	Log:Info("ROUND", "Taggers selected", {
		TaggerCount = #selectedTaggerEntities,
		RunnerCount = totalRunnerCount - #selectedTaggerEntities,
	})

	-- Broadcast phase change
	RemoteEvents:FireAllClients("PhaseChanged", "Round", self.Timer)

	-- Notify clients of tagger selections
	for _, tagger in ipairs(self.SelectedTaggers) do
		RemoteEvents:FireAllClients("TaggerSelected", tagger)
	end
end

function RoundPhase:Update(deltaTime)
	if not self.IsRunning then
		return false
	end

	self.Timer = self.Timer - deltaTime

	-- Check end conditions (count both players and NPCs)
	local remainingRunners = CombinedStateManager:GetRunnerCount()
	local remainingTaggers = CombinedStateManager:GetTaggerCount()

	-- End if no runners remain (all tagged - taggers win)
	if remainingRunners == 0 then
		Log:Info("ROUND", "Round ending - All runners tagged")
		return true
	end

	-- End if no taggers remain (all disconnected - runners win by default)
	if remainingTaggers == 0 then
		Log:Info("ROUND", "Round ending - No taggers remaining")
		return true
	end

	-- End if timer expires
	if RoundConfig.Gameplay.TimerEnd and self.Timer <= 0 then
		Log:Info("ROUND", "Round ending - Timer expired")
		return true
	end

	return false
end

function RoundPhase:End()
	self.IsRunning = false
	self.SelectedTaggers = {} -- Clear tagger list

	Log:Info("ROUND", "Phase ended", {
		RemainingRunners = PlayerStateManager:CountPlayersByState(PlayerStateManager.States.Runner),
	})
end

-- =============================================================================
-- TAGGER SELECTION
-- =============================================================================

function RoundPhase:SelectRandomTaggers(runners, count)
	if #runners <= count then
		-- All runners become taggers (shouldn't happen in normal gameplay)
		return table.clone(runners)
	end

	-- Shuffle runners
	local shuffled = table.clone(runners)
	for i = #shuffled, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	-- Take first 'count' players as taggers
	local taggers = {}
	for i = 1, count do
		table.insert(taggers, shuffled[i])
	end

	return taggers
end

-- =============================================================================
-- PLAYER TAGGING (Future implementation)
-- =============================================================================

function RoundPhase:TagPlayer(tagger, runner)
	-- Validate tagger state
	if PlayerStateManager:GetState(tagger) ~= PlayerStateManager.States.Tagger then
		Log:Warn("ROUND", "Non-tagger attempted to tag player", {
			Tagger = tagger.Name,
			TaggerState = PlayerStateManager:GetState(tagger),
		})
		return false
	end

	-- Validate runner state
	if PlayerStateManager:GetState(runner) ~= PlayerStateManager.States.Runner then
		Log:Warn("ROUND", "Attempted to tag non-runner", {
			Runner = runner.Name,
			RunnerState = PlayerStateManager:GetState(runner),
		})
		return false
	end

	-- Transition runner to Ghost
	PlayerStateManager:SetState(runner, PlayerStateManager.States.Ghost)

	Log:Info("ROUND", "Player tagged", {
		Tagger = tagger.Name,
		Runner = runner.Name,
	})

	-- Broadcast tag event
	RemoteEvents:FireAllClients("PlayerTagged", tagger, runner)

	return true
end

-- =============================================================================
-- DISCONNECT HANDLING
-- =============================================================================

function RoundPhase:HandleDisconnect(player)
	local state = PlayerStateManager:GetState(player)

	if state == PlayerStateManager.States.Runner then
		-- Treat disconnected runners as tagged
		if RoundConfig.DisconnectBuffer.RoundTreatAsTagged then
			Log:Info("ROUND", "Disconnected runner treated as tagged", { Player = player.Name })
			-- Player will be removed by PlayerRemoving event in PlayerStateManager
		end
	elseif state == PlayerStateManager.States.Tagger then
		-- Don't replace taggers, just remove them
		Log:Info("ROUND", "Tagger disconnected", { Player = player.Name })
	end
end

-- =============================================================================
-- GETTERS
-- =============================================================================

function RoundPhase:GetTimer()
	return self.Timer
end

function RoundPhase:GetTaggers()
	return table.clone(self.SelectedTaggers)
end

return RoundPhase
