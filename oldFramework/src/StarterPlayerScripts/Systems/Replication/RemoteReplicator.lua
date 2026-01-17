-- =============================================================================
-- SIMPLIFIED REMOTE REPLICATOR
-- Receives and interpolates other players' states
-- Simplified from original - removed unnecessary complexity
-- =============================================================================

local RemoteReplicator = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local CompressionUtils = require(Locations.Modules.Utils.CompressionUtils)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local Config = require(Locations.Modules.Config)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

local ReplicationConfig = require(ReplicatedStorage.Configs.ReplicationConfig)

-- State tracking
RemoteReplicator.RemotePlayers = {} -- [UserId] = { Player, Character, SnapshotBuffer, SmoothDirection, HeadOffset, RigBaseOffset, BufferDelay, LastPacketTime, SimulatedPosition, LastSequenceNumber, LastAnimationId, Head }
RemoteReplicator.RenderConnection = nil

-- Performance stats (for debugger)
RemoteReplicator.StatesReceived = 0
RemoteReplicator.PacketsLost = 0
RemoteReplicator.PacketsReceived = 0
RemoteReplicator.Interpolations = 0
RemoteReplicator.StatsResetTime = tick()
RemoteReplicator.PlayerLossStats = {} -- [UserId] = { LossRate, PacketsLost, PacketsReceived }

function RemoteReplicator:Init()
	Log:RegisterCategory("REPLICATOR_REMOTE", "Remote player interpolation")

	self.AnimationController = nil -- Cached on first use

	-- Initialize performance stats
	self.StatesReceived = 0
	self.PacketsLost = 0
	self.PacketsReceived = 0
	self.Interpolations = 0
	self.StatsResetTime = tick()
	self.PlayerLossStats = {}

	-- Listen for replicated states from server
	RemoteEvents:ConnectClient("CharacterStateReplicated", function(batch)
		self:OnStatesReplicated(batch)
	end)

	-- Start per-frame rendering loop
	self.RenderConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:ReplicatePlayers(deltaTime)
	end)

	Log:Info("REPLICATOR_REMOTE", "RemoteReplicator initialized")
end

function RemoteReplicator:OnStatesReplicated(batch)
	local localPlayer = Players.LocalPlayer
	local currentTime = tick()

	for _, entry in ipairs(batch) do
		local userId = entry.UserId
		local compressedState = entry.State

		-- Skip local player
		if localPlayer.UserId == userId then
			continue
		end

		-- Decompress state
		local state = CompressionUtils:DecompressState(compressedState)
		if not state then
			continue
		end

		-- Get or create remote player data
		local remoteData = self.RemotePlayers[userId]
		if not remoteData then
			local player = Players:GetPlayerByUserId(userId)
			if not player or not player.Character then
				continue
			end

			-- Calculate offsets from template
			local headOffset, rigBaseOffset = self:CalculateOffsets()

			remoteData = {
				Player = player,
				Character = player.Character,
				SnapshotBuffer = {},
				SmoothDirection = (state.Rotation * Vector3.new(0, 0, -1)).Unit,
				HeadOffset = headOffset,
				RigBaseOffset = rigBaseOffset,
				BufferDelay = ReplicationConfig.Interpolation.InterpolationDelay,
				LastPacketTime = currentTime,
				SimulatedPosition = state.Position,
				LastSequenceNumber = state.SequenceNumber,
				LastAnimationId = state.AnimationId or 1,
				Head = player.Character:FindFirstChild("Head"),
			}
			self.RemotePlayers[userId] = remoteData

			-- Set initial position
			if player.Character.PrimaryPart then
				player.Character.PrimaryPart.CFrame = CFrame.new(state.Position) * state.Rotation
				player.Character.PrimaryPart.Anchored = true

				-- Disable physics constraints
				local alignOrientation = player.Character.PrimaryPart:FindFirstChild("AlignOrientation")
				if alignOrientation then
					alignOrientation.Enabled = false
				end
				local vectorForce = player.Character.PrimaryPart:FindFirstChild("VectorForce")
				if vectorForce then
					vectorForce.Enabled = false
				end
			end
		else
			-- Track packet loss using sequence numbers
			local lastSeq = remoteData.LastSequenceNumber
			local currentSeq = state.SequenceNumber
			local sequenceGap = currentSeq >= lastSeq and (currentSeq - lastSeq) or ((65536 - lastSeq) + currentSeq)

			-- Initialize player stats if needed
			self.PlayerLossStats[userId] = self.PlayerLossStats[userId]
				or { LossRate = 0, PacketsLost = 0, PacketsReceived = 0 }

			-- Track packet loss
			if sequenceGap > 1 then
				local lostPackets = sequenceGap - 1
				self.PacketsLost = self.PacketsLost + lostPackets
				self.PlayerLossStats[userId].PacketsLost = self.PlayerLossStats[userId].PacketsLost + lostPackets
			end

			self.PacketsReceived = self.PacketsReceived + 1
			self.PlayerLossStats[userId].PacketsReceived = self.PlayerLossStats[userId].PacketsReceived + 1
			remoteData.LastSequenceNumber = currentSeq
		end

		self.StatesReceived = self.StatesReceived + 1

		-- Add snapshot to buffer
		self:AddSnapshotToBuffer(remoteData, state, currentTime)
	end
end

function RemoteReplicator:CalculateOffsets()
	local headOffset, rigBaseOffset = nil, nil
	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if characterTemplate then
		local templateHead = characterTemplate:FindFirstChild("Head")
		local templateHRP = characterTemplate:FindFirstChild("HumanoidRootPart")
		if templateHead and templateHRP then
			headOffset = templateHRP.CFrame:ToObjectSpace(templateHead.CFrame)
		end

		local templateRoot = characterTemplate:FindFirstChild("Root")
		local templateRig = characterTemplate:FindFirstChild("Rig")
		local templateRigHRP = templateRig and templateRig:FindFirstChild("HumanoidRootPart")
		if templateRoot and templateRigHRP then
			rigBaseOffset = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
		end
	end
	return headOffset, rigBaseOffset
end

function RemoteReplicator:AddSnapshotToBuffer(remoteData, state, receiveTime)
	local buffer = remoteData.SnapshotBuffer
	if not buffer then
		buffer = {}
		remoteData.SnapshotBuffer = buffer
	end

	-- Initialize LastPacketTime if not set
	if not remoteData.LastPacketTime then
		remoteData.LastPacketTime = receiveTime
	end

	-- Initialize BufferDelay if not set
	if not remoteData.BufferDelay then
		remoteData.BufferDelay = ReplicationConfig.Interpolation.InterpolationDelay
	end

	-- Create snapshot entry
	local snapshot = {
		Position = state.Position,
		Rotation = state.Rotation,
		Velocity = state.Velocity,
		ServerTimestamp = state.Timestamp,
		ReceiveTime = receiveTime,
		IsGrounded = state.IsGrounded,
		AnimationId = state.AnimationId,
		RigTilt = state.RigTilt,
		SequenceNumber = state.SequenceNumber,
	}

	-- Check for duplicate sequence numbers
	for i = #buffer, 1, -1 do
		if buffer[i] and buffer[i].SequenceNumber == snapshot.SequenceNumber then
			return -- Duplicate packet
		end
	end

	-- Insert in chronological order
	table.insert(buffer, snapshot)

	-- Remove old snapshots (keep last 10)
	while #buffer > 10 do
		table.remove(buffer, 1)
	end

	-- Simple adaptive buffer delay (simplified from original)
	-- Defensive: ensure values exist
	local lastPacketTime = remoteData.LastPacketTime or receiveTime
	local currentBufferDelay = remoteData.BufferDelay or 0.1
	local interpolationDelay = ReplicationConfig.Interpolation.InterpolationDelay or 0.1
	local maxExtrapolationTime = ReplicationConfig.Interpolation.MaxExtrapolationTime or 0.2

	local timeSinceLastPacket = receiveTime - lastPacketTime
	remoteData.LastPacketTime = receiveTime

	if timeSinceLastPacket > 0.06 then -- Slow packets
		remoteData.BufferDelay = math.min(currentBufferDelay + 0.005, maxExtrapolationTime + interpolationDelay)
	elseif timeSinceLastPacket < 0.025 and #buffer > 5 then -- Fast packets
		remoteData.BufferDelay = math.max(currentBufferDelay - 0.003, interpolationDelay)
	end
end

function RemoteReplicator:ReplicatePlayers(dt)
	local currentTime = tick()
	dt = math.clamp(dt, 1 / 240, 1 / 15) -- Clamp delta time

	for userId, remoteData in pairs(self.RemotePlayers) do
		if not remoteData.Character or not remoteData.Character.Parent or not remoteData.Character.PrimaryPart then
			self.RemotePlayers[userId] = nil
			continue
		end

		if remoteData.IsRagdolled then
			continue
		end

		local primaryPart = remoteData.Character.PrimaryPart
		local buffer = remoteData.SnapshotBuffer

		if #buffer < 1 then
			continue
		end

		local latestSnapshot = buffer[#buffer]
		local renderTime = currentTime - remoteData.BufferDelay

		-- Get interpolated state
		local targetPosition, targetRotation, targetIsGrounded, targetAnimationId, targetRigTilt =
			self:GetStateAtTime(buffer, renderTime)

		if not targetPosition then
			targetPosition = latestSnapshot.Position
			targetRotation = latestSnapshot.Rotation
			targetIsGrounded = latestSnapshot.IsGrounded
			targetAnimationId = latestSnapshot.AnimationId
			targetRigTilt = latestSnapshot.RigTilt or 0
		end

		if not remoteData.SimulatedPosition then
			remoteData.SimulatedPosition = targetPosition
		end

		-- Detect teleports
		local positionError = targetPosition - remoteData.SimulatedPosition
		local positionErrorMagnitude = positionError.Magnitude

		if positionErrorMagnitude > 150 then
			remoteData.SimulatedPosition = targetPosition
		else
			-- Smooth interpolation
			local correctionStrength = 15
			local positionCorrection = positionError * (1 - math.exp(-correctionStrength * dt))
			remoteData.SimulatedPosition = remoteData.SimulatedPosition + positionCorrection
		end

		-- Smooth rotation
		local targetDirection = (targetRotation * Vector3.new(0, 0, -1)).Unit
		local currentDirection = remoteData.SmoothDirection or targetDirection
		local smoothedDirection = currentDirection:Lerp(targetDirection, 1 - math.exp(-15 * dt))
		remoteData.SmoothDirection = smoothedDirection

		-- Build final CFrame
		local cf
		if smoothedDirection.Magnitude > 0.01 then
			cf = CFrame.new(remoteData.SimulatedPosition, remoteData.SimulatedPosition + smoothedDirection)
		else
			cf = CFrame.new(remoteData.SimulatedPosition)
				* (remoteData.LastCFrame and remoteData.LastCFrame.Rotation or targetRotation)
		end
		remoteData.LastCFrame = cf

		-- Apply to character
		primaryPart.CFrame = cf

		-- Apply rig rotation
		self:ApplyReplicatedRigRotation(remoteData.Character, primaryPart, targetRigTilt, remoteData.RigBaseOffset)

		-- Handle head replication
		if remoteData.Head and remoteData.Head.Anchored and remoteData.HeadOffset then
			remoteData.Head.CFrame = cf * remoteData.HeadOffset
		end

		-- Handle animation changes
		if remoteData.LastAnimationId ~= targetAnimationId then
			self:PlayRemoteAnimation(remoteData.Player, targetAnimationId)
			remoteData.LastAnimationId = targetAnimationId
		end

		self.Interpolations = self.Interpolations + 1
	end
end

-- Helper: Play animation for remote player
function RemoteReplicator:PlayRemoteAnimation(player, animationId)
	local animationName = Config.Animation.AnimationNames[animationId]
	if not animationName then
		return
	end

	self.AnimationController = self.AnimationController or ServiceRegistry:GetController("AnimationController")
	if not self.AnimationController then
		return
	end

	-- Handle JumpCancel variants (JumpCancel1, JumpCancel2, etc.)
	local variantIndex = nil
	if animationName:match("^JumpCancel%d$") then
		variantIndex = tonumber(animationName:match("%d$"))
		animationName = "JumpCancel"
	end

	self.AnimationController:PlayAnimationForOtherPlayer(player, animationName, nil, variantIndex)
end

function RemoteReplicator:GetStateAtTime(buffer, renderTime)
	-- Find the two snapshots that bracket the render time
	local from, to = nil, nil

	for i = 1, #buffer - 1 do
		local current = buffer[i]
		local next = buffer[i + 1]

		if current.ReceiveTime <= renderTime and next.ReceiveTime >= renderTime then
			from = current
			to = next
			break
		end
	end

	-- If no bracket found, use latest snapshot
	if not from or not to then
		local latest = buffer[#buffer]
		return latest.Position, latest.Rotation, latest.IsGrounded, latest.AnimationId, latest.RigTilt or 0
	end

	-- Interpolate between snapshots
	local timeDiff = to.ReceiveTime - from.ReceiveTime
	local alpha = 0
	if timeDiff > 0 then
		alpha = (renderTime - from.ReceiveTime) / timeDiff
		alpha = math.clamp(alpha, 0, 1)
	end

	local position = from.Position:Lerp(to.Position, alpha)
	local rotation = from.Rotation:Lerp(to.Rotation, alpha)
	local isGrounded = to.IsGrounded
	local animationId = to.AnimationId
	local fromTilt = from.RigTilt or 0
	local toTilt = to.RigTilt or 0
	local rigTilt = fromTilt + (toTilt - fromTilt) * alpha

	return position, rotation, isGrounded, animationId, rigTilt
end

function RemoteReplicator:ApplyReplicatedRigRotation(character, primaryPart, rigTilt, rigBaseOffset)
	local rig = CharacterLocations:GetRig(character)
	if not rig or not rigBaseOffset then
		return
	end

	local tiltRotation = CFrame.Angles(math.rad(rigTilt), 0, 0)
	local rigOffset = rigBaseOffset * tiltRotation

	local parts = {}
	local cframes = {}
	local targetCFrame = primaryPart.CFrame * rigOffset

	for _, part in pairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
			table.insert(cframes, targetCFrame)
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function RemoteReplicator:SetPlayerRagdolled(player, isRagdolled)
	local remoteData = self.RemotePlayers[player.UserId]
	if remoteData then
		remoteData.IsRagdolled = isRagdolled
	end
end

function RemoteReplicator:GetPerformanceStats()
	-- Reset stats every second
	if tick() - self.StatsResetTime >= 1.0 then
		self:ResetPerSecondStats()
	end

	-- Calculate global packet loss rate
	local totalPackets = self.PacketsReceived + self.PacketsLost
	local globalLossRate = totalPackets > 0 and (self.PacketsLost / totalPackets) or 0

	return {
		StatesReceived = self.StatesReceived,
		TrackedPlayers = self:GetTrackedPlayerCount(),
		PacketsLost = self.PacketsLost,
		PacketsReceived = self.PacketsReceived,
		Interpolations = self.Interpolations,
		GlobalPacketLossRate = globalLossRate,
		PlayerLossStats = self:GetPlayerLossArray(),
	}
end

function RemoteReplicator:ResetPerSecondStats()
	self.StatesReceived = 0
	self.PacketsLost = 0
	self.PacketsReceived = 0
	self.Interpolations = 0
	self.StatsResetTime = tick()

	for _, stats in pairs(self.PlayerLossStats) do
		local total = stats.PacketsReceived + stats.PacketsLost
		stats.LossRate = total > 0 and (stats.PacketsLost / total) or 0
		stats.PacketsLost = 0
		stats.PacketsReceived = 0
	end
end

function RemoteReplicator:GetPlayerLossArray()
	local result = {}
	for userId, stats in pairs(self.PlayerLossStats) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(result, { Player = player.Name, LossRate = stats.LossRate })
		end
	end
	return result
end

function RemoteReplicator:GetTrackedPlayerCount()
	local count = 0
	for _, remoteData in pairs(self.RemotePlayers) do
		if remoteData.Character and remoteData.Character.Parent then
			count = count + 1
		end
	end
	return count
end

return RemoteReplicator
