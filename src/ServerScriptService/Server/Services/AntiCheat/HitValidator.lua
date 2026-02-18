--[[
	HitValidator.lua
	
	Server-side hit validation with lag compensation.
	Validates client-reported hits against server state using:
	- Position history backtracking
	- Ping-based rollback timing
	- Stance-aware hitbox validation
	- Line-of-sight verification
	- Statistical anti-cheat tracking
	
	Usage:
		HitValidator:Init(net)
		local isValid, reason = HitValidator:ValidateHit(shooter, hitData, weaponConfig)
]]

local HitValidator = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PositionHistory = require(script.Parent.PositionHistory)
local LatencyTracker = require(script.Parent.LatencyTracker)

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

local CONFIG = {
	-- Debug
	DebugLogging = true,            -- Enable detailed hit validation logging

	-- Timing
	MaxTimestampAge = 2.0,          -- Max seconds in the past (hard cap)
	MaxRollbackTime = 2.0,          -- Never rollback more than this (matches position history buffer)
	MinTimestampAge = -0.35,        -- Allow moderate clock jitter/network variance before rejecting
	FutureTimestampClamp = 0.25,    -- Clamp slightly-future timestamps instead of rejecting immediately
	ClientMaxFutureLead = 2.0,      -- Reject only extreme future timestamps (likely tampering)
	ClientMaxPastAge = 10.0,        -- Reject only extreme stale timestamps (likely replay/tampering)

	-- Distance
	RangeTolerance = 1.2,           -- 20% extra range tolerance

	-- Position validation
	BasePositionTolerance = 8,      -- studs (scaled by ping) - includes root-to-hitbox surface offset
	BaseHeadTolerance = 6,          -- studs (for headshots, accounts for head height + body offset)
	HeadHeightOffset = 2.5,         -- studs above root where head is located
	BodyRadiusOffset = 3,           -- extra studs for hit point on body surface vs root center

	-- Rate limiting
	FireRateTolerance = 0.70,       -- Allow 30% faster than config (latency + jitter)

	-- Statistical tracking
	MinShotsForAnalysis = 50,       -- Shots before flagging for accuracy
	SuspiciousHitRate = 0.95,       -- 95%+ accuracy is suspicious
	SuspiciousHeadshotRate = 0.80,  -- 80%+ headshot rate is suspicious
	MinHeadshotsForAnalysis = 20,   -- Headshots before flagging ratio
}

-- Stance enum for comparison
local Stance = {
	Standing = 0,
	Crouched = 1,
	Sliding = 2,
}

-- Hitbox dimensions per stance (approximate)
local HITBOX_BOUNDS = {
	[Stance.Standing] = {
		Body = { Height = 3.5, Width = 2.0 },
		Head = { Height = 1.2, Width = 1.2 },
	},
	[Stance.Crouched] = {
		Body = { Height = 2.0, Width = 2.0 },
		Head = { Height = 1.0, Width = 1.0 },
	},
	[Stance.Sliding] = {
		Body = { Height = 1.5, Width = 2.5 },
		Head = { Height = 0.8, Width = 1.0 },
	},
}

-- =============================================================================
-- STATE
-- =============================================================================

HitValidator.LastFireTimes = {}    -- [player] = { [weaponId] = timestamp }
HitValidator.PlayerStats = {}      -- [player] = { TotalShots, Hits, Headshots, ... }
HitValidator.FlaggedPlayers = {}   -- [player] = { reason, timestamp, value }
HitValidator._net = nil

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function HitValidator:Init(net)
	self._net = net
	
	-- Initialize subsystems
	PositionHistory:Init()
	LatencyTracker:Init(net)
	
	-- Setup for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		self:_initPlayer(player)
	end
	
	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		self:_initPlayer(player)
	end)
	
	-- Cleanup on leave
	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)
end

function HitValidator:_initPlayer(player)
	self.PlayerStats[player] = {
		TotalShots = 0,
		Hits = 0,
		Headshots = 0,
		SessionStart = workspace:GetServerTimeNow(),
		LastHitTime = 0,
	}
	self.LastFireTimes[player] = {}
end

function HitValidator:_cleanupPlayer(player)
	self.PlayerStats[player] = nil
	self.LastFireTimes[player] = nil
	self.FlaggedPlayers[player] = nil
end

-- =============================================================================
-- MAIN VALIDATION
-- =============================================================================

--[[
	Validate a hit from a client
	
	@param shooter Player - The player who fired
	@param hitData table - Parsed hit data from HitPacketUtils:ParsePacket()
	@param weaponConfig table - Weapon configuration from LoadoutConfig
	@return boolean, string - (isValid, reason)
]]
function HitValidator:ValidateHit(shooter, hitData, weaponConfig)
	local now = hitData.serverReceiveTime or workspace:GetServerTimeNow()

	-- Client timestamp is advisory only. We only reject extreme values.
	if type(hitData.timestamp) == "number" then
		local futureDelta = hitData.timestamp - now
		local pastAge = now - hitData.timestamp

		if futureDelta > 0 and futureDelta <= CONFIG.FutureTimestampClamp then
			hitData.timestamp = now
		end

		if not RunService:IsStudio() and futureDelta > CONFIG.ClientMaxFutureLead then
			return false, "TimestampInFuture"
		end

		if pastAge > CONFIG.ClientMaxPastAge then
			return false, "TimestampTooOld"
		end
	end
	
	-- Get network conditions
	local rollbackTime = LatencyTracker:GetRollbackTime(shooter)
	local tolerances = LatencyTracker:GetAdaptiveTolerances(shooter)

	-- Server-authoritative shot time for all rollback validations.
	local clampedRollback = math.min(rollbackTime, CONFIG.MaxRollbackTime)
	local estimatedShotTime = now - clampedRollback
	local oldestAllowed = now - CONFIG.MaxTimestampAge
	hitData.timestamp = math.clamp(estimatedShotTime, oldestAllowed, now)
	
	-- 1. RATE LIMITING
	local valid, reason
	valid, reason = self:_validateFireRate(shooter, now, weaponConfig)
	if not valid then
		return false, reason
	end
	local weaponId = weaponConfig.name or weaponConfig.weaponName or "Unknown"
	if not self.LastFireTimes[shooter] then
		self.LastFireTimes[shooter] = {}
	end
	self.LastFireTimes[shooter][weaponId] = now
	
	-- 2. RANGE VALIDATION
	valid, reason = self:_validateRange(hitData, weaponConfig)
	if not valid then
		return false, reason
	end
	
	-- 3. POSITION BACKTRACKING (if target is a player)
	if hitData.hitPlayer then
		valid, reason = self:_validatePositionBacktrack(shooter, hitData, rollbackTime, tolerances)
		if not valid then
			return false, reason
		end
		
		-- 4. STANCE VALIDATION
		valid, reason = self:_validateStance(hitData, rollbackTime)
		if not valid then
			return false, reason
		end
		
		-- 5. LINE-OF-SIGHT CHECK
		valid, reason = self:_validateLineOfSight(shooter, hitData, rollbackTime)
		if not valid then
			return false, reason
		end
	end
	
	-- 6. UPDATE STATISTICS
	self:_updateStats(shooter, hitData.hitPlayer ~= nil, hitData.isHeadshot)

	if CONFIG.DebugLogging then
		warn(string.format("[HitValidator] VALID: shooter=%s target=%s damage pipeline continuing",
			shooter and shooter.Name or "?", hitData.hitPlayer and hitData.hitPlayer.Name or "nil (env hit)"))
	end
	
	return true, "Valid"
end

-- =============================================================================
-- VALIDATION LAYERS
-- =============================================================================

function HitValidator:_validateTimestamp(timestamp, now, tolerances)
	local age = now - timestamp
	local maxAge = math.min(tolerances.TimestampTolerance, CONFIG.MaxTimestampAge)
	
	-- Check if timestamp is in the future (with small tolerance)
	if age < CONFIG.MinTimestampAge then
		return false, "TimestampInFuture"
	end
	
	-- Check if timestamp is too old
	if age > maxAge then
		return false, "TimestampTooOld"
	end
	
	return true
end

function HitValidator:_validateFireRate(shooter, now, weaponConfig)
	local fireRate = weaponConfig.fireRate or 600
	local fireInterval = 60 / fireRate

	local weaponId = weaponConfig.name or weaponConfig.weaponName or "Unknown"
	if not self.LastFireTimes[shooter] then
		self.LastFireTimes[shooter] = {}
	end
	local lastFire = self.LastFireTimes[shooter][weaponId] or 0

	local timeSinceLastFire = now - lastFire
	local minInterval = fireInterval * CONFIG.FireRateTolerance
	
	if timeSinceLastFire < minInterval then
		if CONFIG.DebugLogging then
			warn(string.format("[HitValidator] FireRateTooFast: %s weapon=%s timeSince=%.4f minInterval=%.4f", 
				shooter and shooter.Name or "?", tostring(weaponId), timeSinceLastFire, minInterval))
		end
		return false, "FireRateTooFast"
	end
	
	return true
end

function HitValidator:_validateRange(hitData, weaponConfig)
	local distance = (hitData.hitPosition - hitData.origin).Magnitude
	local maxRange = (weaponConfig.range or 100) * CONFIG.RangeTolerance
	
	if distance > maxRange then
		return false, "OutOfRange"
	end
	
	return true
end

function HitValidator:_validatePositionBacktrack(shooter, hitData, rollbackTime, tolerances)
	local hitTime = hitData.timestamp
	
	-- Clamp rollback time to prevent abuse
	local clampedRollback = math.min(rollbackTime, CONFIG.MaxRollbackTime)
	local now = workspace:GetServerTimeNow()
	local minLookbackTime = now - clampedRollback
	local lookbackTime = math.max(hitTime, minLookbackTime)
	
	-- Get target's position at hit time
	local targetPosAtHit = PositionHistory:GetPositionAtTime(hitData.hitPlayer, lookbackTime)
	
	if not targetPosAtHit then
		if CONFIG.DebugLogging then
			warn("[HitValidator] PositionBacktrack: no history for", hitData.hitPlayer and hitData.hitPlayer.Name or "?", "- allowing hit")
		end
		-- No position history - allow hit (player just spawned)
		return true
	end
	
	-- Calculate tolerance based on hit type
	local baseTolerance
	if hitData.isHeadshot then
		baseTolerance = tolerances.HeadTolerance or CONFIG.BaseHeadTolerance
	else
		baseTolerance = tolerances.PositionTolerance or CONFIG.BasePositionTolerance
	end
	-- Add body radius offset: client hit position is on the body surface,
	-- but server position history tracks the root center.
	local tolerance = baseTolerance + CONFIG.BodyRadiusOffset

	-- Consider target's ping as well for combined tolerance
	local pingFactor = 1.0
	if hitData.hitPlayer and hitData.hitPlayer.Parent then
		local targetPing = LatencyTracker:GetPing(hitData.hitPlayer)
		local shooterPing = LatencyTracker:GetPing(shooter)
		pingFactor = 1 + ((shooterPing + targetPing) / 300)
		pingFactor = math.min(pingFactor, 2.5)
		tolerance = tolerance * pingFactor
	end
	
	-- Check for stale position data and increase tolerance
	local oldestTime, newestTime = PositionHistory:GetTimeRange(hitData.hitPlayer)
	local dataAge = 0
	local staleFactor = 1.0
	if newestTime then
		dataAge = now - newestTime
		-- If data is older than 0.5s, increase tolerance (up to 2x at 2s stale)
		if dataAge > 0.5 then
			staleFactor = 1 + math.min((dataAge - 0.5) / 1.5, 1.0)  -- 1.0 to 2.0
			tolerance = tolerance * staleFactor
		end
	end
	
	-- Adjust target position for headshots (head is above root)
	local adjustedTargetPos = targetPosAtHit
	if hitData.isHeadshot then
		adjustedTargetPos = targetPosAtHit + Vector3.new(0, CONFIG.HeadHeightOffset, 0)
	end
	
	-- Check if hit position is within tolerance of target's actual position
	local offset = (hitData.hitPosition - adjustedTargetPos).Magnitude
	
	-- Debug logging
	if CONFIG.DebugLogging then
		local targetName = hitData.hitPlayer and hitData.hitPlayer.Name or "Unknown"
		warn(string.format("[HitValidator] PositionBacktrack: target=%s offset=%.2f tolerance=%.2f (base=%s pingFactor=%.2f staleFactor=%.2f)",
			targetName, offset, tolerance, tostring(baseTolerance), pingFactor, staleFactor))
	end
	
	if offset > tolerance then
		return false, "TargetNotAtPosition"
	end
	
	return true
end

function HitValidator:_validateStance(hitData, rollbackTime)
	local hitTime = hitData.timestamp
	local clampedRollback = math.min(rollbackTime, CONFIG.MaxRollbackTime)
	local now = workspace:GetServerTimeNow()
	local lookbackTime = math.max(hitTime, now - clampedRollback)
	
	-- Get target's stance at hit time
	local actualStance = PositionHistory:GetStanceAtTime(hitData.hitPlayer, lookbackTime)
	
	if actualStance == nil then
		-- No stance history - allow (assume standing)
		return true
	end
	
	-- Client claimed one stance, server has another
	-- Allow small discrepancy due to replication delay
	local claimedStance = hitData.targetStance
	
	-- If stances match, always valid
	if claimedStance == actualStance then
		return true
	end
	
	-- Allow adjacent stance transitions (standing <-> crouched, crouched <-> sliding)
	-- This accounts for replication delay during stance changes
	local stanceMatch = false
	if claimedStance == Stance.Standing then
		stanceMatch = (actualStance == Stance.Standing or actualStance == Stance.Crouched)
	elseif claimedStance == Stance.Crouched then
		stanceMatch = (actualStance == Stance.Standing or actualStance == Stance.Crouched or actualStance == Stance.Sliding)
	elseif claimedStance == Stance.Sliding then
		stanceMatch = (actualStance == Stance.Crouched or actualStance == Stance.Sliding)
	end
	
	if not stanceMatch then
		if CONFIG.DebugLogging then
			warn(string.format("[HitValidator] StanceMismatch: target=%s claimed=%d actual=%d",
				hitData.hitPlayer and hitData.hitPlayer.Name or "?", claimedStance, actualStance))
		end
		return false, "StanceMismatch"
	end
	
	return true
end

function HitValidator:_validateLineOfSight(shooter, hitData, rollbackTime)
	-- Use hitData.origin (camera/eye position from the client packet) as the ray
	-- start. PositionHistory stores root (waist-height) positions which are ~2.5
	-- studs below the camera. At close/medium range the angular difference causes
	-- false "LineOfSightBlocked" rejections that don't affect long-range weapons
	-- like Sniper. Range + backtrack checks already validate the claim.
	local shooterOrigin = hitData.origin
	
	local rayDirection = (hitData.hitPosition - shooterOrigin).Unit
	local rayLength = (hitData.hitPosition - shooterOrigin).Magnitude
	
	-- Exclude ALL player characters — the LOS check only cares about static
	-- environment geometry. Other players' physical rigs should never cause a
	-- false obstruction.
	local excludeList = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(excludeList, plr.Character)
		end
	end

	-- Exclude non-gameplay folders that the client also excludes
	local folderNames = { "Effects", "VoxelCache", "__Destruction", "VoxelDebris", "Ragdolls", "Rigs" }
	for _, name in ipairs(folderNames) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(excludeList, folder)
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = excludeList
	rayParams.RespectCanCollide = true

	local result = workspace:Raycast(shooterOrigin, rayDirection * rayLength, rayParams)

	if result then
		local distToTarget = (result.Position - hitData.hitPosition).Magnitude
		if distToTarget > CONFIG.BodyRadiusOffset + 2 then
			if CONFIG.DebugLogging then
				warn(string.format("[HitValidator] LOS blocked: shooter=%s obstruction='%s' class=%s distToTarget=%.2f tolerance=%.2f",
					shooter and shooter.Name or "?",
					result.Instance and result.Instance:GetFullName() or "?",
					result.Instance and result.Instance.ClassName or "?",
					distToTarget, CONFIG.BodyRadiusOffset + 2))
			end
			return false, "LineOfSightBlocked"
		end
	end

	return true
end

-- =============================================================================
-- STATISTICAL TRACKING
-- =============================================================================

function HitValidator:_updateStats(player, isHit, isHeadshot)
	local stats = self.PlayerStats[player]
	if not stats then return end
	
	stats.TotalShots = stats.TotalShots + 1
	
	if isHit then
		stats.Hits = stats.Hits + 1
		stats.LastHitTime = workspace:GetServerTimeNow()
		
		if isHeadshot then
			stats.Headshots = stats.Headshots + 1
		end
	end
	
	-- Check for suspicious patterns
	self:_checkSuspiciousStats(player)
end

function HitValidator:_checkSuspiciousStats(player)
	local stats = self.PlayerStats[player]
	if not stats then return end
	
	-- Need minimum shots for analysis
	if stats.TotalShots < CONFIG.MinShotsForAnalysis then
		return
	end
	
	local hitRate = stats.Hits / stats.TotalShots
	
	-- Check hit rate
	if hitRate > CONFIG.SuspiciousHitRate then
		self:_flagPlayer(player, "SuspiciousAccuracy", hitRate)
	end
	
	-- Check headshot rate
	if stats.Headshots >= CONFIG.MinHeadshotsForAnalysis then
		local headshotRate = stats.Headshots / stats.Hits
		if headshotRate > CONFIG.SuspiciousHeadshotRate then
			self:_flagPlayer(player, "SuspiciousHeadshotRate", headshotRate)
		end
	end
end

function HitValidator:_flagPlayer(player, reason, value)
	-- Don't re-flag for same reason
	local existing = self.FlaggedPlayers[player]
	if existing and existing.reason == reason then
		return
	end
	
	self.FlaggedPlayers[player] = {
		reason = reason,
		timestamp = workspace:GetServerTimeNow(),
		value = value,
	}
	
	
	-- TODO: Send to analytics, notify admins, etc.
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--[[
	Record a validation violation
	
	@param player Player - The player
	@param violationType string - Type of violation
	@param value number? - Associated value
]]
function HitValidator:RecordViolation(player, violationType, value)
end

--[[
	Get player statistics
	
	@param player Player - The player to query
	@return table? - Stats or nil
]]
function HitValidator:GetPlayerStats(player)
	local stats = self.PlayerStats[player]
	if not stats then return nil end
	
	local hitRate = stats.TotalShots > 0 and (stats.Hits / stats.TotalShots) or 0
	local headshotRate = stats.Hits > 0 and (stats.Headshots / stats.Hits) or 0
	
	return {
		TotalShots = stats.TotalShots,
		Hits = stats.Hits,
		Headshots = stats.Headshots,
		HitRate = hitRate,
		HeadshotRate = headshotRate,
		SessionDuration = workspace:GetServerTimeNow() - stats.SessionStart,
	}
end

--[[
	Get all flagged players
	
	@return table - Array of {player, reason, timestamp, value}
]]
function HitValidator:GetFlaggedPlayers()
	local result = {}
	for player, data in pairs(self.FlaggedPlayers) do
		if player.Parent then
			table.insert(result, {
				player = player,
				reason = data.reason,
				timestamp = data.timestamp,
				value = data.value,
			})
		end
	end
	return result
end

--[[
	Clear a player's flag
	
	@param player Player - The player to clear
]]
function HitValidator:ClearFlag(player)
	self.FlaggedPlayers[player] = nil
end

--[[
	Reset a player's statistics
	
	@param player Player - The player to reset
]]
function HitValidator:ResetStats(player)
	if self.PlayerStats[player] then
		self.PlayerStats[player] = {
			TotalShots = 0,
			Hits = 0,
			Headshots = 0,
			SessionStart = workspace:GetServerTimeNow(),
			LastHitTime = 0,
		}
	end
end

--[[
	Get latency info for a player (delegates to LatencyTracker)
	
	@param player Player - The player to query
	@return table? - Latency debug info
]]
function HitValidator:GetPlayerLatency(player)
	return LatencyTracker:GetDebugInfo(player)
end

--[[
	Store a position sample (called from ReplicationService)
	
	@param player Player - The player
	@param position Vector3 - World position
	@param timestamp number - Timestamp
	@param stance number? - Stance enum value
]]
function HitValidator:StorePosition(player, position, timestamp, stance)
	PositionHistory:StoreSample(player, position, timestamp, stance)
end

--[[
	Update player stance (called when crouch state changes)
	
	@param player Player - The player
	@param stance number - New stance
]]
function HitValidator:SetPlayerStance(player, stance)
	PositionHistory:SetStance(player, stance)
end

return HitValidator
