local CharacterLocations = {}

function CharacterLocations:GetRoot(character)
	if not character or not character.Parent then
		return nil
	end
	return character:FindFirstChild("Root")
end

function CharacterLocations:GetBody(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	local default = collider and collider:FindFirstChild("Default")
	return default and default:FindFirstChild("Body")
end

function CharacterLocations:GetFeet(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	local default = collider and collider:FindFirstChild("Default")
	return default and default:FindFirstChild("Feet")
end

function CharacterLocations:GetHead(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	local default = collider and collider:FindFirstChild("Default")
	return default and default:FindFirstChild("Head")
end

function CharacterLocations:GetCrouchBody(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	local crouch = collider and collider:FindFirstChild("Crouch")
	return crouch and crouch:FindFirstChild("CrouchBody")
end

function CharacterLocations:GetCrouchHead(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	local crouch = collider and collider:FindFirstChild("Crouch")
	return crouch and crouch:FindFirstChild("CrouchHead")
end

function CharacterLocations:GetCollisionHead(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	local uncrouch = collider and collider:FindFirstChild("UncrouchCheck")
	return uncrouch and uncrouch:FindFirstChild("CollisionHead")
end

function CharacterLocations:GetCollisionBody(character)
	if not character or not character.Parent then
		return nil
	end
	local collider = character:FindFirstChild("Collider")
	local uncrouch = collider and collider:FindFirstChild("UncrouchCheck")
	return uncrouch and uncrouch:FindFirstChild("CollisionBody")
end

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
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "Head" and child.Parent == character then
			return child
		end
	end
	return nil
end

function CharacterLocations:GetRig(character)
	if not character or not character.Parent then
		return nil
	end

	local rigInCharacter = character:FindFirstChild("Rig")
	if rigInCharacter then
		return rigInCharacter
	end

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
	local RigManager = require(Locations.Game:WaitForChild("Character"):WaitForChild("Rig"):WaitForChild("RigManager"))

	return RigManager:GetRigForCharacter(character)
end

function CharacterLocations:GetRigHumanoidRootPart(character)
	local rig = self:GetRig(character)
	return rig and rig:FindFirstChild("HumanoidRootPart") or nil
end

function CharacterLocations:ForEachRigPart(character, callback)
	if not character or not character.Parent or not callback then
		return
	end

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

function CharacterLocations:ForEachColliderPart(character, callback)
	if not character or not character.Parent or not callback then
		return
	end

	local collider = character:FindFirstChild("Collider")
	if not collider then
		return
	end

	-- Legacy: Collider/Default, Collider/Crouch (Models)
	for _, colliderModel in pairs(collider:GetChildren()) do
		if colliderModel:IsA("Model") then
			for _, part in pairs(colliderModel:GetChildren()) do
				if part:IsA("BasePart") then
					callback(part, colliderModel.Name)
				end
			end
		end
	end

	-- New structure: Collider/Hitbox/Standing, Collider/Hitbox/Crouching (Models or Folders)
	local hitboxFolder = collider:FindFirstChild("Hitbox")
	if hitboxFolder then
		for _, stanceFolder in ipairs({ "Standing", "Crouching" }) do
			local folder = hitboxFolder:FindFirstChild(stanceFolder)
			if folder then
				for _, part in pairs(folder:GetChildren()) do
					if part:IsA("BasePart") then
						callback(part, stanceFolder)
					end
				end
			end
		end
	end
end

return CharacterLocations
