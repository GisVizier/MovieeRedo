--[[
	Unequip.lua (Revolver)

	Handles unequipping the Revolver weapon.
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

	print("[Revolver] Unequipping for player:", player.Name)

	-- TODO: Play unequip animation
	-- TODO: Remove weapon model from player's hand
	-- TODO: Play unequip sound

	-- Clear equipped state
	weaponInstance.State.Equipped = false

	print("[Revolver] Unequipped successfully")
end

return Unequip
