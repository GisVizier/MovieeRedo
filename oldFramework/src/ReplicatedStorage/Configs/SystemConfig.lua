local SystemConfig = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestMode = require(ReplicatedStorage:WaitForChild("TestMode"))

-- =============================================================================
-- NETWORK SETTINGS
-- =============================================================================

SystemConfig.Network = {
	CharacterRespawnTime = 3,
	AutoSpawnOnJoin = true,
	GiveClientNetworkOwnership = true,
}

-- =============================================================================
-- SERVER SETTINGS
-- =============================================================================

SystemConfig.Server = {
	-- Garbage collection settings
	GCInterval = 60,
	GCMaxAge = 300,

	-- Character limits
	MaxCharactersPerPlayer = 1,
	CharacterTimeoutTime = 180,
}

-- =============================================================================
-- LOGGING SYSTEM
-- =============================================================================

SystemConfig.Logging = {
	MinLogLevel = TestMode.ENABLED and 2 or 3, -- 2=DEBUG in test mode, 3=INFO in production
	LogToRobloxOutput = true,
	LogToMemory = true,
	MaxLogEntries = TestMode.ENABLED and 2000 or 1000,
	LogPerformanceMetrics = TestMode.Performance.LogMemoryUsage,
	PerformanceLogInterval = 30,
}

-- =============================================================================
-- HUMANOID SETTINGS (for VC and Bubble Chat)
-- =============================================================================

SystemConfig.Humanoid = {
	-- Core Humanoid settings for minimal performance
	EvaluateStateMachine = false, -- Disable physics/state machine for custom character
	RequiresNeck = false, -- Don't kill character if neck disconnects
	BreakJointsOnDeath = false, -- Don't break joints on death

	-- Display settings - hide all UI for clean appearance
	HealthDisplayDistance = 0, -- Hide health bar completely
	NameDisplayDistance = 0, -- Hide name display
	DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None,

	-- Health settings
	MaxHealth = 100,
	Health = 100,

	-- Disable unnecessary Humanoid states for performance
	DisabledStates = {
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Flying,
		Enum.HumanoidStateType.Freefall,
		Enum.HumanoidStateType.Jumping,
		Enum.HumanoidStateType.Landed,
		Enum.HumanoidStateType.Physics,
		Enum.HumanoidStateType.PlatformStanding,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Running,
		Enum.HumanoidStateType.RunningNoPhysics,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.StrafingNoPhysics,
		Enum.HumanoidStateType.Swimming,
	},
}

-- =============================================================================
-- DEBUG SETTINGS
-- =============================================================================

SystemConfig.Debug = {
	-- Visual debug options
	ShowGroundRaycast = TestMode.Visual.ShowGroundRaycast,
	ShowCharacterBounds = TestMode.Visual.ShowCharacterBounds,
	ShowPhysicsForces = TestMode.Visual.ShowPhysicsForces,

	-- Logging debug options
	LogMovementInput = TestMode.Logging.LogCharacterMovement,
	LogGroundDetection = TestMode.Logging.LogGroundDetection,
	LogPhysicsChanges = TestMode.Logging.LogPhysicsChanges,
}

return SystemConfig
