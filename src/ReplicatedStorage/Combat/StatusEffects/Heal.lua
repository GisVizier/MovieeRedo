--[[
	Heal.lua
	Status effect that heals over time
	
	Settings:
	- duration: number (required)
	- healPerTick: number (default 5)
	- tickRate: number? (default 0.25)
	- source: Player?
]]

local Heal = {}
Heal.Id = "Heal"
Heal.DefaultTickRate = 0.25

--[[
	Called when the effect is first applied
]]
function Heal:OnApply(target: Player, settings, combatResource)
	local character = target.Character
	if character then
		-- Set healing visual attribute for client VFX
		character:SetAttribute("HealVFX", true)
	end
end

--[[
	Called every tick while the effect is active
]]
function Heal:OnTick(target: Player, settings, deltaTime: number, combatResource)
	if not combatResource then
		return true -- Keep effect but skip heal
	end
	
	local healAmount = settings.healPerTick or 5
	
	combatResource:Heal(healAmount, {
		source = settings.source,
		healType = "HoT",
	})
	
	return true -- Continue effect
end

--[[
	Called when the effect is removed
]]
function Heal:OnRemove(target: Player, settings, reason: string, combatResource)
	local character = target.Character
	if character then
		character:SetAttribute("HealVFX", nil)
	end
end

return Heal
