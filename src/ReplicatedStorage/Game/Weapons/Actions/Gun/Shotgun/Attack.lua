--[[
	Attack.lua (Shotgun)

	Client-side attack checks + ammo consumption.
	No viewmodel, VFX, or networking here.
]]

local Attack = {}

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local now = currentTime or os.clock()

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

	local track = weaponInstance.Animator and weaponInstance.Animator:GetTrack("Fire")
	if track then
		track:Play(0.05)
	end

	return true
end

return Attack
