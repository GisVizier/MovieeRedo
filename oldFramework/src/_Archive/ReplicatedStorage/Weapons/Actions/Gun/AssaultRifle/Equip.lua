--[[
	Equip.lua (AssaultRifle)

	Handles equipping the AssaultRifle weapon.
]]

local Equip = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)

--[[
	Execute the equip action
	@param weaponInstance table - The weapon instance
]]
function Equip.Execute(weaponInstance)
	local player = weaponInstance.Player
	local config = weaponInstance.Config

	print("[AssaultRifle] Equipping for player:", player.Name)

	-- TODO: Play equip animation
	-- TODO: Spawn weapon model in player's hand
	-- TODO: Play equip sound

	-- Set equipped state
	weaponInstance.State.Equipped = true

	print("[AssaultRifle] Equipped successfully")
end

return Equip
