--[[
	Burn.lua
	Status effect that deals damage over time
	
	Settings:
	- duration: number (required)
	- damagePerTick: number (default 10)
	- tickRate: number? (default 0.5)
	- source: Player?
]]

local Burn = {}
Burn.Id = "Burn"
Burn.DefaultTickRate = 0.5

--[[
	Called when the effect is first applied
]]
function Burn:OnApply(target: Player, settings, combatResource)
	-- Could add VFX start here
	local character = target.Character
	if character then
		-- Set burning visual attribute for client VFX
		character:SetAttribute("BurnVFX", true)
	end
end

--[[
	Called every tick while the effect is active
	Return false to remove the effect early
]]
function Burn:OnTick(target: Player, settings, deltaTime: number, combatResource)
	if not combatResource then
		return true -- Keep effect but skip damage
	end
	
	local damage = settings.damagePerTick or 10
	
	combatResource:TakeDamage(damage, {
		source = settings.source,
		isTrueDamage = false,
		damageType = "Burn",
	})
	
	return true -- Continue effect
end

--[[
	Called when the effect is removed
]]
function Burn:OnRemove(target: Player, settings, reason: string, combatResource)
	local character = target.Character
	if character then
		character:SetAttribute("BurnVFX", nil)
	end
end

return Burn
