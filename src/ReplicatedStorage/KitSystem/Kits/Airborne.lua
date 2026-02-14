--[[
	Airborne Server Kit
	
	Charge System:
	- 2 discrete charges (bars)
	- Ability requires 1 FULL charge to use (consumes from stored charges)
	- Float drains the "active" bar (partial); when depleted, float stops
	- Regen starts 0.35s after last charge use, fills partial until it becomes a stored charge
	- When last stored charge is used via ability → cooldown → restore 1 charge
	
	State Model:
	- charges: stored FULL bars (0, 1, or 2) - these are reserved, not actively draining
	- partial: the bar currently being drained (float) or filled (regen) - 0.0 to 1.0
	- When full: charges=2, partial=0
	
	Display:
	- Bar 1 = charges >= 1 ? 100% : partial
	- Bar 2 = charges >= 2 ? 100% : (charges == 1 ? partial : 0)
]]

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)

local Kit = {}
Kit.__index = Kit

-- Constants
local MAX_CHARGES = 2
local REGEN_TIME = 5           -- Seconds to fill 1 bar (0% → 100%)
local REGEN_RATE = 1 / REGEN_TIME
local REGEN_DELAY = 1.5        -- Seconds to wait before regen starts after ability use

function Kit.new(ctx)
	local self = setmetatable({}, Kit)
	
	self._ctx = ctx
	self._heartbeat = nil
	
	-- Charge state
	self._chargeState = {
		charges = MAX_CHARGES,  -- Stored full bars (0, 1, or 2)
		partial = 0,            -- Active bar being filled (0.0 to 1.0)
		regenDelayUntil = 0,    -- Timestamp when regen can start
	}
	
	return self
end

function Kit:SetCharacter(character)
	self._ctx.character = character
end

function Kit:Destroy()
	if self._heartbeat then
		self._heartbeat:Disconnect()
		self._heartbeat = nil
	end
	
	local player = self._ctx.player
	if player then
		player:SetAttribute("AirborneCharges", nil)
	end
end

function Kit:OnEquipped()
	local player = self._ctx.player
	
	-- Initialize at FULL capacity: 2 stored charges, no partial
	self._chargeState = {
		charges = MAX_CHARGES,
		partial = 0,
		regenDelayUntil = 0,
	}
	
	self:_syncToClient()
	
	-- Start heartbeat for regen
	self._heartbeat = RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end)
end

function Kit:OnUnequipped()
	if self._heartbeat then
		self._heartbeat:Disconnect()
		self._heartbeat = nil
	end
	
	local player = self._ctx.player
	if player then
		player:SetAttribute("AirborneCharges", nil)
	end
end

--[[
	Resets kit state when entering training ground from lobby.
]]
function Kit:ResetForTraining()
	self._chargeState = {
		charges = MAX_CHARGES,
		partial = 0,
		regenDelayUntil = 0,
	}
	self:_syncToClient()
end

--[[
	Tick regen logic (no float drain - float is infinite)
]]
function Kit:_tick(dt)
	local state = self._chargeState
	local changed = false
	local now = os.clock()
	
	-- REGEN when we have room AND delay has passed
	local totalCharge = state.charges + state.partial
	
	if totalCharge < MAX_CHARGES and now >= state.regenDelayUntil then
		state.partial = state.partial + (REGEN_RATE * dt)
		changed = true
		
		if state.partial >= 1.0 then
			-- Bar filled - convert to stored charge
			state.partial = 0
			state.charges = state.charges + 1
			
			-- Cap at max
			if state.charges >= MAX_CHARGES then
				state.charges = MAX_CHARGES
				state.partial = 0
			end
		end
	end
	
	if changed then
		self:_syncToClient()
	end
end

--[[
	Check if player has at least 1 stored full charge for ability use
]]
function Kit:_hasFullCharge(): boolean
	return self._chargeState.charges >= 1
end

--[[
	Check if player has any charge (for floating)
]]
function Kit:_hasAnyCharge(): boolean
	return self._chargeState.charges > 0 or self._chargeState.partial > 0
end

--[[
	Consume 1 stored charge for ability use
	Returns: success (boolean), triggeredCooldown (boolean)
]]
function Kit:_consumeCharge(): (boolean, boolean)
	local state = self._chargeState
	
	-- Need at least 1 stored full bar
	if state.charges < 1 then
		return false, false
	end
	
	-- Consume one stored charge
	state.charges = state.charges - 1
	
	-- Set regen delay
	state.regenDelayUntil = os.clock() + REGEN_DELAY
	
	-- Cooldown triggers when last STORED charge is used (charges hits 0)
	local usedLastBar = (state.charges == 0)
	
	self:_syncToClient()
	
	return true, usedLastBar
end

--[[
	Restore 1 charge (called after cooldown ends)
]]
function Kit:_restoreCharge()
	local state = self._chargeState
	
	if state.charges < MAX_CHARGES then
		state.charges = state.charges + 1
	end
	
	self:_syncToClient()
end

--[[
	Trigger cooldown when last charge is used
	Empties everything, starts cooldown, restores 1 charge after
]]
function Kit:_triggerEmptyCooldown()
	local player = self._ctx.player
	local service = self._ctx.service
	
	if not player or not service then return end
	
	-- Empty everything to zero
	self._chargeState.charges = 0
	self._chargeState.partial = 0
	
	-- Start ability cooldown
	service:StartCooldown(player)
	
	-- Get cooldown duration
	local cooldown = KitConfig.getAbilityCooldown("Airborne") or 5
	
	-- BLOCK regen until cooldown ends
	self._chargeState.regenDelayUntil = os.clock() + cooldown
	self:_syncToClient()
	
	-- Restore 1 FULL charge after cooldown (then normal regen fills second bar)
	local kitRef = self
	local playerRef = player
	
	task.delay(cooldown, function()
		if kitRef and kitRef._ctx and kitRef._ctx.player == playerRef then
			kitRef:_restoreCharge()
		end
	end)
end

--[[
	Sync charge state to client via attribute
]]
function Kit:_syncToClient()
	local player = self._ctx.player
	if not player then return end
	
	local state = self._chargeState
	local data = {
		charges = state.charges,
		partial = state.partial,
		maxCharges = MAX_CHARGES,
	}
	
	player:SetAttribute("AirborneCharges", HttpService:JSONEncode(data))
end

--[[
	Handle ability activation
	
	clientData can contain:
	- useAbility: boolean - Consume a stored charge for ability
]]
function Kit:OnAbility(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	
	local player = self._ctx.player
	local service = self._ctx.service
	
	clientData = clientData or {}
	
	-- Handle ability use (Cloudskip/Updraft)
	if clientData.useAbility then
		local success, wasLastCharge = self:_consumeCharge()
		
		if not success then
			-- Not enough charge - reject
			return false
		end
		
		-- If this was the last charge, trigger cooldown
		if wasLastCharge then
			self:_triggerEmptyCooldown()
		end
		
		-- End the ability
		return true
	end
	
	return false
end

function Kit:OnUltimate(inputState, clientData)
	return false
end

return Kit
