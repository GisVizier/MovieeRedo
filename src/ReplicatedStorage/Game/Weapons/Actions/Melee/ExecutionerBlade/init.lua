--[[
	ExecutionerBlade.lua (Client Actions)

	Main module for Executioner's Blade client-side action helpers.
	Heavy melee weapon with powerful special attack.
]]

local ExecutionerBlade = {}
local Attack = require(script:WaitForChild("Attack"))

ExecutionerBlade.Cancels = {
	FireCancelsSpecial = true,     -- Attack cancels special windup
	SpecialCancelsFire = true,     -- Special blocks normal attacks
	ReloadCancelsSpecial = false,
	SpecialCancelsReload = false,
}

function ExecutionerBlade.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	weaponInstance.State.LastAttackTime = weaponInstance.State.LastAttackTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false
end

function ExecutionerBlade.OnEquip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.15, true)
	end
end

function ExecutionerBlade.OnUnequip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	local Special = require(script:WaitForChild("Special"))
	if Special.IsActive() then
		Special.Cancel()
	end
end

function ExecutionerBlade.CanFire(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local cooldown = config.attackCooldown or 0.6

	local timeSinceLastAttack = os.clock() - (state.LastAttackTime or 0)
	return timeSinceLastAttack >= cooldown
end

function ExecutionerBlade.CanReload(_weaponInstance)
	return false
end

function ExecutionerBlade.CanSpecial(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false
	end

	local cooldownService = weaponInstance.Cooldown
	
	if cooldownService and cooldownService:IsOnCooldown("ExecutionerSpecial") then
		return false
	end

	return true
end

function ExecutionerBlade.QuickAction(weaponInstance, currentTime)
	return Attack.Execute(weaponInstance, currentTime)
end

return ExecutionerBlade
