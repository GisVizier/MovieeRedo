local ReplicationService = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CompressionUtils = require(Locations.Shared.Util:WaitForChild("CompressionUtils"))
local ReplicationConfig = require(Locations.Global:WaitForChild("Replication"))
local MovementValidator = require(script.Parent.Parent.AntiCheat.MovementValidator)
local HitValidator = require(script.Parent.Parent.AntiCheat.HitValidator)
local function vmLog(...) end

-- Stance enum (must match PositionHistory.Stance)
local Stance = {
	Standing = 0,
	Crouched = 1,
	Sliding = 2,
}

ReplicationService.PlayerStates = {}
ReplicationService.PlayerStances = {} -- [player] = stance enum
ReplicationService.PlayerViewmodelActionSeq = {} -- [player] = latest action sequence number
ReplicationService.PlayerActiveViewmodelActions = {} -- [player] = { [key] = payload }
ReplicationService.ReadyPlayers = {} -- [player] = true when client ready to receive replication
ReplicationService.LastBroadcastTime = 0
ReplicationService._net = nil

local function isStatefulViewmodelAction(actionName: string): boolean
	return actionName == "ADS"
		or actionName == "PlayWeaponTrack"
		or actionName == "PlayAnimation"
		or actionName == "SetTrackSpeed"
end

local function getViewmodelActionStateKey(weaponId: string, actionName: string, trackName: string): string
	return string.format("%s|%s|%s", tostring(actionName), tostring(weaponId), tostring(trackName))
end

function ReplicationService:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Initialize anti-cheat
	-- MovementValidator:Init() -- DISABLED - too aggressive for slide/jump mechanics
	-- HitValidator:Init() -- Now initialized in WeaponService

	self._net:ConnectServer("CharacterStateUpdate", function(player, compressedState)
		self:OnClientStateUpdate(player, compressedState)
	end)

	self._net:ConnectServer("ViewmodelActionUpdate", function(player, compressedAction)
		self:OnViewmodelActionUpdate(player, compressedAction)
	end)

	self._net:ConnectServer("RequestInitialStates", function(player)
		self:SendInitialStatesToPlayer(player)
	end)

	-- Track crouch state changes for hit detection stance validation
	self._net:ConnectServer("CrouchStateChanged", function(player, isCrouching)
		self:OnCrouchStateChanged(player, isCrouching)
	end)

	-- Client signals ready to receive replication events
	self._net:ConnectServer("ClientReplicationReady", function(player)
		self.ReadyPlayers[player] = true
		self:SendViewmodelActionSnapshotToPlayer(player)
	end)

	-- Cleanup on player leaving
	game.Players.PlayerRemoving:Connect(function(player)
		self.ReadyPlayers[player] = nil
		self.PlayerViewmodelActionSeq[player] = nil
		self.PlayerActiveViewmodelActions[player] = nil
	end)

	local updateRate = ReplicationConfig.UpdateRates.ServerToClients

	if updateRate > 0 then
		local interval = 1 / updateRate
		RunService.Heartbeat:Connect(function()
			local currentTime = tick()

			-- Broadcast character states
			if currentTime - self.LastBroadcastTime >= interval then
				self:BroadcastStates()
				self.LastBroadcastTime = currentTime
			end
		end)
	end
end

function ReplicationService:Start()
	-- No-op for now.
end

function ReplicationService:RegisterPlayer(player)
	self.PlayerStates[player] = {
		LastState = nil,
		CachedCompressedState = nil,
		LastUpdateTime = tick(),
	}
	self.PlayerStances[player] = Stance.Standing
	self.PlayerActiveViewmodelActions[player] = {}
end

function ReplicationService:UnregisterPlayer(player)
	self.PlayerStates[player] = nil
	self.PlayerStances[player] = nil
	self.PlayerViewmodelActionSeq[player] = nil
	self.PlayerActiveViewmodelActions[player] = nil
end

function ReplicationService:_updateActiveViewmodelState(player, weaponId, actionName, trackName, isActive, sequenceNumber, timestamp)
	if not player then
		return
	end

	local stateMap = self.PlayerActiveViewmodelActions[player]
	if not stateMap then
		stateMap = {}
		self.PlayerActiveViewmodelActions[player] = stateMap
	end

	if actionName == "Equip" or actionName == "Unequip" then
		table.clear(stateMap)
		return
	end

	if not isStatefulViewmodelAction(actionName) then
		return
	end

	local key = getViewmodelActionStateKey(weaponId, actionName, trackName)
	if isActive then
		stateMap[key] = {
			PlayerUserId = player.UserId,
			WeaponId = weaponId,
			ActionName = actionName,
			TrackName = trackName,
			IsActive = true,
			SequenceNumber = sequenceNumber,
			Timestamp = timestamp,
		}
	else
		stateMap[key] = nil
	end
end

function ReplicationService:OnCrouchStateChanged(player, isCrouching)
	-- Update stance tracking
	local newStance = isCrouching and Stance.Crouched or Stance.Standing
	self.PlayerStances[player] = newStance

	-- Notify HitValidator of stance change
	HitValidator:SetPlayerStance(player, newStance)
end

function ReplicationService:OnClientStateUpdate(player, compressedState)
	local state = CompressionUtils:DecompressState(compressedState)
	if not state then
		return
	end

	local playerData = self.PlayerStates[player]
	if not playerData then
		-- First state from this player, initialize
		playerData = {
			LastState = state,
			CachedCompressedState = compressedState,
			LastUpdateTime = tick(),
		}
		self.PlayerStates[player] = playerData
		return
	end

	-- Check if this is the first state update (LastState is nil)
	if not playerData.LastState then
		playerData.LastState = state
		playerData.CachedCompressedState = compressedState
		playerData.LastUpdateTime = tick()
		return
	end

	-- Anti-cheat validation (DISABLED - too aggressive)
	-- local deltaTime = state.Timestamp - playerData.LastState.Timestamp
	-- local isValid = MovementValidator:Validate(player, state, deltaTime)
	--
	-- if not isValid then
	-- 	-- Reject invalid state - don't update or broadcast
	-- 	return
	-- end

	-- Valid state - proceed normally
	playerData.LastState = state
	playerData.CachedCompressedState = compressedState
	playerData.LastUpdateTime = tick()

	-- Store position for weapon hit lag compensation (with current stance)
	local currentStance = self.PlayerStances[player] or Stance.Standing
	HitValidator:StorePosition(player, state.Position, state.Timestamp, currentStance)
end

function ReplicationService:OnViewmodelActionUpdate(player, compressedAction)
	local payload = CompressionUtils:DecompressViewmodelAction(compressedAction)
	if not payload then
		vmLog("Drop: failed decompress", player and player.Name or "?")
		return
	end

	local weaponId = tostring(payload.WeaponId or "")
	local actionName = tostring(payload.ActionName or "")
	local trackName = tostring(payload.TrackName or "")
	local isActive = payload.IsActive == true
	local sequenceNumber = tonumber(payload.SequenceNumber) or 0
	local timestamp = tonumber(payload.Timestamp) or workspace:GetServerTimeNow()

	if actionName == "" then
		vmLog("Drop: empty action", player.Name)
		return
	end
	if weaponId == "" and actionName ~= "Unequip" then
		vmLog("Drop: empty weapon for non-unequip", player.Name, actionName)
		return
	end

	if #weaponId > 32 or #actionName > 32 or #trackName > 32 then
		vmLog("Drop: field too long", player.Name, weaponId, actionName, trackName)
		return
	end

	local lastSeq = self.PlayerViewmodelActionSeq[player]
	if lastSeq ~= nil then
		local gap = sequenceNumber >= lastSeq and (sequenceNumber - lastSeq) or ((65536 - lastSeq) + sequenceNumber)
		if gap == 0 then
			vmLog("Drop: duplicate seq", player.Name, sequenceNumber)
			return
		end
		if gap > 32768 then
			vmLog("Drop: old seq", player.Name, "seq=", sequenceNumber, "last=", lastSeq)
			return
		end
	end
	self.PlayerViewmodelActionSeq[player] = sequenceNumber
	self:_updateActiveViewmodelState(player, weaponId, actionName, trackName, isActive, sequenceNumber, timestamp)

	local replicated = CompressionUtils:CompressViewmodelAction(
		player.UserId,
		weaponId,
		actionName,
		trackName,
		isActive,
		sequenceNumber,
		timestamp
	)

	if replicated then
		vmLog("Relay", player.Name, "weapon=", weaponId, "action=", actionName, "track=", trackName, "active=", tostring(isActive))
		self:_fireToReadyClientsExcept(player, "ViewmodelActionReplicated", replicated)
	end
end

function ReplicationService:SendViewmodelActionSnapshotToPlayer(targetPlayer)
	if not targetPlayer or not targetPlayer.Parent then
		return
	end

	local snapshot = {}
	for sourcePlayer, stateMap in pairs(self.PlayerActiveViewmodelActions) do
		if sourcePlayer ~= targetPlayer and sourcePlayer.Parent and type(stateMap) == "table" then
			for _, payload in pairs(stateMap) do
				if type(payload) == "table" and payload.IsActive == true then
					table.insert(snapshot, payload)
				end
			end
		end
	end

	self._net:FireClient("ViewmodelActionSnapshot", targetPlayer, snapshot)
end

-- Helper to send to only ready players (avoids race condition on join)
function ReplicationService:_fireToReadyClients(eventName, data)
	for player in pairs(self.ReadyPlayers) do
		if player.Parent then
			self._net:FireClient(eventName, player, data)
		end
	end
end

function ReplicationService:_fireToReadyClientsExcept(excludedPlayer, eventName, data)
	for player in pairs(self.ReadyPlayers) do
		if player.Parent and player ~= excludedPlayer then
			self._net:FireClient(eventName, player, data)
		end
	end
end

function ReplicationService:BroadcastStates()
	local batch = {}

	for player, playerData in pairs(self.PlayerStates) do
		if player.Parent and playerData.CachedCompressedState then
			table.insert(batch, {
				UserId = player.UserId,
				State = playerData.CachedCompressedState,
			})
		end
	end

	if #batch == 0 then
		return
	end

	local optimization = ReplicationConfig.Optimization
	if optimization.EnableBatching then
		local currentBatch = {}
		local batchCount = 0

		for _, entry in ipairs(batch) do
			table.insert(currentBatch, entry)
			batchCount += 1

			if batchCount >= optimization.MaxBatchSize then
				self:_fireToReadyClients("CharacterStateReplicated", currentBatch)
				currentBatch = {}
				batchCount = 0
			end
		end

		if batchCount > 0 then
			self:_fireToReadyClients("CharacterStateReplicated", currentBatch)
		end
	else
		for _, entry in ipairs(batch) do
			self:_fireToReadyClients("CharacterStateReplicated", { entry })
		end
	end
end

function ReplicationService:SendInitialStatesToPlayer(newPlayer)
	local initialStates = {}

	for otherPlayer, playerData in pairs(self.PlayerStates) do
		if otherPlayer ~= newPlayer and playerData.LastState then
			local state = playerData.LastState
			local compressedState = CompressionUtils:CompressState(
				state.Position,
				state.Rotation,
				state.Velocity,
				state.Timestamp,
				state.IsGrounded or false,
				state.AnimationId or 1,
				state.RigTilt or 0,
				0,
				state.AimPitch or 0
			)

			if compressedState then
				table.insert(initialStates, {
					UserId = otherPlayer.UserId,
					State = compressedState,
				})
			end
		end
	end

	if #initialStates > 0 then
		self._net:FireClient("CharacterStateReplicated", newPlayer, initialStates)
	end
end

return ReplicationService
