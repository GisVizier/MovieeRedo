local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local SlidingSystem = require(Locations.Game:WaitForChild("Movement"):WaitForChild("SlidingSystem"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

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

local function springStep(position: Vector3, velocity: Vector3, target: Vector3, stiffness: number, damping: number, dt: number)
	local displacement = target - position
	local accel = displacement * stiffness - velocity * damping
	velocity = velocity + accel * dt
	position = position + velocity * dt
	return position, velocity
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
	self._impulseCF = CFrame.new()
	self._impulseOffset = Vector3.zero
	self._impulseVelocity = Vector3.zero
	self._smoothedVel = Vector3.zero
	self._smoothedSpeed = 0
	self._bobWeight = 0
	self._lastSlideDir = Vector3.new(0, 0, -1)
	self._wasSliding = false
	self._wasVaulting = false
	self._lastJumpCancelTime = 0
	self._movementController = nil
	return self
end

function ViewmodelEffects:Reset()
	self._sway = Vector2.zero
	self._swayCF = CFrame.new()
	self._bobT = 0
	self._bobCF = CFrame.new()
	self._slideCF = CFrame.new()
	self._impulseCF = CFrame.new()
	self._impulseOffset = Vector3.zero
	self._impulseVelocity = Vector3.zero
	self._smoothedVel = Vector3.zero
	self._smoothedSpeed = 0
	self._bobWeight = 0
	self._lastSlideDir = Vector3.new(0, 0, -1)
	self._wasSliding = false
	self._wasVaulting = false
	self._lastJumpCancelTime = 0
end

function ViewmodelEffects:Update(dt: number, cameraCFrame: CFrame, weaponId: string?): CFrame
	dt = clampDt(dt)
	local cfg = ViewmodelConfig
	local effects = cfg.Effects
	local smoothing = effects.MovementSmoothing or {}

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

	-- Smoothed horizontal velocity (stability on accel/decel).
	local root = getRootPart()
	local vel = root and root.AssemblyLinearVelocity or Vector3.zero
	local horizontalVel = Vector3.new(vel.X, 0, vel.Z)
	do
		local speedAlpha = math.clamp(expAlpha(dt, smoothing.SpeedSmoothness or 12), 0, 1)
		local dirAlpha = math.clamp(expAlpha(dt, smoothing.DirectionSmoothness or 14), 0, 1)
		self._smoothedVel = self._smoothedVel:Lerp(horizontalVel, dirAlpha)
		local targetSpeed = self._smoothedVel.Magnitude
		self._smoothedSpeed = self._smoothedSpeed + (targetSpeed - self._smoothedSpeed) * speedAlpha
	end

	-- Movement bob (based on speed + state).
	do
		local speed = self._smoothedSpeed
		local grounded = MovementStateManager:GetIsGrounded()
		local moveStart = smoothing.MoveStartSpeed or 1.25
		local moveStop = smoothing.MoveStopSpeed or 0.75
		local isMoving = (self._bobWeight > 0.05 and speed > moveStop) or speed > moveStart
		local bobBlend = math.clamp(expAlpha(dt, smoothing.BobBlendSpeed or 10), 0, 1)
		local targetWeight = (grounded and isMoving) and 1 or 0
		self._bobWeight = self._bobWeight + (targetWeight - self._bobWeight) * bobBlend

		if not grounded or self._bobWeight < 0.01 then
			self._bobT = 0
		end

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
			local weightedTarget = CFrame.new():Lerp(target, self._bobWeight)
			self._bobCF = self._bobCF:Lerp(weightedTarget, math.clamp(dt * 8, 0, 1))
		else
			self._bobCF = self._bobCF:Lerp(CFrame.new(), math.clamp(dt * 10, 0, 1))
		end
	end

	-- Slide tilt (camera-relative, as requested).
	do
		local slideCfg = effects.SlideTilt
		local isSliding = MovementStateManager:IsSliding()

		if slideCfg and slideCfg.Enabled and isSliding then
			local d = self._smoothedVel
			if d.Magnitude > 0.1 then
				self._lastSlideDir = d.Unit
			else
				local fallback = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z)
				if fallback.Magnitude > 0.05 then
					self._lastSlideDir = fallback.Unit
				end
			end
			d = self._lastSlideDir

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

	-- Impulse response (vault, slide start, jump cancel).
	do
		local impulseCfg = effects.Impulse
		if impulseCfg and impulseCfg.Enabled then
			if not self._movementController then
				self._movementController = ServiceRegistry:GetController("MovementController")
					or ServiceRegistry:GetController("CharacterController")
			end

			local isSliding = MovementStateManager:IsSliding()
			if isSliding and not self._wasSliding and impulseCfg.SlideKick then
				self._impulseVelocity += impulseCfg.SlideKick
			end
			self._wasSliding = isSliding

			local isVaulting = self._movementController and self._movementController.IsVaulting or false
			if isVaulting and not self._wasVaulting and impulseCfg.VaultKick then
				self._impulseVelocity += impulseCfg.VaultKick
			end
			self._wasVaulting = isVaulting

			local jumpCancelTime = SlidingSystem.LastJumpCancelTime or 0
			if jumpCancelTime > (self._lastJumpCancelTime or 0) and impulseCfg.JumpCancelKick then
				self._lastJumpCancelTime = jumpCancelTime
				self._impulseVelocity += impulseCfg.JumpCancelKick
			end

			self._impulseOffset, self._impulseVelocity =
				springStep(self._impulseOffset, self._impulseVelocity, Vector3.zero, impulseCfg.Stiffness or 80, impulseCfg.Damping or 18, dt)

			local maxOffset = impulseCfg.MaxOffset or 0.22
			if self._impulseOffset.Magnitude > maxOffset then
				self._impulseOffset = self._impulseOffset.Unit * maxOffset
			end
			self._impulseCF = CFrame.new(self._impulseOffset)
		else
			self._impulseCF = CFrame.new()
		end
	end

	return self._swayCF * self._bobCF * self._slideCF * self._impulseCF
end

return ViewmodelEffects
