local GarbageCollectorService = {}

-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)

-- Performance optimizations
local tick = tick
local pairs = pairs
local string_find = string.find
local pcall = pcall

GarbageCollectorService.TrackedConnections = {}
GarbageCollectorService.TrackedObjects = {}
GarbageCollectorService.OrphanedObjects = {}
GarbageCollectorService.CleanupCallbacks = {}

GarbageCollectorService.Settings = {
	SweepInterval = 30,
	MaxOrphanAge = 60,
	MemoryWarningThreshold = 500,
}

GarbageCollectorService.Stats = {
	TotalObjectsCleaned = 0,
	TotalConnectionsCleaned = 0,
	LastSweepTime = 0,
	CurrentMemoryUsage = 0,
}

function GarbageCollectorService:Init()
	Log:RegisterCategory("GC", "Garbage collection and cleanup management")

	Log:Debug("GC", "Initializing cleanup system")

	self:StartPeriodicCleanup()

	Players.PlayerRemoving:Connect(function(player)
		self:CleanupPlayer(player)
	end)

	Log:Debug("GC", "Cleanup system active")
end

function GarbageCollectorService:StartPeriodicCleanup()
	-- Use a less frequent connection for performance
	local lastCheck = tick()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()

		-- Only check every second to reduce overhead
		if currentTime - lastCheck >= 1 then
			lastCheck = currentTime

			if currentTime - self.Stats.LastSweepTime > self.Settings.SweepInterval then
				self:PerformCleanupSweep()
				self.Stats.LastSweepTime = currentTime
			end
		end
	end)

	-- Track the cleanup connection itself
	self:TrackConnection(connection, "GC_PeriodicCleanup")
end

function GarbageCollectorService:PerformCleanupSweep()
	local timer = Log:StartTimer("GC", "Cleanup Sweep")
	local cleaned = 0

	cleaned = cleaned + self:CleanupOrphanedObjects()

	cleaned = cleaned + self:CleanupDeadConnections()

	cleaned = cleaned + self:CleanupDestroyedObjects()

	self:UpdateMemoryStats()

	local duration = timer:Stop()
	Log:Info("GC", "Cleanup sweep completed", {
		ObjectsCleaned = cleaned,
		Duration = string.format("%.2fs", duration),
		MemoryUsage = string.format("%.1f MB", self.Stats.CurrentMemoryUsage / 1024),
	})
end

function GarbageCollectorService:CleanupOrphanedObjects()
	local cleaned = 0
	local currentTime = tick()

	for objectId, data in pairs(self.OrphanedObjects) do
		if currentTime - data.OrphanTime > self.Settings.MaxOrphanAge then
			if data.Object and data.Object.Parent then
				if data.CleanupCallback then
					pcall(data.CleanupCallback, data.Object)
				end

				data.Object:Destroy()
				cleaned = cleaned + 1
			end

			self.OrphanedObjects[objectId] = nil
		end
	end

	self.Stats.TotalObjectsCleaned = self.Stats.TotalObjectsCleaned + cleaned
	return cleaned
end

function GarbageCollectorService:CleanupDeadConnections()
	local cleaned = 0

	for connectionId, connectionData in pairs(self.TrackedConnections) do
		local connection = connectionData.Connection

		if not connection or not connection.Connected then
			if connection and connection.Connected then
				connection:Disconnect()
			end

			self.TrackedConnections[connectionId] = nil
			cleaned = cleaned + 1
		end
	end

	self.Stats.TotalConnectionsCleaned = self.Stats.TotalConnectionsCleaned + cleaned
	return cleaned
end

function GarbageCollectorService:CleanupDestroyedObjects()
	local cleaned = 0

	for objectId, objectData in pairs(self.TrackedObjects) do
		local object = objectData.Object

		if not object or not object.Parent then
			if objectData.CleanupCallback then
				pcall(objectData.CleanupCallback, object)
			end

			self.TrackedObjects[objectId] = nil
			cleaned = cleaned + 1
		end
	end

	return cleaned
end

function GarbageCollectorService:UpdateMemoryStats()
	self.Stats.CurrentMemoryUsage = gcinfo()

	-- Warn if memory usage gets too high - helps catch memory leaks
	if self.Stats.CurrentMemoryUsage > self.Settings.MemoryWarningThreshold * 1024 then
		Log:Warn("GC", "High memory usage detected", {
			MemoryUsage = string.format("%.1f MB", self.Stats.CurrentMemoryUsage / 1024),
			Threshold = string.format("%.1f MB", self.Settings.MemoryWarningThreshold),
		})
	end
end

function GarbageCollectorService:TrackConnection(connection, name, cleanupCallback)
	local connectionId = tostring(connection) .. "_" .. tick()

	self.TrackedConnections[connectionId] = {
		Connection = connection,
		Name = name or "Unknown",
		CreatedTime = tick(),
		CleanupCallback = cleanupCallback,
	}

	return connectionId
end

function GarbageCollectorService:TrackObject(object, name, cleanupCallback)
	local objectId = tostring(object) .. "_" .. tick()

	self.TrackedObjects[objectId] = {
		Object = object,
		Name = name or "Unknown",
		CreatedTime = tick(),
		CleanupCallback = cleanupCallback,
	}

	return objectId
end

function GarbageCollectorService:MarkAsOrphaned(object, cleanupCallback)
	local objectId = tostring(object) .. "_orphan_" .. tick()

	self.OrphanedObjects[objectId] = {
		Object = object,
		OrphanTime = tick(),
		CleanupCallback = cleanupCallback,
	}

	return objectId
end

function GarbageCollectorService:UntrackConnection(connectionId)
	if self.TrackedConnections[connectionId] then
		local connection = self.TrackedConnections[connectionId].Connection
		if connection and connection.Connected then
			connection:Disconnect()
		end
		self.TrackedConnections[connectionId] = nil
	end
end

function GarbageCollectorService:UntrackObject(objectId)
	self.TrackedObjects[objectId] = nil
end

function GarbageCollectorService:CleanupPlayer(player)
	Log:Info("GC", "Cleaning up player", { Player = player.Name })
	local cleaned = 0
	local playerName = player.Name

	-- Clean up connections associated with this player
	for connectionId, data in pairs(self.TrackedConnections) do
		if string_find(data.Name or "", playerName) then
			local connection = data.Connection
			if connection and connection.Connected then
				connection:Disconnect()
			end
			self.TrackedConnections[connectionId] = nil
			cleaned = cleaned + 1
		end
	end

	-- Clean up objects associated with this player
	for objectId, data in pairs(self.TrackedObjects) do
		if string_find(data.Name or "", playerName) then
			if data.CleanupCallback then
				pcall(data.CleanupCallback, data.Object)
			end
			self.TrackedObjects[objectId] = nil
			cleaned = cleaned + 1
		end
	end

	Log:Info("GC", "Player cleanup completed", { Player = playerName, ItemsCleaned = cleaned })
end

function GarbageCollectorService:ForceCleanupSweep()
	self:PerformCleanupSweep()
end

function GarbageCollectorService:GetStats()
	return {
		TotalObjectsCleaned = self.Stats.TotalObjectsCleaned,
		TotalConnectionsCleaned = self.Stats.TotalConnectionsCleaned,
		CurrentMemoryUsage = self.Stats.CurrentMemoryUsage,
		TrackedConnections = self:CountTable(self.TrackedConnections),
		TrackedObjects = self:CountTable(self.TrackedObjects),
		OrphanedObjects = self:CountTable(self.OrphanedObjects),
		LastSweepTime = self.Stats.LastSweepTime,
	}
end

function GarbageCollectorService:CountTable(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

function GarbageCollectorService:SafeDestroy(object, cleanupCallback)
	if not object or not object.Parent then
		return
	end

	if cleanupCallback then
		pcall(cleanupCallback, object)
	end

	object:Destroy()

	self.Stats.TotalObjectsCleaned = self.Stats.TotalObjectsCleaned + 1
end

return GarbageCollectorService
