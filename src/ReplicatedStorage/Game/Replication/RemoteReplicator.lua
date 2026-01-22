local RemoteReplicator = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HttpService = game:GetService("HttpService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CompressionUtils = require(Locations.Shared.Util:WaitForChild("CompressionUtils"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local RigManager = require(Locations.Game:WaitForChild("Character"):WaitForChild("Rig"):WaitForChild("RigManager"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local AnimationIds = require(Locations.Shared:WaitForChild("Types"):WaitForChild("AnimationIds"))
local ReplicationConfig = require(Locations.Global:WaitForChild("Replication"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local ThirdPersonWeaponManager =
	require(Locations.Game:WaitForChild("Weapons"):WaitForChild("ThirdPersonWeaponManager"))
local IKSystem = require(Locations.Game:WaitForChild("IK"):WaitForChild("IKSystem"))

RemoteReplicator.RemotePlayers = {}
RemoteReplicator.RenderConnection = nil
RemoteReplicator._net = nil
RemoteReplicator.AnimationController = nil

RemoteReplicator.StatesReceived = 0
RemoteReplicator.PacketsLost = 0
RemoteReplicator.PacketsReceived = 0
RemoteReplicator.Interpolations = 0
RemoteReplicator.StatsResetTime = tick()
RemoteReplicator.PlayerLossStats = {}

function RemoteReplicator:Init(net)
	self._net = net

	self._net:ConnectClient("CharacterStateReplicated", function(batch)
		self:OnStatesReplicated(batch)
	end)
	
	-- Listen for IK aim broadcasts from server
	self._net:ConnectClient("IKAimBroadcast", function(aimBatch)
		self:OnIKAimBroadcast(aimBatch)
	end)

	self.RenderConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:ReplicatePlayers(deltaTime)
	end)
end

function RemoteReplicator:OnStatesReplicated(batch)
	local localPlayer = Players.LocalPlayer
	local currentTime = tick()

	for _, entry in ipairs(batch) do
		local userId = entry.UserId
		local compressedState = entry.State

		if localPlayer and localPlayer.UserId == userId then
			continue
		end

		local state = CompressionUtils:DecompressState(compressedState)
		if not state then
			continue
		end

		local remoteData = self.RemotePlayers[userId]
		if not remoteData then
			local player = Players:GetPlayerByUserId(userId)
			if not player or not player.Character or not player.Character.PrimaryPart then
				continue
			end

			local rig = nil
			if Config.Gameplay.Character.EnableRig then
				rig = RigManager:GetActiveRig(player)
				if not rig then
					rig = RigManager:CreateRig(player, player.Character)
				end
			end

			local headOffset, rigBaseOffset = self:CalculateOffsets()

			-- Initialize weapon manager and IK system for third-person
			local weaponManager = rig and ThirdPersonWeaponManager.new(rig) or nil
			local ikSystem = rig and IKSystem.new(rig) or nil
			if ikSystem then
				ikSystem:SetEnabled(true)
			end

			remoteData = {
				Player = player,
				Character = player.Character,
				PrimaryPart = player.Character.PrimaryPart,
				Rig = rig,
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
				RigPartOffsets = rig and self:_calculateRigPartOffsets(rig) or nil,
				WeaponManager = weaponManager,
				IK = ikSystem,
				IKAimPitch = 0,
				IKAimYaw = 0,
				CurrentLoadout = nil,
				CurrentEquippedSlot = nil,
			}

			-- Parse initial loadout and equipped slot from player attributes
			self:_updateRemoteLoadout(remoteData, player)
			self:_updateRemoteEquippedSlot(remoteData, player)
			self.RemotePlayers[userId] = remoteData

			local primaryPart = remoteData.PrimaryPart
			if primaryPart then
				primaryPart.CFrame = CFrame.new(state.Position) * state.Rotation
				primaryPart.Anchored = true

				local alignOrientation = primaryPart:FindFirstChild("AlignOrientation")
				if alignOrientation then
					alignOrientation.Enabled = false
				end
				local vectorForce = primaryPart:FindFirstChild("VectorForce")
				if vectorForce then
					vectorForce.Enabled = false
				end
			end
		else
			local lastSeq = remoteData.LastSequenceNumber
			local currentSeq = state.SequenceNumber
			local sequenceGap = currentSeq >= lastSeq and (currentSeq - lastSeq) or ((65536 - lastSeq) + currentSeq)

			self.PlayerLossStats[userId] = self.PlayerLossStats[userId]
				or { LossRate = 0, PacketsLost = 0, PacketsReceived = 0 }

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

function RemoteReplicator:_calculateRigPartOffsets(rig)
	if not rig then
		return nil
	end

	local rigRoot = rig:FindFirstChild("HumanoidRootPart") or rig.PrimaryPart
	if not rigRoot then
		return nil
	end

	local offsets = {}
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			offsets[part] = rigRoot.CFrame:ToObjectSpace(part.CFrame)
		end
	end

	return offsets
end

function RemoteReplicator:AddSnapshotToBuffer(remoteData, state, receiveTime)
	local buffer = remoteData.SnapshotBuffer
	if not buffer then
		buffer = {}
		remoteData.SnapshotBuffer = buffer
	end

	remoteData.LastPacketTime = remoteData.LastPacketTime or receiveTime
	remoteData.BufferDelay = remoteData.BufferDelay or ReplicationConfig.Interpolation.InterpolationDelay

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

	for i = #buffer, 1, -1 do
		if buffer[i] and buffer[i].SequenceNumber == snapshot.SequenceNumber then
			return
		end
	end

	table.insert(buffer, snapshot)

	while #buffer > 10 do
		table.remove(buffer, 1)
	end

	local lastPacketTime = remoteData.LastPacketTime or receiveTime
	local currentBufferDelay = remoteData.BufferDelay or 0.1
	local interpolationDelay = ReplicationConfig.Interpolation.InterpolationDelay or 0.1
	local maxExtrapolationTime = ReplicationConfig.Interpolation.MaxExtrapolationTime or 0.2

	local timeSinceLastPacket = receiveTime - lastPacketTime
	remoteData.LastPacketTime = receiveTime

	if timeSinceLastPacket > 0.06 then
		remoteData.BufferDelay = math.min(currentBufferDelay + 0.005, maxExtrapolationTime + interpolationDelay)
	elseif timeSinceLastPacket < 0.025 and #buffer > 5 then
		remoteData.BufferDelay = math.max(currentBufferDelay - 0.003, interpolationDelay)
	end
end

function RemoteReplicator:ReplicatePlayers(dt)
	local currentTime = tick()
	dt = math.clamp(dt, 1 / 240, 1 / 15)

	for userId, remoteData in pairs(self.RemotePlayers) do
		if not remoteData.Character or not remoteData.Character.Parent or not remoteData.PrimaryPart then
			self.RemotePlayers[userId] = nil
			continue
		end

		if remoteData.IsRagdolled then
			continue
		end

		local buffer = remoteData.SnapshotBuffer
		if not buffer or #buffer < 1 then
			continue
		end

		local latestSnapshot = buffer[#buffer]
		local renderTime = currentTime - remoteData.BufferDelay

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

		local positionError = targetPosition - remoteData.SimulatedPosition
		local positionErrorMagnitude = positionError.Magnitude

		if positionErrorMagnitude > 150 then
			remoteData.SimulatedPosition = targetPosition
		else
			local correctionStrength = 15
			local positionCorrection = positionError * (1 - math.exp(-correctionStrength * dt))
			remoteData.SimulatedPosition = remoteData.SimulatedPosition + positionCorrection
		end

		local targetDirection = (targetRotation * Vector3.new(0, 0, -1)).Unit
		local currentDirection = remoteData.SmoothDirection or targetDirection
		local smoothedDirection = currentDirection:Lerp(targetDirection, 1 - math.exp(-15 * dt))
		remoteData.SmoothDirection = smoothedDirection

		local cf
		if smoothedDirection.Magnitude > 0.01 then
			cf = CFrame.new(remoteData.SimulatedPosition, remoteData.SimulatedPosition + smoothedDirection)
		else
			cf = CFrame.new(remoteData.SimulatedPosition)
				* (remoteData.LastCFrame and remoteData.LastCFrame.Rotation or targetRotation)
		end
		remoteData.LastCFrame = cf

		remoteData.PrimaryPart.CFrame = cf

		if remoteData.Rig then
			self:ApplyReplicatedRigRotation(remoteData, targetRigTilt)

			-- Check for loadout/slot changes on the remote player
			self:_updateRemoteLoadout(remoteData, remoteData.Player)
			self:_updateRemoteEquippedSlot(remoteData, remoteData.Player)

			-- Update IK with received aim data
			if remoteData.IK then
				remoteData.IK:Update(dt, remoteData.IKAimPitch or 0, remoteData.IKAimYaw or 0)
			end
		end

		if remoteData.Head and remoteData.Head.Anchored and remoteData.HeadOffset then
			remoteData.Head.CFrame = cf * remoteData.HeadOffset
		end

		if remoteData.LastAnimationId ~= targetAnimationId then
			self:PlayRemoteAnimation(remoteData.Player, targetAnimationId)
			remoteData.LastAnimationId = targetAnimationId
		end

		self.Interpolations = self.Interpolations + 1
	end
end

function RemoteReplicator:PlayRemoteAnimation(player, animationId)
	local animationName = AnimationIds:GetName(animationId)
	if not animationName then
		return
	end

	self.AnimationController = self.AnimationController or ServiceRegistry:GetController("AnimationController")
	if not self.AnimationController then
		return
	end

	local variantIndex = nil
	if animationName:match("^JumpCancel%d$") then
		variantIndex = tonumber(animationName:match("%d$"))
		animationName = "JumpCancel"
	end

	self.AnimationController:PlayAnimationForOtherPlayer(player, animationName, nil, variantIndex)
end

function RemoteReplicator:GetStateAtTime(buffer, renderTime)
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

	if not from or not to then
		local latest = buffer[#buffer]
		return latest.Position, latest.Rotation, latest.IsGrounded, latest.AnimationId, latest.RigTilt or 0
	end

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

function RemoteReplicator:ApplyReplicatedRigRotation(remoteData, rigTilt)
	local rig = remoteData.Rig or CharacterLocations:GetRig(remoteData.Character)
	if not rig or not remoteData.RigBaseOffset then
		return
	end

	local tiltRotation = CFrame.Angles(math.rad(rigTilt), 0, 0)
	local rigOffset = remoteData.RigBaseOffset * tiltRotation
	local targetCFrame = remoteData.PrimaryPart.CFrame * rigOffset

	local parts = {}
	local cframes = {}
	local offsets = remoteData.RigPartOffsets

	if offsets then
		for part, offset in pairs(offsets) do
			if part:IsA("BasePart") then
				table.insert(parts, part)
				table.insert(cframes, targetCFrame * offset)
			end
		end
	else
		for _, part in pairs(rig:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(parts, part)
				table.insert(cframes, targetCFrame)
			end
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
	if tick() - self.StatsResetTime >= 1.0 then
		self:ResetPerSecondStats()
	end

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

-- Update remote player's loadout from their attributes
function RemoteReplicator:_updateRemoteLoadout(remoteData, player)
	if not player then
		return
	end

	local raw = player:GetAttribute("SelectedLoadout")
	if type(raw) ~= "string" or raw == "" then
		return
	end

	-- Check if loadout changed
	if remoteData._lastLoadoutRaw == raw then
		return
	end
	remoteData._lastLoadoutRaw = raw

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)

	if not ok or type(decoded) ~= "table" then
		return
	end

	-- Handle both {loadout: {...}} and direct loadout format
	local loadout = decoded.loadout or decoded
	remoteData.CurrentLoadout = loadout

	-- Re-equip current slot with new loadout
	if remoteData.CurrentEquippedSlot then
		self:_equipRemoteWeapon(remoteData)
	end
end

-- Update remote player's equipped slot from their attributes
function RemoteReplicator:_updateRemoteEquippedSlot(remoteData, player)
	if not player then
		return
	end

	local slot = player:GetAttribute("EquippedSlot")

	-- Check if slot changed
	if remoteData.CurrentEquippedSlot == slot then
		return
	end

	remoteData.CurrentEquippedSlot = slot
	self:_equipRemoteWeapon(remoteData)
end

-- Equip the appropriate weapon on the remote player's rig
function RemoteReplicator:_equipRemoteWeapon(remoteData)
	if not remoteData.WeaponManager then
		return
	end

	local slot = remoteData.CurrentEquippedSlot
	if not slot or slot == "" or slot == "Fists" then
		remoteData.WeaponManager:UnequipWeapon()
		if remoteData.IK then
			remoteData.IK:ClearWeapon()
		end
		return
	end

	-- Get weapon ID from loadout
	local weaponId = nil
	if remoteData.CurrentLoadout and type(remoteData.CurrentLoadout) == "table" then
		weaponId = remoteData.CurrentLoadout[slot]
	end

	if not weaponId or weaponId == "" then
		remoteData.WeaponManager:UnequipWeapon()
		if remoteData.IK then
			remoteData.IK:ClearWeapon()
		end
		return
	end

	-- Equip the weapon
	local success = remoteData.WeaponManager:EquipWeapon(weaponId)
	
	-- Update IK system with weapon
	if remoteData.IK then
		if success then
			remoteData.IK:SetWeapon(remoteData.WeaponManager:GetWeaponModel(), weaponId)
		else
			remoteData.IK:ClearWeapon()
		end
	end
end

-- Handle IK aim broadcasts from server
function RemoteReplicator:OnIKAimBroadcast(aimBatch)
	if type(aimBatch) ~= "table" then
		return
	end
	
	local localPlayer = Players.LocalPlayer
	
	for userIdStr, aimData in pairs(aimBatch) do
		local userId = tonumber(userIdStr)
		if not userId then
			continue
		end
		
		-- Skip local player
		if localPlayer and localPlayer.UserId == userId then
			continue
		end
		
		local remoteData = self.RemotePlayers[userId]
		if remoteData then
			-- Smoothly interpolate aim data
			local targetPitch = aimData.Pitch or 0
			local targetYaw = aimData.Yaw or 0
			
			-- Simple lerp for smooth transitions (can be improved with more sophisticated interpolation)
			local lerpSpeed = 0.3
			remoteData.IKAimPitch = remoteData.IKAimPitch and (remoteData.IKAimPitch + (targetPitch - remoteData.IKAimPitch) * lerpSpeed) or targetPitch
			remoteData.IKAimYaw = remoteData.IKAimYaw and (remoteData.IKAimYaw + (targetYaw - remoteData.IKAimYaw) * lerpSpeed) or targetYaw
		end
	end
end

return RemoteReplicator
