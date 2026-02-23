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
local function vmLog(...) end

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
RemoteReplicator.PendingViewmodelActions = {}
RemoteReplicator.PendingCrouchStates = {}
RemoteReplicator.ActiveViewmodelState = {} -- [userId] = { [key] = payload }
RemoteReplicator._localInLobby = false
RemoteReplicator._lobbyConn = nil

local MAX_SEQUENCE = 65536
local HALF_SEQUENCE = MAX_SEQUENCE / 2

local function isStatefulViewmodelAction(actionName: string): boolean
	return actionName == "ADS"
		or actionName == "PlayWeaponTrack"
		or actionName == "PlayAnimation"
end

local function getViewmodelActionStateKey(weaponId: string, actionName: string, trackName: string): string
	return string.format("%s|%s|%s", tostring(actionName), tostring(weaponId), tostring(trackName))
end

function RemoteReplicator:Init(net)
	self._net = net

	self._net:ConnectClient("CharacterStateReplicated", function(batch)
		self:OnStatesReplicated(batch)
	end)

	self._net:ConnectClient("ViewmodelActionReplicated", function(compressedPayload)
		self:OnViewmodelActionReplicated(compressedPayload)
	end)

	self._net:ConnectClient("ViewmodelActionSnapshot", function(snapshot)
		self:OnViewmodelActionSnapshot(snapshot)
	end)

	self._net:ConnectClient("CrouchStateChanged", function(otherPlayer, isCrouching)
		self:OnCrouchStateChanged(otherPlayer, isCrouching)
	end)

	local localPlayer = Players.LocalPlayer
	if localPlayer then
		self._localInLobby = localPlayer:GetAttribute("InLobby") == true
		self._lobbyConn = localPlayer:GetAttributeChangedSignal("InLobby"):Connect(function()
			local inLobby = localPlayer:GetAttribute("InLobby") == true
			if inLobby ~= self._localInLobby then
				self._localInLobby = inLobby
				if inLobby then
					-- Entered lobby: unequip weapons for all remote players
					for _, remoteData in pairs(self.RemotePlayers) do
						if remoteData.WeaponManager then
							remoteData.WeaponManager:UnequipWeapon()
						end
					end
				else
					-- Left lobby: re-equip weapons for all remote players
					for _, remoteData in pairs(self.RemotePlayers) do
						if remoteData.WeaponManager then
							self:_equipRemoteWeapon(remoteData)
						end
					end
				end
			end
		end)
	end

	self.RenderConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:ReplicatePlayers(deltaTime)
	end)
end

function RemoteReplicator:OnCrouchStateChanged(otherPlayer, isCrouching)
	if not otherPlayer then
		return
	end

	local userId = otherPlayer.UserId
	local crouchState = isCrouching == true
	local remoteData = self.RemotePlayers[userId]
	if not remoteData then
		self.PendingCrouchStates[userId] = crouchState
		return
	end

	remoteData.IsCrouching = crouchState
	if remoteData.WeaponManager then
		remoteData.WeaponManager:SetCrouching(crouchState)
	end
end

function RemoteReplicator:OnViewmodelActionReplicated(compressedPayload)
	local payload = CompressionUtils:DecompressViewmodelAction(compressedPayload)
	if not payload then
		vmLog("Drop: failed decompress")
		return
	end

	local userId = tonumber(payload.PlayerUserId)
	if not userId then
		vmLog("Drop: invalid userId")
		return
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer.UserId == userId then
		return
	end

	local remoteData = self.RemotePlayers[userId]
	if not remoteData then
		vmLog("Queue pending action; remoteData missing", "userId=", userId, "action=", tostring(payload.ActionName))
		local pending = self.PendingViewmodelActions[userId]
		if not pending then
			pending = {}
			self.PendingViewmodelActions[userId] = pending
		end
		table.insert(pending, payload)
		if #pending > 8 then
			table.remove(pending, 1)
		end
		return
	end

	vmLog(
		"Apply immediate action",
		"userId=",
		userId,
		"weapon=",
		tostring(payload.WeaponId),
		"action=",
		tostring(payload.ActionName)
	)
	self:_applyReplicatedViewmodelAction(remoteData, payload)
end

function RemoteReplicator:_applyViewmodelActionByUserId(userId: number, payload, forceApply: boolean?)
	local remoteData = self.RemotePlayers[userId]
	if remoteData then
		if forceApply == true then
			payload.ForceApply = true
		end
		self:_applyReplicatedViewmodelAction(remoteData, payload)
		return
	end

	local pending = self.PendingViewmodelActions[userId]
	if not pending then
		pending = {}
		self.PendingViewmodelActions[userId] = pending
	end
	if forceApply == true then
		payload.ForceApply = true
	end
	table.insert(pending, payload)
	if #pending > 16 then
		table.remove(pending, 1)
	end
end

function RemoteReplicator:OnViewmodelActionSnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	local desiredByUser = {}
	for _, payload in ipairs(snapshot) do
		if type(payload) == "table" then
			local userId = tonumber(payload.PlayerUserId)
			local actionName = tostring(payload.ActionName or "")
			local isActive = payload.IsActive == true
			if userId and isStatefulViewmodelAction(actionName) and isActive then
				local weaponId = tostring(payload.WeaponId or "")
				local trackName = tostring(payload.TrackName or "")
				local key = getViewmodelActionStateKey(weaponId, actionName, trackName)
				local desired = desiredByUser[userId]
				if not desired then
					desired = {}
					desiredByUser[userId] = desired
				end
				desired[key] = payload
			end
		end
	end

	for userId, currentMap in pairs(self.ActiveViewmodelState) do
		local desiredMap = desiredByUser[userId] or {}
		for key, currentPayload in pairs(currentMap) do
			if desiredMap[key] == nil then
				local stopPayload = {
					PlayerUserId = userId,
					WeaponId = currentPayload.WeaponId,
					SkinId = currentPayload.SkinId,
					ActionName = currentPayload.ActionName,
					TrackName = currentPayload.TrackName,
					IsActive = false,
				}
				self:_applyViewmodelActionByUserId(userId, stopPayload, true)
			end
		end
	end

	for userId, desiredMap in pairs(desiredByUser) do
		for _, payload in pairs(desiredMap) do
			self:_applyViewmodelActionByUserId(userId, payload, true)
		end
	end
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
			if not player then
				continue
			end

			-- player.Character relies on property replication which can be slow.
			-- Fallback: look for character in Entities folder by player name.
			local character = player.Character
			if not character or not character.PrimaryPart then
				local entities = workspace:FindFirstChild("Entities")
				if entities then
					character = entities:FindFirstChild(player.Name)
				end
				-- Final fallback: check workspace directly
				if not character then
					character = workspace:FindFirstChild(player.Name)
				end
			end

			if not character or not character.PrimaryPart then
				vmLog("Skip state: no character/primarypart for", player.Name)
				continue
			end

			local rig = nil
			if Config.Gameplay.Character.EnableRig then
				-- Rig is created server-side and replicates automatically.
				-- GetActiveRig checks the Rigs container by OwnerUserId attribute.
				rig = RigManager:GetActiveRig(player)
				if not rig then
					local waitStart = tick()
					while not rig and (tick() - waitStart) < 5 do
						task.wait(0.15)
						rig = RigManager:GetActiveRig(player)
					end
				end
			end

			local headOffset, rigBaseOffset = self:CalculateOffsets()

			-- Initialize weapon manager for third-person
			local weaponManager = rig and ThirdPersonWeaponManager.new(rig) or nil
			vmLog(
				"Created remoteData",
				"player=",
				player.Name,
				"hasRig=",
				rig ~= nil,
				"hasWeaponManager=",
				weaponManager ~= nil
			)

			remoteData = {
				Player = player,
				Character = character,
				PrimaryPart = character.PrimaryPart,
				Rig = rig,
				SnapshotBuffer = {},
				SmoothDirection = (state.Rotation * Vector3.new(0, 0, -1)).Unit,
				HeadOffset = headOffset,
				RigBaseOffset = rigBaseOffset,
				BufferDelay = ReplicationConfig.Interpolation.InterpolationDelay,
				LastPacketTime = currentTime,
				SimulatedPosition = state.Position,
				LastSequenceNumber = state.SequenceNumber,
				LastAnimationId = 0, -- Sentinel: force initial animation play for late joiners
				LastAimPitch = state.AimPitch or 0,
				Head = character:FindFirstChild("Head"),
				RigPartOffsets = rig and self:_calculateRigPartOffsets(rig) or nil,
				WeaponManager = weaponManager,
				CurrentLoadout = nil,
				CurrentSkins = nil,
				CurrentEquippedSlot = nil,
				LastViewmodelActionSeq = nil,
				IsCrouching = self.PendingCrouchStates[userId] == true,
			}

			self.PendingCrouchStates[userId] = nil
			if weaponManager then
				weaponManager:SetCrouching(remoteData.IsCrouching)
			end

			-- Parse initial loadout and equipped slot from player attributes (skip equip when in lobby)
			if not self._localInLobby then
				self:_updateRemoteLoadout(remoteData, player)
				self:_updateRemoteEquippedSlot(remoteData, player)
			end
			self.RemotePlayers[userId] = remoteData

			-- Add initial state to buffer so ReplicatePlayers processes updates (fixes stuck animation for late joiners)
			self:AddSnapshotToBuffer(remoteData, state, currentTime)

			local pendingActions = self.PendingViewmodelActions[userId]
			if pendingActions then
				vmLog("Flushing pending actions", "player=", player.Name, "count=", #pendingActions)
				for _, pendingPayload in ipairs(pendingActions) do
					self:_applyReplicatedViewmodelAction(remoteData, pendingPayload)
				end
				self.PendingViewmodelActions[userId] = nil
			end

			-- Force-play initial animation so late joiners see the correct state immediately
			local initialAnimId = state.AnimationId or 1
			if self:PlayRemoteAnimation(remoteData.Player, initialAnimId) then
				remoteData.LastAnimationId = initialAnimId
			end

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
			local lastSeq = tonumber(remoteData.LastSequenceNumber) or 0
			local currentSeq = tonumber(state.SequenceNumber) or 0
			local sequenceGap = (currentSeq - lastSeq) % MAX_SEQUENCE

			self.PlayerLossStats[userId] = self.PlayerLossStats[userId]
				or { LossRate = 0, PacketsLost = 0, PacketsReceived = 0 }

			-- Drop duplicate/out-of-order snapshots so stale initial states cannot
			-- overwrite a newer movement animation state for late joiners.
			if sequenceGap == 0 then
				continue
			end
			if sequenceGap > HALF_SEQUENCE then
				continue
			end

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
		AimPitch = state.AimPitch or 0,
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
			-- Cleanup weapon manager before removing
			if remoteData.WeaponManager then
				remoteData.WeaponManager:Destroy()
			end
			self.PendingViewmodelActions[userId] = nil
			self.ActiveViewmodelState[userId] = nil
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

		local targetPosition, targetRotation, targetAimPitch, targetIsGrounded, targetAnimationId, targetRigTilt =
			self:GetStateAtTime(buffer, renderTime)

		if not targetPosition then
			targetPosition = latestSnapshot.Position
			targetRotation = latestSnapshot.Rotation
			targetAimPitch = latestSnapshot.AimPitch or 0
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
		remoteData.LastAimPitch = targetAimPitch or 0

		if remoteData.Rig then
			self:ApplyReplicatedRigRotation(remoteData, targetRigTilt)

			-- Check for loadout/slot changes on the remote player (skip when in lobby)
			if not self._localInLobby then
				self:_updateRemoteLoadout(remoteData, remoteData.Player)
				self:_updateRemoteEquippedSlot(remoteData, remoteData.Player)
			end
		end

		if remoteData.WeaponManager and not self._localInLobby then
			remoteData.WeaponManager:SetCrouching(remoteData.IsCrouching == true)
			remoteData.WeaponManager:UpdateTransform(cf, remoteData.LastAimPitch, dt)
		end

		if remoteData.Head and remoteData.Head.Anchored and remoteData.HeadOffset then
			remoteData.Head.CFrame = cf * remoteData.HeadOffset
		end

		if remoteData.LastAnimationId ~= targetAnimationId then
			if self:PlayRemoteAnimation(remoteData.Player, targetAnimationId) then
				remoteData.LastAnimationId = targetAnimationId
			end
		end

		self.Interpolations = self.Interpolations + 1
	end
end

function RemoteReplicator:PlayRemoteAnimation(player, animationId)
	local animationName = AnimationIds:GetName(animationId)
	if not animationName then
		return false
	end

	self.AnimationController = self.AnimationController or ServiceRegistry:GetController("AnimationController")
	if not self.AnimationController then
		return false
	end

	local variantIndex = nil
	if animationName:match("^JumpCancel%d$") then
		variantIndex = tonumber(animationName:match("%d$"))
		animationName = "JumpCancel"
	end

	return self.AnimationController:PlayAnimationForOtherPlayer(player, animationName, nil, variantIndex) == true
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
		return latest.Position,
			latest.Rotation,
			latest.AimPitch or 0,
			latest.IsGrounded,
			latest.AnimationId,
			latest.RigTilt or 0
	end

	local timeDiff = to.ReceiveTime - from.ReceiveTime
	local alpha = 0
	if timeDiff > 0 then
		alpha = (renderTime - from.ReceiveTime) / timeDiff
		alpha = math.clamp(alpha, 0, 1)
	end

	local position = from.Position:Lerp(to.Position, alpha)
	local rotation = from.Rotation:Lerp(to.Rotation, alpha)
	local fromAimPitch = from.AimPitch or 0
	local toAimPitch = to.AimPitch or 0
	local aimPitch = fromAimPitch + (toAimPitch - fromAimPitch) * alpha
	local isGrounded = to.IsGrounded
	local animationId = to.AnimationId
	local fromTilt = from.RigTilt or 0
	local toTilt = to.RigTilt or 0
	local rigTilt = fromTilt + (toTilt - fromTilt) * alpha

	return position, rotation, aimPitch, isGrounded, animationId, rigTilt
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

function RemoteReplicator:_applyReplicatedViewmodelAction(remoteData, payload)
	if not remoteData or not payload then
		return
	end

	if self._localInLobby then
		return
	end

	local forceApply = payload.ForceApply == true
	local sequenceNumber = tonumber(payload.SequenceNumber) or 0
	if not forceApply then
		local lastSeq = remoteData.LastViewmodelActionSeq
		if lastSeq ~= nil then
			local gap = sequenceNumber >= lastSeq and (sequenceNumber - lastSeq) or ((65536 - lastSeq) + sequenceNumber)
			if gap == 0 then
				return
			end
			if gap > 32768 then
				return
			end
		end
		remoteData.LastViewmodelActionSeq = sequenceNumber
	end

	local weaponManager = remoteData.WeaponManager
	if not weaponManager then
		return
	end

	local weaponId = tostring(payload.WeaponId or "")
	local skinId = tostring(payload.SkinId or "")
	local actionName = tostring(payload.ActionName or "")
	local trackName = tostring(payload.TrackName or "")
	local isActive = payload.IsActive == true
	local player = remoteData.Player
	local userId = player and player.UserId or nil

	if actionName == "Unequip" then
		vmLog("Remote unequip", remoteData.Player and remoteData.Player.Name or "?", "seq=", sequenceNumber)
		weaponManager:UnequipWeapon()
		if userId then
			self.ActiveViewmodelState[userId] = {}
		end
		return
	end

	local currentSkinId = ""
	if type(weaponManager.GetSkinId) == "function" then
		currentSkinId = tostring(weaponManager:GetSkinId() or "")
	end

	if weaponId ~= "" and (weaponManager:GetWeaponId() ~= weaponId or currentSkinId ~= skinId) then
		vmLog(
			"Remote equip",
			remoteData.Player and remoteData.Player.Name or "?",
			"weapon=",
			weaponId,
			"skin=",
			skinId,
			"seq=",
			sequenceNumber
		)
		weaponManager:EquipWeapon(weaponId, skinId)
	end

	vmLog(
		"Remote apply action",
		remoteData.Player and remoteData.Player.Name or "?",
		"action=",
		actionName,
		"track=",
		trackName,
		"active=",
		tostring(isActive)
	)
	weaponManager:ApplyReplicatedAction(actionName, trackName, isActive)

	if userId and isStatefulViewmodelAction(actionName) then
		local userMap = self.ActiveViewmodelState[userId]
		if not userMap then
			userMap = {}
			self.ActiveViewmodelState[userId] = userMap
		end
		local stateKey = getViewmodelActionStateKey(weaponId, actionName, trackName)
		if isActive then
			userMap[stateKey] = {
				PlayerUserId = userId,
				WeaponId = weaponId,
				SkinId = skinId,
				ActionName = actionName,
				TrackName = trackName,
				IsActive = true,
			}
		else
			userMap[stateKey] = nil
		end
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

	-- Optional skin payload support if upstream includes it.
	local skins = decoded.equippedSkins or decoded.skins or decoded.EQUIPPED_SKINS
	if type(skins) == "table" then
		remoteData.CurrentSkins = skins
	else
		remoteData.CurrentSkins = nil
	end

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
	if not slot or slot == "" then
		remoteData.WeaponManager:UnequipWeapon()
		return
	end

	-- Get weapon ID from loadout
	local weaponId = nil
	if slot == "Fists" then
		weaponId = "Fists"
	elseif remoteData.CurrentLoadout and type(remoteData.CurrentLoadout) == "table" then
		weaponId = remoteData.CurrentLoadout[slot]
	end

	if not weaponId or weaponId == "" then
		remoteData.WeaponManager:UnequipWeapon()
		return
	end

	-- Equip the weapon
	local skinId = ""
	if type(remoteData.CurrentSkins) == "table" then
		local resolved = remoteData.CurrentSkins[weaponId]
		if type(resolved) == "string" and resolved ~= "" then
			skinId = resolved
		end
	end
	local success = remoteData.WeaponManager:EquipWeapon(weaponId, skinId)
	return success
end

return RemoteReplicator
