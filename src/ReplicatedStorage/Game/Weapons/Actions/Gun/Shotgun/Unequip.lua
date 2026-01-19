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
	local track = weaponInstance.Animator and weaponInstance.Animator:GetTrack("Unequip")
	if track then
		track:Play(0.1)
	end
	return true
end

return Unequip
