--[[
	Reload.lua (Shotgun)

	Client-side reload validation + state.
	No viewmodel, VFX, or networking here.
]]

local Reload = {}

function Reload.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config

	if state.IsReloading then
		return false, "Reloading"
	end

	local clipSize = config.clipSize or 0
	if (state.CurrentAmmo or 0) >= clipSize then
		return false, "Full"
	end

	if (state.ReserveAmmo or 0) <= 0 then
		return false, "NoReserve"
	end

	state.IsReloading = true
	state.ReloadStartTime = os.clock()

	local track = weaponInstance.Animator and weaponInstance.Animator:GetTrack("Reload")
	if track then
		track:Play(0.1)
	end

	return true
end

return Reload
