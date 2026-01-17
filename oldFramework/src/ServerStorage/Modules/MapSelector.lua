local MapSelector = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local Config = require(Locations.Modules.Config)

-- State
MapSelector.MapWeights = {} -- { [mapModel] = weight }
MapSelector.MapHistory = {} -- Queue of recently played maps
MapSelector.Initialized = false

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function MapSelector:Init()
	if self.Initialized then
		return
	end

	Log:RegisterCategory("MAPSELECT", "Map selection and weight system")

	-- Initialize weights for all maps
	self:InitializeMapWeights()

	self.Initialized = true
	Log:Info("MAPSELECT", "MapSelector initialized", {
		TotalMaps = self:GetTotalMapCount(),
	})
end

function MapSelector:InitializeMapWeights()
	local mapsFolder = ServerStorage:FindFirstChild("Maps")
	if not mapsFolder then
		Log:Error("MAPSELECT", "Maps folder not found in ServerStorage")
		return
	end

	-- Initialize small maps
	local smallFolder = mapsFolder:FindFirstChild(Config.Round.Maps.SmallMapsFolder)
	if smallFolder then
		for _, mapModel in ipairs(smallFolder:GetChildren()) do
			if mapModel:IsA("Model") then
				self.MapWeights[mapModel] = Config.Round.Maps.BaseWeight
			end
		end
	else
		Log:Warn("MAPSELECT", "Small maps folder not found", {
			ExpectedName = Config.Round.Maps.SmallMapsFolder,
		})
	end

	-- Initialize large maps
	local largeFolder = mapsFolder:FindFirstChild(Config.Round.Maps.LargeMapsFolder)
	if largeFolder then
		for _, mapModel in ipairs(largeFolder:GetChildren()) do
			if mapModel:IsA("Model") then
				self.MapWeights[mapModel] = Config.Round.Maps.BaseWeight
			end
		end
	else
		Log:Warn("MAPSELECT", "Large maps folder not found", {
			ExpectedName = Config.Round.Maps.LargeMapsFolder,
		})
	end

	Log:Debug("MAPSELECT", "Initialized map weights", {
		SmallMaps = smallFolder and #smallFolder:GetChildren() or 0,
		LargeMaps = largeFolder and #largeFolder:GetChildren() or 0,
	})
end

-- =============================================================================
-- MAP SELECTION
-- =============================================================================

function MapSelector:SelectMap(playerCount, disconnectBuffer)
	if not self.Initialized then
		self:Init()
	end

	-- Determine map size category
	local threshold = Config.Round.Players.SmallMapThreshold
	local useSmallMaps = playerCount <= threshold

	-- Apply disconnect protection near threshold (within +/- 1 of threshold)
	if playerCount >= threshold - 1 and playerCount <= threshold + 1 then
		-- Check if we're near the threshold and disconnects are likely
		if disconnectBuffer and disconnectBuffer:PredictDisconnects() then
			useSmallMaps = true -- Bias toward smaller map
			Log:Debug("MAPSELECT", "Applying disconnect protection, biasing toward small map", {
				PlayerCount = playerCount,
				Threshold = threshold,
			})
		end
	end

	-- Get eligible maps
	local eligibleMaps = self:GetEligibleMaps(useSmallMaps)

	if #eligibleMaps == 0 then
		Log:Error("MAPSELECT", "No eligible maps found", {
			PlayerCount = playerCount,
			UseSmallMaps = useSmallMaps,
		})
		return nil
	end

	-- Perform weighted random selection
	local selectedMap = self:WeightedRandomSelection(eligibleMaps)

	if selectedMap then
		Log:Info("MAPSELECT", "Map selected", {
			MapName = selectedMap.Name,
			PlayerCount = playerCount,
			MapSize = useSmallMaps and "Small" or "Large",
		})
	end

	-- NOTE: Weight/history updates happen when map is ACTUALLY USED, not when selected
	-- See ConfirmMapUsed() method

	return selectedMap
end

function MapSelector:GetEligibleMaps(useSmallMaps)
	local mapsFolder = ServerStorage:FindFirstChild("Maps")
	if not mapsFolder then
		return {}
	end

	local folderName = useSmallMaps and Config.Round.Maps.SmallMapsFolder or Config.Round.Maps.LargeMapsFolder
	local targetFolder = mapsFolder:FindFirstChild(folderName)

	if not targetFolder then
		Log:Error("MAPSELECT", "Target maps folder not found", { FolderName = folderName })
		return {}
	end

	local eligible = {}
	for _, mapModel in ipairs(targetFolder:GetChildren()) do
		if mapModel:IsA("Model") and self.MapWeights[mapModel] then
			table.insert(eligible, mapModel)
		end
	end

	return eligible
end

function MapSelector:WeightedRandomSelection(maps)
	if #maps == 0 then
		return nil
	end

	if #maps == 1 then
		return maps[1]
	end

	-- Calculate total weight
	local totalWeight = 0
	for _, map in ipairs(maps) do
		totalWeight = totalWeight + (self.MapWeights[map] or Config.Round.Maps.BaseWeight)
	end

	if totalWeight == 0 then
		-- Fallback to random selection if all weights are 0
		return maps[math.random(1, #maps)]
	end

	-- Random selection based on weights
	local randomValue = math.random() * totalWeight
	local currentWeight = 0

	for _, map in ipairs(maps) do
		currentWeight = currentWeight + (self.MapWeights[map] or Config.Round.Maps.BaseWeight)
		if randomValue <= currentWeight then
			return map
		end
	end

	-- Fallback (should never reach here)
	return maps[#maps]
end

-- =============================================================================
-- WEIGHT MANAGEMENT
-- =============================================================================

function MapSelector:ConfirmMapUsed(map)
	-- This should be called when a map is ACTUALLY USED in a round
	-- Not just when it's selected during intermission

	if not map then
		Log:Warn("MAPSELECT", "Cannot confirm nil map usage")
		return
	end

	-- Add to history
	table.insert(self.MapHistory, map)

	-- Trim history to configured size
	while #self.MapHistory > Config.Round.Maps.HistorySize do
		table.remove(self.MapHistory, 1)
	end

	-- Reduce weight of played map
	self.MapWeights[map] = Config.Round.Maps.PlayedWeight

	Log:Info("MAPSELECT", "Map confirmed as used, weight reduced", {
		MapName = map.Name,
		NewWeight = self.MapWeights[map],
		HistorySize = #self.MapHistory,
	})
end

-- Legacy method for backward compatibility (now just calls ConfirmMapUsed)
function MapSelector:OnMapSelected(map)
	self:ConfirmMapUsed(map)
end

function MapSelector:IncrementNonPlayedWeights()
	-- Get last played map
	local lastPlayed = self.MapHistory[#self.MapHistory]

	if not lastPlayed then
		return
	end

	-- Increment weights for all maps except the last played
	for map, weight in pairs(self.MapWeights) do
		if map ~= lastPlayed then
			self.MapWeights[map] = math.min(weight + Config.Round.Maps.WeightIncrement, Config.Round.Maps.BaseWeight)
		end
	end

	Log:Debug("MAPSELECT", "Incremented non-played map weights", {
		Increment = Config.Round.Maps.WeightIncrement,
	})
end

function MapSelector:ResetWeights()
	for map, _ in pairs(self.MapWeights) do
		self.MapWeights[map] = Config.Round.Maps.BaseWeight
	end

	self.MapHistory = {}

	Log:Info("MAPSELECT", "Reset all map weights to base value")
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

function MapSelector:GetTotalMapCount()
	local count = 0
	for _, _ in pairs(self.MapWeights) do
		count = count + 1
	end
	return count
end

function MapSelector:GetMapWeight(map)
	return self.MapWeights[map] or Config.Round.Maps.BaseWeight
end

function MapSelector:GetMapHistory()
	return table.clone(self.MapHistory)
end

function MapSelector:GetMapWeights()
	return table.clone(self.MapWeights)
end

function MapSelector:IsInHistory(map)
	for _, historyMap in ipairs(self.MapHistory) do
		if historyMap == map then
			return true
		end
	end
	return false
end

-- =============================================================================
-- DEBUG FUNCTIONS
-- =============================================================================

function MapSelector:PrintWeights(useSmallMaps)
	local eligibleMaps = self:GetEligibleMaps(useSmallMaps)

	Log:Info("MAPSELECT", "=== MAP WEIGHTS ===")
	Log:Info("MAPSELECT", string.format("Map Size: %s", useSmallMaps and "Small" or "Large"))
	Log:Info("MAPSELECT", string.format("Total Eligible: %d", #eligibleMaps))

	for _, map in ipairs(eligibleMaps) do
		local weight = self.MapWeights[map] or 0
		local inHistory = self:IsInHistory(map) and " (in history)" or ""
		Log:Info("MAPSELECT", string.format("  %s: %d%s", map.Name, weight, inHistory))
	end
end

return MapSelector
