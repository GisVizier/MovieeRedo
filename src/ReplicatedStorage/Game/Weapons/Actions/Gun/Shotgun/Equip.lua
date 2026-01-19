--[[
	Equip.lua (Shotgun)

	Client-side equip state toggle only.
]]

local Equip = {}

function Equip.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false, "InvalidInstance"
	end

	weaponInstance.State.Equipped = true
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.1, true)
	end
	return true
end

return Equip
