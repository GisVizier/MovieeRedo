local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ConnectionManager = require(ReplicatedStorage.CoreUI.ConnectionManager)
local CrosshairSystem = ReplicatedStorage:WaitForChild("CrosshairSystem")
local CrosshairsFolder = CrosshairSystem:WaitForChild("Crosshairs")
local ServiceRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("ServiceRegistry"))

-- DEBUG LOGGING
local DEBUG_CROSSHAIR = false
local DEBUG_LOG_INTERVAL = 1 -- Only log every N seconds to avoid spam
local lastDebugTime = 0

-- Lazy load MovementStateManager to avoid circular dependencies
local MovementStateManager = nil
local function getMovementStateManager()
	if MovementStateManager then
		return MovementStateManager
	end
	pcall(function()
		local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
		MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
	end)
	return MovementStateManager
end

local CrosshairController = {}
CrosshairController.__index = CrosshairController

CrosshairController.Mock = {
	weaponData = {
		spreadX = 1.5,
		spreadY = 1.5,
		recoilMultiplier = 1.2,
	},
	customization = {
		showDot = true,
		showTopLine = true,
		showBottomLine = true,
		showLeftLine = true,
		showRightLine = true,
		lineThickness = 2,
		lineLength = 6,           -- Shorter lines for cleaner look
		gapFromCenter = 10,       -- Much wider gap - spread out more
		dotSize = 3,              -- Small centered dot
		rotation = 0,
		cornerRadius = 0,
		mainColor = Color3.fromRGB(255, 255, 255),
		outlineColor = Color3.fromRGB(0, 0, 0),
		outlineThickness = 0,     -- NO outline for cleaner look
		opacity = 0.95,
		scale = 1,
		dynamicSpreadEnabled = true,
	},
	player = nil,
	character = nil,
}

function CrosshairController.new(player: Player?)
	local self = setmetatable({}, CrosshairController)

	self._player = player or CrosshairController.Mock.player or Players.LocalPlayer
	self._connections = ConnectionManager.new()
	self._module = nil
	self._frame = nil
	self._weaponData = nil
	self._customization = nil
	self._rootPart = nil
	self._updateConnection = nil
	self._screenGui = nil
	self._templateContainer = nil
	self._hitmarker = nil
	self._hitmarkerScale = nil
	self._hitmarkerTween = nil
	self._hitmarkerFadeTween = nil
	self._hitmarkerBaseScale = 1
	self._hitmarkerHideSeq = 0
	self._hitmarkerLastHitTime = 0
	self._hitmarkerStack = 0
	self._moduleCache = {}
	self._moduleCacheWarmed = false
	self._hideReticleInADS = true
	self._reticleHidden = false
	self._reticleVisibilitySnapshot = {}

	self:_bindCharacter()
	self:_warmModuleCache()

	return self
end

function CrosshairController:_warmModuleCache()
	if self._moduleCacheWarmed then
		return
	end

	self._moduleCacheWarmed = true

	for _, child in ipairs(CrosshairsFolder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, moduleDef = pcall(require, child)
			if ok then
				self._moduleCache[child.Name] = moduleDef
			else
				warn("[CrosshairController] Failed to warm module cache:", child.Name, moduleDef)
			end
		end
	end
end

function CrosshairController:_bindCharacter()
	if not self._player then
		return
	end

	self._connections:track(self._player, "CharacterAdded", function(character)
		-- Support custom character system (Root) and default (HumanoidRootPart)
		self._rootPart = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	end, "character")

	local character = self._player.Character or CrosshairController.Mock.character
	if character then
		self._rootPart = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
	end
end

function CrosshairController:_resolveGui()
	if not self._player then
		return nil
	end

	if self._screenGui and self._templateContainer then
		return self._templateContainer
	end

	local playerGui = self._player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end

	local screenGui = playerGui:FindFirstChild("Crosshair")
	if not screenGui then
		return nil
	end

	local container = screenGui:FindFirstChild("Frame")
	if not container then
		return nil
	end

	self._screenGui = screenGui
	self._templateContainer = container

	return container
end

function CrosshairController:_loadModule(crosshairName: string)
	if not self._moduleCacheWarmed then
		self:_warmModuleCache()
	end

	local cached = self._moduleCache[crosshairName]
	if cached then
		return cached
	end

	local moduleScript = CrosshairsFolder:FindFirstChild(crosshairName)
	if not moduleScript then
		warn("[CrosshairController] Crosshair module missing:", crosshairName)
		return nil
	end

	local ok, moduleDef = pcall(require, moduleScript)
	if not ok then
		warn("[CrosshairController] Failed to require module:", crosshairName, moduleDef)
		return nil
	end

	self._moduleCache[crosshairName] = moduleDef
	return moduleDef
end

function CrosshairController:_cancelHitmarkerTweens()
	if self._hitmarkerTween then
		self._hitmarkerTween:Cancel()
		self._hitmarkerTween = nil
	end
	if self._hitmarkerRotationTween then
		self._hitmarkerRotationTween:Cancel()
		self._hitmarkerRotationTween = nil
	end
	if self._hitmarkerFadeTween then
		self._hitmarkerFadeTween:Cancel()
		self._hitmarkerFadeTween = nil
	end
end

function CrosshairController:_cacheHitmarker()
	self._hitmarker = nil
	self._hitmarkerScale = nil
	self._hitmarkerBaseScale = 1
	self._hitmarkerHideSeq = 0
	self._hitmarkerLastHitTime = 0
	self._hitmarkerStack = 0

	if not self._frame then
		return
	end

	local hitmarker = self._frame:FindFirstChild("Hitmarker", true)
	if not (hitmarker and hitmarker:IsA("ImageLabel")) then
		local container = self:_resolveGui()
		local defaultTemplate = container and container:FindFirstChild("Default")
		local defaultHitmarker = defaultTemplate and defaultTemplate:FindFirstChild("Hitmarker", true)
		if defaultHitmarker and defaultHitmarker:IsA("ImageLabel") then
			local clone = defaultHitmarker:Clone()
			clone.Name = "Hitmarker"
			clone.Visible = false
			clone.Parent = self._frame
			hitmarker = clone
		end
	end
	if not (hitmarker and hitmarker:IsA("ImageLabel")) then
		return
	end

	self._hitmarker = hitmarker
	self._hitmarker.ImageTransparency = 1
	self._hitmarker.Visible = false

	local markerScale = hitmarker:FindFirstChild("UIScale")
	if not (markerScale and markerScale:IsA("UIScale")) then
		markerScale = Instance.new("UIScale")
		markerScale.Scale = 1
		markerScale.Parent = hitmarker
	end
	self._hitmarkerScale = markerScale
	self._hitmarkerBaseScale = markerScale.Scale
end

function CrosshairController:ApplyCrosshair(crosshairName: string, weaponData: any?, player: Player?)
	if DEBUG_CROSSHAIR then
		print("[Crosshair] ApplyCrosshair called:", crosshairName)
	end
	
	if player then
		self._player = player
		self:_bindCharacter()
	end

	self:RemoveCrosshair()

	local container = self:_resolveGui()
	if not container then
		warn("[CrosshairController] Crosshair templates not found.")
		return
	end
	
	if DEBUG_CROSSHAIR then
		print("[Crosshair] Container found:", container:GetFullName())
		print("[Crosshair] Container children:")
		for _, child in container:GetChildren() do
			print("  -", child.Name, child.ClassName)
		end
	end

	local template = container:FindFirstChild(crosshairName)
	if not template then
		warn("[CrosshairController] Crosshair template missing:", crosshairName)
		return
	end
	
	if DEBUG_CROSSHAIR then
		print("[Crosshair] Template found:", template:GetFullName())
		print("[Crosshair] Template children:")
		for _, child in template:GetChildren() do
			print("  -", child.Name, child.ClassName)
			if child:IsA("Frame") or child:IsA("Folder") then
				for _, subChild in child:GetChildren() do
					print("    -", subChild.Name, subChild.ClassName)
				end
			end
		end
	end

	local moduleDef = self:_loadModule(crosshairName)
	if not moduleDef then
		return
	end

	local clone = template:Clone()
	clone.Visible = true
	clone.Parent = self._screenGui
	
	-- Hide the template container so only the dynamic clone is visible
	if self._templateContainer then
		self._templateContainer.Visible = false
	end

	local moduleInstance = moduleDef.new(clone)
	if not moduleInstance then
		clone:Destroy()
		return
	end
	
	if DEBUG_CROSSHAIR then
		print("[Crosshair] Module created successfully")
		print("[Crosshair] Module has _top:", moduleInstance._top ~= nil)
		print("[Crosshair] Module has _bottom:", moduleInstance._bottom ~= nil)
		print("[Crosshair] Module has _left:", moduleInstance._left ~= nil)
		print("[Crosshair] Module has _right:", moduleInstance._right ~= nil)
		print("[Crosshair] Module has _lines:", moduleInstance._lines ~= nil)
		print("[Crosshair] Module has _dot:", moduleInstance._dot ~= nil)
	end

	self._frame = clone
	self._module = moduleInstance
	self._weaponData = weaponData or CrosshairController.Mock.weaponData
	self._customization = self._customization or CrosshairController.Mock.customization
	self:_cacheHitmarker()
	self:_setReticleHidden(false)
	
	if DEBUG_CROSSHAIR then
		print("[Crosshair] WeaponData:", self._weaponData)
	end

	if moduleInstance.ApplyCustomization then
		moduleInstance:ApplyCustomization(self._customization)
	end

	-- Seed spread using current movement so it doesn't start at default size
	local velocity, speed = self:_getVelocity()
	local movementState = self:_getMovementState()
	self._module:Update(1, {
		velocity = velocity,
		speed = speed,
		weaponData = self._weaponData,
		customization = self._customization,
		dt = 1,
		isCrouching = movementState.isCrouching,
		isSliding = movementState.isSliding,
		isSprinting = movementState.isSprinting,
		isGrounded = movementState.isGrounded,
		isADS = movementState.isADS,
	})

	self:_startUpdateLoop()
	
	if DEBUG_CROSSHAIR then
		print("[Crosshair] Update loop started, connection exists:", self._updateConnection ~= nil)
	end
end

function CrosshairController:RemoveCrosshair()
	self:_cancelHitmarkerTweens()
	self._hitmarker = nil
	self._hitmarkerScale = nil
	self._hitmarkerHideSeq = 0
	self._hitmarkerLastHitTime = 0
	self._hitmarkerStack = 0
	self._reticleHidden = false
	self._reticleVisibilitySnapshot = {}

	if self._updateConnection then
		self._updateConnection:Disconnect()
		self._updateConnection = nil
	end

	if self._frame then
		self._frame:Destroy()
		self._frame = nil
	end

	self._module = nil
	self._weaponData = nil
end

function CrosshairController:_getReticleProtectedSet()
	local protected = {}

	if not self._hitmarker or not self._hitmarker.Parent then
		return protected
	end

	protected[self._hitmarker] = true

	for _, descendant in self._hitmarker:GetDescendants() do
		protected[descendant] = true
	end

	local current = self._hitmarker.Parent
	while current and current ~= self._frame do
		protected[current] = true
		current = current.Parent
	end

	return protected
end

function CrosshairController:_setReticleHidden(hidden: boolean)
	hidden = hidden == true

	if not self._frame then
		self._reticleHidden = false
		self._reticleVisibilitySnapshot = {}
		return
	end

	if self._reticleHidden == hidden then
		return
	end

	if hidden then
		self._reticleVisibilitySnapshot = {}
		local protected = self:_getReticleProtectedSet()
		for _, descendant in self._frame:GetDescendants() do
			if descendant:IsA("GuiObject") and not protected[descendant] then
				self._reticleVisibilitySnapshot[descendant] = descendant.Visible
				descendant.Visible = false
			end
		end
		self._reticleHidden = true
		return
	end

	for guiObject, wasVisible in pairs(self._reticleVisibilitySnapshot) do
		if guiObject and guiObject.Parent and guiObject:IsA("GuiObject") then
			guiObject.Visible = wasVisible
		end
	end

	self._reticleVisibilitySnapshot = {}
	self._reticleHidden = false
end

function CrosshairController:_startUpdateLoop()
	if self._updateConnection then
		return
	end

	self._updateConnection = RunService.RenderStepped:Connect(function(dt)
		self:_update(dt)
	end)
end

function CrosshairController:_getVelocity()
	local rootPart = nil
	local characterController = ServiceRegistry:GetController("CharacterController")

	if characterController and characterController.PrimaryPart then
		rootPart = characterController.PrimaryPart
	else
		local character = self._player and self._player.Character
		if character then
			-- Support custom character system (Root) and default (HumanoidRootPart)
			rootPart = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
		end
	end

	if not rootPart then
		return Vector3.zero, 0
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	return velocity, speed
end

function CrosshairController:_getMovementState()
	local msm = getMovementStateManager()
	local characterController = ServiceRegistry:GetController("CharacterController")
	-- WeaponController is registered as "Weapon" not "WeaponController"
	local weaponController = ServiceRegistry:GetController("Weapon")
	
	local isCrouching = false
	local isSliding = false
	local isSprinting = false
	local isGrounded = true
	local isADS = false
	
	-- Get movement states from MovementStateManager (primary source)
	if msm then
		isCrouching = msm:IsCrouching()
		isSliding = msm:IsSliding()
		isSprinting = msm:IsSprinting()
		isGrounded = msm:GetIsGrounded()
	end
	
	-- CharacterController has authoritative grounded state
	if characterController then
		isGrounded = characterController.IsGrounded
		-- Fallback: check IsCrouching/IsSprinting flags if msm failed
		if not msm then
			if characterController.IsCrouching then
				isCrouching = characterController.IsCrouching
			end
			if characterController.IsSprinting then
				isSprinting = characterController.IsSprinting
			end
		end
	end
	
	-- Check ADS state from WeaponController
	if weaponController then
		if type(weaponController.IsADS) == "function" then
			isADS = weaponController:IsADS()
		elseif type(weaponController.GetCurrentActions) == "function" then
			local actions = weaponController:GetCurrentActions()
			local special = actions and actions.Special
			if special and type(special.IsActive) == "function" then
				local ok, active = pcall(function()
					return special.IsActive()
				end)
				if ok then
					isADS = active == true
				end
			end
		elseif weaponController._isADS ~= nil then
			isADS = weaponController._isADS == true
		end
	end
	
	return {
		isCrouching = isCrouching,
		isSliding = isSliding,
		isSprinting = isSprinting,
		isGrounded = isGrounded,
		isADS = isADS,
	}
end

function CrosshairController:_update(dt: number)
	if not self._module then
		if DEBUG_CROSSHAIR then
			local now = tick()
			if now - lastDebugTime > DEBUG_LOG_INTERVAL then
				lastDebugTime = now
				warn("[Crosshair] _update called but self._module is nil!")
			end
		end
		return
	end

	local velocity, speed = self:_getVelocity()
	local movementState = self:_getMovementState()
	
	-- Debug log periodically
	if DEBUG_CROSSHAIR then
		local now = tick()
		if now - lastDebugTime > DEBUG_LOG_INTERVAL then
			lastDebugTime = now
			print("[Crosshair] UPDATE LOOP RUNNING")
			print("[Crosshair]   Speed:", string.format("%.2f", speed))
			print("[Crosshair]   Grounded:", movementState.isGrounded)
			print("[Crosshair]   Sprinting:", movementState.isSprinting)
			print("[Crosshair]   Crouching:", movementState.isCrouching)
			print("[Crosshair]   ADS:", movementState.isADS)
		end
	end
	
	local state = {
		velocity = velocity,
		speed = speed,
		weaponData = self._weaponData,
		customization = self._customization,
		dt = dt,
		-- Movement state for spread modifiers
		isCrouching = movementState.isCrouching,
		isSliding = movementState.isSliding,
		isSprinting = movementState.isSprinting,
		isGrounded = movementState.isGrounded,
		isADS = movementState.isADS,
	}

	local shouldHideReticle = self._hideReticleInADS and movementState.isADS == true
	self:_setReticleHidden(shouldHideReticle)

	self._module:Update(dt, state)
end

function CrosshairController:OnRecoil(recoilData: any)
	if not self._module then
		return
	end

	self._module:OnRecoil(recoilData, self._weaponData)
end

function CrosshairController:SetCustomization(customizationData: any)
	self._customization = customizationData or self._customization
	if self._module and self._module.ApplyCustomization and self._customization then
		self._module:ApplyCustomization(self._customization)
		if self._reticleHidden then
			self:_setReticleHidden(false)
			self:_setReticleHidden(true)
		end
	end
end

function CrosshairController:SetRotation(rotationDeg: number)
	if not self._customization then
		self._customization = table.clone(CrosshairController.Mock.customization)
	end
	self._customization.rotation = rotationDeg or 0
	if self._module and self._module.ApplyCustomization then
		self._module:ApplyCustomization(self._customization)
		if self._reticleHidden then
			self:_setReticleHidden(false)
			self:_setReticleHidden(true)
		end
	end
end

function CrosshairController:SetHideReticleInADS(enabled: boolean?)
	self._hideReticleInADS = enabled ~= false
	if not self._hideReticleInADS then
		self:_setReticleHidden(false)
	end
end

function CrosshairController:GetHideReticleInADS(): boolean
	return self._hideReticleInADS == true
end

function CrosshairController:ShowHitmarker(isHeadshot: boolean?)
	if not self._hitmarker then
		return
	end

	local now = tick()
	if now - self._hitmarkerLastHitTime > 1.35 then
		self._hitmarkerStack = 0
	end
	self._hitmarkerLastHitTime = now
	self._hitmarkerStack = math.clamp(self._hitmarkerStack + 1, 1, 6)

	self._hitmarkerHideSeq += 1
	local hideSeq = self._hitmarkerHideSeq

	local stackBoost = math.min((self._hitmarkerStack - 1) * 0.08, 0.4)
	local startScale = self._hitmarkerBaseScale * (1.45 + stackBoost)
	local endScale = self._hitmarkerBaseScale * 0.6
	local showDuration = 0.185
	local visibleLifetime = .95
	local fadeDuration = 0.65

	self:_cancelHitmarkerTweens()

	self._hitmarker.ImageTransparency = 0
	self._hitmarker.ImageColor3 = isHeadshot and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(255, 255, 255)
	self._hitmarker.Visible = true

	-- Random rotation offset that snaps back to 0 for a punchy feel
	local randomRotation = math.random(-25, 25)
	self._hitmarker.Rotation = randomRotation
	self._hitmarkerRotationTween = TweenService:Create(
		self._hitmarker,
		TweenInfo.new(showDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Rotation = 0 }
	)
	self._hitmarkerRotationTween:Play()

	if self._hitmarkerScale then
		self._hitmarkerScale.Scale = startScale
		self._hitmarkerTween = TweenService:Create(
			self._hitmarkerScale,
			TweenInfo.new(showDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = endScale }
		)
		self._hitmarkerTween:Play()
	end

	task.delay(visibleLifetime, function()
		if self._hitmarkerHideSeq ~= hideSeq then
			return
		end
		if not self._hitmarker then
			return
		end

		self._hitmarkerFadeTween = TweenService:Create(
			self._hitmarker,
			TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ ImageTransparency = 1 }
		)
		self._hitmarkerFadeTween.Completed:Connect(function()
			if self._hitmarkerHideSeq ~= hideSeq then
				return
			end
			if self._hitmarker then
				self._hitmarker.Visible = false
			end
			self._hitmarkerStack = 0
		end)
		self._hitmarkerFadeTween:Play()
	end)
end

function CrosshairController:Destroy()
	self:RemoveCrosshair()
	self._connections:cleanupAll()
	self._connections:destroy()
end

return CrosshairController
