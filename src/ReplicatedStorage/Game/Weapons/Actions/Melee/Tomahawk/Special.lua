--[[
	Special.lua (Tomahawk)

	Tomahawk special ability - quick stab/lunge.
	Uses cooldown system.
]]

local Special = {}
Special._isActive = false

function Special.Execute(weaponInstance, isPressed)
	if not weaponInstance then
		return false, "InvalidInstance"
	end

	-- Only trigger on press, not release
	if not isPressed then
		return true
	end

	local config = weaponInstance.Config
	local cooldownService = weaponInstance.Cooldown

	-- Check cooldown
	if cooldownService and cooldownService:IsOnCooldown("TomahawkSpecial") then
		return false, "Cooldown"
	end

	Special._isActive = true

	-- Play special animation
	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Special", 0.05, true)
	end

	-- Start cooldown
	local specialCooldown = config and config.specialCooldown or 3.0
	if cooldownService then
		cooldownService:StartCooldown("TomahawkSpecial", specialCooldown)
	end

	-- Perform special attack raycast
	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(true)
	if hitData and weaponInstance.Net then
		weaponInstance.Net:FireServer("MeleeSpecial", {
			weaponId = weaponInstance.WeaponName,
			timestamp = os.clock(),
			origin = hitData.origin,
			direction = hitData.direction,
			hitPart = hitData.hitPart,
			hitPosition = hitData.hitPosition,
			hitPlayer = hitData.hitPlayer,
			hitCharacter = hitData.hitCharacter,
		})
	end

	-- Reset active state after a short delay
	task.delay(0.3, function()
		Special._isActive = false
	end)

	return true
end

function Special.Cancel()
	Special._isActive = false
end

function Special.IsActive()
	return Special._isActive
end

return Special
