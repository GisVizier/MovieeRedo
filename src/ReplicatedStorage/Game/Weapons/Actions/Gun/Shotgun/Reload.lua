--[[
	Reload.lua (Shotgun)

	Client-side reload validation + state.
	Handles multi-stage reload animation and timing.
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
	local playAnim = weaponInstance.PlayAnimation
	if playAnim then
		playAnim("Start", 0.1, true)
	end

	if weaponInstance.ApplyState then
		weaponInstance.ApplyState(state)
	end

	local missing = math.max(clipSize - (state.CurrentAmmo or 0), 0)
	local shellsToLoad = math.min(missing, state.ReserveAmmo or 0)
	local totalReloadTime = config.reloadTime or 0
	local perShell = shellsToLoad > 0 and (totalReloadTime / shellsToLoad) or totalReloadTime

	local function loadOneShell()
		if state.ReserveAmmo <= 0 or state.CurrentAmmo >= clipSize then
			return
		end

		if playAnim then
			playAnim("Action", 0.05, true)
		end

		state.CurrentAmmo = (state.CurrentAmmo or 0) + 1
		state.ReserveAmmo = (state.ReserveAmmo or 0) - 1

		if weaponInstance.ApplyState then
			weaponInstance.ApplyState(state)
		end
	end

	for i = 1, shellsToLoad do
		task.delay(perShell * (i - 1), loadOneShell)
	end

	task.delay(totalReloadTime, function()
		state.IsReloading = false
		if playAnim then
			playAnim("End", 0.1, true)
		end
		if weaponInstance.ApplyState then
			weaponInstance.ApplyState(state)
		end
	end)

	return true
end

return Reload
