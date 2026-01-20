--[[
	Special.lua (AssaultRifle - ADS)

	Handles Aim Down Sights for the AssaultRifle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

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

	local gunContent = rig.Model:FindFirstChild("Primary", true)
	local adsAttachment = gunContent and gunContent:FindFirstChild("Aim")

	if adsAttachment then
		local adsOffset = rig.Model:GetPivot():ToObjectSpace(adsAttachment.WorldCFrame):Inverse()
		Special._resetOffset = viewmodelController:SetOffset(adsOffset)
	end

	local config = weaponInstance.Config
	local adsFOV = config and config.adsFOV
	if adsFOV then
		local cameraController = ServiceRegistry:GetController("Camera")
		if cameraController and cameraController.SetFOV then
			Special._originalFOV = workspace.CurrentCamera.FieldOfView
			cameraController:SetFOV(adsFOV)
		else
			Special._originalFOV = workspace.CurrentCamera.FieldOfView
			workspace.CurrentCamera.FieldOfView = adsFOV
		end
	end

	-- Apply ADS speed multiplier
	local adsSpeedMult = config and config.adsSpeedMultiplier or 0.7
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
		local cameraController = ServiceRegistry:GetController("Camera")
		if cameraController and cameraController.ResetFOV then
			cameraController:ResetFOV()
		else
			workspace.CurrentCamera.FieldOfView = Special._originalFOV
		end
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
