--[[
	Attack.lua (Revolver)

	Client-side attack checks + ammo consumption.
	Semi-automatic fire mode.
	
	Uses the PROJECTILE SYSTEM for bullet physics.
	Single accurate bullet with slight drop at range.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Inspect = require(script.Parent:WaitForChild("Inspect"))

-- Lazy-loaded projectile service
local WeaponProjectile
local function getWeaponProjectile()
	if not WeaponProjectile then
		local Controllers = Players.LocalPlayer
			:WaitForChild("PlayerScripts")
			:WaitForChild("Initializer")
			:WaitForChild("Controllers")
		local WeaponServices = Controllers:WaitForChild("Weapon"):WaitForChild("Services")
		WeaponProjectile = require(WeaponServices:WaitForChild("WeaponProjectile"))
	end
	return WeaponProjectile
end

local Attack = {}

function Attack.Execute(weaponInstance, currentTime)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	Inspect.Cancel()

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local now = currentTime or workspace:GetServerTimeNow()

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

	-- Fire single projectile
	local projectileService = getWeaponProjectile()
	
	if not projectileService then
		return false, "ServiceNotFound"
	end
	
	-- Initialize if needed
	if not projectileService._initialized and weaponInstance.Net then
		projectileService:Init(weaponInstance.Net)
		projectileService._initialized = true
	end
	
	-- Fire single bullet
	local projectileId = projectileService:Fire(weaponInstance, {})
	
	if not projectileId then
		return false, "FireFailed"
	end

	-- Play fire effects (muzzle flash, sound, etc.)
	if weaponInstance.PlayFireEffects then
		weaponInstance.PlayFireEffects({
			origin = workspace.CurrentCamera.CFrame.Position,
		})
	end

	return true
end

return Attack
