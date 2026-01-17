-- =============================================================================
-- SIMPLIFIED CLIENT REPLICATOR
-- Sends local character state to server at 60Hz
-- Simplified from original - removed unnecessary complexity
-- =============================================================================

local ClientReplicator = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local CompressionUtils = require(Locations.Modules.Utils.CompressionUtils)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

local ReplicationConfig = require(ReplicatedStorage.Configs.ReplicationConfig)

-- State
ClientReplicator.Character = nil
ClientReplicator.PrimaryPart = nil
ClientReplicator.RigHumanoidRootPart = nil
ClientReplicator.RigOffset = CFrame.new()
ClientReplicator.HumanoidOffset = CFrame.new()
ClientReplicator.HeadOffset = CFrame.new()
ClientReplicator.IsActive = false

-- Update tracking
ClientReplicator.LastUpdateTime = 0
ClientReplicator.LastSentState = nil
ClientReplicator.SequenceNumber = 0

-- Performance stats (for debugger)
ClientReplicator.PacketsSent = 0
ClientReplicator.UpdatesSkipped = 0
ClientReplicator.StatsResetTime = tick()

-- Connection
ClientReplicator.UpdateConnection = nil

function ClientReplicator:Init()
	Log:RegisterCategory("REPLICATOR_CLIENT", "Client-side character replication")

	-- Listen for server corrections
	RemoteEvents:ConnectClient("ServerCorrection", function(compressedState)
		-- Reconciliation can be added here if needed
	end)

	local characterStateEvent = RemoteEvents:GetEvent("CharacterStateUpdate")
	local isUnreliable = characterStateEvent and characterStateEvent:IsA("UnreliableRemoteEvent")

	Log:Info("REPLICATOR_CLIENT", "ClientReplicator initialized", {
		UpdateRate = ReplicationConfig.UpdateRates.ClientToServer .. "Hz",
		IsUnreliable = isUnreliable,
	})

	if not isUnreliable then
		Log:Warn("REPLICATOR_CLIENT", "⚠️ CharacterStateUpdate is NOT UnreliableRemoteEvent!")
	end
end

function ClientReplicator:Start(character, primaryPart)
	if self.IsActive then
		self:Stop()
	end

	self.Character = character
	self.PrimaryPart = primaryPart
	self.RigHumanoidRootPart = CharacterLocations:GetRigHumanoidRootPart(character)
	self.IsActive = true
	self.LastUpdateTime = 0
	self.LastSentState = nil
	self.SequenceNumber = 0
	self.PacketsSent = 0
	self.UpdatesSkipped = 0
	self.StatsResetTime = tick()

	self:CalculateOffsets()

	-- Start update loop
	local updateInterval = 1 / ReplicationConfig.UpdateRates.ClientToServer
	self.UpdateConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - self.LastUpdateTime >= updateInterval then
			self:SendStateUpdate()
			self.LastUpdateTime = currentTime
		end

		-- Sync Rig's HumanoidRootPart to Root part every frame
		self:SyncRigHumanoidRootPart()
	end)

	Log:Info("REPLICATOR_CLIENT", "Started replication for character", {
		Character = character.Name,
		UpdateInterval = math.floor(updateInterval * 1000) .. "ms",
	})
end

function ClientReplicator:Stop()
	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
		self.UpdateConnection = nil
	end

	self.IsActive = false
	self.Character = nil
	self.PrimaryPart = nil
	self.RigHumanoidRootPart = nil
	self.RigOffset = CFrame.new()
	self.HumanoidOffset = CFrame.new()
	self.SequenceNumber = 0

	Log:Info("REPLICATOR_CLIENT", "Stopped replication")
end

function ClientReplicator:CalculateOffsets()
	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not characterTemplate then
		return
	end

	local templateRoot = characterTemplate:FindFirstChild("Root")
	if not templateRoot then
		return
	end

	-- Calculate Rig offset
	local templateRig = characterTemplate:FindFirstChild("Rig")
	local templateRigHRP = templateRig and templateRig:FindFirstChild("HumanoidRootPart")
	if templateRigHRP then
		self.RigOffset = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
	end

	-- Calculate Humanoid offset
	local templateHumanoidHRP = characterTemplate:FindFirstChild("HumanoidRootPart")
	if templateHumanoidHRP then
		self.HumanoidOffset = templateRoot.CFrame:Inverse() * templateHumanoidHRP.CFrame
	end

	-- Calculate Head offset
	local templateHead = characterTemplate:FindFirstChild("Head")
	if templateHead then
		self.HeadOffset = templateRoot.CFrame:Inverse() * templateHead.CFrame
	end
end

-- Helper: Collect humanoid parts for voice chat sync
function ClientReplicator:CollectHumanoidParts(parts, cframes, rootCFrame)
	local humanoidRootPart = self.Character:FindFirstChild("HumanoidRootPart")
	local humanoidHead = CharacterLocations:GetHumanoidHead(self.Character)

	if humanoidRootPart then
		humanoidRootPart.Massless = true
		humanoidRootPart.Anchored = true
		table.insert(parts, humanoidRootPart)
		table.insert(cframes, rootCFrame * self.HumanoidOffset)
	end

	if humanoidHead then
		humanoidHead.Massless = true
		humanoidHead.Anchored = true
		table.insert(parts, humanoidHead)
		table.insert(cframes, rootCFrame * (self.HeadOffset or self.HumanoidOffset))
	end
end

function ClientReplicator:SyncRigHumanoidRootPart()
	if not self.Character or not self.PrimaryPart or not self.PrimaryPart.Parent then
		return
	end

	local parts, cframes = {}, {}
	local rootCFrame = self.PrimaryPart.CFrame
	local isRagdolled = self.Character:GetAttribute("RagdollActive")

	-- Sync rig parts (skip if ragdolled)
	if not isRagdolled then
		local rig = CharacterLocations:GetRig(self.Character)
		if rig then
			local rigTargetCFrame = rootCFrame * self.RigOffset
			for _, part in pairs(rig:GetDescendants()) do
				if part:IsA("BasePart") then
					table.insert(parts, part)
					table.insert(cframes, rigTargetCFrame)
				end
			end
		end
	end

	-- Always sync humanoid parts for voice chat
	self:CollectHumanoidParts(parts, cframes, rootCFrame)

	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function ClientReplicator:SendStateUpdate()
	if not self.IsActive or not self.Character or not self.PrimaryPart then
		return
	end

	-- Capture current state
	local position = self.PrimaryPart.Position
	local rotation = self.PrimaryPart.CFrame
	local velocity = self.PrimaryPart.AssemblyLinearVelocity
	local timestamp = tick()
	local isGrounded = MovementStateManager:GetIsGrounded()

	-- Get current animation ID
	local animationController = ServiceRegistry:GetController("AnimationController")
	local animationId = animationController and animationController:GetCurrentAnimationId() or 1

	-- Get rig tilt
	local RigRotationUtils = require(Locations.Modules.Systems.Character.RigRotationUtils)
	local rigTilt = RigRotationUtils:GetCurrentTilt(self.Character) or 0

	-- Delta compression check
	if ReplicationConfig.Compression.UseDeltaCompression and self.LastSentState then
		local shouldSendPosition = CompressionUtils:ShouldSendPositionUpdate(self.LastSentState.Position, position)
		local shouldSendRotation = CompressionUtils:ShouldSendRotationUpdate(self.LastSentState.Rotation, rotation)
		local shouldSendVelocity = CompressionUtils:ShouldSendVelocityUpdate(self.LastSentState.Velocity, velocity)
		local shouldSendGrounded = (self.LastSentState.IsGrounded ~= isGrounded)
		local shouldSendAnimation = (self.LastSentState.AnimationId ~= animationId)
		local shouldSendRigTilt = math.abs((self.LastSentState.RigTilt or 0) - rigTilt) > 1

		if
			not shouldSendPosition
			and not shouldSendRotation
			and not shouldSendVelocity
			and not shouldSendGrounded
			and not shouldSendAnimation
			and not shouldSendRigTilt
		then
			self.UpdatesSkipped = self.UpdatesSkipped + 1
			return -- No significant change, skip update
		end
	end

	-- Increment sequence number
	self.SequenceNumber = (self.SequenceNumber + 1) % 65536

	-- Compress and send state
	local compressedState = CompressionUtils:CompressState(
		position,
		rotation,
		velocity,
		timestamp,
		isGrounded,
		animationId,
		rigTilt,
		self.SequenceNumber
	)

	RemoteEvents:FireServer("CharacterStateUpdate", compressedState)
	self.PacketsSent = self.PacketsSent + 1

	-- Store for delta comparison
	self.LastSentState = {
		Position = position,
		Rotation = rotation,
		Velocity = velocity,
		Timestamp = timestamp,
		IsGrounded = isGrounded,
		AnimationId = animationId,
		RigTilt = rigTilt,
	}
end

function ClientReplicator:GetPerformanceStats()
	local currentTime = tick()
	local timeSinceReset = currentTime - self.StatsResetTime

	-- Reset stats every second for per-second calculations
	if timeSinceReset >= 1.0 then
		self.PacketsSent = 0
		self.UpdatesSkipped = 0
		self.StatsResetTime = currentTime
		timeSinceReset = 0
	end

	return {
		PacketsSent = self.PacketsSent,
		UpdatesSkipped = self.UpdatesSkipped,
		IsReconciling = false, -- Reconciliation removed in simplified version
	}
end

return ClientReplicator
