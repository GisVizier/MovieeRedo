--[[
	BaseGun.lua

	Shared functionality for all gun-type weapons.
	Provides common methods that can be used or overridden by specific gun implementations.
]]

local BaseGun = {}

--[[
	Check if the gun can fire
	@param weaponInstance table - The weapon instance
	@return boolean - Whether the gun can fire
]]
function BaseGun.CanFire(weaponInstance)
	local state = weaponInstance.State
	local config = weaponInstance.Config

	-- Cannot fire if not equipped
	if not state.Equipped then
		return false
	end

	-- Cannot fire if reloading
	if state.IsReloading then
		return false
	end

	-- Cannot fire if already attacking (for semi-auto)
	if config.FireRate.FireMode == "Semi" and state.IsAttacking then
		return false
	end

	-- Cannot fire if no ammo
	if state.CurrentAmmo <= 0 then
		-- Auto reload if enabled
		if config.Ammo.AutoReload and state.ReserveAmmo > 0 then
			-- Trigger reload (will be handled by Reload action)
			return false
		end
		return false
	end

	return true
end

--[[
	Check if the gun can reload
	@param weaponInstance table - The weapon instance
	@return boolean - Whether the gun can reload
]]
function BaseGun.CanReload(weaponInstance)
	local state = weaponInstance.State
	local config = weaponInstance.Config

	-- Cannot reload if not equipped
	if not state.Equipped then
		return false
	end

	-- Cannot reload if already reloading
	if state.IsReloading then
		return false
	end

	-- Cannot reload if mag is full
	if state.CurrentAmmo >= config.Ammo.MagSize then
		return false
	end

	-- Cannot reload if no reserve ammo
	if state.ReserveAmmo <= 0 then
		return false
	end

	return true
end

--[[
	Calculate damage based on distance
	@param weaponInstance table - The weapon instance
	@param distance number - Distance to target in studs
	@param isHeadshot boolean - Whether this is a headshot
	@return number - Calculated damage
]]
function BaseGun.CalculateDamage(weaponInstance, distance, isHeadshot)
	local config = weaponInstance.Config.Damage
	local baseDamage = isHeadshot and config.HeadshotDamage or config.BodyDamage

	-- Calculate falloff multiplier
	local falloffMultiplier = 1
	if distance > config.MinRange then
		local falloffRange = config.MaxRange - config.MinRange
		local falloffDistance = math.min(distance - config.MinRange, falloffRange)
		local falloffProgress = falloffDistance / falloffRange

		-- Linear interpolation between 1.0 and MinDamageMultiplier
		falloffMultiplier = 1 - (falloffProgress * (1 - config.MinDamageMultiplier))
	end

	return baseDamage * falloffMultiplier
end

--[[
	Calculate fire rate cooldown
	@param weaponInstance table - The weapon instance
	@return number - Cooldown in seconds
]]
function BaseGun.GetFireCooldown(weaponInstance)
	local shotsPerSecond = weaponInstance.Config.FireRate.ShotsPerSecond
	return 1 / shotsPerSecond -- Convert shots per second to seconds per shot
end

--[[
	Consume ammo from the magazine
	@param weaponInstance table - The weapon instance
	@param amount number - Amount of ammo to consume (default 1)
]]
function BaseGun.ConsumeAmmo(weaponInstance, amount)
	amount = amount or 1
	weaponInstance.State.CurrentAmmo = math.max(0, weaponInstance.State.CurrentAmmo - amount)
end

--[[
	Reload the weapon (transfer ammo from reserve to magazine)
	@param weaponInstance table - The weapon instance
]]
function BaseGun.PerformReload(weaponInstance)
	local state = weaponInstance.State
	local config = weaponInstance.Config.Ammo

	-- Calculate ammo needed to fill mag
	local ammoNeeded = config.MagSize - state.CurrentAmmo

	-- Calculate ammo to transfer
	local ammoToTransfer = math.min(ammoNeeded, state.ReserveAmmo)

	-- Transfer ammo
	state.CurrentAmmo = state.CurrentAmmo + ammoToTransfer
	state.ReserveAmmo = state.ReserveAmmo - ammoToTransfer
end

return BaseGun
