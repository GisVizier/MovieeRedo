--[[
	RigManager.lua

	Manages visual R6 rigs in a separate Workspace folder.
	This allows rigs to persist after character death/respawn for ragdoll effects.

	Architecture:
	- All rigs are stored in workspace.Rigs (created on client/server init)
	- Each rig is named "{PlayerName}_Rig" or "{PlayerName}_Rig_{Number}" for dead rigs
	- Active rigs are synced to character Root position via BulkMoveTo/Welds
	- Dead rigs remain in RigContainer as ragdolls until cleanup

	Usage:
	local RigManager = require(Locations.Modules.Systems.Character.RigManager)
	RigManager:Init()
	local rig = RigManager:CreateRig(player, character)
	RigManager:MarkRigAsDead(rig) -- Renames to _Rig_1, _Rig_2, etc.
	RigManager:CleanupDeadRigs(player, maxRigs) -- Keep only N most recent dead rigs
]]

local RigManager = {}

-- Services
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local LogService = require(Locations.Modules.Systems.Core.LogService)

-- Constants
local RIG_CONTAINER_NAME = "Rigs"

-- State
RigManager.RigContainer = nil
RigManager.ActiveRigs = {} -- [player] = rig (currently active rig)
RigManager.DeadRigCounts = {} -- [player] = number (counter for dead rig numbering)

function RigManager:Init()
	-- Create or get the Rigs container in Workspace
	self.RigContainer = Workspace:FindFirstChild(RIG_CONTAINER_NAME)

	if not self.RigContainer then
		self.RigContainer = Instance.new("Folder")
		self.RigContainer.Name = RIG_CONTAINER_NAME
		self.RigContainer.Parent = Workspace

		LogService:Info("RIG_MANAGER", "Created Rigs container in Workspace")
	else
		LogService:Info("RIG_MANAGER", "Found existing Rigs container in Workspace")
	end
end

function RigManager:GetRigContainer()
	if not self.RigContainer then
		self:Init()
	end
	return self.RigContainer
end

function RigManager:CreateRig(player, character)
	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not characterTemplate then
		LogService:Error("RIG_MANAGER", "CharacterTemplate not found in ReplicatedStorage")
		return nil
	end

	local templateRig = characterTemplate:FindFirstChild("Rig")
	if not templateRig then
		LogService:Error("RIG_MANAGER", "Rig not found in CharacterTemplate")
		return nil
	end

	-- Clone the rig
	local rig = templateRig:Clone()
	rig.Name = player.Name .. "_Rig"

	-- Store reference to owner player (attributes only support primitives, not instances)
	rig:SetAttribute("OwnerUserId", player.UserId)
	rig:SetAttribute("OwnerName", player.Name)
	rig:SetAttribute("IsActive", true) -- Mark as active rig
	-- NOTE: Cannot use SetAttribute for character reference (instances not supported)
	-- We'll use the ActiveRigs table to track character-to-rig relationship

	-- Parent to RigContainer instead of character
	rig.Parent = self:GetRigContainer()

	-- Store as active rig (this is our character-to-rig lookup)
	self.ActiveRigs[player] = rig

	LogService:Info("RIG_MANAGER", "Created rig in RigContainer", {
		Player = player.Name,
		RigName = rig.Name,
	})

	return rig
end

function RigManager:GetActiveRig(player)
	return self.ActiveRigs[player]
end

function RigManager:GetRigFromCharacter(character)
	-- Get player from character, then use ActiveRigs table
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return self.ActiveRigs[player]
	end

	-- Fallback: Find rig by character name (for death/ragdoll scenarios where player may be detached)
	-- Character name matches player name in this project
	local characterName = character.Name
	for _, rig in pairs(self:GetRigContainer():GetChildren()) do
		if rig:GetAttribute("OwnerName") == characterName and rig:GetAttribute("IsActive") then
			return rig
		end
	end

	return nil
end

function RigManager:MarkRigAsDead(rig)
	if not rig then return end

	local ownerName = rig:GetAttribute("OwnerName")
	if not ownerName then
		LogService:Warn("RIG_MANAGER", "Rig has no OwnerName attribute")
		return
	end

	-- Get player to track dead rig count
	local player = Players:FindFirstChild(ownerName)
	if not player then
		-- Player left, just mark as dead without numbering
		rig:SetAttribute("IsActive", false)
		rig:SetAttribute("IsDead", true)
		rig:SetAttribute("DeathTime", tick())
		rig:SetAttribute("CharacterReference", nil)
		return
	end

	-- Increment dead rig counter
	self.DeadRigCounts[player] = (self.DeadRigCounts[player] or 0) + 1
	local deadRigNumber = self.DeadRigCounts[player]

	-- Rename rig to indicate it's a dead rig
	rig.Name = ownerName .. "_Rig_" .. deadRigNumber

	-- Mark as dead
	rig:SetAttribute("IsActive", false)
	rig:SetAttribute("IsDead", true)
	rig:SetAttribute("DeathTime", tick())
	rig:SetAttribute("DeadRigNumber", deadRigNumber)

	-- Clear from active rigs
	if self.ActiveRigs[player] == rig then
		self.ActiveRigs[player] = nil
	end

	LogService:Info("RIG_MANAGER", "Marked rig as dead", {
		Player = ownerName,
		RigName = rig.Name,
		DeadRigNumber = deadRigNumber,
	})
end

function RigManager:CleanupDeadRigs(player, maxDeadRigs)
	maxDeadRigs = maxDeadRigs or 3 -- Default: keep 3 most recent dead rigs

	local ownerName = player.Name
	local deadRigs = {}

	-- Collect all dead rigs for this player
	for _, rig in pairs(self:GetRigContainer():GetChildren()) do
		if rig:GetAttribute("OwnerName") == ownerName and rig:GetAttribute("IsDead") then
			table.insert(deadRigs, rig)
		end
	end

	-- Sort by death time (newest first)
	table.sort(deadRigs, function(a, b)
		local timeA = a:GetAttribute("DeathTime") or 0
		local timeB = b:GetAttribute("DeathTime") or 0
		return timeA > timeB
	end)

	-- Remove oldest rigs beyond the max limit
	local rigsRemoved = 0
	for i = maxDeadRigs + 1, #deadRigs do
		deadRigs[i]:Destroy()
		rigsRemoved = rigsRemoved + 1
	end

	if rigsRemoved > 0 then
		LogService:Info("RIG_MANAGER", "Cleaned up old dead rigs", {
			Player = ownerName,
			RigsRemoved = rigsRemoved,
			RigsRemaining = math.min(#deadRigs, maxDeadRigs),
		})
	end
end

function RigManager:CleanupPlayerRigs(player)
	local ownerName = player.Name
	local rigsRemoved = 0

	-- Remove all rigs for this player (active and dead)
	for _, rig in pairs(self:GetRigContainer():GetChildren()) do
		if rig:GetAttribute("OwnerName") == ownerName then
			rig:Destroy()
			rigsRemoved = rigsRemoved + 1
		end
	end

	-- Clear tracking
	self.ActiveRigs[player] = nil
	self.DeadRigCounts[player] = nil

	LogService:Info("RIG_MANAGER", "Cleaned up all rigs for player", {
		Player = ownerName,
		RigsRemoved = rigsRemoved,
	})
end

function RigManager:GetAllDeadRigs(player)
	local ownerName = player.Name
	local deadRigs = {}

	for _, rig in pairs(self:GetRigContainer():GetChildren()) do
		if rig:GetAttribute("OwnerName") == ownerName and rig:GetAttribute("IsDead") then
			table.insert(deadRigs, rig)
		end
	end

	return deadRigs
end

return RigManager
