--[[
	Equip.lua (Knife)

	Handles equipping the Knife weapon.
]]

local Equip = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)

--[[
	Execute the equip action
	@param weaponInstance table - The weapon instance
]]
function Equip.Execute(weaponInstance)
	local player = weaponInstance.Player
	local config = weaponInstance.Config

	print("[Knife] Equipping for player:", player.Name)

	-- TODO: Play equip animation
	-- TODO: Spawn weapon model in player's hand
	-- TODO: Play equip sound

	-- Set equipped state
	weaponInstance.State.Equipped = true

	print("[Knife] Equipped successfully")
end

return Equip
