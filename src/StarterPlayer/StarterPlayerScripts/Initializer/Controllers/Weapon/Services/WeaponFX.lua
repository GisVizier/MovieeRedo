--[[
	WeaponFX.lua
	Handles weapon visual effects including tracers, hitmarkers, and damage indicators
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tracers = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Tracers"))

local WeaponFX = {}
WeaponFX.__index = WeaponFX

--[[
	Finds the character model from a hit part
	Works for players, dummies, and custom "bean" characters
	@param hitPart BasePart
	@return Model?
]]
local function findCharacterFromPart(hitPart: BasePart): Model?
	if not hitPart then return nil end
	
	-- Walk up ancestors looking for a valid character
	local current = hitPart.Parent
	while current and current ~= workspace do
		if current:IsA("Model") then
			-- Check for Humanoid (players and standard dummies)
			if current:FindFirstChildOfClass("Humanoid") then
				return current
			end
			
			-- Check for "bean" character structure (Rig, Collider, Root)
			if current:FindFirstChild("Rig") or current:FindFirstChild("Collider") then
				return current
			end
			
			-- Check for dummy tag
			if CollectionService:HasTag(current, "Dummy") or CollectionService:HasTag(current, "Target") then
				return current
			end
			
			-- Check if parent is a Collider folder (part is inside Collider)
			if current.Name == "Collider" and current.Parent and current.Parent:IsA("Model") then
				return current.Parent
			end
		end
		
		current = current.Parent
	end
	
	return nil
end

local function getTracerSettings(weaponConfig)
	local settings = {
		trailScale = 1,
		muzzleScale = nil,
	}

	if type(weaponConfig) ~= "table" then
		return settings
	end

	local tracerConfig = weaponConfig.tracer
	if type(tracerConfig) == "table" then
		if type(tracerConfig.trailScale) == "number" and tracerConfig.trailScale > 0 then
			settings.trailScale = tracerConfig.trailScale
		end
		if type(tracerConfig.muzzleScale) == "number" and tracerConfig.muzzleScale > 0 then
			settings.muzzleScale = tracerConfig.muzzleScale
		end
	end

	-- Backward compatibility for legacy flat fields.
	if type(weaponConfig.tracerScale) == "number" and weaponConfig.tracerScale > 0 then
		settings.trailScale = weaponConfig.tracerScale
	end
	if type(weaponConfig.muzzleScale) == "number" and weaponConfig.muzzleScale > 0 then
		settings.muzzleScale = weaponConfig.muzzleScale
	end

	return settings
end

function WeaponFX.new(loadoutConfig, logService)
	local self = setmetatable({}, WeaponFX)
	self._loadoutConfig = loadoutConfig
	self._logService = logService
	
	-- Initialize tracers
	Tracers:Init()
	
	return self
end

--[[
	Fires a tracer and returns the handle for projectile to animate
	@param weaponId string
	@param origin Vector3
	@param gunModel Model?
	@param playerTracerId string? - Player's equipped tracer cosmetic
	@return TracerHandle?
]]
function WeaponFX:FireTracer(weaponId: string, origin: Vector3, gunModel: Model?, playerTracerId: string?)
	local weaponConfig = self._loadoutConfig.getWeapon(weaponId)
	local tracerId = weaponConfig and weaponConfig.tracerId or nil
	local tracerSettings = getTracerSettings(weaponConfig)
	
	-- Resolve: weapon tracer > player cosmetic > default
	local resolvedTracerId = Tracers:Resolve(tracerId, playerTracerId)
	
	return Tracers:Fire(resolvedTracerId, origin, gunModel, true, tracerSettings)
end

--[[
	Called when tracer hits a player
]]
function WeaponFX:TracerHitPlayer(handle, hitPosition: Vector3, hitPart: BasePart, targetCharacter: Model)
	Tracers:HitPlayer(handle, hitPosition, hitPart, targetCharacter)
end

--[[
	Called when tracer hits world
]]
function WeaponFX:TracerHitWorld(handle, hitPosition: Vector3, hitNormal: Vector3, hitPart: BasePart)
	Tracers:HitWorld(handle, hitPosition, hitNormal, hitPart)
end

--[[
	Cleanup a tracer handle
]]
function WeaponFX:CleanupTracer(handle)
	if handle and handle.cleanup then
		handle.cleanup()
	end
end

--[[
	Renders hitscan bullet effects (muzzle flash + world impact).
	Hitscan is instant so we skip trail FX entirely — no pooled attachment needed.
	@param hitData table
]]
function WeaponFX:RenderBulletTracer(hitData)
	if not hitData then return end
	if not hitData.origin or not hitData.hitPosition then return end

	local weaponConfig = self._loadoutConfig.getWeapon(hitData.weaponId)
	local tracerId = weaponConfig and weaponConfig.tracerId or nil
	local tracerSettings = getTracerSettings(weaponConfig)
	local resolvedId = Tracers:Resolve(tracerId, nil)
	local tracerModule = Tracers:Get(resolvedId)
	if not tracerModule then return end

	-- Muzzle flash on the gun model
	if tracerModule.Muzzle and hitData.gunModel then
		local muzzleAttachment = nil
		if typeof(hitData.muzzleAttachment) == "Instance" and hitData.muzzleAttachment:IsA("Attachment") then
			muzzleAttachment = hitData.muzzleAttachment
		else
			muzzleAttachment = Tracers:FindMuzzleAttachment(hitData.gunModel)
		end
		if muzzleAttachment then
			tracerModule:Muzzle(hitData.origin, hitData.gunModel, nil, Tracers, muzzleAttachment, tracerSettings)
		end
	end

	-- World impact FX (only when we didn't hit a character)
	local hitCharacter = findCharacterFromPart(hitData.hitPart)
	if not hitCharacter and tracerModule.HitWorld then
		tracerModule:HitWorld(hitData.hitPosition, hitData.hitNormal or Vector3.yAxis, hitData.hitPart, nil, Tracers)
	end
end

--[[
	Shows hitmarker
]]
function WeaponFX:ShowHitmarker(hitData)
	self._logService:Debug("WEAPON", "Hitmarker", { damage = hitData.damage, headshot = hitData.isHeadshot })
end

--[[
	Shows damage indicator
]]
function WeaponFX:ShowDamageIndicator(hitData)
	self._logService:Debug("WEAPON", "Taking damage", { damage = hitData.damage })
end

--[[
	Gets the Tracers system
]]
function WeaponFX:GetTracers()
	return Tracers
end

--[[
	Cleanup
]]
function WeaponFX:Destroy()
	Tracers:Cleanup()
end

return WeaponFX
