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
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local _recoilPitch = 0
local _recoilYaw = 0
local _recoilConfig = nil
local _recoilConnection = nil

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))
local CrosshairController =
	require(ReplicatedStorage:WaitForChild("CrosshairSystem"):WaitForChild("CrosshairController"))

local WeaponServices = script.Parent:WaitForChild("Services")
local WeaponAmmo = require(WeaponServices:WaitForChild("WeaponAmmo"))
local WeaponRaycast = require(WeaponServices:WaitForChild("WeaponRaycast"))
local WeaponFX = require(WeaponServices:WaitForChild("WeaponFX"))
local WeaponCooldown = require(WeaponServices:WaitForChild("WeaponCooldown"))
local WeaponProjectile = require(WeaponServices:WaitForChild("WeaponProjectile"))
local Tracers = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("Tracers"))

-- Aim Assist
local AimAssist = require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("AimAssist"))
local AimAssistConfig =
	require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("AimAssist"):WaitForChild("AimAssistConfig"))

local ActionsRoot = ReplicatedStorage:WaitForChild("Game"):WaitForChild("Weapons"):WaitForChild("Actions")

local DEBUG_WEAPON = false
local SHOW_TRACERS = true
local DEBUG_QUICK_MELEE = true
local DEBUG_HITMARKER = true

local LocalPlayer = Players.LocalPlayer
local WEAPON_SOUND_MODULE_INFO = { Module = "Sound" }
local LOCAL_WEAPON_VOLUME = 1.0
local LOCAL_WEAPON_ROLLOFF_MODE = Enum.RollOffMode.InverseTapered
local LOCAL_WEAPON_MIN_DISTANCE = 7.5
local LOCAL_WEAPON_MAX_DISTANCE = 360
local FIRE_SOUND_PITCH_MIN = 0.92
local FIRE_SOUND_PITCH_MAX = 1.10
local FIRE_SOUND_PITCH_RNG = Random.new()
local ADS_SENSITIVITY_BASE_MULT = 0.75
local DEFAULT_EQUIP_FIRE_LOCK = 0.35
local MIN_EQUIP_FIRE_LOCK = 0.1
local MAX_EQUIP_FIRE_LOCK = 2.5
local SHOTGUN_SWAP_SKIP_WINDOW = 0.9

local function quickMeleeLog(message, data)
	if not DEBUG_QUICK_MELEE then
		return
	end
	LogService:Info("WEAPON_QM", message, data)
end


local function hitmarkerDebug(message, data)
	if not DEBUG_HITMARKER then
		return
	end
end

local function normalizeSoundId(soundRef)
	if type(soundRef) == "table" then
		soundRef = soundRef.Id or soundRef.id or soundRef.SoundId or soundRef.soundId
	end

	if type(soundRef) == "number" then
		if soundRef <= 0 then
			return nil
		end
		return "rbxassetid://" .. tostring(math.floor(soundRef))
	end

	if type(soundRef) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(soundRef, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if trimmed == "" then
		return nil
	end

	if string.match(trimmed, "^rbxassetid://%d+$") then
		return trimmed
	end
	if string.match(trimmed, "^rbxasset://") then
		return trimmed
	end

	local numeric = tonumber(trimmed)
	if numeric and numeric > 0 then
		return "rbxassetid://" .. tostring(math.floor(numeric))
	end

	return nil
end

local function getViewmodelSoundRoot()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local sounds = assets:FindFirstChild("Sounds")
	if not sounds then
		return nil
	end
	local viewModel = sounds:FindFirstChild("ViewModel")
	if not viewModel then
		return nil
	end
	return viewModel
end

-- Controller state
WeaponController._registry = nil
WeaponController._net = nil
WeaponController._inputManager = nil
WeaponController._viewmodelController = nil
WeaponController._camera = nil
WeaponController._crosshair = nil
WeaponController._replicationController = nil

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
WeaponController._isADS = false
WeaponController._lastFireTime = 0
WeaponController._lastFireTimeBySlot = {}
WeaponController._isAutomatic = false
WeaponController._autoFireConn = nil
WeaponController._isReloading = false
WeaponController._reloadToken = 0
WeaponController._reloadFireLocked = false
WeaponController._equipFireLockUntil = 0
WeaponController._equipFireLockToken = 0
WeaponController._equipBufferedShot = false
WeaponController._lastShotWeaponId = nil
WeaponController._lastShotTime = 0
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
WeaponController._crosshairSlidingRotation = 0
WeaponController._crosshairRotation = 0
WeaponController._crosshairRotationTarget = 0
WeaponController._crosshairRotationConn = nil
WeaponController._debugRaycastKeyConn = nil
WeaponController._quickMeleeToken = 0
WeaponController._quickMeleeSession = nil
WeaponController._replicatedMovementTrack = nil
WeaponController._replicatedTrackStopTokens = {}
WeaponController._replicatedTrackStopConnections = {}
WeaponController._activeActionSounds = {}
WeaponController._lastActionSoundAt = {}
WeaponController._muzzleAttachmentCache = setmetatable({}, { __mode = "k" })

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

	-- Initialize WeaponProjectile early so OnClientEvent handlers for
	-- ProjectileReplicate and ProjectileHitConfirmed are connected before
	-- any events arrive from the server (prevents "did you forget to implement OnClientEvent?" warnings).
	WeaponProjectile:Init(net)

	-- Listen for hit confirmations from server
	if self._net then
		self._net:ConnectClient("HitConfirmed", function(hitData)
			self:_onHitConfirmed(hitData)
		end)
	end

	-- Initialize Aim Assist
	self:_initializeAimAssist()

	_recoilConnection = RunService.Heartbeat:Connect(function(dt)
		if _recoilPitch == 0 and _recoilYaw == 0 then
			return
		end
		local speed = _recoilConfig and _recoilConfig.recoverySpeed or 10
		local decay = math.min(1, speed * dt)

		local pitchRecover = _recoilPitch * decay
		local yawRecover = _recoilYaw * decay

		_recoilPitch = _recoilPitch - pitchRecover
		_recoilYaw = _recoilYaw - yawRecover

		if math.abs(_recoilPitch) < 0.01 then
			_recoilPitch = 0
		end
		if math.abs(_recoilYaw) < 0.01 then
			_recoilYaw = 0
		end

		local cam = ServiceRegistry:GetController("CameraController")
		if cam then
			cam.TargetAngleX = cam.TargetAngleX - pitchRecover
			cam.TargetAngleY = cam.TargetAngleY - yawRecover
		end
	end)

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

	if LocalPlayer then
		local baseSensitivity = UserInputService.MouseDeltaSensitivity
		if type(baseSensitivity) ~= "number" or baseSensitivity <= 0 then
			baseSensitivity = 1
		end

		if type(LocalPlayer:GetAttribute("MouseSensitivityScale")) ~= "number" then
			LocalPlayer:SetAttribute("MouseSensitivityScale", math.clamp(baseSensitivity, 0.01, 4))
		end
		if type(LocalPlayer:GetAttribute("ADSSensitivityScale")) ~= "number" then
			LocalPlayer:SetAttribute("ADSSensitivityScale", ADS_SENSITIVITY_BASE_MULT)
		end
		LocalPlayer:SetAttribute("WeaponADSActive", false)
		self:_applyMouseSensitivityForADS(false)
	end

	local inputController = self._registry:TryGet("Input")
	self._inputManager = inputController and inputController.Manager
	self._viewmodelController = self._registry:TryGet("Viewmodel")
	self._replicationController = self._registry:TryGet("Replication")
	self._crosshair = CrosshairController.new(Players.LocalPlayer)

	local crosshairConfig = LoadoutConfig.Crosshair
	if crosshairConfig and crosshairConfig.DefaultCustomization then
		self._crosshair:SetCustomization(crosshairConfig.DefaultCustomization)
	end
	if self._crosshair and type(self._crosshair.SetHideReticleInADS) == "function" then
		local hideInADS = true
		if crosshairConfig and crosshairConfig.HideInADS ~= nil then
			hideInADS = crosshairConfig.HideInADS == true
		end
		self._crosshair:SetHideReticleInADS(hideInADS)
	end

	self:_connectInputs()
	self:_connectDebugRaycastKey()
	self:_connectSlotChanges()
	self:_connectMovementState()
	self:_ensureCrosshairRotationLoop()

	-- Mobile auto-shoot: fire immediately when a player/dummy is in crosshair (no ADS, no delay)
	if UserInputService.TouchEnabled then
		AimAssistConfig.AutoShoot.Enabled = true
		AimAssistConfig.AutoShoot.ADSOnly = false
		AimAssistConfig.AutoShoot.AcquisitionDelay = 0
		AimAssistConfig.AutoShoot.MaxAngleForAutoShoot = 8
		AimAssistConfig.Input.TouchInactivityTimeout = 1.5
	else
		AimAssistConfig.AutoShoot.Enabled = false
	end

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

function WeaponController:_ensureCrosshairRotationLoop()
	if self._crosshairRotationConn then
		return
	end
	self._crosshairRotationConn = RunService.RenderStepped:Connect(function(dt)
		if not self._crosshair then
			return
		end
		local speed = 12
		local alpha = math.clamp(1 - math.exp(-speed * dt), 0, 1)
		self._crosshairRotation = self._crosshairRotation
			+ (self._crosshairRotationTarget - self._crosshairRotation) * alpha
		self._crosshair:SetRotation(self._crosshairRotation)
	end)
end

function WeaponController:_connectMovementState()
	MovementStateManager:ConnectToStateChange(function(_, newState)
		if not self._crosshair then
			return
		end
		if newState == MovementStateManager.States.Sliding then
			self._crosshairSlidingRotation = 30
		else
			self._crosshairSlidingRotation = 0
		end
		self._crosshairRotationTarget = self._crosshairSlidingRotation
	end)
end

function WeaponController:_connectInputs()
	if not self._inputManager then
		return
	end

	-- Fire input
	self._inputManager:ConnectToInput("Fire", function(isFiring)
		self._isFiring = isFiring
		if isFiring then
			if self:_isEquipLocked() then
				self._equipBufferedShot = true
				self:_stopAutoFire()
				return
			end
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
		if isPressed and not self._isReloading and not self._isFiring and not self:IsADS() then
			self:Inspect()
		end
	end)

	-- Special input (ADS for guns, ability for melee)
	self._inputManager:ConnectToInput("Special", function(isPressed)
		self:Special(isPressed)
	end)

	self._inputManager:ConnectToInput("QuickMelee", function(isPressed)
		quickMeleeLog("Input callback", { isPressed = isPressed })
		if isPressed then
			self:QuickMelee()
		end
	end)
end

function WeaponController:_connectDebugRaycastKey()
	if self._debugRaycastKeyConn then
		self._debugRaycastKeyConn:Disconnect()
		self._debugRaycastKeyConn = nil
	end
	self._debugRaycastKeyConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Y then
			WeaponRaycast.DebugRaycastEnabled = not WeaponRaycast.DebugRaycastEnabled
			LogService:Info(
				"WEAPON",
				"Debug raycast " .. (WeaponRaycast.DebugRaycastEnabled and "ON" or "OFF") .. " (Y to toggle)"
			)
		end
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

		self:_syncReplicatedMovementTrack()

		local cameraController = self._registry and self._registry:TryGet("Camera")
		local currentMode = cameraController and cameraController.GetCurrentMode and cameraController:GetCurrentMode()
			or nil
		if currentMode ~= lastCameraMode then
			lastCameraMode = currentMode
			self:_onCameraModeChanged(currentMode)
		end
	end)
end

function WeaponController:_syncReplicatedMovementTrack()
	if not self._viewmodelController then
		return
	end

	local equippedWeaponId = self._equippedWeaponId
	if type(equippedWeaponId) ~= "string" or equippedWeaponId == "" then
		if self._replicatedMovementTrack then
			self:_replicateViewmodelAction("PlayWeaponTrack", self._replicatedMovementTrack, false)
			self._replicatedMovementTrack = nil
		end
		return
	end

	local trackName = nil
	if type(self._viewmodelController.GetCurrentMovementTrack) == "function" then
		trackName = self._viewmodelController:GetCurrentMovementTrack()
	end
	if trackName ~= "Idle" and trackName ~= "Walk" and trackName ~= "Run" then
		trackName = "Idle"
	end

	-- Don't replicate Run animation for Shorty and DualPistols (their 3D viewmodel doesn't need it)
	if trackName == "Run" and (equippedWeaponId == "Shorty" or equippedWeaponId == "DualPistols") then
		trackName = "Idle"
	end

	if trackName == self._replicatedMovementTrack then
		return
	end

	if self._replicatedMovementTrack then
		self:_replicateViewmodelAction("PlayWeaponTrack", self._replicatedMovementTrack, false)
	end

	self:_replicateViewmodelAction("PlayWeaponTrack", trackName, true)
	self._replicatedMovementTrack = trackName
end

function WeaponController:_onSlotChanged(slot)
	self:_onQuickMeleeSlotChanged(slot)

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

	local mainModule = nil
	if weaponFolder:IsA("ModuleScript") then
		-- Package module (folder with init.lua mapped to ModuleScript) - require root.
		mainModule = weaponFolder
	else
		-- Plain folder layout - require explicit init child.
		local initModule = weaponFolder:FindFirstChild("init")
		if initModule and initModule:IsA("ModuleScript") then
			mainModule = initModule
		end
	end

	local actions = {
		Main = mainModule and require(mainModule) or nil,
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
	if type(self._crosshair.SetHideReticleInADS) == "function" then
		local hideInADS = true
		if crosshairConfig.HideInADS ~= nil then
			hideInADS = crosshairConfig.HideInADS == true
		end
		self._crosshair:SetHideReticleInADS(hideInADS)
	end
	self._crosshairRotationTarget = self._crosshairSlidingRotation
	self._crosshairRotation = self._crosshairRotationTarget
	self._crosshair:SetRotation(self._crosshairRotation)
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
		local state = self._weaponInstance and self._weaponInstance.State or nil
		local recoilScale = 1
		if state and type(state.CrosshairRecoilScale) == "number" then
			recoilScale = math.max(state.CrosshairRecoilScale, 0.1)
		end
		self._crosshair:OnRecoil({ amount = (weaponData.recoilMultiplier or 1) * recoilScale })
	end
end

function WeaponController:_applyCameraRecoil()
	if not self._equippedWeaponId then
		return
	end
	local weaponConfig = LoadoutConfig.getWeapon(self._equippedWeaponId)
	local recoilData = weaponConfig and weaponConfig.recoil
	if not recoilData then
		return
	end

	_recoilConfig = recoilData

	local cameraController = ServiceRegistry:GetController("CameraController")
	if not cameraController then
		return
	end

	local isADS = self:_resolveADSState(self._isADS)
	local adsRecoilMult = 1
	if isADS then
		adsRecoilMult = recoilData.adsMultiplier
			or recoilData.adsRecoilMultiplier
			or weaponConfig.adsEffectsMultiplier
			or 0.35
	end

	local state = self._weaponInstance and self._weaponInstance.State or nil
	local shotRecoilScale = 1
	if state and type(state.ShotRecoilScale) == "number" then
		shotRecoilScale = math.max(state.ShotRecoilScale, 0.1)
	end
	adsRecoilMult *= shotRecoilScale

	local pitchKick = (recoilData.pitchUp or 1) * adsRecoilMult
	local yawKick = ((math.random() * 2 - 1) * (recoilData.yawRandom or 0.5)) * adsRecoilMult

	_recoilPitch = _recoilPitch + pitchKick
	_recoilYaw = _recoilYaw + yawKick

	cameraController.TargetAngleX = cameraController.TargetAngleX + pitchKick
	cameraController.TargetAngleY = cameraController.TargetAngleY + yawKick
end

function WeaponController:_resolveADSState(defaultState: boolean?): boolean
	local fallback = defaultState == true
	local special = self._currentActions and self._currentActions.Special
	if special and type(special.IsActive) == "function" then
		local ok, active = pcall(function()
			return special.IsActive()
		end)
		if ok then
			return active == true
		end
	end
	return fallback
end

function WeaponController:_isEquipLocked(): boolean
	return (self._equipFireLockUntil or 0) > os.clock()
end

function WeaponController:_clearEquipFireLock()
	self._equipFireLockToken = (self._equipFireLockToken or 0) + 1
	self._equipFireLockUntil = 0
	self._equipBufferedShot = false
end

function WeaponController:_flushBufferedEquipShot()
	if self:_isEquipLocked() then
		return
	end
	if self._equipBufferedShot ~= true then
		return
	end

	self._equipBufferedShot = false
	self:_onFirePressed()
	if self._isFiring then
		self:_startAutoFire()
	end
end

function WeaponController:_setEquipFireLock(durationSeconds: number?)
	local duration = tonumber(durationSeconds) or DEFAULT_EQUIP_FIRE_LOCK
	duration = math.clamp(duration, MIN_EQUIP_FIRE_LOCK, MAX_EQUIP_FIRE_LOCK)

	self._equipFireLockToken = (self._equipFireLockToken or 0) + 1
	local token = self._equipFireLockToken
	self._equipFireLockUntil = os.clock() + duration
	local wasFiringHeld = self._isFiring == true
	self._equipBufferedShot = wasFiringHeld

	-- Equipping should immediately stop any pending fire loop/state.
	self._isFiring = false
	self:_stopAutoFire()

	task.delay(duration, function()
		if self._equipFireLockToken ~= token then
			return
		end
		if (self._equipFireLockUntil or 0) <= os.clock() then
			self._equipFireLockUntil = 0
			self:_flushBufferedEquipShot()
		end
	end)
end

function WeaponController:_isShotgunWeapon(weaponId: string?): boolean
	if type(weaponId) ~= "string" or weaponId == "" then
		return false
	end

	local cfg = LoadoutConfig.getWeapon(weaponId)
	if not cfg then
		return false
	end

	local fireProfile = cfg.fireProfile
	if type(fireProfile) == "table" and fireProfile.mode == "Shotgun" then
		return true
	end

	return (tonumber(cfg.pelletsPerShot) or 1) > 1
end

function WeaponController:_shouldSkipShotgunEquip(outgoingWeaponId: string?, incomingWeaponId: string?): boolean
	if not self:_isShotgunWeapon(incomingWeaponId) then
		return false
	end

	if not self:_isShotgunWeapon(self._lastShotWeaponId) then
		return false
	end

	local now = workspace:GetServerTimeNow()
	if (now - (self._lastShotTime or 0)) > SHOTGUN_SWAP_SKIP_WINDOW then
		return false
	end

	-- Preferred path: direct shotgun -> shotgun swap.
	if self:_isShotgunWeapon(outgoingWeaponId) then
		return true
	end

	-- Fallback: recent shotgun shot + incoming shotgun still gets skip (covers slot-sync edge cases).
	return true
end

function WeaponController:_getLastFireTimeForSlot(slot: string?): number
	if type(slot) ~= "string" or slot == "" then
		return 0
	end

	if type(self._lastFireTimeBySlot) ~= "table" then
		self._lastFireTimeBySlot = {}
	end

	return tonumber(self._lastFireTimeBySlot[slot]) or 0
end

function WeaponController:_setLastFireTimeForSlot(slot: string?, fireTime: number?)
	local resolved = tonumber(fireTime) or 0
	self._lastFireTime = resolved

	if type(slot) ~= "string" or slot == "" then
		return
	end

	if type(self._lastFireTimeBySlot) ~= "table" then
		self._lastFireTimeBySlot = {}
	end
	self._lastFireTimeBySlot[slot] = resolved
end

function WeaponController:_bypassShotgunSwapCooldown(slot: string?, weaponConfig)
	if not self:_isShotgunWeapon(self._equippedWeaponId) then
		return
	end

	local now = workspace:GetServerTimeNow()
	local fireRate = weaponConfig and tonumber(weaponConfig.fireRate) or 0
	local bypassTime = 0
	if fireRate > 0 then
		local interval = 60 / fireRate
		bypassTime = now - interval - 0.01
	end

	self:_setLastFireTimeForSlot(slot, bypassTime)
	if self._weaponInstance and self._weaponInstance.State then
		self._weaponInstance.State.LastFireTime = bypassTime
	end
end

-- =============================================================================
-- EQUIP / UNEQUIP
-- =============================================================================

function WeaponController:_equipWeapon(weaponId, slot)
	local previousWeaponId = self._equippedWeaponId

	-- Unequip old weapon first
	self:_unequipCurrentWeapon()

	-- Load actions for new weapon
	local success, actions = pcall(function()
		return self:_loadActionsForWeapon(weaponId)
	end)

	if not success then
		return
	end

	self._currentActions = actions
	self._isADS = false
	self._equippedWeaponId = weaponId
	self._lastFireTime = self:_getLastFireTimeForSlot(slot)

	-- Build weapon instance
	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	self._weaponInstance = self:_buildWeaponInstance(weaponId, weaponConfig, slot)

	-- Set weapon speed multiplier attribute
	if LocalPlayer and weaponConfig then
		local speedMult = weaponConfig.speedMultiplier or 1.0
		LocalPlayer:SetAttribute("WeaponSpeedMultiplier", speedMult)
		LocalPlayer:SetAttribute("WeaponADSActive", false)
	end
	self:_applyMouseSensitivityForADS(false)

	-- Initialize and equip
	local didSkipEquipAnimation = false
	if self._currentActions.Main then
		local quickSession = self._quickMeleeSession
		local shouldSkipQuickMelee = quickSession
			and quickSession.skipEquipAnimation == true
			and slot == "Melee"
		local shouldSkipShotgunEquip = self:_shouldSkipShotgunEquip(previousWeaponId, weaponId)
		local shouldSkipOnEquip = shouldSkipQuickMelee or shouldSkipShotgunEquip

		if self._currentActions.Main.Initialize then
			self._currentActions.Main.Initialize(self._weaponInstance)
		end

		if shouldSkipOnEquip then
			if shouldSkipQuickMelee and quickSession then
				quickSession.skipEquipAnimation = false
			end
			if shouldSkipShotgunEquip then
				self:_bypassShotgunSwapCooldown(slot, weaponConfig)
			end
			local viewmodelController = self._viewmodelController
			local animator = viewmodelController and viewmodelController._animator
			if animator and type(animator.Stop) == "function" then
				animator:Stop("Equip", 0)
			end
			didSkipEquipAnimation = true
		elseif self._currentActions.Main.OnEquip then
			local ok, err = pcall(function()
				self._currentActions.Main.OnEquip(self._weaponInstance)
			end)
			if not ok then
			end
		end

	end

	if didSkipEquipAnimation then
		self:_clearEquipFireLock()
	else
		local equipLockDuration = DEFAULT_EQUIP_FIRE_LOCK
		local equipTrack = self:_getViewmodelTrack("Equip")
		if equipTrack then
			local trackLength = tonumber(equipTrack.Length)
			if trackLength and trackLength > 0 then
				local speed = tonumber(equipTrack.Speed) or 1
				if math.abs(speed) < 0.001 then
					speed = 1
				end
				equipLockDuration = math.clamp((trackLength / math.abs(speed)) + 0.02, MIN_EQUIP_FIRE_LOCK, MAX_EQUIP_FIRE_LOCK)
			end
		end
		self:_setEquipFireLock(equipLockDuration)
	end

	-- Fallback equip cue: guarantees equip audio even if Main module is missing.
	if self._weaponInstance and self._weaponInstance.PlayActionSound then
		LogService:Info("WEAPON_SOUND", "Equip fallback sound requested", {
			weaponId = weaponId,
			slot = slot,
		})
		local ok, err = pcall(function()
			self._weaponInstance.PlayActionSound("Equip")
		end)
		if not ok then
		end
	end

	self:_applyCrosshairForWeapon(weaponId)

	_recoilConfig = weaponConfig and weaponConfig.recoil or nil
	_recoilPitch = 0
	_recoilYaw = 0

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
	if not self._aimAssist then
		return
	end

	local cameraController = self._registry and self._registry:TryGet("Camera")
	if not cameraController then
		return
	end

	-- Get camera config for base sensitivity values
	local Config = require(
		game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Config")
	)
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

function WeaponController:_setADSActiveAttribute(isADS: boolean)
	if LocalPlayer then
		LocalPlayer:SetAttribute("WeaponADSActive", isADS == true)
	end
end

function WeaponController:_applyMouseSensitivityForADS(isADS: boolean?)
	if not LocalPlayer then
		return
	end

	local hipSensitivity = LocalPlayer:GetAttribute("MouseSensitivityScale")
	if type(hipSensitivity) ~= "number" then
		hipSensitivity = UserInputService.MouseDeltaSensitivity
		if type(hipSensitivity) ~= "number" or hipSensitivity <= 0 then
			hipSensitivity = 1
		end
		LocalPlayer:SetAttribute("MouseSensitivityScale", hipSensitivity)
	end

	local adsSensitivityScale = LocalPlayer:GetAttribute("ADSSensitivityScale")
	if type(adsSensitivityScale) ~= "number" then
		adsSensitivityScale = ADS_SENSITIVITY_BASE_MULT
		LocalPlayer:SetAttribute("ADSSensitivityScale", adsSensitivityScale)
	end

	local adsSpeedMultiplier = LocalPlayer:GetAttribute("ADSSpeedMultiplier")
	if type(adsSpeedMultiplier) ~= "number" then
		adsSpeedMultiplier = 1
	end

	local adsActive = isADS
	if adsActive == nil then
		adsActive = self._isADS == true
	end

	local targetSensitivity = hipSensitivity
	if adsActive then
		targetSensitivity = hipSensitivity * adsSensitivityScale * adsSpeedMultiplier * ADS_SENSITIVITY_BASE_MULT
	end

	UserInputService.MouseDeltaSensitivity = math.clamp(targetSensitivity, 0.01, 4)
end

function WeaponController:OnRespawnRefresh()
	self._isADS = false
	self:_setADSActiveAttribute(false)
	self:_applyMouseSensitivityForADS(false)
	self:_unequipCurrentWeapon()
	self:_initializeAmmo()
	local slot = self._viewmodelController and self._viewmodelController:GetActiveSlot()
	if slot and slot ~= "Fists" then
		self:_onSlotChanged(slot)
	end
end

function WeaponController:_unequipCurrentWeapon()
	self:_clearReplicatedTrackStopWatch()
	self:_stopAllTrackedWeaponActionSounds(true)

	if self._replicatedMovementTrack then
		self:_replicateViewmodelAction("PlayWeaponTrack", self._replicatedMovementTrack, false)
		self._replicatedMovementTrack = nil
	end

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
			self._currentActions.Reload.Cancel(self._weaponInstance)
		end
	end

	-- Reset speed multipliers
	if LocalPlayer then
		LocalPlayer:SetAttribute("WeaponSpeedMultiplier", 1.0)
		LocalPlayer:SetAttribute("ADSSpeedMultiplier", 1.0)
		LocalPlayer:SetAttribute("WeaponADSActive", false)
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
	self:_clearEquipFireLock()
	self._isReloading = false
	self._reloadFireLocked = false
	self._isADS = false
	self:_applyMouseSensitivityForADS(false)

	_recoilConfig = nil
	_recoilPitch = 0
	_recoilYaw = 0
end

-- =============================================================================
-- WEAPON INSTANCE
-- =============================================================================

function WeaponController:_getSkinIdForSlot(slot)
	if type(slot) ~= "string" or slot == "" then
		return nil
	end

	local viewmodelController = self._viewmodelController
	if not viewmodelController then
		return nil
	end

	if type(viewmodelController.GetRigForSlot) == "function" then
		local rig = viewmodelController:GetRigForSlot(slot)
		if rig and type(rig._skinId) == "string" and rig._skinId ~= "" then
			return rig._skinId
		end
	end

	if type(viewmodelController.GetActiveSlot) == "function" and viewmodelController:GetActiveSlot() == slot then
		local activeRig = viewmodelController:GetActiveRig()
		if activeRig and type(activeRig._skinId) == "string" and activeRig._skinId ~= "" then
			return activeRig._skinId
		end
	end

	return nil
end

function WeaponController:_resolveWeaponActionSoundId(weaponId, slot, actionName)
	if type(weaponId) ~= "string" or weaponId == "" then
		return nil, nil
	end
	if type(actionName) ~= "string" or actionName == "" then
		return nil, nil
	end

	local weaponCfg = ViewmodelConfig.Weapons and ViewmodelConfig.Weapons[weaponId]
	if type(weaponCfg) ~= "table" then
		return nil, nil
	end

	local skinId = self:_getSkinIdForSlot(slot)
	local soundRef = nil

	if skinId and ViewmodelConfig.Skins then
		local weaponSkins = ViewmodelConfig.Skins[weaponId]
		local skinCfg = weaponSkins and weaponSkins[skinId]
		if type(skinCfg) == "table" and type(skinCfg.Sounds) == "table" then
			soundRef = skinCfg.Sounds[actionName]
		end
	end

	if soundRef == nil and type(weaponCfg.Sounds) == "table" then
		soundRef = weaponCfg.Sounds[actionName]
	end

	local normalizedId = normalizeSoundId(soundRef)
	if normalizedId then
		return {
			SoundId = normalizedId,
			Source = "id",
		}, skinId
	end

	if type(soundRef) == "string" and soundRef ~= "" then
		local soundRoot = getViewmodelSoundRoot()
		if soundRoot then
			local weaponFolder = soundRoot:FindFirstChild(weaponId)
			if weaponFolder then
				if skinId then
					local skinFolder = weaponFolder:FindFirstChild(skinId)
					if skinFolder then
						local skinTemplate = skinFolder:FindFirstChild(soundRef)
						if skinTemplate and skinTemplate:IsA("Sound") then
							return {
								Template = skinTemplate,
								Source = "template",
							}, skinId
						end
					end
				end

				local template = weaponFolder:FindFirstChild(soundRef)
				if template and template:IsA("Sound") then
					return {
						Template = template,
						Source = "template",
					}, skinId
				end
			end
		end
	end

	return nil, skinId
end

function WeaponController:_getWeaponActionSoundKey(weaponId, slot, actionName)
	if type(weaponId) ~= "string" or weaponId == "" then
		return nil
	end
	if type(actionName) ~= "string" or actionName == "" then
		return nil
	end
	return tostring(weaponId) .. "|" .. tostring(slot) .. "|" .. tostring(actionName)
end

function WeaponController:_isLayeredWeaponActionSound(actionName)
	if type(actionName) ~= "string" or actionName == "" then
		return false
	end
	local lowered = string.lower(actionName)
	return string.find(lowered, "fire", 1, true) ~= nil
end

function WeaponController:_resolveCachedMuzzleAttachment(rig)
	if not rig or not rig.Model or not rig.Model:IsA("Model") then
		return nil
	end

	local model = rig.Model
	local cache = self._muzzleAttachmentCache
	if type(cache) ~= "table" then
		cache = setmetatable({}, { __mode = "k" })
		self._muzzleAttachmentCache = cache
	end

	local cached = cache[model]
	if cached == false then
		return nil
	end

	if cached and cached.Parent then
		return cached
	end

	local resolved = Tracers:FindMuzzleAttachment(model)
	cache[model] = resolved or false
	return resolved
end

function WeaponController:_resolveActionSoundPitch(actionName, pitch)
	if type(pitch) == "number" then
		if self:_isLayeredWeaponActionSound(actionName) then
			return pitch * FIRE_SOUND_PITCH_RNG:NextNumber(FIRE_SOUND_PITCH_MIN, FIRE_SOUND_PITCH_MAX)
		end
		return pitch
	end

	if self:_isLayeredWeaponActionSound(actionName) then
		return FIRE_SOUND_PITCH_RNG:NextNumber(FIRE_SOUND_PITCH_MIN, FIRE_SOUND_PITCH_MAX)
	end

	return nil
end

function WeaponController:_stopWeaponActionSoundByAction(weaponId, slot, actionName)
	local actionKey = self:_getWeaponActionSoundKey(weaponId, slot, actionName)
	if not actionKey then
		return
	end
	self:_stopTrackedWeaponActionSound(actionKey, true)
end

function WeaponController:_stopTrackedWeaponActionSound(actionKey, replicateStop)
	if type(actionKey) ~= "string" or actionKey == "" then
		return
	end

	local entry = self._activeActionSounds and self._activeActionSounds[actionKey]
	if not entry then
		return
	end

	if entry.endedConn then
		entry.endedConn:Disconnect()
		entry.endedConn = nil
	end

	local sound = entry.sound
	if sound and sound.Parent then
		pcall(function()
			sound:Stop()
		end)
		pcall(function()
			sound:Destroy()
		end)
	end

	self._activeActionSounds[actionKey] = nil

	if replicateStop == true then
		VFXRep:Fire("Others", WEAPON_SOUND_MODULE_INFO, {
			category = "Weapon",
			stop = true,
			key = actionKey,
		})
	end
end

function WeaponController:_stopAllTrackedWeaponActionSounds(replicateStop)
	local active = self._activeActionSounds
	if type(active) ~= "table" then
		return
	end

	local actionKeys = {}
	for actionKey, _ in pairs(active) do
		table.insert(actionKeys, actionKey)
	end
	for _, actionKey in ipairs(actionKeys) do
		self:_stopTrackedWeaponActionSound(actionKey, replicateStop == true)
	end
end

function WeaponController:_playWeaponActionSound(weaponId, slot, actionName, pitch, _options)
	if actionName == "Equip" then
		LogService:Info("WEAPON_SOUND", "Equip sound requested", {
			weaponId = weaponId,
			slot = slot,
			action = actionName,
		})
	end

	local soundDef = nil
	local skinId = nil
	soundDef, skinId = self:_resolveWeaponActionSoundId(weaponId, slot, actionName)
	if not soundDef then
		if actionName == "Equip" then
			LogService:Warn("WEAPON_SOUND", "Equip sound not resolved", {
				weaponId = weaponId,
				slot = slot,
				action = actionName,
				skinId = skinId,
			})
		end
		return
	end

	local actionKey = self:_getWeaponActionSoundKey(weaponId, slot, actionName)
	if not actionKey then
		return
	end

	local now = os.clock()
	local last = self._lastActionSoundAt and self._lastActionSoundAt[actionKey] or 0
	local minInterval = (actionName == "Equip") and 0.045 or 0
	if minInterval > 0 and (now - last) < minInterval then
		if actionName == "Equip" then
			local soundKey = soundDef.SoundId
			if not soundKey and soundDef.Template then
				soundKey = soundDef.Template.Name
			end
			LogService:Info("WEAPON_SOUND", "Equip sound skipped by dedupe", {
				weaponId = weaponId,
				slot = slot,
				soundId = soundKey,
			})
		end
		return
	end
	self._lastActionSoundAt[actionKey] = now

	local layered = self:_isLayeredWeaponActionSound(actionName)
	local resolvedPitch = self:_resolveActionSoundPitch(actionName, pitch)
	if not layered then
		self:_stopTrackedWeaponActionSound(actionKey, false)
	end

	local localSound = self:_playLocalWeaponSound(soundDef, resolvedPitch, slot, actionName, weaponId)
	if actionName == "Equip" then
		local soundKey = soundDef.SoundId
		if not soundKey and soundDef.Template then
			soundKey = soundDef.Template:GetFullName()
		end
		LogService:Info("WEAPON_SOUND", "Equip sound play attempt", {
			weaponId = weaponId,
			slot = slot,
			soundId = soundKey,
			hasLocalSound = localSound ~= nil,
			parentedToViewmodel = self._viewmodelController ~= nil,
		})
	end

	if localSound then
		-- Fire sounds should layer; never cut a previous shot to replay.
		if not layered then
			local entry = {
				sound = localSound,
				endedConn = nil,
			}
			entry.endedConn = localSound.Ended:Connect(function()
				local activeEntry = self._activeActionSounds and self._activeActionSounds[actionKey]
				if activeEntry and activeEntry.sound == localSound then
					if activeEntry.endedConn then
						activeEntry.endedConn:Disconnect()
						activeEntry.endedConn = nil
					end
					self._activeActionSounds[actionKey] = nil
				end
			end)
			self._activeActionSounds[actionKey] = entry
		end
	end

	local payload = {
		category = "Weapon",
		weaponId = weaponId,
		action = actionName,
	}
	if type(skinId) == "string" and skinId ~= "" then
		payload.skinId = skinId
	end
	if type(resolvedPitch) == "number" then
		payload.pitch = resolvedPitch
	end
	if not layered then
		payload.key = actionKey
	end
	VFXRep:Fire("Others", WEAPON_SOUND_MODULE_INFO, payload)
end

function WeaponController:_playLocalWeaponSound(soundDef, pitch, slot, actionName, weaponId)
	if type(soundDef) ~= "table" then
		return nil
	end

	local parent = SoundService
	local viewmodelController = self._viewmodelController
	if viewmodelController then
		local rig = nil
		if type(viewmodelController.GetRigForSlot) == "function" and type(slot) == "string" and slot ~= "" then
			rig = viewmodelController:GetRigForSlot(slot)
		end
		if not rig and type(viewmodelController.GetActiveRig) == "function" then
			rig = viewmodelController:GetActiveRig()
		end
		if rig then
			if self:_isLayeredWeaponActionSound(actionName) and rig.Model and rig.Model:IsA("Model") then
				local muzzleAttachment = self:_resolveCachedMuzzleAttachment(rig)
				if muzzleAttachment then
					parent = muzzleAttachment
				end
			end

			if rig.Anchor and rig.Anchor:IsA("BasePart") then
				if parent == SoundService then
					parent = rig.Anchor
				end
			elseif rig.Model then
				local model = rig.Model
				local basePart = model.PrimaryPart
					or model:FindFirstChild("HumanoidRootPart", true)
					or model:FindFirstChildWhichIsA("BasePart", true)
				if parent == SoundService and basePart and basePart:IsA("BasePart") then
					parent = basePart
				end
			end
		end
	end

	if parent == SoundService then
		local character = LocalPlayer and LocalPlayer.Character
		if character then
			local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
			if root then
				parent = root
			end
		end
	end

	local sound = nil
	if soundDef.Template and soundDef.Template:IsA("Sound") then
		sound = soundDef.Template:Clone()
		if type(pitch) == "number" then
			sound.PlaybackSpeed = pitch
		end
	elseif type(soundDef.SoundId) == "string" and soundDef.SoundId ~= "" then
		sound = Instance.new("Sound")
		sound.SoundId = soundDef.SoundId
		sound.Volume = LOCAL_WEAPON_VOLUME
		if type(pitch) == "number" then
			sound.PlaybackSpeed = pitch
		end
		sound.RollOffMode = LOCAL_WEAPON_ROLLOFF_MODE
		sound.RollOffMinDistance = LOCAL_WEAPON_MIN_DISTANCE
		sound.RollOffMaxDistance = LOCAL_WEAPON_MAX_DISTANCE
	else
		return nil
	end

	local weaponSoundGroup = SoundService:FindFirstChild("Guns") or SoundService:FindFirstChild("SFX")
	if weaponSoundGroup and weaponSoundGroup:IsA("SoundGroup") then
		sound.SoundGroup = weaponSoundGroup
	end

	if self:_isLayeredWeaponActionSound(actionName) then
		local closePreset = "Gun_Close"
		if weaponId == "Shorty" then
			closePreset = "Gun_NeutralClose"
		end
		SoundManager:ApplyPresets(sound, {
			closePreset,
			SoundManager:GetIsIndoor() and "Indoor" or "Outdoor",
		})
	end

	sound.Parent = parent
	sound:Play()

	if actionName == "Equip" then
		local soundKey = soundDef.SoundId
		if not soundKey and soundDef.Template then
			soundKey = soundDef.Template:GetFullName()
		end
		LogService:Info("WEAPON_SOUND", "Equip sound instance played", {
			soundId = soundKey,
			parent = sound.Parent and sound.Parent:GetFullName() or "nil",
			isPlaying = sound.IsPlaying,
		})
	end

	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 0.5)
	return sound
end

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
			local track = self:_playViewmodelAnimation(name, fade, restart)
			self:_replicateViewmodelAction("PlayAnimation", name, true)
			if track then
				self:_watchReplicatedTrackStop("PlayAnimation", name, track)
			end
			return track
		end,
		PlayWeaponTrack = function(name, fade)
			if self._viewmodelController and self._viewmodelController.PlayWeaponTrack then
				local track = self._viewmodelController:PlayWeaponTrack(name, fade)
				self:_replicateViewmodelAction("PlayWeaponTrack", name, true)
				if track then
					self:_watchReplicatedTrackStop("PlayWeaponTrack", name, track)
				end
				return track
			end
			return nil
		end,

		-- Raycast helpers
		PerformRaycast = function(ignoreSpread, extraSpreadMultiplier)
			return self:_performRaycast(weaponConfig, ignoreSpread, extraSpreadMultiplier)
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
		PlayActionSound = function(actionName, pitch, options)
			self:_playWeaponActionSound(weaponId, slot, actionName, pitch, options)
		end,
		StopActionSound = function(actionName)
			self:_stopWeaponActionSoundByAction(weaponId, slot, actionName)
		end,

		-- State management
		GetIsReloading = function()
			return self._isReloading
		end,
		SetIsReloading = function(value)
			self._isReloading = value == true
			if not self._isReloading then
				self._reloadFireLocked = false
			end
		end,
		GetReloadFireLocked = function()
			return self._reloadFireLocked == true
		end,
		SetReloadFireLocked = function(value)
			self._reloadFireLocked = value == true
		end,
		CanFireDuringReload = function()
			local ammoData = self._ammo and slot and self._ammo:GetAmmo(slot) or nil
			local currentAmmo = ammoData and ammoData.currentAmmo or 0
			if currentAmmo <= 0 then
				return false
			end
			return self._reloadFireLocked ~= true
		end,
		GetReloadToken = function()
			return self._reloadToken
		end,
		SetReloadToken = function(value)
			self._reloadToken = tonumber(value) or 0
		end,
		IncrementReloadToken = function()
			self._reloadToken = self._reloadToken + 1
			return self._reloadToken
		end,
		GetCurrentAmmo = function()
			local ammoData = self._ammo and slot and self._ammo:GetAmmo(slot) or nil
			if ammoData then
				return ammoData.currentAmmo or 0
			end
			return 0
		end,
		GetReserveAmmo = function()
			local ammoData = self._ammo and slot and self._ammo:GetAmmo(slot) or nil
			if ammoData then
				return ammoData.reserveAmmo or 0
			end
			return 0
		end,
		DecrementAmmo = function()
			if not self._ammo or not slot then
				return false
			end
			local ok = self._ammo:DecrementAmmo(slot, weaponConfig, LocalPlayer, self._isReloading, function()
				return self:_getCurrentSlot()
			end)
			if ok and self._weaponInstance and self._weaponInstance.State then
				self._weaponInstance.State.CurrentAmmo = self._ammo:GetCurrentAmmo(slot)
			end
			return ok
		end,
		ApplyState = function(nextState)
			if type(nextState) ~= "table" then
				return
			end

			if type(nextState.IsReloading) == "boolean" then
				self._isReloading = nextState.IsReloading
			end
			if type(nextState.ReloadFireLocked) == "boolean" then
				self._reloadFireLocked = nextState.ReloadFireLocked
			elseif not self._isReloading then
				self._reloadFireLocked = false
			end
			if type(nextState.LastFireTime) == "number" then
				self:_setLastFireTimeForSlot(slot, nextState.LastFireTime)
			end

			if self._ammo and slot then
				self._ammo:ApplyState(nextState, slot, weaponConfig, LocalPlayer, self._isReloading, function()
					return self:_getCurrentSlot()
				end)
			end

			if self._weaponInstance and self._weaponInstance.State then
				local stateRef = self._weaponInstance.State
				if type(nextState.CurrentAmmo) == "number" then
					stateRef.CurrentAmmo = nextState.CurrentAmmo
				end
				if type(nextState.ReserveAmmo) == "number" then
					stateRef.ReserveAmmo = nextState.ReserveAmmo
				end
				stateRef.IsReloading = self._isReloading
				stateRef.ReloadFireLocked = self._reloadFireLocked
				stateRef.LastFireTime = self:_getLastFireTimeForSlot(slot)
			end
		end,
		CancelReload = function()
			if self._currentActions and self._currentActions.Reload and self._currentActions.Reload.Interrupt then
				self._currentActions.Reload.Interrupt(self._weaponInstance)
				return
			end
			if self._currentActions and self._currentActions.Reload and self._currentActions.Reload.Cancel then
				self._currentActions.Reload.Cancel(self._weaponInstance)
			end
		end,

		-- State object (updated each call)
		State = {
			CurrentAmmo = ammo and ammo.currentAmmo or 0,
			ReserveAmmo = ammo and ammo.reserveAmmo or 0,
			IsReloading = self._isReloading,
			ReloadFireLocked = self._reloadFireLocked,
			IsAttacking = self._isFiring,
			LastFireTime = self:_getLastFireTimeForSlot(slot),
			Equipped = self:_isActiveWeaponEquipped() and not self:_isEquipLocked(),
		},
	}
end

function WeaponController:_updateWeaponInstanceState()
	if not self._weaponInstance then
		return
	end

	local slot = self:_getCurrentSlot()
	local ammo = self._ammo and self._ammo:GetAmmo(slot) or nil
	local previousState = self._weaponInstance.State
	local nextState = {}
	if type(previousState) == "table" then
		for key, value in pairs(previousState) do
			nextState[key] = value
		end
	end

	nextState.CurrentAmmo = ammo and ammo.currentAmmo or 0
	nextState.ReserveAmmo = ammo and ammo.reserveAmmo or 0
	nextState.IsReloading = self._isReloading
	nextState.ReloadFireLocked = self._reloadFireLocked
	nextState.IsAttacking = self._isFiring
	nextState.LastFireTime = self:_getLastFireTimeForSlot(slot)
	nextState.Equipped = self:_isActiveWeaponEquipped() and not self:_isEquipLocked()

	self._weaponInstance.State = nextState
end

-- =============================================================================
-- ACTIONS
-- =============================================================================

function WeaponController:_onFirePressed()
local currentTime = workspace:GetServerTimeNow()

	-- Between-round lock: server sets AttackDisabled during between-round phase
	if LocalPlayer and LocalPlayer:GetAttribute("AttackDisabled") then
		return
	end

	-- During loadout (MatchFrozen): only allow firing when in first person
	if LocalPlayer and LocalPlayer:GetAttribute("MatchFrozen") then
		if not self:_isFirstPerson() then
			return
		end
	end

	if not self:_isActiveWeaponEquipped() then
		return
	end
	if self:_isEquipLocked() then
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
				self._isADS = self:_resolveADSState(false)
				self:_updateAimAssistADS(self._isADS)
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
	self:_applyCameraRecoil()

	-- Update state after attack
	local resolvedShotTime = currentTime
	if self._weaponInstance and self._weaponInstance.State and type(self._weaponInstance.State.LastFireTime) == "number" then
		resolvedShotTime = self._weaponInstance.State.LastFireTime
	end
	self:_setLastFireTimeForSlot(self:_getCurrentSlot(), resolvedShotTime)
	self._lastShotWeaponId = self._equippedWeaponId
	self._lastShotTime = resolvedShotTime
	self:_updateWeaponInstanceState()
end

function WeaponController:_canQuickMeleeFromWeapon(weaponConfig)
	if not weaponConfig then
		return false
	end

	local actionFlags = weaponConfig.actions
	if actionFlags and actionFlags.canQuickUseMelee ~= nil then
		return actionFlags.canQuickUseMelee == true
	end

	return weaponConfig.weaponType ~= "Melee"
end

function WeaponController:_clearQuickMeleeSession(reason)
	local session = self._quickMeleeSession
	if session then
		quickMeleeLog("Session cleared", {
			reason = reason or "Unknown",
			sessionId = session.id,
			returnSlot = session.returnSlot,
			isReturning = session.isReturning,
		})
	end
	self._quickMeleeSession = nil
end

function WeaponController:_startQuickMeleeSession(returnSlot, sourceSlot)
	self._quickMeleeToken = (self._quickMeleeToken or 0) + 1

	local session = {
		id = self._quickMeleeToken,
		returnSlot = returnSlot,
		sourceSlot = sourceSlot,
		reachedMelee = false,
		returnPending = type(returnSlot) == "string" and returnSlot ~= "" and returnSlot ~= "Melee",
		isReturning = false,
		skipEquipAnimation = true,
		readyToReturnAt = os.clock() + 0.12,
		nextReturnAttemptAt = 0,
	}

	self._quickMeleeSession = session
	quickMeleeLog("Session started", {
		sessionId = session.id,
		sourceSlot = sourceSlot,
		returnSlot = returnSlot,
		returnPending = session.returnPending,
	})
	return session
end

function WeaponController:_isQuickMeleeSessionActive(sessionId)
	local session = self._quickMeleeSession
	return session ~= nil and session.id == sessionId
end

function WeaponController:_onQuickMeleeSlotChanged(slot)
	local session = self._quickMeleeSession
	if not session then
		return
	end

	quickMeleeLog("Slot changed during session", {
		sessionId = session.id,
		slot = slot,
		isReturning = session.isReturning,
		returnSlot = session.returnSlot,
	})

	if session.isReturning then
		self:_clearQuickMeleeSession("SlotChangedWhileReturning")
		return
	end

	if slot == "Melee" then
		session.reachedMelee = true
		return
	end

	-- Ignore pre-equip slot updates (source slot heartbeat) until we actually reach melee.
	if session.reachedMelee ~= true then
		quickMeleeLog("Ignoring pre-melee slot update", {
			sessionId = session.id,
			slot = slot,
			sourceSlot = session.sourceSlot,
		})
		return
	end

	-- After reaching melee, any non-melee slot is a manual cancel.
	if slot ~= "Melee" then
		self:_clearQuickMeleeSession("ManualSwapCanceled")
	end
end

function WeaponController:_isQuickMeleeActionBlocking()
	if self._isReloading or self._isFiring then
		return true
	end

	local actions = self._currentActions
	if not actions then
		return false
	end

	if actions.Special and type(actions.Special.IsActive) == "function" then
		local ok, active = pcall(function()
			return actions.Special.IsActive()
		end)
		if ok and active == true then
			return true
		end
	end

	if actions.Inspect and type(actions.Inspect.IsInspecting) == "function" then
		local ok, inspecting = pcall(function()
			return actions.Inspect.IsInspecting()
		end)
		if ok and inspecting == true then
			return true
		end
	end

	if actions.Attack and type(actions.Attack.IsActive) == "function" then
		local ok, attacking = pcall(function()
			return actions.Attack.IsActive()
		end)
		if ok and attacking == true then
			return true
		end
	end

	return false
end

function WeaponController:_attemptQuickMeleeReturn(session)
	if not self._viewmodelController then
		self:_clearQuickMeleeSession("NoViewmodelForReturn")
		return
	end

	local returnSlot = session.returnSlot
	if type(returnSlot) ~= "string" or returnSlot == "" or returnSlot == "Melee" then
		self:_clearQuickMeleeSession("InvalidReturnSlot")
		return
	end

	session.isReturning = true
	session.nextReturnAttemptAt = os.clock() + 0.1
	quickMeleeLog("Attempting return", {
		sessionId = session.id,
		returnSlot = returnSlot,
	})

	if type(self._viewmodelController._tryEquipSlotFromLoadout) == "function" then
		self._viewmodelController:_tryEquipSlotFromLoadout(returnSlot)
		return
	end

	if type(self._viewmodelController.SetActiveSlot) == "function" then
		self._viewmodelController:SetActiveSlot(returnSlot)
		return
	end

	self:_clearQuickMeleeSession("ReturnEquipUnavailable")
end

function WeaponController:_scheduleQuickMeleeReturn(sessionId)
	task.spawn(function()
		while true do
			local session = self._quickMeleeSession
			if not session or session.id ~= sessionId then
				return
			end

			if not session.returnPending then
				self:_clearQuickMeleeSession("ReturnNotPending")
				return
			end

			local activeSlot = self._viewmodelController and self._viewmodelController:GetActiveSlot()
			if session.isReturning then
				if activeSlot == session.returnSlot then
					self:_clearQuickMeleeSession("ReturnedToPreviousSlot")
					return
				end
				if activeSlot ~= "Melee" then
					self:_clearQuickMeleeSession("ReturnInterruptedBySlotChange")
					return
				end
			elseif activeSlot ~= "Melee" then
				-- Manual slot change canceled quick melee.
				self:_clearQuickMeleeSession("ManualSlotChangeBeforeReturn")
				return
			end

			local now = os.clock()
			if now < session.readyToReturnAt then
				RunService.Heartbeat:Wait()
				continue
			end

			if self:_isQuickMeleeActionBlocking() then
				local nowBlocked = os.clock()
				if not session._lastBlockedLogAt or nowBlocked - session._lastBlockedLogAt > 0.5 then
					session._lastBlockedLogAt = nowBlocked
					quickMeleeLog("Return blocked by active action", {
						sessionId = session.id,
						isReloading = self._isReloading,
						isFiring = self._isFiring,
					})
				end
				RunService.Heartbeat:Wait()
				continue
			end

			if now >= (session.nextReturnAttemptAt or 0) then
				self:_attemptQuickMeleeReturn(session)
			end

			RunService.Heartbeat:Wait()
		end
	end)
end

function WeaponController:_requestEquipMelee()
	if not self._viewmodelController then
		quickMeleeLog("Equip melee failed: no viewmodel controller")
		return false
	end

	local loadout = self._viewmodelController._loadout
	if type(loadout) ~= "table" then
		quickMeleeLog("Equip melee failed: invalid loadout")
		return false
	end

	local meleeWeaponId = loadout.Melee
	if type(meleeWeaponId) ~= "string" or meleeWeaponId == "" then
		quickMeleeLog("Equip melee failed: no melee weapon in loadout")
		return false
	end
	quickMeleeLog("Equip melee requested", { meleeWeaponId = meleeWeaponId })

	if type(self._viewmodelController.SkipNextEquipAnimation) == "function" then
		self._viewmodelController:SkipNextEquipAnimation()
	end

	if type(self._viewmodelController._tryEquipSlotFromLoadout) == "function" then
		self._viewmodelController:_tryEquipSlotFromLoadout("Melee")
	elseif type(self._viewmodelController.SetActiveSlot) == "function" then
		self._viewmodelController:SetActiveSlot("Melee")
	else
		quickMeleeLog("Equip melee failed: no equip function on viewmodel")
		return false
	end

	return true
end

function WeaponController:_executeQuickMeleeAction()
	if not self._weaponInstance or not self._currentActions then
		quickMeleeLog("Execute quick melee aborted", { reason = "NoWeapon" })
		return false, "NoWeapon"
	end

	if self._weaponInstance.WeaponType ~= "Melee" then
		quickMeleeLog("Execute quick melee aborted", {
			reason = "NotMelee",
			weaponType = self._weaponInstance.WeaponType,
			weaponId = self._weaponInstance.WeaponId,
		})
		return false, "NotMelee"
	end

	local activeSlot = self._viewmodelController and self._viewmodelController:GetActiveSlot()
	if not self:_isActiveWeaponEquipped() and activeSlot ~= "Melee" then
		quickMeleeLog("Execute quick melee aborted", {
			reason = "NotEquipped",
			activeSlot = activeSlot,
			equippedWeaponId = self._equippedWeaponId,
		})
		return false, "NotEquipped"
	end

	self:_updateWeaponInstanceState()
	if self._weaponInstance.State then
		-- Quick melee should still execute even if camera mode is not first-person.
		self._weaponInstance.State.Equipped = true
	end

	local now = workspace:GetServerTimeNow()
	local main = self._currentActions.Main
	if main and type(main.QuickAction) == "function" then
		local ok, reason = main.QuickAction(self._weaponInstance, now)
		quickMeleeLog("Main.QuickAction executed", { ok = ok, reason = reason })
		return ok, reason
	end

	local quickAction = self._currentActions.QuickAction
	if quickAction and type(quickAction.Execute) == "function" then
		local ok, reason = quickAction.Execute(self._weaponInstance, now)
		quickMeleeLog("QuickAction.Execute executed", { ok = ok, reason = reason })
		return ok, reason
	end

	if self._currentActions.Attack and type(self._currentActions.Attack.Execute) == "function" then
		local ok, reason = self._currentActions.Attack.Execute(self._weaponInstance, now)
		quickMeleeLog("Attack.Execute fallback executed", { ok = ok, reason = reason })
		return ok, reason
	end

	quickMeleeLog("Execute quick melee aborted", { reason = "NoQuickAction" })
	return false, "NoQuickAction"
end

function WeaponController:QuickMelee()
	if not self._viewmodelController then
		quickMeleeLog("QuickMelee rejected", { reason = "NoViewmodel" })
		return false, "NoViewmodel"
	end

	local activeSlot = self._viewmodelController:GetActiveSlot()
	local needsEquip = activeSlot ~= "Melee"
	local returnSlot = needsEquip and activeSlot or nil
	quickMeleeLog("QuickMelee requested", {
		activeSlot = activeSlot,
		needsEquip = needsEquip,
		returnSlot = returnSlot,
		equippedWeaponId = self._equippedWeaponId,
	})

	if needsEquip then
		local currentConfig = self._weaponInstance and self._weaponInstance.Config
		if not self:_canQuickMeleeFromWeapon(currentConfig) then
			quickMeleeLog("QuickMelee rejected", { reason = "QuickMeleeDisabled" })
			return false, "QuickMeleeDisabled"
		end
	end

	local session = self:_startQuickMeleeSession(returnSlot, activeSlot)

	if needsEquip and not self:_requestEquipMelee() then
		self:_clearQuickMeleeSession("EquipMeleeRequestFailed")
		return false, "NoMelee"
	end

	local sessionId = session.id

	task.spawn(function()
		if needsEquip then
			local deadline = os.clock() + 1.5
			local gotMeleeEquipped = false
			while os.clock() < deadline do
				if not self:_isQuickMeleeSessionActive(sessionId) then
					return
				end

				local currentSlot = self._viewmodelController and self._viewmodelController:GetActiveSlot()
				if currentSlot == "Melee" and self._weaponInstance and self._weaponInstance.WeaponType == "Melee" then
					gotMeleeEquipped = true
					break
				end

				RunService.Heartbeat:Wait()
			end

			if not gotMeleeEquipped then
				quickMeleeLog("Equip wait timed out", {
					sessionId = sessionId,
					activeSlot = self._viewmodelController and self._viewmodelController:GetActiveSlot(),
					equippedWeaponId = self._equippedWeaponId,
					weaponType = self._weaponInstance and self._weaponInstance.WeaponType or nil,
				})
			end
		end

		if not self:_isQuickMeleeSessionActive(sessionId) then
			return
		end

		if not self._weaponInstance or self._weaponInstance.WeaponType ~= "Melee" then
			local activeSession = self._quickMeleeSession
			if activeSession and activeSession.id == sessionId and activeSession.returnPending then
				self:_attemptQuickMeleeReturn(activeSession)
			else
				self:_clearQuickMeleeSession("MeleeWeaponInstanceMissing")
			end
			return
		end

		local actionOk, actionReason = self:_executeQuickMeleeAction()
		quickMeleeLog("Quick melee execute result", {
			sessionId = sessionId,
			ok = actionOk,
			reason = actionReason,
		})

		if not self:_isQuickMeleeSessionActive(sessionId) then
			return
		end

		local activeSession = self._quickMeleeSession
		if not activeSession or activeSession.id ~= sessionId then
			return
		end

		if activeSession.returnPending then
			quickMeleeLog("Scheduling return to previous slot", {
				sessionId = sessionId,
				returnSlot = activeSession.returnSlot,
			})
			self:_scheduleQuickMeleeReturn(sessionId)
		else
			self:_clearQuickMeleeSession("NoReturnNeeded")
		end
	end)

	return true
end

function WeaponController:Reload()
	if LocalPlayer and LocalPlayer:GetAttribute("AttackDisabled") then
		return
	end

	if not self._currentActions then
		return
	end

	if not self._weaponInstance then
		return
	end

	-- During loadout (MatchFrozen): only allow reload when in first person
	if LocalPlayer and LocalPlayer:GetAttribute("MatchFrozen") and not self:_isFirstPerson() then
		return
	end

	-- Update state
	self:_updateWeaponInstanceState()

	-- If reload is invalid (full mag, no reserve, etc), do nothing.
	-- This prevents reload input from interrupting active animations/actions.
	local canReloadFn = self._currentActions.Main and self._currentActions.Main.CanReload
	if type(canReloadFn) == "function" then
		local canReload = canReloadFn(self._weaponInstance)
		if not canReload then
			return
		end
	end

	-- Reload should stop any ongoing weapon actions first.
	self._isFiring = false
	self:_stopAutoFire()
	if self._currentActions.Attack and self._currentActions.Attack.Cancel then
		self._currentActions.Attack.Cancel(self._weaponInstance)
	end

	-- Reload should always stop inspect.
	if
		self._currentActions.Inspect
		and self._currentActions.Inspect.IsInspecting
		and self._currentActions.Inspect.IsInspecting()
		and self._currentActions.Inspect.Cancel
	then
		self._currentActions.Inspect.Cancel()
	end

	-- Reload should always stop ADS/special to avoid FOV/ADS state desync.
	if self._currentActions.Special and self._currentActions.Special.Cancel then
		self._currentActions.Special.Cancel()
	end
	self._isADS = false
	self:_setADSActiveAttribute(false)
	self:_applyMouseSensitivityForADS(false)
	self:_updateAimAssistADS(false)
	self:_stopWeaponTracks("Reload")

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

	if self._isReloading or self._isFiring then
		return
	end

	if self:IsADS() then
		return
	end

	-- Execute inspect
	if self._currentActions.Inspect then
		local ok = self._currentActions.Inspect.Execute(self._weaponInstance)
		if ok then
			self:_replicateViewmodelAction("Inspect", "Inspect", true)
			LogService:Debug("WEAPON", "Inspecting", { weaponId = self._equippedWeaponId })
		end
	end
end

function WeaponController:Special(isPressed)
	if LocalPlayer and LocalPlayer:GetAttribute("AttackDisabled") then
		return
	end

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

	if self._isReloading then
		if
			self._currentActions.Special
			and self._currentActions.Special.IsActive
			and self._currentActions.Special.IsActive()
			and self._currentActions.Special.Cancel
		then
			self._currentActions.Special.Cancel()
		end
		self._isADS = false
		self:_setADSActiveAttribute(false)
		self:_applyMouseSensitivityForADS(false)
		self:_updateAimAssistADS(false)
		return
	end

	-- Check cancel logic
	local cancels = self:_getCancels()

	-- Cancel reload on special
	if isPressed and cancels.SpecialCancelsReload then
		if self._isReloading and self._currentActions.Reload and self._currentActions.Reload.Cancel then
			self._currentActions.Reload.Cancel(self._weaponInstance)
		end
	end

	-- Execute special
	if self._currentActions.Special then
		self._currentActions.Special.Execute(self._weaponInstance, isPressed)
	end

	self._isADS = self:_resolveADSState(isPressed)
	self:_setADSActiveAttribute(self._isADS)
	self:_applyMouseSensitivityForADS(self._isADS)

	-- Apply Aim Assist ADS boost
	self:_updateAimAssistADS(self._isADS)

	local weaponType = self._weaponInstance and self._weaponInstance.WeaponType or "Gun"
	if weaponType == "Gun" then
		local trackName = self._isADS and "ADS" or "Hip"
		self:_replicateViewmodelAction("ADS", trackName, self._isADS)
	else
		self:_replicateViewmodelAction("Special", "Special", isPressed)
	end
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

		-- Start auto-shoot if target is in sight and ADS-only is enabled
		if self._hasAutoShootTarget and AimAssistConfig.AutoShoot.ADSOnly then
			self:_startAutoShootIfEnabled()
		end
	else
		-- Deactivate ADS (restore base strengths)
		self._aimAssist:deactivateADS()

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

	if self:_isEquipLocked() then
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

function WeaponController:_replicateViewmodelAction(actionName, trackName, isActive)
	if type(actionName) ~= "string" or actionName == "" then
		return
	end

	if not self._replicationController and self._registry then
		self._replicationController = self._registry:TryGet("Replication")
	end

	local replicationController = self._replicationController
	if not replicationController or type(replicationController.ReplicateViewmodelAction) ~= "function" then
		return
	end

	local weaponId = self._equippedWeaponId or (self._weaponInstance and self._weaponInstance.WeaponId)
	if not weaponId or weaponId == "" then
		return
	end

	local slot = self:_getCurrentSlot()
	local skinId = self:_getSkinIdForSlot(slot)
	if type(skinId) ~= "string" then
		skinId = ""
	end

	if isActive ~= true and type(trackName) == "string" and trackName ~= "" then
		local trackKey = string.format("%s|%s", tostring(actionName), tostring(trackName))
		self:_clearReplicatedTrackStopWatch(trackKey)
	end

	replicationController:ReplicateViewmodelAction(weaponId, skinId, actionName, trackName or "", isActive == true)
end

function WeaponController:_clearReplicatedTrackStopWatch(trackKey)
	local connectionMap = self._replicatedTrackStopConnections
	if type(connectionMap) ~= "table" then
		self._replicatedTrackStopConnections = {}
		return
	end

	if trackKey == nil then
		for key, connections in pairs(connectionMap) do
			if type(connections) == "table" then
				for _, connection in ipairs(connections) do
					if typeof(connection) == "RBXScriptConnection" then
						connection:Disconnect()
					end
				end
			end
			connectionMap[key] = nil
		end
		self._replicatedTrackStopTokens = {}
		return
	end

	local connections = connectionMap[trackKey]
	if type(connections) == "table" then
		for _, connection in ipairs(connections) do
			if typeof(connection) == "RBXScriptConnection" then
				connection:Disconnect()
			end
		end
	end
	connectionMap[trackKey] = nil
end

function WeaponController:_watchReplicatedTrackStop(actionName, trackName, track)
	if type(actionName) ~= "string" or actionName == "" then
		return
	end
	if type(trackName) ~= "string" or trackName == "" then
		return
	end
	if type(track) ~= "userdata" then
		return
	end

	local trackKey = string.format("%s|%s", tostring(actionName), tostring(trackName))
	local tokenMap = self._replicatedTrackStopTokens
	if type(tokenMap) ~= "table" then
		tokenMap = {}
		self._replicatedTrackStopTokens = tokenMap
	end

	local token = (tokenMap[trackKey] or 0) + 1
	tokenMap[trackKey] = token
	self:_clearReplicatedTrackStopWatch(trackKey)

	local emitted = false
	local function replicateStop()
		if emitted then
			return
		end
		if tokenMap[trackKey] ~= token then
			return
		end
		emitted = true
		self:_clearReplicatedTrackStopWatch(trackKey)
		self:_replicateViewmodelAction(actionName, trackName, false)
	end

	local connections = {
		track.Stopped:Connect(replicateStop),
		track.Ended:Connect(replicateStop),
	}
	self._replicatedTrackStopConnections[trackKey] = connections
end

function WeaponController:_getViewmodelTrack(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end

	local viewmodelController = self._viewmodelController
	if not viewmodelController then
		return nil
	end

	local animator = viewmodelController._animator
	if not animator or type(animator.GetTrack) ~= "function" then
		return nil
	end

	return animator:GetTrack(name)
end

function WeaponController:_playViewmodelAnimation(name, fade, restart)
	if self._viewmodelController and type(self._viewmodelController.PlayViewmodelAnimation) == "function" then
		self._viewmodelController:PlayViewmodelAnimation(name, fade, restart)
		return self:_getViewmodelTrack(name)
	end
	return nil
end

function WeaponController:_stopWeaponTracks(exceptTrackName)
	if not self._viewmodelController then
		return
	end

	local animator = self._viewmodelController._animator
	if not animator then
		return
	end

	local tracks = animator._tracks
	if type(tracks) ~= "table" then
		return
	end

	for trackName, track in pairs(tracks) do
		if trackName ~= exceptTrackName and track and track.IsPlaying then
			pcall(function()
				track:Stop(0.05)
			end)
		end
	end
end

function WeaponController:_performRaycast(weaponConfig, ignoreSpread, extraSpreadMultiplier)
	local spreadMultiplier = 1

	if not ignoreSpread and LocalPlayer and weaponConfig then
		local crosshairData = weaponConfig.crosshair or {}
		local spreadFactors = weaponConfig.spreadFactors or {}
		local movementState = self._crosshair
			and self._crosshair._getMovementState
			and self._crosshair:_getMovementState()

		local horizontalSpeed = 0
		local character = LocalPlayer.Character
		local root = character and (character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart"))
		if root then
			local velocity = root.AssemblyLinearVelocity
			horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		end

		local baseSpeedReference = tonumber(spreadFactors.speedReference) or tonumber(spreadFactors.velocityReference) or 20
		if baseSpeedReference <= 0 then
			baseSpeedReference = 20
		end
		local baseSpeedMaxBonus = tonumber(spreadFactors.speedMaxBonus)
		if baseSpeedMaxBonus == nil then
			baseSpeedMaxBonus = tonumber(spreadFactors.velocityMaxBonus) or 0.8
		end
		baseSpeedMaxBonus = math.max(baseSpeedMaxBonus, 0)

		local function resolveSpreadFactor(key, fallback)
			local customValue = spreadFactors[key]
			if type(customValue) == "number" then
				return customValue
			end
			local legacyValue = crosshairData[key]
			if type(legacyValue) == "number" then
				return legacyValue
			end
			return fallback
		end

		local isADS = movementState and movementState.isADS == true
		local speedReference = baseSpeedReference
		local speedMaxBonus = baseSpeedMaxBonus
		if isADS then
			local adsSpeedReference = tonumber(spreadFactors.adsSpeedReference) or tonumber(spreadFactors.adsVelocityReference)
			local adsSpeedMaxBonus = tonumber(spreadFactors.adsSpeedMaxBonus) or tonumber(spreadFactors.adsVelocityMaxBonus)
			if adsSpeedReference and adsSpeedReference > 0 then
				speedReference = adsSpeedReference
			end
			if adsSpeedMaxBonus then
				speedMaxBonus = math.max(adsSpeedMaxBonus, 0)
			end
		end

		local movementBoost = 1 + math.clamp(horizontalSpeed / speedReference, 0, 1) * speedMaxBonus
		spreadMultiplier *= movementBoost

		if movementState then
			if movementState.isCrouching then
				spreadMultiplier *= resolveSpreadFactor("crouchMult", 1)
			elseif movementState.isSliding then
				spreadMultiplier *= resolveSpreadFactor("slideMult", 1)
			elseif movementState.isSprinting then
				spreadMultiplier *= resolveSpreadFactor("sprintMult", 1)
			end

			if movementState.isGrounded == false then
				spreadMultiplier *= resolveSpreadFactor("airMult", 1)
			end

			if movementState.isADS then
				spreadMultiplier *= resolveSpreadFactor("adsMult", 1)
			else
				spreadMultiplier *= resolveSpreadFactor("hipfireMult", 1)
			end
		else
			spreadMultiplier *= resolveSpreadFactor("hipfireMult", 1)
		end

		local minMultiplier = tonumber(spreadFactors.minMultiplier) or 0
		local maxMultiplier = tonumber(spreadFactors.maxMultiplier) or math.huge
		if maxMultiplier < minMultiplier then
			maxMultiplier = minMultiplier
		end
		spreadMultiplier = math.clamp(spreadMultiplier, minMultiplier, maxMultiplier)
	end

	local externalSpread = tonumber(extraSpreadMultiplier)
	if externalSpread and externalSpread > 0 then
		spreadMultiplier *= externalSpread
	end

	return WeaponRaycast.PerformRaycast(self._camera, LocalPlayer, weaponConfig, ignoreSpread, spreadMultiplier)
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
	local isADS = self:_resolveADSState(self._isADS)
	if isADS then
		local adsRecoilMult = recoilCfg.adsMultiplier
			or recoilCfg.adsRecoilMultiplier
			or (weaponConfig and weaponConfig.adsEffectsMultiplier)
			or 0.35
		kickPos *= adsRecoilMult
		kickRot *= adsRecoilMult
	end

	self._viewmodelController:ApplyRecoil(kickPos, kickRot)

	-- Render tracer immediately (client-side prediction)
	if SHOW_TRACERS and hitData then
		hitData._localShot = true
		hitData.weaponId = weaponId
		-- Populate gunModel from viewmodel rig so muzzle FX can find the attachment
		if not hitData.gunModel then
			local rig = self._viewmodelController:GetActiveRig()
			hitData.gunModel = rig and rig.Model or nil
		end
		self:_renderBulletTracer(hitData)
	end
end

function WeaponController:_onHitConfirmed(hitData)
	if not hitData then
		return
	end

	local localUserId = LocalPlayer and LocalPlayer.UserId or nil
	local localCharacter = LocalPlayer and LocalPlayer.Character or nil
	local localCharacterName = localCharacter and localCharacter.Name or nil

	-- Tracers are now rendered immediately in _playFireEffects (client-side prediction)
	-- Only render here for OTHER players' shots (so we see their tracers)
	if SHOW_TRACERS and hitData.shooter ~= localUserId then
		-- Populate gunModel from shooter's 3rd person weapon for muzzle flash
		if not hitData.gunModel and hitData.shooter then
			local RemoteReplicator = require(
				ReplicatedStorage:WaitForChild("Game"):WaitForChild("Replication"):WaitForChild("RemoteReplicator")
			)
			local remoteData = RemoteReplicator.RemotePlayers[hitData.shooter]
			if remoteData and remoteData.WeaponManager then
				hitData.gunModel = remoteData.WeaponManager:GetWeaponModel()
			end
		end
		self:_renderBulletTracer(hitData)
	end

	local didHitTarget = hitData.hitPlayer ~= nil
		or (type(hitData.hitCharacterName) == "string" and hitData.hitCharacterName ~= "")
	local isLocalPlayerHit = localUserId ~= nil and hitData.hitPlayer == localUserId
	local isLocalCharacterHit = localCharacterName ~= nil and hitData.hitCharacterName == localCharacterName
	local shouldShowHitmarker = hitData.shooter == localUserId and didHitTarget and not isLocalPlayerHit and not isLocalCharacterHit

	if hitData.shooter == localUserId then
		hitmarkerDebug("HitConfirmed", {
			shooter = hitData.shooter,
			hitPlayer = hitData.hitPlayer,
			hitCharacterName = hitData.hitCharacterName,
			localUserId = localUserId,
			localCharacterName = localCharacterName,
			didHitTarget = didHitTarget,
			isLocalPlayerHit = isLocalPlayerHit,
			isLocalCharacterHit = isLocalCharacterHit,
			shouldShowHitmarker = shouldShowHitmarker,
		})
	end

	if shouldShowHitmarker then
		self:_showHitmarker(hitData)
	end

	if hitData.hitPlayer == localUserId then
		self:_showDamageIndicator(hitData)
	end
end

function WeaponController:_renderBulletTracer(hitData)
	if not hitData then
		return
	end

	if not hitData.weaponId and self._equippedWeaponId then
		hitData.weaponId = self._equippedWeaponId
	end

	if not hitData.gunModel and hitData._localShot == true and self._viewmodelController then
		local rig = self._viewmodelController:GetActiveRig()
		hitData.gunModel = rig and rig.Model or nil
	end

	if self._fx then
		self._fx:RenderBulletTracer(hitData)
	end
end

function WeaponController:_showHitmarker(hitData)
	if self._crosshair and type(self._crosshair.ShowHitmarker) == "function" then
		self._crosshair:ShowHitmarker(hitData and hitData.isHeadshot == true)
	end
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
		self:_applyMouseSensitivityForADS(self._isADS == true)
	end
end

function WeaponController:GetADSSpeedMultiplier(): number
	if LocalPlayer then
		return LocalPlayer:GetAttribute("ADSSpeedMultiplier") or 1.0
	end
	return 1.0
end

function WeaponController:IsADS(): boolean
	self._isADS = self:_resolveADSState(self._isADS)
	return self._isADS == true
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
