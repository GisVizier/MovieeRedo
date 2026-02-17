local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Net = require(Locations.Shared.Net.Net)
local Loader = require(Locations.Shared.Util.Loader)
local Registry = require(script.Parent:WaitForChild("Registry"):WaitForChild("Registry"))

Net:Init()

-- Initialize VoxelDestruction early so its _ClientDestruction RemoteEvent is created
-- before any client tries to WaitForChild for it. Without this, clients that load the
-- module at startup get an infinite yield.
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("VoxelDestruction"))

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
		name = "CombatService",
		module = servicesFolder:WaitForChild("Combat"):WaitForChild("CombatService"),
	},
	{
		name = "CharacterService",
		module = servicesFolder:WaitForChild("Character"):WaitForChild("CharacterService"),
	},
	{
		name = "KitService",
		module = servicesFolder:WaitForChild("Kit"):WaitForChild("KitService"),
	},
	{
		name = "MatchService",
		module = servicesFolder:WaitForChild("Match"):WaitForChild("MatchService"),
	},
	{
		name = "ReplicationService",
		module = servicesFolder:WaitForChild("Replication"):WaitForChild("ReplicationService"),
	},
	{
		name = "MovementService",
		module = servicesFolder:WaitForChild("Movement"):WaitForChild("MovementService"),
	},
	{
		name = "GadgetService",
		module = servicesFolder:WaitForChild("Gadgets"):WaitForChild("GadgetService"),
	},
	{
		name = "WeaponService",
		module = servicesFolder:WaitForChild("Weapon"):WaitForChild("WeaponService"),
	},
	{
		name = "EmoteService",
		module = servicesFolder:WaitForChild("Emote"):WaitForChild("EmoteService"),
	},
	{
		name = "OverheadService",
		module = servicesFolder:WaitForChild("Overhead"):WaitForChild("OverheadService"),
	},
	{
		name = "DummyService",
		module = servicesFolder:WaitForChild("Dummy"):WaitForChild("DummyService"),
	},
	{
		name = "PracticeDummyService",
		module = servicesFolder:WaitForChild("PracticeDummyService"),
	},
	{
		name = "KnockbackService",
		module = servicesFolder:WaitForChild("Knockback"):WaitForChild("KnockbackService"),
	},
	{
		name = "Queue",
		module = servicesFolder:WaitForChild("Queue"):WaitForChild("QueueService"),
	},
	{
		name = "Round",
		module = servicesFolder:WaitForChild("Round"):WaitForChild("RoundService"),
	},
	{
		name = "MapLoader",
		module = servicesFolder:WaitForChild("Map"):WaitForChild("MapLoaderService"),
	},
	{
		name = "MatchManager",
		module = servicesFolder:WaitForChild("Match"):WaitForChild("MatchManager"),
	},
}

-- Temporary recv isolation toggles. Set to true to skip loading a service.
local DISABLED_SERVICES = {
	DummyService = true,
	PracticeDummyService = true,
}

local enabledEntries = {}
for _, entry in ipairs(entries) do
	if not DISABLED_SERVICES[entry.name] then
		table.insert(enabledEntries, entry)
	end
end

Loader:Load(enabledEntries, registry, Net)

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

-- Connect Hitbox utility to ReplicationService for server-side position lookups
do
	local Hitbox = require(Locations.Shared.Util.Hitbox)
	local replicationService = registry:TryGet("ReplicationService")
	if replicationService then
		Hitbox.SetReplicationService(replicationService)
	end
end
