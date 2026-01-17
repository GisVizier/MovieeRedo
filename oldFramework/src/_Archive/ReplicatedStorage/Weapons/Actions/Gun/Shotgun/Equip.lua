--[[
	Equip.lua (Shotgun)

	Handles equipping the Shotgun weapon.
]]

local Equip = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local WeaponAnimationService = require(Locations.Modules.Weapons.Systems.WeaponAnimationService)

--[[
	Execute the equip action
	@param weaponInstance table - The weapon instance
]]
function Equip.Execute(weaponInstance)
	local player = weaponInstance.Player

	print("[Shotgun] Equipping for player:", player.Name)

	-- Play equip animation on viewmodel and character rig
	-- This also sets up character animations for the weapon
	WeaponAnimationService:PlayEquipAnimation(weaponInstance)

	-- TODO: Spawn weapon model in player's hand (3rd-person weapon welding)
	-- TODO: Play equip sound

	-- Set equipped state
	weaponInstance.State.Equipped = true

	print("[Shotgun] Equipped successfully")
end

return Equip
