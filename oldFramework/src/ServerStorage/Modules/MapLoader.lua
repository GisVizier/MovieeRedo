local MapLoader = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local Config = require(Locations.Modules.Config)
local RemoteEvents = require(Locations.Modules.RemoteEvents)

-- State
MapLoader.CurrentMap = nil -- Reference to currently loaded map in workspace
MapLoader.CurrentMapModel = nil -- Reference to source map model in ServerStorage
MapLoader.MapWeightApplied = false -- Track if current map's weight has been applied

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function MapLoader:Init()
	Log:RegisterCategory("MAPLOAD", "Map loading, cloning, and cleanup")
	Log:Info("MAPLOAD", "MapLoader initialized")
end

-- =============================================================================
-- MAP LOADING
-- =============================================================================

function MapLoader:LoadMap(mapModel)
	if not mapModel then
		Log:Error("MAPLOAD", "Cannot load nil map")
		return false
	end

	-- Validate map has required folders
	if not self:ValidateMap(mapModel) then
		Log:Error("MAPLOAD", "Map validation failed", { MapName = mapModel.Name })
		return false
	end

	-- Clean up existing map if any
	if self.CurrentMap then
		self:UnloadCurrentMap()
	end

	-- Clone the map
	local success, clonedMap = pcall(function()
		return mapModel:Clone()
	end)

	if not success or not clonedMap then
		Log:Error("MAPLOAD", "Failed to clone map", {
			MapName = mapModel.Name,
			Error = clonedMap,
		})
		return false
	end

	-- Maps should already be positioned correctly in ServerStorage
	-- Parent to workspace to make visible
	clonedMap.Parent = Workspace

	-- Store references
	self.CurrentMap = clonedMap
	self.CurrentMapModel = mapModel
	self.MapWeightApplied = false -- Reset weight flag for new map

	Log:Info("MAPLOAD", "Map loaded successfully", {
		MapName = mapModel.Name,
		ChildCount = #clonedMap:GetChildren(),
	})

	-- Notify clients that map has loaded
	RemoteEvents:FireAllClients("MapLoaded", mapModel.Name)

	return true
end

function MapLoader:UnloadCurrentMap()
	if not self.CurrentMap then
		return true
	end

	local mapName = self.CurrentMap.Name

	-- Destroy the map
	local success, err = pcall(function()
		self.CurrentMap:Destroy()
	end)

	if not success then
		Log:Error("MAPLOAD", "Failed to destroy map", {
			MapName = mapName,
			Error = err,
		})
		return false
	end

	-- Clear references
	self.CurrentMap = nil
	self.CurrentMapModel = nil
	self.MapWeightApplied = false -- Reset weight flag

	Log:Info("MAPLOAD", "Map unloaded successfully", { MapName = mapName })

	return true
end

-- =============================================================================
-- MAP VALIDATION
-- =============================================================================

function MapLoader:ValidateMap(mapModel)
	if not mapModel:IsA("Model") then
		Log:Error("MAPLOAD", "Map is not a Model", { Type = mapModel.ClassName })
		return false
	end

	-- Check for Spawns folder
	local spawnsFolder = mapModel:FindFirstChild(Config.Round.Spawns.SpawnsFolderName)
	if not spawnsFolder then
		Log:Error("MAPLOAD", "Map missing Spawns folder", {
			MapName = mapModel.Name,
			ExpectedFolder = Config.Round.Spawns.SpawnsFolderName,
		})
		return false
	end

	-- Check that Spawns has at least one spawn point
	local spawnCount = #spawnsFolder:GetChildren()
	if spawnCount == 0 then
		Log:Error("MAPLOAD", "Spawns folder is empty", { MapName = mapModel.Name })
		return false
	end

	-- Check for GhostSpawns folder
	local ghostSpawnsFolder = mapModel:FindFirstChild(Config.Round.Spawns.GhostSpawnsFolderName)
	if not ghostSpawnsFolder then
		Log:Warn("MAPLOAD", "Map missing GhostSpawns folder (will use Spawns as fallback)", {
			MapName = mapModel.Name,
			ExpectedFolder = Config.Round.Spawns.GhostSpawnsFolderName,
		})
		-- Not a critical error, we can use regular spawns for ghosts
	end

	Log:Debug("MAPLOAD", "Map validation passed", {
		MapName = mapModel.Name,
		SpawnCount = spawnCount,
		HasGhostSpawns = ghostSpawnsFolder ~= nil,
	})

	return true
end

-- =============================================================================
-- MAP QUERIES
-- =============================================================================

function MapLoader:GetCurrentMap()
	return self.CurrentMap
end

function MapLoader:GetCurrentMapModel()
	return self.CurrentMapModel
end

function MapLoader:IsMapLoaded()
	return self.CurrentMap ~= nil and self.CurrentMap.Parent == Workspace
end

function MapLoader:GetMapName()
	if self.CurrentMap then
		return self.CurrentMap.Name
	end
	return nil
end

function MapLoader:GetSpawnsFolder()
	if not self.CurrentMap then
		return nil
	end

	return self.CurrentMap:FindFirstChild(Config.Round.Spawns.SpawnsFolderName)
end

function MapLoader:GetGhostSpawnsFolder()
	if not self.CurrentMap then
		return nil
	end

	local ghostSpawns = self.CurrentMap:FindFirstChild(Config.Round.Spawns.GhostSpawnsFolderName)

	-- Fallback to regular spawns if ghost spawns don't exist
	if not ghostSpawns then
		Log:Debug("MAPLOAD", "Using regular spawns for ghosts (no GhostSpawns folder)")
		return self:GetSpawnsFolder()
	end

	return ghostSpawns
end

function MapLoader:GetSpawnCount()
	local spawnsFolder = self:GetSpawnsFolder()
	if not spawnsFolder then
		return 0
	end

	return #spawnsFolder:GetChildren()
end

function MapLoader:GetGhostSpawnCount()
	local ghostSpawnsFolder = self:GetGhostSpawnsFolder()
	if not ghostSpawnsFolder then
		return 0
	end

	return #ghostSpawnsFolder:GetChildren()
end

function MapLoader:IsMapWeightApplied()
	return self.MapWeightApplied
end

function MapLoader:SetMapWeightApplied()
	self.MapWeightApplied = true
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

function MapLoader:CanAccommodatePlayers(playerCount)
	if not self:IsMapLoaded() then
		return false
	end

	local spawnCount = self:GetSpawnCount()
	return spawnCount >= playerCount
end

function MapLoader:GetLobbySpawn()
	-- Find the permanent Lobby model in workspace
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		-- Wait for Lobby to load (similar to interactables pattern)
		Log:Debug("MAPLOAD", "Waiting for Lobby model to load")
		local startTime = tick()
		while not lobby and (tick() - startTime) < 10 do
			task.wait(0.1)
			lobby = Workspace:FindFirstChild("Lobby")
		end

		if not lobby then
			Log:Error("MAPLOAD", "Lobby model not found in workspace after waiting")
			return nil
		end
	end

	-- Find the Spawn part inside Lobby
	local spawnPart = lobby:FindFirstChild("Spawn")
	if not spawnPart then
		-- Wait for Spawn part to load
		Log:Debug("MAPLOAD", "Waiting for Spawn part in Lobby")
		local startTime = tick()
		while not spawnPart and (tick() - startTime) < 5 do
			task.wait(0.1)
			spawnPart = lobby:FindFirstChild("Spawn")
		end

		if not spawnPart then
			Log:Error("MAPLOAD", "Spawn part not found in Lobby model after waiting")
			return nil
		end
	end

	Log:Debug("MAPLOAD", "Lobby spawn found", { Position = spawnPart.Position })
	return spawnPart
end

function MapLoader:ValidateLobbyExists()
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		Log:Error("MAPLOAD", "CRITICAL: Lobby model not found in workspace")
		return false
	end

	local spawnPart = lobby:FindFirstChild("Spawn")
	if not spawnPart then
		Log:Error("MAPLOAD", "CRITICAL: Spawn part not found in Lobby model")
		return false
	end

	Log:Debug("MAPLOAD", "Lobby validation passed")
	return true
end

-- =============================================================================
-- DEBUG FUNCTIONS
-- =============================================================================

function MapLoader:GetDebugInfo()
	return {
		IsMapLoaded = self:IsMapLoaded(),
		MapName = self:GetMapName(),
		SpawnCount = self:GetSpawnCount(),
		GhostSpawnCount = self:GetGhostSpawnCount(),
		LobbyExists = self:ValidateLobbyExists(),
	}
end

return MapLoader
