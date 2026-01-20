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
	local token = weaponInstance.BumpReloadToken and weaponInstance.BumpReloadToken() or 0

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Reload", 0.1, true)
	end

	if weaponInstance.ApplyState then
		weaponInstance.ApplyState(state)
	end

	local reloadTime = config.reloadTime or 0
	task.delay(reloadTime, function()
		if weaponInstance.GetReloadToken and weaponInstance.GetReloadToken() ~= token then
			return
		end

		local needed = clipSize - (state.CurrentAmmo or 0)
		local toReload = math.min(needed, state.ReserveAmmo or 0)

		state.CurrentAmmo = (state.CurrentAmmo or 0) + toReload
		state.ReserveAmmo = (state.ReserveAmmo or 0) - toReload
		state.IsReloading = false

		if weaponInstance.ApplyState then
			weaponInstance.ApplyState(state)
		end
	end)

	return true
end

return Reload
