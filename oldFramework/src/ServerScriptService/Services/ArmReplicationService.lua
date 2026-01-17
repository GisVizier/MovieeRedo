local ArmReplicationService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local Log = require(Locations.Modules.Systems.Core.LogService)

ArmReplicationService.PlayerLookData = {}
ArmReplicationService.BroadcastRate = 1 / 20
ArmReplicationService.LastBroadcastTime = 0
ArmReplicationService.HeartbeatConnection = nil

function ArmReplicationService:Init()
	Log:RegisterCategory("ARM_REPLICATION", "Arm/head look direction replication service")

	self:SetupListeners()
	self:StartBroadcasting()

	Players.PlayerRemoving:Connect(function(player)
		self.PlayerLookData[player.UserId] = nil
	end)

	Log:Info("ARM_REPLICATION", "ArmReplicationService initialized")
end

function ArmReplicationService:SetupListeners()
	RemoteEvents:ConnectServer("ArmLookUpdate", function(player, lookData)
		if not lookData or type(lookData) ~= "table" then
			return
		end

		local pitch = lookData.Pitch
		local yaw = lookData.Yaw

		if type(pitch) ~= "number" or type(yaw) ~= "number" then
			return
		end

		pitch = math.clamp(pitch, -math.pi / 2, math.pi / 2)
		yaw = math.clamp(yaw, -math.pi, math.pi)

		self.PlayerLookData[player.UserId] = {
			Pitch = pitch,
			Yaw = yaw,
			Timestamp = tick(),
		}
	end)
end

function ArmReplicationService:StartBroadcasting()
	if self.HeartbeatConnection then
		self.HeartbeatConnection:Disconnect()
	end

	self.HeartbeatConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - self.LastBroadcastTime < self.BroadcastRate then
			return
		end
		self.LastBroadcastTime = currentTime

		local dataCount = 0
		for _ in pairs(self.PlayerLookData) do
			dataCount = dataCount + 1
		end

		if dataCount == 0 then
			return
		end

		RemoteEvents:FireAllClients("ArmLookReplicated", self.PlayerLookData)
	end)
end

function ArmReplicationService:GetPlayerLookData(player)
	return self.PlayerLookData[player.UserId]
end

function ArmReplicationService:Cleanup()
	if self.HeartbeatConnection then
		self.HeartbeatConnection:Disconnect()
		self.HeartbeatConnection = nil
	end

	self.PlayerLookData = {}
end

return ArmReplicationService
