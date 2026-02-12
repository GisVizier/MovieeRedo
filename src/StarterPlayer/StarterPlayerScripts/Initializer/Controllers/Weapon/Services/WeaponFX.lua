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
	
	-- Resolve: weapon tracer > player cosmetic > default
	local resolvedTracerId = Tracers:Resolve(tracerId, playerTracerId)
	
	return Tracers:Fire(resolvedTracerId, origin, gunModel)
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
	Legacy: Renders bullet tracer (instant, for hitscan)
	@param hitData table
]]
function WeaponFX:RenderBulletTracer(hitData)
	if not hitData then return end
	if not hitData.origin or not hitData.hitPosition then return end
	
	-- For hitscan, fire tracer and immediately complete it
	local handle = self:FireTracer(hitData.weaponId, hitData.origin, hitData.gunModel)
	if not handle then return end
	
	-- Move to hit position
	handle.attachment.WorldPosition = hitData.hitPosition
	
	-- Determine hit type (works for players and dummies)
	local hitCharacter = findCharacterFromPart(hitData.hitPart)

	-- Call world hit effects only - player hit effects are triggered by
	-- CombatController when damage is actually confirmed by the server
	if not hitCharacter then
		Tracers:HitWorld(handle, hitData.hitPosition, hitData.hitNormal or Vector3.yAxis, hitData.hitPart)
	end
	
	-- Cleanup after short delay
	task.delay(0.5, function()
		self:CleanupTracer(handle)
	end)
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
