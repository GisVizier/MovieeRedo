--[[
	Reload.lua (Shotgun)

	Handles reloading the Shotgun weapon.
]]

local Reload = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)
local WeaponAnimationService = require(Locations.Modules.Weapons.Systems.WeaponAnimationService)

--[[
	Execute the reload action
	@param weaponInstance table - The weapon instance
]]
function Reload.Execute(weaponInstance)
	local player = weaponInstance.Player
	local config = weaponInstance.Config
	local state = weaponInstance.State

	-- Check if can reload
	if not BaseGun.CanReload(weaponInstance) then
		print("[Shotgun] Cannot reload - conditions not met")
		return
	end

	print("[Shotgun] Reloading for player:", player.Name)
	print("[Shotgun] Current ammo:", state.CurrentAmmo, "Reserve:", state.ReserveAmmo)

	-- Set reloading state
	state.IsReloading = true

	-- Play reload animation on viewmodel and character rig
	local animDuration = WeaponAnimationService:PlayReloadAnimation(weaponInstance)

	-- TODO: Play reload sound

	-- Wait for animation to complete (use animation duration or config reload time, whichever is longer)
	local waitTime = math.max(animDuration, config.Ammo.ReloadTime)
	task.wait(waitTime)

	-- Perform the reload (transfer ammo from reserve to magazine)
	BaseGun.PerformReload(weaponInstance)

	-- Clear reloading state
	state.IsReloading = false

	print("[Shotgun] Reload complete. Ammo:", state.CurrentAmmo, "/", config.Ammo.MagSize, "Reserve:", state.ReserveAmmo)
end

return Reload
