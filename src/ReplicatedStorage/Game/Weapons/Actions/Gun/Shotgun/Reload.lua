--[[
	Reload.lua (Shotgun)

	Client-side reload validation + state.
	Handles multi-stage reload animation and timing.
]]

local Reload = {}

local function getReloading(weaponInstance, state)
	if weaponInstance.GetIsReloading then
		return weaponInstance.GetIsReloading()
	end
	return state.IsReloading
end

local function setReloading(weaponInstance, state, value)
	if weaponInstance.SetIsReloading then
		weaponInstance.SetIsReloading(value)
	end
	state.IsReloading = value
end

local function getToken(weaponInstance, state)
	if weaponInstance.GetReloadToken then
		return weaponInstance.GetReloadToken()
	end
	return state.ReloadToken
end

local function bumpToken(weaponInstance, state)
	if weaponInstance.GetReloadToken and weaponInstance.SetReloadToken then
		local token = (weaponInstance.GetReloadToken() or 0) + 1
		weaponInstance.SetReloadToken(token)
		return token
	end
	state.ReloadToken = (state.ReloadToken or 0) + 1
	return state.ReloadToken
end

function Reload.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config

	if getReloading(weaponInstance, state) then
		return false, "Reloading"
	end

	local clipSize = config.clipSize or 0
	if (state.CurrentAmmo or 0) >= clipSize then
		return false, "Full"
	end

	if (state.ReserveAmmo or 0) <= 0 then
		return false, "NoReserve"
	end

	setReloading(weaponInstance, state, true)
	state.ReloadStartTime = os.clock()
	local reloadToken = bumpToken(weaponInstance, state)
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
		if not getReloading(weaponInstance, state) or getToken(weaponInstance, state) ~= reloadToken then
			return
		end
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
		if not getReloading(weaponInstance, state) or getToken(weaponInstance, state) ~= reloadToken then
			return
		end
		setReloading(weaponInstance, state, false)
		if playAnim then
			playAnim("End", 0.1, true)
		end
		if weaponInstance.ApplyState then
			weaponInstance.ApplyState(state)
		end
	end)

	return true
end

function Reload.Interrupt(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	if not getReloading(weaponInstance, state) then
		return false, "NotReloading"
	end

	setReloading(weaponInstance, state, false)
	bumpToken(weaponInstance, state)

	local playAnim = weaponInstance.PlayAnimation
	if playAnim then
		playAnim("End", 0.1, true)
	end

	if weaponInstance.ApplyState then
		weaponInstance.ApplyState(state)
	end

	return true
end

-- Alias for Cancel (used by WeaponController)
function Reload.Cancel(weaponInstance)
	return Reload.Interrupt(weaponInstance)
end

return Reload
