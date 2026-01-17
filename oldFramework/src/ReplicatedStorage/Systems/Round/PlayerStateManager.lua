local PlayerStateManager = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local RemoteEvents = require(Locations.Modules.RemoteEvents)

-- =============================================================================
-- PLAYER STATES
-- =============================================================================

PlayerStateManager.States = {
	Lobby = "Lobby", -- In the lobby, eligible for match start
	AFK = "AFK", -- In the lobby but excluded from loading into matches (player-toggled)
	Runner = "Runner", -- Active player trying to survive
	Tagger = "Tagger", -- Active player trying to tag runners
	Ghost = "Ghost", -- Dead/tagged player spectating
	Spectator = "Spectator", -- Players who were taggers in previous round
}

-- State tracking
PlayerStateManager.PlayerStates = {} -- { [player] = state }
PlayerStateManager.StateChangeCallbacks = {} -- { [callbackId] = callback }
local nextCallbackId = 1

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function PlayerStateManager:Init()
	Log:RegisterCategory("PLAYERSTATE", "Player state management for round system")

	-- Initialize all connected players to Lobby state
	for _, player in ipairs(Players:GetPlayers()) do
		self:SetState(player, self.States.Lobby)
	end

	-- Handle new players joining
	Players.PlayerAdded:Connect(function(player)
		self:SetState(player, self.States.Lobby)
	end)

	-- Cleanup when players leave
	Players.PlayerRemoving:Connect(function(player)
		self:RemovePlayer(player)
	end)

	-- Server-side AFK toggle handling
	if game:GetService("RunService"):IsServer() then
		RemoteEvents:ConnectServer("AFKToggle", function(player)
			self:ToggleAFK(player)
		end)
	end

	Log:Info("PLAYERSTATE", "PlayerStateManager initialized")
end

-- =============================================================================
-- STATE MANAGEMENT
-- =============================================================================

function PlayerStateManager:SetState(player, newState)
	if not player or not Players:FindFirstChild(player.Name) then
		Log:Warn("PLAYERSTATE", "Attempted to set state for invalid player", {
			Player = player and player.Name or "nil",
			State = newState,
		})
		return false
	end

	local oldState = self.PlayerStates[player]

	-- Validate state
	local validState = false
	for _, state in pairs(self.States) do
		if state == newState then
			validState = true
			break
		end
	end

	if not validState then
		Log:Error("PLAYERSTATE", "Invalid state", { Player = player.Name, State = newState })
		return false
	end

	-- Update state
	self.PlayerStates[player] = newState

	Log:Debug("PLAYERSTATE", "State changed", {
		Player = player.Name,
		OldState = oldState or "None",
		NewState = newState,
	})

	-- Fire callbacks
	self:FireStateChangeCallbacks(player, oldState, newState)

	-- Replicate to clients
	if game:GetService("RunService"):IsServer() then
		RemoteEvents:FireAllClients("PlayerStateChanged", player, newState)
	end

	return true
end

function PlayerStateManager:GetState(player)
	return self.PlayerStates[player] or self.States.Lobby
end

function PlayerStateManager:RemovePlayer(player)
	local state = self.PlayerStates[player]
	self.PlayerStates[player] = nil

	Log:Debug("PLAYERSTATE", "Player removed from state tracking", {
		Player = player.Name,
		LastState = state or "None",
	})
end

-- =============================================================================
-- STATE QUERIES
-- =============================================================================

function PlayerStateManager:GetPlayersByState(state)
	local players = {}
	for player, playerState in pairs(self.PlayerStates) do
		if playerState == state then
			table.insert(players, player)
		end
	end
	return players
end

function PlayerStateManager:CountPlayersByState(state)
	local count = 0
	for _, playerState in pairs(self.PlayerStates) do
		if playerState == state then
			count = count + 1
		end
	end
	return count
end

function PlayerStateManager:GetAllPlayerStates()
	return table.clone(self.PlayerStates)
end

-- =============================================================================
-- BULK STATE TRANSITIONS
-- =============================================================================

function PlayerStateManager:TransitionPlayers(fromState, toState)
	local players = self:GetPlayersByState(fromState)
	local count = 0

	for _, player in ipairs(players) do
		if self:SetState(player, toState) then
			count = count + 1
		end
	end

	Log:Info("PLAYERSTATE", "Bulk state transition", {
		FromState = fromState,
		ToState = toState,
		Count = count,
	})

	return count
end

function PlayerStateManager:TransitionMultipleStates(fromStates, toState)
	local count = 0

	for _, fromState in ipairs(fromStates) do
		count = count + self:TransitionPlayers(fromState, toState)
	end

	return count
end

-- =============================================================================
-- AFK SYSTEM
-- =============================================================================

function PlayerStateManager:ToggleAFK(player)
	local currentState = self:GetState(player)

	if currentState == self.States.AFK then
		-- Return to Lobby
		self:SetState(player, self.States.Lobby)
		Log:Info("PLAYERSTATE", "Player returned from AFK", { Player = player.Name })
		return self.States.Lobby
	elseif currentState == self.States.Lobby then
		-- Mark as AFK
		self:SetState(player, self.States.AFK)
		Log:Info("PLAYERSTATE", "Player marked as AFK", { Player = player.Name })
		return self.States.AFK
	else
		-- Can only toggle AFK in Lobby state
		Log:Warn("PLAYERSTATE", "Cannot toggle AFK outside of Lobby", {
			Player = player.Name,
			CurrentState = currentState,
		})
		return currentState
	end
end

function PlayerStateManager:SetAFK(player, isAFK)
	local currentState = self:GetState(player)

	if currentState ~= self.States.Lobby and currentState ~= self.States.AFK then
		Log:Warn("PLAYERSTATE", "Cannot set AFK outside of Lobby", {
			Player = player.Name,
			CurrentState = currentState,
		})
		return false
	end

	local targetState = isAFK and self.States.AFK or self.States.Lobby
	return self:SetState(player, targetState)
end

-- =============================================================================
-- CALLBACKS
-- =============================================================================

function PlayerStateManager:RegisterStateChangeCallback(callback)
	local id = nextCallbackId
	nextCallbackId = nextCallbackId + 1

	self.StateChangeCallbacks[id] = callback

	Log:Debug("PLAYERSTATE", "Registered state change callback", { CallbackId = id })

	-- Return cleanup function
	return function()
		self.StateChangeCallbacks[id] = nil
		Log:Debug("PLAYERSTATE", "Unregistered state change callback", { CallbackId = id })
	end
end

function PlayerStateManager:FireStateChangeCallbacks(player, oldState, newState)
	for id, callback in pairs(self.StateChangeCallbacks) do
		local success, err = pcall(callback, player, oldState, newState)
		if not success then
			Log:Error("PLAYERSTATE", "State change callback error", {
				CallbackId = id,
				Error = err,
			})
		end
	end
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

function PlayerStateManager:IsInActiveRound(player)
	local state = self:GetState(player)
	return state == self.States.Runner or state == self.States.Tagger
end

function PlayerStateManager:CanStartMatch()
	local lobbyCount = self:CountPlayersByState(self.States.Lobby)
	local Config = require(Locations.Modules.Config)
	return lobbyCount >= Config.Round.Players.MinPlayers
end

function PlayerStateManager:GetActivePlayerCount()
	return self:CountPlayersByState(self.States.Runner) + self:CountPlayersByState(self.States.Tagger)
end

function PlayerStateManager:ResetAllToLobby()
	for player, _ in pairs(self.PlayerStates) do
		if self:GetState(player) ~= self.States.AFK then
			self:SetState(player, self.States.Lobby)
		end
	end

	Log:Info("PLAYERSTATE", "Reset all non-AFK players to Lobby")
end

return PlayerStateManager
