--[[
	Inspect.lua (_Template)

	============================================================================
	INSPECT ACTION TEMPLATE
	============================================================================

	This module handles weapon inspection logic.
	Called when the player presses the inspect key.

	KEY POINTS:
	- Plays the "Inspect" animation on the viewmodel
	- Can be cancelled by other actions

	============================================================================
]]

local Inspect = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

--[[
	============================================================================
	MAIN INSPECT EXECUTION
	============================================================================
]]
function Inspect.Execute(weaponInstance)
	local state = weaponInstance.State

	-- Don't inspect while reloading or attacking
	if state.IsReloading or state.IsAttacking then
		Log:Debug("WEAPON", "[Template] Cannot inspect - busy")
		return
	end

	Log:Info("WEAPON", "[Template] Inspecting weapon")

	-- =========================================================================
	-- PLAY INSPECT ANIMATION
	-- =========================================================================

	local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")

	if ViewmodelController then
		-- Play the inspect animation
		ViewmodelController:PlayAnimation("Inspect")

		-- Example: Wait for inspect to complete before allowing other actions
		-- local ViewmodelAnimator = ViewmodelController.ViewmodelAnimator
		-- if ViewmodelAnimator then
		--     local inspectTrack = ViewmodelAnimator:GetTrack("Inspect")
		--     if inspectTrack then
		--         inspectTrack.Stopped:Wait()
		--     end
		-- end
	end
end

--[[
	============================================================================
	CANCEL INSPECT
	============================================================================
	Call this if you need to cancel an in-progress inspect
	(e.g., when player fires or reloads)
]]
function Inspect.Cancel()
	local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")
	if ViewmodelController then
		ViewmodelController:StopAnimation("Inspect")
		Log:Debug("WEAPON", "[Template] Inspect cancelled")
	end
end

--[[
	============================================================================
	CHECK IF INSPECTING
	============================================================================
]]
function Inspect.IsInspecting()
	local ViewmodelController = ServiceRegistry:GetController("ViewmodelController")
	if ViewmodelController and ViewmodelController.ViewmodelAnimator then
		return ViewmodelController.ViewmodelAnimator:IsPlaying("Inspect")
	end
	return false
end

return Inspect
