local SpawnManager = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local CharacterUtils = require(Locations.Modules.Systems.Character.CharacterUtils)

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function SpawnManager:Init()
	Log:RegisterCategory("SPAWN", "Spawn position management for lobby and maps")
	Log:Info("SPAWN", "SpawnManager initialized")
end

-- =============================================================================
-- LOBBY SPAWNING
-- =============================================================================

function SpawnManager:GetLobbySpawnPosition(lobbySpawnPart)
	if not lobbySpawnPart then
		Log:Error("SPAWN", "Lobby spawn part is nil")
		return Vector3.new(0, 10, 0) -- Fallback position
	end

	-- Get the size of the spawn part
	local size = lobbySpawnPart.Size
	local position = lobbySpawnPart.Position

	-- Calculate random X and Z within bounds
	local halfWidth = size.X / 2
	local halfDepth = size.Z / 2

	local randomX = position.X + math.random() * size.X - halfWidth
	local randomZ = position.Z + math.random() * size.Z - halfDepth

	-- Y coordinate is bottom surface (spawn parts are no-collide/transparent on ground)
	local spawnY = position.Y - (size.Y / 2)

	local spawnPosition = Vector3.new(randomX, spawnY, randomZ)

	Log:Debug("SPAWN", "Generated lobby spawn position", {
		Position = spawnPosition,
		SpawnPartSize = size,
	})

	return spawnPosition
end

function SpawnManager:SpawnEntitiesInLobby(entities, lobbySpawnPart)
	local spawnedCount = 0

	for _, entity in ipairs(entities) do
		local success = self:SpawnEntityInLobby(entity, lobbySpawnPart)
		if success then
			spawnedCount = spawnedCount + 1
		end
	end

	Log:Info("SPAWN", "Spawned entities in lobby", {
		Total = #entities,
		Successful = spawnedCount,
	})

	return spawnedCount
end

function SpawnManager:SpawnEntityInLobby(entity, lobbySpawnPart)
	-- Handle both Player objects and NPC entity wrappers
	local character = nil
	local entityName = nil

	if entity.Type == "Player" then
		-- It's a player
		if not entity.Entity or not entity.Entity.Character then
			Log:Warn("SPAWN", "Cannot spawn player in lobby without character", {
				Player = entity.Entity and entity.Entity.Name or "nil",
			})
			return false
		end
		character = entity.Entity.Character
		entityName = entity.Entity.Name
	elseif entity.Type == "NPC" then
		-- It's an NPC - entity.Entity is the NPC name, need to get the character
		local NPCService = require(game:GetService("ServerScriptService").Services.NPCService)
		local npcData = NPCService:GetNPC(entity.Entity)
		if not npcData or not npcData.Character then
			Log:Warn("SPAWN", "Cannot spawn NPC in lobby without character", {
				NPC = entity.Entity,
			})
			return false
		end
		character = npcData.Character
		entityName = entity.Entity
	else
		Log:Error("SPAWN", "Unknown entity type for lobby spawn", { Type = entity.Type })
		return false
	end

	if not character or not character.Parent then
		Log:Warn("SPAWN", "Entity has no character for lobby spawn", { Entity = entityName })
		return false
	end

	-- Get random position
	local spawnPosition = self:GetLobbySpawnPosition(lobbySpawnPart)

	-- Move character
	local success = CharacterUtils:SetCharacterPosition(character, spawnPosition)

	if success then
		Log:Debug("SPAWN", "Entity spawned in lobby", {
			Entity = entityName,
			Type = entity.Type,
			Position = spawnPosition,
		})
	else
		Log:Error("SPAWN", "Failed to spawn entity in lobby", {
			Entity = entityName,
			Type = entity.Type,
			Position = spawnPosition,
		})
	end

	return success
end

-- =============================================================================
-- MAP SPAWNING
-- =============================================================================

function SpawnManager:AssignMapSpawns(entities, spawnsFolder)
	if not spawnsFolder then
		Log:Error("SPAWN", "Spawns folder is nil")
		return {}
	end

	-- Get all spawn parts
	local spawnParts = spawnsFolder:GetChildren()

	if #spawnParts == 0 then
		Log:Error("SPAWN", "No spawn parts found in spawns folder")
		return {}
	end

	-- Shuffle spawn parts for random distribution
	local shuffledSpawns = self:ShuffleTable(spawnParts)

	-- Validate we have enough spawns
	if #entities > #shuffledSpawns then
		Log:Warn("SPAWN", "More entities than spawn points", {
			Entities = #entities,
			Spawns = #shuffledSpawns,
		})
	end

	-- Assign spawns to entities (players or NPCs)
	local assignments = {}
	for i, entity in ipairs(entities) do
		local spawnIndex = ((i - 1) % #shuffledSpawns) + 1
		assignments[entity] = shuffledSpawns[spawnIndex]
	end

	Log:Info("SPAWN", "Assigned map spawns", {
		Entities = #entities,
		Spawns = #shuffledSpawns,
	})

	return assignments
end

function SpawnManager:TeleportPlayersToSpawns(spawnAssignments)
	local successCount = 0

	for entity, spawnPart in pairs(spawnAssignments) do
		local success = self:TeleportEntityToSpawn(entity, spawnPart)
		if success then
			successCount = successCount + 1
		end
	end

	Log:Info("SPAWN", "Teleported entities to spawns", {
		Total = self:CountTable(spawnAssignments),
		Successful = successCount,
	})

	return successCount
end

function SpawnManager:TeleportEntityToSpawn(entity, spawnPart)
	-- Handle both Player objects and NPC entity wrappers
	local character = nil
	local entityName = nil

	if entity.Type == "Player" then
		-- It's a player
		if not entity.Entity or not entity.Entity.Character then
			Log:Warn("SPAWN", "Cannot teleport player without character", {
				Player = entity.Entity and entity.Entity.Name or "nil",
			})
			return false
		end
		character = entity.Entity.Character
		entityName = entity.Entity.Name
	elseif entity.Type == "NPC" then
		-- It's an NPC - entity.Entity is the NPC name, need to get the character
		local NPCService = require(game:GetService("ServerScriptService").Services.NPCService)
		local npcData = NPCService:GetNPC(entity.Entity)
		if not npcData or not npcData.Character then
			Log:Warn("SPAWN", "Cannot teleport NPC without character", {
				NPC = entity.Entity,
			})
			return false
		end
		character = npcData.Character
		entityName = entity.Entity
	else
		Log:Error("SPAWN", "Unknown entity type", { Type = entity.Type })
		return false
	end

	if not spawnPart then
		Log:Error("SPAWN", "Spawn part is nil for entity", { Entity = entityName })
		return false
	end

	-- Get spawn position (bottom of spawn part, since they're no-collide/transparent)
	local spawnPosition = spawnPart.Position - Vector3.new(0, spawnPart.Size.Y / 2, 0)

	-- Validate character has PrimaryPart
	if not character.PrimaryPart then
		Log:Error("SPAWN", "Character missing PrimaryPart", {
			Entity = entityName,
			Type = entity.Type,
			Character = character.Name,
		})
		return false
	end

	-- Teleport character
	CharacterUtils:SetCharacterPosition(character, spawnPosition)

	Log:Debug("SPAWN", "Entity teleported to spawn", {
		Entity = entityName,
		Type = entity.Type,
		SpawnPart = spawnPart.Name,
		Position = spawnPosition,
	})

	return true
end

-- =============================================================================
-- GHOST SPAWNING
-- =============================================================================

function SpawnManager:SpawnGhosts(ghostPlayers, ghostSpawnsFolder)
	if not ghostSpawnsFolder then
		Log:Error("SPAWN", "Ghost spawns folder is nil")
		return 0
	end

	-- Wrap players in entity format for AssignMapSpawns
	local ghostEntities = {}
	for _, player in ipairs(ghostPlayers) do
		table.insert(ghostEntities, {
			Type = "Player",
			Entity = player,
			Name = player.Name,
		})
	end

	-- Assign and teleport ghosts using same logic as regular spawns
	local assignments = self:AssignMapSpawns(ghostEntities, ghostSpawnsFolder)
	return self:TeleportPlayersToSpawns(assignments)
end

-- =============================================================================
-- CHARACTER FREEZING (for RoundStart phase)
-- =============================================================================

function SpawnManager:FreezePlayer(player)
	local character = player.Character
	if not character then
		return false
	end

	local primaryPart = character.PrimaryPart
	if not primaryPart then
		Log:Warn("SPAWN", "Cannot freeze player without PrimaryPart", { Player = player.Name })
		return false
	end

	-- Disable VectorForce to stop movement (smooth, no physics discontinuity)
	local vectorForce = primaryPart:FindFirstChild("VectorForce")
	if vectorForce then
		vectorForce.Enabled = false
	else
		Log:Debug("SPAWN", "No VectorForce found for freezing", { Player = player.Name })
	end

	-- Clear current velocity to stop immediately
	primaryPart.AssemblyLinearVelocity = Vector3.zero
	primaryPart.AssemblyAngularVelocity = Vector3.zero

	Log:Debug("SPAWN", "Player frozen", { Player = player.Name })
	return true
end

function SpawnManager:UnfreezePlayer(player)
	local character = player.Character
	if not character then
		return false
	end

	local primaryPart = character.PrimaryPart
	if not primaryPart then
		Log:Warn("SPAWN", "Cannot unfreeze player without PrimaryPart", { Player = player.Name })
		return false
	end

	-- Re-enable VectorForce to allow movement again
	local vectorForce = primaryPart:FindFirstChild("VectorForce")
	if vectorForce then
		vectorForce.Enabled = true
	else
		Log:Debug("SPAWN", "No VectorForce found for unfreezing", { Player = player.Name })
	end

	Log:Debug("SPAWN", "Player unfrozen", { Player = player.Name })
	return true
end

function SpawnManager:FreezePlayers(players)
	local count = 0
	for _, player in ipairs(players) do
		if self:FreezePlayer(player) then
			count = count + 1
		end
	end

	Log:Info("SPAWN", "Froze players", { Count = count, Total = #players })
	return count
end

function SpawnManager:UnfreezePlayers(players)
	local count = 0
	for _, player in ipairs(players) do
		if self:UnfreezePlayer(player) then
			count = count + 1
		end
	end

	Log:Info("SPAWN", "Unfroze players", { Count = count, Total = #players })
	return count
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

function SpawnManager:ShuffleTable(tbl)
	local shuffled = table.clone(tbl)
	local n = #shuffled

	for i = n, 2, -1 do
		local j = math.random(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	return shuffled
end

function SpawnManager:CountTable(tbl)
	local count = 0
	for _, _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

function SpawnManager:ValidateSpawnCount(playerCount, spawnsFolder)
	if not spawnsFolder then
		return false
	end

	local spawnCount = #spawnsFolder:GetChildren()

	if spawnCount < playerCount then
		Log:Warn("SPAWN", "Insufficient spawn points", {
			Required = playerCount,
			Available = spawnCount,
		})
		return false
	end

	return true
end

return SpawnManager
