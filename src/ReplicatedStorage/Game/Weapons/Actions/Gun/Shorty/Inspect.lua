--[[
	Inspect.lua

	Client-side inspect gating only.
	No viewmodel, VFX, or networking here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local Inspect = {}
Inspect._isInspecting = false

function Inspect.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	if state.IsReloading or state.IsAttacking then
		return false, "Busy"
	end

	-- Get viewmodel controller for offset and animation
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return false, "NoViewmodel"
	end
	if viewmodelController.IsADS and viewmodelController:IsADS() then
		return false, "Busy"
	end

	Inspect._isInspecting = true

	-- Play inspect animation and get track back
	local track = viewmodelController:PlayWeaponTrack("Inspect", 0.1)
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound("Inspect")
	end

	-- Reset offset when animation ends
	local function onComplete()
		Inspect._isInspecting = false
	end

	if track then
		track.Stopped:Once(onComplete)
	else
		-- No track found, reset after a delay
		task.delay(2, onComplete)
	end

	return true
end

function Inspect.Cancel()
	if not Inspect._isInspecting then
		return
	end

	Inspect._isInspecting = false

	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return
	end

	-- Reset offset back to normal
	viewmodelController:SetOffset(CFrame.new())

	-- Stop inspect animation
	local animator = viewmodelController._animator
	if animator and type(animator.Stop) == "function" then
		animator:Stop("Inspect", 0.1)
	end
end

function Inspect.IsInspecting()
	return Inspect._isInspecting
end

return Inspect
