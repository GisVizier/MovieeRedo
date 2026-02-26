local FOVController = {}

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))

-- =============================================================================
-- STATE
-- =============================================================================
FOVController.BaseFOV = 70
FOVController.CurrentFOV = 70
FOVController.TargetFOV = 70
FOVController.SmoothedFOV = 70
FOVController.SettingsEffectsEnabled = true
FOVController.ADSZoomStrength = 1
FOVController.ADSActive = false
FOVController.ADSWeaponFOV = nil

FOVController.ActiveEffects = {}
FOVController.IsInitialized = false
FOVController.UpdateConnection = nil

-- Override state (for SetFOV/TweenFOV)
FOVController.OverrideFOV = nil           -- nil = use effects system, number = override
FOVController.OverrideTweenStart = nil
FOVController.OverrideTweenEnd = nil
FOVController.OverrideTweenDuration = 0
FOVController.OverrideTweenElapsed = 0
FOVController.OverrideTweenEasing = nil
FOVController.OverrideTweenDirection = nil
FOVController.OverrideClearPending = false

-- Effect priorities (higher = takes precedence)
local EFFECT_PRIORITIES = {
	Velocity = 1,
	Sprint = 2,
	Slide = 3,
}

local function clampFOV(value)
	local numeric = tonumber(value)
	if numeric == nil then
		return 70
	end
	return math.clamp(numeric, 30, 120)
end

local function getPlayerConfiguredBaseFOV()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end

	local value = localPlayer:GetAttribute("SettingsBaseFOV")
	if type(value) ~= "number" then
		return nil
	end

	return clampFOV(value)
end

local function getPlayerConfiguredEffectsEnabled()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end

	local value = localPlayer:GetAttribute("SettingsFOVEffectsEnabled")
	if type(value) ~= "boolean" then
		return nil
	end

	return value
end

local function getPlayerConfiguredZoomStrength()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end

	local value = localPlayer:GetAttribute("SettingsFOVZoomStrength")
	if type(value) ~= "number" then
		return nil
	end

	return math.clamp(value, 0, 1)
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================
function FOVController:Init()
	if self.IsInitialized then
		return
	end
	
	local fovConfig = Config.Camera and Config.Camera.FOV
	local effectsConfig = fovConfig and fovConfig.Effects
	if fovConfig then
		self.BaseFOV = fovConfig.Base or 80
	end
	local playerBaseFOV = getPlayerConfiguredBaseFOV()
	if playerBaseFOV then
		self.BaseFOV = playerBaseFOV
	end
	self.SettingsEffectsEnabled = not (effectsConfig and effectsConfig.Enabled == false)
	local playerEffectsEnabled = getPlayerConfiguredEffectsEnabled()
	if playerEffectsEnabled ~= nil then
		self.SettingsEffectsEnabled = playerEffectsEnabled
	end
	self.ADSZoomStrength = 1
	local playerZoomStrength = getPlayerConfiguredZoomStrength()
	if playerZoomStrength ~= nil then
		self.ADSZoomStrength = playerZoomStrength
	end
	self.ADSActive = false
	self.ADSWeaponFOV = nil
	
	self.CurrentFOV = self.BaseFOV
	self.TargetFOV = self.BaseFOV
	self.SmoothedFOV = self.BaseFOV
	self.ActiveEffects = {}
	self.IsInitialized = true
	
	self:StartUpdateLoop()
	
	LogService:Info("FOV", "FOVController initialized", { BaseFOV = self.BaseFOV })
end

function FOVController:_clearOverrideState()
	self.OverrideFOV = nil
	self.OverrideTweenStart = nil
	self.OverrideTweenEnd = nil
	self.OverrideTweenDuration = 0
	self.OverrideTweenElapsed = 0
	self.OverrideTweenEasing = nil
	self.OverrideTweenDirection = nil
	self.OverrideClearPending = false
end

function FOVController:IsEnabled()
	return self.SettingsEffectsEnabled ~= false
end

-- =============================================================================
-- UPDATE LOOP
-- =============================================================================
function FOVController:StartUpdateLoop()
	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
	end
	
	self.UpdateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:UpdateSmoothedFOV(deltaTime)
	end)
end

function FOVController:UpdateSmoothedFOV(deltaTime)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	
	-- Handle override tweening
	if self.OverrideFOV and self.OverrideTweenDuration > 0 then
		self.OverrideTweenElapsed = self.OverrideTweenElapsed + deltaTime
		local alpha = math.clamp(self.OverrideTweenElapsed / self.OverrideTweenDuration, 0, 1)
		
		-- Apply easing
		local easingStyle = self.OverrideTweenEasing or Enum.EasingStyle.Quad
		local easingDir = self.OverrideTweenDirection or Enum.EasingDirection.Out
		local easedAlpha = TweenService:GetValue(alpha, easingStyle, easingDir)
		
		self.SmoothedFOV = self.OverrideTweenStart + (self.OverrideTweenEnd - self.OverrideTweenStart) * easedAlpha
		
		if alpha >= 1 then
			local finalFOV = self.OverrideTweenEnd
			self.OverrideTweenDuration = 0
			self.OverrideTweenElapsed = 0
			self.OverrideTweenStart = nil
			self.OverrideTweenEnd = nil
			self.SmoothedFOV = finalFOV
			if self.OverrideClearPending then
				self.OverrideFOV = nil
				self.OverrideClearPending = false
			else
				self.OverrideFOV = finalFOV
			end
		end
		
		camera.FieldOfView = self.SmoothedFOV
		self.CurrentFOV = self.SmoothedFOV
		return
	end
	
	-- If override is set (no tween), use it directly
	if self.OverrideFOV then
		self.SmoothedFOV = self.OverrideFOV
		camera.FieldOfView = self.SmoothedFOV
		self.CurrentFOV = self.SmoothedFOV
		return
	end
	
	-- Original effects-based logic
	self.TargetFOV = self:CalculateTargetFOV()
	
	local fovConfig = Config.Camera and Config.Camera.FOV
	local lerpAlpha = (fovConfig and fovConfig.LerpAlpha) or 0.06
	
	-- Smooth lerp toward target
	local smoothFactor = lerpAlpha * (deltaTime * 60)
	smoothFactor = math.clamp(smoothFactor, 0, 1)
	
	self.SmoothedFOV = self.SmoothedFOV + (self.TargetFOV - self.SmoothedFOV) * smoothFactor
	
	-- Snap if very close
	if math.abs(self.SmoothedFOV - self.TargetFOV) < 0.01 then
		self.SmoothedFOV = self.TargetFOV
	end
	
	camera.FieldOfView = self.SmoothedFOV
	self.CurrentFOV = self.SmoothedFOV
end

-- =============================================================================
-- EFFECT MANAGEMENT
-- =============================================================================
function FOVController:AddEffect(effectName, customDelta)
	local fovConfig = Config.Camera and Config.Camera.FOV
	local effectsConfig = fovConfig and fovConfig.Effects
	local delta = customDelta
	
	if not delta then
		if effectName == "Slide" then
			delta = effectsConfig and effectsConfig.Slide or 5
		elseif effectName == "Sprint" then
			delta = effectsConfig and effectsConfig.Sprint or 3
		else
			delta = 0
		end
	end
	
	if delta == 0 then
		return
	end
	
	self.ActiveEffects[effectName] = {
		Priority = EFFECT_PRIORITIES[effectName] or 0,
		Delta = delta,
	}
end

function FOVController:RemoveEffect(effectName)
	if not self.ActiveEffects[effectName] then
		return
	end
	
	self.ActiveEffects[effectName] = nil
end

function FOVController:UpdateVelocityFOV(currentSpeed)
	local fovConfig = Config.Camera and Config.Camera.FOV
	local velocityConfig = fovConfig and fovConfig.Velocity
	
	if not velocityConfig or velocityConfig.Enabled == false then
		self:RemoveEffect("Velocity")
		return
	end
	
	local minSpeed = velocityConfig.MinSpeed or 18
	local maxSpeed = velocityConfig.MaxSpeed or 100
	local minBoost = velocityConfig.MinBoost or 0
	local maxBoost = velocityConfig.MaxBoost or 30
	
	if currentSpeed < minSpeed then
		self:RemoveEffect("Velocity")
		return
	end
	
	local speedRange = maxSpeed - minSpeed
	local speedAboveMin = math.min(currentSpeed - minSpeed, speedRange)
	local t = speedAboveMin / speedRange
	local delta = minBoost + (t * (maxBoost - minBoost))
	
	if delta > 0.1 then
		self.ActiveEffects["Velocity"] = {
			Priority = EFFECT_PRIORITIES.Velocity,
			Delta = delta,
		}
	else
		self:RemoveEffect("Velocity")
	end
end

function FOVController:UpdateMomentum(currentSpeed)
	self:UpdateVelocityFOV(currentSpeed)
	self:UpdateSprintFOV(currentSpeed)
end

function FOVController:UpdateSprintFOV(currentSpeed)
	-- Only apply sprint FOV when actually moving while sprinting
	local MovementStateManager = require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("Movement"):WaitForChild("MovementStateManager"))
	local isSprinting = MovementStateManager:IsSprinting()
	
	local fovConfig = Config.Camera and Config.Camera.FOV
	local effectsConfig = fovConfig and fovConfig.Effects
	local sprintDelta = effectsConfig and effectsConfig.Sprint or 3
	
	-- Minimum speed threshold to consider "actually moving"
	local minMoveSpeed = 5
	
	if isSprinting and currentSpeed >= minMoveSpeed then
		self:AddEffect("Sprint", sprintDelta)
	else
		self:RemoveEffect("Sprint")
	end
end

function FOVController:CalculateTargetFOV()
	local baseFOV = self.BaseFOV
	if self.ADSActive then
		local weaponADSFOV = self.ADSWeaponFOV
		if type(weaponADSFOV) ~= "number" then
			return baseFOV
		end

		local zoomStrength = math.clamp(tonumber(self.ADSZoomStrength) or 1, 0, 1)
		return baseFOV + ((weaponADSFOV - baseFOV) * zoomStrength)
	end

	if not self:IsEnabled() then
		return baseFOV
	end

	local totalDelta = 0
	
	for _, effectData in pairs(self.ActiveEffects) do
		totalDelta += effectData.Delta or 0
	end
	
	local fovConfig = Config.Camera and Config.Camera.FOV
	local maxTotalBoost = fovConfig and fovConfig.MaxTotalBoost
	if maxTotalBoost then
		totalDelta = math.min(totalDelta, maxTotalBoost)
	end
	
	return baseFOV + totalDelta
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================
function FOVController:SetBaseFOV(fov)
	if type(fov) ~= "number" then
		return
	end
	self.BaseFOV = clampFOV(fov)
end

function FOVController:SetSettingsBaseFOV(fov)
	self:SetBaseFOV(fov)
end

function FOVController:SetEffectsEnabled(enabled)
	self.SettingsEffectsEnabled = enabled == true
end

function FOVController:SetADSZoomStrength(value)
	local numeric = tonumber(value)
	if numeric == nil then
		return
	end

	if numeric > 1 then
		numeric = numeric / 100
	end

	self.ADSZoomStrength = math.clamp(numeric, 0, 1)
end

function FOVController:SetADSState(isActive, weaponADSFOV)
	self.ADSActive = isActive == true
	if self.ADSActive then
		if type(weaponADSFOV) == "number" then
			self.ADSWeaponFOV = clampFOV(weaponADSFOV)
		elseif type(self.ADSWeaponFOV) ~= "number" then
			self.ADSWeaponFOV = self.BaseFOV
		end
	else
		self.ADSWeaponFOV = nil
	end
end

function FOVController:Reset()
	self.ActiveEffects = {}
	self:_clearOverrideState()
	
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = self.BaseFOV
	end
	self.CurrentFOV = self.BaseFOV
	self.TargetFOV = self.BaseFOV
	self.SmoothedFOV = self.BaseFOV

	if self.IsInitialized and not self.UpdateConnection then
		self:StartUpdateLoop()
	end
end

function FOVController:ResetToConfigBase()
	local fovConfig = Config.Camera and Config.Camera.FOV
	local configuredBase = getPlayerConfiguredBaseFOV() or (fovConfig and fovConfig.Base) or self.BaseFOV or 80
	self:SetBaseFOV(configuredBase)
	self:Reset()
end

function FOVController:GetCurrentFOV()
	local camera = workspace.CurrentCamera
	return camera and camera.FieldOfView or self.BaseFOV
end

function FOVController:GetActiveEffects()
	return self.ActiveEffects
end

-- =============================================================================
-- DIRECT FOV CONTROL (with override and tweening)
-- =============================================================================

--[[
	Set FOV to a specific value (bypasses effects system).
	
	@param fov: number - Target FOV value
	@param tweenDuration: number? - How long to tween (0 or nil = instant)
	@param easingStyle: Enum.EasingStyle? - Easing style (default = Quad)
	@param easingDirection: Enum.EasingDirection? - Easing direction (default = Out)
	@return function - Call to clear the override and return to effects system
]]
function FOVController:SetFOV(fov: number, tweenDuration: number?, easingStyle: Enum.EasingStyle?, easingDirection: Enum.EasingDirection?)
	local duration = tweenDuration or 0
	
	if duration <= 0 then
		-- Instant set
		self.OverrideFOV = fov
		self.OverrideClearPending = false
		self.OverrideTweenStart = nil
		self.OverrideTweenEnd = nil
		self.OverrideTweenDuration = 0
		self.OverrideTweenElapsed = 0
		self.OverrideTweenEasing = nil
		self.OverrideTweenDirection = nil
		self.SmoothedFOV = fov
		
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = fov
		end
	else
		-- Start tween
		self.OverrideTweenStart = self.SmoothedFOV
		self.OverrideTweenEnd = fov
		self.OverrideTweenDuration = duration
		self.OverrideTweenElapsed = 0
		self.OverrideTweenEasing = easingStyle or Enum.EasingStyle.Quad
		self.OverrideTweenDirection = easingDirection or Enum.EasingDirection.Out
		self.OverrideClearPending = false
		self.OverrideFOV = fov
	end
	
	-- Return cleanup function
	return function(returnDuration: number?)
		self:ClearFOVOverride(returnDuration)
	end
end

--[[
	Tween FOV to a specific value (override).
	
	@param targetFov: number - Target FOV
	@param duration: number - Tween duration in seconds
	@param easingStyle: Enum.EasingStyle? - Easing style (default = Quad)
	@param easingDirection: Enum.EasingDirection? - Easing direction (default = Out)
]]
function FOVController:TweenFOV(targetFov: number, duration: number, easingStyle: Enum.EasingStyle?, easingDirection: Enum.EasingDirection?)
	self.OverrideTweenStart = self.SmoothedFOV
	self.OverrideTweenEnd = targetFov
	self.OverrideTweenDuration = duration
	self.OverrideTweenElapsed = 0
	self.OverrideTweenEasing = easingStyle or Enum.EasingStyle.Quad
	self.OverrideTweenDirection = easingDirection or Enum.EasingDirection.Out
	self.OverrideClearPending = false
	self.OverrideFOV = targetFov
end

--[[
	Clear FOV override and return to effects-based system.
	
	@param tweenDuration: number? - How long to tween back (0 or nil = instant)
]]
function FOVController:ClearFOVOverride(tweenDuration: number?)
	local duration = tweenDuration or 0
	
	if duration <= 0 then
		-- Instant clear
		self:_clearOverrideState()
		self.TargetFOV = self:CalculateTargetFOV()
		self.SmoothedFOV = self.TargetFOV
		self.CurrentFOV = self.TargetFOV
		local camera = workspace.CurrentCamera
		if camera then
			camera.FieldOfView = self.TargetFOV
		end
	else
		-- Tween back to effects-based FOV
		local targetFOV = self:CalculateTargetFOV()
		self.OverrideTweenStart = self.SmoothedFOV
		self.OverrideTweenEnd = targetFOV
		self.OverrideTweenDuration = duration
		self.OverrideTweenElapsed = 0
		self.OverrideTweenEasing = Enum.EasingStyle.Quad
		self.OverrideTweenDirection = Enum.EasingDirection.Out
		self.OverrideClearPending = true
		if self.OverrideFOV == nil then
			self.OverrideFOV = self.SmoothedFOV
		end
	end
end

--[[
	Check if FOV is currently overridden.
	
	@return boolean
]]
function FOVController:IsOverridden()
	return self.OverrideFOV ~= nil
end

return FOVController
