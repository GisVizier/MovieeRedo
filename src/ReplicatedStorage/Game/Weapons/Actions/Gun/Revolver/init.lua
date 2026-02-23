--[[
	Revolver.lua (Client Actions)

	Main module for Revolver client-side action helpers.
	Semi-automatic secondary weapon.
]]

local Revolver = {}
local Visuals = require(script:WaitForChild("Visuals"))

Revolver.Cancels = {
	FireCancelsSpecial = false,
	SpecialCancelsFire = false,
	ReloadCancelsSpecial = true,
	SpecialCancelsReload = true,
}

function Revolver.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	weaponInstance.State.LastFireTime = weaponInstance.State.LastFireTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false

	local config = weaponInstance.Config
	Visuals.UpdateAmmoVisibility(weaponInstance, weaponInstance.State.CurrentAmmo or 0, config and config.clipSize or 8)
end

function Revolver.OnEquip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.1, true)
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config
	Visuals.UpdateAmmoVisibility(weaponInstance, state and state.CurrentAmmo or 0, config and config.clipSize or 8)
end

function Revolver.OnUnequip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	local Special = require(script:WaitForChild("Special"))
	if Special.IsActive() then
		Special.Cancel()
	end
end

function Revolver.CanFire(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	local state = weaponInstance.State
	if state.IsReloading then
		return false
	end

	return (state.CurrentAmmo or 0) > 0
end

function Revolver.CanReload(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config

	if state.IsReloading then
		return false
	end

	if (state.CurrentAmmo or 0) >= (config.clipSize or 0) then
		return false
	end

	return (state.ReserveAmmo or 0) > 0
end

function Revolver.CanSpecial(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	return not weaponInstance.State.IsReloading
end

return Revolver
