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

--[[
	Returns training players in the same area as the given player.
	Used for match-scoped replication to isolate training areas.
	
	Edge case: if player has CurrentArea = nil, returns only players
	who also have CurrentArea = nil (solo scope / same nil bucket).
	
	@param player Player - the reference player
	@return { Player, ... } - players in the same training area
]]
function RoundService:GetPlayersInSameArea(player)
	if not self:IsPlayerInTraining(player) then
		return {}
	end

	local areaId = player:GetAttribute("CurrentArea")
	local result = {}

	for _, userId in self._trainingPlayers do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			local pArea = p:GetAttribute("CurrentArea")
			-- Match if both have same area (including both nil)
			if pArea == areaId then
				table.insert(result, p)
			end
		end
	end

	return result
end

function RoundService:_setupPlayerRemoving()
	Players.PlayerRemoving:Connect(function(player)
		self:RemovePlayer(player)
	end)
end

function RoundService:_setupDeathHandling()
	-- Death is now handled server-side by CombatService._handleDeath(),
	-- which checks IsPlayerInTraining() and calls RespawnInTraining().
	-- The old "PlayerDied" client remote was never fired, so we no longer rely on it.
end

--[[
	Public method called by CombatService after spawning a new character
	for a training player. Teleports to a training spawn and notifies the client.
	@param player Player
]]
function RoundService:RespawnInTraining(player)
	if not self:IsPlayerInTraining(player) then
		return
	end

	self:_teleportPlayerToTraining(player)
	self._net:FireClient(player, "PlayerRespawned", {})
end

function RoundService:_teleportPlayerToTraining(player)
	local spawns = CollectionService:GetTagged(MatchmakingConfig.Spawns.TrainingTag)

	if #spawns == 0 then
		return
	end

	local spawn = spawns[math.random(1, #spawns)]
	local character = player.Character

	if character then
		character:PivotTo(spawn.CFrame + Vector3.new(0, 3, 0))

		-- Clear velocity on both HumanoidRootPart and Root (the actual physics body)
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end

		local physicsRoot = character:FindFirstChild("Root")
		if physicsRoot then
			physicsRoot.AssemblyLinearVelocity = Vector3.zero
			physicsRoot.AssemblyAngularVelocity = Vector3.zero
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
