--[[
	Inspect.lua (SniperRifle)

	Handles inspecting the SniperRifle weapon.
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

	-- Cannot inspect while reloading or attacking
	if state.IsReloading or state.IsAttacking then
		print("[SniperRifle] Cannot inspect - busy")
		return
	end

	print("[SniperRifle] Inspecting for player:", player.Name)

	-- TODO: Play inspect animation
	-- TODO: Temporarily disable other actions during inspect

	print("[SniperRifle] Inspect complete")
end

return Inspect
