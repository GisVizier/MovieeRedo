--[[
	Reload.lua (Revolver)

	Client-side reload flow using marker-driven animations.
	Supports:
	- ReloadBullets markers: remove, add, _finish
	- ReloadEmpty markers: add, _finish
]]

local Inspect = require(script.Parent:WaitForChild("Inspect"))
local Special = require(script.Parent:WaitForChild("Special"))
local Visuals = require(script.Parent:WaitForChild("Visuals"))

local Reload = {}

local activeReload = nil

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
	state.IsReloading = value == true
end

local function setReloadLock(weaponInstance, state, value)
	if weaponInstance.SetReloadFireLocked then
		weaponInstance.SetReloadFireLocked(value)
	end
	state.ReloadFireLocked = value == true
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

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function clearActiveReload(stopTrack)
	if not activeReload then
		return
	end

	disconnectConnection(activeReload.markerConnection)
	disconnectConnection(activeReload.stoppedConnection)

	if stopTrack and activeReload.track and activeReload.track.IsPlaying then
		activeReload.track:Stop(0.05)
	end

	activeReload = nil
end

local function applyAddMarkerAmmo(ctx)
	local state = ctx.state
	local config = ctx.weaponInstance.Config
	local clipSize = config and (config.clipSize or 8) or 8
	local currentAmmo = state.CurrentAmmo or 0
	local reserveAmmo = state.ReserveAmmo or 0

	local missing = math.max(clipSize - currentAmmo, 0)
	local toReload = math.min(missing, reserveAmmo)
	if toReload <= 0 then
		return
	end

	state.CurrentAmmo = currentAmmo + toReload
	state.ReserveAmmo = reserveAmmo - toReload
	commitState(ctx.weaponInstance, state)
	Visuals.UpdateAmmoVisibility(ctx.weaponInstance, state.CurrentAmmo or 0, clipSize)
end

local function finishReload(ctx)
	if not ctx then
		return
	end

	local state = ctx.state
	local weaponInstance = ctx.weaponInstance
	local clipSize = weaponInstance.Config and (weaponInstance.Config.clipSize or 8) or 8

	setReloadLock(weaponInstance, state, false)
	setReloading(weaponInstance, state, false)
	clearReloadSnapshot(state)
	commitState(weaponInstance, state)
	Visuals.UpdateAmmoVisibility(weaponInstance, state.CurrentAmmo or 0, clipSize)
	clearActiveReload(false)
end

local function startReloadTrack(weaponInstance, animName)
	local track = nil
	if weaponInstance.PlayWeaponTrack then
		track = weaponInstance.PlayWeaponTrack(animName, 0.05)
	end
	if not track and weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation(animName, 0.1, true)
	end
	return track
end

function Reload.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local clipSize = config.clipSize or 8

	if getReloading(weaponInstance, state) then
		return false, "Reloading"
	end

	if (state.CurrentAmmo or 0) >= clipSize then
		return false, "Full"
	end

	if (state.ReserveAmmo or 0) <= 0 then
		return false, "NoReserve"
	end

	Inspect.Cancel()
	if Special.IsActive and Special.IsActive() then
		Special.Cancel()
	end

	clearActiveReload(true)

	local animName = ((state.CurrentAmmo or 0) <= 0) and "ReloadEmpty" or "ReloadBullets"

	setReloadSnapshot(state)
	setReloading(weaponInstance, state, true)
	setReloadLock(weaponInstance, state, true)
	state.ReloadStartTime = os.clock()
	local reloadToken = bumpToken(weaponInstance, state)
	commitState(weaponInstance, state)

	local track = startReloadTrack(weaponInstance, animName)
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound(animName)
	end

	if not track then
		local reloadTime = config.reloadTime or 1.5
		task.delay(reloadTime, function()
			if not getReloading(weaponInstance, state) or getToken(weaponInstance, state) ~= reloadToken then
				return
			end

			local missing = math.max(clipSize - (state.CurrentAmmo or 0), 0)
			local toReload = math.min(missing, state.ReserveAmmo or 0)
			state.CurrentAmmo = (state.CurrentAmmo or 0) + toReload
			state.ReserveAmmo = (state.ReserveAmmo or 0) - toReload
			setReloadLock(weaponInstance, state, false)
			setReloading(weaponInstance, state, false)
			clearReloadSnapshot(state)
			commitState(weaponInstance, state)
			Visuals.UpdateAmmoVisibility(weaponInstance, state.CurrentAmmo or 0, clipSize)
		end)
		return true
	end

	activeReload = {
		weaponInstance = weaponInstance,
		state = state,
		reloadToken = reloadToken,
		track = track,
		animName = animName,
	}

	activeReload.markerConnection = track:GetMarkerReachedSignal("Event"):Connect(function(param)
		if not activeReload then
			return
		end

		local ctx = activeReload
		if getToken(ctx.weaponInstance, ctx.state) ~= ctx.reloadToken then
			return
		end
		if not getReloading(ctx.weaponInstance, ctx.state) then
			return
		end

		local marker = string.lower(tostring(param or ""))
		if marker == "remove" then
			Visuals.SetAllVisible(ctx.weaponInstance, false, clipSize)
		elseif marker == "add" then
			applyAddMarkerAmmo(ctx)
		elseif marker == "_finish" then
			finishReload(ctx)
		end
	end)

	activeReload.stoppedConnection = track.Stopped:Connect(function()
		if not activeReload then
			return
		end

		local ctx = activeReload
		if getToken(ctx.weaponInstance, ctx.state) ~= ctx.reloadToken then
			clearActiveReload(false)
			return
		end

		if getReloading(ctx.weaponInstance, ctx.state) then
			finishReload(ctx)
		else
			clearActiveReload(false)
		end
	end)

	return true
end

function Reload.Interrupt(weaponInstance)
	local ctx = activeReload
	if not ctx then
		if not weaponInstance or not weaponInstance.State then
			return false, "InvalidInstance"
		end
		if not getReloading(weaponInstance, weaponInstance.State) then
			return false, "NotReloading"
		end
		ctx = {
			weaponInstance = weaponInstance,
			state = weaponInstance.State,
		}
	end

	local targetWeapon = ctx.weaponInstance
	local state = ctx.state
	if not targetWeapon or not state then
		return false, "InvalidInstance"
	end

	if not getReloading(targetWeapon, state) then
		clearActiveReload(false)
		return false, "NotReloading"
	end

	restoreReloadSnapshot(state)
	setReloading(targetWeapon, state, false)
	setReloadLock(targetWeapon, state, false)
	bumpToken(targetWeapon, state)
	commitState(targetWeapon, state)
	Visuals.UpdateAmmoVisibility(targetWeapon, state.CurrentAmmo or 0, targetWeapon.Config and targetWeapon.Config.clipSize or 8)

	clearActiveReload(true)

	if targetWeapon.StopActionSound then
		targetWeapon.StopActionSound("ReloadBullets")
		targetWeapon.StopActionSound("ReloadEmpty")
	end

	return true
end

function Reload.Cancel(weaponInstance)
	return Reload.Interrupt(weaponInstance)
end

return Reload
