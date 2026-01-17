local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

-- DISABLE ROBLOX DEFAULT CHARACTER SPAWNING - WE HANDLE IT MANUALLY
Players.CharacterAutoLoads = false

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ServiceLoader = require(Locations.Modules.Utils.ServiceLoader)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local SoundManager = require(Locations.Modules.Systems.Core.SoundManager)
local Log = require(Locations.Modules.Systems.Core.LogService)

-- LOGSERVICE MUST BE FIRST, THEN GARBAGE COLLECTOR, THEN OTHERS
-- Initialize SoundManager
SoundManager:Init()

-- Initialize VFXController
local VFXController = require(Locations.Modules.Systems.Core.VFXController)
VFXController:Init()

Log:RegisterCategory("SERVER_INIT", "Server initialization and setup")

-- Move character template to ReplicatedStorage so clients can access it
local characterTemplate = ServerStorage.Models:WaitForChild("Character")
local clientCharacterTemplate = characterTemplate:Clone()
clientCharacterTemplate.Name = "CharacterTemplate"
clientCharacterTemplate.Parent = ReplicatedStorage
Log:Info("SERVER_INIT", "Character template moved to ReplicatedStorage for client access")

local services = {
	"LogServiceInitializer",
	"GarbageCollectorService",
	"CollisionGroupService",
	"ServerReplicator",
	"CharacterService",
	"AnimationService",
	"NPCService",
	"RoundService",
	"InventoryService",
	"ArmReplicationService",
	"KitService",
}
local loadedServices = ServiceLoader:LoadModules(ServerScriptService.Services, services, "SERVER")

Players.PlayerAdded:Connect(function(player)
	-- Don't auto-spawn characters - let the client request when ready
	-- This prevents double spawning when client requests character spawn
	Log:Info("SERVER_INIT", "Player joined, waiting for client character spawn request", { Player = player.Name })

	-- Give the client a moment to initialize, then signal server is ready
	task.spawn(function()
		task.wait(0.5)
		RemoteEvents:FireClient("ServerReady", player)
		Log:Debug("SERVER_INIT", "Sent ServerReady to player", { Player = player.Name })

		-- Send all existing characters to the new player so they can see them
		local characterService = ServiceRegistry:GetService("CharacterService")
		if characterService then
			for otherPlayer, character in pairs(characterService.ActiveCharacters) do
				if otherPlayer ~= player and character and character.Parent then
					-- Fire CharacterSpawned for each existing character
					RemoteEvents:FireClient("CharacterSpawned", player, character)
					Log:Debug("SERVER_INIT", "Sent existing character to new player", {
						OtherPlayer = otherPlayer.Name,
						NewPlayer = player.Name,
					})
				end
			end
		end
	end)
end)

-- Register services in the registry
for name, service in pairs(loadedServices) do
	ServiceRegistry:RegisterService(name, service)
end

Players.PlayerRemoving:Connect(function(player)
	local characterService = ServiceRegistry:GetService("CharacterService")
	if characterService then
		characterService:RemoveCharacter(player)
	end
end)

-- Signal that server is ready for client requests
Log:Info("SERVER_INIT", "All services initialized, server ready")
