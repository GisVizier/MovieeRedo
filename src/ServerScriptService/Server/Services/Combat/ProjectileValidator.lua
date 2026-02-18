--[[
	ProjectileValidator.lua
	
	Server-side validation for projectile hits.
	Validates hit claims from clients using position history, flight time checks,
	and trajectory verification.
	
	Integrates with existing HitDetectionAPI for position history and latency tracking.
	
	Usage:
		local ProjectileValidator = require(path.to.ProjectileValidator)
		ProjectileValidator:Init(hitDetectionAPI)
		
		local valid, reason = ProjectileValidator:ValidateHit(shooter, hitData, weaponConfig)
]]

local ProjectileValidator = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ProjectilePhysics = require(Locations.Shared.Util:WaitForChild("ProjectilePhysics"))

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

local CONFIG = {
	-- Debug
	DebugLogging = true,

	-- Timestamp validation
	MaxTimestampAge = 2.0,        -- Max time in past for hits (seconds)
	MinTimestampAge = -0.1,       -- Small tolerance for processing delay
	MaxFlightTime = 10.0,         -- Maximum allowed flight time

	-- Flight time validation
	FlightTimeTolerance = 0.30,   -- 30% variance allowed (network jitter)

	-- Position validation
	BasePositionTolerance = 8,    -- Base tolerance (studs) - accounts for root-to-hitbox offset (~2-3 studs)
	MaxPositionTolerance = 30,    -- Maximum tolerance cap
	BaseHeadTolerance = 6,        -- Head hitbox tolerance (head is smaller but offset from root)
	HeadHeightOffset = 2.5,       -- Vertical offset for head position
	BodyRadiusOffset = 3,         -- Extra studs to account for hit point being on body surface vs root center

	-- Trajectory validation
	TrajectoryCheckPoints = 3,    -- Points to check along path

	-- Rate limiting
	FireRateTolerance = 0.70,     -- 30% faster allowed (latency + jitter)

	-- Anti-cheat thresholds
	MinShotsForAnalysis = 30,
	SuspiciousHitRate = 0.90,     -- 90%+ accuracy triggers flag
	SuspiciousHeadshotRate = 0.70, -- 70%+ headshot rate triggers flag
}

-- Internal state
local HitDetectionAPI = nil
local PlayerStats = {}
local FlaggedPlayers = {}

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

--[[
	Initialize the projectile validator
	
	@param hitDetectionAPI table - Reference to HitDetectionAPI for position history
]]
function ProjectileValidator:Init(hitDetectionAPI)
	HitDetectionAPI = hitDetectionAPI
	
	-- Clean up on player leaving
	Players.PlayerRemoving:Connect(function(player)
		PlayerStats[player] = nil
		FlaggedPlayers[player] = nil
	end)
end

-- =============================================================================
-- MAIN VALIDATION
-- =============================================================================

--[[
	Validate a projectile hit from a client
	
	@param shooter Player - The player who fired
	@param hitData table - Parsed hit data from ProjectilePacketUtils:ParseHitPacket()
	@param weaponConfig table - Weapon configuration with projectile settings
	@return boolean, string - (isValid, reason)
]]
function ProjectileValidator:ValidateHit(shooter, hitData, weaponConfig)
	if not shooter or not hitData or not weaponConfig then
		return false, "InvalidInput"
	end
	
	local projectileConfig = weaponConfig.projectile
	if not projectileConfig then
		return false, "NotProjectileWeapon"
	end
	
	-- 1. Timestamp validation
	local valid, reason = self:_validateTimestamps(shooter, hitData)
	if not valid then
		self:_logValidation(shooter, hitData, reason, false)
		return false, reason
	end
	
	-- 2. Flight time validation
	valid, reason = self:_validateFlightTime(hitData, projectileConfig)
	if not valid then
		self:_logValidation(shooter, hitData, reason, false)
		return false, reason
	end
	
	-- 3. Range validation
	valid, reason = self:_validateRange(hitData, weaponConfig)
	if not valid then
		self:_logValidation(shooter, hitData, reason, false)
		return false, reason
	end
	
	-- 4. Target position validation (if hitting a player)
	if hitData.targetUserId and hitData.targetUserId ~= 0 then
		valid, reason = self:_validateTargetPosition(shooter, hitData, projectileConfig)
		if not valid then
			self:_logValidation(shooter, hitData, reason, false)
			return false, reason
		end
	end
	
	-- 5. Trajectory validation
	valid, reason = self:_validateTrajectory(shooter, hitData, projectileConfig)
	if not valid then
		self:_logValidation(shooter, hitData, reason, false)
		return false, reason
	end
	
	-- 6. Track statistics
	self:_trackStats(shooter, hitData)
	
	self:_logValidation(shooter, hitData, "Valid", true)
	return true, "Valid"
end

-- =============================================================================
-- VALIDATION CHECKS
-- =============================================================================

--[[
	Validate timestamps
]]
function ProjectileValidator:_validateTimestamps(shooter, hitData)
	local now = workspace:GetServerTimeNow()
	local shooterPing = HitDetectionAPI and HitDetectionAPI:GetPlayerPing(shooter) or 80
	
	-- Fire timestamp not in future
	if hitData.fireTimestamp > now + math.abs(CONFIG.MinTimestampAge) then
		return false, "FireTimestampInFuture"
	end
	
	-- Impact timestamp after fire
	if hitData.impactTimestamp <= hitData.fireTimestamp then
		return false, "ImpactBeforeFire"
	end
	
	-- Fire timestamp not too old (scaled by ping)
	local maxAge = CONFIG.MaxTimestampAge + (shooterPing / 1000)
	if now - hitData.fireTimestamp > maxAge then
		return false, "TimestampTooOld"
	end
	
	-- Flight time not too long
	local flightTime = hitData.impactTimestamp - hitData.fireTimestamp
	if flightTime > CONFIG.MaxFlightTime then
		return false, "FlightTimeTooLong"
	end
	
	return true
end

--[[
	Validate flight time matches expected
]]
function ProjectileValidator:_validateFlightTime(hitData, projectileConfig)
	local claimedFlightTime = hitData.flightTime or (hitData.impactTimestamp - hitData.fireTimestamp)
	
	-- Create physics simulator
	local physics = ProjectilePhysics.new(projectileConfig)
	
	-- Calculate expected flight time
	local expectedFlightTime = physics:CalculateFlightTime(
		hitData.origin,
		hitData.hitPosition,
		projectileConfig.speed
	)
	
	-- Validate within tolerance
	local tolerance = CONFIG.FlightTimeTolerance
	local minTime = expectedFlightTime * (1 - tolerance)
	local maxTime = expectedFlightTime * (1 + tolerance)
	
	-- Add extra tolerance for high-ping players
	local shooterPing = HitDetectionAPI and HitDetectionAPI:GetPlayerPing(Players:GetPlayerByUserId(hitData.targetUserId)) or 80
	maxTime = maxTime + (shooterPing / 1000) * 0.5
	
	if claimedFlightTime < minTime * 0.8 or claimedFlightTime > maxTime * 1.5 then
		if CONFIG.DebugLogging then
			warn(string.format("[ProjectileValidator] FlightTimeMismatch: claimed=%.4f expected=%.4f min=%.4f max=%.4f",
				claimedFlightTime, expectedFlightTime, minTime * 0.8, maxTime * 1.5))
		end
		return false, "FlightTimeMismatch"
	end
	
	return true
end

--[[
	Validate hit is within weapon range
]]
function ProjectileValidator:_validateRange(hitData, weaponConfig)
	local distance = (hitData.hitPosition - hitData.origin).Magnitude
	local maxRange = weaponConfig.range or 500
	
	-- Allow 20% extra for tolerance
	if distance > maxRange * 1.2 then
		return false, "OutOfRange"
	end
	
	return true
end

--[[
	Validate target was at claimed position (using position history)
]]
function ProjectileValidator:_validateTargetPosition(shooter, hitData, projectileConfig)
	if not HitDetectionAPI then
		return true
	end
	
	local target = hitData.hitPlayer
	if not target then
		-- Try to find player by userId
		target = Players:GetPlayerByUserId(hitData.targetUserId)
		if not target then
			return false, "TargetNotFound"
		end
	end
	
	-- Get target position at IMPACT time (not fire time)
	local rollbackTime = HitDetectionAPI:GetRollbackTime(shooter) or 0.1
	local lookupTime = hitData.impactTimestamp - rollbackTime
	
	local historicalPosition = HitDetectionAPI:GetPositionAtTime(target, lookupTime)
	if not historicalPosition then
		if CONFIG.DebugLogging then
			warn(string.format("[ProjectileValidator] No position history for target=%s, allowing hit",
				target and target.Name or "?"))
		end
		return true
	end
	
	-- Adjust for headshot
	local adjustedPosition = historicalPosition
	if hitData.isHeadshot then
		adjustedPosition = historicalPosition + Vector3.new(0, CONFIG.HeadHeightOffset, 0)
	end
	
	-- Calculate offset
	local offset = (hitData.hitPosition - adjustedPosition).Magnitude
	
	-- Calculate tolerance
	local tolerance = self:_calculateTolerance(shooter, target, hitData, projectileConfig)
	
	if CONFIG.DebugLogging then
		warn(string.format("[ProjectileValidator] TargetPos: target=%s offset=%.2f tolerance=%.2f hit=%s hist=%s",
			target and target.Name or "?", offset, tolerance,
			tostring(hitData.hitPosition), tostring(adjustedPosition)))
	end
	
	if offset > tolerance then
		return false, "TargetNotAtPosition"
	end
	
	return true
end

--[[
	Validate trajectory wasn't obstructed
]]
function ProjectileValidator:_validateTrajectory(shooter, hitData, projectileConfig)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Exclude ALL player characters — trajectory checks only care about
	-- static environment geometry, not other players' physical rigs.
	local filterList = {}
	for _, plr in Players:GetPlayers() do
		if plr.Character then
			table.insert(filterList, plr.Character)
		end
	end

	local folderNames = { "Effects", "VoxelCache", "__Destruction", "VoxelDebris", "Ragdolls", "Rigs" }
	for _, name in ipairs(folderNames) do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(filterList, folder)
		end
	end

	raycastParams.FilterDescendantsInstances = filterList
	
	local physics = ProjectilePhysics.new(projectileConfig)
	
	local isClear, obstruction = physics:CheckTrajectoryObstruction(
		hitData.origin,
		hitData.hitPosition,
		raycastParams,
		CONFIG.TrajectoryCheckPoints
	)
	
	if not isClear and obstruction then
		if CONFIG.DebugLogging then
			warn(string.format("[ProjectileValidator] TrajectoryObstructed: shooter=%s obstruction=%s class=%s",
				shooter and shooter.Name or "?",
				obstruction and obstruction:GetFullName() or "?",
				obstruction and obstruction.ClassName or "?"))
		end
		return false, "TrajectoryObstructed"
	end
	
	return true
end

-- =============================================================================
-- TOLERANCE CALCULATION
-- =============================================================================

--[[
	Calculate position validation tolerance based on conditions
]]
function ProjectileValidator:_calculateTolerance(shooter, target, hitData, projectileConfig)
	local baseTolerance = hitData.isHeadshot and CONFIG.BaseHeadTolerance or CONFIG.BasePositionTolerance

	-- Add body radius offset: client hit position is on the body surface,
	-- but server position history tracks the root/HumanoidRootPart center.
	-- This inherent offset is 2-3 studs even on a perfectly stationary target.
	baseTolerance = baseTolerance + CONFIG.BodyRadiusOffset

	-- Scale with ping (both shooter and target contribute to mismatch)
	local shooterPing = HitDetectionAPI and HitDetectionAPI:GetPlayerPing(shooter) or 80
	local targetPing = HitDetectionAPI and HitDetectionAPI:GetPlayerPing(target) or 80
	local pingFactor = 1 + (shooterPing + targetPing) / 300
	pingFactor = math.clamp(pingFactor, 1, 2.5)

	-- Scale with flight time (longer flight = more prediction error)
	local flightTime = hitData.flightTime or 0
	local flightFactor = 1 + flightTime * 2
	flightFactor = math.clamp(flightFactor, 1, 3)

	-- Scale with pierce/bounce (accumulated error)
	local pierceFactor = 1 + (hitData.pierceCount or 0) * 0.5
	local bounceFactor = 1 + (hitData.bounceCount or 0) * 0.5

	-- Check for stale position history data and increase tolerance
	local staleFactor = 1.0
	if HitDetectionAPI and target then
		local _, newestTime = HitDetectionAPI:GetHistoryTimeRange(target)
		if newestTime then
			local dataAge = workspace:GetServerTimeNow() - newestTime
			if dataAge > 0.3 then
				staleFactor = 1 + math.min((dataAge - 0.3) / 1.0, 1.5)
			end
		end
	end

	local finalTolerance = baseTolerance * pingFactor * flightFactor * pierceFactor * bounceFactor * staleFactor

	return math.min(finalTolerance, CONFIG.MaxPositionTolerance)
end

-- =============================================================================
-- STATISTICS & ANTI-CHEAT
-- =============================================================================

--[[
	Track player statistics
]]
function ProjectileValidator:_trackStats(shooter, hitData)
	if not PlayerStats[shooter] then
		PlayerStats[shooter] = {
			TotalShots = 0,
			Hits = 0,
			Headshots = 0,
			SessionStart = os.clock(),
		}
	end
	
	local stats = PlayerStats[shooter]
	stats.TotalShots = stats.TotalShots + 1
	
	if hitData.targetUserId and hitData.targetUserId ~= 0 then
		stats.Hits = stats.Hits + 1
		
		if hitData.isHeadshot then
			stats.Headshots = stats.Headshots + 1
		end
	end
	
	-- Check for suspicious accuracy
	if stats.TotalShots >= CONFIG.MinShotsForAnalysis then
		local hitRate = stats.Hits / stats.TotalShots
		local headshotRate = stats.Hits > 0 and (stats.Headshots / stats.Hits) or 0
		
		if hitRate > CONFIG.SuspiciousHitRate then
			self:_flagPlayer(shooter, "SuspiciousHitRate", hitRate)
		end
		
		if headshotRate > CONFIG.SuspiciousHeadshotRate and stats.Headshots >= 20 then
			self:_flagPlayer(shooter, "SuspiciousHeadshotRate", headshotRate)
		end
	end
end

--[[
	Flag a player for suspicious activity
]]
function ProjectileValidator:_flagPlayer(player, reason, value)
	if FlaggedPlayers[player] then
		return -- Already flagged
	end
	
	FlaggedPlayers[player] = {
		reason = reason,
		value = value,
		timestamp = os.clock(),
	}
	
end

-- =============================================================================
-- DEBUG LOGGING
-- =============================================================================

--[[
	Log validation result
]]
function ProjectileValidator:_logValidation(shooter, hitData, reason, isValid)
	if not CONFIG.DebugLogging then
		return
	end
	
	local targetName = "Environment"
	if hitData.hitPlayer then
		targetName = hitData.hitPlayer.Name
	elseif hitData.targetUserId and hitData.targetUserId ~= 0 then
		targetName = "UserId:" .. tostring(hitData.targetUserId)
	end
	
	local symbol = isValid and "✓" or "✗"
	warn(string.format("[ProjectileValidator] %s %s -> %s | weapon=%s reason=%s",
		symbol, shooter and shooter.Name or "?", targetName,
		hitData.weaponName or "?", reason))
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

--[[
	Get player statistics
]]
function ProjectileValidator:GetPlayerStats(player)
	local stats = PlayerStats[player]
	if not stats then
		return nil
	end
	
	return {
		TotalShots = stats.TotalShots,
		Hits = stats.Hits,
		Headshots = stats.Headshots,
		HitRate = stats.TotalShots > 0 and (stats.Hits / stats.TotalShots) or 0,
		HeadshotRate = stats.Hits > 0 and (stats.Headshots / stats.Hits) or 0,
		SessionDuration = os.clock() - stats.SessionStart,
	}
end

--[[
	Get flagged players
]]
function ProjectileValidator:GetFlaggedPlayers()
	local flagged = {}
	for player, data in pairs(FlaggedPlayers) do
		table.insert(flagged, {
			player = player,
			reason = data.reason,
			value = data.value,
			timestamp = data.timestamp,
		})
	end
	return flagged
end

--[[
	Clear a player's flag
]]
function ProjectileValidator:ClearFlag(player)
	FlaggedPlayers[player] = nil
end

--[[
	Reset a player's stats
]]
function ProjectileValidator:ResetStats(player)
	PlayerStats[player] = nil
end

--[[
	Get configuration
]]
function ProjectileValidator:GetConfig()
	return CONFIG
end

--[[
	Update configuration
]]
function ProjectileValidator:SetConfig(key, value)
	if CONFIG[key] ~= nil then
		CONFIG[key] = value
	end
end

return ProjectileValidator
