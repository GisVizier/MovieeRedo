local CharacterUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local ValidationUtils = require(Locations.Modules.Utils.ValidationUtils)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local Config = require(Locations.Modules.Config)
local Log = require(Locations.Modules.Systems.Core.LogService)

function CharacterUtils:GetPrimaryPart(character)
	if not ValidationUtils:IsCharacterValid(character) then
		return nil
	end

	-- Use CharacterLocations for consistency - this ensures we always get the actual Root part
	return CharacterLocations:GetRoot(character)
end

function CharacterUtils:SetCharacterPosition(character, position)
	if not character.PrimaryPart then
		return false
	end

	local primaryPart = character.PrimaryPart

	-- Clear velocity to prevent physics conflicts during teleport
	primaryPart.AssemblyLinearVelocity = Vector3.zero
	primaryPart.AssemblyAngularVelocity = Vector3.zero

	-- Temporarily disable VectorForce to eliminate physics conflicts
	local vectorForce = primaryPart:FindFirstChild("VectorForce")
	local wasEnabled = false
	if vectorForce then
		wasEnabled = vectorForce.Enabled
		vectorForce.Enabled = false
	end

	-- Calculate target position based on feet
	local feetPart = CharacterLocations:GetFeet(character)
	local targetCFrame

	if feetPart then
		local primaryPartCFrame = primaryPart.CFrame
		local feetCFrame = feetPart.CFrame

		local relativePosition = primaryPartCFrame:PointToObjectSpace(feetCFrame.Position)
		local feetBottomOffset = relativePosition.Y - (feetPart.Size.Y / 2)

		local targetPrimaryPartPosition = position - Vector3.new(0, feetBottomOffset, 0)
		targetCFrame = CFrame.new(targetPrimaryPartPosition)
	else
		targetCFrame = CFrame.new(position)
	end

	-- Use modern PivotTo instead of deprecated SetPrimaryPartCFrame
	character:PivotTo(targetCFrame)

	-- Restore network ownership to the player (if this is a player character)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		-- Apply network ownership to all collider parts
		CharacterLocations:ForEachColliderPart(character, function(part)
			pcall(function()
				part:SetNetworkOwner(player)
			end)
		end)
	end

	-- Re-enable VectorForce if it was enabled before
	if vectorForce and wasEnabled then
		vectorForce.Enabled = true
	end

	return true
end

function CharacterUtils:GetCharacterPosition(character)
	if not character.PrimaryPart then
		return Vector3.new(0, 0, 0)
	end

	local feetPart = CharacterLocations:GetFeet(character)

	if feetPart then
		local feetPosition = feetPart.Position
		local feetSize = feetPart.Size
		return feetPosition - Vector3.new(0, feetSize.Y / 2, 0)
	else
		return character.PrimaryPart.Position
	end
end

function CharacterUtils:IsCharacterValid(character)
	return ValidationUtils:IsCharacterValid(character)
end

function CharacterUtils:SetupPhysics(primaryPart, _config)
	return MovementUtils:SetupPhysicsConstraints(primaryPart)
end

function CharacterUtils:RotateCharacterToCamera(primaryPart, cameraYAngle, _movementInput, _deltaTime)
	if not ValidationUtils:IsPrimaryPartValid(primaryPart) then
		return
	end

	MovementUtils:SetCharacterRotation(primaryPart.AlignOrientation, cameraYAngle)
end

function CharacterUtils:ConfigurePhysicsProperties(character)
	if not self:IsCharacterValid(character) then
		return
	end

	-- Apply CustomPhysicalProperties from config to all character parts
	local physicsProps = Config.Gameplay.Character.CustomPhysicalProperties
	if not physicsProps then
		return
	end

	-- Create Roblox PhysicalProperties object
	local customProperties = PhysicalProperties.new(
		physicsProps.Density,
		physicsProps.Friction,
		physicsProps.Elasticity,
		physicsProps.FrictionWeight,
		physicsProps.ElasticityWeight
	)

	-- Apply to ALL descendants (covers everything: Root, Collider parts, Rig parts, voice chat parts, accessories)
	for _, descendant in pairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CustomPhysicalProperties = customProperties
		end
	end
end

function CharacterUtils:ApplyNetworkOwnership(character, player)
	if not self:IsCharacterValid(character) then
		return
	end

	-- Apply network ownership to all parts in the character's Collider models
	CharacterLocations:ForEachColliderPart(character, function(part)
		local success, error = pcall(function()
			part.Anchored = false
			part:SetNetworkOwner(player)
		end)

		if not success then
			Log:Warn("CHAR_UTILS", "Failed to set ownership for collider part", {
				Part = part.Name,
				Error = error,
			})
		end
	end)

	-- Apply network ownership to all Rig parts (for smooth movement on client)
	local rigHumanoidRootPart = CharacterLocations:GetRigHumanoidRootPart(character)
	CharacterLocations:ForEachRigPart(character, function(rigPart)
		-- Skip the Rig's HumanoidRootPart - it's client-controlled separately
		if rigPart == rigHumanoidRootPart then
			return
		end

		local success, error = pcall(function()
			rigPart.Anchored = false
			rigPart:SetNetworkOwner(player)
		end)

		if not success then
			Log:Warn("CHAR_UTILS", "Failed to set ownership for rig part", {
				Part = rigPart.Name,
				Error = error,
			})
		end
	end)
end

-- Common physics constraint setup utility
function CharacterUtils:SetupBasicMovementConstraints(primaryPart, constraintNamePrefix)
	if not primaryPart then
		return nil, nil, nil, nil
	end

	constraintNamePrefix = constraintNamePrefix or ""

	-- Create or get attachment
	local attachment = self:GetOrCreateAttachment(primaryPart, constraintNamePrefix .. "Attachment")

	-- Create or get AlignOrientation for character rotation
	local alignOrientationName = constraintNamePrefix .. "AlignOrientation"
	local alignOrientation = primaryPart:FindFirstChild(alignOrientationName)
	if not alignOrientation then
		alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = alignOrientationName
		alignOrientation.Attachment0 = attachment
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.PrimaryAxisOnly = false
		alignOrientation.MaxTorque = 40000
		alignOrientation.Responsiveness = 15
		alignOrientation.RigidityEnabled = true
		alignOrientation.Parent = primaryPart
	end

	-- Create or get movement constraint (BodyVelocity for NPCs, VectorForce for players)
	local movementConstraintName = constraintNamePrefix .. "BodyVelocity"
	local bodyVelocity = primaryPart:FindFirstChild(movementConstraintName)
	if not bodyVelocity then
		bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Name = movementConstraintName
		bodyVelocity.MaxForce = Vector3.new(4000, 0, 4000) -- Only apply horizontal force
		bodyVelocity.Velocity = Vector3.new(0, 0, 0)
		bodyVelocity.Parent = primaryPart
	end

	return attachment, alignOrientation, bodyVelocity
end

-- Helper function to get or create an attachment on a part
function CharacterUtils:GetOrCreateAttachment(part, attachmentName)
	if not part then
		return nil
	end

	local attachment = part:FindFirstChild(attachmentName)
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = attachmentName
		attachment.Parent = part
	end

	return attachment
end

function CharacterUtils:RestorePrimaryPartAfterClone(characterModel, characterTemplate)
	-- Restore PrimaryPart reference after cloning (required because cloning breaks the reference)
	local primaryPart = nil

	if characterTemplate.PrimaryPart then
		local primaryPartName = characterTemplate.PrimaryPart.Name
		primaryPart = characterModel:FindFirstChild(primaryPartName)
		if primaryPart then
			characterModel.PrimaryPart = primaryPart
		end
	end

	if not primaryPart then
		-- Fallback: prioritize Root part first, then other options
		local possibleNames = { "Root", "HumanoidRootPart", "Torso", "UpperTorso" }
		for _, name in ipairs(possibleNames) do
			primaryPart = characterModel:FindFirstChild(name)
			if primaryPart then
				characterModel.PrimaryPart = primaryPart
				break
			end
		end
	end

	if not primaryPart then
		Log:Warn("CHAR_UTILS", "Could not find primary part for character", {
			Character = characterModel.Name,
		})
	end

	return primaryPart
end

return CharacterUtils
