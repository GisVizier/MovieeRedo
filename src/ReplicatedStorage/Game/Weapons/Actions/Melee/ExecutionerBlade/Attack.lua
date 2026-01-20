--[[
	Attack.lua (ExecutionerBlade)

	Client-side melee attack.
	Heavy swing with longer cooldown.
]]

local Inspect = require(script.Parent:WaitForChild("Inspect"))

local Attack = {}

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	-- Cancel inspect
	Inspect.Cancel()

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local now = currentTime or os.clock()

	if state.Equipped == false then
		return false, "NotEquipped"
	end

	local cooldown = config.attackCooldown or 0.6
	local timeSinceLastAttack = now - (state.LastAttackTime or 0)
	
	if timeSinceLastAttack < cooldown then
		return false, "Cooldown"
	end

	state.LastAttackTime = now

	-- Play heavy attack animation
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Attack", 0.08, true)
	end

	-- Perform melee raycast
	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(true)
	if hitData and weaponInstance.Net then
		weaponInstance.Net:FireServer("MeleeAttack", {
			weaponId = weaponInstance.WeaponName,
			timestamp = now,
			origin = hitData.origin,
			direction = hitData.direction,
			hitPart = hitData.hitPart,
			hitPosition = hitData.hitPosition,
			hitPlayer = hitData.hitPlayer,
			hitCharacter = hitData.hitCharacter,
		})
	end

	return true
end

return Attack
