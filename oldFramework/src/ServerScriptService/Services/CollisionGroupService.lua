local CollisionGroupService = {}

-- Services
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local LogService = require(Locations.Modules.Systems.Core.LogService)

-- Constants
local PLAYER_COLLISION_GROUP = "Players"
local HITBOX_COLLISION_GROUP = "Hitboxes"
local RAGDOLL_COLLISION_GROUP = "Ragdolls"

function CollisionGroupService:Init()
	LogService:RegisterCategory("COLLISION", "Player collision group management")

	-- Register collision group for players if it doesn't exist
	local success, error = pcall(function()
		PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
	end)

	if success then
		LogService:Info("COLLISION", "Created player collision group")
	else
		-- Group might already exist, which is fine
		LogService:Debug("COLLISION", "Player collision group already exists or failed to create", { Error = error })
	end

	-- Set players to not collide with each other
	local setSuccess, setError = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
	end)

	if setSuccess then
		LogService:Info("COLLISION", "Players configured to not collide with each other")
	else
		LogService:Error("COLLISION", "Failed to configure player collision", { Error = setError })
	end

	-- Register collision group for hitboxes (used for weapon hit detection)
	local hitboxSuccess, hitboxError = pcall(function()
		PhysicsService:RegisterCollisionGroup(HITBOX_COLLISION_GROUP)
	end)

	if hitboxSuccess then
		LogService:Info("COLLISION", "Created hitbox collision group")
	else
		LogService:Debug("COLLISION", "Hitbox collision group already exists or failed to create", { Error = hitboxError })
	end

	-- Hitboxes should not physically collide with anything (CanCollide=false anyway)
	-- But they should be raycastable via CollisionGroup filter
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(HITBOX_COLLISION_GROUP, HITBOX_COLLISION_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(HITBOX_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
	end)

	-- Register collision group for ragdolls (dead players)
	local ragdollSuccess, ragdollError = pcall(function()
		PhysicsService:RegisterCollisionGroup(RAGDOLL_COLLISION_GROUP)
	end)

	if ragdollSuccess then
		LogService:Info("COLLISION", "Created ragdoll collision group")
	else
		LogService:Debug("COLLISION", "Ragdoll collision group already exists or failed to create", { Error = ragdollError })
	end

	-- Ragdolls should NOT collide with players (so players can walk through dead bodies)
	-- But ragdolls CAN collide with each other and the environment
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(RAGDOLL_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(RAGDOLL_COLLISION_GROUP, HITBOX_COLLISION_GROUP, false)
	end)

	LogService:Info("COLLISION", "CollisionGroupService initialized")
end

function CollisionGroupService:SetCharacterCollisionGroup(character)
	if not character or not character:IsA("Model") then
		LogService:Warn("COLLISION", "Invalid character provided to SetCharacterCollisionGroup")
		return false
	end

	local success = true
	local partsProcessed = 0

	-- Apply collision group to all BaseParts in the character
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local partSuccess, partError = pcall(function()
				part.CollisionGroup = PLAYER_COLLISION_GROUP
			end)

			if partSuccess then
				partsProcessed = partsProcessed + 1
			else
				LogService:Warn("COLLISION", "Failed to set collision group for part", {
					Character = character.Name,
					Part = part.Name,
					Error = partError,
				})
				success = false
			end
		end
	end

	if success then
		LogService:Debug("COLLISION", "Character collision group set successfully", {
			Character = character.Name,
			PartsProcessed = partsProcessed,
		})
	end

	return success
end

function CollisionGroupService:SetHitboxCollisionGroup(character)
	if not character or not character:IsA("Model") then
		LogService:Warn("COLLISION", "Invalid character provided to SetHitboxCollisionGroup")
		return false
	end

	local hitboxFolder = character:FindFirstChild("Hitbox")
	if not hitboxFolder then
		LogService:Warn("COLLISION", "No Hitbox folder found in character", { Character = character.Name })
		return false
	end

	local success = true
	local partsProcessed = 0

	-- Apply Hitboxes collision group to all hitbox parts
	for _, hitboxPart in pairs(hitboxFolder:GetChildren()) do
		if hitboxPart:IsA("BasePart") then
			local partSuccess, partError = pcall(function()
				hitboxPart.CollisionGroup = HITBOX_COLLISION_GROUP
			end)

			if partSuccess then
				partsProcessed = partsProcessed + 1
			else
				LogService:Warn("COLLISION", "Failed to set hitbox collision group for part", {
					Character = character.Name,
					Part = hitboxPart.Name,
					Error = partError,
				})
				success = false
			end
		end
	end

	if success then
		LogService:Debug("COLLISION", "Hitbox collision group set successfully", {
			Character = character.Name,
			PartsProcessed = partsProcessed,
		})
	end

	return success
end

function CollisionGroupService:RemoveCharacterFromCollisionGroup(character)
	if not character or not character:IsA("Model") then
		return
	end

	-- Reset all parts back to default collision group
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part.CollisionGroup = "Default"
			end)
		end
	end

	LogService:Debug("COLLISION", "Character removed from collision group", { Character = character.Name })
end

function CollisionGroupService:SetRagdollCollisionGroup(rig)
	if not rig or not rig:IsA("Model") then
		LogService:Warn("COLLISION", "Invalid rig provided to SetRagdollCollisionGroup")
		return false
	end

	local success = true
	local partsProcessed = 0

	-- Apply ragdoll collision group to all BaseParts in the rig
	for _, part in pairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			local partSuccess, partError = pcall(function()
				part.CollisionGroup = RAGDOLL_COLLISION_GROUP
			end)

			if partSuccess then
				partsProcessed = partsProcessed + 1
			else
				LogService:Warn("COLLISION", "Failed to set ragdoll collision group for part", {
					Rig = rig.Name,
					Part = part.Name,
					Error = partError,
				})
				success = false
			end
		end
	end

	if success then
		LogService:Debug("COLLISION", "Ragdoll collision group set successfully", {
			Rig = rig.Name,
			PartsProcessed = partsProcessed,
		})
	end

	return success
end

-- Get collision group name for external use (client-side ragdoll system)
function CollisionGroupService:GetRagdollCollisionGroupName()
	return RAGDOLL_COLLISION_GROUP
end

return CollisionGroupService
