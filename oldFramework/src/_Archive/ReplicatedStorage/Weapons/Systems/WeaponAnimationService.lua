--[[
	WeaponAnimationService.lua

	Centralized service for playing weapon animations on both viewmodel and character rig.
	This should be used by weapon action modules (Attack.lua, Reload.lua, etc.) instead of
	directly calling ViewmodelController.

	Usage from weapon actions:
	local WeaponAnimationService = require(Locations.Modules.Weapons.Systems.WeaponAnimationService)
	WeaponAnimationService:PlayFireAnimation(weaponInstance)
	WeaponAnimationService:PlayReloadAnimation(weaponInstance)
	WeaponAnimationService:PlayEquipAnimation(weaponInstance)
	WeaponAnimationService:PlayInspectAnimation(weaponInstance)
]]

local WeaponAnimationService = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules (lazy loaded to avoid circular dependencies)
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- State
WeaponAnimationService.CharacterAnimator = nil
WeaponAnimationService.CharacterAnimationTracks = {}
WeaponAnimationService.CurrentWeaponName = nil
WeaponAnimationService.ThirdPersonWeaponManager = nil

-- Initialize category
LogService:RegisterCategory("WEAPON_ANIM", "Weapon animation service")

--[[
	Lazy-load ThirdPersonWeaponManager (client-only module)
	@return table|nil - ThirdPersonWeaponManager or nil
]]
local function getThirdPersonWeaponManager()
	if WeaponAnimationService.ThirdPersonWeaponManager then
		return WeaponAnimationService.ThirdPersonWeaponManager
	end

	-- Only try to load on client
	if not RunService:IsClient() then
		return nil
	end

	local success, manager = pcall(function()
		local playerScripts = LocalPlayer:WaitForChild("PlayerScripts", 3)
		if playerScripts then
			local systems = playerScripts:FindFirstChild("Systems")
			if systems then
				local viewmodel = systems:FindFirstChild("Viewmodel")
				if viewmodel then
					local module = viewmodel:FindFirstChild("ThirdPersonWeaponManager")
					if module then
						local loaded = require(module)
						loaded:Init()
						return loaded
					end
				end
			end
		end
		return nil
	end)

	if success and manager then
		WeaponAnimationService.ThirdPersonWeaponManager = manager
		return manager
	end

	return nil
end

--============================================================================
-- VIEWMODEL ANIMATIONS
--============================================================================

--[[
	Get the ViewmodelController from ServiceRegistry
	@return table|nil - ViewmodelController or nil
]]
local function getViewmodelController()
	return ServiceRegistry:GetController("ViewmodelController")
end

--[[
	Get the player's active rig from RigManager
	@return Model|nil - The player's rig or nil
]]
local function getPlayerRig()
	local RigManager = require(Locations.Modules.Systems.Character.RigManager)
	-- Don't call Init() here - RigManager should be initialized by the character system
	return RigManager:GetActiveRig(LocalPlayer)
end

--[[
	Get the existing Animator from the rig's Humanoid
	NOTE: Do NOT create new AnimationController - the rig uses Humanoid.Animator
	which is shared with AnimationController.lua
	@param rig Model - The character rig
	@return Animator|nil
]]
local function getExistingAnimator(rig)
	if not rig then
		return nil
	end

	-- Get the Humanoid's Animator (shared with AnimationController.lua)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid:FindFirstChildOfClass("Animator")
	end

	return nil
end

--============================================================================
-- CHARACTER ANIMATION SETUP
--============================================================================

--[[
	Setup character animations for a weapon
	@param weaponName string - Name of the weapon
]]
function WeaponAnimationService:SetupCharacterAnimations(weaponName)
	local rig = getPlayerRig()
	if not rig then
		LogService:Debug("WEAPON_ANIM", "No rig found for character animations")
		return
	end

	-- Use existing Animator from Humanoid (shared with AnimationController.lua)
	-- Do NOT create new AnimationController - that would conflict with character animations
	local animator = getExistingAnimator(rig)
	if not animator then
		LogService:Warn("WEAPON_ANIM", "Animator not found in rig Humanoid")
		return
	end

	self.CharacterAnimator = animator
	self.CharacterAnimationTracks = {}
	self.CurrentWeaponName = weaponName

	-- Load character animations from config
	local charAnims = ViewmodelConfig:GetCharacterAnimations(weaponName)
	if not charAnims then
		LogService:Debug("WEAPON_ANIM", "No character animations for weapon", { Weapon = weaponName })
		return
	end

	for animName, animId in pairs(charAnims) do
		if animId and animId ~= "rbxassetid://0" then
			local animation = Instance.new("Animation")
			animation.AnimationId = animId

			local track = animator:LoadAnimation(animation)
			track.Looped = (animName == "Idle" or animName == "Walk" or animName == "Run")
			track.Priority = Enum.AnimationPriority.Action

			self.CharacterAnimationTracks[animName] = track

			LogService:Debug("WEAPON_ANIM", "Loaded character animation", {
				Animation = animName,
				AnimationId = animId,
			})
		end
	end

	LogService:Info("WEAPON_ANIM", "Character animations setup complete", {
		Weapon = weaponName,
		TrackCount = #self.CharacterAnimationTracks,
	})
end

--[[
	Cleanup character animations
]]
function WeaponAnimationService:CleanupCharacterAnimations()
	for _, track in pairs(self.CharacterAnimationTracks) do
		if track.IsPlaying then
			track:Stop(0)
		end
	end

	self.CharacterAnimationTracks = {}
	self.CharacterAnimator = nil
	self.CurrentWeaponName = nil
end

--============================================================================
-- ANIMATION PLAYBACK
--============================================================================

--[[
	Play animation on viewmodel
	@param animationName string - Animation name (Fire, Reload, etc.)
]]
function WeaponAnimationService:PlayViewmodelAnimation(animationName)
	local viewmodelController = getViewmodelController()
	if viewmodelController and viewmodelController.ViewmodelAnimator then
		viewmodelController.ViewmodelAnimator:PlayAnimation(animationName)
	end
end

--[[
	Play animation on character rig
	@param animationName string - Animation name (Fire, Reload, etc.)
]]
function WeaponAnimationService:PlayCharacterAnimation(animationName)
	local track = self.CharacterAnimationTracks[animationName]
	if track then
		if track.IsPlaying then
			track:Stop(0)
		end
		track:Play(0.1)

		LogService:Debug("WEAPON_ANIM", "Playing character animation", { Animation = animationName })
	end
end

--[[
	Stop animation on character rig
	@param animationName string - Animation name
]]
function WeaponAnimationService:StopCharacterAnimation(animationName)
	local track = self.CharacterAnimationTracks[animationName]
	if track and track.IsPlaying then
		track:Stop(0.2)
	end
end

--[[
	Play both viewmodel and character animations
	@param animationName string - Animation name
]]
function WeaponAnimationService:PlayBothAnimations(animationName)
	self:PlayViewmodelAnimation(animationName)
	self:PlayCharacterAnimation(animationName)
end

--============================================================================
-- WEAPON ACTION HELPERS
-- These are the main functions weapon action modules should call
--============================================================================

--[[
	Play fire/attack animation
	@param weaponInstance table - The weapon instance
]]
function WeaponAnimationService:PlayFireAnimation(weaponInstance)
	local animName = weaponInstance.WeaponType == "Melee" and "Attack" or "Fire"
	self:PlayBothAnimations(animName)

	-- Handle UnADSOnShoot if enabled
	local viewmodelController = getViewmodelController()
	if viewmodelController and viewmodelController.Config then
		local shouldUnADS = ViewmodelConfig:GetUnADSOnShoot(viewmodelController.Config)
		if shouldUnADS and viewmodelController.IsADS then
			viewmodelController:SetADS(false)
		end
	end

	LogService:Debug("WEAPON_ANIM", "PlayFireAnimation called", {
		Weapon = weaponInstance.WeaponName,
		AnimName = animName,
	})
end

--[[
	Play reload animation
	@param weaponInstance table - The weapon instance
	@return number - Duration of reload animation
]]
function WeaponAnimationService:PlayReloadAnimation(weaponInstance)
	self:PlayBothAnimations("Reload")

	-- Get animation duration for timing
	local duration = 2.0 -- Default fallback

	local viewmodelController = getViewmodelController()
	if viewmodelController and viewmodelController.ViewmodelAnimator then
		local track = viewmodelController.ViewmodelAnimator:GetTrack("Reload")
		if track then
			duration = track.Length
		end
	end

	LogService:Debug("WEAPON_ANIM", "PlayReloadAnimation called", {
		Weapon = weaponInstance.WeaponName,
		Duration = duration,
	})

	return duration
end

--[[
	Play equip animation
	@param weaponInstance table - The weapon instance
	@return number - Duration of equip animation
]]
function WeaponAnimationService:PlayEquipAnimation(weaponInstance)
	-- Setup character animations for the new weapon
	self:SetupCharacterAnimations(weaponInstance.WeaponName)

	-- Equip 3rd-person weapon on character rig
	local thirdPersonManager = getThirdPersonWeaponManager()
	if thirdPersonManager then
		thirdPersonManager:EquipWeapon(weaponInstance.WeaponName, weaponInstance.SkinName)
	end

	self:PlayBothAnimations("Equip")

	-- Get animation duration for timing
	local duration = 0.5 -- Default fallback

	local viewmodelController = getViewmodelController()
	if viewmodelController and viewmodelController.ViewmodelAnimator then
		local track = viewmodelController.ViewmodelAnimator:GetTrack("Equip")
		if track then
			duration = track.Length
		end
	end

	LogService:Debug("WEAPON_ANIM", "PlayEquipAnimation called", {
		Weapon = weaponInstance.WeaponName,
		Duration = duration,
	})

	return duration
end

--[[
	Play unequip animation (or just stop all)
	@param weaponInstance table - The weapon instance
]]
function WeaponAnimationService:PlayUnequipAnimation(weaponInstance)
	-- Stop all character animations
	for _, track in pairs(self.CharacterAnimationTracks) do
		if track.IsPlaying then
			track:Stop(0.2)
		end
	end

	-- Unequip 3rd-person weapon from character rig
	local thirdPersonManager = getThirdPersonWeaponManager()
	if thirdPersonManager then
		thirdPersonManager:UnequipWeapon()
	end

	-- Cleanup character animations
	self:CleanupCharacterAnimations()

	LogService:Debug("WEAPON_ANIM", "PlayUnequipAnimation called", {
		Weapon = weaponInstance.WeaponName,
	})
end

--[[
	Play inspect animation
	@param weaponInstance table - The weapon instance
]]
function WeaponAnimationService:PlayInspectAnimation(weaponInstance)
	self:PlayBothAnimations("Inspect")

	LogService:Debug("WEAPON_ANIM", "PlayInspectAnimation called", {
		Weapon = weaponInstance.WeaponName,
	})
end

--[[
	Check if currently playing a specific animation
	@param animationName string - Animation to check
	@return boolean - True if playing
]]
function WeaponAnimationService:IsPlayingAnimation(animationName)
	local viewmodelController = getViewmodelController()
	if viewmodelController and viewmodelController.ViewmodelAnimator then
		return viewmodelController.ViewmodelAnimator:IsPlaying(animationName)
	end
	return false
end

--[[
	Check if any blocking animation is playing (Fire, Reload, Equip, Inspect)
	@return boolean - True if a blocking animation is playing
]]
function WeaponAnimationService:IsBlockingAnimationPlaying()
	local blockingAnims = { "Fire", "Attack", "Reload", "Equip", "Inspect" }
	for _, animName in ipairs(blockingAnims) do
		if self:IsPlayingAnimation(animName) then
			return true
		end
	end
	return false
end

return WeaponAnimationService
