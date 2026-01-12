local CharacterUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))

function CharacterUtils:RestorePrimaryPartAfterClone(characterModel, characterTemplate)
	local primaryPart = nil

	if characterTemplate.PrimaryPart then
		local primaryPartName = characterTemplate.PrimaryPart.Name
		primaryPart = characterModel:FindFirstChild(primaryPartName)
		if primaryPart then
			characterModel.PrimaryPart = primaryPart
		end
	end

	if not primaryPart then
		local possibleNames = { "Root", "HumanoidRootPart", "Torso", "UpperTorso" }
		for _, name in ipairs(possibleNames) do
			primaryPart = characterModel:FindFirstChild(name)
			if primaryPart then
				characterModel.PrimaryPart = primaryPart
				break
			end
		end
	end

	return primaryPart
end

function CharacterUtils:ConfigurePhysicsProperties(character)
	if not character or not character.Parent then
		return
	end

	local physicsProps = Config.Gameplay.Character.CustomPhysicalProperties
	if not physicsProps then
		return
	end

	local customProperties = PhysicalProperties.new(
		physicsProps.Density,
		physicsProps.Friction,
		physicsProps.Elasticity,
		physicsProps.FrictionWeight,
		physicsProps.ElasticityWeight
	)

	for _, descendant in pairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CustomPhysicalProperties = customProperties
		end
	end
end

return CharacterUtils
