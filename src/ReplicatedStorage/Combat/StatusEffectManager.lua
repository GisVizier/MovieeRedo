--[[
	StatusEffectManager.lua
	Manages status effects for a single player with tick execution
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage:WaitForChild("CoreUI"):WaitForChild("Signal"))
local CombatConfig = require(script.Parent:WaitForChild("CombatConfig"))

local StatusEffectManager = {}
StatusEffectManager.__index = StatusEffectManager

-- Cache for loaded effect modules
local EffectModuleCache = {}

--[[
	Loads a status effect module by ID
	@param effectId string
	@return StatusEffectModule?
]]
local function loadEffectModule(effectId: string)
	if EffectModuleCache[effectId] then
		return EffectModuleCache[effectId]
	end
	
	local effectsFolder = script.Parent:FindFirstChild("StatusEffects")
	if not effectsFolder then
		return nil
	end
	
	local moduleScript = effectsFolder:FindFirstChild(effectId)
	if not moduleScript then
		return nil
	end
	
	local ok, effectModule = pcall(require, moduleScript)
	if not ok then
		return nil
	end
	
	EffectModuleCache[effectId] = effectModule
	return effectModule
end

--[[
	Creates a new StatusEffectManager for a player
	@param player Player
	@param combatResource CombatResource?
	@return StatusEffectManager
]]
function StatusEffectManager.new(player: Player, combatResource: any?)
	local self = setmetatable({}, StatusEffectManager)
	
	self._player = player
	self._combatResource = combatResource
	self._activeEffects = {} -- effectId -> ActiveStatusEffect
	
	-- Events
	self.OnEffectApplied = Signal.new()
	self.OnEffectRefreshed = Signal.new()
	self.OnEffectRemoved = Signal.new()
	self.OnEffectTick = Signal.new()
	
	return self
end

--[[
	Sets the combat resource (for damage/heal effects)
	@param combatResource CombatResource
]]
function StatusEffectManager:SetCombatResource(combatResource: any)
	self._combatResource = combatResource
end

--[[
	Applies a status effect with the given settings
	If the effect already exists, refreshes its duration
	@param effectId string - ID of the effect (must match module name)
	@param settings StatusEffectSettings - Effect configuration
]]
function StatusEffectManager:Apply(effectId: string, settings: {
	duration: number,
	tickRate: number?,
	source: Player?,
	[string]: any,
})
	local effectModule = loadEffectModule(effectId)
	if not effectModule then
		return
	end
	
	local existing = self._activeEffects[effectId]
	local now = os.clock()
	
	if existing then
		-- Refresh duration (infinite stacking via reset)
		existing.settings = settings
		existing.remainingDuration = settings.duration
		existing.startTime = now
		
		self.OnEffectRefreshed:fire(effectId, settings.duration)
		return
	end
	
	-- Create new effect instance
	local activeEffect = {
		effectId = effectId,
		settings = settings,
		startTime = now,
		remainingDuration = settings.duration,
		lastTickTime = now,
		module = effectModule,
	}
	
	self._activeEffects[effectId] = activeEffect
	
	-- Set attribute on character for movement/other systems to check
	local character = self._player.Character
	if character then
		character:SetAttribute(effectId, true)
	end
	
	-- Call OnApply if module has it
	if effectModule.OnApply then
		local ok, err = pcall(function()
			effectModule:OnApply(self._player, settings, self._combatResource)
		end)
		if not ok then
		end
	end
	
	self.OnEffectApplied:fire(effectId, settings)
end

--[[
	Removes a status effect
	@param effectId string
	@param reason string? - Why it was removed (e.g., "expired", "cleanse", "death")
]]
function StatusEffectManager:Remove(effectId: string, reason: string?)
	local activeEffect = self._activeEffects[effectId]
	if not activeEffect then
		return
	end
	
	reason = reason or "manual"
	
	-- Clear attribute
	local character = self._player.Character
	if character then
		character:SetAttribute(effectId, nil)
	end
	
	-- Call OnRemove if module has it
	if activeEffect.module and activeEffect.module.OnRemove then
		local ok, err = pcall(function()
			activeEffect.module:OnRemove(self._player, activeEffect.settings, reason, self._combatResource)
		end)
		if not ok then
		end
	end
	
	self._activeEffects[effectId] = nil
	self.OnEffectRemoved:fire(effectId, reason)
end

--[[
	Removes all active effects
	@param reason string?
]]
function StatusEffectManager:RemoveAll(reason: string?)
	reason = reason or "clear"
	
	local effectIds = {}
	for effectId in pairs(self._activeEffects) do
		table.insert(effectIds, effectId)
	end
	
	for _, effectId in ipairs(effectIds) do
		self:Remove(effectId, reason)
	end
end

--[[
	Checks if an effect is active
	@param effectId string
	@return boolean
]]
function StatusEffectManager:Has(effectId: string): boolean
	return self._activeEffects[effectId] ~= nil
end

--[[
	Gets remaining duration of an effect
	@param effectId string
	@return number? - Remaining seconds, or nil if not active
]]
function StatusEffectManager:GetRemaining(effectId: string): number?
	local activeEffect = self._activeEffects[effectId]
	if not activeEffect then
		return nil
	end
	return activeEffect.remainingDuration
end

--[[
	Gets all active effect IDs with their remaining durations
	@return {[string]: number}
]]
function StatusEffectManager:GetActiveEffects(): {[string]: number}
	local result = {}
	for effectId, activeEffect in pairs(self._activeEffects) do
		result[effectId] = activeEffect.remainingDuration
	end
	return result
end

--[[
	Ticks all active effects
	Call this from the server heartbeat loop
	@param deltaTime number
]]
function StatusEffectManager:Tick(deltaTime: number)
	local now = os.clock()
	local toRemove = {}
	
	for effectId, activeEffect in pairs(self._activeEffects) do
		-- Update remaining duration
		activeEffect.remainingDuration = activeEffect.remainingDuration - deltaTime
		
		-- Check if expired
		if activeEffect.remainingDuration <= 0 then
			table.insert(toRemove, effectId)
		else
			-- Process tick
			local tickRate = activeEffect.settings.tickRate 
				or (activeEffect.module and activeEffect.module.DefaultTickRate)
				or CombatConfig.StatusEffects.TickRate
			
			local timeSinceLastTick = now - activeEffect.lastTickTime
			
			if timeSinceLastTick >= tickRate then
				activeEffect.lastTickTime = now
				
				-- Call OnTick if module has it
				if activeEffect.module and activeEffect.module.OnTick then
					local ok, result = pcall(function()
						return activeEffect.module:OnTick(
							self._player, 
							activeEffect.settings, 
							timeSinceLastTick,
							self._combatResource
						)
					end)
					
					if not ok then
					elseif result == false then
						-- Module returned false, remove effect early
						table.insert(toRemove, effectId)
					end
				end
				
				self.OnEffectTick:fire(effectId, activeEffect.remainingDuration)
			end
		end
	end
	
	-- Remove expired/cancelled effects
	for _, effectId in ipairs(toRemove) do
		self:Remove(effectId, "expired")
	end
end

--[[
	Notifies the manager that the player took damage
	Used by effects like Frozen that break on damage
	@param damage number
	@param source Player?
]]
function StatusEffectManager:NotifyDamage(damage: number, source: Player?)
	for effectId, activeEffect in pairs(self._activeEffects) do
		if activeEffect.settings.breakOnDamage then
			activeEffect.settings._damageTaken = true
		end
	end
end

--[[
	Gets the player this manager belongs to
	@return Player
]]
function StatusEffectManager:GetPlayer(): Player
	return self._player
end

--[[
	Destroys the manager and removes all effects
]]
function StatusEffectManager:Destroy()
	self:RemoveAll("destroy")
	
	self.OnEffectApplied:destroy()
	self.OnEffectRefreshed:destroy()
	self.OnEffectRemoved:destroy()
	self.OnEffectTick:destroy()
end

return StatusEffectManager
