local ServerReplicator = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local CompressionUtils = require(Locations.Modules.Utils.CompressionUtils)
local Log = require(Locations.Modules.Systems.Core.LogService)

local ReplicationConfig = require(ReplicatedStorage.Configs.ReplicationConfig)

-- State tracking
ServerReplicator.PlayerStates = {} -- [player] = { LastState, LastUpdateTime, FrameHistory, CachedCompressedState }
ServerReplicator.LastBroadcastTime = 0

-- Performance tracking
ServerReplicator.PacketsReceivedPerSecond = 0
ServerReplicator.PacketsSentPerSecond = 0

function ServerReplicator:Init()
	Log:RegisterCategory("REPLICATOR_SERVER", "Server-side character replication and validation")

	-- Listen for client state updates
	RemoteEvents:ConnectServer("CharacterStateUpdate", function(player, compressedState)
		self:OnClientStateUpdate(player, compressedState)
	end)

	-- Listen for late-join initial state requests
	RemoteEvents:ConnectServer("RequestInitialStates", function(player)
		self:SendInitialStatesToPlayer(player)
	end)

	-- Start broadcast loop
	if ReplicationConfig.UpdateRates.ServerToClients > 0 then
		local broadcastInterval = 1 / ReplicationConfig.UpdateRates.ServerToClients
		RunService.Heartbeat:Connect(function()
			local currentTime = tick()
			if currentTime - self.LastBroadcastTime >= broadcastInterval then
				self:BroadcastStates()
				self.LastBroadcastTime = currentTime
			end
		end)
	end

	-- DIAGNOSTIC: Verify we're using UnreliableRemoteEvent
	local characterStateEvent = RemoteEvents:GetEvent("CharacterStateReplicated")
	local isUnreliable = characterStateEvent and characterStateEvent:IsA("UnreliableRemoteEvent")

	Log:Debug("REPLICATOR_SERVER", "ServerReplicator initialized", {
		UpdateRate = ReplicationConfig.UpdateRates.ServerToClients .. "Hz",
		EventType = characterStateEvent and characterStateEvent.ClassName or "NOT_FOUND",
		IsUnreliable = isUnreliable,
	})

	if not isUnreliable then
		Log:Warn("REPLICATOR_SERVER", "⚠️ CRITICAL: CharacterStateReplicated is NOT UnreliableRemoteEvent!", {
			EventType = characterStateEvent and characterStateEvent.ClassName or "NOT_FOUND",
			ExpectedType = "UnreliableRemoteEvent",
			Impact = "Clients will experience ~24% packet loss from Roblox throttling at 60Hz",
		})
	end
end

function ServerReplicator:OnClientStateUpdate(player, compressedState)
	self.PacketsReceivedPerSecond = self.PacketsReceivedPerSecond + 1

	-- Decompress state
	local state = CompressionUtils:DecompressState(compressedState)

	-- Check if decompression failed (checksum mismatch or invalid data)
	if not state then
		Log:Warn("REPLICATOR_SERVER", "Failed to decompress state from client", {
			Player = player.Name,
			BufferType = type(compressedState),
			BufferSize = type(compressedState) == "buffer" and buffer.len(compressedState) or "N/A",
		})
		return
	end

	-- Get player's last known state
	local playerData = self.PlayerStates[player]
	if not playerData then
		-- First update from this player
		playerData = {
			LastState = state,
			LastUpdateTime = tick(),
			FrameHistory = {}, -- Frame-accurate position history for lag compensation
			CachedCompressedState = compressedState, -- Cache for efficient broadcasting
		}
		self.PlayerStates[player] = playerData

		if ReplicationConfig.Debug.LogClientUpdates then
			Log:Debug("REPLICATOR_SERVER", "First state received", {
				Player = player.Name,
				Position = state.Position,
			})
		end
		return
	end

	-- Update player state (validation removed - will be added later)
	playerData.LastState = state
	playerData.LastUpdateTime = tick()
	playerData.CachedCompressedState = compressedState -- Cache compressed state for broadcasting

	-- Apply state to server-side character Root part
	self:ApplyStateToCharacter(player, state)

	-- Add to frame history for lag compensation
	if ReplicationConfig.ServerHistory.EnableFrameHistory then
		self:AddToFrameHistory(player, state)
	end

	if ReplicationConfig.Debug.LogClientUpdates then
		Log:Debug("REPLICATOR_SERVER", "State validated and queued", {
			Player = player.Name,
			Position = state.Position,
		})
	end
end

-- Validation functions removed - anti-cheat will be added later

function ServerReplicator:BroadcastStates()
	-- Collect all active player states (broadcast last known state for ALL players every tick)
	local batch = {}

	for player, playerData in pairs(self.PlayerStates) do
		-- Only broadcast players that have a state and are still in the game
		if playerData.LastState and playerData.CachedCompressedState and player.Parent then
			table.insert(batch, {
				UserId = player.UserId,
				State = playerData.CachedCompressedState, -- Use cached compressed state
			})
		end
	end

	-- Don't broadcast if no players have states yet
	if #batch == 0 then
		return
	end

	local config = ReplicationConfig.Optimization

	-- Batch states if enabled
	if config.EnableBatching then
		local currentBatch = {}
		local batchCount = 0

		for _, entry in ipairs(batch) do
			table.insert(currentBatch, entry)
			batchCount = batchCount + 1

			-- Send batch when full
			if batchCount >= config.MaxBatchSize then
				RemoteEvents:FireAllClients("CharacterStateReplicated", currentBatch)
				self.PacketsSentPerSecond = self.PacketsSentPerSecond + 1
				currentBatch = {}
				batchCount = 0
			end
		end

		-- Send remaining batch
		if batchCount > 0 then
			RemoteEvents:FireAllClients("CharacterStateReplicated", currentBatch)
			self.PacketsSentPerSecond = self.PacketsSentPerSecond + 1
		end
	else
		-- Send individual states
		for _, entry in ipairs(batch) do
			RemoteEvents:FireAllClients("CharacterStateReplicated", {
				{
					UserId = entry.UserId,
					State = entry.State,
				},
			})
			self.PacketsSentPerSecond = self.PacketsSentPerSecond + 1
		end
	end

	if ReplicationConfig.Debug.LogServerBroadcasts then
		Log:Debug("REPLICATOR_SERVER", "Broadcast states", {
			PlayerCount = #batch,
		})
	end
end

function ServerReplicator:ApplyStateToCharacter(player, state)
	-- NOTE: Server does NOT update character position
	-- Server's anchored Humanoid model stays static - ONLY for voice chat infrastructure
	-- Client physics are fully client-side, server just relays position data to other clients
	-- This eliminates server-side physics processing entirely

	if ReplicationConfig.Debug.LogClientUpdates then
		Log:Debug("REPLICATOR_SERVER", "State received and queued for broadcast (server model stays static)", {
			Player = player.Name,
			Position = state.Position,
		})
	end
end

function ServerReplicator:RegisterPlayer(player)
	-- Initialize player state tracking
	self.PlayerStates[player] = {
		LastState = nil,
		LastUpdateTime = tick(),
		FrameHistory = {}, -- Frame-accurate history for lag compensation
		CachedCompressedState = nil, -- Will be populated on first state update
	}

	Log:Debug("REPLICATOR_SERVER", "Player registered for replication", {
		Player = player.Name,
	})

	-- LATE-JOIN SYNC: Client will request initial states when ready via RequestInitialStates event
	-- This ensures visual characters are set up before receiving position data
end

function ServerReplicator:SendInitialStatesToPlayer(newPlayer)
	-- Collect all active player states
	local initialStates = {}

	for otherPlayer, playerData in pairs(self.PlayerStates) do
		-- Skip the new player themselves and players without a state yet
		if otherPlayer ~= newPlayer and playerData.LastState then
			-- Compress and send their last known state (all required fields)
			local compressedState = CompressionUtils:CompressState(
				playerData.LastState.Position,
				playerData.LastState.Rotation,
				playerData.LastState.Velocity,
				playerData.LastState.Timestamp,
				playerData.LastState.IsGrounded or false,
				playerData.LastState.AnimationId or 1, -- Default to IdleStanding if missing
				playerData.LastState.RigTilt or 0,
				0 -- SequenceNumber = 0 for initial state (not part of sequence)
			)

			table.insert(initialStates, {
				UserId = otherPlayer.UserId,
				State = compressedState,
			})
		end
	end

	-- Send batch of initial states to the new player
	if #initialStates > 0 then
		RemoteEvents:FireClient("CharacterStateReplicated", newPlayer, initialStates)

		Log:Info("REPLICATOR_SERVER", "Sent initial player states to late-joiner", {
			NewPlayer = newPlayer.Name,
			StateCount = #initialStates,
		})
	end
end

function ServerReplicator:UnregisterPlayer(player)
	-- Clean up player state
	self.PlayerStates[player] = nil

	Log:Debug("REPLICATOR_SERVER", "Player unregistered from replication", {
		Player = player.Name,
	})
end

function ServerReplicator:GetPlayerState(player)
	local playerData = self.PlayerStates[player]
	return playerData and playerData.LastState
end

function ServerReplicator:GetPerformanceStats()
	return {
		PacketsReceived = self.PacketsReceivedPerSecond,
		PacketsSent = self.PacketsSentPerSecond,
		TrackedPlayers = self:GetTrackedPlayerCount(),
	}
end

function ServerReplicator:GetTrackedPlayerCount()
	local count = 0
	for _ in pairs(self.PlayerStates) do
		count = count + 1
	end
	return count
end

-- =============================================================================
-- FRAME HISTORY (Server-authoritative lag compensation)
-- =============================================================================

function ServerReplicator:AddToFrameHistory(player, state)
	local playerData = self.PlayerStates[player]
	if not playerData then
		return
	end

	-- Add state to history
	table.insert(playerData.FrameHistory, {
		Position = state.Position,
		Rotation = state.Rotation,
		Velocity = state.Velocity,
		Timestamp = state.Timestamp,
	})

	-- Limit history size
	local maxEntries = ReplicationConfig.ServerHistory.MaxHistoryEntries
	while #playerData.FrameHistory > maxEntries do
		table.remove(playerData.FrameHistory, 1)
	end

	-- Remove old entries outside max duration
	local maxAge = ReplicationConfig.ServerHistory.HistoryDuration
	local cutoffTime = tick() - maxAge
	for i = #playerData.FrameHistory, 1, -1 do
		if playerData.FrameHistory[i].Timestamp < cutoffTime then
			table.remove(playerData.FrameHistory, i)
		else
			break -- History is sorted, so stop when we find a recent entry
		end
	end

	if ReplicationConfig.Debug.LogFrameHistory then
		Log:Debug("REPLICATOR_SERVER", "Frame history updated", {
			Player = player.Name,
			HistorySize = #playerData.FrameHistory,
			Timestamp = state.Timestamp,
		})
	end
end

function ServerReplicator:GetPlayerStateAtTime(player, timestamp)
	local playerData = self.PlayerStates[player]
	if not playerData or not playerData.FrameHistory then
		return nil
	end

	local history = playerData.FrameHistory

	-- No history available
	if #history == 0 then
		return playerData.LastState
	end

	-- Requested time is too old (outside history window)
	local oldestFrame = history[1]
	if timestamp < oldestFrame.Timestamp then
		if ReplicationConfig.Debug.LogFrameHistory then
			Log:Warn("REPLICATOR_SERVER", "Requested time too old", {
				Player = player.Name,
				RequestedTime = timestamp,
				OldestTime = oldestFrame.Timestamp,
			})
		end
		return oldestFrame
	end

	-- Requested time is in the future (use latest state)
	local newestFrame = history[#history]
	if timestamp > newestFrame.Timestamp then
		return newestFrame
	end

	-- Binary search for closest frame
	local left, right = 1, #history
	while left < right do
		local mid = math.floor((left + right) / 2)
		if history[mid].Timestamp < timestamp then
			left = mid + 1
		else
			right = mid
		end
	end

	-- Interpolate between two closest frames
	local frameAfter = history[left]
	local frameBefore = left > 1 and history[left - 1] or frameAfter

	if frameBefore == frameAfter then
		return frameAfter
	end

	-- Linear interpolation
	local alpha = (timestamp - frameBefore.Timestamp) / (frameAfter.Timestamp - frameBefore.Timestamp)
	alpha = math.clamp(alpha, 0, 1)

	return {
		Position = frameBefore.Position:Lerp(frameAfter.Position, alpha),
		Rotation = frameBefore.Rotation:Lerp(frameAfter.Rotation, alpha),
		Velocity = frameBefore.Velocity:Lerp(frameAfter.Velocity, alpha),
		Timestamp = timestamp,
	}
end

function ServerReplicator:GetPlayerStateWithLagCompensation(player, clientTimestamp)
	if not ReplicationConfig.ServerHistory.EnableLagCompensation then
		return self:GetPlayerState(player)
	end

	-- Calculate lag-compensated time
	local maxCompensation = ReplicationConfig.ServerHistory.MaxCompensationTime
	local compensatedTime = math.max(clientTimestamp, tick() - maxCompensation)

	return self:GetPlayerStateAtTime(player, compensatedTime)
end

-- Reset performance counters every second
RunService.Heartbeat:Connect(function()
	local currentTime = tick()
	if not ServerReplicator._lastPerfReset or currentTime - ServerReplicator._lastPerfReset >= 1.0 then
		ServerReplicator.PacketsReceivedPerSecond = 0
		ServerReplicator.PacketsSentPerSecond = 0
		ServerReplicator._lastPerfReset = currentTime
	end
end)

return ServerReplicator
