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
	local track = weaponInstance.Animator and weaponInstance.Animator:GetTrack("Equip")
	if track then
		track:Play(0.1)
	end
	return true
end

return Equip
