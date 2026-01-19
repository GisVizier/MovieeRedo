--[[
	Inspect.lua (Shotgun)

	Client-side inspect gating only.
	No viewmodel, VFX, or networking here.
]]

local Inspect = {}

function Inspect.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	if state.IsReloading or state.IsAttacking then
		return false, "Busy"
	end

	local track = weaponInstance.Animator and weaponInstance.Animator:GetTrack("Inspect")
	if track then
		track:Play(0.1)
	end

	return true
end

return Inspect
