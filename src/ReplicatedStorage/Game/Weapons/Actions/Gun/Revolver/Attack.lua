--[[
	Attack.lua (Revolver)

	Client-side attack checks + ammo consumption.
	Semi-automatic fire mode.
]]

local Inspect = require(script.Parent:WaitForChild("Inspect"))

local Attack = {}

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	Inspect.Cancel()

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local now = currentTime or os.clock()

	if state.Equipped == false then
		return false, "NotEquipped"
	end

	if state.IsReloading then
		return false, "Reloading"
	end

	if (state.CurrentAmmo or 0) <= 0 then
		return false, "NoAmmo"
	end

	local fireInterval = 60 / (config.fireRate or 120)
	if state.LastFireTime and now - state.LastFireTime < fireInterval then
		return false, "Cooldown"
	end

	state.LastFireTime = now
	state.CurrentAmmo = math.max((state.CurrentAmmo or 0) - 1, 0)

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Fire", 0.05, true)
	end

	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(false)
	if hitData and weaponInstance.Net then
		weaponInstance.Net:FireServer("WeaponFired", {
			weaponId = weaponInstance.WeaponName,
			timestamp = now,
			origin = hitData.origin,
			direction = hitData.direction,
			hitPart = hitData.hitPart,
			hitPosition = hitData.hitPosition,
			hitPlayer = hitData.hitPlayer,
			hitCharacter = hitData.hitCharacter,
			isHeadshot = hitData.isHeadshot,
		})

		if weaponInstance.PlayFireEffects then
			weaponInstance.PlayFireEffects(hitData)
		end

		if weaponInstance.RenderTracer then
			weaponInstance.RenderTracer(hitData)
		end
	end

	return true
end

return Attack
