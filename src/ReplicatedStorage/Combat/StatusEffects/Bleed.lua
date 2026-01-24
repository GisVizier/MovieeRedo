--[[
	Bleed.lua
	Status effect that forces walk speed (disables sprinting)
	
	Settings:
	- duration: number (required)
	- tickRate: number? (optional, for any DoT component)
	- damagePerTick: number? (optional, if bleed also damages)
	- source: Player?
]]

local Bleed = {}
Bleed.Id = "Bleed"
Bleed.DefaultTickRate = 1.0

--[[
	Called when the effect is first applied
	Sets Bleed attribute on character - MovementController checks this to block sprint
]]
function Bleed:OnApply(target: Player, settings, combatResource)
	local character = target.Character
	if character then
		-- Bleed attribute is set by StatusEffectManager
		-- Set visual attribute for client
		character:SetAttribute("BleedVFX", true)
	end
end

--[[
	Called every tick while the effect is active
	Optionally applies DoT damage if damagePerTick is set
]]
function Bleed:OnTick(target: Player, settings, deltaTime: number, combatResource)
	-- Optional DoT component
	if settings.damagePerTick and combatResource then
		combatResource:TakeDamage(settings.damagePerTick, {
			source = settings.source,
			isTrueDamage = false,
			damageType = "Bleed",
		})
	end
	
	return true -- Continue effect
end

--[[
	Called when the effect is removed
]]
function Bleed:OnRemove(target: Player, settings, reason: string, combatResource)
	local character = target.Character
	if character then
		character:SetAttribute("BleedVFX", nil)
	end
end

return Bleed
