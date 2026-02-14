local DualPistols = {}
local DualPistolsVisuals = require(script:WaitForChild("Visuals"))

DualPistols.Cancels = {
	FireCancelsSpecial = false,
	SpecialCancelsFire = false,
	ReloadCancelsSpecial = true,
	SpecialCancelsReload = false,
}

function DualPistols.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	weaponInstance.State.LastFireTime = weaponInstance.State.LastFireTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false
	DualPistolsVisuals.UpdateAmmoVisibility(weaponInstance, weaponInstance.State.CurrentAmmo or 0)
end

function DualPistols.OnEquip(weaponInstance)
	if not weaponInstance then
		return
	end

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.1, true)
	end

	if weaponInstance.State then
		DualPistolsVisuals.UpdateAmmoVisibility(weaponInstance, weaponInstance.State.CurrentAmmo or 0)
	end
end

function DualPistols.OnUnequip(weaponInstance)
	local Attack = require(script:WaitForChild("Attack"))
	if Attack and Attack.Cancel then
		Attack.Cancel(weaponInstance)
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

function DualPistols.CanSpecial(_weaponInstance)
	return false
end

return DualPistols
