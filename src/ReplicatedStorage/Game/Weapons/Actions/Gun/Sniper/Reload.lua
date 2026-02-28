--[[
	Reload.lua (Sniper)

	Client-side marker-driven reload.
	Supports Reload (tac) and Reload2 (empty) with markers:
	- Event:eject
	- Event:add
	- Event:_finish
]]

local Inspect = require(script.Parent:WaitForChild("Inspect"))
local Special = require(script.Parent:WaitForChild("Special"))

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
	local clipSize = config and (config.clipSize or 5) or 5
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
end

local function finishReload(ctx)
	if not ctx then
		return
	end

	local state = ctx.state
	local weaponInstance = ctx.weaponInstance

	setReloadLock(weaponInstance, state, false)
	setReloading(weaponInstance, state, false)
	clearReloadSnapshot(state)
	commitState(weaponInstance, state)
	clearActiveReload(false)
end

local function startReloadTrack(weaponInstance, animName)
	local track = nil
	if weaponInstance.PlayWeaponTrack then
		track = weaponInstance.PlayWeaponTrack(animName, 0.08)
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

	Inspect.Cancel()
	if Special.IsActive and Special.IsActive() then
		Special.Cancel()
	end

	clearActiveReload(true)

	local animName = ((state.CurrentAmmo or 0) <= 0) and "Reload2" or "Reload"

	setReloadSnapshot(state)
	setReloading(weaponInstance, state, true)
	setReloadLock(weaponInstance, state, true)
	local reloadToken = bumpToken(weaponInstance, state)
	commitState(weaponInstance, state)

	local track = startReloadTrack(weaponInstance, animName)
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound(animName)
	end

	if not track then
		local reloadTime = config.reloadTime or 2.5
		task.delay(reloadTime, function()
			if not getReloading(weaponInstance, state) or getToken(weaponInstance, state) ~= reloadToken then
				return
			end

			local neededAmmo = clipSize - (state.CurrentAmmo or 0)
			local ammoToReload = math.min(neededAmmo, state.ReserveAmmo or 0)

			state.CurrentAmmo = (state.CurrentAmmo or 0) + ammoToReload
			state.ReserveAmmo = (state.ReserveAmmo or 0) - ammoToReload

			setReloadLock(weaponInstance, state, false)
			setReloading(weaponInstance, state, false)
			clearReloadSnapshot(state)
			commitState(weaponInstance, state)
		end)
		return true
	end

	activeReload = {
		weaponInstance = weaponInstance,
		state = state,
		reloadToken = reloadToken,
		track = track,
		animName = animName,
		ejectSeen = false,
		addApplied = false,
		finished = false,
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
		if marker == "eject" then
			ctx.ejectSeen = true
		elseif marker == "add" then
			if ctx.addApplied then
				return
			end
			ctx.addApplied = true
			applyAddMarkerAmmo(ctx)
		elseif marker == "_finish" then
			ctx.finished = true
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
			-- If the reload track stops without the explicit _finish marker,
			-- treat it as an interruption and restore pre-reload ammo.
			if ctx.finished ~= true then
				restoreReloadSnapshot(ctx.state)
				setReloadLock(ctx.weaponInstance, ctx.state, false)
				setReloading(ctx.weaponInstance, ctx.state, false)
				commitState(ctx.weaponInstance, ctx.state)
				clearActiveReload(false)
				return
			end
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

	clearActiveReload(true)

	if targetWeapon.StopActionSound then
		targetWeapon.StopActionSound("Reload")
		targetWeapon.StopActionSound("Reload2")
	end
	return true
end

function Reload.Cancel(weaponInstance)
	return Reload.Interrupt(weaponInstance)
end

return Reload
