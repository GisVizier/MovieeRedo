--[[
	PositionHistory.lua
	
	Ring buffer-based position and stance history for lag compensation.
	Stores 60 samples per player (1 second at 60Hz) using efficient buffer storage.
	
	Each sample: 21 bytes
	- Timestamp: f64 (8 bytes) - double precision for Unix timestamps
	- Position: Vector3 (12 bytes) 
	- Stance: u8 (1 byte) - 0=Standing, 1=Crouched, 2=Sliding
	
	Total memory per player: ~1.3KB (60 samples * 21 bytes)
	
	Usage:
		PositionHistory:InitPlayer(player)
		PositionHistory:StoreSample(player, position, timestamp, stance)
		local pos = PositionHistory:GetPositionAtTime(player, timestamp)
		local stance = PositionHistory:GetStanceAtTime(player, timestamp)
]]

local PositionHistory = {}

-- Configuration
local CONFIG = {
	HistorySize = 60,       -- 1 second at 60Hz
	SampleSize = 21,        -- bytes per sample (8 + 12 + 1) - f64 timestamp for precision
	MaxInterpolationGap = 0.1, -- Max time gap to interpolate across (seconds)
}

-- Stance enum
PositionHistory.Stance = {
	Standing = 0,
	Crouched = 1,
	Sliding = 2,
}

-- Reverse lookup for stance names
PositionHistory.StanceNames = {
	[0] = "Standing",
	[1] = "Crouched",
	[2] = "Sliding",
}

-- Per-player data storage
PositionHistory.Players = {}

--[[
	Buffer layout per sample (21 bytes):
	Offset 0:  f64 timestamp (8 bytes - double precision for Unix timestamps)
	Offset 8:  f32 position.X
	Offset 12: f32 position.Y
	Offset 16: f32 position.Z
	Offset 20: u8  stance
]]

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function PositionHistory:Init()
	-- Clean up on player removal
	game.Players.PlayerRemoving:Connect(function(player)
		self:RemovePlayer(player)
	end)
	
	-- Initialize existing players
	for _, player in ipairs(game.Players:GetPlayers()) do
		self:InitPlayer(player)
	end
	
	-- Initialize new players
	game.Players.PlayerAdded:Connect(function(player)
		self:InitPlayer(player)
	end)
end

function PositionHistory:InitPlayer(player)
	if self.Players[player] then
		return -- Already initialized
	end
	
	local bufferSize = CONFIG.HistorySize * CONFIG.SampleSize
	
	self.Players[player] = {
		Buffer = buffer.create(bufferSize),
		WriteIndex = 0,
		Count = 0,
		LastStance = self.Stance.Standing, -- Track current stance for replication
	}
end

function PositionHistory:RemovePlayer(player)
	self.Players[player] = nil
end

-- =============================================================================
-- STORAGE
-- =============================================================================

--[[
	Store a position sample for a player
	
	@param player Player - The player to store for
	@param position Vector3 - World position
	@param timestamp number - Server timestamp (os.clock or tick)
	@param stance number? - Stance enum value (default: last known stance)
]]
function PositionHistory:StoreSample(player, position, timestamp, stance)
	local data = self.Players[player]
	if not data then
		self:InitPlayer(player)
		data = self.Players[player]
	end
	
	-- Use provided stance or fall back to last known
	local stanceValue = stance or data.LastStance
	data.LastStance = stanceValue
	
	-- Calculate buffer offset for this sample
	local sampleIndex = data.WriteIndex % CONFIG.HistorySize
	local offset = sampleIndex * CONFIG.SampleSize
	
	-- Write sample to buffer (f64 timestamp for precision with Unix timestamps)
	buffer.writef64(data.Buffer, offset, timestamp)
	buffer.writef32(data.Buffer, offset + 8, position.X)
	buffer.writef32(data.Buffer, offset + 12, position.Y)
	buffer.writef32(data.Buffer, offset + 16, position.Z)
	buffer.writeu8(data.Buffer, offset + 20, stanceValue)
	
	-- Update indices
	data.WriteIndex = data.WriteIndex + 1
	data.Count = math.min(data.Count + 1, CONFIG.HistorySize)
end

--[[
	Update the current stance for a player (called when crouch state changes)
	
	@param player Player - The player
	@param stance number - New stance enum value
]]
function PositionHistory:SetStance(player, stance)
	local data = self.Players[player]
	if data then
		data.LastStance = stance
	end
end

-- =============================================================================
-- RETRIEVAL
-- =============================================================================

--[[
	Read a sample from the buffer at a specific index
	
	@param data table - Player's history data
	@param index number - Sample index (0 to Count-1, where 0 is oldest)
	@return timestamp, position, stance
]]
function PositionHistory:_readSample(data, index)
	local offset = index * CONFIG.SampleSize
	
	-- Read f64 timestamp for precision with Unix timestamps
	local timestamp = buffer.readf64(data.Buffer, offset)
	local position = Vector3.new(
		buffer.readf32(data.Buffer, offset + 8),
		buffer.readf32(data.Buffer, offset + 12),
		buffer.readf32(data.Buffer, offset + 16)
	)
	local stance = buffer.readu8(data.Buffer, offset + 20)
	
	return timestamp, position, stance
end

--[[
	Get the actual buffer index for a logical sample number
	Ring buffer means newest sample is at (WriteIndex - 1), oldest at (WriteIndex - Count)
	
	@param data table - Player's history data
	@param sampleNum number - 0 = oldest, Count-1 = newest
	@return number - Buffer index
]]
function PositionHistory:_getBufferIndex(data, sampleNum)
	-- Calculate which buffer slot contains this sample
	local startIndex = (data.WriteIndex - data.Count) % CONFIG.HistorySize
	return (startIndex + sampleNum) % CONFIG.HistorySize
end

--[[
	Find two samples that bracket a target timestamp for interpolation
	
	@param data table - Player's history data
	@param targetTime number - Target timestamp
	@return prevSample, nextSample (or nil if not found)
]]
function PositionHistory:_findBracketingSamples(data, targetTime)
	if data.Count == 0 then
		return nil, nil
	end
	
	local prevSample, nextSample = nil, nil
	
	-- Search through samples from newest to oldest
	for i = data.Count - 1, 0, -1 do
		local bufferIndex = self:_getBufferIndex(data, i)
		local timestamp, position, stance = self:_readSample(data, bufferIndex)
		
		if timestamp <= targetTime then
			prevSample = { Timestamp = timestamp, Position = position, Stance = stance }
			break
		else
			nextSample = { Timestamp = timestamp, Position = position, Stance = stance }
		end
	end
	
	-- If we only found samples after targetTime, get the oldest as prev
	if not prevSample and data.Count > 0 then
		local oldestIndex = self:_getBufferIndex(data, 0)
		local timestamp, position, stance = self:_readSample(data, oldestIndex)
		prevSample = { Timestamp = timestamp, Position = position, Stance = stance }
	end
	
	return prevSample, nextSample
end

--[[
	Get interpolated position at a specific timestamp
	
	@param player Player - The player to query
	@param targetTime number - Target timestamp
	@return Vector3? - Interpolated position, or nil if no data
]]
function PositionHistory:GetPositionAtTime(player, targetTime)
	local data = self.Players[player]
	if not data or data.Count == 0 then
		return nil
	end
	
	local prevSample, nextSample = self:_findBracketingSamples(data, targetTime)
	
	if not prevSample then
		return nil
	end
	
	-- If no next sample or target is before/at prev, return prev position
	if not nextSample or targetTime <= prevSample.Timestamp then
		return prevSample.Position
	end
	
	-- Check if gap is too large to interpolate
	local gap = nextSample.Timestamp - prevSample.Timestamp
	if gap > CONFIG.MaxInterpolationGap then
		-- Return closest sample instead of interpolating
		if math.abs(targetTime - prevSample.Timestamp) < math.abs(targetTime - nextSample.Timestamp) then
			return prevSample.Position
		else
			return nextSample.Position
		end
	end
	
	-- Interpolate between samples
	local alpha = (targetTime - prevSample.Timestamp) / gap
	alpha = math.clamp(alpha, 0, 1)
	
	return prevSample.Position:Lerp(nextSample.Position, alpha)
end

--[[
	Get stance at a specific timestamp (no interpolation - uses closest sample)
	
	@param player Player - The player to query
	@param targetTime number - Target timestamp
	@return number? - Stance enum value, or nil if no data
]]
function PositionHistory:GetStanceAtTime(player, targetTime)
	local data = self.Players[player]
	if not data or data.Count == 0 then
		return nil
	end
	
	local prevSample, nextSample = self:_findBracketingSamples(data, targetTime)
	
	if not prevSample then
		return nil
	end
	
	-- Stance doesn't interpolate - use the sample closest to target time
	if not nextSample then
		return prevSample.Stance
	end
	
	if math.abs(targetTime - prevSample.Timestamp) <= math.abs(targetTime - nextSample.Timestamp) then
		return prevSample.Stance
	else
		return nextSample.Stance
	end
end

--[[
	Get stance name at a specific timestamp
	
	@param player Player - The player to query
	@param targetTime number - Target timestamp
	@return string? - Stance name ("Standing", "Crouched", "Sliding"), or nil
]]
function PositionHistory:GetStanceNameAtTime(player, targetTime)
	local stance = self:GetStanceAtTime(player, targetTime)
	if stance then
		return self.StanceNames[stance]
	end
	return nil
end

--[[
	Get both position and stance at a specific timestamp
	
	@param player Player - The player to query
	@param targetTime number - Target timestamp
	@return Vector3?, number? - Position and stance, or nil if no data
]]
function PositionHistory:GetStateAtTime(player, targetTime)
	return self:GetPositionAtTime(player, targetTime), self:GetStanceAtTime(player, targetTime)
end

-- =============================================================================
-- UTILITY
-- =============================================================================

--[[
	Get the current sample count for a player
	
	@param player Player - The player to query
	@return number - Number of stored samples (0 to HistorySize)
]]
function PositionHistory:GetSampleCount(player)
	local data = self.Players[player]
	return data and data.Count or 0
end

--[[
	Get the timestamp range of stored samples
	
	@param player Player - The player to query
	@return oldestTime, newestTime (or nil if no samples)
]]
function PositionHistory:GetTimeRange(player)
	local data = self.Players[player]
	if not data or data.Count == 0 then
		return nil, nil
	end
	
	local oldestIndex = self:_getBufferIndex(data, 0)
	local newestIndex = self:_getBufferIndex(data, data.Count - 1)
	
	-- Read f64 timestamps for precision with Unix timestamps
	local oldestTime = buffer.readf64(data.Buffer, oldestIndex * CONFIG.SampleSize)
	local newestTime = buffer.readf64(data.Buffer, newestIndex * CONFIG.SampleSize)
	
	return oldestTime, newestTime
end

--[[
	Get the player's current/last known stance
	
	@param player Player - The player to query
	@return number - Stance enum value
]]
function PositionHistory:GetCurrentStance(player)
	local data = self.Players[player]
	return data and data.LastStance or self.Stance.Standing
end

--[[
	Debug: Get all samples for a player (expensive, use only for debugging)
	
	@param player Player - The player to query
	@return table - Array of {Timestamp, Position, Stance}
]]
function PositionHistory:GetAllSamples(player)
	local data = self.Players[player]
	if not data or data.Count == 0 then
		return {}
	end
	
	local samples = {}
	for i = 0, data.Count - 1 do
		local bufferIndex = self:_getBufferIndex(data, i)
		local timestamp, position, stance = self:_readSample(data, bufferIndex)
		table.insert(samples, {
			Timestamp = timestamp,
			Position = position,
			Stance = stance,
			StanceName = self.StanceNames[stance],
		})
	end
	
	return samples
end

return PositionHistory
