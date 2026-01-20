--[[
	Inspect.lua (AssaultRifle)

	Client-side inspect with viewmodel offset.
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

	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return false, "NoViewmodel"
	end

	Inspect._isInspecting = true

	local resetOffset = viewmodelController:SetOffset(
		CFrame.new(0.15, -0.05, -0.2) * CFrame.Angles(math.rad(15), math.rad(-20), 0)
	)

	local track = viewmodelController:PlayWeaponTrack("Inspect", 0.1)

	local function onComplete()
		Inspect._isInspecting = false
		if resetOffset then
			resetOffset()
		end
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

	viewmodelController:SetOffset(CFrame.new())

	local animator = viewmodelController._animator
	if animator and type(animator.Stop) == "function" then
		animator:Stop("Inspect", 0.1)
	end
end

function Inspect.IsInspecting()
	return Inspect._isInspecting
end

return Inspect
