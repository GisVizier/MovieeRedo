local CrouchUtils = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local Config = require(Locations.Modules.Config)
local WeldUtils = require(Locations.Modules.Utils.WeldUtils)
local CollisionUtils = require(Locations.Modules.Utils.CollisionUtils)

CrouchUtils.CharacterCrouchState = {}

-- Simplified weld setup for other players (only Rig, no collider parts)
function CrouchUtils:SetupRigOnlyWelds(character)
	if not character or not character.PrimaryPart then
		return false
	end

	local root = character.PrimaryPart
	local rigHumanoidRootPart = CharacterLocations:GetRigHumanoidRootPart(character)

	if not rigHumanoidRootPart then
		return false
	end

	-- Make all rig parts massless and non-colliding FIRST
	CharacterLocations:ForEachRigPart(character, function(rigPart)
		rigPart.Massless = true
		rigPart.CanCollide = false
		rigPart.CanQuery = false
		rigPart.CanTouch = false
	end)

	-- Unanchor the Rig's HumanoidRootPart so the weld can work
	rigHumanoidRootPart.Anchored = false

	-- Calculate offset from Root to Rig's HumanoidRootPart based on character template
	-- This ensures the Rig maintains its proper Y-position relative to the collision parts
	local offsetCFrame = CFrame.new()

	-- Get character template to calculate the original offset
	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if characterTemplate then
		local templateRoot = characterTemplate:FindFirstChild("Root")
		local templateRig = characterTemplate:FindFirstChild("Rig")
		local templateRigHRP = templateRig and templateRig:FindFirstChild("HumanoidRootPart")

		if templateRoot and templateRigHRP then
			-- Calculate relative offset in template's space
			offsetCFrame = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
		end
	end

	-- Weld Rig's HumanoidRootPart to Root with proper offset
	local success, err = pcall(function()
		WeldUtils:CreateWeld(root, rigHumanoidRootPart, "RigWeld", offsetCFrame, CFrame.new())
	end)

	if not success then
		warn("Failed to create Rig weld for other player:", err)
		return false
	end

	return true
end

-- Setup hitbox welds for replicated characters (other players only)
function CrouchUtils:SetupHitboxWelds(character)
	if not character or not character.PrimaryPart then
		return false
	end

	local hitboxFolder = character:FindFirstChild("Hitbox")
	local rig = CharacterLocations:GetRig(character)

	if not hitboxFolder or not rig then
		return false
	end

	-- Mapping of hitbox parts to rig parts
	local hitboxToRigMapping = {
		Body = "Torso",
		Head = "Head",
		LeftLeg = "Left Leg",
		RightLeg = "Right Leg",
		LeftArm = "Left Arm",
		RightArm = "Right Arm",
	}

	-- Get character template to calculate proper offsets
	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not characterTemplate then
		warn("CharacterTemplate not found in ReplicatedStorage")
		return false
	end

	local templateHitbox = characterTemplate:FindFirstChild("Hitbox")
	local templateRig = characterTemplate:FindFirstChild("Rig")

	if not templateHitbox or not templateRig then
		warn("CharacterTemplate missing Hitbox or Rig model")
		return false
	end

	-- Weld each hitbox part to its corresponding rig part
	for hitboxPartName, rigPartName in pairs(hitboxToRigMapping) do
		local hitboxPart = hitboxFolder:FindFirstChild(hitboxPartName)
		local rigPart = rig:FindFirstChild(rigPartName)

		if hitboxPart and rigPart then
			-- Calculate offset from template
			local templateHitboxPart = templateHitbox:FindFirstChild(hitboxPartName)
			local templateRigPart = templateRig:FindFirstChild(rigPartName)

			local offsetCFrame = CFrame.new()
			if templateHitboxPart and templateRigPart then
				-- Calculate relative offset: rigPart's inverse * hitboxPart position
				offsetCFrame = templateRigPart.CFrame:Inverse() * templateHitboxPart.CFrame
			end

			-- Configure hitbox part properties
			hitboxPart.Massless = true
			hitboxPart.CanCollide = false
			hitboxPart.CanQuery = true -- Enable for raycasting/hit detection
			hitboxPart.CanTouch = true -- Enable for touch-based hit detection
			hitboxPart.Anchored = false -- Must be unanchored for weld to work

			-- Create weld from rig part to hitbox part
			local success, err = pcall(function()
				WeldUtils:CreateWeld(rigPart, hitboxPart, hitboxPartName .. "HitboxWeld", offsetCFrame, CFrame.new())
			end)

			if not success then
				warn("Failed to create hitbox weld for", hitboxPartName, ":", err)
			end
		else
			if not hitboxPart then
				warn("Hitbox part not found:", hitboxPartName)
			end
			if not rigPart then
				warn("Rig part not found:", rigPartName)
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

	-- Humanoid parts for VC only
	local humanoidRootPart = CharacterLocations:GetHumanoidRootPart(character)

	-- Required parts for all characters
	if not body or not feet or not head or not crouchBody or not crouchHead then
		return false
	end

	-- Collision parts are optional - only exist for local player
	local hasCollisionParts = collisionHead ~= nil and collisionBody ~= nil

	-- Humanoid parts are optional - only set up if HumanoidRootPart exists (no Head needed for VC)
	local hasHumanoidParts = humanoidRootPart ~= nil

	-- Remove existing WeldConstraints from all collider parts
	CharacterLocations:ForEachColliderPart(character, function(part)
		if part ~= root then
			for _, constraint in pairs(part:GetChildren()) do
				if constraint:IsA("WeldConstraint") then
					constraint:Destroy()
				end
			end
		end
	end)

	-- Create legacy Welds for character structure
	WeldUtils:CreateBeanShapeWeld(root, body, "BodyWeld", CFrame.new(0, 0, 0))
	WeldUtils:CreateWeld(root, feet, "FeetWeld", CFrame.new(0, -1.25, 0), CFrame.new(0, 0, 0))
	WeldUtils:CreateWeld(root, head, "HeadWeld", CFrame.new(0, 1.25, 0), CFrame.new(0, 0, 0))

	-- Calculate shortened positions automatically
	local heightReduction = Config.Gameplay.Character.CrouchHeightReduction

	-- Scale down the crouch body
	crouchBody.Size = Vector3.new(
		body.Size.X - heightReduction, -- Reduce height (X-axis due to 90° rotation)
		body.Size.Y,
		body.Size.Z
	)

	-- Position crouch body lower to keep bottom edge in same place
	WeldUtils:CreateBeanShapeWeld(root, crouchBody, "CrouchBodyWeld", CFrame.new(0, -heightReduction / 2, 0))

	-- Position crouch head to sit on top of shortened body
	WeldUtils:CreateWeld(
		root,
		crouchHead,
		"CrouchHeadWeld",
		CFrame.new(0, 1.25 - heightReduction, 0),
		CFrame.new(0, 0, 0)
	)

	-- Setup collision parts (invisible, used only for uncrouch collision detection)
	-- Only for local player - other players don't have these parts
	if hasCollisionParts then
		WeldUtils:CreateBeanShapeWeld(root, collisionBody, "CollisionBodyWeld", CFrame.new(0, 0, 0))
		WeldUtils:CreateWeld(root, collisionHead, "CollisionHeadWeld", CFrame.new(0, 1.25, 0), CFrame.new(0, 0, 0))

		-- Make collision parts transparent and non-collidable
		collisionBody.Transparency = 1
		collisionBody.CanCollide = false
		collisionHead.Transparency = 1
		collisionHead.CanCollide = false
	end

	-- Setup Humanoid parts (HumanoidRootPart, Head) for local player
	-- NO LONGER WELDED - synced via BulkMoveTo in ClientReplicator for zero physics interference
	if hasHumanoidParts then
		local humanoidHead = CharacterLocations:GetHumanoidHead(character)

		-- Make humanoid parts massless and non-colliding
		humanoidRootPart.Massless = true
		humanoidRootPart.CanCollide = false
		humanoidRootPart.CanQuery = false
		humanoidRootPart.CanTouch = false
		humanoidRootPart.Transparency = 1
		humanoidRootPart.Anchored = true -- CRITICAL: Must be anchored for BulkMoveTo to work properly

		if humanoidHead then
			humanoidHead.Massless = true
			humanoidHead.CanCollide = false
			humanoidHead.CanQuery = false
			humanoidHead.CanTouch = false
			humanoidHead.Transparency = 1
			humanoidHead.Anchored = true -- CRITICAL: Must be anchored for BulkMoveTo to work properly
		end

		-- NO WELDS - BulkMoveTo handles syncing to Root every frame
	end

	-- Setup Rig parts - NO LONGER WELDED
	-- Synced via BulkMoveTo in ClientReplicator to eliminate Humanoid mass interference
	local rigHumanoidRootPart = CharacterLocations:GetRigHumanoidRootPart(character)
	if rigHumanoidRootPart then
		-- Make all rig parts massless and non-colliding FIRST
		CharacterLocations:ForEachRigPart(character, function(rigPart)
			rigPart.Massless = true
			rigPart.CanCollide = false
			rigPart.CanQuery = false
			rigPart.CanTouch = false
		end)

		-- CRITICAL: Anchor the Rig's HumanoidRootPart so it doesn't fall through world
		-- BulkMoveTo works with anchored parts (it just sets CFrame every frame)
		rigHumanoidRootPart.Anchored = true

		-- NO WELDS - BulkMoveTo handles syncing to Root every frame
	end

	-- Ensure proper initial visual state: show normal parts, hide crouch parts
	body.Transparency = 0
	body.CanCollide = true
	head.Transparency = 0
	head.CanCollide = true
	crouchBody.Transparency = 1
	crouchBody.CanCollide = false
	crouchHead.Transparency = 1
	crouchHead.CanCollide = false

	-- Store crouch state only
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

	-- Find the player who owns this character
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return false
	end

	-- Just update crouch state - visual crouch is handled by MovementStateManager
	crouchData.IsCrouched = true

	return true
end

function CrouchUtils:Uncrouch(character)
	local crouchData = self.CharacterCrouchState[character]
	if not crouchData or not crouchData.IsCrouched then
		return false
	end

	-- Find the player who owns this character
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return false
	end

	-- Just update crouch state - visual crouch removal is handled by MovementStateManager
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

-- VISUAL CROUCH UTILITIES (can be used independently of crouch state)
function CrouchUtils:ApplyVisualCrouch(character, skipClearanceCheck)
	local body = CharacterLocations:GetBody(character)
	local head = CharacterLocations:GetHead(character)
	local crouchBody = CharacterLocations:GetCrouchBody(character)
	local crouchHead = CharacterLocations:GetCrouchHead(character)

	if not body or not head or not crouchBody or not crouchHead then
		return false
	end

	-- Check clearance for crouched collision unless explicitly skipped
	if not skipClearanceCheck and not self:CanCrouch(character) then
		return false
	end

	-- Dampen velocity when near edges to prevent physics flinging
	local primaryPart = character.PrimaryPart
	if primaryPart then
		local currentVelocity = primaryPart.AssemblyLinearVelocity
		-- Only dampen if there's significant upward velocity that could cause issues
		if currentVelocity.Y > 5 then
			-- Check if we're near an edge (not fully grounded)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = { character }
			raycastParams.RespectCanCollide = true

			local feetPart = CharacterLocations:GetFeet(character) or primaryPart
			local rayOrigin = feetPart.Position
			local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -2, 0), raycastParams)

			-- If no ground directly below, we're near an edge - dampen velocity
			if not rayResult then
				primaryPart.AssemblyLinearVelocity = Vector3.new(
					currentVelocity.X,
					math.min(currentVelocity.Y * 0.3, 2),
					currentVelocity.Z
				)
			end
		end
	end

	-- Hide normal parts
	body.Transparency = 1
	body.CanCollide = false
	head.Transparency = 1
	head.CanCollide = false

	-- Show crouch parts
	crouchBody.Transparency = 0
	crouchBody.CanCollide = true
	crouchHead.Transparency = 0
	crouchHead.CanCollide = true

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

	-- Create OverlapParams to exclude character parts and respect actual geometry
	local overlapParams = CollisionUtils:CreateExclusionOverlapParams({ character })

	-- Use GetPartsInPart for accurate geometry collision detection using crouch parts
	local headObstructions = workspace:GetPartsInPart(crouchHead, overlapParams)
	local bodyObstructions = workspace:GetPartsInPart(crouchBody, overlapParams)

	-- If any parts found, there's an obstruction
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

	-- Create OverlapParams to exclude character parts and respect actual geometry
	local overlapParams = CollisionUtils:CreateExclusionOverlapParams({ character })

	-- Use GetPartsInPart for accurate geometry collision detection using normal parts
	local headObstructions = workspace:GetPartsInPart(normalHead, overlapParams)
	local bodyObstructions = workspace:GetPartsInPart(normalBody, overlapParams)

	-- If any parts found, there's an obstruction
	return #headObstructions == 0 and #bodyObstructions == 0
end

function CrouchUtils:RemoveVisualCrouch(character)
	local body = CharacterLocations:GetBody(character)
	local head = CharacterLocations:GetHead(character)
	local crouchBody = CharacterLocations:GetCrouchBody(character)
	local crouchHead = CharacterLocations:GetCrouchHead(character)

	if not body or not head or not crouchBody or not crouchHead then
		return false
	end

	-- Show normal parts
	body.Transparency = 0
	body.CanCollide = true
	head.Transparency = 0
	head.CanCollide = true

	-- Hide crouch parts
	crouchBody.Transparency = 1
	crouchBody.CanCollide = false
	crouchHead.Transparency = 1
	crouchHead.CanCollide = false

	return true
end

function CrouchUtils:IsVisuallycrouched(character)
	local crouchHead = CharacterLocations:GetCrouchHead(character)
	return crouchHead and crouchHead.Transparency < 1
end

return CrouchUtils
