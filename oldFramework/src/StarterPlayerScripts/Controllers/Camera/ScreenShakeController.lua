local ScreenShakeController = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local LogService = require(Locations.Modules.Systems.Core.LogService)

ScreenShakeController.IsInitialized = false
ScreenShakeController.ActiveShakes = {}
ScreenShakeController.CurrentOffset = Vector3.zero
ScreenShakeController.CurrentRotation = Vector3.zero
ScreenShakeController.Connection = nil

function ScreenShakeController:Init()
	if self.IsInitialized then
		return
	end

	self.ActiveShakes = {}
	self.CurrentOffset = Vector3.zero
	self.CurrentRotation = Vector3.zero
	self.IsInitialized = true

	self:StartUpdateLoop()

	LogService:Info("SCREEN_SHAKE", "ScreenShakeController initialized")
end

function ScreenShakeController:IsEnabled()
	local shakeConfig = Config.Controls.Camera.ScreenShake
	return shakeConfig and shakeConfig.Enabled ~= false
end

function ScreenShakeController:Shake(intensity, duration, frequency)
	if not self:IsEnabled() then
		return
	end

	local shakeId = tostring(tick()) .. "_" .. math.random(1000, 9999)

	self.ActiveShakes[shakeId] = {
		Intensity = intensity or 0.3,
		Duration = duration or 0.2,
		Frequency = frequency or 15,
		StartTime = tick(),
		Elapsed = 0,
	}

	LogService:Debug("SCREEN_SHAKE", "Shake started", {
		Id = shakeId,
		Intensity = intensity,
		Duration = duration,
	})

	return shakeId
end

function ScreenShakeController:ShakeWallJump()
	local shakeConfig = Config.Controls.Camera.ScreenShake
	if not shakeConfig or not shakeConfig.WallJump then
		return
	end

	local wallJumpConfig = shakeConfig.WallJump
	self:Shake(
		wallJumpConfig.Intensity or 0.3,
		wallJumpConfig.Duration or 0.2,
		wallJumpConfig.Frequency or 15
	)
end

function ScreenShakeController:StopShake(shakeId)
	if shakeId and self.ActiveShakes[shakeId] then
		self.ActiveShakes[shakeId] = nil
	end
end

function ScreenShakeController:StopAllShakes()
	self.ActiveShakes = {}
	self.CurrentOffset = Vector3.zero
	self.CurrentRotation = Vector3.zero
end

function ScreenShakeController:StartUpdateLoop()
	if self.Connection then
		self.Connection:Disconnect()
	end

	self.Connection = RunService.RenderStepped:Connect(function(deltaTime)
		self:Update(deltaTime)
	end)
end

function ScreenShakeController:Update(deltaTime)
	local totalOffset = Vector3.zero
	local totalRotation = Vector3.zero
	local shakesToRemove = {}

	for shakeId, shakeData in pairs(self.ActiveShakes) do
		shakeData.Elapsed = shakeData.Elapsed + deltaTime

		if shakeData.Elapsed >= shakeData.Duration then
			table.insert(shakesToRemove, shakeId)
		else
			local progress = shakeData.Elapsed / shakeData.Duration
			local decay = 1 - progress
			local intensity = shakeData.Intensity * decay

			local time = tick() * shakeData.Frequency

			local offsetX = math.sin(time * 2.3) * intensity
			local offsetY = math.cos(time * 1.7) * intensity
			local offsetZ = math.sin(time * 3.1) * intensity * 0.5

			local rotX = math.cos(time * 2.1) * intensity * 0.5
			local rotY = math.sin(time * 1.9) * intensity * 0.3
			local rotZ = math.cos(time * 2.7) * intensity * 0.2

			totalOffset = totalOffset + Vector3.new(offsetX, offsetY, offsetZ)
			totalRotation = totalRotation + Vector3.new(rotX, rotY, rotZ)
		end
	end

	for _, shakeId in ipairs(shakesToRemove) do
		self.ActiveShakes[shakeId] = nil
	end

	self.CurrentOffset = totalOffset
	self.CurrentRotation = totalRotation
end

function ScreenShakeController:GetOffset()
	return self.CurrentOffset
end

function ScreenShakeController:GetRotation()
	return self.CurrentRotation
end

function ScreenShakeController:Cleanup()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end

	self.ActiveShakes = {}
	self.CurrentOffset = Vector3.zero
	self.CurrentRotation = Vector3.zero
	self.IsInitialized = false
end

return ScreenShakeController
