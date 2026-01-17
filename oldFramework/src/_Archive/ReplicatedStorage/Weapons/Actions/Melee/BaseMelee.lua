--[[
	BaseMelee.lua

	Shared functionality for all melee-type weapons.
	Provides common methods that can be used or overridden by specific melee implementations.
]]

local BaseMelee = {}

--[[
	Check if the melee weapon can attack
	@param weaponInstance table - The weapon instance
	@return boolean - Whether the weapon can attack
]]
function BaseMelee.CanAttack(weaponInstance)
	local state = weaponInstance.State

	-- Cannot attack if not equipped
	if not state.Equipped then
		return false
	end

	-- Cannot attack if already attacking
	if state.IsAttacking then
		return false
	end

	return true
end

--[[
	Calculate damage based on attack type and hit location
	@param weaponInstance table - The weapon instance
	@param isHeadshot boolean - Whether this is a headshot
	@param attackType string - "Light" or "Heavy" (optional)
	@return number - Calculated damage
]]
function BaseMelee.CalculateDamage(weaponInstance, isHeadshot, attackType)
	local config = weaponInstance.Config

	-- Use attack type specific damage if available
	if attackType and config.Attack.AttackTypes[attackType] then
		local attackConfig = config.Attack.AttackTypes[attackType]
		return isHeadshot and attackConfig.HeadshotDamage or attackConfig.Damage
	end

	-- Fall back to base damage
	return isHeadshot and config.Damage.HeadshotDamage or config.Damage.BodyDamage
end

--[[
	Check if an attack is a backstab
	@param weaponInstance table - The weapon instance
	@param attackerPosition Vector3 - Position of the attacker
	@param targetPosition Vector3 - Position of the target
	@param targetLookVector Vector3 - Look vector of the target
	@return boolean - Whether this is a backstab
]]
function BaseMelee.IsBackstab(weaponInstance, attackerPosition, targetPosition, targetLookVector)
	local config = weaponInstance.Config.Damage

	-- Check if backstab damage is configured
	if not config.BackstabDamage or not config.BackstabAngle then
		return false
	end

	-- Calculate direction from target to attacker
	local directionToAttacker = (attackerPosition - targetPosition).Unit

	-- Calculate angle between target's look vector and direction to attacker
	local dotProduct = targetLookVector:Dot(directionToAttacker)
	local angleInRadians = math.acos(math.clamp(dotProduct, -1, 1))
	local angleInDegrees = math.deg(angleInRadians)

	-- Check if angle is within backstab threshold
	return angleInDegrees <= config.BackstabAngle
end

--[[
	Get attack cooldown based on attack type
	@param weaponInstance table - The weapon instance
	@param attackType string - "Light" or "Heavy" (optional)
	@return number - Cooldown in seconds
]]
function BaseMelee.GetAttackCooldown(weaponInstance, attackType)
	local config = weaponInstance.Config

	-- Use attack type specific cooldown if available
	if attackType and config.Attack.AttackTypes[attackType] then
		return config.Attack.AttackTypes[attackType].Cooldown
	end

	-- Fall back to attack rate
	return 1 / config.Attack.AttackRate
end

--[[
	Get attack duration based on attack type
	@param weaponInstance table - The weapon instance
	@param attackType string - "Light" or "Heavy" (optional)
	@return number - Duration in seconds
]]
function BaseMelee.GetAttackDuration(weaponInstance, attackType)
	local config = weaponInstance.Config

	-- Use attack type specific duration if available
	if attackType and config.Attack.AttackTypes[attackType] then
		return config.Attack.AttackTypes[attackType].Duration
	end

	-- Fall back to base attack duration
	return config.Attack.AttackDuration
end

--[[
	Perform a hitbox check for melee attack
	@param weaponInstance table - The weapon instance
	@param attackerPosition Vector3 - Position of the attacker
	@param attackDirection Vector3 - Direction of the attack
	@return table - Array of hit results {Part, Position, Distance}
]]
function BaseMelee.PerformHitDetection(weaponInstance, attackerPosition, attackDirection)
	local config = weaponInstance.Config.Attack
	local player = weaponInstance.Player

	-- Raycast parameters
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { player.Character }

	-- Perform raycast
	local raycastResult = workspace:Raycast(attackerPosition, attackDirection * config.Range, raycastParams)

	if raycastResult then
		return {
			{
				Part = raycastResult.Instance,
				Position = raycastResult.Position,
				Distance = raycastResult.Distance,
				Normal = raycastResult.Normal,
			},
		}
	end

	return {}
end

return BaseMelee
