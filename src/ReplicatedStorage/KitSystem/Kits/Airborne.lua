--[[
	Airborne Kit - Server Module
	
	The server kit handles:
	- Passive abilities (Air Cushion - slow fall)
	- Cooldown management via service:StartCooldown()
	- Returning true to end skill and re-equip weapon
	
	Physics and animations are handled CLIENT-SIDE for responsiveness.
]]

local RunService = game:GetService("RunService")

local Kit = {}
Kit.__index = Kit

-- =============================================================================
-- CONFIG
-- =============================================================================
local AIR_CUSHION_MAX_FALL = -20  -- Max fall speed (normally ~-50)

-- =============================================================================
-- CONSTRUCTOR
-- =============================================================================
function Kit.new(ctx)
	local self = setmetatable({}, Kit)
	self._ctx = ctx
	self._passiveConnection = nil
	return self
end

function Kit:SetCharacter(character)
	self._ctx.character = character
	self:_setupPassive()
end

function Kit:Destroy()
	self:_cleanupPassive()
end

function Kit:OnEquipped()
	self:_setupPassive()
end

function Kit:OnUnequipped()
	self:_cleanupPassive()
end

-- =============================================================================
-- PASSIVE: AIR CUSHION
-- Slows fall speed, letting you float down and land softly.
-- =============================================================================
function Kit:_setupPassive()
	self:_cleanupPassive()
	
	local character = self._ctx.character
	if not character then return end
	
	local primaryPart = character.PrimaryPart
	if not primaryPart then return end
	
	self._passiveConnection = RunService.Heartbeat:Connect(function()
		if not primaryPart or not primaryPart.Parent then
			self:_cleanupPassive()
			return
		end
		
		local vel = primaryPart.AssemblyLinearVelocity
		if vel.Y < AIR_CUSHION_MAX_FALL then
			primaryPart.AssemblyLinearVelocity = Vector3.new(vel.X, AIR_CUSHION_MAX_FALL, vel.Z)
		end
	end)
end

function Kit:_cleanupPassive()
	if self._passiveConnection then
		self._passiveConnection:Disconnect()
		self._passiveConnection = nil
	end
end

-- =============================================================================
-- ABILITY: CLOUDSKIP
-- Wind dash - physics applied on CLIENT for responsiveness.
-- Server validates, starts cooldown, and broadcasts VFX to other players.
-- =============================================================================
function Kit:OnAbility(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	
	local player = self._ctx.player
	local service = self._ctx.service
	local character = self._ctx.character
	local hrp = character and character.PrimaryPart
	
	-- Start cooldown (uses KitConfig.Airborne.Ability.Cooldown)
	service:StartCooldown(player)
	
	-- Broadcast VFX to OTHER players (client already plays their own via "User" function)
	-- Uses "Observer" function for spectator-specific effects
	if hrp then
		service:BroadcastVFX(player, "Others", "Cloudskip", {
			position = hrp.Position,
			direction = clientData and clientData.direction or Vector3.new(0, 0, -1),
		}, "Observer")
	end
	
	-- Return true = skill ends, weapon re-equips
	return true
end

-- =============================================================================
-- ULTIMATE: HURRICANE
-- AOE vortex that pulls enemies in and launches them.
-- TODO: Implement server-side damage/pull logic
-- =============================================================================
function Kit:OnUltimate(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	
	local player = self._ctx.player
	local service = self._ctx.service
	local character = self._ctx.character
	local hrp = character and character.PrimaryPart
	
	-- Broadcast VFX to OTHER players (client already plays their own via "User" function)
	-- Uses "Observer" function for spectator-specific effects
	if hrp then
		service:BroadcastVFX(player, "Others", "Hurricane", {
			position = hrp.Position,
		}, "Observer")
	end
	
	-- TODO: Hurricane server logic
	-- - Spawn damage zone
	-- - Pull nearby enemies
	-- - Launch after duration
	
	return true
end

return Kit
