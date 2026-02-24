--[[
	ProjectileAPI.lua
	
	Public API for the Projectile System.
	Provides a clean facade for external systems to interact with projectile
	validation, tracking, and statistics.
	
	This module wraps ProjectileValidator and integrates with HitDetectionAPI.
	
	Usage:
		local ProjectileAPI = require(path.to.ProjectileAPI)
		ProjectileAPI:Init(net, hitDetectionAPI)
		
		-- Validation
		local valid, reason = ProjectileAPI:ValidateHit(shooter, hitData, weaponConfig)
		
		-- Queries
		local stats = ProjectileAPI:GetPlayerStats(player)
		local isProjectile = ProjectileAPI:IsProjectileWeapon(weaponConfig)
]]

local ProjectileAPI = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ProjectileValidator = require(script.Parent.ProjectileValidator)
local ProjectilePhysics = require(Locations.Shared.Util:WaitForChild("ProjectilePhysics"))
local ProjectilePacketUtils = require(Locations.Shared.Util:WaitForChild("ProjectilePacketUtils"))

-- Internal state
local Net = nil
local HitDetectionAPI = nil
local ActiveProjectiles = {} -- Track active projectiles per player
local Initialized = false

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

--[[
	Initialize the projectile API
	
	@param net table - Network module for events
	@param hitDetectionAPI table - Reference to HitDetectionAPI for position history
]]
function ProjectileAPI:Init(net, hitDetectionAPI)
	if Initialized then
		return
	end
	
	Net = net
	HitDetectionAPI = hitDetectionAPI
	
	-- Initialize validator
	ProjectileValidator:Init(hitDetectionAPI)
	
	-- Clean up on player leaving
	Players.PlayerRemoving:Connect(function(player)
		ActiveProjectiles[player] = nil
	end)
	
	Initialized = true
	-- print("[ProjectileAPI] Initialized")
end

-- =============================================================================
-- HIT VALIDATION
-- =============================================================================

--[[
	Validate a projectile hit from a client
	
	@param shooter Player - The player who fired
	@param hitData table - Parsed hit data from ProjectilePacketUtils:ParseHitPacket()
	@param weaponConfig table - Weapon configuration with projectile settings
	@return boolean, string - (isValid, reason)
]]
function ProjectileAPI:ValidateHit(shooter, hitData, weaponConfig)
	return ProjectileValidator:ValidateHit(shooter, hitData, weaponConfig)
end

--[[
	Validate a projectile spawn from a client
	
	@param shooter Player - The player who fired
	@param spawnData table - Parsed spawn data from ProjectilePacketUtils:ParseSpawnPacket()
	@param weaponConfig table - Weapon configuration
	@return boolean, string - (isValid, reason)
]]
function ProjectileAPI:ValidateSpawn(shooter, spawnData, weaponConfig)
	if not shooter or not spawnData or not weaponConfig then
		return false, "InvalidInput"
	end
	
	-- Basic validation
	local now = workspace:GetServerTimeNow()
	
	-- Timestamp not in future
	if spawnData.fireTimestamp > now + 0.1 then
		return false, "TimestampInFuture"
	end
	
	-- Timestamp not too old
	if now - spawnData.fireTimestamp > 1.0 then
		return false, "TimestampTooOld"
	end
	
	-- Track projectile
	self:_trackProjectile(shooter, spawnData)
	
	return true, "Valid"
end

-- =============================================================================
-- PROJECTILE TRACKING
-- =============================================================================

--[[
	Track an active projectile
]]
function ProjectileAPI:_trackProjectile(player, spawnData)
	if not ActiveProjectiles[player] then
		ActiveProjectiles[player] = {}
	end
	
	-- Limit active projectiles per player
	local maxProjectiles = 10
	if #ActiveProjectiles[player] >= maxProjectiles then
		-- Remove oldest
		table.remove(ActiveProjectiles[player], 1)
	end
	
	table.insert(ActiveProjectiles[player], {
		id = spawnData.projectileId,
		fireTimestamp = spawnData.fireTimestamp,
		origin = spawnData.origin,
		direction = spawnData.direction,
		speed = spawnData.speed,
		weaponId = spawnData.weaponId,
	})
end

--[[
	Get active projectiles for a player
	
	@param player Player - The player to query
	@return table - Array of active projectile data
]]
function ProjectileAPI:GetActiveProjectiles(player)
	return ActiveProjectiles[player] or {}
end

--[[
	Remove a projectile from tracking
	
	@param player Player - The player
	@param projectileId number - The projectile ID to remove
]]
function ProjectileAPI:RemoveProjectile(player, projectileId)
	local projectiles = ActiveProjectiles[player]
	if not projectiles then
		return
	end
	
	for i, proj in ipairs(projectiles) do
		if proj.id == projectileId then
			table.remove(projectiles, i)
			return
		end
	end
end

--[[
	Find a tracked projectile by ID
	
	@param player Player - The player
	@param projectileId number - The projectile ID
	@return table? - Projectile data or nil
]]
function ProjectileAPI:FindProjectile(player, projectileId)
	local projectiles = ActiveProjectiles[player]
	if not projectiles then
		return nil
	end
	
	for _, proj in ipairs(projectiles) do
		if proj.id == projectileId then
			return proj
		end
	end
	
	return nil
end

-- =============================================================================
-- PHYSICS QUERIES
-- =============================================================================

--[[
	Create a physics simulator for a weapon config
	
	@param weaponConfig table - Weapon configuration with projectile settings
	@return ProjectilePhysics - Physics simulator instance
]]
function ProjectileAPI:CreatePhysics(weaponConfig)
	local projectileConfig = weaponConfig.projectile
	if not projectileConfig then
		-- Return default physics if not a projectile weapon
		return ProjectilePhysics.new({
			speed = 500,
			gravity = 0,
			drag = 0,
		})
	end
	
	return ProjectilePhysics.new(projectileConfig)
end

--[[
	Calculate expected flight time between two points
	
	@param origin Vector3 - Start position
	@param target Vector3 - End position
	@param weaponConfig table - Weapon configuration
	@return number - Expected flight time in seconds
]]
function ProjectileAPI:CalculateFlightTime(origin, target, weaponConfig)
	local physics = self:CreatePhysics(weaponConfig)
	local speed = weaponConfig.projectile and weaponConfig.projectile.speed or 500
	return physics:CalculateFlightTime(origin, target, speed)
end

--[[
	Predict impact point for a projectile
	
	@param origin Vector3 - Fire position
	@param direction Vector3 - Fire direction
	@param weaponConfig table - Weapon configuration
	@param raycastParams RaycastParams - Collision parameters
	@return table - { position, normal, distance, flightTime, instance }
]]
function ProjectileAPI:PredictImpact(origin, direction, weaponConfig, raycastParams)
	local physics = self:CreatePhysics(weaponConfig)
	local speed = weaponConfig.projectile and weaponConfig.projectile.speed or 500
	return physics:PredictImpact(origin, direction, speed, raycastParams)
end

-- =============================================================================
-- CONFIGURATION QUERIES
-- =============================================================================

--[[
	Check if a weapon uses the projectile system
	
	@param weaponConfig table - Weapon configuration
	@return boolean - True if weapon uses projectiles
]]
function ProjectileAPI:IsProjectileWeapon(weaponConfig)
	return ProjectilePacketUtils:IsProjectileWeapon(weaponConfig)
end

--[[
	Get projectile configuration from weapon config
	
	@param weaponConfig table - Weapon configuration
	@return table? - Projectile config or nil
]]
function ProjectileAPI:GetProjectileConfig(weaponConfig)
	return weaponConfig and weaponConfig.projectile
end

-- =============================================================================
-- STATISTICS & ANTI-CHEAT
-- =============================================================================

--[[
	Get player combat statistics
	
	@param player Player - The player to query
	@return table? - { TotalShots, Hits, Headshots, HitRate, HeadshotRate, SessionDuration }
]]
function ProjectileAPI:GetPlayerStats(player)
	return ProjectileValidator:GetPlayerStats(player)
end

--[[
	Get all flagged players
	
	@return table - Array of { player, reason, timestamp, value }
]]
function ProjectileAPI:GetFlaggedPlayers()
	return ProjectileValidator:GetFlaggedPlayers()
end

--[[
	Get recent rejection log entries from the projectile validator.
	
	@param count number? - How many recent entries (default: all stored)
	@return table - Array of rejection entries, newest first
]]
function ProjectileAPI:GetRejectionLog(count)
	return ProjectileValidator:GetRejectionLog(count)
end

--[[
	Get rejection counts grouped by reason.
	
	@return table - { [reason] = count }
]]
function ProjectileAPI:GetRejectionSummary()
	return ProjectileValidator:GetRejectionSummary()
end

--[[
	Clear a player's flag
	
	@param player Player - The player to clear
]]
function ProjectileAPI:ClearPlayerFlag(player)
	ProjectileValidator:ClearFlag(player)
end

--[[
	Reset a player's combat statistics
	
	@param player Player - The player to reset
]]
function ProjectileAPI:ResetPlayerStats(player)
	ProjectileValidator:ResetStats(player)
end

-- =============================================================================
-- LATENCY QUERIES (Delegated to HitDetectionAPI)
-- =============================================================================

--[[
	Get player's current ping in milliseconds
	
	@param player Player - The player to query
	@return number - Ping in ms
]]
function ProjectileAPI:GetPlayerPing(player)
	if HitDetectionAPI then
		return HitDetectionAPI:GetPlayerPing(player)
	end
	return 80 -- Default
end

--[[
	Get the rollback time for a player
	
	@param player Player - The player to query
	@return number - Rollback time in seconds
]]
function ProjectileAPI:GetRollbackTime(player)
	if HitDetectionAPI then
		return HitDetectionAPI:GetRollbackTime(player)
	end
	return 0.1 -- Default
end

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

--[[
	Get validator configuration
	
	@return table - Configuration values
]]
function ProjectileAPI:GetValidatorConfig()
	return ProjectileValidator:GetConfig()
end

--[[
	Update a validator configuration value
	
	@param key string - Config key
	@param value any - New value
]]
function ProjectileAPI:SetValidatorConfig(key, value)
	ProjectileValidator:SetConfig(key, value)
end

-- =============================================================================
-- PACKET UTILITIES (Re-exported for convenience)
-- =============================================================================

--[[
	Parse a spawn packet
	
	@param packetString string - Serialized buffer
	@return table? - Parsed spawn data
]]
function ProjectileAPI:ParseSpawnPacket(packetString)
	return ProjectilePacketUtils:ParseSpawnPacket(packetString)
end

--[[
	Parse a hit packet
	
	@param packetString string - Serialized buffer
	@return table? - Parsed hit data
]]
function ProjectileAPI:ParseHitPacket(packetString)
	return ProjectilePacketUtils:ParseHitPacket(packetString)
end

--[[
	Create a replicate packet (server -> clients)
	
	@param replicateData table - Data to replicate
	@param weaponId string|number - Weapon identifier
	@return string? - Serialized buffer
]]
function ProjectileAPI:CreateReplicatePacket(replicateData, weaponId)
	return ProjectilePacketUtils:CreateReplicatePacket(replicateData, weaponId)
end

--[[
	Create a destroyed packet (server -> clients)
	
	@param projectileId number - Projectile ID
	@param hitPosition Vector3 - Impact position
	@param reason string|number - Destroy reason
	@return string? - Serialized buffer
]]
function ProjectileAPI:CreateDestroyedPacket(projectileId, hitPosition, reason)
	return ProjectilePacketUtils:CreateDestroyedPacket(projectileId, hitPosition, reason)
end

-- =============================================================================
-- ENUMS
-- =============================================================================

-- Expose destroy reason enum for external use
ProjectileAPI.DestroyReason = {
	Timeout = 0,
	HitTarget = 1,
	HitEnvironment = 2,
	OutOfRange = 3,
	Cancelled = 4,
}

-- Expose spread mode enum
ProjectileAPI.SpreadMode = {
	None = 0,
	Cone = 1,
	Pattern = 2,
}

return ProjectileAPI
