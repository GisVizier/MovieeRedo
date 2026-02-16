--[[
	ProjectilePacketUtils.lua
	
	Utilities for creating and parsing projectile packets.
	Used by clients to send projectile data and servers to validate/replicate.
	
	Converts between game-friendly data tables and efficient buffer packets.
	
	Usage (Client):
		local packet = ProjectilePacketUtils:CreateSpawnPacket(spawnData, "Bow")
		Net:FireServer("ProjectileSpawned", packet)
		
		local hitPacket = ProjectilePacketUtils:CreateHitPacket(hitData, "Bow")
		Net:FireServer("ProjectileHit", hitPacket)
	
	Usage (Server):
		local spawnData = ProjectilePacketUtils:ParseSpawnPacket(packetString)
		local hitData = ProjectilePacketUtils:ParseHitPacket(packetString)
]]

local ProjectilePacketUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Sera = require(Locations.Shared.Util:WaitForChild("Sera"))
local SeraSchemas = require(Locations.Shared.Util.Sera:WaitForChild("Schemas"))

-- Local references to enums for faster lookup
local HitPartEnum = SeraSchemas.Enums.HitPart
local StanceEnum = SeraSchemas.Enums.Stance
local WeaponIdEnum = SeraSchemas.Enums.WeaponId
local DestroyReasonEnum = SeraSchemas.Enums.ProjectileDestroyReason

-- Reverse lookups
local HitPartNames = SeraSchemas.EnumNames.HitPart
local StanceNames = SeraSchemas.EnumNames.Stance
local WeaponIdNames = SeraSchemas.EnumNames.WeaponId
local DestroyReasonNames = SeraSchemas.EnumNames.ProjectileDestroyReason

-- Projectile ID counter (client-side, wraps at max uint32)
local projectileIdCounter = 0
local MAX_PROJECTILE_ID = 4294967295

-- =============================================================================
-- PROJECTILE ID GENERATION
-- =============================================================================

--[[
	Generate a unique projectile ID (client-side)
	
	@return number - Unique projectile ID
]]
function ProjectilePacketUtils:GenerateProjectileId()
	projectileIdCounter = (projectileIdCounter + 1) % MAX_PROJECTILE_ID
	-- Add some randomness to prevent prediction
	return projectileIdCounter + math.random(0, 65535) * 65536
end

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

--[[
	Get weapon ID from weapon name
	
	@param weaponName string - Name of the weapon
	@return number - WeaponId enum value
]]
function ProjectilePacketUtils:GetWeaponId(weaponName)
	return WeaponIdEnum[weaponName] or WeaponIdEnum.Unknown
end

--[[
	Get weapon name from ID
	
	@param weaponId number - WeaponId enum value
	@return string - Weapon name
]]
function ProjectilePacketUtils:GetWeaponName(weaponId)
	return WeaponIdNames[weaponId] or "Unknown"
end

--[[
	Get hit part type from a hit instance
	
	@param hitPart Instance? - The part that was hit
	@param isHeadshot boolean? - Override to force headshot
	@return number - HitPart enum value
]]
function ProjectilePacketUtils:GetHitPartType(hitPart, isHeadshot)
	if isHeadshot then
		return HitPartEnum.Head
	end
	
	if not hitPart then
		return HitPartEnum.None
	end
	
	local name = hitPart.Name
	
	-- Head hitbox parts
	if name == "Head" or name == "CrouchHead" or name == "HitboxHead" then
		return HitPartEnum.Head
	-- Body hitbox parts
	elseif name == "Body" or name == "CrouchBody" or name == "HitboxBody" or name == "Torso" or name == "HumanoidRootPart" then
		return HitPartEnum.Body
	-- Limb parts
	elseif name:match("Arm") or name:match("Leg") or name:match("Hand") or name:match("Foot") then
		return HitPartEnum.Limb
	end
	
	return HitPartEnum.Body
end

--[[
	Detect target's stance from hit part or character
	
	@param hitPart Instance? - The part that was hit
	@param targetCharacter Model? - The target character
	@return number - Stance enum value
]]
function ProjectilePacketUtils:DetectStance(hitPart, targetCharacter)
	if hitPart then
		local name = hitPart.Name
		if name == "CrouchBody" or name == "CrouchHead" then
			return StanceEnum.Crouched
		end
	end
	
	if targetCharacter then
		local isCrouching = targetCharacter:GetAttribute("IsCrouching")
		local isSliding = targetCharacter:GetAttribute("IsSliding")
		
		if isSliding then
			return StanceEnum.Sliding
		elseif isCrouching then
			return StanceEnum.Crouched
		end
	end
	
	return StanceEnum.Standing
end

-- =============================================================================
-- SPAWN PACKET (Client -> Server)
-- =============================================================================

--[[
	Create a projectile spawn packet
	
	@param spawnData table - Spawn data:
		{
			origin = Vector3,
			direction = Vector3,
			speed = number,
			chargePercent = number?, -- 0-1
			timestamp = number?,
		}
	@param weaponId string|number - Weapon name or ID
	@param spreadSeed number? - Random seed for spread verification
	@return string?, number? - Serialized buffer string, projectile ID
]]
function ProjectilePacketUtils:CreateSpawnPacket(spawnData, weaponId, spreadSeed)
	if not spawnData or not spawnData.origin or not spawnData.direction then
		return nil, nil
	end
	
	local projectileId = self:GenerateProjectileId()
	local weaponIdNum = type(weaponId) == "number" and weaponId or self:GetWeaponId(weaponId)
	local direction = spawnData.direction.Unit
	
	local packet = {
		FireTimestamp = spawnData.timestamp or workspace:GetServerTimeNow(),
		Origin = spawnData.origin,
		DirectionX = direction.X,
		DirectionY = direction.Y,
		DirectionZ = direction.Z,
		Speed = spawnData.speed or 100,
		ChargePercent = math.floor((spawnData.chargePercent or 1) * 255),
		WeaponId = weaponIdNum,
		ProjectileId = projectileId,
		SpreadSeed = spreadSeed or math.random(0, 65535),
	}
	
	local buf, err = Sera.Serialize(SeraSchemas.ProjectileSpawnPacket, packet)
	if not buf then
		return nil, nil
	end
	
	return buffer.tostring(buf), projectileId
end

--[[
	Parse a projectile spawn packet
	
	@param packetString string - Serialized buffer string
	@return table? - Parsed spawn data
]]
function ProjectilePacketUtils:ParseSpawnPacket(packetString)
	if type(packetString) ~= "string" then
		return nil
	end
	
	local buf = buffer.fromstring(packetString)
	
	local success, data = pcall(function()
		return Sera.Deserialize(SeraSchemas.ProjectileSpawnPacket, buf)
	end)
	
	if not success then
		return nil
	end
	
	return {
		fireTimestamp = data.FireTimestamp,
		origin = data.Origin,
		direction = Vector3.new(data.DirectionX, data.DirectionY, data.DirectionZ),
		speed = data.Speed,
		chargePercent = data.ChargePercent / 255,
		weaponId = data.WeaponId,
		weaponName = WeaponIdNames[data.WeaponId] or "Unknown",
		projectileId = data.ProjectileId,
		spreadSeed = data.SpreadSeed,
	}
end

-- =============================================================================
-- HIT PACKET (Client -> Server)
-- =============================================================================

--[[
	Create a projectile hit packet
	
	@param hitData table - Hit data:
		{
			fireTimestamp = number,
			impactTimestamp = number?,
			origin = Vector3,
			hitPosition = Vector3,
			hitPart = Instance?,
			hitPlayer = Player?,
			hitCharacter = Model?,
			isHeadshot = boolean?,
			projectileId = number,
			pierceCount = number?,
			bounceCount = number?,
		}
	@param weaponId string|number - Weapon name or ID
	@return string? - Serialized buffer string
]]
function ProjectilePacketUtils:CreateHitPacket(hitData, weaponId)
	if not hitData or not hitData.origin or not hitData.hitPosition then
		return nil
	end
	
	local targetUserId = 0
	if hitData.hitPlayer and hitData.hitPlayer:IsA("Player") then
		targetUserId = hitData.hitPlayer.UserId
	end
	
	local hitPartType = self:GetHitPartType(hitData.hitPart, hitData.isHeadshot)
	local weaponIdNum = type(weaponId) == "number" and weaponId or self:GetWeaponId(weaponId)
	local targetStance = self:DetectStance(hitData.hitPart, hitData.hitCharacter)
	
	local packet = {
		FireTimestamp = hitData.fireTimestamp or workspace:GetServerTimeNow(),
		ImpactTimestamp = hitData.impactTimestamp or workspace:GetServerTimeNow(),
		Origin = hitData.origin,
		HitPosition = hitData.hitPosition,
		TargetUserId = targetUserId,
		HitPart = hitPartType,
		WeaponId = weaponIdNum,
		ProjectileId = hitData.projectileId or 0,
		TargetStance = targetStance,
		PierceCount = hitData.pierceCount or 0,
		BounceCount = hitData.bounceCount or 0,
	}
	
	local buf, err = Sera.Serialize(SeraSchemas.ProjectileHitPacket, packet)
	if not buf then
		return nil
	end
	
	return buffer.tostring(buf)
end

--[[
	Parse a projectile hit packet
	
	@param packetString string - Serialized buffer string
	@return table? - Parsed hit data
]]
function ProjectilePacketUtils:ParseHitPacket(packetString)
	if type(packetString) ~= "string" then
		return nil
	end
	
	local buf = buffer.fromstring(packetString)
	
	local success, data = pcall(function()
		return Sera.Deserialize(SeraSchemas.ProjectileHitPacket, buf)
	end)
	
	if not success then
		return nil
	end
	
	-- Resolve player from userId
	local hitPlayer = nil
	if data.TargetUserId and data.TargetUserId ~= 0 then
		hitPlayer = Players:GetPlayerByUserId(data.TargetUserId)
		-- Fallback for test clients with negative IDs
		if not hitPlayer then
			for _, player in Players:GetPlayers() do
				if player.UserId == data.TargetUserId then
					hitPlayer = player
					break
				end
			end
		end
	end
	
	return {
		fireTimestamp = data.FireTimestamp,
		impactTimestamp = data.ImpactTimestamp,
		flightTime = data.ImpactTimestamp - data.FireTimestamp,
		origin = data.Origin,
		hitPosition = data.HitPosition,
		targetUserId = data.TargetUserId,
		hitPlayer = hitPlayer,
		hitPart = data.HitPart,
		hitPartName = HitPartNames[data.HitPart] or "Unknown",
		isHeadshot = data.HitPart == HitPartEnum.Head,
		weaponId = data.WeaponId,
		weaponName = WeaponIdNames[data.WeaponId] or "Unknown",
		projectileId = data.ProjectileId,
		targetStance = data.TargetStance,
		targetStanceName = StanceNames[data.TargetStance] or "Standing",
		pierceCount = data.PierceCount,
		bounceCount = data.BounceCount,
	}
end

-- =============================================================================
-- REPLICATE PACKET (Server -> Clients)
-- =============================================================================

--[[
	Create a projectile replicate packet (server-side)
	
	@param replicateData table - Replicate data:
		{
			shooterUserId = number,
			origin = Vector3,
			direction = Vector3,
			speed = number,
			projectileId = number,
			chargePercent = number?, -- 0-1
		}
	@param weaponId string|number - Weapon name or ID
	@return string? - Serialized buffer string
]]
function ProjectilePacketUtils:CreateReplicatePacket(replicateData, weaponId)
	if not replicateData or not replicateData.origin or not replicateData.direction then
		return nil
	end
	
	local weaponIdNum = type(weaponId) == "number" and weaponId or self:GetWeaponId(weaponId)
	local direction = replicateData.direction.Unit
	
	local packet = {
		ShooterUserId = replicateData.shooterUserId or 0,
		Origin = replicateData.origin,
		DirectionX = direction.X,
		DirectionY = direction.Y,
		DirectionZ = direction.Z,
		Speed = replicateData.speed or 100,
		ProjectileId = replicateData.projectileId or 0,
		WeaponId = weaponIdNum,
		ChargePercent = math.floor((replicateData.chargePercent or 1) * 255),
	}
	
	local buf, err = Sera.Serialize(SeraSchemas.ProjectileReplicatePacket, packet)
	if not buf then
		return nil
	end
	
	return buffer.tostring(buf)
end

--[[
	Parse a projectile replicate packet
	
	@param packetString string - Serialized buffer string
	@return table? - Parsed replicate data
]]
function ProjectilePacketUtils:ParseReplicatePacket(packetString)
	if type(packetString) ~= "string" then
		return nil
	end
	
	local buf = buffer.fromstring(packetString)
	
	local success, data = pcall(function()
		return Sera.Deserialize(SeraSchemas.ProjectileReplicatePacket, buf)
	end)
	
	if not success then
		return nil
	end
	
	-- Resolve shooter player
	local shooter = nil
	if data.ShooterUserId and data.ShooterUserId ~= 0 then
		shooter = Players:GetPlayerByUserId(data.ShooterUserId)
	end
	
	return {
		shooterUserId = data.ShooterUserId,
		shooter = shooter,
		origin = data.Origin,
		direction = Vector3.new(data.DirectionX, data.DirectionY, data.DirectionZ),
		speed = data.Speed,
		projectileId = data.ProjectileId,
		weaponId = data.WeaponId,
		weaponName = WeaponIdNames[data.WeaponId] or "Unknown",
		chargePercent = data.ChargePercent / 255,
	}
end

-- =============================================================================
-- DESTROYED PACKET (Server -> Clients)
-- =============================================================================

--[[
	Create a projectile destroyed packet (server-side)
	
	@param projectileId number - The projectile ID
	@param hitPosition Vector3 - Impact position for VFX
	@param reason string|number - Destroy reason
	@return string? - Serialized buffer string
]]
function ProjectilePacketUtils:CreateDestroyedPacket(projectileId, hitPosition, reason)
	local reasonNum = type(reason) == "number" and reason or (DestroyReasonEnum[reason] or DestroyReasonEnum.Timeout)
	
	local packet = {
		ProjectileId = projectileId,
		HitPosition = hitPosition or Vector3.zero,
		DestroyReason = reasonNum,
	}
	
	local buf, err = Sera.Serialize(SeraSchemas.ProjectileDestroyedPacket, packet)
	if not buf then
		return nil
	end
	
	return buffer.tostring(buf)
end

--[[
	Parse a projectile destroyed packet
	
	@param packetString string - Serialized buffer string
	@return table? - Parsed destroyed data
]]
function ProjectilePacketUtils:ParseDestroyedPacket(packetString)
	if type(packetString) ~= "string" then
		return nil
	end
	
	local buf = buffer.fromstring(packetString)
	
	local success, data = pcall(function()
		return Sera.Deserialize(SeraSchemas.ProjectileDestroyedPacket, buf)
	end)
	
	if not success then
		return nil
	end
	
	return {
		projectileId = data.ProjectileId,
		hitPosition = data.HitPosition,
		destroyReason = data.DestroyReason,
		destroyReasonName = DestroyReasonNames[data.DestroyReason] or "Unknown",
	}
end

-- =============================================================================
-- UTILITY
-- =============================================================================

--[[
	Get packet size information
	
	@return table - Size info for each packet type
]]
function ProjectilePacketUtils:GetPacketSizes()
	return {
		ProjectileSpawnPacket = 44,
		ProjectileHitPacket = 53,
		ProjectileReplicatePacket = 38,
		ProjectileDestroyedPacket = 17,
	}
end

--[[
	Validate packet structure without full parsing (quick check)
	
	@param packetString string - Serialized buffer string
	@param packetType string - "Spawn", "Hit", "Replicate", or "Destroyed"
	@return boolean - True if appears valid
]]
function ProjectilePacketUtils:ValidatePacketStructure(packetString, packetType)
	if type(packetString) ~= "string" then
		return false
	end
	
	local sizes = self:GetPacketSizes()
	local expectedSize = sizes["Projectile" .. packetType .. "Packet"]
	
	if not expectedSize then
		return false
	end
	
	-- Allow some tolerance for different serialization
	return #packetString >= expectedSize - 5 and #packetString <= expectedSize + 5
end

--[[
	Check if weapon config uses projectiles
	
	@param weaponConfig table - Weapon configuration from LoadoutConfig
	@return boolean - True if weapon uses projectile system
]]
function ProjectilePacketUtils:IsProjectileWeapon(weaponConfig)
	return weaponConfig and weaponConfig.projectile ~= nil
end

return ProjectilePacketUtils
