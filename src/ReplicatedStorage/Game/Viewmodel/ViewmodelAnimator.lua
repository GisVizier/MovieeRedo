local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))

local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local ViewmodelAnimator = {}
ViewmodelAnimator.__index = ViewmodelAnimator

local LocalPlayer = Players.LocalPlayer

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
	return self
end

function ViewmodelAnimator:BindRig(rig, weaponId: string?)
	self:Unbind()

	self._rig = rig
	self._tracks = {}
	self._currentMove = nil
	self._initialized = false

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
	self._conn = RunService.Heartbeat:Connect(function()
		self:_updateMovement()
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

function ViewmodelAnimator:_updateMovement()
	if not self._rig or not self._initialized then
		return
	end

	local root = getRootPart()
	local vel = root and root.AssemblyLinearVelocity or Vector3.zero
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	local grounded = MovementStateManager:GetIsGrounded()
	local state = MovementStateManager:GetCurrentState()

	local target = "Idle"
	if grounded and speed > 1 then
		if state == MovementStateManager.States.Sprinting then
			target = self._tracks.Run and "Run" or "Walk"
		else
			target = "Walk"
		end
	end

	-- Always ensure the correct animation is playing
	local targetTrack = self._tracks[target]
	if not targetTrack then
		return
	end

	-- If we need to change animations OR the target isn't playing, switch to it
	if self._currentMove ~= target or not targetTrack.IsPlaying then
		if self._currentMove and self._currentMove ~= target then
			self:Stop(self._currentMove, 0.15)
		end
		self:Play(target, 0.15, false)
		self._currentMove = target
	end
end

return ViewmodelAnimator
