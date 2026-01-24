--[[
	Ragdoll.lua
	Default kill effect - triggers the ragdoll system on the victim
]]

local Players = game:GetService("Players")

local Ragdoll = {}
Ragdoll.Id = "Ragdoll"
Ragdoll.Name = "Ragdoll"

--[[
	Executes the ragdoll kill effect
	@param victim Player
	@param killer Player?
	@param weaponId string?
	@param options table?
]]
function Ragdoll:Execute(victim: Player, killer: Player?, weaponId: string?, options: {[string]: any}?)
	-- The actual ragdoll is handled by CharacterService on the server
	-- This module just needs to signal the intent
	
	local character = victim.Character
	if not character then
		return
	end
	
	-- Set attribute to trigger ragdoll
	-- CharacterService listens for this and handles the actual ragdoll physics
	character:SetAttribute("KillEffect", "Ragdoll")
	character:SetAttribute("KillerId", killer and killer.UserId or nil)
	character:SetAttribute("KillWeaponId", weaponId)
	
	-- Apply fling options if provided
	if options then
		if options.flingDirection then
			character:SetAttribute("KillFlingDirection", options.flingDirection)
		end
		if options.flingStrength then
			character:SetAttribute("KillFlingStrength", options.flingStrength)
		end
	end
end

return Ragdoll
