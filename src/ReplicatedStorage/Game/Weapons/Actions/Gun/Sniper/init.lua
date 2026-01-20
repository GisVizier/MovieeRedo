--[[
	Sniper.lua (Client Actions)

	Main module for Sniper client-side action helpers.
	Semi-automatic fire with high zoom ADS.
]]

local Sniper = {}

Sniper.Cancels = {
	FireCancelsSpecial = false,
	SpecialCancelsFire = false,
	ReloadCancelsSpecial = true,
	SpecialCancelsReload = true,
}

function Sniper.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	weaponInstance.State.LastFireTime = weaponInstance.State.LastFireTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false
end

function Sniper.OnEquip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.1, true)
	end
end

function Sniper.OnUnequip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	local Special = require(script:WaitForChild("Special"))
	if Special.IsActive() then
		Special.Cancel()
	end
end

function Sniper.CanFire(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	local state = weaponInstance.State
	if state.IsReloading then
		return false
	end

	return (state.CurrentAmmo or 0) > 0
end

function Sniper.CanReload(weaponInstance)
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

function Sniper.CanSpecial(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	return not weaponInstance.State.IsReloading
end

return Sniper
