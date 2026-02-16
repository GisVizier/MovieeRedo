--[[
	HitPacketUtils.lua
	
	Utilities for creating and parsing hit detection packets.
	Used by clients to send hit data and servers to validate it.
	
	Converts between game-friendly hit data tables and efficient buffer packets.
	
	Usage (Client):
		local packet = HitPacketUtils:CreatePacket(hitData, "Shotgun")
		Net:FireServer("WeaponFired", packet)
	
	Usage (Server):
		local hitData = HitPacketUtils:ParsePacket(packetString)
		local isValid = HitValidator:ValidateHit(shooter, hitData, weaponConfig)
]]

local HitPacketUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Sera = require(Locations.Shared.Util:WaitForChild("Sera"))
local SeraSchemas = require(Locations.Shared.Util.Sera:WaitForChild("Schemas"))

-- Local references to enums for faster lookup
local HitPartEnum = SeraSchemas.Enums.HitPart
local StanceEnum = SeraSchemas.Enums.Stance
local WeaponIdEnum = SeraSchemas.Enums.WeaponId

-- Reverse lookups
local HitPartNames = SeraSchemas.EnumNames.HitPart
local StanceNames = SeraSchemas.EnumNames.Stance
local WeaponIdNames = SeraSchemas.EnumNames.WeaponId

-- =============================================================================
-- HIT PART DETECTION
-- =============================================================================

--[[
	Determine hit part type from a hit instance
	
	@param hitPart Instance? - The part that was hit
	@param isHeadshot boolean? - Override to force headshot
	@return number - HitPart enum value
]]
function HitPacketUtils:GetHitPartType(hitPart, isHeadshot)
	if isHeadshot then
		return HitPartEnum.Head
	end
	
	if not hitPart then
		return HitPartEnum.None
	end
	
	local name = hitPart.Name
	
	-- Head hitbox parts (including hitbox folder variants)
	if name == "Head" or name == "CrouchHead" or name == "HitboxHead" then
		return HitPartEnum.Head
	-- Body hitbox parts
	elseif name == "Body" or name == "CrouchBody" or name == "HitboxBody" or name == "Torso" or name == "HumanoidRootPart" then
		return HitPartEnum.Body
	-- Limb parts (R6 character parts)
	elseif name:match("Arm") or name:match("Leg") or name:match("Hand") or name:match("Foot") then
		return HitPartEnum.Limb
	end
	
	-- Default to body for any other hit
	return HitPartEnum.Body
end

--[[
	Get weapon ID from weapon name
	
	@param weaponName string - Name of the weapon
	@return number - WeaponId enum value
]]
function HitPacketUtils:GetWeaponId(weaponName)
	return WeaponIdEnum[weaponName] or WeaponIdEnum.Unknown
end

--[[
	Get weapon name from ID
	
	@param weaponId number - WeaponId enum value
	@return string - Weapon name
]]
function HitPacketUtils:GetWeaponName(weaponId)
	return WeaponIdNames[weaponId] or "Unknown"
end

-- =============================================================================
-- STANCE DETECTION
-- =============================================================================

--[[
	Detect target's stance from hit part or character
	
	@param hitPart Instance? - The part that was hit
	@param targetCharacter Model? - The target character
	@return number - Stance enum value
]]
function HitPacketUtils:DetectStance(hitPart, targetCharacter)
	-- Check if we hit a crouch-specific part
	if hitPart then
		local name = hitPart.Name
		if name == "CrouchBody" or name == "CrouchHead" then
			return StanceEnum.Crouched
		end
	end
	
	-- Check character attribute if available
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
-- PACKET CREATION (Client -> Server)
-- =============================================================================

--[[
	Create a hit packet buffer from hit data
	
	@param hitData table - Hit data from raycast:
		{
			origin = Vector3,
			hitPosition = Vector3,
			hitPart = Instance?,
			hitPlayer = Player?,
			hitCharacter = Model?,
			isHeadshot = boolean?,
			timestamp = number?,
		}
	@param weaponId string|number - Weapon name or ID
	@return string? - Serialized buffer string, or nil on error
]]
function HitPacketUtils:CreatePacket(hitData, weaponId)
	if not hitData or not hitData.origin or not hitData.hitPosition then
		return nil
	end
	
	-- Get target user ID (0 if not a player)
	local targetUserId = 0
	if hitData.hitPlayer and hitData.hitPlayer:IsA("Player") then
		targetUserId = hitData.hitPlayer.UserId
	end
	
	-- Determine hit part type
	local hitPartType = self:GetHitPartType(hitData.hitPart, hitData.isHeadshot)
	
	-- Get weapon ID
	local weaponIdNum = type(weaponId) == "number" and weaponId or self:GetWeaponId(weaponId)
	
	-- Detect target stance
	local targetStance = self:DetectStance(hitData.hitPart, hitData.hitCharacter)
	
	-- Build packet data
	local packet = {
		Timestamp = hitData.timestamp or workspace:GetServerTimeNow(),
		Origin = hitData.origin,
		HitPosition = hitData.hitPosition,
		TargetUserId = targetUserId,
		HitPart = hitPartType,
		WeaponId = weaponIdNum,
		TargetStance = targetStance,
	}
	
	-- Serialize
	local buf, err = Sera.Serialize(SeraSchemas.HitPacket, packet)
	if not buf then
		return nil
	end
	
	return buffer.tostring(buf)
end

--[[
	Create a shotgun hit packet with pellet information
	
	@param hitData table - Same as CreatePacket, plus:
		{
			pelletHits = number,      -- Total pellets that hit this target
			headshotPellets = number, -- Pellets that were headshots
		}
	@param weaponId string|number - Weapon name or ID
	@return string? - Serialized buffer string
]]
function HitPacketUtils:CreateShotgunPacket(hitData, weaponId)
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
		Timestamp = hitData.timestamp or workspace:GetServerTimeNow(),
		Origin = hitData.origin,
		HitPosition = hitData.hitPosition,
		TargetUserId = targetUserId,
		HitPart = hitPartType,
		WeaponId = weaponIdNum,
		TargetStance = targetStance,
		PelletHits = hitData.pelletHits or 1,
		HeadshotPellets = hitData.headshotPellets or 0,
	}
	
	local buf, err = Sera.Serialize(SeraSchemas.ShotgunHitPacket, packet)
	if not buf then
		return nil
	end
	
	return buffer.tostring(buf)
end

-- =============================================================================
-- PACKET PARSING (Server)
-- =============================================================================

--[[
	Parse a hit packet buffer into usable hit data
	
	@param packetString string - Serialized buffer string
	@return table? - Parsed hit data:
		{
			timestamp = number,
			origin = Vector3,
			hitPosition = Vector3,
			targetUserId = number,
			hitPlayer = Player?,      -- Resolved from userId
			hitPart = number,         -- HitPart enum
			hitPartName = string,     -- "None"/"Body"/"Head"/"Limb"
			isHeadshot = boolean,
			weaponId = number,
			weaponName = string,
			targetStance = number,    -- Stance enum
			targetStanceName = string,
		}
]]
function HitPacketUtils:ParsePacket(packetString)
	if type(packetString) ~= "string" then
		return nil
	end
	
	local buf = buffer.fromstring(packetString)
	
	local success, data = pcall(function()
		return Sera.Deserialize(SeraSchemas.HitPacket, buf)
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
		timestamp = data.Timestamp,
		origin = data.Origin,
		hitPosition = data.HitPosition,
		targetUserId = data.TargetUserId,
		hitPlayer = hitPlayer,
		hitPart = data.HitPart,
		hitPartName = HitPartNames[data.HitPart] or "Unknown",
		isHeadshot = data.HitPart == HitPartEnum.Head,
		weaponId = data.WeaponId,
		weaponName = WeaponIdNames[data.WeaponId] or "Unknown",
		targetStance = data.TargetStance,
		targetStanceName = StanceNames[data.TargetStance] or "Standing",
	}
end

--[[
	Parse a shotgun hit packet
	
	@param packetString string - Serialized buffer string
	@return table? - Parsed hit data (same as ParsePacket plus pellet info)
]]
function HitPacketUtils:ParseShotgunPacket(packetString)
	if type(packetString) ~= "string" then
		return nil
	end
	
	local buf = buffer.fromstring(packetString)
	
	local success, data = pcall(function()
		return Sera.Deserialize(SeraSchemas.ShotgunHitPacket, buf)
	end)
	
	if not success then
		return nil
	end
	
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
		timestamp = data.Timestamp,
		origin = data.Origin,
		hitPosition = data.HitPosition,
		targetUserId = data.TargetUserId,
		hitPlayer = hitPlayer,
		hitPart = data.HitPart,
		hitPartName = HitPartNames[data.HitPart] or "Unknown",
		isHeadshot = data.HitPart == HitPartEnum.Head,
		weaponId = data.WeaponId,
		weaponName = WeaponIdNames[data.WeaponId] or "Unknown",
		targetStance = data.TargetStance,
		targetStanceName = StanceNames[data.TargetStance] or "Standing",
		pelletHits = data.PelletHits,
		headshotPellets = data.HeadshotPellets,
	}
end

-- =============================================================================
-- UTILITY
-- =============================================================================

--[[
	Check if a packet is a shotgun packet (by size)
	
	@param packetString string - Serialized buffer string
	@return boolean - True if shotgun packet
]]
function HitPacketUtils:IsShotgunPacket(packetString)
	-- ShotgunHitPacket is 41 bytes, regular HitPacket is 39 bytes
	return type(packetString) == "string" and #packetString >= 41
end

--[[
	Get packet size information
	
	@return table - Size info for each packet type
]]
function HitPacketUtils:GetPacketSizes()
	return {
		HitPacket = 39,        -- 8 (timestamp) + 12 + 12 + 4 + 1 + 1 + 1
		ShotgunHitPacket = 41, -- 39 + 2 (pellet counts)
	}
end

--[[
	Validate packet structure without full parsing (quick check)
	
	@param packetString string - Serialized buffer string
	@return boolean - True if appears valid
]]
function HitPacketUtils:ValidatePacketStructure(packetString)
	if type(packetString) ~= "string" then
		return false
	end
	
	local len = #packetString
	return len == 39 or len == 41
end

return HitPacketUtils
