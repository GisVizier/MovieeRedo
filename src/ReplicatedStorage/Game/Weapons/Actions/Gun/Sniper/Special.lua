local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))

local Special = {}
Special._isADS = false
local ADS_TRACK_FADE = 0.03
local ADS_TRACK_SPEED = 1.8

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
		if (isPressed and Special._isADS) or ((not isPressed) and (not Special._isADS)) then
			return true
		end
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
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return
	end

	local config = weaponInstance.Config
	local adsFOV = config and config.adsFOV
	local adsEffectsMultiplier = config and config.adsEffectsMultiplier or 0.15

	viewmodelController:SetADS(true, adsEffectsMultiplier)
	FOVController:SetADSState(true, adsFOV)

	local adsSpeedMult = config and config.adsSpeedMultiplier or 0.5
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(adsSpeedMult)
	end

	if weaponInstance.PlayWeaponTrack then
		local adsTrack = weaponInstance.PlayWeaponTrack("ADS", ADS_TRACK_FADE)
		if not adsTrack then
			adsTrack = weaponInstance.PlayWeaponTrack("Aim", ADS_TRACK_FADE)
		end
		if not adsTrack then
			adsTrack = weaponInstance.PlayWeaponTrack("Idle", ADS_TRACK_FADE)
		end
		if adsTrack then
			pcall(function()
				adsTrack.Looped = true
				adsTrack.TimePosition = 0
			end)
			if adsTrack.AdjustSpeed then
				local trackSpeed = ADS_TRACK_SPEED
				local targetDuration = config and tonumber(config.adsAnimationDuration)
				local trackLength = tonumber(adsTrack.Length)
				if targetDuration and targetDuration > 0 and trackLength and trackLength > 0 then
					trackSpeed = math.max(trackLength / targetDuration, 0.01)
				end
				adsTrack:AdjustSpeed(trackSpeed)
			end
		end
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
		local hipTrack = weaponInstance.PlayWeaponTrack("Hip", ADS_TRACK_FADE)
		if not hipTrack then
			hipTrack = weaponInstance.PlayWeaponTrack("Idle", ADS_TRACK_FADE)
		end
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
