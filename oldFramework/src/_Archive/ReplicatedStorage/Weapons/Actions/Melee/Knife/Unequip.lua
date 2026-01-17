--[[
	Unequip.lua (Knife)

	Handles unequipping the Knife weapon.
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

	print("[Knife] Unequipping for player:", player.Name)

	-- TODO: Play unequip animation
	-- TODO: Remove weapon model from player's hand
	-- TODO: Play unequip sound

	-- Clear equipped state
	weaponInstance.State.Equipped = false

	-- Reset combo count
	weaponInstance.State.ComboCount = 0

	print("[Knife] Unequipped successfully")
end

return Unequip
