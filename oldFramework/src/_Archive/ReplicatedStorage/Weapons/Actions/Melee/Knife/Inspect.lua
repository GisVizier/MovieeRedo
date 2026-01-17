--[[
	Inspect.lua (Knife)

	Handles inspecting the Knife weapon.
]]

local Inspect = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)

--[[
	Execute the inspect action
	@param weaponInstance table - The weapon instance
]]
function Inspect.Execute(weaponInstance)
	local player = weaponInstance.Player
	local config = weaponInstance.Config
	local state = weaponInstance.State

	-- Cannot inspect while attacking
	if state.IsAttacking then
		print("[Knife] Cannot inspect - busy")
		return
	end

	print("[Knife] Inspecting for player:", player.Name)

	-- TODO: Play inspect animation (knife flip, twirl, etc.)
	-- TODO: Temporarily disable other actions during inspect

	print("[Knife] Inspect complete")
end

return Inspect
