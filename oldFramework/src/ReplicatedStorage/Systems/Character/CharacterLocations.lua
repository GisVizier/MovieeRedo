--[[
	CharacterLocations - Centralized character part path management

	This module provides a single source of truth for all character part locations,
	making it easy to update the character structure without touching multiple files.
]]

local CharacterLocations = {}

-- Character part accessor functions
-- These functions return the actual part objects from a character model

function CharacterLocations:GetFeet(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	if not collider then
		return nil
	end
	local default = collider:FindFirstChild("Default")
	if not default then
		return nil
	end
	return default:FindFirstChild("Feet")
end

function CharacterLocations:GetHead(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	if not collider then
		return nil
	end
	local default = collider:FindFirstChild("Default")
	if not default then
		return nil
	end
	return default:FindFirstChild("Head")
end

function CharacterLocations:GetBody(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	if not collider then
		return nil
	end
	local default = collider:FindFirstChild("Default")
	if not default then
		return nil
	end
	return default:FindFirstChild("Body")
end

-- Crouch state parts
function CharacterLocations:GetCrouchHead(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	if not collider then
		return nil
	end
	local crouch = collider:FindFirstChild("Crouch")
	if not crouch then
		return nil
	end
	return crouch:FindFirstChild("CrouchHead")
end

function CharacterLocations:GetCrouchBody(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	if not collider then
		return nil
	end
	local crouch = collider:FindFirstChild("Crouch")
	if not crouch then
		return nil
	end
	return crouch:FindFirstChild("CrouchBody")
end

-- Collision detection parts
function CharacterLocations:GetCollisionHead(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	if not collider then
		return nil
	end
	local uncrouchCheck = collider:FindFirstChild("UncrouchCheck")
	if not uncrouchCheck then
		return nil
	end
	return uncrouchCheck:FindFirstChild("CollisionHead")
end

function CharacterLocations:GetCollisionBody(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	if not collider then
		return nil
	end
	local uncrouchCheck = collider:FindFirstChild("UncrouchCheck")
	if not uncrouchCheck then
		return nil
	end
	return uncrouchCheck:FindFirstChild("CollisionBody")
end

-- Root part (unchanged - still at top level)
function CharacterLocations:GetRoot(character)
	if not character or not character.Parent then
		return nil
	end
	return character:FindFirstChild("Root")
end

-- Humanoid parts (for VC and bubble chat) - now directly in character
function CharacterLocations:GetHumanoidRootPart(character)
	if not character or not character.Parent then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

function CharacterLocations:GetHumanoidHead(character)
	if not character or not character.Parent then
		return nil
	end
	-- Look for Head that's a direct child of character (not in Collider)
	for _, child in ipairs(character:GetChildren()) do
		if child.Name == "Head" and child:IsA("BasePart") and child.Parent == character then
			return child
		end
	end
	return nil
end

function CharacterLocations:GetHumanoidInstance(character)
	if not character or not character.Parent then
		return nil
	end
	-- IMPORTANT: Only get Humanoid that's a DIRECT child of Character (not in Rig)
	-- The Rig also has a Humanoid for cosmetics, but the health Humanoid is directly under Character
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Humanoid") then
			return child
		end
	end
	return nil
end

-- Helper function to get all collider models
function CharacterLocations:GetColliderModels(character)
	if not character or not character.Parent then
		return {}
	end

	local collider = character:FindFirstChild("Collider")
	if not collider then
		return {}
	end

	local models = {}
	for _, child in pairs(collider:GetChildren()) do
		if child:IsA("Model") then
			models[child.Name] = child
		end
	end

	return models
end

-- Helper function to get all parts from all collider models
function CharacterLocations:GetAllColliderParts(character)
	local parts = {}
	local colliderModels = self:GetColliderModels(character)

	for _, model in pairs(colliderModels) do
		for _, part in pairs(model:GetChildren()) do
			if part:IsA("BasePart") then
				table.insert(parts, part)
			end
		end
	end

	return parts
end

-- Helper function to iterate through all collider parts (for physics/network ownership)
function CharacterLocations:ForEachColliderPart(character, callback)
	if not character or not character.Parent or not callback then
		return
	end

	local collider = character:FindFirstChild("Collider")
	if not collider then
		return
	end

	for _, colliderModel in pairs(collider:GetChildren()) do
		if colliderModel:IsA("Model") then
			for _, part in pairs(colliderModel:GetChildren()) do
				if part:IsA("BasePart") then
					callback(part, colliderModel.Name)
				end
			end
		end
	end
end

-- Rig part accessor functions
-- NEW: Rigs are now stored in workspace.Rigs instead of being parented to the character
-- This allows rigs to persist after death/respawn for ragdoll effects
function CharacterLocations:GetRig(character)
	if not character or not character.Parent then
		return nil
	end

	-- First check if rig is still directly in character (legacy support)
	local rigInCharacter = character:FindFirstChild("Rig")
	if rigInCharacter then
		return rigInCharacter
	end

	-- NEW: Use RigManager to find the active rig for this character
	-- Load RigManager dynamically to avoid circular dependencies
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
	local RigManager = require(Locations.Modules.Systems.Character.RigManager)

	return RigManager:GetRigFromCharacter(character)
end

function CharacterLocations:GetRigHumanoidRootPart(character)
	if not character or not character.Parent then
		return nil
	end
	local rig = self:GetRig(character)
	if not rig then
		return nil
	end
	return rig:FindFirstChild("HumanoidRootPart")
end

function CharacterLocations:GetRigTorso(character)
	if not character or not character.Parent then
		return nil
	end
	local rig = self:GetRig(character)
	if not rig then
		return nil
	end
	return rig:FindFirstChild("Torso")
end

-- Helper function to iterate through all Rig parts (for welding/network ownership)
function CharacterLocations:ForEachRigPart(character, callback)
	if not character or not character.Parent or not callback then
		return
	end

	-- Use GetRig to support both legacy (in character) and new (in workspace.Rigs) locations
	local rig = self:GetRig(character)
	if not rig then
		return
	end

	for _, part in pairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			callback(part)
		end
	end
end

-- Validation helpers
function CharacterLocations:HasColliderStructure(character)
	if not character or not character.Parent then
		return false
	end
	local collider = character:FindFirstChild("Collider")
	return collider and collider:IsA("Model")
end

function CharacterLocations:HasDefaultParts(character)
	if not self:HasColliderStructure(character) then
		return false
	end
	local collider = character:FindFirstChild("Collider")
	if not collider then
		return false
	end
	local default = collider:FindFirstChild("Default")
	return default and default:IsA("Model")
end

return CharacterLocations
