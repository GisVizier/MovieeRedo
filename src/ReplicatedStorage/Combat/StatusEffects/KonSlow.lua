--[[
	KonSlow.lua
	Status effect applied by Aki's Kon ability (both trap and projectile variants).
	
	Effects:
	- 30% movement speed reduction (via ExternalMoveMult attribute on player)
	- Disables sprinting (via KonSlow attribute on character, checked in MovementController)
	- Duration: 5 seconds
	
	Settings:
	- duration: number (required, default 5)
	- source: Player? (the Aki player who applied it)
]]

local Players = game:GetService("Players")

local KonSlow = {}
KonSlow.Id = "KonSlow"
KonSlow.DefaultTickRate = 0.5

-- Store original ExternalMoveMult per player so we can restore it
local SavedMoveMult = {}

--[[
	Called when the effect is first applied
	Sets KonSlow attribute on character (MovementController checks this to block sprint)
	and reduces movement speed by 30%
]]
function KonSlow:OnApply(target: Player, settings, combatResource)
	local character = target.Character
	if not character then return end
	
	-- KonSlow attribute is set by StatusEffectManager automatically
	-- Set visual attribute for client VFX (optional slow VFX)
	character:SetAttribute("KonSlowVFX", true)
	
	-- Save current ExternalMoveMult and apply 30% reduction (0.7 multiplier)
	local currentMult = target:GetAttribute("ExternalMoveMult")
	if typeof(currentMult) ~= "number" then
		currentMult = 1
	end
	SavedMoveMult[target.UserId] = currentMult
	
	-- Apply 0.7 multiplier (30% speed reduction)
	target:SetAttribute("ExternalMoveMult", math.clamp(currentMult * 0.7, 0.1, 1))
end

--[[
	Called every tick while the effect is active
	Ensures sprint stays disabled while effect is active
]]
function KonSlow:OnTick(target: Player, settings, deltaTime: number, combatResource)
	return true -- Continue effect
end

--[[
	Called when the effect is removed
	Restores movement speed and sprint capability
]]
function KonSlow:OnRemove(target: Player, settings, reason: string, combatResource)
	local character = target.Character
	if character then
		character:SetAttribute("KonSlowVFX", nil)
	end
	
	-- Restore ExternalMoveMult
	local saved = SavedMoveMult[target.UserId]
	if saved then
		target:SetAttribute("ExternalMoveMult", saved)
	else
		target:SetAttribute("ExternalMoveMult", 1)
	end
	SavedMoveMult[target.UserId] = nil
end

return KonSlow
