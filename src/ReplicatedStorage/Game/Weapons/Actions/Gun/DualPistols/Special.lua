local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))

local Inspect = require(script.Parent:WaitForChild("Inspect"))
local DualPistolsState = require(script.Parent:WaitForChild("State"))

local Special = {}
Special._isADS = false
Special._originalFOV = nil
Special._activeSlot = nil
Special._specialTracks = {
	"SpecailLeft",
	"SpecailRight",
	"SpecailLeftFire",
	"SpecailRightFire",
}

local function getADSAnimation(side)
	if side == "left" then
		return "SpecailLeft"
	end
	return "SpecailRight"
end

local function getOtherSide(side)
	return (side == "left") and "right" or "left"
end

local function getGunNameForSide(side)
	return (side == "left") and "LeftGun" or "RightGun"
end

local function playWeaponAnimation(weaponInstance, animName, fadeTime)
	local track = nil
	if weaponInstance.PlayWeaponTrack then
		track = weaponInstance.PlayWeaponTrack(animName, fadeTime or 0.1)
	end
	if not track and weaponInstance.PlayAnimation then
		weaponInstance.PlayAnimation(animName, fadeTime or 0.1, true)
		local vm = weaponInstance.GetViewmodelController and weaponInstance.GetViewmodelController()
		local animator = vm and vm._animator or nil
		if animator and type(animator.GetTrack) == "function" then
			track = animator:GetTrack(animName)
		end
	end
	if track then
		local isADSLoop = (animName == "SpecailLeft" or animName == "SpecailRight")
		track.Looped = isADSLoop
	end
	return track
end

local function stopSpecialTracks(weaponInstance, fadeTime)
	if not weaponInstance then
		return
	end

	local vm = weaponInstance.GetViewmodelController and weaponInstance.GetViewmodelController()
	local animator = vm and vm._animator or nil
	if not animator or type(animator.Stop) ~= "function" then
		return
	end

	for _, trackName in ipairs(Special._specialTracks) do
		animator:Stop(trackName, fadeTime or 0.05)
	end
end

local function findGunAttachment(model, gunName, attachmentName)
	if not model then
		return nil
	end

	local partsFolder = model:FindFirstChild("Parts")
	if partsFolder and (partsFolder:IsA("Model") or partsFolder:IsA("Folder")) then
		local gunNode = partsFolder:FindFirstChild(gunName)
		if gunNode then
			local direct = gunNode:FindFirstChild(attachmentName, true)
			if direct and direct:IsA("Attachment") then
				return direct
			end
		end
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc.Name == gunName and (desc:IsA("BasePart") or desc:IsA("Model")) then
			local found = desc:FindFirstChild(attachmentName, true)
			if found and found:IsA("Attachment") then
				return found
			end
		end
	end

	return nil
end

function Special.Execute(weaponInstance, isPressed)
	if not weaponInstance or not weaponInstance.State or not weaponInstance.Config then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	local config = weaponInstance.Config
	local slot = weaponInstance.Slot
	if type(slot) ~= "string" or slot == "" then
		return false, "InvalidSlot"
	end

	if state.IsReloading then
		if Special._isADS then
			Special.Cancel()
		end
		return false, "Reloading"
	end

	if isPressed then
		Inspect.Cancel()
		DualPistolsState.SyncToTotal(slot, state.CurrentAmmo or 0, config.clipSize or 16)
		local side = DualPistolsState.EnterADS(slot, state.CurrentAmmo or 0, config.clipSize or 16)

		Special._isADS = true
		Special._activeSlot = slot
		Special:_enterADS(weaponInstance, side)
		return true
	end

	if not Special._isADS then
		return true
	end

	DualPistolsState.ExitADS(slot)
	Special._isADS = false
	Special._activeSlot = nil
	Special:_exitADS(weaponInstance)
	return true
end

function Special:_enterADS(weaponInstance, side)
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return
	end

	local rig = weaponInstance.GetRig and weaponInstance.GetRig() or nil
	local model = rig and rig.Model or nil
	local primaryGunName = getGunNameForSide(side)
	local fallbackGunName = getGunNameForSide(getOtherSide(side))
	local aimAttachment = findGunAttachment(model, primaryGunName, "AimPosition")
	local lookAtAttachment = findGunAttachment(model, primaryGunName, "LookAt")
	if not aimAttachment then
		aimAttachment = findGunAttachment(model, fallbackGunName, "AimPosition")
	end
	if not lookAtAttachment then
		lookAtAttachment = findGunAttachment(model, fallbackGunName, "LookAt")
	end
	if viewmodelController.SetCustomADSTarget then
		viewmodelController:SetCustomADSTarget(aimAttachment, lookAtAttachment)
	end

	local config = weaponInstance.Config
	local adsFOV = config and config.adsFOV
	local adsEffectsMultiplier = config and config.adsEffectsMultiplier or 0.15

	viewmodelController:SetADS(true, adsEffectsMultiplier)

	if adsFOV then
		Special._originalFOV = FOVController.BaseFOV
		FOVController:SetBaseFOV(adsFOV)
	end

	local adsSpeedMult = config and config.adsSpeedMultiplier or 0.75
	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(adsSpeedMult)
	end

	stopSpecialTracks(weaponInstance, 0.03)
	playWeaponAnimation(weaponInstance, getADSAnimation(side), 0.1)
end

function Special:_exitADS(weaponInstance)
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	stopSpecialTracks(weaponInstance, 0.08)
	if viewmodelController then
		if viewmodelController.ClearCustomADSTarget then
			viewmodelController:ClearCustomADSTarget()
		end
		viewmodelController:SetADS(false)
	end

	if Special._originalFOV then
		FOVController:SetBaseFOV(Special._originalFOV)
		Special._originalFOV = nil
	end

	local weaponController = ServiceRegistry:GetController("Weapon")
	if weaponController and weaponController.SetADSSpeedMultiplier then
		weaponController:SetADSSpeedMultiplier(1.0)
	end

	if weaponInstance then
		playWeaponAnimation(weaponInstance, "Idle", 0.08)
	end
end

function Special.Cancel()
	local shouldExitADS = Special._isADS or Special._originalFOV ~= nil
	if not shouldExitADS then
		return
	end

	if Special._activeSlot then
		DualPistolsState.ExitADS(Special._activeSlot)
	end

	Special._isADS = false
	Special._activeSlot = nil
	Special:_exitADS(nil)
end

function Special.IsActive()
	return Special._isADS
end

return Special
