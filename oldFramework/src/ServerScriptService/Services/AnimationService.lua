local AnimationService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local Config = require(Locations.Modules.Config)
local Log = require(Locations.Modules.Systems.Core.LogService)

AnimationService.PlayerAnimationStates = {}

function AnimationService:Init()
	Log:RegisterCategory("ANIMATION", "Animation system and replication")

	-- Listen for Players service to track character spawns
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			self:OnCharacterSpawned(player, character)
		end)

		player.CharacterRemoving:Connect(function(character)
			self:OnCharacterRemoving(player, character)
		end)
	end)

	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			self:OnCharacterSpawned(player, player.Character)
		end

		player.CharacterAdded:Connect(function(character)
			self:OnCharacterSpawned(player, character)
		end)

		player.CharacterRemoving:Connect(function(character)
			self:OnCharacterRemoving(player, character)
		end)
	end


	Log:Debug("ANIMATION", "AnimationService initialized")
end

function AnimationService:OnCharacterSpawned(player, character)
	if not character then
		Log:Warn("ANIMATION", "Character not found for player", { Player = player.Name })
		return
	end

	-- NOTE: Server-side animation system only tracks state and relays to clients
	-- Server doesn't create Animators - clients create them on the Rig's Humanoid
	-- when setting up visual characters (ClientCharacterSetup)

	-- Initialize player animation state tracking
	self.PlayerAnimationStates[player] = {
		currentState = "Walking", -- Default state
		isMoving = false,
	}

	Log:Info("ANIMATION", "Initialized animation state tracking for player", { Player = player.Name })
end

function AnimationService:OnCharacterRemoving(player, character)
	self.PlayerAnimationStates[player] = nil
end

function AnimationService:GetPlayerAnimationState(player)
	return self.PlayerAnimationStates[player]
end

return AnimationService
