local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))

local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local ViewmodelAnimator = {}
ViewmodelAnimator.__index = ViewmodelAnimator

local AIRBORNE_SPRINT_SPEED = 0.2

local LocalPlayer = Players.LocalPlayer

local function expAlpha(dt: number, k: number): number
	if dt <= 0 then
		return 0
	end
	return 1 - math.exp(-k * dt)
end

local function getRootPart(): BasePart?
	local character = LocalPlayer and LocalPlayer.Character
	if not character then
		return nil
	end
	return character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
end

local function isValidAnimId(animId: any): boolean
	return type(animId) == "string" and animId ~= "" and animId ~= "rbxassetid://0"
end

function ViewmodelAnimator.new()
	local self = setmetatable({}, ViewmodelAnimator)
	self._rig = nil
	self._tracks = {}
	self._currentMove = nil
	self._conn = nil
	self._initialized = false
	self._smoothedSpeed = 0
	return self
end

function ViewmodelAnimator:BindRig(rig, weaponId: string?)
	self:Unbind()

	self._rig = rig
	self._tracks = {}
	self._currentMove = nil
	self._initialized = false
	self._smoothedSpeed = 0

	if not rig or not rig.Animator then
		return
	end

	local cfg = ViewmodelConfig.Weapons[weaponId or ""] or ViewmodelConfig.Weapons.Fists
	local anims = cfg and cfg.Animations or {}

	for name, animId in pairs(anims) do
		if isValidAnimId(animId) then
			local anim = Instance.new("Animation")
			anim.AnimationId = animId
			local track = rig.Animator:LoadAnimation(anim)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = (name == "Idle" or name == "Walk" or name == "Run" or name == "ADS")
			self._tracks[name] = track
		end
	end

	-- Pre-load all movement animations by playing and immediately stopping them
	-- This "primes" the animation system so they're ready when needed
	for name, track in pairs(self._tracks) do
		if name == "Walk" or name == "Run" then
			track:Play(0)
			track:Stop(0)
		end
	end

	-- Start with idle
	self:Play("Idle", 0.15, true)
	self._currentMove = "Idle"

	-- Start the movement update loop immediately
	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_updateMovement(dt)
	end)

	-- Mark as initialized after a short delay to ensure animation system is ready
	task.delay(0.1, function()
		self._initialized = true
	end)
end

function ViewmodelAnimator:Unbind()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end

	for _, track in pairs(self._tracks) do
		pcall(function()
			if track.IsPlaying then
				track:Stop(0)
			end
		end)
	end

	self._rig = nil
	self._tracks = {}
	self._currentMove = nil
	self._initialized = false
end

function ViewmodelAnimator:Play(name: string, fadeTime: number?, restart: boolean?)
	local track = self._tracks[name]
	if not track then
		return
	end

	if restart and track.IsPlaying then
		track:Stop(0)
	end

	if not track.IsPlaying then
		track:Play(fadeTime or 0.1)
	end
end

function ViewmodelAnimator:Stop(name: string, fadeTime: number?)
	local track = self._tracks[name]
	if track and track.IsPlaying then
		track:Stop(fadeTime or 0.1)
	end
end

function ViewmodelAnimator:GetTrack(name: string)
	return self._tracks[name]
end

function ViewmodelAnimator:_updateMovement(dt: number)
	if not self._rig or not self._initialized then
		return
	end

	local root = getRootPart()
	local vel = root and root.AssemblyLinearVelocity or Vector3.zero
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	dt = dt or (1 / 60)
	local smoothCfg = ViewmodelConfig.Effects and ViewmodelConfig.Effects.MovementSmoothing or {}
	local speedAlpha = math.clamp(expAlpha(dt, smoothCfg.SpeedSmoothness or 12), 0, 1)
	self._smoothedSpeed = self._smoothedSpeed + (speed - self._smoothedSpeed) * speedAlpha

	local grounded = MovementStateManager:GetIsGrounded()
	local state = MovementStateManager:GetCurrentState()

	local target = "Idle"
	local moveStart = smoothCfg.MoveStartSpeed or 1.25
	local moveStop = smoothCfg.MoveStopSpeed or 0.75
	local isMoving = self._smoothedSpeed > moveStart or (self._currentMove ~= "Idle" and self._smoothedSpeed > moveStop)

	if isMoving then
		if state == MovementStateManager.States.Sprinting and self._tracks.Run then
			-- Keep sprint animation even while airborne.
			target = "Run"
		elseif grounded then
			target = "Walk"
		end
	end
	if not self._tracks[target] then
		target = "Idle"
	end

	-- Smooth crossfade between idle/walk/run.
	local fade = 0.18
	for _, name in ipairs({ "Idle", "Walk", "Run" }) do
		local track = self._tracks[name]
		if track then
			if not track.IsPlaying then
				track:Play(0)
			end
			local weight = (name == target) and 1 or 0
			track:AdjustWeight(weight, fade)
		end
	end
	do
		local runTrack = self._tracks.Run
		if runTrack then
			local speed = (target == "Run" and not grounded) and AIRBORNE_SPRINT_SPEED or 1
			runTrack:AdjustSpeed(speed)
		end
	end
	self._currentMove = target
end

return ViewmodelAnimator
