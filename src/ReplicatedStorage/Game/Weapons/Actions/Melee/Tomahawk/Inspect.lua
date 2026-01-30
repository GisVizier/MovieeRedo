--[[
	Inspect.lua (Tomahawk)

	Client-side inspect - animation only, no viewmodel offset.
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
	if state.IsAttacking then
		return false, "Busy"
	end

	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return false, "NoViewmodel"
	end

	Inspect._isInspecting = true

	-- Play inspect animation (no offset for melee)
	local track = viewmodelController:PlayWeaponTrack("Inspect", 0.1)

	local function onComplete()
		Inspect._isInspecting = false
	end

	if track then
		track.Stopped:Once(onComplete)
	else
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
