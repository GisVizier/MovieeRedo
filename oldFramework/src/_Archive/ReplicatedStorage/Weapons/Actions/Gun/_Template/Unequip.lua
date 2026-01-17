--[[
	Unequip.lua (_Template)

	============================================================================
	UNEQUIP ACTION TEMPLATE
	============================================================================

	This module handles weapon unequipping logic.
	Called when the player switches away from this weapon.

	KEY POINTS:
	- The viewmodel will be destroyed after this runs
	- Use this for cleanup and unequip effects

	============================================================================
]]

local Unequip = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

--[[
	============================================================================
	MAIN UNEQUIP EXECUTION
	============================================================================
]]
function Unequip.Execute(weaponInstance)
	local player = weaponInstance.Player

	Log:Info("WEAPON", "[Template] Unequipping for player: " .. player.Name)

	-- =========================================================================
	-- CUSTOM UNEQUIP BEHAVIOR
	-- =========================================================================

	local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")

	if ViewmodelController then
		-- Example: Play unequip/holster animation before destroying
		-- ViewmodelController:PlayAnimation("Unequip")
		-- task.wait(0.3) -- Wait for animation

		-- Example: Stop any ongoing animations
		ViewmodelController:StopAnimation("ADS")
		ViewmodelController:StopAnimation("Reload")
	end

	-- =========================================================================
	-- PLAY UNEQUIP SOUND
	-- =========================================================================

	-- SoundManager:PlaySound("Unequip_" .. weaponInstance.WeaponName)

	-- =========================================================================
	-- CLEANUP STATE
	-- =========================================================================

	weaponInstance.State.Equipped = false
	weaponInstance.State.IsReloading = false
	weaponInstance.State.IsAttacking = false

	Log:Info("WEAPON", "[Template] Unequipped successfully")
end

return Unequip
