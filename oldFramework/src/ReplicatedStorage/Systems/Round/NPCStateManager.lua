local NPCStateManager = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local RemoteEvents = require(Locations.Modules.RemoteEvents)

-- Import player states from PlayerStateManager for consistency
local PlayerStateManager = require(Locations.Modules.Systems.Round.PlayerStateManager)

-- =============================================================================
-- NPC STATE TRACKING
-- =============================================================================

-- NPCs use the same states as players (except AFK)
NPCStateManager.States = PlayerStateManager.States

-- State tracking
NPCStateManager.NPCStates = {} -- { [npcName] = state }
NPCStateManager.StateChangeCallbacks = {} -- { [callbackId] = callback }
local nextCallbackId = 1

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function NPCStateManager:Init()
	Log:RegisterCategory("NPCSTATE", "NPC state management for round system")
	Log:Info("NPCSTATE", "NPCStateManager initialized")
end

-- =============================================================================
-- STATE MANAGEMENT
-- =============================================================================

function NPCStateManager:SetState(npcName, newState)
	if not npcName then
		Log:Warn("NPCSTATE", "Attempted to set state for nil NPC")
		return false
	end

	local oldState = self.NPCStates[npcName]

	-- Validate state (reuse PlayerStateManager validation)
	local validState = false
	for _, state in pairs(self.States) do
		if state == newState then
			validState = true
			break
		end
	end

	if not validState then
		Log:Error("NPCSTATE", "Invalid state", { NPC = npcName, State = newState })
		return false
	end

	-- NPCs can't be AFK
	if newState == self.States.AFK then
		Log:Warn("NPCSTATE", "NPCs cannot be AFK", { NPC = npcName })
		return false
	end

	-- Update state
	self.NPCStates[npcName] = newState

	Log:Debug("NPCSTATE", "State changed", {
		NPC = npcName,
		OldState = oldState or "None",
		NewState = newState,
	})

	-- Fire callbacks
	self:FireStateChangeCallbacks(npcName, oldState, newState)

	-- Replicate to clients
	if game:GetService("RunService"):IsServer() then
		RemoteEvents:FireAllClients("NPCStateChanged", npcName, newState)
	end

	return true
end

function NPCStateManager:GetState(npcName)
	return self.NPCStates[npcName] or self.States.Lobby
end

function NPCStateManager:RemoveNPC(npcName)
	local state = self.NPCStates[npcName]
	self.NPCStates[npcName] = nil

	Log:Debug("NPCSTATE", "NPC removed from state tracking", {
		NPC = npcName,
		LastState = state or "None",
	})
end

-- =============================================================================
-- STATE QUERIES
-- =============================================================================

function NPCStateManager:GetNPCsByState(state)
	local npcs = {}
	for npcName, npcState in pairs(self.NPCStates) do
		if npcState == state then
			table.insert(npcs, npcName)
		end
	end
	return npcs
end

function NPCStateManager:CountNPCsByState(state)
	local count = 0
	for _, npcState in pairs(self.NPCStates) do
		if npcState == state then
			count = count + 1
		end
	end
	return count
end

function NPCStateManager:GetAllNPCStates()
	return table.clone(self.NPCStates)
end

-- =============================================================================
-- BULK STATE TRANSITIONS
-- =============================================================================

function NPCStateManager:TransitionNPCs(fromState, toState)
	local npcs = self:GetNPCsByState(fromState)
	local count = 0

	for _, npcName in ipairs(npcs) do
		if self:SetState(npcName, toState) then
			count = count + 1
		end
	end

	Log:Info("NPCSTATE", "Bulk NPC state transition", {
		FromState = fromState,
		ToState = toState,
		Count = count,
	})

	return count
end

-- =============================================================================
-- CALLBACKS
-- =============================================================================

function NPCStateManager:RegisterStateChangeCallback(callback)
	local id = nextCallbackId
	nextCallbackId = nextCallbackId + 1

	self.StateChangeCallbacks[id] = callback

	Log:Debug("NPCSTATE", "Registered state change callback", { CallbackId = id })

	-- Return cleanup function
	return function()
		self.StateChangeCallbacks[id] = nil
		Log:Debug("NPCSTATE", "Unregistered state change callback", { CallbackId = id })
	end
end

function NPCStateManager:FireStateChangeCallbacks(npcName, oldState, newState)
	for id, callback in pairs(self.StateChangeCallbacks) do
		local success, err = pcall(callback, npcName, oldState, newState)
		if not success then
			Log:Error("NPCSTATE", "State change callback error", {
				CallbackId = id,
				Error = err,
			})
		end
	end
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

function NPCStateManager:IsInActiveRound(npcName)
	local state = self:GetState(npcName)
	return state == self.States.Runner or state == self.States.Tagger
end

function NPCStateManager:GetActiveNPCCount()
	return self:CountNPCsByState(self.States.Runner) + self:CountNPCsByState(self.States.Tagger)
end

function NPCStateManager:ResetAllToLobby()
	for npcName, _ in pairs(self.NPCStates) do
		self:SetState(npcName, self.States.Lobby)
	end

	Log:Info("NPCSTATE", "Reset all NPCs to Lobby")
end

return NPCStateManager
