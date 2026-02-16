--[[
	KillEffects/init.lua
	Registry and execution of kill effects
	
	Every weapon has a default kill effect. Players can customize
	kill effects per weapon in their WEAPON_DATA.
]]

local KillEffects = {}

-- Cache for loaded effect modules
local EffectModuleCache = {}

-- Default kill effect
KillEffects.DefaultEffect = "Ragdoll"

-- Service registry (set via Init)
KillEffects._registry = nil

--[[
	Initializes KillEffects with the service registry so that
	individual effect modules can access services (e.g. CharacterService).
	@param registry ServiceRegistry
]]
function KillEffects:Init(registry)
	self._registry = registry
end

--[[
	Loads a kill effect module by ID
	@param effectId string
	@return KillEffectDefinition?
]]
local function loadEffectModule(effectId: string)
	if EffectModuleCache[effectId] then
		return EffectModuleCache[effectId]
	end
	
	local moduleScript = script:FindFirstChild(effectId)
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
	Gets all available kill effect IDs
	@return {string}
]]
function KillEffects:GetAvailableEffects(): {string}
	local effects = {}
	for _, child in ipairs(script:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(effects, child.Name)
		end
	end
	return effects
end

--[[
	Gets a kill effect module by ID
	@param effectId string
	@return KillEffectDefinition?
]]
function KillEffects:GetEffect(effectId: string)
	return loadEffectModule(effectId)
end

--[[
	Executes a kill effect on a victim
	@param effectId string - Kill effect ID
	@param victim Player - The player who died
	@param killer Player? - The player who caused the death
	@param weaponId string? - The weapon used
	@param options table? - Additional options to pass to the effect
]]
function KillEffects:Execute(effectId: string, victim: Player, killer: Player?, weaponId: string?, options: {[string]: any}?)
	local effectModule = loadEffectModule(effectId)
	
	if not effectModule then
		-- Fall back to default
		effectModule = loadEffectModule(KillEffects.DefaultEffect)
		if not effectModule then
			return
		end
	end

	-- Build context so effects can access services
	local context = {
		registry = self._registry,
	}
	
	if effectModule.Execute then
		local ok, err = pcall(function()
			effectModule:Execute(victim, killer, weaponId, options, context)
		end)
		
		if not ok then
		end
	else
	end
end

--[[
	Gets the kill effect for a weapon, accounting for player customization
	@param weaponId string - The weapon ID
	@param weaponConfig table? - The weapon configuration (for default effect)
	@param playerWeaponData table? - Player's weapon customization data
	@return string - The kill effect ID to use
]]
function KillEffects:GetWeaponKillEffect(weaponId: string, weaponConfig: {[string]: any}?, playerWeaponData: {[string]: any}?): string
	-- Check player customization first
	if playerWeaponData and playerWeaponData.killEffect then
		return playerWeaponData.killEffect
	end
	
	-- Check weapon default
	if weaponConfig and weaponConfig.defaultKillEffect then
		return weaponConfig.defaultKillEffect
	end
	
	-- Global default
	return KillEffects.DefaultEffect
end

return KillEffects
