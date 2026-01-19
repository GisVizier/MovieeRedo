--[[
	Shotgun.lua (Client Actions)

	Main module for Shotgun client-side action helpers.
	Keep this focused on state/logic only (no viewmodel or VFX).
]]

local Shotgun = {}

function Shotgun.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	weaponInstance.State.LastFireTime = weaponInstance.State.LastFireTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false
end

function Shotgun.CanFire(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	local state = weaponInstance.State
	if state.IsReloading then
		return false
	end

	return (state.CurrentAmmo or 0) > 0
end

function Shotgun.CalculateDamage(_weaponInstance, _distance, _isHeadshot)
	-- Placeholder: damage handled by existing WeaponController/server validation.
	return 0
end

return Shotgun
