--[[
	Equip.lua (_Template)

	============================================================================
	EQUIP ACTION TEMPLATE
	============================================================================

	This module handles weapon equipping logic.
	Called when the player switches to this weapon.

	KEY POINTS:
	- WeaponController already plays "Equip" animation automatically
	- WeaponController creates the viewmodel before calling this
	- Use this for weapon-specific equip behavior

	============================================================================
	ANIMATION FLOW
	============================================================================

	When player equips weapon:
	1. WeaponController:EquipWeapon() is called
	2. ViewmodelController:CreateViewmodel() creates the viewmodel
	3. ViewmodelController:PlayAnimation("Equip") plays equip anim
	4. WeaponManager:EquipWeapon() calls this Equip.Execute()

	The "Equip" animation is already playing when this function runs.
	You can add additional behavior here (sounds, effects, etc.)

	============================================================================
]]

local Equip = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

--[[
	============================================================================
	MAIN EQUIP EXECUTION
	============================================================================
]]
function Equip.Execute(weaponInstance)
	local player = weaponInstance.Player
	local config = weaponInstance.Config

	Log:Info("WEAPON", "[Template] Equipping for player: " .. player.Name)

	-- =========================================================================
	-- CUSTOM EQUIP BEHAVIOR
	-- =========================================================================

	-- NOTE: The "Equip" animation is already playing via WeaponController
	-- Add any additional equip logic here

	local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")

	if ViewmodelController then
		-- Example: Check equip animation progress
		local ViewmodelAnimator = ViewmodelController.ViewmodelAnimator
		if ViewmodelAnimator then
			local equipTrack = ViewmodelAnimator:GetTrack("Equip")
			if equipTrack then
				-- Example: Connect to keyframe for sound timing
				-- equipTrack:GetMarkerReachedSignal("DrawComplete"):Connect(function()
				--     SoundManager:PlaySound("DrawComplete")
				-- end)
			end
		end

		-- Example: Get weapon config for equip time
		local viewmodelConfig = ViewmodelController:GetCurrentConfig()
		if viewmodelConfig then
			Log:Debug("WEAPON", "[Template] Weapon weight: " .. (viewmodelConfig.Weight or 1.0))
		end
	end

	-- =========================================================================
	-- PLAY EQUIP SOUND
	-- =========================================================================

	-- SoundManager:PlaySound("Equip_" .. weaponInstance.WeaponName)

	-- =========================================================================
	-- SET EQUIPPED STATE
	-- =========================================================================

	weaponInstance.State.Equipped = true

	Log:Info("WEAPON", "[Template] Equipped successfully")
end

--[[
	============================================================================
	OPTIONAL: WAIT FOR EQUIP TO COMPLETE
	============================================================================
	Call this if you need to wait for the equip animation to finish
	before allowing other actions.
]]
function Equip.WaitForComplete(weaponInstance)
	local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")
	if not ViewmodelController then
		return
	end

	local ViewmodelAnimator = ViewmodelController.ViewmodelAnimator
	if not ViewmodelAnimator then
		return
	end

	local equipTrack = ViewmodelAnimator:GetTrack("Equip")
	if equipTrack and equipTrack.IsPlaying then
		equipTrack.Stopped:Wait()
	end
end

return Equip
