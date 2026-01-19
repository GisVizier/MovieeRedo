--[[
	Unequip.lua (Shotgun)

	Client-side unequip state toggle only.
]]

local Unequip = {}

function Unequip.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false, "InvalidInstance"
	end

	weaponInstance.State.Equipped = false
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Unequip", 0.1, true)
	end
	return true
end

return Unequip
