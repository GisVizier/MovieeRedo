--[[
	Reload.lua (_Template)

	============================================================================
	RELOAD ACTION TEMPLATE
	============================================================================

	This module handles weapon reloading logic.
	Called when the player presses the reload key.

	KEY POINTS:
	- WeaponController already plays "Reload" animation automatically
	- Use task.wait() or animation signals for timing
	- BaseGun.PerformReload() handles ammo transfer

	============================================================================
	ANIMATION FLOW
	============================================================================

	When player reloads:
	1. WeaponController:ReloadWeapon() is called
	2. WeaponManager:ReloadWeapon() calls this Reload.Execute()
	3. WeaponController plays "Reload" animation automatically

	The timing of ammo refill should match the animation keyframes.
	Use animation markers or task.wait(reloadTime) for synchronization.

	============================================================================
]]

local Reload = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

--[[
	============================================================================
	MAIN RELOAD EXECUTION
	============================================================================
]]
function Reload.Execute(weaponInstance)
	local player = weaponInstance.Player
	local config = weaponInstance.Config
	local state = weaponInstance.State

	-- Check if can reload
	if not BaseGun.CanReload(weaponInstance) then
		Log:Debug("WEAPON", "[Template] Cannot reload - conditions not met")
		return
	end

	Log:Info("WEAPON", "[Template] Reloading for player: " .. player.Name)
	Log:Debug("WEAPON", "[Template] Current ammo: " .. state.CurrentAmmo .. " Reserve: " .. state.ReserveAmmo)

	-- Set reloading state
	state.IsReloading = true

	-- =========================================================================
	-- VIEWMODEL ANIMATION INTEGRATION
	-- =========================================================================

	local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")

	if ViewmodelController then
		-- NOTE: The "Reload" animation is already playing via WeaponController

		-- Example: Connect to animation keyframes for sound timing
		local ViewmodelAnimator = ViewmodelController.ViewmodelAnimator
		if ViewmodelAnimator then
			local reloadTrack = ViewmodelAnimator:GetTrack("Reload")
			if reloadTrack then
				-- Example: Play magazine out sound at keyframe
				-- local magOutConnection = reloadTrack:GetMarkerReachedSignal("MagOut"):Connect(function()
				--     SoundManager:PlaySound("MagOut")
				-- end)

				-- Example: Play magazine in sound at keyframe
				-- local magInConnection = reloadTrack:GetMarkerReachedSignal("MagIn"):Connect(function()
				--     SoundManager:PlaySound("MagIn")
				-- end)

				-- Example: Play bolt release sound at keyframe
				-- local boltConnection = reloadTrack:GetMarkerReachedSignal("BoltRelease"):Connect(function()
				--     SoundManager:PlaySound("BoltRelease")
				-- end)
			end
		end
	end

	-- =========================================================================
	-- WAIT FOR RELOAD TO COMPLETE
	-- =========================================================================

	-- Option 1: Wait for configured reload time
	task.wait(config.Ammo.ReloadTime)

	-- Option 2: Wait for animation to finish (more precise)
	-- if ViewmodelController then
	--     local ViewmodelAnimator = ViewmodelController.ViewmodelAnimator
	--     if ViewmodelAnimator then
	--         local reloadTrack = ViewmodelAnimator:GetTrack("Reload")
	--         if reloadTrack and reloadTrack.IsPlaying then
	--             reloadTrack.Stopped:Wait()
	--         end
	--     end
	-- end

	-- =========================================================================
	-- PERFORM AMMO TRANSFER
	-- =========================================================================

	-- Check if reload was cancelled
	if not state.IsReloading then
		Log:Debug("WEAPON", "[Template] Reload cancelled")
		return
	end

	-- Transfer ammo from reserve to magazine
	BaseGun.PerformReload(weaponInstance)

	-- =========================================================================
	-- CLEANUP
	-- =========================================================================

	state.IsReloading = false

	Log:Info("WEAPON", "[Template] Reload complete", {
		Ammo = state.CurrentAmmo .. "/" .. config.Ammo.MagSize,
		Reserve = state.ReserveAmmo,
	})
end

--[[
	============================================================================
	CANCEL RELOAD
	============================================================================
	Call this if you need to cancel an in-progress reload
	(e.g., when player sprints or takes damage)
]]
function Reload.Cancel(weaponInstance)
	if weaponInstance.State.IsReloading then
		weaponInstance.State.IsReloading = false

		local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")
		if ViewmodelController then
			ViewmodelController:StopAnimation("Reload")
		end

		Log:Debug("WEAPON", "[Template] Reload cancelled")
	end
end

return Reload
