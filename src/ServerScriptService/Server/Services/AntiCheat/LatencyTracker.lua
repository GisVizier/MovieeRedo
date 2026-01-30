--[[
	LatencyTracker.lua
	
	Measures and tracks per-player latency for lag compensation.
	Uses ping-pong packets to measure RTT and maintains a rolling average.
	
	Features:
	- Automatic ping every ~1 second per player
	- Rolling average RTT calculation
	- Jitter (variance) tracking
	- Adaptive tolerances based on network conditions
	
	Usage:
		LatencyTracker:Init(net)
		local ping = LatencyTracker:GetPing(player) -- milliseconds
		local rollback = LatencyTracker:GetRollbackTime(player) -- seconds
		local tolerances = LatencyTracker:GetAdaptiveTolerances(player)
]]

local LatencyTracker = {}

local RunService = game:GetService("RunService")

-- Configuration
local CONFIG = {
	PingIntervalSeconds = 1.0,      -- How often to ping each player
	SampleCount = 10,               -- Rolling average sample count
	MaxPingMs = 500,                -- Cap ping at 500ms (reject higher)
	MinPingMs = 5,                  -- Minimum realistic ping
	DefaultPingMs = 80,             -- Assumed ping before first measurement
	DefaultJitterMs = 20,           -- Default jitter assumption
	JitterSamples = 5,              -- Recent samples for jitter calculation
	ProcessingBufferMs = 16,        -- ~1 frame at 60fps
}

-- Base tolerances (scaled by ping)
local BASE_TOLERANCES = {
	PositionTolerance = 5,          -- studs
	HeadTolerance = 2.5,            -- studs (tighter for headshots)
	TimestampTolerance = 0.5,       -- seconds
}

-- Per-player data
LatencyTracker.Players = {}
LatencyTracker._net = nil
LatencyTracker._pendingPings = {}
LatencyTracker._heartbeatConnection = nil
LatencyTracker._ready = {}

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function LatencyTracker:Init(net)
	self._net = net
	
	-- Listen for ping responses
	net:ConnectServer("PingResponse", function(player, token)
		self:_onPingResponse(player, token)
	end)

	-- Client tells us when it's ready to receive PingRequest
	net:ConnectServer("PingReady", function(player)
		self._ready[player] = true
	end)
	
	-- Initialize existing players
	for _, player in ipairs(game.Players:GetPlayers()) do
		self:_initPlayer(player)
	end
	
	-- Initialize new players
	game.Players.PlayerAdded:Connect(function(player)
		self:_initPlayer(player)
	end)
	
	-- Cleanup on player removal
	game.Players.PlayerRemoving:Connect(function(player)
		self:_removePlayer(player)
	end)
	
	-- Start ping loop
	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:_pingLoop()
	end)
end

function LatencyTracker:_initPlayer(player)
	if self.Players[player] then
		return
	end
	
	local sampleBufferSize = CONFIG.SampleCount * 4 -- f32 = 4 bytes
	
	self.Players[player] = {
		PingSamples = buffer.create(sampleBufferSize),
		WriteIndex = 0,
		SampleCount = 0,
		AveragePing = CONFIG.DefaultPingMs,
		Jitter = CONFIG.DefaultJitterMs,
		LastPingTime = 0,
		OneWayLatency = CONFIG.DefaultPingMs / 2,
	}
	self._ready[player] = false
end

function LatencyTracker:_removePlayer(player)
	self.Players[player] = nil
	self._pendingPings[player] = nil
	self._ready[player] = nil
end

-- =============================================================================
-- PING MEASUREMENT
-- =============================================================================

function LatencyTracker:_pingLoop()
	local now = os.clock()
	
	for player, data in pairs(self.Players) do
		if player.Parent then -- Player still in game
			if not self._ready[player] then
				continue
			end
			if now - data.LastPingTime >= CONFIG.PingIntervalSeconds then
				self:_sendPing(player, now)
			end
		end
	end
end

function LatencyTracker:_sendPing(player, now)
	local data = self.Players[player]
	if not data then return end
	
	-- Generate unique token for this ping
	local token = math.random(1, 2147483647)
	
	self._pendingPings[player] = {
		Token = token,
		SentTime = now,
	}
	
	data.LastPingTime = now
	
	-- Send ping request to client
	if self._net then
		self._net:FireClient("PingRequest", player, token)
	end
end

function LatencyTracker:_onPingResponse(player, token)
	local pending = self._pendingPings[player]
	if not pending or pending.Token ~= token then
		return -- Stale or invalid response
	end
	
	local now = os.clock()
	local rttSeconds = now - pending.SentTime
	local rttMs = rttSeconds * 1000
	
	self._pendingPings[player] = nil
	
	-- Validate ping range
	if rttMs < CONFIG.MinPingMs or rttMs > CONFIG.MaxPingMs then
		return -- Reject outliers
	end
	
	-- Store sample
	self:_storePingSample(player, rttMs)
end

function LatencyTracker:_storePingSample(player, pingMs)
	local data = self.Players[player]
	if not data then return end
	
	-- Write to ring buffer
	local offset = (data.WriteIndex % CONFIG.SampleCount) * 4
	buffer.writef32(data.PingSamples, offset, pingMs)
	
	data.WriteIndex = data.WriteIndex + 1
	data.SampleCount = math.min(data.SampleCount + 1, CONFIG.SampleCount)
	
	-- Recalculate statistics
	self:_recalculateStats(player)
end

function LatencyTracker:_recalculateStats(player)
	local data = self.Players[player]
	if not data or data.SampleCount == 0 then return end
	
	local sum = 0
	local samples = {}
	
	-- Read all samples
	for i = 0, data.SampleCount - 1 do
		local offset = i * 4
		local sample = buffer.readf32(data.PingSamples, offset)
		sum = sum + sample
		table.insert(samples, sample)
	end
	
	-- Calculate average
	local avg = sum / data.SampleCount
	data.AveragePing = avg
	data.OneWayLatency = avg / 2
	
	-- Calculate jitter (standard deviation of recent samples)
	if data.SampleCount >= CONFIG.JitterSamples then
		local variance = 0
		local recentStart = math.max(1, #samples - CONFIG.JitterSamples + 1)
		local recentCount = #samples - recentStart + 1
		
		for i = recentStart, #samples do
			local diff = samples[i] - avg
			variance = variance + (diff * diff)
		end
		
		data.Jitter = math.sqrt(variance / recentCount)
	end
end

-- =============================================================================
-- PUBLIC API - LATENCY QUERIES
-- =============================================================================

--[[
	Get player's current estimated ping in milliseconds
	
	@param player Player - The player to query
	@return number - Ping in milliseconds
]]
function LatencyTracker:GetPing(player)
	local data = self.Players[player]
	return data and data.AveragePing or CONFIG.DefaultPingMs
end

--[[
	Get player's one-way latency (half of RTT) in seconds
	This is what you use for rollback calculations
	
	@param player Player - The player to query
	@return number - One-way latency in seconds
]]
function LatencyTracker:GetOneWayLatency(player)
	local data = self.Players[player]
	return data and (data.OneWayLatency / 1000) or (CONFIG.DefaultPingMs / 2000)
end

--[[
	Get player's jitter (ping variance) in milliseconds
	
	@param player Player - The player to query
	@return number - Jitter in milliseconds
]]
function LatencyTracker:GetJitter(player)
	local data = self.Players[player]
	return data and data.Jitter or CONFIG.DefaultJitterMs
end

--[[
	Calculate the time offset for lag compensation
	Returns how many seconds back in time to look for hit validation
	
	Includes:
	- One-way latency (shooter → server)
	- Jitter buffer (extra tolerance for variance)
	- Processing time allowance
	
	@param player Player - The player to query
	@return number - Rollback time in seconds
]]
function LatencyTracker:GetRollbackTime(player)
	local data = self.Players[player]
	if not data then
		return (CONFIG.DefaultPingMs / 2000) + 0.05 -- Default + buffer
	end
	
	local oneWayLatency = data.OneWayLatency / 1000
	local jitterBuffer = (data.Jitter / 1000) * 2 -- 2x jitter as safety margin
	local processingBuffer = CONFIG.ProcessingBufferMs / 1000
	
	return oneWayLatency + jitterBuffer + processingBuffer
end

--[[
	Get adaptive tolerance values based on player's network conditions
	Higher ping = more tolerance for position validation
	
	@param player Player - The player to query
	@return table - { PositionTolerance, HeadTolerance, TimestampTolerance }
]]
function LatencyTracker:GetAdaptiveTolerances(player)
	local ping = self:GetPing(player)
	local jitter = self:GetJitter(player)
	
	-- Scale based on ping (higher ping = more tolerance)
	-- At 50ms ping: 1x tolerance
	-- At 150ms ping: 1.5x tolerance
	-- At 300ms ping: 2x tolerance
	local pingFactor = math.clamp(ping / 100, 0.5, 3.0)
	
	-- Add extra tolerance for high jitter
	local jitterFactor = 1 + (jitter / 100)
	
	local combinedFactor = pingFactor * jitterFactor
	
	return {
		PositionTolerance = BASE_TOLERANCES.PositionTolerance * combinedFactor,
		HeadTolerance = BASE_TOLERANCES.HeadTolerance * combinedFactor,
		TimestampTolerance = BASE_TOLERANCES.TimestampTolerance * pingFactor,
	}
end

--[[
	Calculate combined tolerance when both shooter and target have latency
	
	@param shooter Player - The shooting player
	@param target Player - The target player
	@return table - Combined tolerances
]]
function LatencyTracker:GetCombinedTolerances(shooter, target)
	local shooterPing = self:GetPing(shooter)
	local targetPing = self:GetPing(target)
	
	-- Combined ping factor considers both players' latency
	local combinedPing = (shooterPing + targetPing) / 2
	local pingFactor = math.clamp(combinedPing / 100, 0.5, 3.0)
	
	local shooterJitter = self:GetJitter(shooter)
	local targetJitter = self:GetJitter(target)
	local avgJitter = (shooterJitter + targetJitter) / 2
	local jitterFactor = 1 + (avgJitter / 100)
	
	local combinedFactor = pingFactor * jitterFactor
	
	return {
		PositionTolerance = BASE_TOLERANCES.PositionTolerance * combinedFactor,
		HeadTolerance = BASE_TOLERANCES.HeadTolerance * combinedFactor,
		TimestampTolerance = BASE_TOLERANCES.TimestampTolerance * pingFactor,
	}
end

-- =============================================================================
-- DEBUG / UTILITY
-- =============================================================================

--[[
	Get full latency info for debugging
	
	@param player Player - The player to query
	@return table? - Debug info or nil if player not found
]]
function LatencyTracker:GetDebugInfo(player)
	local data = self.Players[player]
	if not data then return nil end
	
	return {
		Ping = data.AveragePing,
		OneWayLatency = data.OneWayLatency,
		Jitter = data.Jitter,
		Samples = data.SampleCount,
		RollbackTime = self:GetRollbackTime(player),
		Tolerances = self:GetAdaptiveTolerances(player),
	}
end

--[[
	Force a ping measurement for a player (for debugging)
	
	@param player Player - The player to ping
]]
function LatencyTracker:ForcePing(player)
	self:_sendPing(player, os.clock())
end

--[[
	Get configuration values
	
	@return table - Current configuration
]]
function LatencyTracker:GetConfig()
	return {
		PingInterval = CONFIG.PingIntervalSeconds,
		SampleCount = CONFIG.SampleCount,
		MaxPing = CONFIG.MaxPingMs,
		MinPing = CONFIG.MinPingMs,
		DefaultPing = CONFIG.DefaultPingMs,
		BaseTolerances = BASE_TOLERANCES,
	}
end

--[[
	Update a configuration value at runtime
	
	@param key string - Config key
	@param value any - New value
]]
function LatencyTracker:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
	elseif BASE_TOLERANCES[key] ~= nil then
		BASE_TOLERANCES[key] = value
	end
end

return LatencyTracker
