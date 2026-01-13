local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))

local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local ViewmodelEffects = {}
ViewmodelEffects.__index = ViewmodelEffects

local LocalPlayer = Players.LocalPlayer

local function expAlpha(dt: number, k: number): number
	-- Framerate-independent smoothing: alpha = 1 - exp(-k*dt)
	if dt <= 0 then
		return 0
	end
	return 1 - math.exp(-k * dt)
end

local function clampDt(dt: number): number
	-- Prevent hitch spikes from causing visible snaps.
	return math.clamp(dt, 0, 1 / 20)
end

local function getRootPart(): BasePart?
	local character = LocalPlayer and LocalPlayer.Character
	if not character then
		return nil
	end
	return character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
end

function ViewmodelEffects.new()
	local self = setmetatable({}, ViewmodelEffects)
	self._sway = Vector2.zero
	self._swayCF = CFrame.new()
	self._bobT = 0
	self._bobCF = CFrame.new()
	self._slideCF = CFrame.new()
	return self
end

function ViewmodelEffects:Reset()
	self._sway = Vector2.zero
	self._swayCF = CFrame.new()
	self._bobT = 0
	self._bobCF = CFrame.new()
	self._slideCF = CFrame.new()
end

function ViewmodelEffects:Update(dt: number, cameraCFrame: CFrame, weaponId: string?): CFrame
	dt = clampDt(dt)
	local cfg = ViewmodelConfig
	local effects = cfg.Effects

	-- Mouse sway (simple, snappy).
	if effects.MouseSway and effects.MouseSway.Enabled then
		local delta = UserInputService:GetMouseDelta()
		local sens = effects.MouseSway.MouseSensitivity or 0.15
		local maxAngle = effects.MouseSway.MaxAngleDeg or 12
		local returnSpeed = effects.MouseSway.ReturnSpeed or 14

		local target = Vector2.new(
			math.clamp(-delta.X * sens, -maxAngle, maxAngle),
			math.clamp(-delta.Y * sens, -maxAngle, maxAngle)
		)

		-- Framerate-independent smoothing (reduces snap on dt variance).
		local alpha = math.clamp(expAlpha(dt, returnSpeed), 0, 1)
		self._sway = self._sway:Lerp(target, alpha)
		-- Return-to-center so you don't "stick" if input stops.
		self._sway = self._sway:Lerp(Vector2.zero, math.clamp(expAlpha(dt, returnSpeed * 0.6), 0, 1))
		self._swayCF = CFrame.Angles(math.rad(self._sway.Y), math.rad(self._sway.X), 0)
	else
		self._swayCF = CFrame.new()
	end

	-- Movement bob (based on speed + state).
	do
		local root = getRootPart()
		local vel = root and root.AssemblyLinearVelocity or Vector3.zero
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local grounded = MovementStateManager:GetIsGrounded()

		if not grounded or speed < 0.5 then
			self._bobT = 0
			self._bobCF = self._bobCF:Lerp(CFrame.new(), math.clamp(dt * 10, 0, 1))
		else
			local state = MovementStateManager:GetCurrentState()
			local bobCfg = (state == MovementStateManager.States.Sprinting) and effects.RunBob or effects.WalkBob
			if bobCfg and bobCfg.Enabled then
				local freq = bobCfg.Frequency or 6
				local amp = bobCfg.Amplitude or Vector3.new(0.03, 0.04, 0)

				local speedFactor = math.clamp(speed / 15, 0.6, 1.6)
				self._bobT += dt * freq * speedFactor

				local s = math.sin(self._bobT)
				local c = math.cos(self._bobT * 2)
				local pos = Vector3.new(s * amp.X, math.abs(c) * amp.Y, 0)
				local target = CFrame.new(pos)
				self._bobCF = self._bobCF:Lerp(target, math.clamp(dt * 8, 0, 1))
			else
				self._bobCF = self._bobCF:Lerp(CFrame.new(), math.clamp(dt * 10, 0, 1))
			end
		end
	end

	-- Slide tilt (camera-relative, as requested).
	do
		local slideCfg = effects.SlideTilt
		local isSliding = MovementStateManager:IsSliding()

		if slideCfg and slideCfg.Enabled and isSliding then
			local root = getRootPart()
			local vel = root and root.AssemblyLinearVelocity or Vector3.zero
			local d = Vector3.new(vel.X, 0, vel.Z)
			if d.Magnitude > 0.05 then
				d = d.Unit
			else
				d = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z)
				d = (d.Magnitude > 0.05) and d.Unit or Vector3.new(0, 0, -1)
			end

			local right = cameraCFrame.RightVector
			local side = right:Dot(d) >= 0 and 1 or -1

			local offset = slideCfg.Offset or Vector3.new(0.14, -0.12, 0.06)
			local rot = slideCfg.RotationDeg or Vector3.new(8, 10, 0)
			local roll = (slideCfg.AngleDeg or 18) * side

			local target = CFrame.new(offset.X * side, offset.Y, offset.Z)
				* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y * side), math.rad(roll))

			local speed = slideCfg.TransitionSpeed or 10
			self._slideCF = self._slideCF:Lerp(target, math.clamp(dt * speed, 0, 1))
		else
			self._slideCF = self._slideCF:Lerp(CFrame.new(), math.clamp(dt * 12, 0, 1))
		end
	end

	return self._swayCF * self._bobCF * self._slideCF
end

return ViewmodelEffects
