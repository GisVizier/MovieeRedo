local NPCService = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local CharacterUtils = require(Locations.Modules.Systems.Character.CharacterUtils)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local ValidationUtils = require(Locations.Modules.Utils.ValidationUtils)
local Config = require(Locations.Modules.Config)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
local PartUtils = require(Locations.Modules.Utils.PartUtils)
local WeldUtils = require(Locations.Modules.Utils.WeldUtils)

-- Cache frequently accessed objects
local characterTemplate = nil
local garbageCollector = nil

-- Performance constants
local AI_UPDATE_BASE_INTERVAL = 0.1
local AI_UPDATE_RANDOM_OFFSET = 0.05

NPCService.NPCs = {}
NPCService.NPCCount = 0
NPCService.AIConnections = {}

NPCService.AISettings = {
	ChangeDirectionTime = 2, -- Move for only 2 seconds before deciding again
	IdleTime = 3, -- Idle for 3 seconds when standing still

	-- Movement settings
	MovementSpeedMultiplier = 0.85, -- NPCs move at 85% of player speed
}

function NPCService:Init()
	Log:RegisterCategory("NPC", "NPC spawning and AI management")

	-- Cache references for performance
	characterTemplate = ServerStorage.Models:WaitForChild("Character")
	-- Get garbage collector service safely
	if _G.Services and _G.Services.GarbageCollectorService then
		garbageCollector = _G.Services.GarbageCollectorService
	end

	RemoteEvents:ConnectServer("RequestNPCSpawn", function(player)
		Log:Debug("NPC", "Spawn request received", { Player = player.Name })
		self:SpawnNPC(player)
	end)

	RemoteEvents:ConnectServer("RequestNPCRemoveOne", function(player)
		Log:Debug("NPC", "Remove request received", { Player = player.Name })
		self:RemoveRandomNPC()
	end)

	Log:Debug("NPC", "NPCService initialized")
end

function NPCService:SpawnNPC(requestingPlayer)
	if not characterTemplate then
		Log:Error("NPC", "Character template not found", { Player = requestingPlayer.Name })
		return nil
	end

	self.NPCCount = self.NPCCount + 1
	local npcName = "NPC_" .. self.NPCCount

	local characterModel = characterTemplate:Clone()
	characterModel.Name = npcName

	-- Restore PrimaryPart reference after cloning
	local primaryPart = CharacterUtils:RestorePrimaryPartAfterClone(characterModel, characterTemplate)

	characterModel.Parent = workspace

	-- Get spawn position from round system (same as players)
	local spawnPosition = self:GetNPCSpawnPosition()
	CharacterUtils:SetCharacterPosition(characterModel, spawnPosition)

	-- Setup basic welds for NPCs (no crouch)
	self:SetupNPCWelds(characterModel)

	-- NPCs use simple server-side movement (no VectorForce needed)
	-- primaryPart is already obtained from RestorePrimaryPartAfterClone above
	if not primaryPart then
		Log:Error("NPC", "NPC has no PrimaryPart", { Name = npcName })
		characterModel:Destroy()
		return nil
	end

	local npcData = {
		Name = npcName,
		Character = characterModel,
		PrimaryPart = primaryPart,
		CurrentDirection = Vector2.new(0, 0),
		LastDirectionChange = tick(),
		IsIdle = false,
		IdleStartTime = 0,
	}

	self.NPCs[npcName] = npcData

	-- Setup garbage collection tracking
	if garbageCollector then
		npcData.GCTrackingId = garbageCollector:TrackObject(characterModel, "NPC_" .. npcName, function()
			self:CleanupNPCData(npcName)
		end)
	end

	-- Apply collision group to prevent NPC-to-player collisions
	local collisionGroupService = ServiceRegistry:GetService("CollisionGroupService")
	if collisionGroupService then
		collisionGroupService:SetCharacterCollisionGroup(characterModel)
	end

	-- Register NPC with round system
	self:RegisterNPCWithRoundSystem(npcName)

	self:StartNPCAI(npcData)

	-- Fire character spawned event for clients to handle
	RemoteEvents:FireAllClients("CharacterSpawned", characterModel)

	Log:Info("NPC", "Spawned NPC", { Name = npcName, RequestedBy = requestingPlayer.Name })
	return characterModel
end

function NPCService:SetupNPCWelds(character)
	if not character or not character.PrimaryPart then
		return false
	end

	local root = character.PrimaryPart
	local body = CharacterLocations:GetBody(character)
	local feet = CharacterLocations:GetFeet(character)
	local head = CharacterLocations:GetHead(character)
	local face = CharacterLocations:GetFace(character)

	if not body or not feet or not head or not face then
		warn("NPCService: Missing required parts for NPC welds")
		return false
	end

	-- Create legacy Welds for basic character structure
	WeldUtils:CreateBeanShapeWeld(root, body, "BodyWeld", CFrame.new(0, 0, 0))
	WeldUtils:CreateWeld(root, feet, "FeetWeld", CFrame.new(0, -1.25, 0), CFrame.new(0, 0, 0))
	WeldUtils:CreateWeld(root, head, "HeadWeld", CFrame.new(0, 1.25, 0), CFrame.new(0, 0, 0))
	WeldUtils:CreateWeld(root, face, "FaceWeld", CFrame.new(0, 1.25, 0), CFrame.new(0, 0, 0))

	-- Set proper visibility for normal parts
	body.Transparency = 0
	body.CanCollide = true
	head.Transparency = 0
	head.CanCollide = true
	face.Transparency = 1 -- Face part stays transparent
	face.CanCollide = false

	-- Weld collision parts (UncrouchCheck colliders)
	local collisionBody = CharacterLocations:GetCollisionBody(character)
	local collisionHead = CharacterLocations:GetCollisionHead(character)
	if collisionBody then
		WeldUtils:CreateBeanShapeWeld(root, collisionBody, "CollisionBodyWeld", CFrame.new(0, 0.05, 0))
		PartUtils:MakePartInvisible(collisionBody, { Massless = false })
	end
	if collisionHead then
		WeldUtils:CreateWeld(root, collisionHead, "CollisionHeadWeld", CFrame.new(0, 1.35, 0), CFrame.new(0, 0, 0))
		PartUtils:MakePartInvisible(collisionHead, { Massless = false })
	end

	-- Hide crouch parts if they exist (NPCs don't use them)
	local crouchBody = CharacterLocations:GetCrouchBody(character)
	local crouchHead = CharacterLocations:GetCrouchHead(character)
	local crouchFace = CharacterLocations:GetCrouchFace(character)
	if crouchBody then
		PartUtils:MakePartInvisible(crouchBody, { Massless = false })
	end
	if crouchHead then
		PartUtils:MakePartInvisible(crouchHead, { Massless = false })
	end
	if crouchFace then
		PartUtils:MakePartInvisible(crouchFace, { Massless = false })
	end

	return true
end

function NPCService:RegisterNPCWithRoundSystem(npcName)
	-- Safely check if round system is available
	local success, NPCStateManager = pcall(function()
		return require(Locations.Modules.Systems.Round.NPCStateManager)
	end)

	if not success then
		Log:Warn("NPC", "Round system not available, NPC won't participate in rounds", {
			NPC = npcName,
		})
		return
	end

	-- Initialize if not already done
	if not NPCStateManager.Initialized then
		NPCStateManager:Init()
		NPCStateManager.Initialized = true
	end

	-- Set NPC to Lobby state by default
	NPCStateManager:SetState(npcName, NPCStateManager.States.Lobby)

	Log:Debug("NPC", "NPC registered with round system", {
		NPC = npcName,
		State = "Lobby",
	})
end

function NPCService:GetNPCSpawnPosition()
	-- Try to get lobby spawn through MapLoader (same as players)
	local MapLoader = require(ServerStorage.Modules.MapLoader)
	local lobbySpawn = MapLoader:GetLobbySpawn()

	if lobbySpawn then
		-- Get random position on lobby spawn part
		local SpawnManager = require(ServerStorage.Modules.SpawnManager)
		local spawnPos = SpawnManager:GetLobbySpawnPosition(lobbySpawn)
		Log:Debug("NPC", "Using lobby spawn position", { Position = spawnPos })
		return spawnPos
	end

	-- Fallback to random position near origin
	Log:Warn("NPC", "Lobby spawn not found, using fallback position")
	return Vector3.new(math.random(-10, 10), 10, math.random(-10, 10))
end

function NPCService:StartNPCAI(npcData)
	-- Stagger updates to prevent all NPCs from updating same frame
	local updateInterval = AI_UPDATE_BASE_INTERVAL + (math.random() * AI_UPDATE_RANDOM_OFFSET)
	local lastUpdate = 0

	local connection
	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not npcData.Character or not npcData.Character.Parent then
			connection:Disconnect()
			self:CleanupNPCData(npcData.Name)
			return
		end

		lastUpdate = lastUpdate + deltaTime
		if lastUpdate >= updateInterval then
			self:UpdateNPCAI(npcData, lastUpdate)
			lastUpdate = 0
		end
	end)

	self.AIConnections[npcData.Name] = connection

	-- Track AI connection for cleanup
	if garbageCollector then
		npcData.AIConnectionId = garbageCollector:TrackConnection(connection, "NPC_AI_" .. npcData.Name)
	end
end

function NPCService:UpdateNPCAI(npcData, deltaTime)
	local currentTime = tick()

	if not ValidationUtils:IsNPCDataValid(npcData) then
		return
	end

	-- Simple AI state machine - idle or moving with random direction changes
	if npcData.IsIdle then
		if currentTime - npcData.IdleStartTime > self.AISettings.IdleTime then
			npcData.IsIdle = false
			npcData.CurrentDirection = self:GetRandomDirection()
			npcData.LastDirectionChange = currentTime
		else
			npcData.CurrentDirection = Vector2.new(0, 0)
		end
	else
		if currentTime - npcData.LastDirectionChange > self.AISettings.ChangeDirectionTime then
			if math.random() < 0.85 then -- 85% chance to idle - NPCs mostly stand around
				npcData.IsIdle = true
				npcData.IdleStartTime = currentTime
				npcData.CurrentDirection = Vector2.new(0, 0)
			else
				npcData.CurrentDirection = self:GetRandomDirection()
				npcData.LastDirectionChange = currentTime
			end
		end
	end

	-- Simple server-side movement
	self:ApplySimpleMovement(npcData, currentTime, deltaTime)
end

function NPCService:GetRandomDirection()
	local angle = math.random() * 2 * math.pi
	local magnitude = 0.7 + math.random() * 0.3
	return Vector2.new(math.cos(angle) * magnitude, math.sin(angle) * magnitude)
end

function NPCService:ApplySimpleMovement(npcData, _currentTime, _deltaTime)
	if not npcData.PrimaryPart then
		return
	end

	local primaryPart = npcData.PrimaryPart

	-- Use common physics constraint setup utility
	local _, alignOrientation, bodyVelocity = CharacterUtils:SetupBasicMovementConstraints(primaryPart, "NPC")

	-- Simple movement using BodyVelocity (smoother than direct velocity)
	local moveDirection = Vector3.new(npcData.CurrentDirection.X, 0, -npcData.CurrentDirection.Y)
	if moveDirection.Magnitude > 0 then
		moveDirection = moveDirection.Unit

		-- Set target velocity for smooth movement (slightly slower than players)
		local npcSpeed = Config.Gameplay.Character.WalkSpeed * self.AISettings.MovementSpeedMultiplier
		bodyVelocity.Velocity = Vector3.new(
			moveDirection.X * npcSpeed,
			0, -- BodyVelocity doesn't control Y
			moveDirection.Z * npcSpeed
		)

		-- Update AlignOrientation to face movement direction while staying upright
		-- Add PI to rotate 180 degrees so bean faces forward
		local targetYAngle = math.atan2(moveDirection.X, moveDirection.Z) + math.pi
		local targetCFrame = CFrame.new(primaryPart.Position) * CFrame.Angles(0, targetYAngle, 0)
		alignOrientation.CFrame = targetCFrame
	else
		-- Stop movement when idle
		bodyVelocity.Velocity = Vector3.new(0, 0, 0)
		-- AlignOrientation continues to keep NPC upright even when idle
	end
end

function NPCService:RemoveNPC(npcName)
	local npcData = self.NPCs[npcName]
	if not npcData then
		return
	end

	RemoteEvents:FireAllClients("CharacterRemoving", npcData.Character)

	-- Remove from collision group
	local collisionGroupService = ServiceRegistry:GetService("CollisionGroupService")
	if collisionGroupService then
		collisionGroupService:RemoveCharacterFromCollisionGroup(npcData.Character)
	end

	-- Clean up movement objects
	if npcData.PrimaryPart then
		local bodyVelocity = npcData.PrimaryPart:FindFirstChild("NPCBodyVelocity")
		if bodyVelocity then
			bodyVelocity:Destroy()
		end
		local alignOrientation = npcData.PrimaryPart:FindFirstChild("NPCAlignOrientation")
		if alignOrientation then
			alignOrientation:Destroy()
		end
		local attachment = npcData.PrimaryPart:FindFirstChild("NPCAttachment")
		if attachment then
			attachment:Destroy()
		end
	end

	-- Use garbage collector if available for safer cleanup
	if garbageCollector and npcData.Character then
		garbageCollector:SafeDestroy(npcData.Character, function()
			self:CleanupNPCData(npcName)
		end)
	else
		self:CleanupNPCData(npcName)
		if npcData.Character then
			npcData.Character:Destroy()
		end
	end

	Log:Info("NPC", "Removed NPC", { Name = npcName })
end

function NPCService:CleanupNPCData(npcName)
	local npcData = self.NPCs[npcName]
	if not npcData then
		return
	end

	-- Unregister from round system (if available)
	local success, NPCStateManager = pcall(function()
		return require(Locations.Modules.Systems.Round.NPCStateManager)
	end)
	if success then
		NPCStateManager:RemoveNPC(npcName)
	end

	-- Disconnect AI connection
	if self.AIConnections[npcName] then
		self.AIConnections[npcName]:Disconnect()
		self.AIConnections[npcName] = nil
	end

	-- Clean up garbage collection tracking
	if garbageCollector then
		if npcData.GCTrackingId then
			garbageCollector:UntrackObject(npcData.GCTrackingId)
		end
		if npcData.AIConnectionId then
			garbageCollector:UntrackConnection(npcData.AIConnectionId)
		end
	end

	self.NPCs[npcName] = nil
end

function NPCService:GetNPC(npcName)
	return self.NPCs[npcName]
end

function NPCService:GetAllNPCs()
	return self.NPCs
end

function NPCService:RemoveRandomNPC()
	local npcNames = {}
	for npcName, _ in pairs(self.NPCs) do
		table.insert(npcNames, npcName)
	end

	if #npcNames > 0 then
		local randomIndex = math.random(1, #npcNames)
		local randomNPCName = npcNames[randomIndex]
		self:RemoveNPC(randomNPCName)
		Log:Info("NPC", "Randomly removed NPC", { Name = randomNPCName })
	else
		Log:Debug("NPC", "No NPCs to remove")
	end
end

function NPCService:RemoveAllNPCs()
	for npcName, _ in pairs(self.NPCs) do
		self:RemoveNPC(npcName)
	end
end

return NPCService
