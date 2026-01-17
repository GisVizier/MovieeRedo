local CombinedStateManager = {}

-- This module combines Player and NPC state queries for the round system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)

local PlayerStateManager = require(Locations.Modules.Systems.Round.PlayerStateManager)
local NPCStateManager = require(Locations.Modules.Systems.Round.NPCStateManager)

-- =============================================================================
-- COMBINED QUERIES (Players + NPCs)
-- =============================================================================

function CombinedStateManager:GetCombinedCountByState(state)
	local playerCount = PlayerStateManager:CountPlayersByState(state)
	local npcCount = NPCStateManager:CountNPCsByState(state)
	return playerCount + npcCount
end

function CombinedStateManager:GetLobbyCount()
	return self:GetCombinedCountByState(PlayerStateManager.States.Lobby)
end

function CombinedStateManager:GetRunnerCount()
	return self:GetCombinedCountByState(PlayerStateManager.States.Runner)
end

function CombinedStateManager:GetTaggerCount()
	return self:GetCombinedCountByState(PlayerStateManager.States.Tagger)
end

function CombinedStateManager:GetGhostCount()
	return self:GetCombinedCountByState(PlayerStateManager.States.Ghost)
end

function CombinedStateManager:GetSpectatorCount()
	return self:GetCombinedCountByState(PlayerStateManager.States.Spectator)
end

-- =============================================================================
-- TRANSITION HELPERS
-- =============================================================================

function CombinedStateManager:TransitionAll(fromState, toState)
	local playerCount = PlayerStateManager:TransitionPlayers(fromState, toState)
	local npcCount = NPCStateManager:TransitionNPCs(fromState, toState)
	return playerCount + npcCount
end

function CombinedStateManager:ResetAllToLobby()
	PlayerStateManager:ResetAllToLobby()
	NPCStateManager:ResetAllToLobby()
end

-- =============================================================================
-- COMBINED ENTITY LISTS (for spawning, etc.)
-- =============================================================================

function CombinedStateManager:GetCombinedEntitiesByState(state)
	local players = PlayerStateManager:GetPlayersByState(state)
	local npcNames = NPCStateManager:GetNPCsByState(state)

	-- Return a combined table with type information
	local entities = {}

	for _, player in ipairs(players) do
		table.insert(entities, {
			Type = "Player",
			Entity = player,
			Name = player.Name,
		})
	end

	for _, npcName in ipairs(npcNames) do
		table.insert(entities, {
			Type = "NPC",
			Entity = npcName,
			Name = npcName,
		})
	end

	return entities
end

-- =============================================================================
-- SEPARATE ACCESS (when you need to distinguish)
-- =============================================================================

function CombinedStateManager:GetPlayers(state)
	return PlayerStateManager:GetPlayersByState(state)
end

function CombinedStateManager:GetNPCs(state)
	return NPCStateManager:GetNPCsByState(state)
end

-- =============================================================================
-- EXPORT STATE MANAGERS
-- =============================================================================

CombinedStateManager.PlayerStateManager = PlayerStateManager
CombinedStateManager.NPCStateManager = NPCStateManager
CombinedStateManager.States = PlayerStateManager.States

return CombinedStateManager
