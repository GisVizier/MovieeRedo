local ClientCharacterSetup = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CrouchUtils = require(Locations.Modules.Systems.Character.CrouchUtils)
local RigManager = require(Locations.Modules.Systems.Character.RigManager)
local Log = require(Locations.Modules.Systems.Core.LogService)

local LocalPlayer = Players.LocalPlayer

-- Track characters being set up to prevent duplicate Rig creation
local CharactersBeingSetup = {} -- [character] = true while setup is in progress

function ClientCharacterSetup:Init()
	Log:RegisterCategory("CLIENT_CHAR_SETUP", "Client-side character visual setup")
	Log:Info("CLIENT_CHAR_SETUP", "ClientCharacterSetup initialized")
end

function ClientCharacterSetup:SetupVisualCharacter(serverCharacter)
	Log:Debug("CLIENT_CHAR_SETUP", "SetupVisualCharacter called", { Character = serverCharacter })

	if not serverCharacter then
		Log:Error("CLIENT_CHAR_SETUP", "Invalid server character - nil", { Character = serverCharacter })
		return false
	end

	local isLocalPlayer = serverCharacter.Name == LocalPlayer.Name

	-- SKIP local player - handled by CharacterSetup with clone-destroy pattern
	if isLocalPlayer then
		Log:Debug("CLIENT_CHAR_SETUP", "Skipping local player (handled by CharacterSetup)")
		return true
	end

	-- OTHER PLAYERS ONLY: Add visual Rig to server's minimal Humanoid model

	-- CRITICAL: Prevent duplicate Rig creation using setup tracking
	-- Check if we're already setting up this character OR if Rig already exists
	if CharactersBeingSetup[serverCharacter] then
		Log:Warn("CLIENT_CHAR_SETUP", "Setup already in progress - blocking duplicate call", {
			Character = serverCharacter.Name,
		})
		return false
	end

	-- NEW: Check workspace.Rigs for existing rig
	RigManager:Init()
	local player = Players:GetPlayerFromCharacter(serverCharacter)

	-- If player lookup fails, try to find player by character name
	if not player then
		player = Players:FindFirstChild(serverCharacter.Name)
		if player then
			Log:Debug("CLIENT_CHAR_SETUP", "Found player by name (character detached)", {
				Character = serverCharacter.Name,
				PlayerCharacter = player.Character and player.Character.Name or "nil",
			})
		end
	end

	if not player then
		Log:Warn("CLIENT_CHAR_SETUP", "Cannot find player from character - skipping setup", {
			Character = serverCharacter.Name,
			CharacterParent = serverCharacter.Parent and serverCharacter.Parent.Name or "nil",
		})
		return false
	end

	-- Verify this is actually the player's current character (not an old one being removed)
	if player.Character ~= serverCharacter then
		Log:Debug("CLIENT_CHAR_SETUP", "Character is not player's current character - skipping", {
			CharacterName = serverCharacter.Name,
			PlayerCurrentCharacter = player.Character and player.Character.Name or "nil",
		})
		return false
	end

	local existingRig = RigManager:GetActiveRig(player)
	if existingRig then
		Log:Debug("CLIENT_CHAR_SETUP", "Rig already exists in RigContainer - skipping duplicate setup", {
			Character = serverCharacter.Name,
			RigName = existingRig.Name,
		})
		return true
	end

	-- Mark this character as being set up to prevent race conditions
	CharactersBeingSetup[serverCharacter] = true

	-- EVENT-DRIVEN: Wait for character to have a PrimaryPart
	if not serverCharacter.PrimaryPart then
		-- Wait for PrimaryPart property to be set (yields until property changes)
		serverCharacter:GetPropertyChangedSignal("PrimaryPart"):Wait()

		-- Verify it was actually set (property changed signal doesn't guarantee it's not nil)
		if not serverCharacter.PrimaryPart then
			Log:Error("CLIENT_CHAR_SETUP", "Character PrimaryPart property changed but still nil", {
				Character = serverCharacter.Name,
			})
			CharactersBeingSetup[serverCharacter] = nil
			return false
		end
	end

	Log:Info("CLIENT_CHAR_SETUP", "Setting up visual Rig for other player", {
		Character = serverCharacter.Name,
	})

	-- Get character template from ReplicatedStorage
	local characterTemplate = ReplicatedStorage:WaitForChild("CharacterTemplate", 5)
	if not characterTemplate then
		Log:Error("CLIENT_CHAR_SETUP", "CharacterTemplate not found in ReplicatedStorage")
		CharactersBeingSetup[serverCharacter] = nil -- Clear tracking on failure
		return false
	end

	-- NEW: Create Rig in workspace.Rigs using RigManager
	-- This allows rigs to persist after death/respawn for ragdoll effects
	local rig = RigManager:CreateRig(player, serverCharacter)
	if not rig then
		Log:Error("CLIENT_CHAR_SETUP", "Failed to create rig in RigContainer")
		CharactersBeingSetup[serverCharacter] = nil -- Clear tracking on failure
		return false
	end

	-- Clone Hitbox for hit detection (if it exists in template)
	local hitbox = nil
	local templateHitbox = characterTemplate:FindFirstChild("Hitbox")
	if templateHitbox then
		hitbox = templateHitbox:Clone()
		Log:Debug("CLIENT_CHAR_SETUP", "Cloned Hitbox from template", {
			Character = serverCharacter.Name,
		})
	end

	-- Apply avatar to the rig
	if player then
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local Config = require(Locations.Modules.Config)
			local humanoidConfig = Config.System.Humanoid

			-- Apply Humanoid settings
			humanoid.EvaluateStateMachine = humanoidConfig.EvaluateStateMachine
			humanoid.RequiresNeck = humanoidConfig.RequiresNeck
			humanoid.BreakJointsOnDeath = humanoidConfig.BreakJointsOnDeath
			humanoid.AutoJumpEnabled = humanoidConfig.AutoJumpEnabled
			humanoid.AutoRotate = humanoidConfig.AutoRotate

			-- Create Animator for animation replication (CRITICAL for other players)
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
				Log:Debug("CLIENT_CHAR_SETUP", "Created Animator on other player's Rig", {
					Player = player.Name,
				})
			end

			-- Apply avatar BEFORE parenting (prevents visual rig recreation)
			task.spawn(function()
				local success, result = pcall(function()
					return game.Players:GetHumanoidDescriptionFromUserId(player.UserId)
				end)

				if success and result then
					pcall(function()
						humanoid:ApplyDescription(result)
					end)
				end
			end)
		end
	end

	-- Calculate proper offset from template to maintain Y-positioning
	local templateRoot = characterTemplate:FindFirstChild("Root")
	local templateRigHRP = rig:FindFirstChild("HumanoidRootPart")
	local rigOffset = CFrame.new()

	if templateRoot and templateRigHRP then
		rigOffset = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
	end

	-- Position Rig at server character's position with proper offset
	-- NEW: Rig is already parented to workspace.Rigs by RigManager
	local targetCFrame = serverCharacter.PrimaryPart.CFrame * rigOffset
	for _, part in pairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame = targetCFrame
		end
	end

	-- Helper function to configure all rig parts
	local function ConfigureRigParts()
		for _, part in pairs(rig:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Massless = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false

				-- CRITICAL: Anchor the Rig's HumanoidRootPart to prevent falling through world
				-- BulkMoveTo works with anchored parts and Motor6Ds still work fine
				if part.Name == "HumanoidRootPart" and part.Parent == rig then
					part.Anchored = true
				end
			end
		end
	end

	-- Configure parts initially (before parenting)
	ConfigureRigParts()

	-- EVENT-DRIVEN: Monitor for any descendants being added and configure them immediately
	-- This handles ApplyDescription's asynchronous part creation properly
	local descendantConnection = rig.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			-- New part added - configure it immediately (no waits needed!)
			descendant.CanCollide = false
			descendant.Massless = true
			descendant.CanQuery = false
			descendant.CanTouch = false

			Log:Debug("CLIENT_CHAR_SETUP", "Auto-configured new rig part", {
				Character = serverCharacter.Name,
				Part = descendant.Name,
			})
		end
	end)

	-- NEW: Rig is already parented to workspace.Rigs by RigManager - no need to parent it

	-- Parent Hitbox to character (if it was cloned)
	if hitbox then
		hitbox.Parent = serverCharacter

		-- Configure hitbox parts for weapon hit detection
		for _, hitboxPart in pairs(hitbox:GetChildren()) do
			if hitboxPart:IsA("BasePart") then
				hitboxPart.CanQuery = true -- Enable for raycasting
				hitboxPart.CanCollide = false
				hitboxPart.CanTouch = true
				hitboxPart.Massless = true
				hitboxPart.Anchored = false
				hitboxPart.CollisionGroup = "Hitboxes" -- Assign to Hitboxes collision group
			end
		end

		Log:Debug("CLIENT_CHAR_SETUP", "Parented and configured Hitbox to character", {
			Character = serverCharacter.Name,
		})
	end

	-- Re-configure all parts after parenting (catches any property resets from parenting)
	ConfigureRigParts()

	-- Setup hitbox welds if Hitbox model exists
	local hitboxSetupSuccess = CrouchUtils:SetupHitboxWelds(serverCharacter)
	if hitboxSetupSuccess then
		Log:Info("CLIENT_CHAR_SETUP", "Hitbox welds setup complete", { Character = serverCharacter.Name })
	else
		Log:Debug("CLIENT_CHAR_SETUP", "No hitbox to setup or setup failed", { Character = serverCharacter.Name })
	end

	-- Keep the DescendantAdded listener active for character lifetime
	-- This ensures any late-loading accessories/parts are configured
	-- Store connection for cleanup
	if not serverCharacter:GetAttribute("_rigDescendantConnection") then
		serverCharacter:SetAttribute("_rigDescendantConnection", true)

		-- Cleanup connection when character is destroyed
		serverCharacter.Destroying:Connect(function()
			if descendantConnection then
				descendantConnection:Disconnect()
			end
		end)
	end

	-- Clear tracking flag on successful completion
	CharactersBeingSetup[serverCharacter] = nil

	Log:Info("CLIENT_CHAR_SETUP", "Visual Rig setup complete for other player", { Character = serverCharacter.Name })
	return true
end

function ClientCharacterSetup:CleanupVisualParts(character)
	-- Clear tracking flag in case cleanup happens during setup
	CharactersBeingSetup[character] = nil

	-- NEW: Mark rig as dead so it can persist for ragdoll
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		local rig = RigManager:GetActiveRig(player)
		if rig then
			RigManager:MarkRigAsDead(rig)
			-- Cleanup old dead rigs (keep only 3 most recent)
			RigManager:CleanupDeadRigs(player, 3)
		end
	end

	-- NEW: Rig is no longer destroyed - it persists in workspace.Rigs as a dead rig
	-- The RigManager handles cleanup based on max dead rig limit

	-- Cleanup crouch state
	CrouchUtils:CleanupWelds(character)
end

return ClientCharacterSetup
