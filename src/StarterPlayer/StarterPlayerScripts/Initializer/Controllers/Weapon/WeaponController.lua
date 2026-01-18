local WeaponController = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))

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
	end

	LogService:Info("WEAPON", "WeaponController started")
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

	-- Fire rate check
	local fireInterval = 60 / (weaponConfig.fireRate or 600)
	if currentTime - self._lastFireTime < fireInterval then
		return
	end

	self._lastFireTime = currentTime

	-- Perform client-side raycast
	local hitData = self:_performRaycast(weaponConfig)

	if hitData then
		-- Send to server for validation
		self._net:FireServer("WeaponFired", {
			weaponId = weaponId,
			timestamp = currentTime,
			origin = hitData.origin,
			direction = hitData.direction,
			hitPart = hitData.hitPart,
			hitPosition = hitData.hitPosition,
			hitPlayer = hitData.hitPlayer,
			isHeadshot = hitData.isHeadshot,
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

	-- Only enable auto-fire for high fire rate weapons (assault rifles)
	if weaponConfig.fireRate and weaponConfig.fireRate > 300 then
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

function WeaponController:_performRaycast(weaponConfig)
	local camera = self._camera
	if not camera then
		return nil
	end

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector.Unit
	local range = weaponConfig.range or 500

	-- Apply spread if weapon has it
	if weaponConfig.spread and weaponConfig.spread > 0 then
		local spreadX = (math.random() - 0.5) * weaponConfig.spread
		local spreadY = (math.random() - 0.5) * weaponConfig.spread
		direction = (direction + Vector3.new(spreadX, spreadY, 0)).Unit
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
	local filterList = {camera}
	if character then
		table.insert(filterList, character)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local result = workspace:Raycast(origin, direction * range, raycastParams)

	if result then
		local hitPlayer = Players:GetPlayerFromCharacter(result.Instance.Parent)
		local isHeadshot = result.Instance.Name == "Head"

		return {
			origin = origin,
			direction = direction,
			hitPart = result.Instance,
			hitPosition = result.Position,
			hitPlayer = hitPlayer,
			isHeadshot = isHeadshot,
			travelTime = weaponConfig.projectileSpeed and
				(result.Position - origin).Magnitude / weaponConfig.projectileSpeed,
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
	-- TODO: Play muzzle flash, recoil, sound
	-- ViewmodelController can handle this via its animator
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

function WeaponController:Destroy()
	self:_stopAutoFire()
end

return WeaponController
