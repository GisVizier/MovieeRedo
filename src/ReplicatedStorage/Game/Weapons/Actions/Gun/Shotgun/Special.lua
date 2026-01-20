--[[
	Special.lua (Shotgun - ADS)

	Handles Aim Down Sights for the Shotgun.
	Aligns viewmodel to aim attachment and adjusts FOV.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))

local Special = {}
Special._isADS = false
Special._resetOffset = nil
Special._originalFOV = nil
Special._adsBlend = 0  -- Blend factor: 0 = hip, 1 = fully ADS
Special._adsAttachment = nil
Special._rig = nil

function Special.Execute(weaponInstance, isPressed)
	if not weaponInstance then
		return false, "InvalidInstance"
	end

	-- TODO: Check player settings for toggle vs hold ADS
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

	if not adsAttachment then
		return
	end

	-- Store references for the blend function
	Special._rig = rig
	Special._adsAttachment = adsAttachment
	Special._adsBlend = 0  -- Start at 0, will blend toward 1

	local config = weaponInstance.Config
	local adsFOV = config and config.adsFOV

	-- Set up the alignment override with smooth blending
	Special._resetOffset = viewmodelController:updateTargetCF(function(normalAlign)
		if not Special._adsAttachment or not Special._rig then
			return normalAlign
		end

		-- Compute ADS alignment
		local adsAlign = Special._rig.Model:GetPivot():ToObjectSpace(Special._adsAttachment.WorldCFrame):Inverse()

		-- Smoothly increase blend toward 1 when ADS is active
		if Special._isADS then
			Special._adsBlend = Special._adsBlend + (1 - Special._adsBlend) * 0.12
		else
			-- Smoothly decrease blend toward 0 when exiting ADS
			Special._adsBlend = Special._adsBlend * 0.88
		end

		-- Lerp between normal and ADS alignment
		return normalAlign:Lerp(adsAlign, Special._adsBlend)
	end)

	-- Set ADS FOV
	if adsFOV then
		Special._originalFOV = FOVController.BaseFOV
		FOVController:SetBaseFOV(adsFOV)
	end

	-- Apply ADS speed multiplier
	local adsSpeedMult = config and config.adsSpeedMultiplier or 0.7
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(adsSpeedMult)
	end

	-- Play ADS animation if exists
	if weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack("ADS", 0.15)
	end
end

function Special:_exitADS(weaponInstance)
	-- Don't immediately clear the override - let it blend out
	-- The blend function checks Special._isADS and will blend toward 0
	
	-- Reset FOV
	if Special._originalFOV then
		FOVController:SetBaseFOV(Special._originalFOV)
		Special._originalFOV = nil
	end

	-- Reset ADS speed multiplier
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(1.0)
	end

	-- Play hip animation if exists
	if weaponInstance and weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack("Hip", 0.15)
	end

	-- Clear override after a delay to allow blend out
	task.delay(0.3, function()
		if not Special._isADS and Special._resetOffset then
			Special._resetOffset()
			Special._resetOffset = nil
			Special._rig = nil
			Special._adsAttachment = nil
			Special._adsBlend = 0
		end
	end)
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
