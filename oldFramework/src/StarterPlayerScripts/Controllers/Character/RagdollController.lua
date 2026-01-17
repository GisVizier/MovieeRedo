--[[
	RagdollController.lua

	Client-side controller for managing ragdoll system.
	Provides EnableRagdoll() method for triggering ragdolls on death.
]]

local RagdollController = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RagdollSystem = require(Locations.Modules.Systems.Character.RagdollSystem)
local RigManager = require(Locations.Modules.Systems.Character.RigManager)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local RemoteEvents = require(Locations.Modules.RemoteEvents)

-- Constants
local LocalPlayer = Players.LocalPlayer

-- State
local Character = nil

function RagdollController:Init()
	LogService:Info("RAGDOLL", "RagdollController initialized")

	-- Initialize RigManager
	RigManager:Init()

	-- Connect to character spawning
	LocalPlayer.CharacterAdded:Connect(function(newCharacter)
		self:OnCharacterAdded(newCharacter)
	end)

	-- Setup for existing character
	if LocalPlayer.Character then
		self:OnCharacterAdded(LocalPlayer.Character)
	end

	-- Cleanup all rigs when player leaves
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		if player == LocalPlayer then
			RigManager:CleanupPlayerRigs(LocalPlayer)
		end
	end)
end

function RagdollController:OnCharacterAdded(newCharacter)
	Character = newCharacter

	LogService:Debug("RAGDOLL", "Character added", {
		CharacterName = Character.Name
	})

	-- Cleanup ragdoll on character removal
	Character:GetPropertyChangedSignal("Parent"):Connect(function()
		if not Character.Parent then
			RagdollSystem:Cleanup(Character)
		end
	end)
end

function RagdollController:EnableRagdoll()
	if not Character then
		LogService:Warn("RAGDOLL", "No character to ragdoll")
		return false
	end

	-- Get rig from RigContainer
	local rig = CharacterLocations:GetRig(Character)
	if not rig then
		LogService:Warn("RAGDOLL", "No Rig found for character")
		return false
	end

	-- Don't ragdoll if already ragdolled
	if RagdollSystem:IsRagdolled(Character) then
		return true
	end

	-- Ragdoll with current velocity
	local root = Character.PrimaryPart
	local velocity = Vector3.new(0, 0, 0)

	-- Use current velocity if character is moving
	if root then
		velocity = root.AssemblyLinearVelocity
	end

	local success = RagdollSystem:RagdollCharacter(Character, {
		Velocity = velocity,
		IsDeath = true,
	})

	if success then
		LogService:Info("RAGDOLL", "Ragdolled character on death")

		RemoteEvents:FireServer("PlayerRagdolled", {
			Velocity = velocity,
			IsDeath = true,
		})
	end

	return success
end

return RagdollController
