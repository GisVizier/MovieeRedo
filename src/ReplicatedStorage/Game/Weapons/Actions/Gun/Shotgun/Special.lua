local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))

local Special = {}
Special._isADS = false
Special._originalFOV = nil
<<<<<<< HEAD
=======
Special._adsBlend = 0 -- Blend factor: 0 = hip, 1 = fully ADS
Special._rig = nil
Special._aimPosition = nil -- Eye position attachment (where camera should be)
Special._aimLookAt = nil -- Look target attachment (what to look at)
>>>>>>> b930847 (hitbox mvp)

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

<<<<<<< HEAD
=======
	local rig = viewmodelController:GetActiveRig()
	if not rig or not rig.Model then
		return
	end

	-- Find the two ADS attachments (inside Parts/Primary)
	-- AimPosition = where the eye/camera should be
	-- AimLookAt = what to look at (front sight, target point)
	local partsFolder = rig.Model:FindFirstChild("Parts", true)
	local gunPart = partsFolder and partsFolder:FindFirstChild("Primary")
	local aimPosition = gunPart and gunPart:FindFirstChild("AimPosition")
	local aimLookAt = gunPart and gunPart:FindFirstChild("AimLookAt")

	if not aimPosition or not aimLookAt then
		warn("[ADS] Missing AimPosition or AimLookAt attachments")
		return
	end

	-- Store references to attachments (live tracking, not frozen)
	Special._rig = rig
	Special._aimPosition = aimPosition
	Special._aimLookAt = aimLookAt
	Special._adsBlend = 0 -- Start at 0, will blend toward 1

>>>>>>> b930847 (hitbox mvp)
	local config = weaponInstance.Config
	local adsFOV = config and config.adsFOV
	local adsEffectsMultiplier = config and config.adsEffectsMultiplier or 0.25

	viewmodelController:SetADS(true, adsEffectsMultiplier)

<<<<<<< HEAD
=======
		-- Compute ADS alignment using lookAt with a stable up vector to avoid roll/spin.
		local eyePos = Special._aimPosition.WorldPosition
		local lookAtPos = Special._aimLookAt.WorldPosition
		local cam = workspace.CurrentCamera
		local dir = lookAtPos - eyePos
		local adsLookCFrame
		if cam and dir.Magnitude > 1e-4 then
			adsLookCFrame = CFrame.lookAt(eyePos, lookAtPos, cam.CFrame.UpVector)
		elseif cam then
			adsLookCFrame = CFrame.new(eyePos, eyePos + cam.CFrame.LookVector)
		else
			adsLookCFrame = CFrame.new(eyePos, eyePos + Vector3.new(0, 0, -1))
		end
		local adsAlign = Special._rig.Model:GetPivot():ToObjectSpace(adsLookCFrame):Inverse()

		-- Smoothly adjust blend factor
		if Special._isADS then
			-- Blend toward 1 when ADS active
			Special._adsBlend = Special._adsBlend + (1 - Special._adsBlend) * 0.12
		else
			-- Blend toward 0 when exiting ADS
			Special._adsBlend = Special._adsBlend * 0.88
		end

		-- Return ADS alignment, blend factor, and effects multiplier
		-- ViewmodelController applies local roll for tilt
		return {
			align = adsAlign,
			blend = Special._adsBlend,
			effectsMultiplier = adsEffectsMultiplier,
		}
	end)

	-- Set ADS FOV
>>>>>>> b930847 (hitbox mvp)
	if adsFOV then
		Special._originalFOV = FOVController.BaseFOV
		FOVController:SetBaseFOV(adsFOV)
	end

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
<<<<<<< HEAD
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if viewmodelController then
		viewmodelController:SetADS(false)
	end

=======
	-- Don't immediately clear the override - let it blend out
	-- The blend function checks Special._isADS and will blend toward 0

	-- Reset FOV
>>>>>>> b930847 (hitbox mvp)
	if Special._originalFOV then
		FOVController:SetBaseFOV(Special._originalFOV)
		Special._originalFOV = nil
	end

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
