local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))
local Inspect = require(script.Parent:WaitForChild("Inspect"))

local Special = {}
Special._isADS = false

function Special.Execute(weaponInstance, isPressed)
	if not weaponInstance then
		return false, "InvalidInstance"
	end

	local isToggle = false

	if isToggle then
		if isPressed then
			Special._isADS = not Special._isADS
		else
			return true
		end
	else
		Special._isADS = isPressed
	end

	if Special._isADS then
		Special:_enterADS(weaponInstance)
	else
		Special:_exitADS(weaponInstance)
	end

	return true
end

function Special:_enterADS(weaponInstance)
	Inspect.Cancel()

	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return
	end

	local config = weaponInstance.Config
	local adsFOV = config and config.adsFOV
	local adsEffectsMultiplier = config and config.adsEffectsMultiplier or 0.25

	viewmodelController:SetADS(true, adsEffectsMultiplier)
	FOVController:SetADSState(true, adsFOV)

	local adsSpeedMult = config and config.adsSpeedMultiplier or 0.7
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(adsSpeedMult)
	end

	if weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack("ADS", 0.15)
	end
	if weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound("AimIn")
	end
end

function Special:_exitADS(weaponInstance)
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if viewmodelController then
		viewmodelController:SetADS(false)
	end
	FOVController:SetADSState(false)

	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(1.0)
	end

	if weaponInstance and weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack("Hip", 0.15)
	end
	if weaponInstance and weaponInstance.PlayActionSound then
		weaponInstance.PlayActionSound("AimOut")
	end
end

function Special.Cancel()
	local shouldExitADS = Special._isADS
	if not shouldExitADS then
		return
	end

	Special._isADS = false
	Special:_exitADS(nil)
end

function Special.IsActive()
	return Special._isADS
end

return Special
