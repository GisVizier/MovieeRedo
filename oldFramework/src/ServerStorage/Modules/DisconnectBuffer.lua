local DisconnectBuffer = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local Config = require(Locations.Modules.Config)

-- State
DisconnectBuffer.DisconnectHistory = {} -- { { player = player, timestamp = tick() } }

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function DisconnectBuffer:Init()
	Log:RegisterCategory("DCBUFFER", "Disconnect tracking and prediction system")

	-- Track player disconnects
	Players.PlayerRemoving:Connect(function(player)
		self:RecordDisconnect(player)
	end)

	-- Periodically clean old entries
	task.spawn(function()
		while true do
			task.wait(10) -- Clean every 10 seconds
			self:CleanOldEntries()
		end
	end)

	Log:Info("DCBUFFER", "DisconnectBuffer initialized")
end

-- =============================================================================
-- DISCONNECT TRACKING
-- =============================================================================

function DisconnectBuffer:RecordDisconnect(player)
	table.insert(self.DisconnectHistory, {
		player = player,
		timestamp = tick(),
	})

	Log:Debug("DCBUFFER", "Recorded disconnect", {
		Player = player.Name,
		Timestamp = tick(),
		TotalInBuffer = #self.DisconnectHistory,
	})
end

function DisconnectBuffer:CleanOldEntries()
	local currentTime = tick()
	local trackingWindow = Config.Round.DisconnectBuffer.TrackingWindow
	local cleaned = 0

	-- Remove entries older than tracking window
	for i = #self.DisconnectHistory, 1, -1 do
		local entry = self.DisconnectHistory[i]
		if currentTime - entry.timestamp > trackingWindow then
			table.remove(self.DisconnectHistory, i)
			cleaned = cleaned + 1
		end
	end

	if cleaned > 0 then
		Log:Debug("DCBUFFER", "Cleaned old disconnect entries", {
			Removed = cleaned,
			Remaining = #self.DisconnectHistory,
		})
	end
end

-- =============================================================================
-- DISCONNECT PREDICTION
-- =============================================================================

function DisconnectBuffer:PredictDisconnects()
	local recentDisconnects = #self.DisconnectHistory
	local threshold = Config.Round.DisconnectBuffer.CascadeThreshold

	-- If we have >= threshold disconnects in the tracking window, predict more
	local prediction = recentDisconnects >= threshold

	if prediction then
		Log:Info("DCBUFFER", "Predicted cascade disconnects", {
			RecentDisconnects = recentDisconnects,
			Threshold = threshold,
		})
	end

	return prediction
end

function DisconnectBuffer:GetRecentDisconnectCount()
	return #self.DisconnectHistory
end

function DisconnectBuffer:GetDisconnectRate()
	if #self.DisconnectHistory == 0 then
		return 0
	end

	-- Calculate disconnects per minute
	local trackingWindow = Config.Round.DisconnectBuffer.TrackingWindow
	local disconnectsPerMinute = (#self.DisconnectHistory / trackingWindow) * 60

	return disconnectsPerMinute
end

-- =============================================================================
-- THRESHOLD PROTECTION
-- =============================================================================

function DisconnectBuffer:ShouldUseSmallerMap(playerCount)
	local threshold = Config.Round.Players.SmallMapThreshold
	local buffer = Config.Round.DisconnectBuffer.ThresholdBuffer

	-- If we're within buffer zone of threshold
	if playerCount >= threshold and playerCount <= threshold + buffer then
		-- Check if disconnects are likely
		if self:PredictDisconnects() then
			Log:Info("DCBUFFER", "Recommending smaller map due to disconnect risk", {
				PlayerCount = playerCount,
				Threshold = threshold,
			})
			return true
		end
	end

	return false
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

function DisconnectBuffer:GetDebugInfo()
	return {
		TotalInBuffer = #self.DisconnectHistory,
		PredictsCascade = self:PredictDisconnects(),
		DisconnectRate = self:GetDisconnectRate(),
		TrackingWindow = Config.Round.DisconnectBuffer.TrackingWindow,
	}
end

function DisconnectBuffer:ClearHistory()
	self.DisconnectHistory = {}
	Log:Info("DCBUFFER", "Cleared disconnect history")
end

return DisconnectBuffer
