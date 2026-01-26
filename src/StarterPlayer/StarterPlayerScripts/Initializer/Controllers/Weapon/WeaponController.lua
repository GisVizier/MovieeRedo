--[[
	WeaponController.lua
	
	Handles weapon input, action delegation, and state management.
	All weapon-specific logic is delegated to Action modules.
]]

local WeaponController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local CrosshairController =
	require(ReplicatedStorage:WaitForChild("CrosshairSystem"):WaitForChild("CrosshairController"))

local WeaponServices = script.Parent:WaitForChild("Services")
local WeaponAmmo = require(WeaponServices:WaitForChild("WeaponAmmo"))
local WeaponRaycast = require(WeaponServices:WaitForChild("WeaponRaycast"))
local WeaponFX = require(WeaponServices:WaitForChild("WeaponFX"))
local WeaponCooldown = require(WeaponServices:WaitForChild("WeaponCooldown"))

-- Aim Assist
local AimAssist = require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("AimAssist"))
local AimAssistConfig = require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("AimAssist"):WaitForChild("AimAssistConfig"))

local ActionsRoot = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Weapons"):WaitForChild("Actions")

local DEBUG_WEAPON = false
local SHOW_TRACERS = true

local LocalPlayer = Players.LocalPlayer

-- Controller state
WeaponController._registry = nil
WeaponController._net = nil
WeaponController._inputManager = nil
WeaponController._viewmodelController = nil
WeaponController._camera = nil
WeaponController._crosshair = nil

-- Services
WeaponController._ammo = nil
WeaponController._fx = nil
WeaponController._cooldown = nil

-- Action system
WeaponController._actionCache = {}
WeaponController._currentActions = nil
WeaponController._equippedWeaponId = nil
WeaponController._weaponInstance = nil

-- State
WeaponController._isFiring = false
WeaponController._lastFireTime = 0
WeaponController._isAutomatic = false
WeaponController._autoFireConn = nil
WeaponController._isReloading = false
WeaponController._reloadToken = 0
WeaponController._slotChangedConn = nil
WeaponController._lastCameraMode = nil

-- Aim Assist
WeaponController._aimAssist = nil
WeaponController._aimAssistEnabled = false
WeaponController._aimAssistConfig = nil
WeaponController._aimAssistTargetConnection = nil

-- Auto-shoot
WeaponController._autoShootEnabled = false
WeaponController._autoShootConn = nil
WeaponController._hasAutoShootTarget = false

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function WeaponController:Init(registry, net)
	self._registry = registry
	self._net = net
	self._camera = workspace.CurrentCamera
	self._ammo = WeaponAmmo.new(LoadoutConfig, HttpService)
	self._fx = WeaponFX.new(LoadoutConfig, LogService)
	self._cooldown = WeaponCooldown.new()

	ServiceRegistry:SetRegistry(registry)
	ServiceRegistry:RegisterController("Weapon", self)

	-- Listen for hit confirmations from server
	if self._net then
		self._net:ConnectClient("HitConfirmed", function(hitData)
			self:_onHitConfirmed(hitData)
		end)
	end

	-- Initialize Aim Assist
	self:_initializeAimAssist()

	LogService:Info("WEAPON", "WeaponController initialized")
end

function WeaponController:_initializeAimAssist()
	self._aimAssist = AimAssist.new()
	
	-- Configure base settings
	self._aimAssist:setSubject(workspace.CurrentCamera)
	self._aimAssist:setType(AimAssist.Enum.AimAssistType.Rotational)
	
	-- Add player targets (ignore local player and teammates)
	self._aimAssist:addPlayerTargets(true, true, AimAssistConfig.Defaults.TargetBones)
	
	-- Add tagged targets (dummies, etc.)
	self._aimAssist:addTargetTag(AimAssistConfig.TargetTags.Primary, AimAssistConfig.Defaults.TargetBones)
	
	-- Enable debug mode if configured (shows FOV circle and target dots)
	if AimAssistConfig.Debug then
		self._aimAssist:setDebug(true)
		LogService:Info("WEAPON", "Aim Assist DEBUG MODE ENABLED - you should see FOV circle on screen")
	end
	
	LogService:Info("WEAPON", "Aim Assist initialized", {
		AllowMouseInput = AimAssistConfig.AllowMouseInput,
		Debug = AimAssistConfig.Debug,
	})
end

function WeaponController:Start()
	LocalPlayer = Players.LocalPlayer
	local inputController = self._registry:TryGet("Input")
	self._inputManager = inputController and inputController.Manager
	self._viewmodelController = self._registry:TryGet("Viewmodel")
	self._crosshair = CrosshairController.new(Players.LocalPlayer)

	local crosshairConfig = LoadoutConfig.Crosshair
	if crosshairConfig and crosshairConfig.DefaultCustomization then
		self._crosshair:SetCustomization(crosshairConfig.DefaultCustomization)
	end

	self:_connectInputs()
	self:_connectSlotChanges()

	-- Initialize ammo when loadout changes
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal("SelectedLoadout"):Connect(function()
			self:_initializeAmmo()
		end)

		task.defer(function()
			self:_initializeAmmo()
		end)
	end

	LogService:Info("WEAPON", "WeaponController started")
end

function WeaponController:_connectInputs()
	if not self._inputManager then
		return
	end

	-- Fire input
	self._inputManager:ConnectToInput("Fire", function(isFiring)
		self._isFiring = isFiring
		if isFiring then
			self:_onFirePressed()
			self:_startAutoFire()
		else
			self:_stopAutoFire()
		end
	end)

	-- Reload input
	self._inputManager:ConnectToInput("Reload", function(isPressed)
		if isPressed and not self._isReloading then
			self:Reload()
		end
	end)

	-- Inspect input
	self._inputManager:ConnectToInput("Inspect", function(isPressed)
		if isPressed and not self._isReloading and not self._isFiring then
			self:Inspect()
		end
	end)

	-- Special input (ADS for guns, ability for melee)
	self._inputManager:ConnectToInput("Special", function(isPressed)
		self:Special(isPressed)
	end)
end

function WeaponController:_connectSlotChanges()
	if not self._viewmodelController then
		return
	end

	-- Poll for slot changes (ViewmodelController doesn't have a signal yet)
	local lastSlot = nil
	local lastCameraMode = nil
	self._slotChangedConn = RunService.Heartbeat:Connect(function()
		local currentSlot = self._viewmodelController:GetActiveSlot()
		if currentSlot ~= lastSlot then
			lastSlot = currentSlot
			self:_onSlotChanged(currentSlot)
		end

		local cameraController = self._registry and self._registry:TryGet("Camera")
		local currentMode = cameraController and cameraController.GetCurrentMode and cameraController:GetCurrentMode()
			or nil
		if currentMode ~= lastCameraMode then
			lastCameraMode = currentMode
			self:_onCameraModeChanged(currentMode)
		end
	end)
end

function WeaponController:_onSlotChanged(slot)
	if not slot or slot == "Fists" then
		self:_unequipCurrentWeapon()
		return
	end

	local loadout = self._viewmodelController._loadout
	local weaponId = loadout and loadout[slot]

	if not weaponId then
		self:_unequipCurrentWeapon()
		return
	end

	self:_equipWeapon(weaponId, slot)
end

-- =============================================================================
-- ACTION LOADING
-- =============================================================================

function WeaponController:_loadActionsForWeapon(weaponId)
	if self._actionCache[weaponId] then
		return self._actionCache[weaponId]
	end

	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		error("[WeaponController] No config found for weapon: " .. tostring(weaponId))
	end

	-- Determine category: Gun or Melee
	local category = weaponConfig.weaponType == "Melee" and "Melee" or "Gun"
	local categoryFolder = ActionsRoot:FindFirstChild(category)

	if not categoryFolder then
		error("[WeaponController] Actions category folder not found: " .. category)
	end

	local weaponFolder = categoryFolder:FindFirstChild(weaponId)
	if not weaponFolder then
		error("[WeaponController] Actions folder not found for weapon: " .. weaponId .. " in " .. category)
	end

	local actions = {
		Main = weaponFolder:FindFirstChild("init") and require(weaponFolder) or nil,
		Attack = weaponFolder:FindFirstChild("Attack") and require(weaponFolder.Attack) or nil,
		Reload = weaponFolder:FindFirstChild("Reload") and require(weaponFolder.Reload) or nil,
		Inspect = weaponFolder:FindFirstChild("Inspect") and require(weaponFolder.Inspect) or nil,
		Special = weaponFolder:FindFirstChild("Special") and require(weaponFolder.Special) or nil,
	}

	self._actionCache[weaponId] = actions
	return actions
end

function WeaponController:_getCancels()
	if self._currentActions and self._currentActions.Main and self._currentActions.Main.Cancels then
		return self._currentActions.Main.Cancels
	end
	return {}
end

function WeaponController:_isFirstPerson()
	local cameraController = self._registry and self._registry:TryGet("Camera")
	if not cameraController or type(cameraController.GetCurrentMode) ~= "function" then
		return false
	end
	return cameraController:GetCurrentMode() == "FirstPerson"
end

function WeaponController:_onCameraModeChanged(_mode)
	if not self._crosshair then
		return
	end

	if not self:_isFirstPerson() then
		self._crosshair:RemoveCrosshair()
		UserInputService.MouseIconEnabled = true
		return
	end

	-- Entering FirstPerson mode - clear force hidden state and apply crosshair
	self._crosshairForcedHidden = false
	UserInputService.MouseIconEnabled = false
	
	if self._equippedWeaponId then
		self:_applyCrosshairForWeapon(self._equippedWeaponId)
	end
end

function WeaponController:_applyCrosshairForWeapon(weaponId)
	local crosshairConfig = LoadoutConfig.Crosshair
	if not (self._crosshair and crosshairConfig) then
		return
	end
	if not self:_isFirstPerson() then
		return
	end

	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	local weaponData = weaponConfig and weaponConfig.crosshair or nil
	local crosshairType = (weaponData and weaponData.type) or "Default"
	UserInputService.MouseIconEnabled = false
	self._crosshair:ApplyCrosshair(crosshairType, weaponData)
end

function WeaponController:_applyCrosshairRecoil()
	local crosshairConfig = LoadoutConfig.Crosshair
	if not (self._crosshair and crosshairConfig and self._equippedWeaponId) then
		return
	end
	if not self:_isFirstPerson() then
		return
	end

	local weaponConfig = LoadoutConfig.getWeapon(self._equippedWeaponId)
	local weaponData = weaponConfig and weaponConfig.crosshair or nil

	if weaponData then
		self._crosshair:OnRecoil({ amount = weaponData.recoilMultiplier or 1 })
	end
end

-- =============================================================================
-- EQUIP / UNEQUIP
-- =============================================================================

function WeaponController:_equipWeapon(weaponId, slot)
	-- Unequip old weapon first
	self:_unequipCurrentWeapon()

	-- Load actions for new weapon
	local success, actions = pcall(function()
		return self:_loadActionsForWeapon(weaponId)
	end)

	if not success then
		warn("[WeaponController] Failed to load actions:", actions)
		return
	end

	self._currentActions = actions
	self._equippedWeaponId = weaponId

	-- Build weapon instance
	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	self._weaponInstance = self:_buildWeaponInstance(weaponId, weaponConfig, slot)

	-- Set weapon speed multiplier attribute
	if LocalPlayer and weaponConfig then
		local speedMult = weaponConfig.speedMultiplier or 1.0
		LocalPlayer:SetAttribute("WeaponSpeedMultiplier", speedMult)
	end

	-- Initialize and equip
	if self._currentActions.Main then
		if self._currentActions.Main.Initialize then
			self._currentActions.Main.Initialize(self._weaponInstance)
		end
		if self._currentActions.Main.OnEquip then
			self._currentActions.Main.OnEquip(self._weaponInstance)
		end
	end

	self:_applyCrosshairForWeapon(weaponId)

	-- Setup Aim Assist for this weapon
	self:_setupAimAssistForWeapon(weaponConfig)

	LogService:Info("WEAPON", "Equipped weapon", { weaponId = weaponId })
end

function WeaponController:_setupAimAssistForWeapon(weaponConfig)
	if not self._aimAssist then
		LogService:Warn("WEAPON", "Aim assist not initialized!")
		return
	end

	local aimAssistConfig = weaponConfig and weaponConfig.aimAssist

	if aimAssistConfig and aimAssistConfig.enabled then
		-- Configure from weapon settings
		self._aimAssist:configureFromWeapon(aimAssistConfig)
		self._aimAssistConfig = aimAssistConfig

		-- Set camera sensitivity multiplier (lower sens = gentler pull)
		self:_updateAimAssistSensitivity()

		-- Enable aim assist
		self._aimAssist:enable()
		self._aimAssistEnabled = true

		-- Setup auto-shoot listener
		self:_setupAutoShoot()

		-- Re-apply debug mode (in case it was lost)
		if AimAssistConfig.Debug then
			self._aimAssist:setDebug(true)
		end

		LogService:Info("WEAPON", "=== AIM ASSIST ENABLED ===", {
			weapon = weaponConfig.id or weaponConfig.name or "Unknown",
			range = aimAssistConfig.range,
			fov = aimAssistConfig.fov,
			friction = aimAssistConfig.friction,
			tracking = aimAssistConfig.tracking,
			centering = aimAssistConfig.centering,
		})
	else
		-- Disable aim assist for this weapon (e.g., melee)
		if self._aimAssistEnabled then
			self._aimAssist:disable()
			self._aimAssistEnabled = false
			self:_cleanupAutoShoot()
			LogService:Info("WEAPON", "Aim assist DISABLED for this weapon")
		end
		self._aimAssistConfig = nil
	end
end

-- Update aim assist sensitivity based on camera sensitivity
function WeaponController:_updateAimAssistSensitivity()
	if not self._aimAssist or not self._aimAssistEnabled then
		return
	end

	local cameraController = self._registry and self._registry:TryGet("Camera")
	if not cameraController then
		return
	end

	-- Get camera config for base sensitivity values
	local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Config"))
	local cameraConfig = Config.Camera

	-- Base mouse sensitivity (from config)
	local baseSensitivity = cameraConfig.Sensitivity.Mouse or 0.2

	-- Actual sensitivity (we could read from player settings if they can customize it)
	local actualSensitivity = baseSensitivity

	-- Calculate multiplier: lower sens = lower pull strength
	-- Sensitivity of 0.1 = 0.5x pull, 0.2 = 1.0x pull, 0.4 = 2.0x pull
	local sensitivityMultiplier = actualSensitivity / baseSensitivity

	self._aimAssist:setSensitivityMultiplier(sensitivityMultiplier)

	LogService:Info("WEAPON", "Aim assist sensitivity updated", {
		baseSens = baseSensitivity,
		actualSens = actualSensitivity,
		multiplier = sensitivityMultiplier,
	})
end

function WeaponController:_unequipCurrentWeapon()
	if self._currentActions and self._currentActions.Main and self._currentActions.Main.OnUnequip then
		self._currentActions.Main.OnUnequip(self._weaponInstance)
	end

	if self._crosshair then
		self._crosshair:RemoveCrosshair()
	end
	UserInputService.MouseIconEnabled = true

	-- Cancel any active actions
	if self._currentActions then
		if self._currentActions.Special and self._currentActions.Special.Cancel then
			self._currentActions.Special.Cancel()
		end
		if self._currentActions.Inspect and self._currentActions.Inspect.Cancel then
			self._currentActions.Inspect.Cancel()
		end
		if self._currentActions.Reload and self._currentActions.Reload.Cancel then
			self._currentActions.Reload.Cancel()
		end
	end

	-- Reset speed multipliers
	if LocalPlayer then
		LocalPlayer:SetAttribute("WeaponSpeedMultiplier", 1.0)
		LocalPlayer:SetAttribute("ADSSpeedMultiplier", 1.0)
	end

	-- Disable Aim Assist and Auto-shoot
	if self._aimAssist and self._aimAssistEnabled then
		self._aimAssist:disable()
		self._aimAssistEnabled = false
		self:_cleanupAutoShoot()
	end
	self._aimAssistConfig = nil

	self._currentActions = nil
	self._equippedWeaponId = nil
	self._weaponInstance = nil
	self._isReloading = false
end

-- =============================================================================
-- WEAPON INSTANCE
-- =============================================================================

function WeaponController:_buildWeaponInstance(weaponId, weaponConfig, slot)
	local ammo = self._ammo and slot and self._ammo:GetAmmo(slot) or nil

	return {
		-- Core references
		Player = LocalPlayer,
		WeaponId = weaponId,
		WeaponName = weaponId,
		WeaponType = weaponConfig and weaponConfig.weaponType or "Gun",
		Config = weaponConfig,
		Slot = slot,
		Net = self._net,

		-- Services
		Ammo = self._ammo,
		Cooldown = self._cooldown,
		FX = self._fx,

		-- Viewmodel access
		GetViewmodelController = function()
			return self._viewmodelController
		end,
		GetRig = function()
			return self._viewmodelController and self._viewmodelController:GetActiveRig()
		end,

		-- Animation helpers
		PlayAnimation = function(name, fade, restart)
			self:_playViewmodelAnimation(name, fade, restart)
		end,
		PlayWeaponTrack = function(name, fade)
			if self._viewmodelController and self._viewmodelController.PlayWeaponTrack then
				return self._viewmodelController:PlayWeaponTrack(name, fade)
			end
			return nil
		end,

		-- Raycast helpers
		PerformRaycast = function(ignoreSpread)
			return self:_performRaycast(weaponConfig, ignoreSpread)
		end,
		GeneratePelletDirections = function(profile)
			return self:_generatePelletDirections(profile)
		end,

		-- FX helpers
		PlayFireEffects = function(hitData)
			self:_playFireEffects(weaponId, hitData)
		end,
		RenderTracer = function(hitData)
			self:_renderBulletTracer(hitData)
		end,

		-- State management
		GetIsReloading = function()
			return self._isReloading
		end,
		SetIsReloading = function(value)
			self._isReloading = value == true
		end,
		GetReloadToken = function()
			return self._reloadToken
		end,
		IncrementReloadToken = function()
			self._reloadToken = self._reloadToken + 1
			return self._reloadToken
		end,

		-- State object (updated each call)
		State = {
			CurrentAmmo = ammo and ammo.currentAmmo or 0,
			ReserveAmmo = ammo and ammo.reserveAmmo or 0,
			IsReloading = self._isReloading,
			IsAttacking = self._isFiring,
			LastFireTime = self._lastFireTime,
			Equipped = self:_isActiveWeaponEquipped(),
		},
	}
end

function WeaponController:_updateWeaponInstanceState()
	if not self._weaponInstance then
		return
	end

	local slot = self:_getCurrentSlot()
	local ammo = self._ammo and self._ammo:GetAmmo(slot) or nil

	self._weaponInstance.State = {
		CurrentAmmo = ammo and ammo.currentAmmo or 0,
		ReserveAmmo = ammo and ammo.reserveAmmo or 0,
		IsReloading = self._isReloading,
		IsAttacking = self._isFiring,
		LastFireTime = self._lastFireTime,
		Equipped = self:_isActiveWeaponEquipped(),
	}
end

-- =============================================================================
-- ACTIONS
-- =============================================================================

function WeaponController:_onFirePressed()
	local currentTime = workspace:GetServerTimeNow()

	if not self:_isActiveWeaponEquipped() then
		return
	end

	if not self._currentActions or not self._currentActions.Attack then
		return
	end

	-- Update aim assist firing state
	if self._aimAssist and self._aimAssistEnabled then
		self._aimAssist:setFiringState(true)
	end

	-- Update weapon instance state
	self:_updateWeaponInstanceState()

	-- Check cancel logic
	local cancels = self:_getCancels()

	-- Cancel inspect on fire
	if
		self._currentActions.Inspect
		and self._currentActions.Inspect.IsInspecting
		and self._currentActions.Inspect.IsInspecting()
	then
		if self._currentActions.Inspect.Cancel then
			self._currentActions.Inspect.Cancel()
		end
	end

	-- Check if special blocks firing
	if cancels.SpecialCancelsFire then
		if
			self._currentActions.Special
			and self._currentActions.Special.IsActive
			and self._currentActions.Special.IsActive()
		then
			return
		end
	end

	-- Check if firing should cancel special
	if cancels.FireCancelsSpecial then
		if
			self._currentActions.Special
			and self._currentActions.Special.IsActive
			and self._currentActions.Special.IsActive()
		then
			if self._currentActions.Special.Cancel then
				self._currentActions.Special.Cancel()
			end
		end
	end

	-- Execute attack
	local ok, reason = self._currentActions.Attack.Execute(self._weaponInstance, currentTime)

	if not ok then
		if reason == "NoAmmo" then
			local weaponConfig = self._weaponInstance.Config
			local fireProfile = weaponConfig and weaponConfig.fireProfile
			if fireProfile and fireProfile.autoReloadOnEmpty ~= false and not self._isReloading then
				self:Reload()
			end
		end
		return
	end

	self:_applyCrosshairRecoil()

	-- Update state after attack
	self._lastFireTime = currentTime
	self:_updateWeaponInstanceState()
end

function WeaponController:Reload()
	if not self._currentActions then
		return
	end

	if not self._weaponInstance then
		return
	end

	-- Update state
	self:_updateWeaponInstanceState()

	-- Check cancel logic
	local cancels = self:_getCancels()

	-- Cancel special on reload
	if cancels.ReloadCancelsSpecial then
		if
			self._currentActions.Special
			and self._currentActions.Special.IsActive
			and self._currentActions.Special.IsActive()
		then
			if self._currentActions.Special.Cancel then
				self._currentActions.Special.Cancel()
			end
		end
	end

	-- Execute reload
	if self._currentActions.Reload then
		local ok, reason = self._currentActions.Reload.Execute(self._weaponInstance)
		if ok then
			LogService:Info("WEAPON", "Reload started", { weaponId = self._equippedWeaponId })
		end
	end
end

function WeaponController:Inspect()
	if not self._currentActions then
		return
	end

	if not self._weaponInstance then
		return
	end

	-- Update state
	self:_updateWeaponInstanceState()

	-- Execute inspect
	if self._currentActions.Inspect then
		local ok = self._currentActions.Inspect.Execute(self._weaponInstance)
		if ok then
			LogService:Debug("WEAPON", "Inspecting", { weaponId = self._equippedWeaponId })
		end
	end
end

function WeaponController:Special(isPressed)
	if not self._currentActions then
		return
	end

	if not self._weaponInstance then
		return
	end
	
	-- Only allow special in FirstPerson camera mode
	local cameraController = ServiceRegistry:GetController("CameraController")
	if cameraController and cameraController:GetCurrentMode() ~= "FirstPerson" then
		return
	end

	-- Update state
	self:_updateWeaponInstanceState()

	-- Check cancel logic
	local cancels = self:_getCancels()

	-- Cancel reload on special
	if isPressed and cancels.SpecialCancelsReload then
		if self._isReloading and self._currentActions.Reload and self._currentActions.Reload.Cancel then
			self._currentActions.Reload.Cancel()
		end
	end

	-- Execute special
	if self._currentActions.Special then
		self._currentActions.Special.Execute(self._weaponInstance, isPressed)
	end
	
	-- Apply Aim Assist ADS boost
	self:_updateAimAssistADS(isPressed)
end

function WeaponController:_updateAimAssistADS(isADS: boolean)
	if not self._aimAssist or not self._aimAssistEnabled then
		return
	end

	-- Update ADS state (no more snap, just state tracking)
	self._aimAssist:setADSState(isADS)

	if isADS then
		-- Apply ADS boost to strengthen the continuous pull
		local boostConfig = self._aimAssistConfig and self._aimAssistConfig.adsBoost
		self._aimAssist:applyADSBoost(boostConfig)
		print("[WeaponController] ADS activated - continuous pull strengthened")

		-- Start auto-shoot if target is in sight and ADS-only is enabled
		if self._hasAutoShootTarget and AimAssistConfig.AutoShoot.ADSOnly then
			self:_startAutoShootIfEnabled()
		end
	else
		-- Deactivate ADS (restore base strengths)
		self._aimAssist:deactivateADS()
		print("[WeaponController] ADS deactivated - normal pull strength")

		-- Stop auto-shoot if ADS-only is required
		if AimAssistConfig.AutoShoot.ADSOnly then
			self:_stopAutoShoot()
		end
	end
end

-- =============================================================================
-- AUTO FIRE
-- =============================================================================

function WeaponController:_startAutoFire()
	if self._autoFireConn then
		return
	end

	if not self:_isActiveWeaponEquipped() then
		return
	end

	if not self._weaponInstance or not self._weaponInstance.Config then
		return
	end

	local weaponConfig = self._weaponInstance.Config
	local fireProfile = weaponConfig.fireProfile or {}

	if fireProfile.mode == "Auto" then
		self._isAutomatic = true

		self._autoFireConn = RunService.Heartbeat:Connect(function()
			if self._isFiring and self._isAutomatic then
				self:_onFirePressed()
			end
		end)
	end
end

function WeaponController:_stopAutoFire()
	self._isAutomatic = false

	-- Clear aim assist firing state when we stop firing
	if self._aimAssist and self._aimAssistEnabled then
		self._aimAssist:setFiringState(false)
	end

	if self._autoFireConn then
		self._autoFireConn:Disconnect()
		self._autoFireConn = nil
	end
end

-- =============================================================================
-- HELPERS
-- =============================================================================

function WeaponController:_getCurrentSlot()
	if not self._viewmodelController then
		return "Primary"
	end

	local slot = self._viewmodelController:GetActiveSlot()
	if not slot or slot == "Fists" then
		return "Primary"
	end

	return slot
end

function WeaponController:_getCurrentWeaponId()
	return self._equippedWeaponId
end

function WeaponController:_isActiveWeaponEquipped()
	if not self._viewmodelController then
		return false
	end

	local slot = self._viewmodelController:GetActiveSlot()
	if not slot or slot == "Fists" then
		return false
	end

	local rig = self._viewmodelController:GetRigForSlot(slot)
	local cam = workspace.CurrentCamera

	return rig and rig.Model and rig.Model.Parent == cam
end

function WeaponController:_initializeAmmo()
	if not LocalPlayer or not self._ammo then
		return
	end

	self._ammo:InitializeFromLoadout(LocalPlayer, self._isReloading, function()
		return self:_getCurrentSlot()
	end)

	LogService:Debug("WEAPON", "Ammo initialized for all slots")
end

function WeaponController:_playViewmodelAnimation(name, fade, restart)
	if self._viewmodelController and type(self._viewmodelController.PlayViewmodelAnimation) == "function" then
		self._viewmodelController:PlayViewmodelAnimation(name, fade, restart)
	end
end

function WeaponController:_performRaycast(weaponConfig, ignoreSpread)
	return WeaponRaycast.PerformRaycast(self._camera, LocalPlayer, weaponConfig, ignoreSpread)
end

function WeaponController:_generatePelletDirections(config)
	return WeaponRaycast.GeneratePelletDirections(self._camera, config)
end

function WeaponController:_playFireEffects(weaponId, hitData)
	if DEBUG_WEAPON then
		LogService:Debug("WEAPON", "Fire effects", { weaponId = weaponId })
	end

	if not self._viewmodelController or not self:_isActiveWeaponEquipped() then
		return
	end

	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	local recoilCfg = weaponConfig and weaponConfig.recoil or {}
	local kickPos = recoilCfg.kickPos or Vector3.new(0, 0, -0.08)
	local kickRot = recoilCfg.kickRot or Vector3.new(-0.08, 0, 0)

	self._viewmodelController:ApplyRecoil(kickPos, kickRot)
end

function WeaponController:_onHitConfirmed(hitData)
	if not hitData then
		return
	end

	if SHOW_TRACERS then
		self:_renderBulletTracer(hitData)
	end

	if hitData.shooter == LocalPlayer.UserId then
		self:_showHitmarker(hitData)
	end

	if hitData.hitPlayer == LocalPlayer.UserId then
		self:_showDamageIndicator(hitData)
	end
end

function WeaponController:_renderBulletTracer(hitData)
	if self._fx then
		self._fx:RenderBulletTracer(hitData)
	end
end

function WeaponController:_showHitmarker(hitData)
	if self._fx then
		self._fx:ShowHitmarker(hitData)
	end
end

function WeaponController:_showDamageIndicator(hitData)
	if self._fx then
		self._fx:ShowDamageIndicator(hitData)
	end
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

function WeaponController:GetAmmoService()
	return self._ammo
end

function WeaponController:GetCooldownService()
	return self._cooldown
end

function WeaponController:GetCurrentActions()
	return self._currentActions
end

function WeaponController:GetWeaponInstance()
	return self._weaponInstance
end

function WeaponController:SetADSSpeedMultiplier(multiplier: number)
	if LocalPlayer then
		LocalPlayer:SetAttribute("ADSSpeedMultiplier", multiplier or 1.0)
	end
end

function WeaponController:GetADSSpeedMultiplier(): number
	if LocalPlayer then
		return LocalPlayer:GetAttribute("ADSSpeedMultiplier") or 1.0
	end
	return 1.0
end

-- =============================================================================
-- AUTO-SHOOT SYSTEM
-- =============================================================================

function WeaponController:_setupAutoShoot()
	-- Cleanup existing connection
	self:_cleanupAutoShoot()

	if not self._aimAssist then
		return
	end

	-- Listen to target acquisition events
	local targetEvent = self._aimAssist:getTargetAcquiredEvent()
	self._aimAssistTargetConnection = targetEvent:Connect(function(data)
		self:_onTargetAcquisitionChanged(data)
	end)

	LogService:Info("WEAPON", "Auto-shoot listener setup complete")
end

function WeaponController:_cleanupAutoShoot()
	if self._aimAssistTargetConnection then
		self._aimAssistTargetConnection:Disconnect()
		self._aimAssistTargetConnection = nil
	end

	self:_stopAutoShoot()
end

function WeaponController:_onTargetAcquisitionChanged(data)
	local hasTarget = data.hasTarget

	if hasTarget then
		-- Target acquired - start auto-shooting if enabled
		self._hasAutoShootTarget = true
		self:_startAutoShootIfEnabled()
	else
		-- Target lost - stop auto-shooting
		self._hasAutoShootTarget = false
		self:_stopAutoShoot()
	end
end

function WeaponController:_startAutoShootIfEnabled()
	-- Check if auto-shoot is globally enabled
	if not AimAssistConfig.AutoShoot.Enabled then
		return
	end

	-- Check if ADS-only mode is enabled and we're not ADS
	if AimAssistConfig.AutoShoot.ADSOnly and not self._aimAssist.isADS then
		return
	end

	-- Don't start if already auto-shooting
	if self._autoShootConn then
		return
	end

	-- Start auto-shoot loop
	self._autoShootConn = RunService.Heartbeat:Connect(function()
		if not self._hasAutoShootTarget then
			self:_stopAutoShoot()
			return
		end

		-- Check ADS requirement
		if AimAssistConfig.AutoShoot.ADSOnly and not self._aimAssist.isADS then
			return
		end

		-- Check if target has been in sight long enough
		if not self._aimAssist:canAutoShoot() then
			return
		end

		-- Check if we can actually fire
		if not self:_isActiveWeaponEquipped() then
			return
		end

		if not self._currentActions or not self._currentActions.Attack then
			return
		end

		-- Trigger attack
		self:_onFirePressed()
	end)

	LogService:Info("WEAPON", "Auto-shoot STARTED")
end

function WeaponController:_stopAutoShoot()
	if self._autoShootConn then
		self._autoShootConn:Disconnect()
		self._autoShootConn = nil
		LogService:Info("WEAPON", "Auto-shoot STOPPED")
	end
end

-- Toggle auto-shoot feature on/off
function WeaponController:SetAutoShootEnabled(enabled: boolean)
	AimAssistConfig.AutoShoot.Enabled = enabled

	if not enabled then
		self:_stopAutoShoot()
	elseif self._hasAutoShootTarget then
		self:_startAutoShootIfEnabled()
	end

	LogService:Info("WEAPON", "Auto-shoot toggled", { enabled = enabled })
end

-- Toggle ADS-only requirement
function WeaponController:SetAutoShootADSOnly(adsOnly: boolean)
	AimAssistConfig.AutoShoot.ADSOnly = adsOnly

	-- Restart auto-shoot if needed to apply new setting
	if self._hasAutoShootTarget then
		self:_stopAutoShoot()
		self:_startAutoShootIfEnabled()
	end

	LogService:Info("WEAPON", "Auto-shoot ADS-only toggled", { adsOnly = adsOnly })
end

-- =============================================================================
-- AIM ASSIST PUBLIC API
-- =============================================================================

function WeaponController:GetAimAssist()
	return self._aimAssist
end

function WeaponController:IsAimAssistEnabled(): boolean
	return self._aimAssistEnabled == true
end

function WeaponController:SetAimAssistDebug(enabled: boolean)
	if self._aimAssist then
		self._aimAssist:setDebug(enabled)
	end
end

-- Update gamepad eligibility (call from input handlers)
function WeaponController:UpdateAimAssistGamepadEligibility(keyCode: Enum.KeyCode, position: Vector3)
	if self._aimAssist then
		self._aimAssist:updateGamepadEligibility(keyCode, position)
	end
end

-- Update touch eligibility (call from input handlers)
function WeaponController:UpdateAimAssistTouchEligibility()
	if self._aimAssist then
		self._aimAssist:updateTouchEligibility()
	end
end

-- =============================================================================
-- CROSSHAIR VISIBILITY
-- =============================================================================

-- Force hide the crosshair (for emote wheel, menus, etc.)
function WeaponController:HideCrosshair()
	self._crosshairForcedHidden = true
	
	if self._crosshair then
		self._crosshair:RemoveCrosshair()
	end
end

-- Restore crosshair visibility after force hide
function WeaponController:RestoreCrosshair()
	self._crosshairForcedHidden = false
	
	-- Only restore if we're in first person with a weapon equipped
	if not self:_isFirstPerson() then
		return
	end
	
	-- Re-apply crosshair for equipped weapon
	if self._equippedWeaponId then
		self:_applyCrosshairForWeapon(self._equippedWeaponId)
	end
end

-- Check if crosshair is force hidden
function WeaponController:IsCrosshairHidden()
	return self._crosshairForcedHidden == true
end

-- Force re-apply crosshair (useful when state gets out of sync)
function WeaponController:RefreshCrosshair()
	-- Clear force hidden state
	self._crosshairForcedHidden = false
	
	-- Re-apply based on current state
	if self:_isFirstPerson() and self._equippedWeaponId then
		self:_applyCrosshairForWeapon(self._equippedWeaponId)
	end
end

-- =============================================================================
-- CLEANUP
-- =============================================================================

function WeaponController:Destroy()
	self:_stopAutoFire()
	self:_unequipCurrentWeapon()

	if self._slotChangedConn then
		self._slotChangedConn:Disconnect()
		self._slotChangedConn = nil
	end

	if self._cooldown then
		self._cooldown:Destroy()
	end
end

return WeaponController
