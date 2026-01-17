--[[
	Unequip.lua (AssaultRifle)

	Handles unequipping the AssaultRifle weapon.
]]

local Unequip = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)

--[[
	Execute the unequip action
	@param weaponInstance table - The weapon instance
]]
function Unequip.Execute(weaponInstance)
	local player = weaponInstance.Player
	local config = weaponInstance.Config

	print("[AssaultRifle] Unequipping for player:", player.Name)

	-- TODO: Play unequip animation
	-- TODO: Remove weapon model from player's hand
	-- TODO: Play unequip sound

	-- Clear equipped state
	weaponInstance.State.Equipped = false

	print("[AssaultRifle] Unequipped successfully")
end

return Unequip
