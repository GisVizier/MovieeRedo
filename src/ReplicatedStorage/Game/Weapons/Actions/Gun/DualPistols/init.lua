local DualPistols = {}
local DualPistolsVisuals = require(script:WaitForChild("Visuals"))
local DualPistolsState = require(script:WaitForChild("State"))

DualPistols.Cancels = {
	FireCancelsSpecial = false,
	SpecialCancelsFire = false,
	ReloadCancelsSpecial = true,
	SpecialCancelsReload = false,
}

function DualPistols.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return
	end

	weaponInstance.State.LastFireTime = weaponInstance.State.LastFireTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false
	DualPistolsState.SyncToTotal(
		weaponInstance.Slot,
		weaponInstance.State.CurrentAmmo or 0,
		weaponInstance.Config.clipSize or 16
	)
	DualPistolsVisuals.UpdateAmmoVisibility(weaponInstance, weaponInstance.State.CurrentAmmo or 0)
end

function DualPistols.OnEquip(weaponInstance)
	if not weaponInstance or not weaponInstance.Config then
		return
	end

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.1, true)
	end
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound("Equip")
	end

	if weaponInstance.State then
		DualPistolsState.SyncToTotal(
			weaponInstance.Slot,
			weaponInstance.State.CurrentAmmo or 0,
			weaponInstance.Config.clipSize or 16
		)
		DualPistolsVisuals.UpdateAmmoVisibility(weaponInstance, weaponInstance.State.CurrentAmmo or 0)
	end
end

function DualPistols.OnUnequip(weaponInstance)
	local Attack = require(script:WaitForChild("Attack"))
	if Attack and Attack.Cancel then
		Attack.Cancel(weaponInstance)
	end

	local Special = require(script:WaitForChild("Special"))
	if Special and Special.IsActive and Special.IsActive() and Special.Cancel then
		Special.Cancel()
	end
end

function DualPistols.CanFire(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	local state = weaponInstance.State
	if state.IsReloading then
		return false
	end

	return (state.CurrentAmmo or 0) > 0
end

function DualPistols.CanReload(weaponInstance)
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

function DualPistols.CanSpecial(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	return not weaponInstance.State.IsReloading
end

return DualPistols
