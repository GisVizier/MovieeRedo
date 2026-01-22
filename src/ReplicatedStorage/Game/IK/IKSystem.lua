--[[
	IKSystem.lua
	
	State management and network synchronization for character IK.
	Creates per-character IK controllers and handles aim replication.
	
	Usage:
		-- Create IK for a rig
		local ik = IKSystem.new(rig)
		ik:SetEnabled(true)
		
		-- Each frame
		ik:Update(dt, aimPitch, aimYaw)
		
		-- When weapon changes
		ik:SetWeapon(weaponModel, weaponId)
		
		-- Cleanup
		ik:Destroy()
		
		-- Network (call once globally)
		IKSystem.StartReplication(net)
		IKSystem.StopReplication()
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local IKSolver = require(Locations.Shared.Util:WaitForChild("IKSolver"))

local IKSystem = {}
IKSystem.__index = IKSystem

--------------------------------------------------------------------------------
-- STATIC STATE (Network replication)
--------------------------------------------------------------------------------

local _net = nil
local _sendConnection = nil
local _receiveConnection = nil
local _lastSendTime = 0
local _remoteAimData = {} -- [userId] = { pitch, yaw, timestamp }

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

--[[
	Create a new IK controller for a character rig.
	
	@param rig - The R6 character rig model
	@return IKSystem instance or nil
]]
function IKSystem.new(rig: Model)
	if not rig then
		return nil
	end
	
	local self = setmetatable({}, IKSystem)
	
	self.Rig = rig
	self.Enabled = false
	self._blendTarget = 0
	self._currentBlend = 0
	
	-- Find and cache Motor6Ds
	self.Motors = {}
	self.OriginalC0 = {}
	self.CurrentC0 = {}
	
	local torso = rig:FindFirstChild("Torso")
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	
	if not torso then
		warn("[IKSystem] Rig missing Torso")
		return nil
	end
	
	-- Cache motors and their original C0 values
	local motorNames = {
		"RootJoint",      -- HRP -> Torso (torso pitch)
		"Neck",           -- Torso -> Head (head look)
		"Left Shoulder",  -- Torso -> Left Arm
		"Right Shoulder", -- Torso -> Right Arm
	}
	
	for _, name in ipairs(motorNames) do
		local motor = nil
		if name == "RootJoint" and hrp then
			motor = hrp:FindFirstChild("RootJoint")
		else
			motor = torso:FindFirstChild(name)
		end
		
		if motor and motor:IsA("Motor6D") then
			self.Motors[name] = motor
			self.OriginalC0[name] = motor.C0
			self.CurrentC0[name] = motor.C0
		end
	end
	
	-- Arm lengths (R6 arms are single parts)
	local leftArm = rig:FindFirstChild("Left Arm")
	local rightArm = rig:FindFirstChild("Right Arm")
	
	self.ArmLengths = {
		Left = leftArm and (leftArm.Size.Y * 0.5) or 1,
		Right = rightArm and (rightArm.Size.Y * 0.5) or 1,
	}
	
	-- Weapon state
	self.WeaponModel = nil
	self.WeaponId = nil
	self.RightGripAttachment = nil
	self.LeftGripAttachment = nil
	
	return self
end

--------------------------------------------------------------------------------
-- ENABLE/DISABLE
--------------------------------------------------------------------------------

--[[
	Enable or disable IK with smooth blend transition.
]]
function IKSystem:SetEnabled(enabled: boolean)
	self.Enabled = enabled
	self._blendTarget = enabled and 1 or 0
end

--[[
	Check if IK is currently enabled.
]]
function IKSystem:IsEnabled(): boolean
	return self.Enabled
end

--------------------------------------------------------------------------------
-- WEAPON MANAGEMENT
--------------------------------------------------------------------------------

--[[
	Set the current weapon for arm IK targeting.
	
	@param weaponModel - The weapon Model (or nil to clear)
	@param weaponId - Weapon identifier for config lookup
]]
function IKSystem:SetWeapon(weaponModel: Model?, weaponId: string?)
	self.WeaponModel = weaponModel
	self.WeaponId = weaponId
	self.RightGripAttachment = nil
	self.LeftGripAttachment = nil
	
	if not weaponModel or not weaponId then
		return
	end
	
	-- Get grip attachment paths from config
	local config = IKSolver.GetWeaponConfig(weaponId)
	if not config then
		return
	end
	
	-- Find grip attachments
	if config.RightGrip then
		self.RightGripAttachment = IKSolver.GetAttachmentFromPath(weaponModel, config.RightGrip)
	end
	
	if config.LeftGrip then
		self.LeftGripAttachment = IKSolver.GetAttachmentFromPath(weaponModel, config.LeftGrip)
	end
end

--[[
	Clear the current weapon.
]]
function IKSystem:ClearWeapon()
	self:SetWeapon(nil, nil)
end

--------------------------------------------------------------------------------
-- UPDATE (Call every frame)
--------------------------------------------------------------------------------

--[[
	Update IK for this character.
	
	@param dt - Delta time
	@param aimPitch - Vertical aim angle (radians, negative = up)
	@param aimYaw - Horizontal aim angle relative to torso (radians)
]]
function IKSystem:Update(dt: number, aimPitch: number, aimYaw: number)
	if not self.Rig or not self.Rig.Parent then
		return
	end
	
	-- Update blend
	local blendSpeed = IKSolver.Config.BlendSpeed
	local blendDelta = (self._blendTarget - self._currentBlend) * math.min(dt * blendSpeed, 1)
	self._currentBlend = self._currentBlend + blendDelta
	
	-- Skip if blend is zero
	if self._currentBlend < 0.01 then
		return
	end
	
	-- Apply torso pitch
	self:_applyTorsoPitch(aimPitch)
	
	-- Apply head look
	self:_applyHeadLook(aimPitch, aimYaw)
	
	-- Apply arm IK (if weapon equipped)
	self:_applyArmIK()
end

--------------------------------------------------------------------------------
-- INTERNAL: IK APPLICATION
--------------------------------------------------------------------------------

function IKSystem:_applyTorsoPitch(aimPitch: number)
	local motor = self.Motors["RootJoint"]
	if not motor then
		return
	end
	
	local original = self.OriginalC0["RootJoint"]
	local config = IKSolver.Config.Torso
	
	-- Calculate target pitch
	local targetPitch = IKSolver.SolveTorsoPitch(aimPitch)
	
	-- Apply pitch rotation to original C0
	local targetC0 = original * CFrame.Angles(targetPitch * config.BlendFactor, 0, 0)
	
	-- Blend between original and target
	local blend = self._currentBlend * config.BlendFactor
	motor.C0 = IKSolver.LerpCFrame(original, targetC0, blend)
	self.CurrentC0["RootJoint"] = motor.C0
end

function IKSystem:_applyHeadLook(aimPitch: number, aimYaw: number)
	local motor = self.Motors["Neck"]
	if not motor then
		return
	end
	
	local original = self.OriginalC0["Neck"]
	local config = IKSolver.Config.Head
	
	-- Calculate head rotation
	local headRotation = IKSolver.SolveHeadLook(aimPitch, aimYaw)
	
	-- Apply rotation to original C0
	local targetC0 = CFrame.new(original.Position) * headRotation
	
	-- Blend
	local blend = self._currentBlend * config.BlendFactor
	motor.C0 = IKSolver.LerpCFrame(original, targetC0, blend)
	self.CurrentC0["Neck"] = motor.C0
end

function IKSystem:_applyArmIK()
	local weaponId = self.WeaponId
	if not weaponId then
		-- Reset arms to original
		self:_resetArm("Right")
		self:_resetArm("Left")
		return
	end
	
	-- Right arm
	if IKSolver.ShouldUseArmIK(weaponId, "Right") and self.RightGripAttachment then
		self:_solveArm("Right", self.RightGripAttachment.WorldPosition)
	else
		self:_resetArm("Right")
	end
	
	-- Left arm
	if IKSolver.ShouldUseArmIK(weaponId, "Left") and self.LeftGripAttachment then
		self:_solveArm("Left", self.LeftGripAttachment.WorldPosition)
	else
		self:_resetArm("Left")
	end
end

function IKSystem:_solveArm(side: string, targetPos: Vector3)
	local motorName = side .. " Shoulder"
	local motor = self.Motors[motorName]
	if not motor or not motor.Part0 then
		return
	end
	
	local original = self.OriginalC0[motorName]
	local armLength = self.ArmLengths[side]
	local config = IKSolver.Config.Arm
	
	-- Get shoulder origin in world space
	local originCF = motor.Part0.CFrame * original
	
	-- Solve IK
	local planeCF, shoulderAngle, elbowAngle = IKSolver.SolveArmIK(
		originCF,
		targetPos,
		armLength,
		armLength, -- R6: upper and lower are same (single arm part)
		side
	)
	
	-- Calculate arm CFrame chain
	local shoulderCF = planeCF * CFrame.Angles(shoulderAngle, 0, 0)
	local upperArmCF = shoulderCF * CFrame.new(0, -armLength, 0)
	local elbowCF = upperArmCF * CFrame.Angles(elbowAngle, 0, 0)
	local handCF = elbowCF * CFrame.new(0, -armLength * 0.5, 0)
	
	-- Convert to C0
	local targetC0 = IKSolver.WorldCFrameToC0(motor, handCF)
	
	-- Blend
	local blend = self._currentBlend * config.BlendFactor
	motor.C0 = IKSolver.LerpCFrame(original, targetC0, blend)
	self.CurrentC0[motorName] = motor.C0
end

function IKSystem:_resetArm(side: string)
	local motorName = side .. " Shoulder"
	local motor = self.Motors[motorName]
	if not motor then
		return
	end
	
	local original = self.OriginalC0[motorName]
	local current = self.CurrentC0[motorName]
	
	-- Smoothly blend back to original
	local blend = 1 - self._currentBlend
	motor.C0 = IKSolver.LerpCFrame(current, original, blend * 0.1)
	self.CurrentC0[motorName] = motor.C0
end

--------------------------------------------------------------------------------
-- RESET
--------------------------------------------------------------------------------

--[[
	Reset all motors to original C0 values.
]]
function IKSystem:Reset()
	for name, motor in pairs(self.Motors) do
		if motor and self.OriginalC0[name] then
			motor.C0 = self.OriginalC0[name]
			self.CurrentC0[name] = self.OriginalC0[name]
		end
	end
	self._currentBlend = 0
end

--------------------------------------------------------------------------------
-- DESTROY
--------------------------------------------------------------------------------

--[[
	Cleanup and reset.
]]
function IKSystem:Destroy()
	self:Reset()
	self:ClearWeapon()
	self.Rig = nil
	self.Motors = {}
	self.OriginalC0 = {}
	self.CurrentC0 = {}
end

--------------------------------------------------------------------------------
-- STATIC: NETWORK REPLICATION
--------------------------------------------------------------------------------

--[[
	Start network replication for aim direction.
	Call once when initializing the IK system.
	
	@param net - Network module with FireServer/ConnectClient
]]
function IKSystem.StartReplication(net)
	if _sendConnection or _receiveConnection then
		IKSystem.StopReplication()
	end
	
	_net = net
	local localPlayer = Players.LocalPlayer
	local updateInterval = 1 / IKSolver.Config.NetworkUpdateRate
	
	-- Send local aim direction at 20Hz
	_sendConnection = RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - _lastSendTime < updateInterval then
			return
		end
		_lastSendTime = now
		
		-- Get camera aim direction
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		
		local lookVector = camera.CFrame.LookVector
		local pitch = math.asin(-lookVector.Y)
		local yaw = math.atan2(-lookVector.X, -lookVector.Z)
		
		-- Send to server
		if _net and _net.FireServer then
			_net:FireServer("IKAimUpdate", {
				Pitch = pitch,
				Yaw = yaw,
			})
		end
	end)
	
	-- Receive aim data from other players
	if _net and _net.ConnectClient then
		_receiveConnection = _net:ConnectClient("IKAimBroadcast", function(data)
			-- data = { [userId] = { Pitch, Yaw } }
			if type(data) ~= "table" then
				return
			end
			
			for userIdStr, aimData in pairs(data) do
				local userId = tonumber(userIdStr) or userIdStr
				if userId ~= (localPlayer and localPlayer.UserId) then
					_remoteAimData[userId] = {
						Pitch = aimData.Pitch or 0,
						Yaw = aimData.Yaw or 0,
						Timestamp = tick(),
					}
				end
			end
		end)
	end
end

--[[
	Stop network replication.
]]
function IKSystem.StopReplication()
	if _sendConnection then
		_sendConnection:Disconnect()
		_sendConnection = nil
	end
	
	if _receiveConnection then
		_receiveConnection:Disconnect()
		_receiveConnection = nil
	end
	
	_net = nil
	_remoteAimData = {}
end

--[[
	Get aim data for a remote player.
	
	@param player - Player instance
	@return { Pitch, Yaw } or nil
]]
function IKSystem.GetRemoteAimData(player: Player)
	if not player then
		return nil
	end
	
	return _remoteAimData[player.UserId]
end

--[[
	Get all remote aim data.
	
	@return Table of [userId] = { Pitch, Yaw, Timestamp }
]]
function IKSystem.GetAllRemoteAimData()
	return _remoteAimData
end

return IKSystem
