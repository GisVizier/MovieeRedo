local ValidationUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))

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

function ValidationUtils:ValidateAndReturnCharacterParts(character)
	if not self:IsCharacterValid(character) then
		return nil, nil, nil
	end

	local primaryPart = character.PrimaryPart
	local feetPart = CharacterLocations:GetFeet(character)
	local headPart = CharacterLocations:GetHead(character)

	return primaryPart, feetPart, headPart
end

return ValidationUtils
