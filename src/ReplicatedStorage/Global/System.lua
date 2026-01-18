local System = {}

System.Network = {
	CharacterRespawnTime = 3,
	AutoSpawnOnJoin = true,
	GiveClientNetworkOwnership = true,
}

System.Server = {
	GCInterval = 60,
	GCMaxAge = 300,
	MaxCharactersPerPlayer = 1,
	CharacterTimeoutTime = 180,
}

System.Logging = {
	MinLogLevel = 3,
	LogToRobloxOutput = true,
	LogToMemory = true,
	MaxLogEntries = 1000,
	LogPerformanceMetrics = false,
	PerformanceLogInterval = 30,
}

System.Humanoid = {
	EvaluateStateMachine = false,
	RequiresNeck = false,
	BreakJointsOnDeath = false,
	HealthDisplayDistance = 0,
	NameDisplayDistance = 0,
	DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None,
	MaxHealth = 100,
	Health = 100,
	AutoJumpEnabled = false,
	AutoRotate = false,
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

System.Debug = {
	ShowGroundRaycast = false,
	ShowCharacterBounds = false,
	ShowPhysicsForces = false,
	LogMovementInput = true,
	LogGroundDetection = true,
	LogPhysicsChanges = false,
}

return System
