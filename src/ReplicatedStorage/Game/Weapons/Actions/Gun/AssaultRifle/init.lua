--[[
	AssaultRifle.lua (Client Actions)

	Main module for AssaultRifle client-side action helpers.
	Automatic fire mode with standard ADS.
]]

local AssaultRifle = {}

-- Cancel behavior configuration
AssaultRifle.Cancels = {
	FireCancelsSpecial = false,    -- Firing does NOT exit ADS
	SpecialCancelsFire = false,    -- ADS does NOT block firing
	ReloadCancelsSpecial = true,   -- Reload exits ADS
	SpecialCancelsReload = true,   -- ADS cancels reload
}

function AssaultRifle.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	weaponInstance.State.LastFireTime = weaponInstance.State.LastFireTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false
end

function AssaultRifle.OnEquip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.1, true)
	end
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound("Equip")
	end
end

function AssaultRifle.OnUnequip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	local Special = require(script:WaitForChild("Special"))
	if Special.IsActive() then
		Special.Cancel()
	end
end

function AssaultRifle.CanFire(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	local state = weaponInstance.State
	if state.IsReloading then
		return false
	end

	return (state.CurrentAmmo or 0) > 0
end

function AssaultRifle.CanReload(weaponInstance)
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

function AssaultRifle.CanSpecial(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	return not weaponInstance.State.IsReloading
end

return AssaultRifle
