local CharacterService = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

CharacterService.ActiveCharacters = {}
CharacterService.IsClientSetupComplete = {}
CharacterService.IsSpawningCharacter = {}

function CharacterService:Init(registry, net)
	self._registry = registry
	self._net = net

	Players.CharacterAutoLoads = false

	self:_cacheTemplate()
	self:_bindRemotes()

	Players.PlayerRemoving:Connect(function(player)
		self:RemoveCharacter(player)
	end)
end

function CharacterService:Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			task.wait(0.5)
			self._net:FireClient("ServerReady", player)
		end)

		self:_sendExistingCharacters(player)
	end)
end

function CharacterService:_cacheTemplate()
	local modelsFolder = ServerStorage:FindFirstChild("Models")
	if not modelsFolder then
		error("ServerStorage.Models folder missing")
	end

	self._template = modelsFolder:FindFirstChild("Character")
	if not self._template then
		error("ServerStorage.Models.Character template missing")
	end
end

function CharacterService:_bindRemotes()
	self._net:ConnectServer("RequestCharacterSpawn", function(player)
		self:SpawnCharacter(player)
	end)

	self._net:ConnectServer("RequestRespawn", function(player)
		if self.IsSpawningCharacter[player.UserId] then
			return
		end

		if not self.IsClientSetupComplete[player.UserId] then
			return
		end

		self:SpawnCharacter(player)
	end)

	self._net:ConnectServer("CharacterSetupComplete", function(player)
		self.IsClientSetupComplete[player.UserId] = true
	end)

	self._net:ConnectServer("CrouchStateChanged", function(player, isCrouching)
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				self._net:FireClient("CrouchStateChanged", otherPlayer, player, isCrouching)
			end
		end
	end)
end

function CharacterService:_sendExistingCharacters(player)
	for otherPlayer, character in pairs(self.ActiveCharacters) do
		if otherPlayer ~= player and character and character.Parent then
			self._net:FireClient("CharacterSpawned", player, character)
		end
	end
end

function CharacterService:SpawnCharacter(player)
	if not self._template then
		self:_cacheTemplate()
	end

	if self.IsSpawningCharacter[player.UserId] then
		return nil
	end
	self.IsSpawningCharacter[player.UserId] = true

	self:RemoveCharacter(player)

	local character = Instance.new("Model")
	character.Name = player.Name
	character.Parent = workspace

	local templateHumanoid = self._template:FindFirstChildOfClass("Humanoid")
	local templateRootPart = self._template:FindFirstChild("HumanoidRootPart")
	local templateHead = self._template:FindFirstChild("Head")

	if not templateHumanoid or not templateRootPart or not templateHead then
		self.IsSpawningCharacter[player.UserId] = nil
		error("Character template missing Humanoid/HRP/Head")
	end

	local humanoid = templateHumanoid:Clone()
	local humanoidRootPart = templateRootPart:Clone()
	local head = templateHead:Clone()

	humanoid.Parent = character
	humanoidRootPart.Parent = character
	head.Parent = character

	humanoidRootPart.Anchored = true
	humanoidRootPart.CanCollide = false
	head.Anchored = true
	head.CanCollide = false

	character.PrimaryPart = humanoidRootPart

	player.Character = character

	local spawnPosition = self:_getSpawnPosition()
	if character.PrimaryPart then
		character:PivotTo(CFrame.new(spawnPosition))
	end

	local headOffset = templateRootPart.CFrame:ToObjectSpace(templateHead.CFrame)
	head.CFrame = humanoidRootPart.CFrame * headOffset

	self.ActiveCharacters[player] = character
	self.IsClientSetupComplete[player.UserId] = false

	local replicationService = self._registry and self._registry:TryGet("ReplicationService")
	if replicationService and replicationService.RegisterPlayer then
		replicationService:RegisterPlayer(player)
	end

	self._net:FireAllClients("CharacterSpawned", character)

	self.IsSpawningCharacter[player.UserId] = nil
	return character
end

function CharacterService:RemoveCharacter(player)
	local character = self.ActiveCharacters[player]
	if not character then
		return
	end

	self._net:FireAllClients("CharacterRemoving", character)

	local replicationService = self._registry and self._registry:TryGet("ReplicationService")
	if replicationService and replicationService.UnregisterPlayer then
		replicationService:UnregisterPlayer(player)
	end

	if player.Character == character then
		player.Character = nil
	end

	character:Destroy()
	self.ActiveCharacters[player] = nil
	self.IsClientSetupComplete[player.UserId] = nil
	self.IsSpawningCharacter[player.UserId] = nil
end

function CharacterService:_getSpawnPosition()
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		return spawnLocation.Position + Vector3.new(0, 3, 0)
	end

	return Vector3.new(0, 5, 0)
end

return CharacterService
