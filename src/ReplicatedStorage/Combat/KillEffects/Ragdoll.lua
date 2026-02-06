--[[
	Ragdoll.lua
	Default kill effect - ragdoll physics on the victim
	
	The actual ragdoll is triggered directly by CombatService._handleDeath
	via CharacterService:Ragdoll(). This module exists as a registered
	KillEffect entry so the system can identify it by ID.
]]

local Ragdoll = {}
Ragdoll.Id = "Ragdoll"
Ragdoll.Name = "Ragdoll"

--[[
	Execute is intentionally a no-op for the Ragdoll effect.
	CombatService._handleDeath handles ragdoll triggering directly
	through CharacterService:Ragdoll() for proper server authority.
]]
function Ragdoll:Execute(_victim: Player, _killer: Player?, _weaponId: string?, _options: {[string]: any}?)
	-- No-op: CombatService handles ragdoll death directly via CharacterService
end

return Ragdoll
