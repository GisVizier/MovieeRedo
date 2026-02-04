--[[
	RoundService
	
	Server-side service for managing Training mode.
	Competitive matches are handled by MatchManager.
	
	This service now focuses on:
	- Training mode (infinite respawns, no scoring)
	- Player joins/leaves Training via AreaTeleport gadget
	
	API:
	- RoundService:StartTraining() -> void
	- RoundService:AddPlayer(player) -> boolean
	- RoundService:RemovePlayer(player) -> void
	- RoundService:IsPlayerInTraining(player) -> boolean
	- RoundService:GetTrainingPlayers() -> { player, ... }
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))

local RoundService = {}

function RoundService:Init(registry, net)
	self._registry = registry
	self._net = net

	self._trainingPlayers = {}

	self._trainingConfig = MatchmakingConfig.getMode("Training")

	self:_setupPlayerRemoving()
	self:_setupDeathHandling()
end

function RoundService:Start()
end

function RoundService:StartTraining()
end

function RoundService:AddPlayer(player)
	if not self._trainingConfig then
		return false
	end

	local userId = player.UserId

	if table.find(self._trainingPlayers, userId) then
		return false
	end

	local matchManager = self._registry:TryGet("MatchManager")
	if matchManager and matchManager:GetMatchForPlayer(player) then
		return false
	end

	table.insert(self._trainingPlayers, userId)

	self:_teleportPlayerToTraining(player)

	self._net:FireAllClients("PlayerJoinedTraining", {
		playerId = userId,
	})

	return true
end

function RoundService:RemovePlayer(player)
	local userId = player.UserId

	local index = table.find(self._trainingPlayers, userId)
	if index then
		table.remove(self._trainingPlayers, index)

		self._net:FireAllClients("PlayerLeftTraining", {
			playerId = userId,
		})
	end
end

function RoundService:IsPlayerInTraining(player)
	return table.find(self._trainingPlayers, player.UserId) ~= nil
end

function RoundService:GetTrainingPlayers()
	local players = {}

	for _, userId in self._trainingPlayers do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(players, player)
		end
	end

	return players
end

function RoundService:_setupPlayerRemoving()
	Players.PlayerRemoving:Connect(function(player)
		self:RemovePlayer(player)
	end)
end

function RoundService:_setupDeathHandling()
	self._net:ConnectServer("PlayerDied", function(player)
		if self:IsPlayerInTraining(player) then
			self:_onTrainingPlayerDied(player)
		end
	end)
end

function RoundService:_onTrainingPlayerDied(player)
	local respawnDelay = self._trainingConfig.respawnDelay or 2

	task.delay(respawnDelay, function()
		if player and player.Parent and self:IsPlayerInTraining(player) then
			self:_respawnPlayer(player)
		end
	end)
end

function RoundService:_respawnPlayer(player)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	end

	self:_teleportPlayerToTraining(player)

	self._net:FireClient(player, "PlayerRespawned", {})
end

function RoundService:_teleportPlayerToTraining(player)
	local spawns = CollectionService:GetTagged(MatchmakingConfig.Spawns.TrainingTag)

	if #spawns == 0 then
		warn("[RoundService] No training spawns found")
		return
	end

	local spawn = spawns[math.random(1, #spawns)]
	local character = player.Character

	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function RoundService:GetActiveMatch()
	return nil
end

function RoundService:GetScores()
	return nil
end

function RoundService:GetPlayers()
	return self:GetTrainingPlayers()
end

function RoundService:GetMode()
	return "Training"
end

function RoundService:IsPlayerInMatch(player)
	if self:IsPlayerInTraining(player) then
		return true
	end

	local matchManager = self._registry:TryGet("MatchManager")
	if matchManager then
		return matchManager:GetMatchForPlayer(player) ~= nil
	end

	return false
end

return RoundService
