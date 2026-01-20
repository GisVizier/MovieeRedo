--[[
	Knife.lua (Client Actions)

	Main module for Knife client-side action helpers.
	Basic melee weapon with cooldown-based attacks.
]]

local Knife = {}

Knife.Cancels = {
	FireCancelsSpecial = false,
	SpecialCancelsFire = false,
	ReloadCancelsSpecial = false,
	SpecialCancelsReload = false,
}

function Knife.Initialize(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	weaponInstance.State.LastAttackTime = weaponInstance.State.LastAttackTime or 0
	weaponInstance.State.Equipped = weaponInstance.State.Equipped ~= false
end

function Knife.OnEquip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Equip", 0.1, true)
	end
end

function Knife.OnUnequip(weaponInstance)
	if not weaponInstance then
		return
	end
	
	local Special = require(script:WaitForChild("Special"))
	if Special.IsActive() then
		Special.Cancel()
	end
end

function Knife.CanFire(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local cooldown = config.attackCooldown or 0.5

	local timeSinceLastAttack = os.clock() - (state.LastAttackTime or 0)
	return timeSinceLastAttack >= cooldown
end

function Knife.CanReload(_weaponInstance)
	-- Melee weapons don't reload
	return false
end

function Knife.CanSpecial(weaponInstance)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false
	end

	local config = weaponInstance.Config
	local cooldownService = weaponInstance.Cooldown
	
	if cooldownService and cooldownService:IsOnCooldown("KnifeSpecial") then
		return false
	end

	return true
end

return Knife
