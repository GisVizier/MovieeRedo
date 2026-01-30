local CharacterService = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local RagdollModule = require(ReplicatedStorage:WaitForChild("Ragdoll"):WaitForChild("Ragdoll"))

CharacterService.ActiveCharacters = {}
CharacterService.IsClientSetupComplete = {}
CharacterService.IsSpawningCharacter = {}

-- Register collision groups for ragdoll system
local function setupCollisionGroups()
	-- Register Ragdolls group
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Ragdolls")
	end)

	-- Ragdolls should not collide with Players (character physics body)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable("Ragdolls", "Players", false)
		PhysicsService:CollisionGroupSetCollidable("Ragdolls", "Default", true)
	end)
end

function CharacterService:Init(registry, net)
	self._registry = registry
	self._net = net

	Players.CharacterAutoLoads = false

	-- Setup collision groups for ragdoll system (must be done on server)
	setupCollisionGroups()

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

	-- Handle players who are already connected (Studio testing)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			task.wait(0.5)
			self._net:FireClient("ServerReady", player)
		end)
	end
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
			-- Ragdoll for 3 seconds with a noticeable upward fling
			self:Ragdoll(player, 3, {
				Velocity = Vector3.new(0, 60, 0), -- Direct velocity for reliable upward launch
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

	-- Set player state to Lobby (will be changed when match starts)
	player:SetAttribute("PlayerState", "Lobby")

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
<<<<<<< HEAD
	-- Primary: Use World/Spawn part
	local world = workspace:FindFirstChild("World")
	if world then
		local spawnPart = world:FindFirstChild("Spawn")
		if spawnPart and spawnPart:IsA("BasePart") then
			local size = spawnPart.Size
			local offset = Vector3.new(
				(math.random() - 0.5) * size.X,
				3, -- Height above spawn
				(math.random() - 0.5) * size.Z
			)
			return spawnPart.Position + offset
		end
	end

	-- Fallback: SpawnLocation
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		return spawnLocation.Position + Vector3.new(0, 3, 0)
=======
	-- Look for tagged lobby spawns first
	local lobbySpawns = CollectionService:GetTagged("LobbySpawn")
	if #lobbySpawns > 0 then
		local spawn = lobbySpawns[math.random(1, #lobbySpawns)]
		return spawn.Position + Vector3.new(0, 3, 0)
	end

	-- Fallback: search for any SpawnLocation in workspace
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			return descendant.Position + Vector3.new(0, 3, 0)
		end
>>>>>>> 6e4120d (emote + lobby fix)
	end

	return Vector3.new(0, 5, 0)
end

-- =============================================================================
-- RAGDOLL SYSTEM (uses RagdollModule)
-- =============================================================================

--[[
	Simple API for abilities, weapons, and game systems to ragdoll players.
	
	Usage:
		CharacterService:Ragdoll(player, duration)
		CharacterService:Ragdoll(player, duration, { FlingDirection = dir, FlingStrength = 80 })
		CharacterService:Unragdoll(player)
		CharacterService:IsRagdolled(player)
]]

function CharacterService:IsRagdolled(player)
	return RagdollModule.IsRagdolled(player)
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

	-- Build knockback force from options
	local knockbackForce = nil
	if options.Velocity then
		knockbackForce = options.Velocity
	elseif options.FlingDirection then
		local strength = options.FlingStrength or 50
		knockbackForce = options.FlingDirection.Unit * strength
	end

	-- Use the RagdollModule
	RagdollModule.Ragdoll(player, knockbackForce, duration)
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

	RagdollModule.GetBackUp(player)
	return true
end

-- Legacy compatibility
function CharacterService:GetRagdoll(player)
	return RagdollModule.GetRig(player)
end

function CharacterService:StartRagdoll(player, options)
	return self:Ragdoll(player, nil, options)
end

function CharacterService:EndRagdoll(player)
	return self:Unragdoll(player)
end

return CharacterService
