--[[
	Reload.lua (Revolver)

	Handles reloading the Revolver weapon.
]]

local Reload = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)

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
		print("[Revolver] Cannot reload - conditions not met")
		return
	end

	print("[Revolver] Reloading for player:", player.Name)
	print("[Revolver] Current ammo:", state.CurrentAmmo, "Reserve:", state.ReserveAmmo)

	-- Set reloading state
	state.IsReloading = true

	-- TODO: Play reload animation
	-- TODO: Play reload sound

	-- Simulate reload time
	task.wait(config.Ammo.ReloadTime)

	-- Perform the reload (transfer ammo from reserve to magazine)
	BaseGun.PerformReload(weaponInstance)

	-- Clear reloading state
	state.IsReloading = false

	print("[Revolver] Reload complete. Ammo:", state.CurrentAmmo, "/", config.Ammo.MagSize, "Reserve:", state.ReserveAmmo)
end

return Reload
