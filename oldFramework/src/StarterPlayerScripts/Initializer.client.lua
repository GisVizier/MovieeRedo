local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ServiceLoader = require(Locations.Modules.Utils.ServiceLoader)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local SoundManager = require(Locations.Modules.Systems.Core.SoundManager)
local LocalPlayer = ServiceLoader:GetLocalPlayer()

-- Initialize custom replication systems
local ClientReplicator = require(LocalPlayer.PlayerScripts.Systems.Replication.ClientReplicator)
local RemoteReplicator = require(LocalPlayer.PlayerScripts.Systems.Replication.RemoteReplicator)
local ReplicationDebugger = require(LocalPlayer.PlayerScripts.Systems.Replication.ReplicationDebugger)

ClientReplicator:Init()
RemoteReplicator:Init()
ReplicationDebugger:Init()

local controllers = {
	"InputManager",
	"CameraController",
	"CharacterController",
	"AnimationController",
	"InteractableController",
	"ClientCharacterSetup",
	"RagdollController",
	"FootstepController",
	"ViewmodelController",
	"InventoryController",
	"CrosshairUIController",
	"KitController",
	"KitAnimationController",
	"ViewmodelSwapController",
}
local loadedControllers =
	ServiceLoader:LoadModules(LocalPlayer:WaitForChild("PlayerScripts").Controllers, controllers, "CLIENT")

-- Register all controllers in the registry (done early so SettingsMenu can access InputManager)
for name, controller in pairs(loadedControllers) do
	ServiceRegistry:RegisterController(name, controller)
end

-- Initialize SoundManager
SoundManager:Init()

-- Initialize VFXController
local VFXController = require(Locations.Modules.Systems.Core.VFXController)
VFXController:Init()

-- Initialize UIManager
local UIManager = require(Locations.Client.UI.UIManager)
local uiManager = UIManager.new()
uiManager:Init()

-- CoreUI is initialized through UIManager
-- Access it via: uiManager:GetModule("CoreUIController")

LogService:Info("INITIALIZER", "Loaded controllers", {
	controllerCount = #controllers,
	controllers = controllers,
})

if loadedControllers.CharacterController and loadedControllers.CharacterController.ConnectToInputs then
	LogService:Info("INITIALIZER", "Connecting CharacterController to inputs")
	loadedControllers.CharacterController:ConnectToInputs(
		loadedControllers.InputManager,
		loadedControllers.CameraController
	)
end

RemoteEvents:ConnectClient("CharacterSpawned", function(character)
	-- Validate character exists and is parented
	if not character or not character.Parent then
		LogService:Warn("INITIALIZER", "CharacterSpawned received invalid/unparented character", {
			Character = character and character.Name or "nil",
		})
		return
	end

	-- Try to find the player for this character
	local Players = game:GetService("Players")
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		player = Players:FindFirstChild(character.Name)
	end

	LogService:Info("INITIALIZER", "Character spawned event received", {
		characterName = character.Name,
		characterParent = character.Parent and character.Parent.Name or "nil",
		playerFound = player ~= nil,
		isPlayerCurrentChar = player and player.Character == character or false,
	})

	-- Skip if this isn't the player's current character (stale event)
	if player and player.Character ~= character then
		LogService:Debug("INITIALIZER", "Skipping stale CharacterSpawned event (not current character)", {
			Character = character.Name,
		})
		return
	end

	-- Setup visual parts for ALL characters (local and other players)
	if loadedControllers.ClientCharacterSetup then
		local success = loadedControllers.ClientCharacterSetup:SetupVisualCharacter(character)
		if not success then
			LogService:Warn("INITIALIZER", "Failed to setup visual character", {
				Character = character.Name,
			})
			return
		end
	end

	-- Only initialize controllers for the local player's character
	if character.Name == LocalPlayer.Name then
		-- Initialize all controllers
		for _name, controller in pairs(loadedControllers) do
			if controller.OnCharacterSpawned then
				controller:OnCharacterSpawned(character)
			end
		end

		-- LATE-JOIN SYNC: Request initial states from server now that we're ready
		-- This ensures we receive other players' positions after our visual setup is complete
		LogService:Info("INITIALIZER", "Requesting initial player states for late-join sync")
		RemoteEvents:FireServer("RequestInitialStates")
	end
end)

RemoteEvents:ConnectClient("CharacterRemoving", function(character)
	-- Trigger ragdoll on death (BEFORE character is destroyed)
	if character.Name == LocalPlayer.Name then
		local Config = require(Locations.Modules.Config)
		if Config.Gameplay.Character.Ragdoll.AutoRagdoll.OnDeath then
			LogService:Info("RAGDOLL", "Triggering ragdoll on character removal (death)")

			local ragdollController = ServiceRegistry:GetController("RagdollController")
			if ragdollController then
				ragdollController:EnableRagdoll()
			end
		end
	end

	-- Cleanup controllers for the local player's character
	if character.Name == LocalPlayer.Name then
		for _name, controller in pairs(loadedControllers) do
			if controller.OnCharacterRemoving then
				controller:OnCharacterRemoving(character)
			end
		end
	end

	-- Cleanup visual parts for ALL characters (local and other players)
	if loadedControllers.ClientCharacterSetup then
		loadedControllers.ClientCharacterSetup:CleanupVisualParts(character)
	end
end)

-- Handle ragdoll replication from other players (P2P ragdoll sync)
RemoteEvents:ConnectClient("PlayerRagdolled", function(ragdolledPlayer, ragdollData)
	LogService:Info("RAGDOLL", "Received ragdoll event for other player", {
		Player = ragdolledPlayer.Name,
	})

	-- Mark this player as ragdolled in RemoteReplicator (stops BulkMoveTo updates)
	RemoteReplicator:SetPlayerRagdolled(ragdolledPlayer, true)

	-- Get the rig from RigManager - try active first, then check by name (handles race condition)
	local RigManager = require(Locations.Modules.Systems.Character.RigManager)
	RigManager:Init()

	local rig = RigManager:GetActiveRig(ragdolledPlayer)

	-- If no active rig, find by owner name (rig may have been marked as dead already)
	if not rig then
		local rigContainer = RigManager:GetRigContainer()
		for _, potentialRig in pairs(rigContainer:GetChildren()) do
			if potentialRig:GetAttribute("OwnerName") == ragdolledPlayer.Name then
				rig = potentialRig
				LogService:Debug("RAGDOLL", "Found rig by owner name (was already marked dead)", {
					Player = ragdolledPlayer.Name,
					RigName = rig.Name,
				})
				break
			end
		end
	end

	if not rig then
		LogService:Warn("RAGDOLL", "No rig found for ragdolled player", {
			Player = ragdolledPlayer.Name,
		})
		return
	end

	-- Get character reference (may be nil during death, but we have the rig)
	local character = ragdolledPlayer.Character

	-- Set RagdollActive on character if it exists
	if character then
		character:SetAttribute("RagdollActive", true)
	end

	-- Trigger ragdoll directly on the rig (bypass character lookup)
	local RagdollSystem = require(Locations.Modules.Systems.Character.RagdollSystem)
	local success = RagdollSystem:RagdollRig(rig, {
		Velocity = ragdollData.Velocity or Vector3.zero,
		IsDeath = ragdollData.IsDeath or false,
	})

	if success then
		LogService:Info("RAGDOLL", "Successfully ragdolled other player's rig", {
			Player = ragdolledPlayer.Name,
		})
	else
		LogService:Warn("RAGDOLL", "Failed to ragdoll other player's rig", {
			Player = ragdolledPlayer.Name,
		})
	end
end)

-- Health sync system - update client Humanoid health when server applies damage
RemoteEvents:ConnectClient("PlayerHealthChanged", function(healthData)
	local targetPlayer = healthData.Player
	if not targetPlayer or not targetPlayer.Character then
		return
	end

	local character = targetPlayer.Character
	local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
	local humanoid = CharacterLocations:GetHumanoidInstance(character)

	if humanoid then
		-- CRITICAL: Set MaxHealth FIRST, then set Health
		-- Roblox automatically clamps Health to MaxHealth, so order matters
		local oldMaxHealth = humanoid.MaxHealth
		local oldHealth = humanoid.Health

		humanoid.MaxHealth = healthData.MaxHealth
		humanoid.Health = healthData.Health

		-- Debug: Verify the health was actually set
		if targetPlayer == LocalPlayer then
			LogService:Info("HEALTH_SYNC", "Local player Humanoid updated", {
				OldMaxHealth = oldMaxHealth,
				OldHealth = oldHealth,
				NewMaxHealth = humanoid.MaxHealth,
				NewHealth = humanoid.Health,
				RequestedHealth = healthData.Health,
				HumanoidPath = humanoid:GetFullName(),
			})
		end

		-- If this is the local player and they died, notify server with killer info
		if targetPlayer == LocalPlayer and healthData.Health <= 0 then
			LogService:Info("HEALTH_SYNC", "Local player died - notifying server", {
				Attacker = healthData.Attacker and healthData.Attacker.Name or "Unknown",
				Headshot = healthData.Headshot,
			})

			-- Send death notification to server with killer info
			RemoteEvents:FireServer("PlayerDied", {
				Killer = healthData.Attacker,
				WasHeadshot = healthData.Headshot,
			})
		end

		LogService:Info("HEALTH_SYNC", "Synced health to client Humanoid", {
			Player = targetPlayer.Name,
			Health = healthData.Health,
			MaxHealth = healthData.MaxHealth,
			Damage = healthData.Damage,
			Attacker = healthData.Attacker and healthData.Attacker.Name or "Unknown",
			Headshot = healthData.Headshot,
			IsDead = healthData.Health <= 0,
		})
	else
		LogService:Warn("HEALTH_SYNC", "Failed to find Humanoid for health sync", {
			Player = targetPlayer.Name,
			HasCharacter = targetPlayer.Character ~= nil,
		})
	end
end)

-- Register replication systems in the registry
ServiceRegistry:RegisterSystem("ClientReplicator", ClientReplicator)
ServiceRegistry:RegisterSystem("RemoteReplicator", RemoteReplicator)
ServiceRegistry:RegisterSystem("ReplicationDebugger", ReplicationDebugger)

-- Wait for server to be ready before requesting character spawn
local characterSpawnRequested = false

local function requestCharacterSpawn(source)
	if characterSpawnRequested then
		return
	end
	characterSpawnRequested = true
	LogService:Debug("INITIALIZER", "Requesting character spawn", { Source = source })
	RemoteEvents:FireServer("RequestCharacterSpawn")
end

local function onServerReady()
	requestCharacterSpawn("ServerReady event")
end

-- Connect to ServerReady event and add fallback
RemoteEvents:ConnectClient("ServerReady", onServerReady)

-- Fallback: if server doesn't respond within 3 seconds, request anyway
task.spawn(function()
	task.wait(3)
	requestCharacterSpawn("fallback timeout")
end)

-- =============================================================================
-- DEBUG UTILITIES (accessible from console in Studio)
-- =============================================================================

-- Create global debug table for easy console access
_G.Debug = _G.Debug or {}

-- Animation state dump (call from console: _G.Debug.DumpAnimations())
_G.Debug.DumpAnimations = function()
	local AnimationController = ServiceRegistry:GetController("AnimationController")
	if AnimationController and AnimationController.DumpAnimationState then
		AnimationController:DumpAnimationState()
	else
		warn("AnimationController not found or DumpAnimationState function missing")
	end
end

-- Log current animation state (call from console: _G.Debug.LogAnimations())
_G.Debug.LogAnimations = function()
	local AnimationController = ServiceRegistry:GetController("AnimationController")
	if AnimationController and AnimationController.LogCurrentAnimationState then
		AnimationController:LogCurrentAnimationState()
	else
		warn("AnimationController not found or LogCurrentAnimationState function missing")
	end
end

-- List all available debug commands
_G.Debug.Help = function()
	print("=== AVAILABLE DEBUG COMMANDS ===")
	print("_G.Debug.DumpAnimations()  - Detailed animation state dump with all tracks")
	print("_G.Debug.LogAnimations()   - Log current animation state (categories)")
	print("_G.Debug.Help()            - Show this help menu")
	print("================================")
end

print("[INITIALIZER] Debug utilities loaded. Type '_G.Debug.Help()' for commands")
