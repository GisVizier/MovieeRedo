local WeaponController = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))

local ShotgunActionsRoot = ReplicatedStorage:WaitForChild("Game")
	:WaitForChild("Weapons")
	:WaitForChild("Actions")
	:WaitForChild("Gun")
	:WaitForChild("Shotgun")
local ShotgunAttack = require(ShotgunActionsRoot:WaitForChild("Attack"))
local ShotgunReload = require(ShotgunActionsRoot:WaitForChild("Reload"))
local ShotgunInspect = require(ShotgunActionsRoot:WaitForChild("Inspect"))

local LocalPlayer = Players.LocalPlayer

WeaponController._registry = nil
WeaponController._net = nil
WeaponController._inputManager = nil
WeaponController._viewmodelController = nil
WeaponController._camera = nil

WeaponController._isFiring = false
WeaponController._lastFireTime = 0
WeaponController._currentWeaponId = nil
WeaponController._isAutomatic = false
WeaponController._autoFireConn = nil
WeaponController._isReloading = false

-- Ammo tracking per slot
WeaponController._ammoData = {
	Primary = { currentAmmo = 0, reserveAmmo = 0 },
	Secondary = { currentAmmo = 0, reserveAmmo = 0 },
	Melee = { currentAmmo = 0, reserveAmmo = 0 },
}

function WeaponController:Init(registry, net)
	self._registry = registry
	self._net = net
	self._camera = workspace.CurrentCamera

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
	if not LocalPlayer then
		return
	end

	local loadoutJson = LocalPlayer:GetAttribute("SelectedLoadout")
	if not loadoutJson or loadoutJson == "" then
		return
	end

	local success, loadoutData = pcall(function()
		return HttpService:JSONDecode(loadoutJson)
	end)

	if not success then
		return
	end

	local loadout = loadoutData.loadout or loadoutData

	-- Initialize ammo for each weapon slot
	for _, slotType in ipairs({ "Primary", "Secondary", "Melee" }) do
		local weaponId = loadout[slotType]
		local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)

		if weaponConfig then
			self._ammoData[slotType] = {
				currentAmmo = weaponConfig.clipSize or 0,
				reserveAmmo = weaponConfig.maxAmmo or 0,
			}

			-- Update HUD for this slot
			self:_updateHUDAmmo(slotType, weaponConfig)
		end
	end

	print("[WEAPON] Ammo initialized for all slots")
end

function WeaponController:_updateHUDAmmo(slotType, weaponConfig)
	if not LocalPlayer then
		return
	end

	local ammo = self._ammoData[slotType]
	if not ammo then
		return
	end

	-- Build weapon data for HUD
	local weaponData = {
		Gun = weaponConfig.name,
		GunId = weaponConfig.id,
		GunType = weaponConfig.weaponType,
		Ammo = ammo.currentAmmo,
		MaxAmmo = ammo.reserveAmmo,
		ClipSize = weaponConfig.clipSize,
		Reloading = self._isReloading and self:_getCurrentSlot() == slotType,
		OnCooldown = false,
		Cooldown = weaponConfig.cooldown or 0,
		ReloadTime = weaponConfig.reloadTime or 0,
		Rarity = weaponConfig.rarity,
		UpdatedAt = os.clock(),
	}

	-- Force attribute update even if JSON string is identical.
	local attrName = slotType .. "Data"
	LocalPlayer:SetAttribute(attrName, nil)
	LocalPlayer:SetAttribute(attrName, HttpService:JSONEncode(weaponData))
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

function WeaponController:_buildWeaponInstance(weaponId, weaponConfig, slot)
	local ammo = slot and self._ammoData[slot] or nil
	return {
		Player = LocalPlayer,
		WeaponType = weaponConfig and weaponConfig.weaponType or "Gun",
		WeaponName = weaponId,
		Config = weaponConfig,
		Animator = self._viewmodelController and self._viewmodelController._animator or nil,
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
	local ammo = slot and self._ammoData[slot] or nil

	if ammo then
		if type(state.CurrentAmmo) == "number" then
			ammo.currentAmmo = state.CurrentAmmo
		end
		if type(state.ReserveAmmo) == "number" then
			ammo.reserveAmmo = state.ReserveAmmo
		end
	end

	if type(state.LastFireTime) == "number" then
		self._lastFireTime = state.LastFireTime
	end
	if type(state.IsReloading) == "boolean" then
		self._isReloading = state.IsReloading
	end

	if weaponConfig and ammo then
		self:_updateHUDAmmo(slot, weaponConfig)
	end
end

function WeaponController:_getCurrentAmmo()
	local slot = self:_getCurrentSlot()
	local ammo = self._ammoData[slot]
	return ammo and ammo.currentAmmo or 0
end

function WeaponController:_decrementAmmo()
	local slot = self:_getCurrentSlot()
	local ammo = self._ammoData[slot]

	if ammo and ammo.currentAmmo > 0 then
		ammo.currentAmmo = ammo.currentAmmo - 1

		-- Update HUD
		local weaponId = self:_getCurrentWeaponId()
		local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)
		if weaponConfig then
			self:_updateHUDAmmo(slot, weaponConfig)
		end

		return true
	end

	return false
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

	-- Block firing while reloading
	if self._isReloading then
		return
	end

	-- Get current weapon
	local weaponId = self:_getCurrentWeaponId()
	if not weaponId or weaponId == "Fists" then
		return
	end

	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		return
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
	local camera = self._camera
	if not camera then
		return nil
	end

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector.Unit
	local range = weaponConfig.range or 500

	-- Apply spread if weapon has it
	if not ignoreSpread and weaponConfig.spread and weaponConfig.spread > 0 then
		direction = self:_getSpreadDirection(direction, weaponConfig.spread)
	end

	-- Calculate bullet drop if projectile
	local targetPosition = origin + direction * range

	if weaponConfig.projectileSpeed and weaponConfig.bulletDrop then
		-- Calculate travel time
		local distance = range
		local travelTime = distance / weaponConfig.projectileSpeed

		-- Calculate drop: d = 0.5 * g * t²
		local gravity = weaponConfig.gravity or workspace.Gravity
		local dropAmount = 0.5 * gravity * (travelTime ^ 2)

		-- Adjust target downward
		targetPosition = targetPosition - Vector3.new(0, dropAmount, 0)

		-- Recalculate direction to compensate
		direction = (targetPosition - origin).Unit
	end

	-- Perform raycast
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local character = LocalPlayer.Character
	local filterList = { camera }
	if character then
		table.insert(filterList, character)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(origin, direction * range, raycastParams)

	if result then
		local hitPlayer = Players:GetPlayerFromCharacter(result.Instance.Parent)
		local isHeadshot = result.Instance.Name == "Head"

		-- Check if we hit a character/rig (has Humanoid)
		local hitCharacter = nil
		if result.Instance.Parent:FindFirstChildOfClass("Humanoid") then
			hitCharacter = result.Instance.Parent
		end

		return {
			origin = origin,
			direction = direction,
			hitPart = result.Instance,
			hitPosition = result.Position,
			hitPlayer = hitPlayer,
			hitCharacter = hitCharacter, -- NEW: Send the character model
			isHeadshot = isHeadshot,
			travelTime = weaponConfig.projectileSpeed
				and (result.Position - origin).Magnitude / weaponConfig.projectileSpeed,
		}
	end

	return {
		origin = origin,
		direction = direction,
		hitPart = nil,
		hitPosition = targetPosition,
		hitPlayer = nil,
		isHeadshot = false,
	}
end

function WeaponController:_getSpreadDirection(baseDirection, spread)
	-- Generate a random direction within a cone around baseDirection
	local angle = math.random() * math.pi * 2
	local radius = math.random() * spread
	local offset = Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)

	local basis = CFrame.lookAt(Vector3.zero, baseDirection)
	local right = basis.RightVector
	local up = basis.UpVector

	return (baseDirection + right * offset.X + up * offset.Y).Unit
end

function WeaponController:_generatePelletDirections(weaponConfig)
	local camera = self._camera
	if not camera then
		return nil
	end

	local baseDirection = camera.CFrame.LookVector.Unit
	local spread = weaponConfig.spread or 0.05
	local pellets = weaponConfig.pelletsPerShot or 1
	local directions = {}

	for _ = 1, pellets do
		table.insert(directions, self:_getSpreadDirection(baseDirection, spread))
	end

	return directions
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
	print("[WEAPON] _playFireEffects called for:", weaponId)
	print("[WEAPON] viewmodelController exists:", self._viewmodelController ~= nil)

	-- Play Fire animation on viewmodel
	if not self:_isShotgunWeapon(weaponId) and self._viewmodelController and self._viewmodelController._animator then
		print("[WEAPON] Animator found")
		local animator = self._viewmodelController._animator
		local track = animator:GetTrack("Fire")

		if track then
			print("[WEAPON] Fire track exists, playing now")
			track:Play(0.05)
		else
			warn("[WEAPON] Fire track NOT FOUND in animator tracks!")
			-- List all available tracks
			local tracks = animator._tracks or {}
			for name, _ in pairs(tracks) do
				warn("[WEAPON] Available track:", name)
			end
		end
	else
		warn("[WEAPON] ViewmodelController or animator NOT FOUND!")
		warn("[WEAPON] viewmodelController:", self._viewmodelController)
		if self._viewmodelController then
			warn("[WEAPON] animator:", self._viewmodelController._animator)
		end
	end

	-- TODO: Play muzzle flash VFX
	-- TODO: Add recoil camera shake
	-- TODO: Add fire sound effect

	LogService:Debug("WEAPON", "Fire effects", { weaponId = weaponId })
end

function WeaponController:_onHitConfirmed(hitData)
	if not hitData then
		return
	end

	-- Render bullet tracer for observers or confirmation
	self:_renderBulletTracer(hitData)

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
	local weaponConfig = LoadoutConfig.getWeapon(hitData.weaponId)
	if not weaponConfig then
		return
	end

	-- Simple tracer for now
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local distance = (hitData.hitPosition - hitData.origin).Magnitude
	part.Size = Vector3.new(0.1, 0.1, distance)
	part.CFrame = CFrame.lookAt((hitData.origin + hitData.hitPosition) / 2, hitData.hitPosition)
	part.Color = weaponConfig.tracerColor or Color3.fromRGB(255, 200, 100)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.3
	part.Parent = workspace

	-- Fade out
	task.spawn(function()
		for i = 1, 10 do
			part.Transparency = 0.3 + (i / 10) * 0.7
			task.wait(0.01)
		end
		part:Destroy()
	end)
end

function WeaponController:_showHitmarker(hitData)
	-- TODO: Show crosshair hitmarker
	LogService:Debug("WEAPON", "Hitmarker", { damage = hitData.damage, headshot = hitData.isHeadshot })
end

function WeaponController:_showDamageIndicator(hitData)
	-- TODO: Show damage direction indicator
	LogService:Debug("WEAPON", "Taking damage", { damage = hitData.damage })
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
	local ammo = self._ammoData[slot]

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
		self:_applyWeaponInstanceState(weaponInstance, slot, weaponConfig)
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
	if not self:_isShotgunWeapon(weaponId) and self._viewmodelController and self._viewmodelController._animator then
		local animator = self._viewmodelController._animator
		local track = animator:GetTrack("Reload")

		if track then
			print("[WEAPON] Reload track exists, playing")
			track:Play(0.1)
		else
			warn("[WEAPON] Reload track NOT FOUND (animation may not exist)")
		end
	end

	-- Set reloading state
	self._isReloading = true

	-- Update HUD to show reloading
	self:_updateHUDAmmo(slot, weaponConfig)

	LogService:Info("WEAPON", "Reloading", {
		weaponId = weaponId,
		duration = weaponConfig.reloadTime,
		currentAmmo = ammo.currentAmmo,
		reserveAmmo = ammo.reserveAmmo,
	})

	-- Wait for reload animation to complete
	task.delay(weaponConfig.reloadTime, function()
		-- Calculate ammo to reload
		local neededAmmo = weaponConfig.clipSize - ammo.currentAmmo
		local ammoToReload = math.min(neededAmmo, ammo.reserveAmmo)

		-- Refill current ammo
		ammo.currentAmmo = ammo.currentAmmo + ammoToReload
		ammo.reserveAmmo = ammo.reserveAmmo - ammoToReload

		self._isReloading = false

		-- Update HUD
		self:_updateHUDAmmo(slot, weaponConfig)

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
	if not self:_isShotgunWeapon(weaponId) and self._viewmodelController and self._viewmodelController._animator then
		local animator = self._viewmodelController._animator
		local track = animator:GetTrack("Inspect")

		if track then
			print("[WEAPON] Inspect track exists, playing")
			track:Play(0.1)
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
