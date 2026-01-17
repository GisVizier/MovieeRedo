local ValidationUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)

function ValidationUtils:IsCharacterValid(character)
	return character and character.Parent and character.PrimaryPart
end

function ValidationUtils:IsPrimaryPartValid(primaryPart)
	return primaryPart and primaryPart.Parent
end

function ValidationUtils:ArePhysicsConstraintsValid(primaryPart)
	if not self:IsPrimaryPartValid(primaryPart) then
		return false, false
	end

	local vectorForce = primaryPart:FindFirstChild("VectorForce")
	local alignOrientation = primaryPart:FindFirstChild("AlignOrientation")

	return vectorForce ~= nil, alignOrientation ~= nil
end

function ValidationUtils:IsPlayerInputValid(inputManager, cameraController)
	return inputManager ~= nil and cameraController ~= nil
end

function ValidationUtils:IsNPCDataValid(npcData)
	return npcData and npcData.Character and npcData.Character.Parent and npcData.PrimaryPart
end

function ValidationUtils:ValidateAndReturnCharacterParts(character)
	if not self:IsCharacterValid(character) then
		return nil, nil, nil
	end

	local primaryPart = character.PrimaryPart
	local feetPart = CharacterLocations:GetFeet(character)
	local headPart = CharacterLocations:GetHead(character)

	return primaryPart, feetPart, headPart
end

-- Common service validation and caching patterns
function ValidationUtils:GetServiceSafely(serviceName, globalTable)
	if globalTable and globalTable[serviceName] then
		return globalTable[serviceName]
	end
	return nil
end

-- Common primary part setup validation
function ValidationUtils:ValidateCharacterSetup(character)
	if not self:IsCharacterValid(character) then
		return false, "Character is invalid"
	end

	local primaryPart = character.PrimaryPart
	if not primaryPart then
		return false, "Character has no PrimaryPart"
	end

	return true, nil
end

-- Physics constraint validation
function ValidationUtils:ValidatePhysicsSetup(primaryPart, requiredConstraints)
	if not self:IsPrimaryPartValid(primaryPart) then
		return false, "Invalid PrimaryPart"
	end

	requiredConstraints = requiredConstraints or { "VectorForce", "AlignOrientation" }

	for _, constraintName in ipairs(requiredConstraints) do
		local constraint = primaryPart:FindFirstChild(constraintName)
		if not constraint then
			return false, "Missing constraint: " .. constraintName
		end
	end

	return true, nil
end

-- Common ground detection validation
function ValidationUtils:ValidateGroundDetectionSetup(character, primaryPart, raycastParams)
	if not self:IsCharacterValid(character) then
		return false, "Invalid character"
	end

	if not self:IsPrimaryPartValid(primaryPart) then
		return false, "Invalid primary part"
	end

	if not raycastParams then
		return false, "Missing raycast parameters"
	end

	return true, nil
end

return ValidationUtils
