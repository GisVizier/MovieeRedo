local CharacterService = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local CrouchUtils = require(Locations.Modules.Systems.Character.CrouchUtils)
local Config = require(Locations.Modules.Config)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
local PartUtils = require(Locations.Modules.Utils.PartUtils)

-- Cache frequently accessed objects
local characterTemplate = nil
local garbageCollector = nil

-- State
CharacterService.ActiveCharacters = {}
CharacterService.IsSpawningCharacter = {} -- Track if a character is currently being spawned for a player
CharacterService.IsClientSetupComplete = {} -- Track if client has completed character setup

function CharacterService:Init()
	Log:RegisterCategory("CHARACTER", "Player character spawning and management")

	-- Cache character template for performance
	characterTemplate = ServerStorage.Models:WaitForChild("Character")
	-- Get garbage collector service safely
	if _G.Services and _G.Services.GarbageCollectorService then
		garbageCollector = _G.Services.GarbageCollectorService
	end

	RemoteEvents:ConnectServer("RequestCharacterSpawn", function(player)
		Log:Debug("CHARACTER", "Spawn request received", { Player = player.Name })
		self:SpawnCharacter(player)
	end)

	RemoteEvents:ConnectServer("RequestRespawn", function(player)
		-- Prevent respawn spam by checking if a spawn is already in progress
		if self.IsSpawningCharacter[player.UserId] then
			Log:Warn("CHARACTER", "Respawn request rejected - spawn already in progress", {
				Player = player.Name,
			})
			return
		end

		-- Prevent respawn if client hasn't completed setup of current character
		if not self.IsClientSetupComplete[player.UserId] then
			Log:Warn("CHARACTER", "Respawn request rejected - client setup not complete", {
				Player = player.Name,
			})
			return
		end

		Log:Debug("CHARACTER", "Respawn request received", { Player = player.Name })
		self:SpawnCharacter(player)
	end)

	RemoteEvents:ConnectServer("CharacterSetupComplete", function(player)
		self.IsClientSetupComplete[player.UserId] = true
		Log:Debug("CHARACTER", "Client setup complete", { Player = player.Name })

		-- Sync initial health to the client now that their character is fully built
		-- This ensures the client's Humanoid exists after they rebuild the character
		local character = self:GetCharacter(player)
		if character then
			local humanoid = CharacterLocations:GetHumanoidInstance(character)
			if humanoid then
				-- Send to this specific client (they just finished setup)
				RemoteEvents:FireClient("PlayerHealthChanged", player, {
					Player = player,
					Health = humanoid.Health,
					MaxHealth = humanoid.MaxHealth,
					Damage = 0,
					Attacker = nil,
					Headshot = false,
				})
				Log:Debug("CHARACTER", "Initial health synced after client setup", {
					Player = player.Name,
					Health = humanoid.Health,
					MaxHealth = humanoid.MaxHealth,
				})
			end
		end
	end)

	-- Handle player death notification from client
	RemoteEvents:ConnectServer("PlayerDied", function(player, deathData)
		self:OnPlayerDeath(player, deathData)
	end)

	-- Handle ragdoll replication to other clients (P2P ragdoll sync)
	RemoteEvents:ConnectServer("PlayerRagdolled", function(player, ragdollData)
		local Players = game:GetService("Players")
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				RemoteEvents:FireClient("PlayerRagdolled", otherPlayer, player, ragdollData)
			end
		end
	end)

	-- TEMPORARY: Handle crouch state replication for visual sync (remove when real player rigs added)
	RemoteEvents:ConnectServer("CrouchStateChanged", function(player, isCrouching)
		local character = self:GetCharacter(player)
		if not character then
			return
		end

		-- Update server-side crouch state tracking
		if CrouchUtils.CharacterCrouchState[character] then
			CrouchUtils.CharacterCrouchState[character].IsCrouched = isCrouching
		else
			-- Initialize crouch state if it doesn't exist
			CrouchUtils.CharacterCrouchState[character] = {
				IsCrouched = isCrouching,
			}
		end

		-- Fire to all OTHER clients (excluding the sender) so they can see the crouch state
		-- The sender already has their own client-side visuals applied immediately
		local Players = game:GetService("Players")
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				RemoteEvents:FireClient("CrouchStateChanged", otherPlayer, player, isCrouching)
			end
		end
	end)

	Log:Debug("CHARACTER", "CharacterService initialized")
end

function CharacterService:SpawnCharacter(player)
	if not characterTemplate then
		Log:Error("CHARACTER", "Character template not found", { Player = player.Name })
		return nil
	end

	-- Mark that we're spawning a character for this player
	self.IsSpawningCharacter[player.UserId] = true

	-- Reset client setup completion flag (new spawn means new setup required)
	self.IsClientSetupComplete[player.UserId] = false

	-- Only remove existing character if it exists and is valid
	local existingCharacter = self.ActiveCharacters[player]
	if existingCharacter and existingCharacter.Parent then
		Log:Debug("CHARACTER", "Removing existing character before spawn", { Player = player.Name })
		self:RemoveCharacter(player)

		-- Wait a frame to ensure cleanup completes before spawning
		task.wait()
	end

	-- Create server-side character (Humanoid parts ONLY for voice chat)
	local characterModel = Instance.new("Model")
	characterModel.Name = player.Name

	-- Clone Humanoid parts from template (Humanoid, HumanoidRootPart, Head)
	local templateHumanoid = characterTemplate:FindFirstChildOfClass("Humanoid")
	local templateHumanoidRootPart = characterTemplate:FindFirstChild("HumanoidRootPart")
	local templateHead = characterTemplate:FindFirstChild("Head")

	if not templateHumanoid or not templateHumanoidRootPart or not templateHead then
		Log:Error("CHARACTER", "Humanoid parts not found in template", { Player = player.Name })
		return nil
	end

	-- Clone parts directly into character model
	local humanoid = templateHumanoid:Clone()
	local humanoidRootPart = templateHumanoidRootPart:Clone()
	local head = templateHead:Clone()

	humanoid.Parent = characterModel
	humanoidRootPart.Parent = characterModel
	head.Parent = characterModel

	-- ANCHOR all Humanoid parts (server has no physics, only position updates from client)
	humanoidRootPart.Anchored = true
	humanoidRootPart.CanCollide = false
	head.Anchored = true
	head.CanCollide = false

	-- Set PrimaryPart to HumanoidRootPart
	characterModel.PrimaryPart = humanoidRootPart

	characterModel.Parent = workspace

	-- CRITICAL FOR ROBLOX RECOGNITION (voice chat)
	player.Character = characterModel

	Log:Debug("CHARACTER", "Spawned minimal Humanoid model (server)", { Player = player.Name })

	-- Get spawn position from round system or default to lobby
	local spawnPosition = self:GetSpawnPosition()

	-- Position Humanoid model at spawn (simple CFrame - parts are anchored)
	humanoidRootPart.CFrame = CFrame.new(spawnPosition)

	-- Position Head using the template's original offset (preserves relative position from template)
	local originalOffset = templateHumanoidRootPart.CFrame:ToObjectSpace(templateHead.CFrame)
	head.CFrame = humanoidRootPart.CFrame * originalOffset

	self.ActiveCharacters[player] = characterModel

	-- Setup garbage collection tracking
	if garbageCollector then
		local trackingId = garbageCollector:TrackObject(characterModel, "Player_" .. player.Name, function()
			self:CleanupPlayerData(player)
		end)
		characterModel:SetAttribute("GCTrackingId", trackingId)
	end

	-- Register player with ServerReplicator for custom replication
	local serverReplicator = ServiceRegistry:GetService("ServerReplicator")
	if serverReplicator then
		serverReplicator:RegisterPlayer(player)
	end

	self:SetupHumanoid(characterModel, player)
	self:SetupCharacterAttributes(characterModel, player)

	RemoteEvents:FireAllClients("CharacterSpawned", characterModel)

	self.IsSpawningCharacter[player.UserId] = false

	Log:Info("CHARACTER", "Character spawned", { Player = player.Name, Position = characterModel.PrimaryPart.Position })
	return characterModel
end

function CharacterService:SetupCharacterAttributes(characterModel, player)
	characterModel:SetAttribute("PlayerUserId", player.UserId)
	characterModel:SetAttribute("SpawnTime", tick())
	characterModel:SetAttribute("IsPlayerCharacter", true)
	
	local humanoid = CharacterLocations:GetHumanoidInstance(characterModel)
	if humanoid then
		humanoid:SetAttribute("MaxHealth", humanoid.MaxHealth)
		humanoid:SetAttribute("Health", humanoid.Health)
	end
	
	Log:Debug("CHARACTER", "Character attributes set", { Player = player.Name })
end

function CharacterService:RemoveCharacter(player)
	local character = self.ActiveCharacters[player]

	if character then
		Log:Info("CHARACTER", "Removing character", { Player = player.Name })

		-- Fire to ALL clients so they can cleanup visual parts for this character
		-- CRITICAL: Fire BEFORE destroying so clients can properly cleanup references
		RemoteEvents:FireAllClients("CharacterRemoving", character)

		-- Wait briefly for clients to process the removal event
		task.wait(0.1)

		-- Unregister from ServerReplicator
		local serverReplicator = ServiceRegistry:GetService("ServerReplicator")
		if serverReplicator then
			serverReplicator:UnregisterPlayer(player)
		end

		-- Remove from collision group
		local collisionGroupService = ServiceRegistry:GetService("CollisionGroupService")
		if collisionGroupService then
			collisionGroupService:RemoveCharacterFromCollisionGroup(character)
		end

		-- Clear player.Character BEFORE destroying (prevents Roblox errors)
		if player.Character == character then
			player.Character = nil
		end

		-- NOTE: Client handles visual part cleanup automatically when character is destroyed

		-- Use garbage collector if available for safer cleanup
		if garbageCollector then
			garbageCollector:SafeDestroy(character, function()
				self:CleanupPlayerData(player)
			end)
		else
			character:Destroy()
			self:CleanupPlayerData(player)
		end

		Log:Debug("CHARACTER", "Character removed successfully", { Player = player.Name })
	end
end

function CharacterService:CleanupPlayerData(player)
	local character = self.ActiveCharacters[player]
	if not character then
		return
	end

	-- Clean up garbage collection tracking
	if garbageCollector then
		local trackingId = character:GetAttribute("GCTrackingId")
		if trackingId then
			garbageCollector:UntrackObject(trackingId)
		end
	end

	self.ActiveCharacters[player] = nil

	-- Clean up spawn state tracking
	self.IsSpawningCharacter[player.UserId] = nil
	self.IsClientSetupComplete[player.UserId] = nil
end

function CharacterService:GetCharacter(player)
	return self.ActiveCharacters[player]
end

function CharacterService:GetAllCharacters()
	return table.clone(self.ActiveCharacters)
end

function CharacterService:SetupHumanoid(characterModel, player)
	local humanoidRootPart = CharacterLocations:GetHumanoidRootPart(characterModel)
	local head = CharacterLocations:GetHumanoidHead(characterModel)

	if not humanoidRootPart or not head then
		Log:Error("CHARACTER", "Missing HumanoidRootPart or Head for voice chat", {
			Character = characterModel.Name,
			HasRootPart = humanoidRootPart ~= nil,
			HasHead = head ~= nil,
		})
		return false
	end

	-- Get the existing Humanoid instance
	local humanoid = CharacterLocations:GetHumanoidInstance(characterModel)
	if not humanoid then
		Log:Error("CHARACTER", "No Humanoid instance found in character", { Character = characterModel.Name })
		return false
	end

	-- Apply configuration from SystemConfig
	local humanoidConfig = Config.System.Humanoid

	-- Core settings for custom character compatibility
	humanoid.EvaluateStateMachine = humanoidConfig.EvaluateStateMachine
	humanoid.RequiresNeck = humanoidConfig.RequiresNeck
	humanoid.BreakJointsOnDeath = humanoidConfig.BreakJointsOnDeath

	-- Display settings - hide UI elements
	humanoid.HealthDisplayDistance = humanoidConfig.HealthDisplayDistance
	humanoid.NameDisplayDistance = humanoidConfig.NameDisplayDistance
	humanoid.DisplayDistanceType = humanoidConfig.DisplayDistanceType

	-- Health settings from HealthConfig
	local healthConfig = Config.Health.Player
	humanoid.MaxHealth = healthConfig.MaxHealth
	humanoid.Health = healthConfig.StartHealth

	-- Disable health regeneration
	local regenerationScript = humanoid:FindFirstChild("Health")
	if regenerationScript then
		regenerationScript:Destroy()
	end

	-- Disable unnecessary states for performance
	for _, state in ipairs(humanoidConfig.DisabledStates) do
		humanoid:SetStateEnabled(state, false)
	end

	-- Make humanoid parts invisible and massless (already anchored from spawn)
	PartUtils:MakePartInvisible(humanoidRootPart)
	PartUtils:MakePartInvisible(head)

	-- NOTE: Death is now handled client-side via PlayerDied RemoteEvent
	-- The client's Humanoid.Died event (in CharacterSetup.lua) triggers death notification
	-- Server's Humanoid.Died event is NOT used because client destroys/rebuilds the Humanoid

	Log:Info("CHARACTER", "Humanoid configured", {
		Character = characterModel.Name,
		MaxHealth = humanoid.MaxHealth,
		Health = humanoid.Health,
	})
	return true
end

function CharacterService:OnPlayerDeath(player, deathData)
	-- Get killer from client-provided death data
	local killer = deathData and deathData.Killer or nil
	local wasHeadshot = deathData and deathData.WasHeadshot or false

	Log:Info("CHARACTER", "Player died", {
		Player = player.Name,
		Killer = killer and killer.Name or "None",
		Headshot = wasHeadshot,
	})

	-- Broadcast death event to all clients (for kill feed, stats, etc.)
	RemoteEvents:FireAllClients("PlayerKilled", {
		Player = player,
		Killer = killer,
		Headshot = wasHeadshot,
	})

	-- Schedule respawn after delay
	local respawnDelay = Config.Health.Player.RespawnDelay
	task.delay(respawnDelay, function()
		if player and player.Parent then -- Check player is still in game
			self:SpawnCharacter(player)
		end
	end)
end

function CharacterService:GetSpawnPosition()
	-- Check if round system exists and is running
	local roundService = ServiceRegistry:GetService("RoundService")
	if not roundService or not roundService:IsSystemRunning() then
		-- Round system not active, spawn at lobby
		return self:GetLobbySpawnPosition()
	end

	-- Round system is active, check player state
	-- For now, just spawn at lobby (phases will reposition as needed)
	return self:GetLobbySpawnPosition()
end

function CharacterService:GetLobbySpawnPosition()
	-- Try to get lobby spawn through MapLoader
	local MapLoader = require(ServerStorage.Modules.MapLoader)
	local lobbySpawn = MapLoader:GetLobbySpawn()

	if lobbySpawn then
		-- Get random position on lobby spawn part
		local SpawnManager = require(ServerStorage.Modules.SpawnManager)
		local spawnPos = SpawnManager:GetLobbySpawnPosition(lobbySpawn)
		Log:Debug("CHARACTER", "Using lobby spawn position", { Position = spawnPos })
		return spawnPos
	end

	-- Fallback to default position if lobby spawn not found
	Log:Warn("CHARACTER", "Lobby spawn not found, using fallback position")
	return Vector3.new(0, 10, 0)
end

return CharacterService
