--[[
	Unequip.lua (Shotgun)

	Handles unequipping the Shotgun weapon.
]]

local Unequip = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local WeaponAnimationService = require(Locations.Modules.Weapons.Systems.WeaponAnimationService)

--[[
	Execute the unequip action
	@param weaponInstance table - The weapon instance
]]
function Unequip.Execute(weaponInstance)
	local player = weaponInstance.Player

	print("[Shotgun] Unequipping for player:", player.Name)

	-- Stop all character animations and cleanup
	WeaponAnimationService:PlayUnequipAnimation(weaponInstance)

	-- TODO: Remove weapon model from player's hand (3rd-person weapon)
	-- TODO: Play unequip sound

	-- Clear equipped state
	weaponInstance.State.Equipped = false

	print("[Shotgun] Unequipped successfully")
end

return Unequip
