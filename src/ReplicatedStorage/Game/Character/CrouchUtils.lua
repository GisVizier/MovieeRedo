local CrouchUtils = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local WeldUtils = require(Locations.Shared.Util:WaitForChild("WeldUtils"))
local CollisionUtils = require(Locations.Shared.Util:WaitForChild("CollisionUtils"))

CrouchUtils.CharacterCrouchState = {}

local DEFAULT_CROUCH_HEIGHT_REDUCTION = 2

function CrouchUtils:SetupRigOnlyWelds(character)
	if not character or not character.PrimaryPart then
		return false
	end

	local root = character.PrimaryPart
	local rigHumanoidRootPart = CharacterLocations:GetRigHumanoidRootPart(character)

	if not rigHumanoidRootPart then
		return false
	end

	-- Apply collision settings to all rig parts
	CharacterLocations:ForEachRigPart(character, function(rigPart)
		rigPart.Massless = true
		rigPart.CanCollide = false
		rigPart.CanQuery = false
		rigPart.CanTouch = false
	end)

	-- Keep the rig HRP anchored (v1 behavior + matches RigManager enforcement).
	-- Welds still work with anchored parts.
	rigHumanoidRootPart.Anchored = true
	
	-- BULLETPROOF: Use CollisionUtils to ensure rig NEVER has collision enabled.
	-- This catches any changes from ApplyDescription or replication.
	local rig = CharacterLocations:GetRig(character)
	if rig and not CollisionUtils:IsEnsuringNonCollideable(rig) then
		CollisionUtils:EnsureNonCollideable(rig, {
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Massless = true,
			UseHeartbeat = true,
			HeartbeatInterval = 0.25,
		})
	end

	local offsetCFrame = CFrame.new()
	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if characterTemplate then
		local templateRoot = characterTemplate:FindFirstChild("Root")
		local templateRig = characterTemplate:FindFirstChild("Rig")
		local templateRigHRP = templateRig and templateRig:FindFirstChild("HumanoidRootPart")

		if templateRoot and templateRigHRP then
			offsetCFrame = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
		end
	end

	local success = pcall(function()
		WeldUtils:CreateWeld(root, rigHumanoidRootPart, "RigWeld", offsetCFrame, CFrame.new())
	end)

	if not success then
		return false
	end

	return true
end

function CrouchUtils:SetupHitboxWelds(character)
	if not character or not character.PrimaryPart then
		return false
	end

	local hitboxFolder = character:FindFirstChild("Hitbox")
	local rig = CharacterLocations:GetRig(character)

	if not hitboxFolder or not rig then
		return false
	end

	local hitboxToRigMapping = {
		Body = "Torso",
		Head = "Head",
		LeftLeg = "Left Leg",
		RightLeg = "Right Leg",
		LeftArm = "Left Arm",
		RightArm = "Right Arm",
	}

	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not characterTemplate then
		return false
	end

	local templateHitbox = characterTemplate:FindFirstChild("Hitbox")
	local templateRig = characterTemplate:FindFirstChild("Rig")

	if not templateHitbox or not templateRig then
		return false
	end

	for hitboxPartName, rigPartName in pairs(hitboxToRigMapping) do
		local hitboxPart = hitboxFolder:FindFirstChild(hitboxPartName)
		local rigPart = rig:FindFirstChild(rigPartName)

		if hitboxPart and rigPart then
			local templateHitboxPart = templateHitbox:FindFirstChild(hitboxPartName)
			local templateRigPart = templateRig:FindFirstChild(rigPartName)

			local offsetCFrame = CFrame.new()
			if templateHitboxPart and templateRigPart then
				offsetCFrame = templateRigPart.CFrame:Inverse() * templateHitboxPart.CFrame
			end

			hitboxPart.Massless = true
			hitboxPart.CanCollide = false
			hitboxPart.CanQuery = true
			hitboxPart.CanTouch = true
			hitboxPart.Anchored = false

			pcall(function()
				WeldUtils:CreateWeld(rigPart, hitboxPart, hitboxPartName .. "HitboxWeld", offsetCFrame, CFrame.new())
			end)
		else
			if not hitboxPart then
			end
			if not rigPart then
			end
		end
	end

	return true
end

function CrouchUtils:SetupLegacyWelds(character)
	if not character or not character.PrimaryPart then
		return false
	end

	local root = character.PrimaryPart
	local body = CharacterLocations:GetBody(character)
	local feet = CharacterLocations:GetFeet(character)
	local head = CharacterLocations:GetHead(character)
	local crouchBody = CharacterLocations:GetCrouchBody(character)
	local crouchHead = CharacterLocations:GetCrouchHead(character)
	local collisionHead = CharacterLocations:GetCollisionHead(character)
	local collisionBody = CharacterLocations:GetCollisionBody(character)

	local humanoidRootPart = CharacterLocations:GetHumanoidRootPart(character)

	if not body or not feet or not head or not crouchBody or not crouchHead then
		return false
	end

	local hasCollisionParts = collisionHead ~= nil and collisionBody ~= nil
	local hasHumanoidParts = humanoidRootPart ~= nil

	CharacterLocations:ForEachColliderPart(character, function(part)
		if part ~= root then
			for _, constraint in pairs(part:GetChildren()) do
				if constraint:IsA("WeldConstraint") then
					constraint:Destroy()
				end
			end
		end
	end)

	WeldUtils:CreateBeanShapeWeld(root, body, "BodyWeld", CFrame.new(0, 0, 0))
	WeldUtils:CreateWeld(root, feet, "FeetWeld", CFrame.new(0, -1.25, 0), CFrame.new(0, 0, 0))
	WeldUtils:CreateWeld(root, head, "HeadWeld", CFrame.new(0, 1.25, 0), CFrame.new(0, 0, 0))

	local heightReduction = (Config.Gameplay and Config.Gameplay.Character and Config.Gameplay.Character.CrouchHeightReduction)
		or DEFAULT_CROUCH_HEIGHT_REDUCTION

	crouchBody.Size = Vector3.new(
		body.Size.X - heightReduction,
		body.Size.Y,
		body.Size.Z
	)

	WeldUtils:CreateBeanShapeWeld(root, crouchBody, "CrouchBodyWeld", CFrame.new(0, -heightReduction / 2, 0))
	WeldUtils:CreateWeld(
		root,
		crouchHead,
		"CrouchHeadWeld",
		CFrame.new(0, 1.25 - heightReduction, 0),
		CFrame.new(0, 0, 0)
	)

	if hasCollisionParts then
		WeldUtils:CreateBeanShapeWeld(root, collisionBody, "CollisionBodyWeld", CFrame.new(0, 0, 0))
		WeldUtils:CreateWeld(root, collisionHead, "CollisionHeadWeld", CFrame.new(0, 1.25, 0), CFrame.new(0, 0, 0))

		collisionBody.Transparency = 1
		collisionBody.CanCollide = false
		collisionHead.Transparency = 1
		collisionHead.CanCollide = false
	end

	if hasHumanoidParts then
		local humanoidHead = CharacterLocations:GetHumanoidHead(character)

		humanoidRootPart.Massless = true
		humanoidRootPart.CanCollide = false
		humanoidRootPart.CanQuery = false
		humanoidRootPart.CanTouch = false
		humanoidRootPart.Transparency = 1
		humanoidRootPart.Anchored = true

		if humanoidHead then
			humanoidHead.Massless = true
			humanoidHead.CanCollide = false
			humanoidHead.CanQuery = false
			humanoidHead.CanTouch = false
			humanoidHead.Transparency = 1
			humanoidHead.Anchored = true
		end
	end

	local rigHumanoidRootPart = CharacterLocations:GetRigHumanoidRootPart(character)
	if rigHumanoidRootPart then
		CharacterLocations:ForEachRigPart(character, function(rigPart)
			rigPart.Massless = true
			rigPart.CanCollide = false
			rigPart.CanQuery = false
			rigPart.CanTouch = false
		end)

		rigHumanoidRootPart.Anchored = true
	end

	body.Transparency = 0
	body.CanCollide = true
	body.CanQuery = true
	head.Transparency = 0
	head.CanCollide = true
	head.CanQuery = true
	crouchBody.Transparency = 1
	crouchBody.CanCollide = false
	crouchBody.CanQuery = false
	crouchHead.Transparency = 1
	crouchHead.CanCollide = false
	crouchHead.CanQuery = false

	self.CharacterCrouchState[character] = {
		IsCrouched = false,
	}

	return true
end

function CrouchUtils:CleanupWelds(character)
	self.CharacterCrouchState[character] = nil
end

function CrouchUtils:Crouch(character)
	local crouchData = self.CharacterCrouchState[character]
	if not crouchData or crouchData.IsCrouched then
		return false
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return false
	end

	crouchData.IsCrouched = true
	return true
end

function CrouchUtils:Uncrouch(character)
	local crouchData = self.CharacterCrouchState[character]
	if not crouchData or not crouchData.IsCrouched then
		return false
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return false
	end

	crouchData.IsCrouched = false
	return true
end

function CrouchUtils:IsCrouched(character)
	local crouchData = self.CharacterCrouchState[character]
	return crouchData and crouchData.IsCrouched or false
end

function CrouchUtils:ToggleCrouch(character)
	return self:IsCrouched(character) and self:Uncrouch(character) or self:Crouch(character)
end

function CrouchUtils:ApplyVisualCrouch(character, skipClearanceCheck)
	local body = CharacterLocations:GetBody(character)
	local head = CharacterLocations:GetHead(character)
	local crouchBody = CharacterLocations:GetCrouchBody(character)
	local crouchHead = CharacterLocations:GetCrouchHead(character)

	if not body or not head or not crouchBody or not crouchHead then
		return false
	end

	if not skipClearanceCheck and not self:CanCrouch(character) then
		return false
	end

	local primaryPart = character.PrimaryPart
	if primaryPart then
		local currentVelocity = primaryPart.AssemblyLinearVelocity
		if currentVelocity.Y > 5 then
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = { character }
			raycastParams.RespectCanCollide = true

			local feetPart = CharacterLocations:GetFeet(character) or primaryPart
			local rayOrigin = feetPart.Position
			local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -2, 0), raycastParams)

			if not rayResult then
				primaryPart.AssemblyLinearVelocity = Vector3.new(
					currentVelocity.X,
					math.min(currentVelocity.Y * 0.3, 2),
					currentVelocity.Z
				)
			end
		end
	end

	body.Transparency = 1
	body.CanCollide = false
	body.CanQuery = false
	head.Transparency = 1
	head.CanCollide = false
	head.CanQuery = false
	crouchBody.Transparency = 0
	crouchBody.CanCollide = true
	crouchBody.CanQuery = true
	crouchHead.Transparency = 0
	crouchHead.CanCollide = true
	crouchHead.CanQuery = true

	return true
end

function CrouchUtils:RemoveVisualCrouch(character)
	local body = CharacterLocations:GetBody(character)
	local head = CharacterLocations:GetHead(character)
	local crouchBody = CharacterLocations:GetCrouchBody(character)
	local crouchHead = CharacterLocations:GetCrouchHead(character)

	if not body or not head or not crouchBody or not crouchHead then
		return false
	end

	body.Transparency = 0
	body.CanCollide = true
	body.CanQuery = true
	head.Transparency = 0
	head.CanCollide = true
	head.CanQuery = true
	crouchBody.Transparency = 1
	crouchBody.CanCollide = false
	crouchBody.CanQuery = false
	crouchHead.Transparency = 1
	crouchHead.CanCollide = false
	crouchHead.CanQuery = false

	return true
end

function CrouchUtils:CanCrouch(character)
	if not character then
		return false
	end

	local crouchHead = CharacterLocations:GetCrouchHead(character)
	local crouchBody = CharacterLocations:GetCrouchBody(character)
	if not crouchHead or not crouchBody then
		return false
	end

	local excluded = { character }
	local rig = CharacterLocations:GetRig(character)
	if rig then
		table.insert(excluded, rig)
	end
	local rigsFolder = workspace:FindFirstChild("Rigs")
	if rigsFolder then
		table.insert(excluded, rigsFolder)
	end

	local overlapParams = CollisionUtils:CreateExclusionOverlapParams(excluded)
	local headObstructions = workspace:GetPartsInPart(crouchHead, overlapParams)
	local bodyObstructions = workspace:GetPartsInPart(crouchBody, overlapParams)

	return #headObstructions == 0 and #bodyObstructions == 0
end

function CrouchUtils:CanUncrouch(character)
	if not character then
		return false
	end

	local normalHead = CharacterLocations:GetHead(character)
	local normalBody = CharacterLocations:GetBody(character)
	if not normalHead or not normalBody then
		return false
	end

	local excluded = { character }
	local rig = CharacterLocations:GetRig(character)
	if rig then
		table.insert(excluded, rig)
	end
	local rigsFolder = workspace:FindFirstChild("Rigs")
	if rigsFolder then
		table.insert(excluded, rigsFolder)
	end

	local overlapParams = CollisionUtils:CreateExclusionOverlapParams(excluded)
	local headObstructions = workspace:GetPartsInPart(normalHead, overlapParams)
	local bodyObstructions = workspace:GetPartsInPart(normalBody, overlapParams)

	return #headObstructions == 0 and #bodyObstructions == 0
end

function CrouchUtils:IsVisuallycrouched(character)
	local crouchHead = CharacterLocations:GetCrouchHead(character)
	return crouchHead and crouchHead.Transparency < 1
end

return CrouchUtils
