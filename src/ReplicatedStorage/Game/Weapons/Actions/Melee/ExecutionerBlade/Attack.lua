--[[
	Attack.lua (ExecutionerBlade)

	Client-side melee attack.
	Heavy swing with longer cooldown.
	Alternates between Slash1 and Slash2 for combo attacks.
]]

local Inspect = require(script.Parent:WaitForChild("Inspect"))

local Attack = {}

-- Track current slash for combo
Attack._currentSlash = 1
Attack._comboResetTime = 2.0 -- Reset combo after 2 seconds of no attacks

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

	-- Reset combo if too much time passed
	if timeSinceLastAttack > Attack._comboResetTime then
		Attack._currentSlash = 1
	end

	state.LastAttackTime = now

	-- Alternate between Slash1 and Slash2
	local slashAnim = Attack._currentSlash == 1 and "Slash1" or "Slash2"
	
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation(slashAnim, 0.08, true)
	end

	-- Cycle to next slash for combo
	Attack._currentSlash = Attack._currentSlash == 1 and 2 or 1

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
