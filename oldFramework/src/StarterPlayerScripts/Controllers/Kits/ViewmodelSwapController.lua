local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

local ViewmodelSwapController = {}
ViewmodelSwapController.SavedWeaponViewmodel = nil
ViewmodelSwapController.AbilityViewmodels = {}

local LocalPlayer = Players.LocalPlayer

local function getViewmodelController()
	return ServiceRegistry:GetController("ViewmodelController")
end

function ViewmodelSwapController:ShowAbilityViewmodel(abilityName, animationToPlay, animations)
	print("[ViewmodelSwap] === SHOW ABILITY VIEWMODEL ===")
	print("[ViewmodelSwap] Ability:", abilityName, "Animation:", animationToPlay)

	local viewmodelController = getViewmodelController()
	if not viewmodelController then
		warn("[ViewmodelSwap] ViewmodelController not available")
		return
	end

	if viewmodelController.CurrentViewmodel then
		self.SavedWeaponViewmodel = {
			Name = viewmodelController.CurrentWeaponName,
			Model = viewmodelController.CurrentViewmodel,
		}
		print("[ViewmodelSwap] Saved weapon viewmodel:", self.SavedWeaponViewmodel.Name)
	end

	local abilityViewmodel = viewmodelController:Create(LocalPlayer, "Fist")
	if not abilityViewmodel then
		warn("[ViewmodelSwap] Failed to create ability viewmodel")
		return
	end

	print("[ViewmodelSwap] Created Fist viewmodel for ability")

	if viewmodelController.ViewmodelAnimator and animations then
		for animName, animId in pairs(animations) do
			print("[ViewmodelSwap] Loading animation:", animName, "ID:", animId)
			viewmodelController.ViewmodelAnimator:LoadAnimation(animName, animId)
		end
	end

	if animationToPlay and viewmodelController.ViewmodelAnimator then
		task.wait(0.1)
		print("[ViewmodelSwap] Playing animation:", animationToPlay)
		viewmodelController.ViewmodelAnimator:PlayAnimation(animationToPlay, 0.05)
	end

	self.AbilityViewmodels[abilityName] = abilityViewmodel
	print("[ViewmodelSwap] ✅ Showed ability viewmodel:", abilityName)
end

function ViewmodelSwapController:HideAbilityViewmodel(abilityName)
	print("[ViewmodelSwap] === HIDE ABILITY VIEWMODEL ===")
	print("[ViewmodelSwap] Ability:", abilityName)

	local viewmodelController = getViewmodelController()
	if not viewmodelController then
		warn("[ViewmodelSwap] ViewmodelController not available")
		return
	end

	self.AbilityViewmodels[abilityName] = nil

	if self.SavedWeaponViewmodel then
		print("[ViewmodelSwap] Restoring weapon viewmodel:", self.SavedWeaponViewmodel.Name)
		viewmodelController:Create(LocalPlayer, self.SavedWeaponViewmodel.Name)
		self.SavedWeaponViewmodel = nil
	end

	print("[ViewmodelSwap] ✅ Hid ability viewmodel:", abilityName)
end

function ViewmodelSwapController:PlayAnimation(abilityName, animationName)
	local viewmodelController = getViewmodelController()
	if not viewmodelController or not viewmodelController.ViewmodelAnimator then
		warn("[ViewmodelSwap] ViewmodelAnimator not available")
		return nil
	end

	print("[ViewmodelSwap] Playing animation:", abilityName, animationName)
	viewmodelController.ViewmodelAnimator:PlayAnimation(animationName, 0.05)

	local track = viewmodelController.ViewmodelAnimator:GetTrack(animationName)
	return track
end

function ViewmodelSwapController:PlayAnimationAndWait(abilityName, animationName, hideAfter, extraDelay)
	local track = self:PlayAnimation(abilityName, animationName)
	if not track then
		warn("[ViewmodelSwap] No track returned for animation:", animationName)
		return
	end

	if hideAfter then
		local length = track.Length
		local buffer = extraDelay or 0.5
		local totalWait = length + buffer
		print("[ViewmodelSwap] Animation length:", length, "Buffer:", buffer, "Total wait:", totalWait)
		task.delay(totalWait, function()
			self:HideAbilityViewmodel(abilityName)
		end)
	end
end

function ViewmodelSwapController:Cleanup()
	self.SavedWeaponViewmodel = nil
	self.AbilityViewmodels = {}
end

function ViewmodelSwapController:Init()
	print("[ViewmodelSwap] Initialized")
end

return ViewmodelSwapController
