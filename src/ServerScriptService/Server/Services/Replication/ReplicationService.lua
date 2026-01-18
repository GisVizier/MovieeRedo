local ReplicationService = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CompressionUtils = require(Locations.Shared.Util:WaitForChild("CompressionUtils"))
local ReplicationConfig = require(Locations.Global:WaitForChild("Replication"))
local MovementValidator = require(script.Parent.Parent.AntiCheat.MovementValidator)
local HitValidator = require(script.Parent.Parent.AntiCheat.HitValidator)

ReplicationService.PlayerStates = {}
ReplicationService.LastBroadcastTime = 0
ReplicationService._net = nil

function ReplicationService:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Initialize anti-cheat
	MovementValidator:Init()
	HitValidator:Init()

	self._net:ConnectServer("CharacterStateUpdate", function(player, compressedState)
		self:OnClientStateUpdate(player, compressedState)
	end)

	self._net:ConnectServer("RequestInitialStates", function(player)
		self:SendInitialStatesToPlayer(player)
	end)

	local updateRate = ReplicationConfig.UpdateRates.ServerToClients
	if updateRate > 0 then
		local interval = 1 / updateRate
		RunService.Heartbeat:Connect(function()
			local currentTime = tick()
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
end

function ReplicationService:UnregisterPlayer(player)
	self.PlayerStates[player] = nil
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

	-- Anti-cheat validation
	local deltaTime = state.Timestamp - playerData.LastState.Timestamp
	local isValid = MovementValidator:Validate(player, state, deltaTime)

	if not isValid then
		-- Reject invalid state - don't update or broadcast
		return
	end

	-- Valid state - proceed normally
	playerData.LastState = state
	playerData.CachedCompressedState = compressedState
	playerData.LastUpdateTime = tick()

	-- Store position for weapon hit lag compensation
	HitValidator:StorePosition(player, state.Position, state.Timestamp)
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
				self._net:FireAllClients("CharacterStateReplicated", currentBatch)
				currentBatch = {}
				batchCount = 0
			end
		end

		if batchCount > 0 then
			self._net:FireAllClients("CharacterStateReplicated", currentBatch)
		end
	else
		for _, entry in ipairs(batch) do
			self._net:FireAllClients("CharacterStateReplicated", { entry })
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
				0
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
