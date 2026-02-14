local Reload = {}
local DualPistolsState = require(script.Parent:WaitForChild("State"))
local DualPistolsVisuals = require(script.Parent:WaitForChild("Visuals"))

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
	state.IsReloading = value
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

local function applyModeFromAddCount(ctx)
	if not ctx or not ctx.weaponInstance then
		return
	end

	if ctx.addCount == 1 then
		DualPistolsState.SetMode(ctx.weaponInstance.Slot, "semi")
	elseif ctx.addCount >= 2 then
		DualPistolsState.SetMode(ctx.weaponInstance.Slot, "burst")
	end
end

function Reload.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local clipSize = config.clipSize or 0

	if getReloading(weaponInstance, state) then
		return false, "Reloading"
	end
	if (state.CurrentAmmo or 0) >= clipSize then
		return false, "Full"
	end
	if (state.ReserveAmmo or 0) <= 0 then
		return false, "NoReserve"
	end

	clearActiveReload(true)

	setReloading(weaponInstance, state, true)
	setReloadLock(weaponInstance, state, true)
	local reloadToken = bumpToken(weaponInstance, state)
	commitState(weaponInstance, state)

	local track = nil
	if weaponInstance.PlayWeaponTrack then
		track = weaponInstance.PlayWeaponTrack("Reload", 0.05)
	end
	if not track and weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Reload", 0.1, true)
	end
	if not track then
		setReloadLock(weaponInstance, state, false)
		setReloading(weaponInstance, state, false)
		commitState(weaponInstance, state)
		return false, "NoReloadTrack"
	end

	activeReload = {
		weaponInstance = weaponInstance,
		state = state,
		reloadToken = reloadToken,
		track = track,
		addCount = 0,
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

		local markerParam = string.lower(tostring(param or ""))
		if markerParam == "add" then
			if ctx.addCount >= 2 then
				return
			end

			local localClip = ctx.weaponInstance.Config and (ctx.weaponInstance.Config.clipSize or 0) or 0
			local neededAmmo = localClip - (ctx.state.CurrentAmmo or 0)
			local ammoToReload = math.min(8, neededAmmo, ctx.state.ReserveAmmo or 0)
			if ammoToReload > 0 then
				ctx.state.CurrentAmmo = (ctx.state.CurrentAmmo or 0) + ammoToReload
				ctx.state.ReserveAmmo = (ctx.state.ReserveAmmo or 0) - ammoToReload
				commitState(ctx.weaponInstance, ctx.state)
				DualPistolsVisuals.UpdateAmmoVisibility(ctx.weaponInstance, ctx.state.CurrentAmmo or 0)
			end
			ctx.addCount += 1
		elseif markerParam == "eject" then
			ctx.state.CurrentAmmo = 0
			commitState(ctx.weaponInstance, ctx.state)
			DualPistolsVisuals.UpdateAmmoVisibility(ctx.weaponInstance, ctx.state.CurrentAmmo or 0)
		elseif markerParam == "_finish" then
			applyModeFromAddCount(ctx)
			setReloadLock(ctx.weaponInstance, ctx.state, false)
			setReloading(ctx.weaponInstance, ctx.state, false)
			commitState(ctx.weaponInstance, ctx.state)
			DualPistolsVisuals.UpdateAmmoVisibility(ctx.weaponInstance, ctx.state.CurrentAmmo or 0)
			clearActiveReload(false)
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
			applyModeFromAddCount(ctx)
			setReloadLock(ctx.weaponInstance, ctx.state, false)
			setReloading(ctx.weaponInstance, ctx.state, false)
			commitState(ctx.weaponInstance, ctx.state)
			DualPistolsVisuals.UpdateAmmoVisibility(ctx.weaponInstance, ctx.state.CurrentAmmo or 0)
		end

		clearActiveReload(false)
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

	setReloading(targetWeapon, state, false)
	setReloadLock(targetWeapon, state, false)
	bumpToken(targetWeapon, state)
	commitState(targetWeapon, state)
	DualPistolsVisuals.UpdateAmmoVisibility(targetWeapon, state.CurrentAmmo or 0)

	-- Interrupted reload still commits weapon mode from marker progress.
	applyModeFromAddCount(ctx)
	clearActiveReload(true)
	return true
end

function Reload.Cancel(weaponInstance)
	return Reload.Interrupt(weaponInstance)
end

return Reload
