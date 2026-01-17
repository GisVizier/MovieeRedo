local FOVController = {}

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local LogService = require(Locations.Modules.Systems.Core.LogService)

local Camera = workspace.CurrentCamera

FOVController.BaseFOV = Config.Controls.Camera.FieldOfView
FOVController.CurrentFOV = FOVController.BaseFOV
FOVController.TargetFOV = FOVController.BaseFOV
FOVController.SmoothedFOV = FOVController.BaseFOV

FOVController.ActiveEffects = {}
FOVController.IsInitialized = false
FOVController.UpdateConnection = nil

local EFFECT_PRIORITIES = {
	Velocity = 1,
	Sprint = 2,
	Slide = 3,
}

function FOVController:Init()
	if self.IsInitialized then
		return
	end

	self.BaseFOV = Config.Controls.Camera.FieldOfView
	self.CurrentFOV = self.BaseFOV
	self.TargetFOV = self.BaseFOV
	self.SmoothedFOV = self.BaseFOV
	self.ActiveEffects = {}
	self.IsInitialized = true

	self:StartUpdateLoop()

	LogService:Info("FOV", "FOVController initialized with velocity-based FOV", { BaseFOV = self.BaseFOV })
end

function FOVController:IsEnabled()
	local fovConfig = Config.Controls.Camera.FOVEffects
	return fovConfig and fovConfig.Enabled ~= false
end

function FOVController:StartUpdateLoop()
	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
	end

	self.UpdateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:UpdateSmoothedFOV(deltaTime)
	end)
end

function FOVController:AddEffect(effectName, customDelta)
	if not self:IsEnabled() then
		return
	end

	local fovConfig = Config.Controls.Camera.FOVEffects
	local delta = customDelta

	if not delta then
		if effectName == "Slide" then
			delta = fovConfig.SlideFOV or 5
		elseif effectName == "Sprint" then
			delta = fovConfig.SprintFOV or 3
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

	local fovConfig = Config.Controls.Camera.FOVEffects
	local velocityConfig = fovConfig and fovConfig.VelocityFOV

	if not velocityConfig or velocityConfig.Enabled == false then
		self:RemoveEffect("Velocity")
		return
	end

	local minSpeed = velocityConfig.MinSpeed or 10
	local maxSpeed = velocityConfig.MaxSpeed or 80
	local minFOVBoost = velocityConfig.MinFOVBoost or 0
	local maxFOVBoost = velocityConfig.MaxFOVBoost or 12

	if currentSpeed < minSpeed then
		self:RemoveEffect("Velocity")
		return
	end

	local speedRange = maxSpeed - minSpeed
	local speedAboveMin = math.min(currentSpeed - minSpeed, speedRange)
	local t = speedAboveMin / speedRange
	local delta = minFOVBoost + (t * (maxFOVBoost - minFOVBoost))

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
end

function FOVController:CalculateTargetFOV()
	local highestPriority = -1
	local highestDelta = 0

	for effectName, effectData in pairs(self.ActiveEffects) do
		if effectData.Priority > highestPriority then
			highestPriority = effectData.Priority
			highestDelta = effectData.Delta
		elseif effectData.Priority == highestPriority then
			highestDelta = math.max(highestDelta, effectData.Delta)
		end
	end

	return self.BaseFOV + highestDelta
end

function FOVController:UpdateSmoothedFOV(deltaTime)
	if not Camera then
		Camera = workspace.CurrentCamera
		if not Camera then return end
	end

	self.TargetFOV = self:CalculateTargetFOV()

	local fovConfig = Config.Controls.Camera.FOVEffects
	local lerpAlpha = (fovConfig and fovConfig.LerpAlpha) or 0.08

	-- Simple lerp toward target (faster = higher FOV)
	local smoothFactor = lerpAlpha * (deltaTime * 60)
	smoothFactor = math.clamp(smoothFactor, 0, 1)

	self.SmoothedFOV = self.SmoothedFOV + (self.TargetFOV - self.SmoothedFOV) * smoothFactor

	if math.abs(self.SmoothedFOV - self.TargetFOV) < 0.01 then
		self.SmoothedFOV = self.TargetFOV
	end

	Camera.FieldOfView = self.SmoothedFOV
	self.CurrentFOV = self.SmoothedFOV
	
	-- Debug: Print to see what's happening
	-- print("[FOV] Target:", math.floor(self.TargetFOV * 10) / 10, "Current:", math.floor(self.SmoothedFOV * 10) / 10)
end

function FOVController:RecalculateFOV()
end

function FOVController:TweenToTarget()
end

function FOVController:SetBaseFOV(fov)
	self.BaseFOV = fov
end

function FOVController:Reset()
	self.ActiveEffects = {}

	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
		self.UpdateConnection = nil
	end

	if Camera then
		Camera.FieldOfView = self.BaseFOV
	end
	self.CurrentFOV = self.BaseFOV
	self.TargetFOV = self.BaseFOV
	self.SmoothedFOV = self.BaseFOV
end

function FOVController:GetCurrentFOV()
	return Camera and Camera.FieldOfView or self.BaseFOV
end

function FOVController:GetActiveEffects()
	return self.ActiveEffects
end

return FOVController
