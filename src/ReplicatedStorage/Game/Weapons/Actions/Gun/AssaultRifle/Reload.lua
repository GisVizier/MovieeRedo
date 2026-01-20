--[[
	Reload.lua (AssaultRifle)

	Client-side reload validation + state.
	Standard magazine reload (not shell-by-shell).
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
	if weaponInstance.IncrementReloadToken then
		return weaponInstance.IncrementReloadToken()
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
	local reloadToken = bumpToken(weaponInstance, state)

	-- Play reload animation
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Reload", 0.1, true)
	end

	-- Update HUD
	local ammoService = weaponInstance.Ammo
	if ammoService and ammoService.UpdateHUDAmmo then
		ammoService:UpdateHUDAmmo(weaponInstance.Slot, config, weaponInstance.Player, true, function()
			return weaponInstance.Slot
		end)
	end

	-- Wait for reload to complete
	local reloadTime = config.reloadTime or 1.8
	task.delay(reloadTime, function()
		if not getReloading(weaponInstance, state) or getToken(weaponInstance, state) ~= reloadToken then
			return
		end

		-- Calculate ammo to reload
		local neededAmmo = clipSize - (state.CurrentAmmo or 0)
		local ammoToReload = math.min(neededAmmo, state.ReserveAmmo or 0)

		state.CurrentAmmo = (state.CurrentAmmo or 0) + ammoToReload
		state.ReserveAmmo = (state.ReserveAmmo or 0) - ammoToReload

		setReloading(weaponInstance, state, false)

		-- Update HUD
		if ammoService and ammoService.UpdateHUDAmmo then
			ammoService:UpdateHUDAmmo(weaponInstance.Slot, config, weaponInstance.Player, false, function()
				return weaponInstance.Slot
			end)
		end
	end)

	return true
end

function Reload.Cancel()
	-- Standard reload can be cancelled via token system
end

return Reload
