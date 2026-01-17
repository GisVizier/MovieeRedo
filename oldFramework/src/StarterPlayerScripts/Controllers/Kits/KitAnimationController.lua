local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

local KitAnimationController = {}
KitAnimationController.CurrentKitName = nil
KitAnimationController.LoadedAnimations = {}

local LocalPlayer = Players.LocalPlayer

local function getViewmodelController()
	return ServiceRegistry:GetController("ViewmodelController")
end

local function getPlayerRig()
	if not LocalPlayer.Character then
		return nil
	end
	return LocalPlayer.Character:FindFirstChild("Rig")
end

local function getExistingAnimator(rig)
	if not rig then
		return nil
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid:FindFirstChildOfClass("Animator")
	end
	return nil
end

function KitAnimationController:LoadKitAnimations(kitName)
	if self.CurrentKitName == kitName then
		return
	end

	self:UnloadCurrentAnimations()

	local kitsFolder = ReplicatedStorage:FindFirstChild("Kits")
	if not kitsFolder then
		warn("[KitAnimationController] Kits folder not found in ReplicatedStorage")
		return
	end

	local kitModule = kitsFolder:FindFirstChild(kitName)
	if not kitModule then
		warn("[KitAnimationController] Kit not found:", kitName)
		return
	end

	local success, kitData = pcall(require, kitModule)
	if not success or not kitData then
		warn("[KitAnimationController] Failed to require kit module:", kitName, kitData)
		return
	end

	local kitConfig = kitData.Config
	if not kitConfig or not kitConfig.Animations then
		warn("[KitAnimationController] No animations configured for kit:", kitName)
		return
	end

	local viewmodelController = getViewmodelController()
	local viewmodelAnimations = kitConfig.Animations.Viewmodel or {}

	if viewmodelController and viewmodelController.ViewmodelAnimator then
		for animName, animId in pairs(viewmodelAnimations) do
			if animId and animId ~= "" and animId ~= "rbxassetid://0" then
				local success = pcall(function()
					viewmodelController.ViewmodelAnimator:LoadAnimation(animName, animId)
				end)

				if success then
					self.LoadedAnimations[animName] = {
						Type = "Viewmodel",
						AnimationId = animId,
					}
					print("[KitAnimationController] Loaded viewmodel animation:", animName, "for", kitName)
				else
					warn("[KitAnimationController] Failed to load viewmodel animation:", animName)
				end
			end
		end
	end

	local characterAnimations = kitConfig.Animations.Character or {}
	local rig = getPlayerRig()
	local animator = getExistingAnimator(rig)

	if animator then
		for animName, animId in pairs(characterAnimations) do
			if animId and animId ~= "" and animId ~= "rbxassetid://0" then
				local animation = Instance.new("Animation")
				animation.AnimationId = animId

				local track = animator:LoadAnimation(animation)
				track.Priority = Enum.AnimationPriority.Action

				self.LoadedAnimations[animName] = {
					Type = "Character",
					Track = track,
					AnimationId = animId,
				}
				print("[KitAnimationController] Loaded character animation:", animName, "for", kitName)
			end
		end
	end

	self.CurrentKitName = kitName
	print("[KitAnimationController] Loaded all animations for kit:", kitName)
end

function KitAnimationController:UnloadCurrentAnimations()
	local viewmodelController = getViewmodelController()

	for animName, data in pairs(self.LoadedAnimations) do
		if data.Type == "Viewmodel" and viewmodelController and viewmodelController.ViewmodelAnimator then
			pcall(function()
				viewmodelController.ViewmodelAnimator:StopAnimation(animName)
			end)
		elseif data.Type == "Character" and data.Track then
			if data.Track.IsPlaying then
				data.Track:Stop(0)
			end
			data.Track:Destroy()
		end
	end

	self.LoadedAnimations = {}
	self.CurrentKitName = nil
end

function KitAnimationController:PlayViewmodelAnimation(animName, fadeTime)
	local data = self.LoadedAnimations[animName]
	if not data or data.Type ~= "Viewmodel" then
		warn("[KitAnimationController] Viewmodel animation not loaded:", animName)
		return
	end

	local viewmodelController = getViewmodelController()
	if viewmodelController and viewmodelController.ViewmodelAnimator then
		viewmodelController.ViewmodelAnimator:PlayAnimation(animName, fadeTime)
	end
end

function KitAnimationController:StopViewmodelAnimation(animName, fadeTime)
	local data = self.LoadedAnimations[animName]
	if not data or data.Type ~= "Viewmodel" then
		return
	end

	local viewmodelController = getViewmodelController()
	if viewmodelController and viewmodelController.ViewmodelAnimator then
		viewmodelController.ViewmodelAnimator:StopAnimation(animName, fadeTime)
	end
end

function KitAnimationController:PlayCharacterAnimation(animName, fadeTime, looped)
	local data = self.LoadedAnimations[animName]
	if not data or data.Type ~= "Character" then
		warn("[KitAnimationController] Character animation not loaded:", animName)
		return
	end

	local track = data.Track
	if track then
		track.Looped = looped or false
		if track.IsPlaying then
			track:Stop(0)
		end
		track:Play(fadeTime or 0.1)
	end
end

function KitAnimationController:StopCharacterAnimation(animName, fadeTime)
	local data = self.LoadedAnimations[animName]
	if not data or data.Type ~= "Character" then
		return
	end

	local track = data.Track
	if track and track.IsPlaying then
		track:Stop(fadeTime or 0.2)
	end
end

function KitAnimationController:IsAnimationLoaded(animName)
	return self.LoadedAnimations[animName] ~= nil
end

function KitAnimationController:Init()
	task.defer(function()
		local KitController = ServiceRegistry:GetController("KitController")
		local ViewmodelController = getViewmodelController()

		if KitController then
			KitController.KitAssigned:connect(function(kitData)
				self:LoadKitAnimations(kitData.KitName)
			end)

			local currentKit = KitController:GetCurrentKit()
			if currentKit and currentKit.KitName then
				self:LoadKitAnimations(currentKit.KitName)
			end
		else
			warn("[KitAnimationController] KitController not found in registry")
		end

		if ViewmodelController then
			local InventoryController = ServiceRegistry:GetController("InventoryController")
			if InventoryController and InventoryController.WeaponEquipped then
				InventoryController.WeaponEquipped:connect(function()
					task.wait(0.1)
					if self.CurrentKitName then
						self:LoadKitAnimations(self.CurrentKitName)
					end
				end)
			end
		end
	end)

	print("[KitAnimationController] Initialized")
end

return KitAnimationController
