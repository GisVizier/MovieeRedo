local CharacterService = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))

CharacterService.ActiveCharacters = {}
CharacterService.IsClientSetupComplete = {}
CharacterService.IsSpawningCharacter = {}

function CharacterService:Init(registry, net)
	self._registry = registry
	self._net = net

	Players.CharacterAutoLoads = false

	self:_cacheTemplate()
	self:_ensureEntitiesContainer()
	self:_bindRemotes()

	Players.PlayerRemoving:Connect(function(player)
		self:Unragdoll(player)
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

	-- Ragdoll test toggle (G key)
	self._net:ConnectServer("ToggleRagdollTest", function(player)
		if self:IsRagdolled(player) then
			self:Unragdoll(player)
		else
			-- Ragdoll for 3 seconds with a small upward fling
			self:Ragdoll(player, 3, {
				FlingDirection = Vector3.new(0, 1, 0),
				FlingStrength = 30,
			})
		end
	end)
end

function CharacterService:_ensureEntitiesContainer()
	local container = workspace:FindFirstChild("Entities")
	if not container then
		container = Instance.new("Folder")
		container.Name = "Entities"
		container.Parent = workspace
	end
	self._entitiesContainer = container
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
	character.Parent = self._entitiesContainer or workspace

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

	-- Initialize combat resources for this player
	local combatService = self._registry and self._registry:TryGet("CombatService")
	if combatService then
		combatService:InitializePlayer(player)
	end

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

-- =============================================================================
-- RAGDOLL SYSTEM
-- =============================================================================

--[[
	Simple API for abilities, weapons, and game systems to ragdoll players.
	
	Usage:
		CharacterService:Ragdoll(player, duration)
		CharacterService:Ragdoll(player, duration, { FlingDirection = dir, FlingStrength = 80 })
		CharacterService:Unragdoll(player)
		CharacterService:IsRagdolled(player)
]]

CharacterService.RagdollDurationThreads = {} -- [player] = thread

function CharacterService:IsRagdolled(player)
	local character = self.ActiveCharacters[player]
	return character and character:GetAttribute("RagdollActive") == true
end

--[[
	Ragdolls a player for a specified duration.
	
	@param player Player - The player to ragdoll
	@param duration number? - Seconds before auto-recovery (nil = permanent)
	@param options table? - Optional configuration:
		- FlingDirection: Vector3 - Direction to fling
		- FlingStrength: number - Force of fling (default: 50)
		- Velocity: Vector3 - Direct velocity to apply
	@return boolean - Whether ragdoll started successfully
]]
function CharacterService:Ragdoll(player, duration, options)
	options = options or {}

	-- Already ragdolled?
	if self:IsRagdolled(player) then
		return false
	end

	local character = self.ActiveCharacters[player]
	if not character or not character.Parent then
		return false
	end

	-- Cancel any existing duration thread
	if self.RagdollDurationThreads[player] then
		task.cancel(self.RagdollDurationThreads[player])
		self.RagdollDurationThreads[player] = nil
	end

	-- Set RagdollActive attribute on character (this stops ClientReplicator from moving rig)
	character:SetAttribute("RagdollActive", true)

	-- Build ragdoll data to send to clients
	local ragdollData = {
		FlingDirection = options.FlingDirection,
		FlingStrength = options.FlingStrength or 50,
		Velocity = options.Velocity,
	}

	-- Fire RagdollStarted to all clients - they will ragdoll their local rig
	self._net:FireAllClients("RagdollStarted", player, ragdollData)

	-- Schedule auto-unragdoll if duration provided
	if duration and duration > 0 then
		self.RagdollDurationThreads[player] = task.delay(duration, function()
			self:Unragdoll(player)
		end)
	end

	return true
end

--[[
	Ends ragdoll for a player.
	
	@param player Player - The player to unragdoll
	@return boolean - Whether unragdoll succeeded
]]
function CharacterService:Unragdoll(player)
	if not self:IsRagdolled(player) then
		return false
	end

	-- Cancel duration thread if active (use pcall since thread may have completed)
	if self.RagdollDurationThreads[player] then
		pcall(task.cancel, self.RagdollDurationThreads[player])
		self.RagdollDurationThreads[player] = nil
	end

	local character = self.ActiveCharacters[player]
	if character then
		character:SetAttribute("RagdollActive", false)
	end

	-- Fire RagdollEnded to all clients
	self._net:FireAllClients("RagdollEnded", player)

	return true
end

-- Legacy compatibility
function CharacterService:GetRagdoll(player)
	return nil -- No longer creating ragdoll clones
end

function CharacterService:StartRagdoll(player, options)
	return self:Ragdoll(player, nil, options)
end

function CharacterService:EndRagdoll(player)
	return self:Unragdoll(player)
end

return CharacterService
