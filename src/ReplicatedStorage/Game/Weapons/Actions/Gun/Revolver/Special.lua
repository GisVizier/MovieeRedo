--[[
	Special.lua (Revolver - ADS)

	Handles Aim Down Sights for the Revolver.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))

local Special = {}
Special._isADS = false
Special._resetOffset = nil
Special._originalFOV = nil

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
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return
	end

	local rig = viewmodelController:GetActiveRig()
	if not rig or not rig.Model then
		return
	end

	-- Find the aim attachment
	local partsFolder = rig.Model:FindFirstChild("Parts", true)
	local gunContent = partsFolder and partsFolder:FindFirstChild("Primary")
	local adsAttachment = gunContent and gunContent:FindFirstChild("Aim")

	local config = weaponInstance.Config
	local adsFOV = config and config.adsFOV
	
	-- ADS alignment - aligns attachment to camera center with smooth transition
	if adsAttachment then
		Special._resetOffset = viewmodelController:SetAlignmentOverride(function()
			return rig.Model:GetPivot():ToObjectSpace(adsAttachment.WorldCFrame):Inverse()
		end)
	end
	
	if adsFOV then
		Special._originalFOV = FOVController.BaseFOV
		FOVController:SetBaseFOV(adsFOV)
	end

	-- Apply ADS speed multiplier
	local adsSpeedMult = config and config.adsSpeedMultiplier or 0.75
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(adsSpeedMult)
	end

	if weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack("ADS", 0.15)
	end
end

function Special:_exitADS(weaponInstance)
	if Special._resetOffset then
		Special._resetOffset()
		Special._resetOffset = nil
	end

	if Special._originalFOV then
		FOVController:SetBaseFOV(Special._originalFOV)
		Special._originalFOV = nil
	end

	-- Reset ADS speed multiplier
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(1.0)
	end

	if weaponInstance and weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack("Hip", 0.15)
	end
end

function Special.Cancel()
	if not Special._isADS then
		return
	end

	Special._isADS = false
	Special:_exitADS(nil)
end

function Special.IsActive()
	return Special._isADS
end

return Special
