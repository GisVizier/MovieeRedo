--[[
	Special.lua (Shotgun - ADS)

	Handles Aim Down Sights for the Shotgun.
	Aligns viewmodel to aim attachment and adjusts FOV.
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

	-- TODO: Check player settings for toggle vs hold ADS
	-- For now, treat as hold (isPressed = true means ADS, false means hip)
	local isToggle = false -- Will be from player settings later

	if isToggle then
		if isPressed then
			Special._isADS = not Special._isADS
		else
			return true -- Ignore release in toggle mode
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
	-- Structure: rig.Model -> Primary (gun content) -> Aim (attachment)
	local gunContent = rig.Model:FindFirstChild("Primary", true)
	local adsAttachment = gunContent and gunContent:FindFirstChild("Aim")

	if adsAttachment then
		-- Calculate offset to align aim attachment with camera center
		local adsOffset = rig.Model:GetPivot():ToObjectSpace(adsAttachment.WorldCFrame):Inverse()
		Special._resetOffset = viewmodelController:SetOffset(adsOffset)
	end

	-- Reduce FOV
	local config = weaponInstance.Config
	local adsFOV = config and config.adsFOV
	if adsFOV then
		local cameraController = ServiceRegistry:GetController("Camera")
		if cameraController and cameraController.SetFOV then
			Special._originalFOV = workspace.CurrentCamera.FieldOfView
			cameraController:SetFOV(adsFOV)
		else
			-- Fallback: directly set FOV
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

	-- Play ADS animation if exists
	if weaponInstance.PlayWeaponTrack then
		weaponInstance.PlayWeaponTrack("ADS", 0.15)
	end
end

function Special:_exitADS(weaponInstance)
	-- Reset viewmodel offset
	if Special._resetOffset then
		Special._resetOffset()
		Special._resetOffset = nil
	end

	-- Reset FOV
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

	-- Play hip animation if exists
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
