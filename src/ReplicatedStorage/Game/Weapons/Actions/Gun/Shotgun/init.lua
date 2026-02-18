--[[
	Shotgun.lua (Client Actions)

	Main module for Shotgun client-side action helpers.
	Defines lifecycle hooks and cancel behavior.
]]

local Shotgun = {}

-- Cancel behavior configuration
Shotgun.Cancels = {
	FireCancelsSpecial = false,    -- Firing does NOT exit ADS
	SpecialCancelsFire = false,    -- ADS does NOT block firing
	ReloadCancelsSpecial = true,   -- Reload exits ADS
	SpecialCancelsReload = true,   -- ADS cancels reload
}

function Shotgun.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	weaponInstance.State.LastFireTime = weaponInstance.State.LastFireTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false
end

function Shotgun.OnEquip(weaponInstance)
	-- Called when weapon becomes active
	if not weaponInstance then
		return
	end
	
	-- Play equip animation if available
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.1, true)
	end
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound("Equip")
	end
end

function Shotgun.OnUnequip(weaponInstance)
	-- Called when switching away from this weapon
	if not weaponInstance then
		return
	end
	
	-- Cancel any active special (ADS)
	local Special = require(script:WaitForChild("Special"))
	if Special.IsActive() then
		Special.Cancel()
	end
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

function Shotgun.CanReload(weaponInstance)
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

function Shotgun.CanSpecial(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false
	end

	-- Can always ADS unless reloading
	return not weaponInstance.State.IsReloading
end

return Shotgun
