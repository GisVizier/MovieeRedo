local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local Inspect = {}
Inspect._isInspecting = false
Inspect._activeWeaponInstance = nil
local INSPECT2_CHANCE = 0.10
local rng = Random.new()

local function chooseInspectTrackName()
	if rng:NextNumber() < INSPECT2_CHANCE then
		return "Inspect2"
	end
	return "Inspect"
end

function Inspect.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false, "InvalidInstance"
	end

	if Inspect._isInspecting then
		Inspect.Cancel()
		return true
	end

	local state = weaponInstance.State
	if state.IsReloading or state.IsAttacking then
		return false, "Busy"
	end

	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return false, "NoViewmodel"
	end
	if viewmodelController.IsADS and viewmodelController:IsADS() then
		return false, "Busy"
	end

	local animator = viewmodelController._animator
	if animator and type(animator.Stop) == "function" then
		animator:Stop("Inspect", 0.05)
		animator:Stop("Inspect2", 0.05)
	end

	Inspect._isInspecting = true
	Inspect._activeWeaponInstance = weaponInstance

	local trackName = chooseInspectTrackName()
	local track = viewmodelController:PlayWeaponTrack(trackName, 0.1)
	if not track and trackName ~= "Inspect" then
		track = viewmodelController:PlayWeaponTrack("Inspect", 0.1)
		trackName = "Inspect"
	end
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound(trackName)
	end
	local function onComplete()
		Inspect._isInspecting = false
		Inspect._activeWeaponInstance = nil
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
	local weaponInstance = Inspect._activeWeaponInstance
	Inspect._activeWeaponInstance = nil

	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return
	end

	viewmodelController:SetOffset(CFrame.new())

	local animator = viewmodelController._animator
	if animator and type(animator.Stop) == "function" then
		animator:Stop("Inspect", 0.1)
		animator:Stop("Inspect2", 0.1)
	end

	if weaponInstance and weaponInstance.StopActionSound then
		weaponInstance.StopActionSound("Inspect")
		weaponInstance.StopActionSound("Inspect2")
	end
end

function Inspect.IsInspecting()
	return Inspect._isInspecting
end

return Inspect
