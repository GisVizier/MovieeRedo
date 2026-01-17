--[[
	ArmReplicator.lua

	Handles arm/head look direction replication to other players.
	- Sends local player's look direction to server at 20Hz
	- Receives other players' look directions and applies to their rigs
	- Uses configurable rotation offsets to fix backwards orientation

	Configuration in ViewmodelConfig.ArmReplication:
	- Neck: Head rotation settings and offset
	- RightShoulder: Right arm rotation settings and offset
	- LeftShoulder: Left arm rotation settings and offset
]]

local ArmReplicator = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Update rate (20 Hz = 50ms between updates)
ArmReplicator.UpdateRate = 1 / 20
ArmReplicator.LastUpdateTime = 0

-- Connections
ArmReplicator.HeartbeatConnection = nil
ArmReplicator.ReplicationConnection = nil
ArmReplicator.LerpConnection = nil

-- Store look directions from other players
ArmReplicator.RemoteLookDirections = {}

-- Store original C0 values for Motor6Ds (to preserve position)
ArmReplicator.OriginalC0Values = {}

-- Store current lerped C0 values for smooth transitions
ArmReplicator.CurrentC0Values = {}

-- Store target C0 values for lerping
ArmReplicator.TargetC0Values = {}

-- Lerp smoothness (higher = faster response, lower = smoother)
ArmReplicator.LerpSpeed = 12

--============================================================================
-- INITIALIZATION
--============================================================================

function ArmReplicator:Init()
	Log:RegisterCategory("ARM_REPLICATION", "Arm/head look direction replication")

	self:StartSending()
	self:StartReceiving()
	self:StartLerpLoop()

	Log:Info("ARM_REPLICATION", "ArmReplicator initialized")
end

--============================================================================
-- LERP UPDATE LOOP
--============================================================================

function ArmReplicator:StartLerpLoop()
	if self.LerpConnection then
		self.LerpConnection:Disconnect()
	end

	self.LerpConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:UpdateLerp(deltaTime)
	end)
end

function ArmReplicator:UpdateLerp(deltaTime)
	local alpha = math.clamp(self.LerpSpeed * deltaTime, 0, 1)

	for motorKey, targetC0 in pairs(self.TargetC0Values) do
		local currentC0 = self.CurrentC0Values[motorKey]
		if currentC0 then
			-- Lerp the CFrame
			local lerpedC0 = currentC0:Lerp(targetC0, alpha)
			self.CurrentC0Values[motorKey] = lerpedC0

			-- Apply to the actual Motor6D
			-- Find the motor by its key (stored reference)
			local motor = self:FindMotorByKey(motorKey)
			if motor then
				motor.C0 = lerpedC0
			end
		else
			-- First frame - initialize current to target
			self.CurrentC0Values[motorKey] = targetC0
		end
	end
end

-- Cache motor references for lookup
ArmReplicator.MotorCache = {}

function ArmReplicator:CacheMotor(motor)
	local key = motor:GetFullName()
	self.MotorCache[key] = motor
	return key
end

function ArmReplicator:FindMotorByKey(key)
	return self.MotorCache[key]
end

--============================================================================
-- SENDING (Local Player -> Server)
--============================================================================

function ArmReplicator:StartSending()
	if self.HeartbeatConnection then
		self.HeartbeatConnection:Disconnect()
	end

	self.HeartbeatConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - self.LastUpdateTime < self.UpdateRate then
			return
		end
		self.LastUpdateTime = currentTime

		-- Only send if we have a viewmodel equipped (cache lookup to avoid spam)
		if self.ViewmodelController == nil then
			self.ViewmodelController = ServiceRegistry:GetController("ViewmodelController") or false
		end
		if not self.ViewmodelController or not self.ViewmodelController:IsViewmodelActive() then
			return
		end

		local cameraController = ServiceRegistry:GetController("CameraController")
		if not cameraController then
			return
		end

		-- Calculate look angles from camera
		local cameraCFrame = Camera.CFrame
		local lookDirection = cameraCFrame.LookVector

		-- Pitch: angle looking up/down (negative Y = looking up)
		local pitch = math.asin(-lookDirection.Y)

		-- Yaw: horizontal rotation
		local yaw = math.atan2(-cameraCFrame.LookVector.X, -cameraCFrame.LookVector.Z)

		RemoteEvents:FireServer("ArmLookUpdate", {
			Pitch = pitch,
			Yaw = yaw,
		})
	end)
end

--============================================================================
-- RECEIVING (Server -> Other Players)
--============================================================================

function ArmReplicator:StartReceiving()
	if self.ReplicationConnection then
		self.ReplicationConnection:Disconnect()
	end

	self.ReplicationConnection = RemoteEvents:ConnectClient("ArmLookReplicated", function(playerLookData)
		for userId, lookData in pairs(playerLookData) do
			-- Don't apply to local player
			if userId ~= LocalPlayer.UserId then
				self.RemoteLookDirections[userId] = {
					Pitch = lookData.Pitch,
					Yaw = lookData.Yaw,
					Timestamp = tick(),
				}
			end
		end

		self:ApplyRemoteLookDirections()
	end)
end

--============================================================================
-- APPLYING LOOK DIRECTIONS TO OTHER PLAYER RIGS
--============================================================================

function ArmReplicator:ApplyRemoteLookDirections()
	local RigManager = require(Locations.Modules.Systems.Character.RigManager)

	for userId, lookData in pairs(self.RemoteLookDirections) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			continue
		end

		local rig = RigManager:GetActiveRig(player)
		if not rig then
			continue
		end

		self:ApplyLookToRig(rig, lookData)
	end
end

function ArmReplicator:ApplyLookToRig(rig, lookData)
	local head = rig:FindFirstChild("Head")
	local torso = rig:FindFirstChild("Torso") or rig:FindFirstChild("UpperTorso")

	if not head or not torso then
		return
	end

	-- Get config settings
	local armConfig = ViewmodelConfig.ArmReplication

	-- Apply neck/head rotation
	local neck = torso:FindFirstChild("Neck")
	if neck and neck:IsA("Motor6D") then
		self:ApplyNeckRotation(neck, lookData, armConfig.Neck)
	end

	-- Apply shoulder rotations
	local rightShoulder = torso:FindFirstChild("Right Shoulder")
	local leftShoulder = torso:FindFirstChild("Left Shoulder")

	if rightShoulder and rightShoulder:IsA("Motor6D") then
		self:ApplyShoulderRotation(rightShoulder, lookData, armConfig.RightShoulder, "Right")
	end

	if leftShoulder and leftShoulder:IsA("Motor6D") then
		self:ApplyShoulderRotation(leftShoulder, lookData, armConfig.LeftShoulder, "Left")
	end
end

--[[
	Apply rotation to neck Motor6D
	Uses config settings for offset and pitch limits
	Sets target C0 for smooth lerping
]]
function ArmReplicator:ApplyNeckRotation(neck, lookData, neckConfig)
	local pitch = lookData.Pitch or 0

	-- Clamp pitch to configured limits
	local clampedPitch = math.clamp(pitch, neckConfig.MinPitch, neckConfig.MaxPitch)

	-- Get or store original C0 position and cache motor
	local neckKey = neck:GetFullName()
	if not self.OriginalC0Values[neckKey] then
		self.OriginalC0Values[neckKey] = neck.C0
		self:CacheMotor(neck)
		-- Initialize current C0 to original on first use
		self.CurrentC0Values[neckKey] = neck.C0
	end
	local originalC0 = self.OriginalC0Values[neckKey]

	-- Calculate target rotation: base position + config offset + pitch rotation
	-- Config offset fixes backwards orientation
	local targetC0 = CFrame.new(originalC0.Position)
		* neckConfig.RotationOffset
		* CFrame.Angles(clampedPitch, 0, 0)

	-- Set target for lerp system
	self.TargetC0Values[neckKey] = targetC0
end

--[[
	Apply rotation to shoulder Motor6D
	Uses config settings for offset, pitch follow, and limits
	Sets target C0 for smooth lerping
]]
function ArmReplicator:ApplyShoulderRotation(shoulder, lookData, shoulderConfig, _side)
	local pitch = lookData.Pitch or 0

	-- Clamp pitch to configured limits
	local clampedPitch = math.clamp(pitch, shoulderConfig.MinPitch, shoulderConfig.MaxPitch)

	-- Apply pitch follow factor (how much arm follows head pitch)
	local armPitch = clampedPitch * shoulderConfig.PitchFollow

	-- Get or store original C0 position and cache motor
	local shoulderKey = shoulder:GetFullName()
	if not self.OriginalC0Values[shoulderKey] then
		self.OriginalC0Values[shoulderKey] = shoulder.C0
		self:CacheMotor(shoulder)
		-- Initialize current C0 to original on first use
		self.CurrentC0Values[shoulderKey] = shoulder.C0
	end
	local originalC0 = self.OriginalC0Values[shoulderKey]

	-- Calculate target rotation: base position + pitch rotation + config offset (fixes backwards arm)
	-- The config offset rotates the arm to face forward instead of sideways
	local targetC0 = CFrame.new(originalC0.Position)
		* CFrame.Angles(armPitch, 0, 0)
		* shoulderConfig.RotationOffset

	-- Set target for lerp system
	self.TargetC0Values[shoulderKey] = targetC0
end

--============================================================================
-- UTILITY FUNCTIONS
--============================================================================

--[[
	Get look direction for a specific player
	Returns nil for local player
]]
function ArmReplicator:GetLookDirection(player)
	if player == LocalPlayer then
		return nil
	end

	return self.RemoteLookDirections[player.UserId]
end

--[[
	Clear cached C0 values for a rig (call when rig is destroyed)
]]
function ArmReplicator:ClearCachedC0(rig)
	-- Remove any cached values for this rig's Motor6Ds
	local torso = rig:FindFirstChild("Torso") or rig:FindFirstChild("UpperTorso")
	if torso then
		local neck = torso:FindFirstChild("Neck")
		if neck then
			local key = neck:GetFullName()
			self.OriginalC0Values[key] = nil
			self.CurrentC0Values[key] = nil
			self.TargetC0Values[key] = nil
			self.MotorCache[key] = nil
		end

		local rightShoulder = torso:FindFirstChild("Right Shoulder")
		if rightShoulder then
			local key = rightShoulder:GetFullName()
			self.OriginalC0Values[key] = nil
			self.CurrentC0Values[key] = nil
			self.TargetC0Values[key] = nil
			self.MotorCache[key] = nil
		end

		local leftShoulder = torso:FindFirstChild("Left Shoulder")
		if leftShoulder then
			local key = leftShoulder:GetFullName()
			self.OriginalC0Values[key] = nil
			self.CurrentC0Values[key] = nil
			self.TargetC0Values[key] = nil
			self.MotorCache[key] = nil
		end
	end
end

--[[
	Cleanup all connections and data
]]
function ArmReplicator:Cleanup()
	if self.HeartbeatConnection then
		self.HeartbeatConnection:Disconnect()
		self.HeartbeatConnection = nil
	end

	if self.ReplicationConnection then
		self.ReplicationConnection:Disconnect()
		self.ReplicationConnection = nil
	end

	if self.LerpConnection then
		self.LerpConnection:Disconnect()
		self.LerpConnection = nil
	end

	self.RemoteLookDirections = {}
	self.OriginalC0Values = {}
	self.CurrentC0Values = {}
	self.TargetC0Values = {}
	self.MotorCache = {}
end

return ArmReplicator
