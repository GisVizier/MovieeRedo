local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Net = require(Locations.Shared.Net.Net)
local Loader = require(Locations.Shared.Util.Loader)
local Registry = require(script.Parent:WaitForChild("Registry"):WaitForChild("Registry"))

Net:Init()

do
	local existing = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not existing then
		local modelsFolder = ServerStorage:WaitForChild("Models")
		local template = modelsFolder:WaitForChild("Character")
		local clone = template:Clone()
		clone.Name = "CharacterTemplate"
		clone.Parent = ReplicatedStorage
	end
end

local registry = Registry.new()

local servicesFolder = script.Parent:WaitForChild("Services")
local entries = {
	{
		name = "CollisionGroupService",
		module = servicesFolder:WaitForChild("Collision"):WaitForChild("CollisionGroupService"),
	},
	{
		name = "CharacterService",
		module = servicesFolder:WaitForChild("Character"):WaitForChild("CharacterService"),
	},
	{
		name = "ReplicationService",
		module = servicesFolder:WaitForChild("Replication"):WaitForChild("ReplicationService"),
	},
	{
		name = "MovementService",
		module = servicesFolder:WaitForChild("Movement"):WaitForChild("MovementService"),
	},
}

Loader:Load(entries, registry, Net)

do
	local collisionGroupService = registry:TryGet("CollisionGroupService")
	if collisionGroupService then
		local template = ReplicatedStorage:FindFirstChild("CharacterTemplate")
		if template then
			collisionGroupService:SetCharacterCollisionGroup(template)
		end

		local modelsFolder = ServerStorage:FindFirstChild("Models")
		local serverTemplate = modelsFolder and modelsFolder:FindFirstChild("Character")
		if serverTemplate then
			collisionGroupService:SetCharacterCollisionGroup(serverTemplate)
		end
	end
end
