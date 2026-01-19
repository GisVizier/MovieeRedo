local WeaponController = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))

local DEBUG_WEAPON = false
local SHOW_TRACERS = true

local ShotgunActionsRoot = ReplicatedStorage:WaitForChild("Game")
	:WaitForChild("Weapons")
	:WaitForChild("Actions")
	:WaitForChild("Gun")
	:WaitForChild("Shotgun")
local ShotgunAttack = require(ShotgunActionsRoot:WaitForChild("Attack"))
local ShotgunReload = require(ShotgunActionsRoot:WaitForChild("Reload"))
local ShotgunInspect = require(ShotgunActionsRoot:WaitForChild("Inspect"))

local WeaponServices = script.Parent:WaitForChild("Services")
local WeaponAmmo = require(WeaponServices:WaitForChild("WeaponAmmo"))
local WeaponRaycast = require(WeaponServices:WaitForChild("WeaponRaycast"))
local WeaponFX = require(WeaponServices:WaitForChild("WeaponFX"))

local LocalPlayer = Players.LocalPlayer

WeaponController._registry = nil
WeaponController._net = nil
WeaponController._inputManager = nil
WeaponController._viewmodelController = nil
WeaponController._camera = nil
WeaponController._ammo = nil
WeaponController._fx = nil
WeaponController._reloadToken = 0

WeaponController._isFiring = false
WeaponController._lastFireTime = 0
WeaponController._currentWeaponId = nil
WeaponController._isAutomatic = false
WeaponController._autoFireConn = nil
WeaponController._isReloading = false

function WeaponController:Init(registry, net)
	self._registry = registry
	self._net = net
	self._camera = workspace.CurrentCamera
	self._ammo = WeaponAmmo.new(LoadoutConfig, HttpService)
	self._fx = WeaponFX.new(LoadoutConfig, LogService)

	-- Listen for hit confirmations from server
	if self._net then
		self._net:ConnectClient("HitConfirmed", function(hitData)
			self:_onHitConfirmed(hitData)
		end)
	end

	LogService:Info("WEAPON", "WeaponController initialized")
end

function WeaponController:Start()
	LocalPlayer = Players.LocalPlayer
	local inputController = self._registry:TryGet("Input")
	self._inputManager = inputController and inputController.Manager
	self._viewmodelController = self._registry:TryGet("Viewmodel")

	-- Connect to Fire input
	if self._inputManager then
		self._inputManager:ConnectToInput("Fire", function(isFiring)
			self._isFiring = isFiring
			if isFiring then
				self:_onFirePressed()
				self:_startAutoFire()
			else
				self:_stopAutoFire()
			end
		end)

		-- Connect to Reload input
		self._inputManager:ConnectToInput("Reload", function(isPressed)
			if isPressed and not self._isReloading then
				self:Reload()
			end
		end)

		-- Connect to Inspect input
		self._inputManager:ConnectToInput("Inspect", function(isPressed)
			if isPressed and not self._isReloading and not self._isFiring then
				self:Inspect()
			end
		end)
	end

	-- Initialize ammo when loadout changes
	if LocalPlayer then
		LocalPlayer:GetAttributeChangedSignal("SelectedLoadout"):Connect(function()
			self:_initializeAmmo()
		end)

		-- Initialize on start if loadout already exists
		task.defer(function()
			self:_initializeAmmo()
		end)
	end

	LogService:Info("WEAPON", "WeaponController started")
end

function WeaponController:_initializeAmmo()
	if not LocalPlayer or not self._ammo then
		return
	end

	self._ammo:InitializeFromLoadout(LocalPlayer, self._isReloading, function()
		return self:_getCurrentSlot()
	end)

	print("[WEAPON] Ammo initialized for all slots")
end

function WeaponController:_getCurrentSlot()
	if not self._viewmodelController or not self._viewmodelController._activeSlot then
		return "Primary"
	end

	local slot = self._viewmodelController._activeSlot
	if slot == "Fists" then
		return "Primary"
	end

	return slot
end

function WeaponController:_isShotgunWeapon(weaponId)
	return weaponId == "Shotgun"
end

function WeaponController:_cancelReload(weaponConfig)
	if not self._isReloading then
		return
	end

	self._isReloading = false
	self._reloadToken = self._reloadToken + 1

	if self._ammo and weaponConfig then
		self._ammo:UpdateHUDAmmo(self:_getCurrentSlot(), weaponConfig, LocalPlayer, self._isReloading, function()
			return self:_getCurrentSlot()
		end)
	end
end

function WeaponController:_playViewmodelAnimation(name, fade, restart)
	if self._viewmodelController and type(self._viewmodelController.PlayViewmodelAnimation) == "function" then
		self._viewmodelController:PlayViewmodelAnimation(name, fade, restart)
	end
end

function WeaponController:_buildWeaponInstance(weaponId, weaponConfig, slot)
	local ammo = self._ammo and slot and self._ammo:GetAmmo(slot) or nil
	return {
		Player = LocalPlayer,
		WeaponType = weaponConfig and weaponConfig.weaponType or "Gun",
		WeaponName = weaponId,
		Config = weaponConfig,
		Animator = self._viewmodelController and self._viewmodelController._animator or nil,
		FireProfile = weaponConfig and self:_getFireProfile(weaponConfig) or nil,
		Net = self._net,
		PerformRaycast = function(ignoreSpread)
			return self:_performRaycast(weaponConfig, ignoreSpread)
		end,
		GeneratePelletDirections = function(profile)
			return self:_generatePelletDirections(profile)
		end,
		PlayFireEffects = function(hitData)
			self:_playFireEffects(weaponId, hitData)
		end,
		RenderTracer = function(hitData)
			self:_renderBulletTracer(hitData)
		end,
		PlayAnimation = function(name, fade, restart)
			self:_playViewmodelAnimation(name, fade, restart)
		end,
		ApplyState = function(state)
			self:_applyWeaponInstanceState({ State = state }, slot, weaponConfig)
		end,
		State = {
			CurrentAmmo = ammo and ammo.currentAmmo or 0,
			ReserveAmmo = ammo and ammo.reserveAmmo or 0,
			IsReloading = self._isReloading,
			IsAttacking = self._isFiring,
			LastFireTime = self._lastFireTime,
			Equipped = true,
		},
	}
end

function WeaponController:_applyWeaponInstanceState(weaponInstance, slot, weaponConfig)
	if not weaponInstance or not weaponInstance.State then
		return
	end

	local state = weaponInstance.State

	if type(state.LastFireTime) == "number" then
		self._lastFireTime = state.LastFireTime
	end

	local nextReloading = self._isReloading
	if type(state.IsReloading) == "boolean" then
		nextReloading = state.IsReloading
		self._isReloading = state.IsReloading
	end

	if self._ammo then
		self._ammo:ApplyState(state, slot, weaponConfig, LocalPlayer, nextReloading, function()
			return self:_getCurrentSlot()
		end)
	end
end

function WeaponController:_getCurrentAmmo()
	local slot = self:_getCurrentSlot()
	return self._ammo and self._ammo:GetCurrentAmmo(slot) or 0
end

function WeaponController:_decrementAmmo()
	local slot = self:_getCurrentSlot()
	if not self._ammo then
		return false
	end

	local weaponId = self:_getCurrentWeaponId()
	local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)
	return self._ammo:DecrementAmmo(slot, weaponConfig, LocalPlayer, self._isReloading, function()
		return self:_getCurrentSlot()
	end)
end

function WeaponController:_getFireProfile(weaponConfig)
	local profile = weaponConfig.fireProfile or {}
	return {
		mode = profile.mode or "Semi",
		autoReloadOnEmpty = profile.autoReloadOnEmpty ~= false,
		pelletsPerShot = profile.pelletsPerShot or weaponConfig.pelletsPerShot,
		spread = profile.spread or weaponConfig.spread,
	}
end

function WeaponController:_isAutoFire(profile)
	return profile.mode == "Auto"
end

function WeaponController:_isShotgun(profile)
	return profile.mode == "Shotgun" and profile.pelletsPerShot and profile.pelletsPerShot > 1
end

function WeaponController:_onFirePressed()
	local currentTime = os.clock()

	-- Get current weapon
	local weaponId = self:_getCurrentWeaponId()
	if not weaponId or weaponId == "Fists" then
		return
	end

	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		return
	end

	-- Allow manual reload interruption if there's still ammo in mag
	if self._isReloading then
		if self:_getCurrentAmmo() > 0 and not self:_isShotgunWeapon(weaponId) then
			self:_cancelReload(weaponConfig)
		else
			return
		end
	end

	local fireProfile = self:_getFireProfile(weaponConfig)
	local isShotgunWeapon = self:_isShotgunWeapon(weaponId)

	if isShotgunWeapon then
		local slot = self:_getCurrentSlot()
		local weaponInstance = self:_buildWeaponInstance(weaponId, weaponConfig, slot)
		local ok, reason = ShotgunAttack.Execute(weaponInstance, currentTime)

		if not ok then
			if reason == "NoAmmo" and fireProfile.autoReloadOnEmpty and not self._isReloading then
				self:Reload()
			end
			return
		end

		self:_applyWeaponInstanceState(weaponInstance, slot, weaponConfig)
		return
	else
		-- Check ammo
		local currentAmmo = self:_getCurrentAmmo()
		if currentAmmo <= 0 then
			-- Auto-reload when clicking with empty magazine
			if fireProfile.autoReloadOnEmpty and not self._isReloading then
				self:Reload()
			end
			return
		end

		-- Fire rate check
		local fireInterval = 60 / (weaponConfig.fireRate or 600)
		if currentTime - self._lastFireTime < fireInterval then
			return
		end

		self._lastFireTime = currentTime

		-- Decrement ammo
		self:_decrementAmmo()
	end

	-- Generate pellet directions for shotgun-style weapons
	local pelletDirections = nil
	if self:_isShotgun(fireProfile) then
		pelletDirections = self:_generatePelletDirections({
			pelletsPerShot = fireProfile.pelletsPerShot,
			spread = fireProfile.spread or 0.15,
		})
	end

	-- Perform client-side raycast for tracer/feedback
	local hitData = self:_performRaycast(weaponConfig, pelletDirections ~= nil)

	if hitData then
		-- Send to server for validation
		print(string.format("[WeaponController] Firing %s at %s", weaponId, tostring(hitData.hitPosition)))

		self._net:FireServer("WeaponFired", {
			weaponId = weaponId,
			timestamp = currentTime,
			origin = hitData.origin,
			direction = hitData.direction,
			hitPart = hitData.hitPart,
			hitPosition = hitData.hitPosition,
			hitPlayer = hitData.hitPlayer,
			hitCharacter = hitData.hitCharacter, -- NEW: Send character model
			isHeadshot = hitData.isHeadshot,
			pelletDirections = pelletDirections,
		})

		-- Play local effects immediately (client prediction)
		self:_playFireEffects(weaponId, hitData)
	end
end

function WeaponController:_startAutoFire()
	if self._autoFireConn then
		return
	end

	local weaponId = self:_getCurrentWeaponId()
	if not weaponId or weaponId == "Fists" then
		return
	end

	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		return
	end

	local fireProfile = self:_getFireProfile(weaponConfig)

	-- Only enable auto-fire for high fire rate weapons (assault rifles)
	if self:_isAutoFire(fireProfile) then
		self._isAutomatic = true
		local fireInterval = 60 / weaponConfig.fireRate

		self._autoFireConn = game:GetService("RunService").Heartbeat:Connect(function()
			if self._isFiring and self._isAutomatic then
				self:_onFirePressed()
			end
		end)
	end
end

function WeaponController:_stopAutoFire()
	self._isAutomatic = false
	if self._autoFireConn then
		self._autoFireConn:Disconnect()
		self._autoFireConn = nil
	end
end

function WeaponController:_performRaycast(weaponConfig, ignoreSpread)
	return WeaponRaycast.PerformRaycast(self._camera, LocalPlayer, weaponConfig, ignoreSpread)
end

function WeaponController:_getSpreadDirection(baseDirection, spread)
	return WeaponRaycast.GetSpreadDirection(baseDirection, spread)
end

function WeaponController:_generatePelletDirections(weaponConfig)
	return WeaponRaycast.GeneratePelletDirections(self._camera, weaponConfig)
end

function WeaponController:_getCurrentWeaponId()
	if not self._viewmodelController or not self._viewmodelController._activeSlot then
		return nil
	end

	local slot = self._viewmodelController._activeSlot
	local loadout = self._viewmodelController._loadout

	if slot == "Fists" then
		return "Fists"
	end

	return loadout and loadout[slot]
end

function WeaponController:_playFireEffects(weaponId, hitData)
	if DEBUG_WEAPON then
		print("[WEAPON] _playFireEffects called for:", weaponId)
		print("[WEAPON] viewmodelController exists:", self._viewmodelController ~= nil)
	end

	-- Play Fire animation on viewmodel
	if not self:_isShotgunWeapon(weaponId) and self._viewmodelController then
		if DEBUG_WEAPON then
			print("[WEAPON] Animator found")
		end
		local animator = self._viewmodelController._animator
		local track = nil
		if type(self._viewmodelController.PlayWeaponTrack) == "function" then
			track = self._viewmodelController:PlayWeaponTrack("Fire", 0.05)
		elseif animator and type(animator.GetTrack) == "function" then
			track = animator:GetTrack("Fire")
			if track then
				track:Play(0.05)
			end
		end

		if track then
			if DEBUG_WEAPON then
				print("[WEAPON] Fire track exists, playing now")
			end
		else
			if DEBUG_WEAPON then
				warn("[WEAPON] Fire track NOT FOUND in animator tracks!")
				-- List all available tracks
				local tracks = animator._tracks or {}
				for name, _ in pairs(tracks) do
					warn("[WEAPON] Available track:", name)
				end
			end
		end
	else
		if DEBUG_WEAPON then
			warn("[WEAPON] ViewmodelController or animator NOT FOUND!")
			warn("[WEAPON] viewmodelController:", self._viewmodelController)
			if self._viewmodelController then
				warn("[WEAPON] animator:", self._viewmodelController._animator)
			end
		end
	end

	-- TODO: Play muzzle flash VFX
	-- TODO: Add recoil camera shake
	-- TODO: Add fire sound effect

	if DEBUG_WEAPON then
		LogService:Debug("WEAPON", "Fire effects", { weaponId = weaponId })
	end
end

function WeaponController:_onHitConfirmed(hitData)
	if not hitData then
		return
	end

	-- Render bullet tracer for observers or confirmation
	if SHOW_TRACERS then
		self:_renderBulletTracer(hitData)
	end

	-- Show hitmarker if we're the shooter
	if hitData.shooter == LocalPlayer.UserId then
		self:_showHitmarker(hitData)
	end

	-- Show damage indicator if we're the victim
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

function WeaponController:Reload()
	local weaponId = self:_getCurrentWeaponId()
	if not weaponId or weaponId == "Fists" then
		return
	end

	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig or not weaponConfig.reloadTime then
		return
	end

	local slot = self:_getCurrentSlot()
	local ammo = self._ammo and self._ammo:GetAmmo(slot) or nil

	if not ammo then
		return
	end

	local isShotgunWeapon = self:_isShotgunWeapon(weaponId)
	if isShotgunWeapon then
		local weaponInstance = self:_buildWeaponInstance(weaponId, weaponConfig, slot)
		local ok = ShotgunReload.Execute(weaponInstance)
		if not ok then
			return
		end
		if weaponInstance.ApplyState then
			weaponInstance.ApplyState(weaponInstance.State)
		end
		return
	else
		-- Don't reload if already full
		if ammo.currentAmmo >= weaponConfig.clipSize then
			print("[WEAPON] Already full, no reload needed")
			return
		end

		-- Don't reload if no reserve ammo
		if ammo.reserveAmmo <= 0 then
			print("[WEAPON] No reserve ammo to reload")
			return
		end
	end

	print("[WEAPON] Reload started for:", weaponId)

	-- Play reload animation
	if not self:_isShotgunWeapon(weaponId) and self._viewmodelController then
		local track = nil
		if type(self._viewmodelController.PlayWeaponTrack) == "function" then
			track = self._viewmodelController:PlayWeaponTrack("Reload", 0.1)
		end
		if track then
			print("[WEAPON] Reload track exists, playing")
		else
			warn("[WEAPON] Reload track NOT FOUND (animation may not exist)")
		end
	end

	-- Set reloading state
	self._isReloading = true
	self._reloadToken = self._reloadToken + 1
	local reloadToken = self._reloadToken

	-- Update HUD to show reloading
	if self._ammo then
		self._ammo:UpdateHUDAmmo(slot, weaponConfig, LocalPlayer, self._isReloading, function()
			return self:_getCurrentSlot()
		end)
	end

	LogService:Info("WEAPON", "Reloading", {
		weaponId = weaponId,
		duration = weaponConfig.reloadTime,
		currentAmmo = ammo.currentAmmo,
		reserveAmmo = ammo.reserveAmmo,
	})

	-- Wait for reload animation to complete
	task.delay(weaponConfig.reloadTime, function()
		if not self._isReloading or reloadToken ~= self._reloadToken then
			return
		end

		-- Calculate ammo to reload
		local neededAmmo = weaponConfig.clipSize - ammo.currentAmmo
		local ammoToReload = math.min(neededAmmo, ammo.reserveAmmo)

		-- Refill current ammo
		ammo.currentAmmo = ammo.currentAmmo + ammoToReload
		ammo.reserveAmmo = ammo.reserveAmmo - ammoToReload

		self._isReloading = false

		-- Update HUD
		if self._ammo then
			self._ammo:UpdateHUDAmmo(slot, weaponConfig, LocalPlayer, self._isReloading, function()
				return self:_getCurrentSlot()
			end)
		end

		LogService:Info("WEAPON", "Reload complete", {
			weaponId = weaponId,
			currentAmmo = ammo.currentAmmo,
			reserveAmmo = ammo.reserveAmmo,
		})
	end)
end

function WeaponController:Inspect()
	local weaponId = self:_getCurrentWeaponId()
	if not weaponId or weaponId == "Fists" then
		return
	end

	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if weaponConfig and self:_isShotgunWeapon(weaponId) then
		local slot = self:_getCurrentSlot()
		local weaponInstance = self:_buildWeaponInstance(weaponId, weaponConfig, slot)
		local ok = ShotgunInspect.Execute(weaponInstance)
		if not ok then
			return
		end
	end

	print("[WEAPON] Inspect called for:", weaponId)

	-- Play inspect animation
	if not self:_isShotgunWeapon(weaponId) and self._viewmodelController then
		local track = nil
		if type(self._viewmodelController.PlayWeaponTrack) == "function" then
			track = self._viewmodelController:PlayWeaponTrack("Inspect", 0.1)
		end
		if track then
			print("[WEAPON] Inspect track exists, playing")
		else
			warn("[WEAPON] Inspect track NOT FOUND")
		end
	end

	LogService:Debug("WEAPON", "Inspecting", { weaponId = weaponId })
end

function WeaponController:Destroy()
	self:_stopAutoFire()
end

return WeaponController
