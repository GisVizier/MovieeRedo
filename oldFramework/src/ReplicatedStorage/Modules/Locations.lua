local Locations = {}

local RunService = game:GetService("RunService")
local isServer = RunService:IsServer()
local isClient = RunService:IsClient()

-- Simple safe waiting function to avoid circular dependency
local function safeWaitForChild(parent, childName, timeout)
	timeout = timeout or 5
	local child = parent:FindFirstChild(childName)
	if child then
		return child
	end

	local startTime = tick()
	while not child and (tick() - startTime) < timeout do
		child = parent:FindFirstChild(childName)
		if not child then
			task.wait(0.1)
		end
	end

	-- Note: We can't use LogService here because Locations is required before LogService
	-- This is a low-level module that needs to work without dependencies
	-- So we keep this single warn statement for critical initialization failures
	if not child then
		warn("Locations: Failed to find " .. childName .. " in " .. parent.Name)
	end

	return child
end

Locations.Services = {
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService"),
	UserInputService = game:GetService("UserInputService"),
	ContextActionService = game:GetService("ContextActionService"),
	TweenService = game:GetService("TweenService"),
	Workspace = workspace,
}

if isServer then
	Locations.Services.ServerStorage = game:GetService("ServerStorage")
	Locations.Services.ServerScriptService = game:GetService("ServerScriptService")
end

if isClient then
	Locations.Services.StarterPlayerScripts = game:GetService("StarterPlayer").StarterPlayerScripts
	Locations.Services.StarterCharacterScripts = game:GetService("StarterPlayer").StarterCharacterScripts
end

Locations.Server = {}
if isServer then
	-- Cache services folder for reuse
	local servicesFolder = safeWaitForChild(Locations.Services.ServerScriptService, "Services", 5)
	if servicesFolder then
		Locations.Server.Services = {
			CharacterService = servicesFolder.CharacterService,
			GarbageCollectorService = servicesFolder.GarbageCollectorService,
			LogServiceInitializer = servicesFolder.LogServiceInitializer,
			NPCService = servicesFolder.NPCService,
			RoundService = servicesFolder.RoundService,
		}
	else
		Locations.Server.Services = {}
	end

	-- Cache ServerStorage modules
	local serverStorageModules = safeWaitForChild(Locations.Services.ServerStorage, "Modules", 5)
	if serverStorageModules then
		Locations.Server.Modules = {
			MapSelector = serverStorageModules.MapSelector,
			MapLoader = serverStorageModules.MapLoader,
			SpawnManager = serverStorageModules.SpawnManager,
			DisconnectBuffer = serverStorageModules.DisconnectBuffer,
		}

		-- Cache Phases folder
		local phasesFolder = safeWaitForChild(serverStorageModules, "Phases", 3)
		if phasesFolder then
			Locations.Server.Phases = {
				IntermissionPhase = phasesFolder.IntermissionPhase,
				RoundStartPhase = phasesFolder.RoundStartPhase,
				RoundPhase = phasesFolder.RoundPhase,
				RoundEndPhase = phasesFolder.RoundEndPhase,
			}
		else
			Locations.Server.Phases = {}
		end
	else
		Locations.Server.Modules = {}
		Locations.Server.Phases = {}
	end
end

Locations.Client = {}
if isClient then
	-- Cache folders for reuse
	local controllersFolder = safeWaitForChild(Locations.Services.StarterPlayerScripts, "Controllers", 5)
	local uiFolder = safeWaitForChild(Locations.Services.StarterPlayerScripts, "UI", 5)

	if controllersFolder then
		-- Helper function to find controller in subfolders
		local function findController(name)
			-- Try direct child first
			local directChild = controllersFolder:FindFirstChild(name)
			if directChild and directChild:IsA("ModuleScript") then
				return directChild
			end

			-- Search in subfolders
			for _, child in ipairs(controllersFolder:GetChildren()) do
				if child:IsA("Folder") then
					local module = child:FindFirstChild(name)
					if module and module:IsA("ModuleScript") then
						return module
					end
				end
			end

			return nil
		end

		Locations.Client.Controllers = {
			CameraController = findController("CameraController"),
			CharacterController = findController("CharacterController"),
			CharacterSetup = findController("CharacterSetup"),
			InputManager = findController("InputManager"),
			AnimationController = findController("AnimationController"),
			InteractableController = findController("InteractableController"),
			ScreenShakeController = findController("ScreenShakeController"),
		}
	else
		Locations.Client.Controllers = {}
	end

	if uiFolder then
		Locations.Client.UI = {
			UIManager = uiFolder.UIManager,
			MobileControls = uiFolder.MobileControls,
			ChatMonitor = uiFolder.ChatMonitor,
		}
	else
		Locations.Client.UI = {}
	end
end

-- Cache commonly used folders to avoid repeated lookups
local replicatedStorage = Locations.Services.ReplicatedStorage
local modulesFolder = safeWaitForChild(replicatedStorage, "Modules", 5)
local systemsFolder = safeWaitForChild(replicatedStorage, "Systems", 5)
local utilsFolder = safeWaitForChild(replicatedStorage, "Utils", 5)
local weaponsFolder = safeWaitForChild(replicatedStorage, "Weapons", 5)

-- Cache system subfolders
local movementSystemsFolder, characterSystemsFolder, coreSystemsFolder, kitsSystemsFolder
if systemsFolder then
	movementSystemsFolder = safeWaitForChild(systemsFolder, "Movement", 3)
	characterSystemsFolder = safeWaitForChild(systemsFolder, "Character", 3)
	coreSystemsFolder = safeWaitForChild(systemsFolder, "Core", 3)
	kitsSystemsFolder = safeWaitForChild(systemsFolder, "Kits", 3)
end

-- Auto-load action modules from a category folder
local function LoadActionCategory(categoryFolder)
	local actions = {}
	if categoryFolder then
		for _, child in ipairs(categoryFolder:GetChildren()) do
			-- Include both ModuleScripts (like BaseGun) and Folders (like Revolver/)
			if child:IsA("ModuleScript") or child:IsA("Folder") then
				actions[child.Name] = child
			end
		end
	end
	return actions
end

-- Cache weapon config folder only (other folders archived)
local weaponConfigsFolder
if weaponsFolder then
	weaponConfigsFolder = safeWaitForChild(weaponsFolder, "Configs", 3)
end

Locations.Modules = {
	Locations = modulesFolder and modulesFolder.Locations,
	RemoteEvents = modulesFolder and modulesFolder.RemoteEvents,
	Config = replicatedStorage.Configs,
	TestMode = replicatedStorage.TestMode,

	-- Systems (complex logic & state management)
	Systems = {
		Movement = movementSystemsFolder and {
			SlidingSystem = movementSystemsFolder.SlidingSystem,
			SlidingBuffer = movementSystemsFolder.SlidingBuffer,
			SlidingPhysics = movementSystemsFolder.SlidingPhysics,
			SlidingState = movementSystemsFolder.SlidingState,
			MovementStateManager = movementSystemsFolder.MovementStateManager,
			MovementUtils = movementSystemsFolder.MovementUtils,
			WallJumpUtils = movementSystemsFolder.WallJumpUtils,
		} or {},
		Character = characterSystemsFolder and {
			CharacterUtils = characterSystemsFolder.CharacterUtils,
			CharacterLocations = characterSystemsFolder.CharacterLocations,
			CrouchUtils = characterSystemsFolder.CrouchUtils,
			RigRotationUtils = characterSystemsFolder.RigRotationUtils,
			RagdollSystem = characterSystemsFolder.RagdollSystem,
			RigManager = characterSystemsFolder.RigManager,
		} or {},
		Core = coreSystemsFolder and {
			LogService = coreSystemsFolder.LogService,
			ConfigCache = coreSystemsFolder.ConfigCache,
			SoundManager = coreSystemsFolder.SoundManager,
			MouseLockManager = coreSystemsFolder.MouseLockManager,
			UserSettings = coreSystemsFolder.UserSettings,
			FOVController = coreSystemsFolder.FOVController,
			VFXController = coreSystemsFolder.VFXController,
		} or {},
		Crosshair = (function()
			local crosshairSystem = systemsFolder and safeWaitForChild(systemsFolder, "Crosshair", 3)
			return crosshairSystem
					and {
						CrosshairController = crosshairSystem.CrosshairController,
						Types = crosshairSystem.Types,
					}
				or {}
		end)(),
		Round = (function()
			local roundSystemsFolder = systemsFolder and safeWaitForChild(systemsFolder, "Round", 3)
			return roundSystemsFolder
					and {
						PlayerStateManager = roundSystemsFolder.PlayerStateManager,
						NPCStateManager = roundSystemsFolder.NPCStateManager,
						CombinedStateManager = roundSystemsFolder.CombinedStateManager,
					}
				or {}
		end)(),
		Kits = kitsSystemsFolder and {
			BaseAbility = kitsSystemsFolder.BaseAbility,
			BaseKit = kitsSystemsFolder.BaseKit,
			AbilityUtils = kitsSystemsFolder.AbilityUtils,
			PassiveAbility = kitsSystemsFolder.PassiveAbility,
			ActiveAbility = kitsSystemsFolder.ActiveAbility,
			UltimateAbility = kitsSystemsFolder.UltimateAbility,
		} or {},
	},

	-- Utils (small helper functions only)
	Utils = utilsFolder and {
		DebugPrint = utilsFolder.DebugPrint,
		MathUtils = utilsFolder.MathUtils,
		NumberUtils = utilsFolder.NumberUtils,
		PathUtils = utilsFolder.PathUtils,
		ServiceLoader = utilsFolder.ServiceLoader,
		ServiceRegistry = utilsFolder.ServiceRegistry,
		TableUtils = utilsFolder.TableUtils,
		ConfigValidator = utilsFolder.ConfigValidator,
		TimerUtils = utilsFolder.TimerUtils,
		ValidationUtils = utilsFolder.ValidationUtils,
		AsyncUtils = utilsFolder.AsyncUtils,
		CompressionUtils = utilsFolder.CompressionUtils,
		PartUtils = utilsFolder.PartUtils,
		WeldUtils = utilsFolder.WeldUtils,
		CollisionUtils = utilsFolder.CollisionUtils,
		WallDetectionUtils = utilsFolder.WallDetectionUtils,
		Sera = utilsFolder.Sera,
		SlideDirectionDetector = utilsFolder.SlideDirectionDetector,
		WalkDirectionDetector = utilsFolder.WalkDirectionDetector,
		WallBoostDirectionDetector = utilsFolder.WallBoostDirectionDetector,
		InputDisplayUtil = utilsFolder.InputDisplayUtil,
		Signal = utilsFolder.Signal,
		ConnectionManager = utilsFolder.ConnectionManager,
		TweenLibrary = utilsFolder.TweenLibrary,
	} or {},

	-- CoreUI - Declarative UI Framework
	-- NOTE: In Rojo, a folder with init.lua becomes the ModuleScript itself
	CoreUI = (function()
		local coreUIModule = safeWaitForChild(replicatedStorage, "CoreUI", 5)
		if coreUIModule then
			return {
				CoreUI = coreUIModule, -- The folder IS the ModuleScript (init.lua)
				Modules = coreUIModule:FindFirstChild("Modules"),
			}
		end
		return {}
	end)(),

	-- Weapons system (most archived - only configs kept for viewmodel)
	Weapons = {
		Configs = weaponConfigsFolder,
	},
}

Locations.RemoteEvents = modulesFolder and modulesFolder.RemoteEvents

Locations.Assets = {}
if isServer then
	Locations.Assets.CharacterModels = safeWaitForChild(Locations.Services.ServerStorage, "Models", 5)
end

return Locations
