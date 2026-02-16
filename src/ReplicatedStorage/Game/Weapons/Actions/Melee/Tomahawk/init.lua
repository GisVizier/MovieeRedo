--[[
	Tomahawk.lua (Client Actions)

	Main module for Tomahawk client-side action helpers.
	Basic melee weapon with cooldown-based attacks.
]]

local Tomahawk = {}
local Attack = require(script:WaitForChild("Attack"))

Tomahawk.Cancels = {
	FireCancelsSpecial = false,
	SpecialCancelsFire = false,
	ReloadCancelsSpecial = false,
	SpecialCancelsReload = false,
}

function Tomahawk.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	weaponInstance.State.LastAttackTime = weaponInstance.State.LastAttackTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false
end

function Tomahawk.OnEquip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.1, true)
	end
end

function Tomahawk.OnUnequip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	local Special = require(script:WaitForChild("Special"))
	if Special.IsActive() then
		Special.Cancel()
	end
end

function Tomahawk.CanFire(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local cooldown = config.attackCooldown or 0.5

	local timeSinceLastAttack = os.clock() - (state.LastAttackTime or 0)
	return timeSinceLastAttack >= cooldown
end

function Tomahawk.CanReload(_weaponInstance)
	-- Melee weapons don't reload
	return false
end

function Tomahawk.CanSpecial(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false
	end

	local config = weaponInstance.Config
	local cooldownService = weaponInstance.Cooldown
	
	if cooldownService and cooldownService:IsOnCooldown("TomahawkSpecial") then
		return false
	end

	return true
end

function Tomahawk.QuickAction(weaponInstance, currentTime)
	return Attack.Execute(weaponInstance, currentTime)
end

return Tomahawk
