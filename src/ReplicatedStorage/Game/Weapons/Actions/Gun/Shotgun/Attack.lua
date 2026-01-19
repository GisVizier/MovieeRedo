--[[
	Attack.lua (Shotgun)

	Client-side attack checks + ammo consumption.
	Handles client networking for Shotgun fire.
]]

local Attack = {}

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

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

	local fireInterval = 60 / (config.fireRate or 600)
	if state.LastFireTime and now - state.LastFireTime < fireInterval then
		return false, "Cooldown"
	end

	state.LastFireTime = now
	state.CurrentAmmo = math.max((state.CurrentAmmo or 0) - 1, 0)

	if weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation("Fire", 0.05, true)
	end

	local fireProfile = weaponInstance.FireProfile or {}
	local pelletDirections = nil
	local pelletsPerShot = fireProfile.pelletsPerShot or config.pelletsPerShot
	if pelletsPerShot and pelletsPerShot > 1 then
		if weaponInstance.GeneratePelletDirections then
			pelletDirections = weaponInstance.GeneratePelletDirections({
				pelletsPerShot = pelletsPerShot,
				spread = fireProfile.spread or 0.15,
			})
		end
	end

	local hitData = weaponInstance.PerformRaycast and weaponInstance.PerformRaycast(pelletDirections ~= nil)
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
			pelletDirections = pelletDirections,
		})

		if weaponInstance.PlayFireEffects then
			weaponInstance.PlayFireEffects(hitData)
		end

		if weaponInstance.RenderTracer then
			if pelletDirections and hitData and hitData.origin then
				local range = (weaponInstance.Config and weaponInstance.Config.range) or 50
				for _, dir in ipairs(pelletDirections) do
					weaponInstance.RenderTracer({
						origin = hitData.origin,
						hitPosition = hitData.origin + dir.Unit * range,
						weaponId = weaponInstance.WeaponName,
					})
				end
			else
				weaponInstance.RenderTracer(hitData)
			end
		end
	end

	return true
end

return Attack
