local FOVController = {}

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))

-- =============================================================================
-- STATE
-- =============================================================================
FOVController.BaseFOV = 80
FOVController.CurrentFOV = 80
FOVController.TargetFOV = 80
FOVController.SmoothedFOV = 80

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

-- Effect priorities (higher = takes precedence)
local EFFECT_PRIORITIES = {
	Velocity = 1,
	Sprint = 2,
	Slide = 3,
}

-- =============================================================================
-- INITIALIZATION
-- =============================================================================
function FOVController:Init()
	if self.IsInitialized then
		return
	end
	
	local fovConfig = Config.Camera and Config.Camera.FOV
	if fovConfig then
		self.BaseFOV = fovConfig.Base or 80
	end
	
	self.CurrentFOV = self.BaseFOV
	self.TargetFOV = self.BaseFOV
	self.SmoothedFOV = self.BaseFOV
	self.ActiveEffects = {}
	self.IsInitialized = true
	
	self:StartUpdateLoop()
	
	LogService:Info("FOV", "FOVController initialized", { BaseFOV = self.BaseFOV })
end

function FOVController:IsEnabled()
	local fovConfig = Config.Camera and Config.Camera.FOV
	local effectsConfig = fovConfig and fovConfig.Effects
	return effectsConfig and effectsConfig.Enabled ~= false
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
			self.OverrideTweenDuration = 0
			self.SmoothedFOV = self.OverrideTweenEnd
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
	if not self:IsEnabled() then
		return
	end
	
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
	if not self:IsEnabled() then
		return
	end
	
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
	if not self:IsEnabled() then
		return
	end
	
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
	local highestPriority = -1
	local highestDelta = 0
	
	for _, effectData in pairs(self.ActiveEffects) do
		if effectData.Priority > highestPriority then
			highestPriority = effectData.Priority
			highestDelta = effectData.Delta
		elseif effectData.Priority == highestPriority then
			highestDelta = math.max(highestDelta, effectData.Delta)
		end
	end
	
	return self.BaseFOV + highestDelta
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================
function FOVController:SetBaseFOV(fov)
	self.BaseFOV = fov
end

function FOVController:Reset()
	self.ActiveEffects = {}
	
	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
		self.UpdateConnection = nil
	end
	
	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = self.BaseFOV
	end
	self.CurrentFOV = self.BaseFOV
	self.TargetFOV = self.BaseFOV
	self.SmoothedFOV = self.BaseFOV
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
		self.OverrideTweenDuration = 0
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
		self.OverrideFOV = nil
		self.OverrideTweenDuration = 0
	else
		-- Tween back to effects-based FOV
		local targetFOV = self:CalculateTargetFOV()
		self.OverrideTweenStart = self.SmoothedFOV
		self.OverrideTweenEnd = targetFOV
		self.OverrideTweenDuration = duration
		self.OverrideTweenElapsed = 0
		self.OverrideTweenEasing = Enum.EasingStyle.Quad
		self.OverrideTweenDirection = Enum.EasingDirection.Out
		
		-- Clear override after tween completes
		task.delay(duration + 0.01, function()
			if self.OverrideFOV == targetFOV or self.OverrideTweenDuration == 0 then
				self.OverrideFOV = nil
			end
		end)
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
