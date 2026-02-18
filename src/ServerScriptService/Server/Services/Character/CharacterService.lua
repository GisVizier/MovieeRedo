local CharacterService = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local RagdollModule = require(ReplicatedStorage:WaitForChild("Ragdoll"):WaitForChild("Ragdoll"))
local RagdollSystem = require(
	ReplicatedStorage:WaitForChild("Game"):WaitForChild("Character"):WaitForChild("Rig"):WaitForChild("RagdollSystem")
)

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

--[[
	Fires an event to all players in the same match context as the source player.
	Falls back to FireAllClients if no match context is found.
]]
function CharacterService:_fireMatchScoped(sourcePlayer, eventName, ...)
	if not self._net then return end
	
	local matchManager = self._registry:TryGet("MatchManager")
	if matchManager and sourcePlayer then
		local recipients = matchManager:GetPlayersInMatch(sourcePlayer)
		if recipients and #recipients > 0 then
			for _, player in recipients do
				self._net:FireClient(eventName, player, ...)
			end
			return
		end
	end
	
	-- Fallback: fire to all clients (lobby/unknown context)
	self._net:FireAllClients(eventName, ...)
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

function CharacterService:SpawnCharacter(player, options)
	options = options or {}

	if not self._template then
		self:_cacheTemplate()
	end

	if self.IsSpawningCharacter[player.UserId] then
		return nil
	end
	self.IsSpawningCharacter[player.UserId] = true

	-- Clean up any active ragdoll before removing the character
	self:Unragdoll(player)

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

	local spawnPosition = options.spawnPosition or self:_getSpawnPosition()
	if character.PrimaryPart then
		character:PivotTo(CFrame.new(spawnPosition))
	end

	local headOffset = templateRootPart.CFrame:ToObjectSpace(templateHead.CFrame)
	head.CFrame = humanoidRootPart.CFrame * headOffset

	self.ActiveCharacters[player] = character
	self.IsClientSetupComplete[player.UserId] = false

	-- Set player state to Lobby unless preserveState is set (mid-match respawn)
	if not options.preserveState then
		player:SetAttribute("PlayerState", "Lobby")
	end

	-- Initialize combat resources for this player
	local combatService = self._registry and self._registry:TryGet("CombatService")
	if combatService then
		combatService:InitializePlayer(player)
	end

	local replicationService = self._registry and self._registry:TryGet("ReplicationService")
	if replicationService and replicationService.RegisterPlayer then
		replicationService:RegisterPlayer(player)
	end

	self:_fireMatchScoped(player, "CharacterSpawned", character)

	self.IsSpawningCharacter[player.UserId] = nil
	return character
end

function CharacterService:RemoveCharacter(player)
	local character = self.ActiveCharacters[player]
	if not character then
		return
	end

	self:_fireMatchScoped(player, "CharacterRemoving", character)

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
	-- Look for tagged lobby spawns first
	local lobbySpawns = CollectionService:GetTagged("LobbySpawn")
	if #lobbySpawns > 0 then
		local spawn = lobbySpawns[math.random(1, #lobbySpawns)]
		if spawn:IsA("BasePart") then
			-- Random position within spawn bounds
			local size = spawn.Size
			local offset = Vector3.new(
				(math.random() - 0.5) * size.X,
				3, -- Height above spawn
				(math.random() - 0.5) * size.Z
			)
			return spawn.Position + offset
		else
			return spawn.Position + Vector3.new(0, 3, 0)
		end
	end

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

	-- Fallback: search for any SpawnLocation in workspace
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			return descendant.Position + Vector3.new(0, 3, 0)
		end
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

	-- Notify match players so CharacterController can switch camera to third-person
	if self._net then
		self:_fireMatchScoped(player, "RagdollStarted", player, {
			Velocity = knockbackForce,
		})
	end

	return true
end

function CharacterService:RagdollCharacter(character, duration, options)
	options = options or {}

	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return false
	end

	local rig = character:FindFirstChild("Rig")
	if not rig then
		rig = character:FindFirstChild("Rig", true)
	end
	if not rig or not (rig:IsA("Model") or rig:IsA("Folder")) then
		return false
	end

	if RagdollSystem:IsRagdolled(rig) then
		return false
	end

	local characterRoot = character:FindFirstChild("Root")
	if characterRoot then
		characterRoot.CanCollide = false
		characterRoot.CanQuery = false
		characterRoot.CanTouch = false
		for _, descendant in ipairs(characterRoot:GetDescendants()) do
			if descendant:IsA("AlignOrientation") or descendant:IsA("VectorForce") then
				descendant.Enabled = false
			end
		end
	end

	local rigRoot = rig:FindFirstChild("HumanoidRootPart", true)
	if not rigRoot or not rigRoot:IsA("BasePart") then
		return false
	end

	if characterRoot then
		-- Ensure the non-ragdoll body shell cannot pin the visual rig.
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") and not descendant:IsDescendantOf(rig) then
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.AssemblyLinearVelocity = Vector3.zero
				descendant.AssemblyAngularVelocity = Vector3.zero
			end
		end

		-- Break any direct joints that could keep rig bound to Root.
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("WeldConstraint") then
				if
					(descendant.Part0 == characterRoot and descendant.Part1 == rigRoot)
					or (descendant.Part0 == rigRoot and descendant.Part1 == characterRoot)
				then
					descendant:Destroy()
				end
			elseif descendant:IsA("Motor6D") then
				if
					(descendant.Part0 == characterRoot and descendant.Part1 == rigRoot)
					or (descendant.Part0 == rigRoot and descendant.Part1 == characterRoot)
				then
					descendant:Destroy()
				end
			elseif descendant:IsA("Weld") then
				if
					(descendant.Part0 == characterRoot and descendant.Part1 == rigRoot)
					or (descendant.Part0 == rigRoot and descendant.Part1 == characterRoot)
				then
					descendant:Destroy()
				end
			end
		end
	end

	local ragdollOptions = {}
	for key, value in pairs(options) do
		ragdollOptions[key] = value
	end
	ragdollOptions.Character = character

	local started = RagdollSystem:RagdollRig(rig, ragdollOptions)
	if not started then
		return false
	end

	character:SetAttribute("KillEffectRagdollActive", true)

	if duration and duration > 0 then
		task.delay(duration, function()
			if not rig or not rig.Parent then
				return
			end

			if RagdollSystem:IsRagdolled(rig) then
				RagdollSystem:UnragdollRig(rig)
			end

			if character and character.Parent then
				character:SetAttribute("KillEffectRagdollActive", false)
			end
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

	RagdollModule.GetBackUp(player)

	-- Notify match players so CharacterController can restore camera mode
	if self._net then
		self:_fireMatchScoped(player, "RagdollEnded", player)
	end

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
