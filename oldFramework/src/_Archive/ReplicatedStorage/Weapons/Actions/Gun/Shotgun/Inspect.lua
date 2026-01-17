--[[
	Inspect.lua (Shotgun)

	Handles inspecting the Shotgun weapon.
]]

local Inspect = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local WeaponAnimationService = require(Locations.Modules.Weapons.Systems.WeaponAnimationService)

--[[
	Execute the inspect action
	@param weaponInstance table - The weapon instance
]]
function Inspect.Execute(weaponInstance)
	local player = weaponInstance.Player
	local state = weaponInstance.State

	-- Cannot inspect while reloading or attacking
	if state.IsReloading or state.IsAttacking then
		print("[Shotgun] Cannot inspect - busy")
		return
	end

	-- Check if already playing a blocking animation
	if WeaponAnimationService:IsBlockingAnimationPlaying() then
		print("[Shotgun] Cannot inspect - animation in progress")
		return
	end

	print("[Shotgun] Inspecting for player:", player.Name)

	-- Play inspect animation on viewmodel and character rig
	WeaponAnimationService:PlayInspectAnimation(weaponInstance)

	print("[Shotgun] Inspect started")
end

return Inspect
