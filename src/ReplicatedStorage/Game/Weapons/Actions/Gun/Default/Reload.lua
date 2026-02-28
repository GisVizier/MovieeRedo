local Reload = {}

local function getReloading(weaponInstance, state)
	if weaponInstance.GetIsReloading then
		return weaponInstance.GetIsReloading()
	end
	return state.IsReloading == true
end

local function setReloading(weaponInstance, state, value)
	if weaponInstance.SetIsReloading then
		weaponInstance.SetIsReloading(value == true)
	end
	state.IsReloading = value == true
end

local function getToken(weaponInstance, state)
	if weaponInstance.GetReloadToken then
		return weaponInstance.GetReloadToken()
	end
	return state.ReloadToken
end

local function bumpToken(weaponInstance, state)
	if weaponInstance.IncrementReloadToken then
		return weaponInstance.IncrementReloadToken()
	end
	if weaponInstance.BumpReloadToken then
		return weaponInstance.BumpReloadToken()
	end
	if weaponInstance.GetReloadToken and weaponInstance.SetReloadToken then
		local token = (weaponInstance.GetReloadToken() or 0) + 1
		weaponInstance.SetReloadToken(token)
		return token
	end
	state.ReloadToken = (state.ReloadToken or 0) + 1
	return state.ReloadToken
end

local function commitState(weaponInstance, state)
	if weaponInstance.ApplyState then
		weaponInstance.ApplyState(state)
	end
end

local function setReloadSnapshot(state)
	state.ReloadSnapshotCurrentAmmo = state.CurrentAmmo or 0
	state.ReloadSnapshotReserveAmmo = state.ReserveAmmo or 0
end

local function clearReloadSnapshot(state)
	state.ReloadSnapshotCurrentAmmo = nil
	state.ReloadSnapshotReserveAmmo = nil
end

local function restoreReloadSnapshot(state)
	if type(state.ReloadSnapshotCurrentAmmo) == "number" then
		state.CurrentAmmo = state.ReloadSnapshotCurrentAmmo
	end
	if type(state.ReloadSnapshotReserveAmmo) == "number" then
		state.ReserveAmmo = state.ReloadSnapshotReserveAmmo
	end
	clearReloadSnapshot(state)
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

	setReloadSnapshot(state)
	setReloading(weaponInstance, state, true)
	local token = bumpToken(weaponInstance, state)

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Reload", 0.1, true)
	end

	commitState(weaponInstance, state)

	local reloadTime = config.reloadTime or 0
	task.delay(reloadTime, function()
		if getToken(weaponInstance, state) ~= token then
			return
		end
		if not getReloading(weaponInstance, state) then
			return
		end

		local needed = clipSize - (state.CurrentAmmo or 0)
		local toReload = math.min(needed, state.ReserveAmmo or 0)

		state.CurrentAmmo = (state.CurrentAmmo or 0) + toReload
		state.ReserveAmmo = (state.ReserveAmmo or 0) - toReload
		setReloading(weaponInstance, state, false)
		clearReloadSnapshot(state)

		commitState(weaponInstance, state)
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

	restoreReloadSnapshot(state)
	setReloading(weaponInstance, state, false)
	bumpToken(weaponInstance, state)
	commitState(weaponInstance, state)

	return true
end

function Reload.Cancel(weaponInstance)
	return Reload.Interrupt(weaponInstance)
end

return Reload
