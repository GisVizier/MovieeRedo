--[[
	HitDetectionAPI.lua
	
	Public API for the Hit Detection System.
	Provides a clean facade for external systems to interact with hit detection,
	lag compensation, and anti-cheat features.
	
	This module wraps HitValidator, PositionHistory, and LatencyTracker
	into a unified interface.
	
	Usage:
		local HitDetectionAPI = require(path.to.HitDetectionAPI)
		HitDetectionAPI:Init(net)
		
		-- Validation
		local valid, reason = HitDetectionAPI:ValidateHit(shooter, hitData, weaponConfig)
		
		-- Latency info
		local ping = HitDetectionAPI:GetPlayerPing(player)
		local stats = HitDetectionAPI:GetPlayerStats(player)
]]

local HitDetectionAPI = {}

local HitValidator = require(script.Parent.HitValidator)
local PositionHistory = require(script.Parent.PositionHistory)
local LatencyTracker = require(script.Parent.LatencyTracker)

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

--[[
	Initialize the hit detection system
	
	@param net table - Network module for ping measurement
]]
function HitDetectionAPI:Init(net)
	-- HitValidator internally initializes PositionHistory and LatencyTracker
	HitValidator:Init(net)
end

-- =============================================================================
-- HIT VALIDATION
-- =============================================================================

--[[
	Validate a hit from a client
	
	@param shooter Player - The player who fired
	@param hitData table - Parsed hit data from HitPacketUtils:ParsePacket()
	@param weaponConfig table - Weapon configuration
	@return boolean, string - (isValid, reason)
]]
function HitDetectionAPI:ValidateHit(shooter, hitData, weaponConfig)
	return HitValidator:ValidateHit(shooter, hitData, weaponConfig)
end

--[[
	Store a position sample for lag compensation
	
	@param player Player - The player
	@param position Vector3 - World position
	@param timestamp number - Server timestamp
	@param stance number? - Stance enum (0=Standing, 1=Crouched, 2=Sliding)
]]
function HitDetectionAPI:StorePosition(player, position, timestamp, stance)
	HitValidator:StorePosition(player, position, timestamp, stance)
end

--[[
	Update a player's stance for hit detection
	
	@param player Player - The player
	@param stance number - New stance enum value
]]
function HitDetectionAPI:SetPlayerStance(player, stance)
	HitValidator:SetPlayerStance(player, stance)
end

-- =============================================================================
-- LATENCY QUERIES
-- =============================================================================

--[[
	Get player's current ping in milliseconds
	
	@param player Player - The player to query
	@return number - Ping in ms
]]
function HitDetectionAPI:GetPlayerPing(player)
	return LatencyTracker:GetPing(player)
end

--[[
	Get player's jitter (ping variance) in milliseconds
	
	@param player Player - The player to query
	@return number - Jitter in ms
]]
function HitDetectionAPI:GetPlayerJitter(player)
	return LatencyTracker:GetJitter(player)
end

--[[
	Get the rollback time for a player (for lag compensation)
	
	@param player Player - The player to query
	@return number - Rollback time in seconds
]]
function HitDetectionAPI:GetRollbackTime(player)
	return LatencyTracker:GetRollbackTime(player)
end

--[[
	Get adaptive tolerances based on player's network conditions
	
	@param player Player - The player to query
	@return table - { PositionTolerance, HeadTolerance, TimestampTolerance }
]]
function HitDetectionAPI:GetAdaptiveTolerances(player)
	return LatencyTracker:GetAdaptiveTolerances(player)
end

--[[
	Get full latency debug info for a player
	
	@param player Player - The player to query
	@return table? - { Ping, Jitter, Samples, RollbackTime, Tolerances }
]]
function HitDetectionAPI:GetLatencyInfo(player)
	return LatencyTracker:GetDebugInfo(player)
end

-- =============================================================================
-- POSITION HISTORY QUERIES
-- =============================================================================

--[[
	Get a player's position at a specific timestamp
	
	@param player Player - The player to query
	@param timestamp number - Target timestamp
	@return Vector3? - Position at that time, or nil
]]
function HitDetectionAPI:GetPositionAtTime(player, timestamp)
	return PositionHistory:GetPositionAtTime(player, timestamp)
end

--[[
	Get a player's stance at a specific timestamp
	
	@param player Player - The player to query
	@param timestamp number - Target timestamp
	@return number? - Stance enum value, or nil
]]
function HitDetectionAPI:GetStanceAtTime(player, timestamp)
	return PositionHistory:GetStanceAtTime(player, timestamp)
end

--[[
	Get stance name at a specific timestamp
	
	@param player Player - The player to query
	@param timestamp number - Target timestamp
	@return string? - "Standing", "Crouched", or "Sliding"
]]
function HitDetectionAPI:GetStanceNameAtTime(player, timestamp)
	return PositionHistory:GetStanceNameAtTime(player, timestamp)
end

--[[
	Get both position and stance at a specific timestamp
	
	@param player Player - The player to query
	@param timestamp number - Target timestamp
	@return Vector3?, number? - Position and stance
]]
function HitDetectionAPI:GetStateAtTime(player, timestamp)
	return PositionHistory:GetStateAtTime(player, timestamp)
end

--[[
	Get the time range of stored position history
	
	@param player Player - The player to query
	@return number?, number? - (oldestTime, newestTime)
]]
function HitDetectionAPI:GetHistoryTimeRange(player)
	return PositionHistory:GetTimeRange(player)
end

-- =============================================================================
-- STATISTICS & ANTI-CHEAT
-- =============================================================================

--[[
	Get player combat statistics
	
	@param player Player - The player to query
	@return table? - { TotalShots, Hits, Headshots, HitRate, HeadshotRate, SessionDuration }
]]
function HitDetectionAPI:GetPlayerStats(player)
	return HitValidator:GetPlayerStats(player)
end

--[[
	Get all flagged players
	
	@return table - Array of { player, reason, timestamp, value }
]]
function HitDetectionAPI:GetFlaggedPlayers()
	return HitValidator:GetFlaggedPlayers()
end

--[[
	Clear a player's flag
	
	@param player Player - The player to clear
]]
function HitDetectionAPI:ClearPlayerFlag(player)
	HitValidator:ClearFlag(player)
end

--[[
	Reset a player's combat statistics
	
	@param player Player - The player to reset
]]
function HitDetectionAPI:ResetPlayerStats(player)
	HitValidator:ResetStats(player)
end

--[[
	Record a validation violation
	
	@param player Player - The player
	@param violationType string - Type of violation
	@param value number? - Associated value
]]
function HitDetectionAPI:RecordViolation(player, violationType, value)
	HitValidator:RecordViolation(player, violationType, value)
end

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

--[[
	Get current latency tracker configuration
	
	@return table - Configuration values
]]
function HitDetectionAPI:GetLatencyConfig()
	return LatencyTracker:GetConfig()
end

--[[
	Update a latency configuration value
	
	@param key string - Config key
	@param value any - New value
]]
function HitDetectionAPI:SetLatencyConfig(key, value)
	LatencyTracker:SetConfig(key, value)
end

-- =============================================================================
-- STANCE ENUM
-- =============================================================================

-- Expose stance enum for external use
HitDetectionAPI.Stance = {
	Standing = 0,
	Crouched = 1,
	Sliding = 2,
}

HitDetectionAPI.StanceNames = {
	[0] = "Standing",
	[1] = "Crouched",
	[2] = "Sliding",
}

return HitDetectionAPI
