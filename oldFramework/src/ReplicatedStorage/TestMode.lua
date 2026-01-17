local RunService = game:GetService("RunService")

local TestMode = {}

-- CHANGE THIS TO FALSE FOR PRODUCTION BUILDS
TestMode.ENABLED = false

-- Set to false to disable test mode in Studio (useful for production testing in Studio)
TestMode.ENABLE_IN_STUDIO = true

-- Auto-enable TestMode in Studio if ENABLE_IN_STUDIO is true
if RunService:IsStudio() and TestMode.ENABLE_IN_STUDIO then
	TestMode.ENABLED = true
end

TestMode.CLIENT_LOGGING_ENABLED = TestMode.ENABLED
TestMode.SERVER_LOGGING_ENABLED = TestMode.ENABLED

-- WARNINGS AND ERRORS ALWAYS SHOW EVEN IN PRODUCTION - DON'T TOUCH
TestMode.ALWAYS_SHOW_WARNINGS = true
TestMode.ALWAYS_SHOW_ERRORS = true

TestMode.Logging = {
	ShowDebugLogs = TestMode.ENABLED and false, -- Disable DEBUG logs globally to reduce clutter
	ShowPerformanceLogs = TestMode.ENABLED,
	ShowNetworkLogs = TestMode.ENABLED,
	ShowDetailedData = TestMode.ENABLED and false, -- Hide detailed data by default

	LogCharacterMovement = TestMode.ENABLED and false,
	LogGroundDetection = TestMode.ENABLED and false,
	LogInputEvents = TestMode.ENABLED and false,
	LogPhysicsChanges = TestMode.ENABLED and false,
	LogServiceInitialization = TestMode.ENABLED and false,
	LogRemoteEvents = TestMode.ENABLED and false,
	LogSlidingSystem = TestMode.ENABLED and false,
	LogAnimationSystem = TestMode.ENABLED and false,
}

TestMode.Visual = {
	ShowGroundRaycast = TestMode.ENABLED and false,
	ShowCharacterBounds = TestMode.ENABLED and true,
	ShowPhysicsForces = TestMode.ENABLED and false,
	ShowHitboxes = TestMode.ENABLED and false,

	ShowFPSCounter = TestMode.ENABLED and true,
	ShowPlayerStats = TestMode.ENABLED and true,
	ShowNetworkStats = TestMode.ENABLED and false,
}

TestMode.Gameplay = {
	AllowDebugCommands = TestMode.ENABLED,
	AllowTeleporting = TestMode.ENABLED,
	AllowSpeedModification = TestMode.ENABLED,
	AllowNoclip = TestMode.ENABLED and false,

	IgnoreCollisions = TestMode.ENABLED and false,
	UnlimitedJumps = TestMode.ENABLED and false,
	GodMode = TestMode.ENABLED and false,
}

TestMode.Performance = {
	EnableProfiler = TestMode.ENABLED and false,
	LogFrameTime = TestMode.ENABLED and false,
	LogMemoryUsage = TestMode.ENABLED and true,
	LogGarbageCollection = TestMode.ENABLED and true,

	ReducedPlayerLimit = TestMode.ENABLED and false,
	SkipAnimations = TestMode.ENABLED and false,
}

TestMode.Network = {
	SimulateLatency = TestMode.ENABLED and false,
	SimulatePacketLoss = TestMode.ENABLED and false,

	LogAllRemoteEvents = TestMode.ENABLED and false,
	LogCharacterUpdates = TestMode.ENABLED and false,
	LogNetworkOwnership = TestMode.ENABLED and true,
}

function TestMode:IsDebugLoggingEnabled()
	return self.ENABLED
		and (self.Logging.ShowDebugLogs or self.Logging.ShowPerformanceLogs or self.Logging.ShowNetworkLogs)
end

-- Check if visual debugging is enabled
function TestMode:IsVisualDebuggingEnabled()
	return self.ENABLED
		and (
			self.Visual.ShowGroundRaycast
			or self.Visual.ShowCharacterBounds
			or self.Visual.ShowPhysicsForces
			or self.Visual.ShowHitboxes
		)
end

-- Check if gameplay debugging is enabled
function TestMode:IsGameplayDebuggingEnabled()
	return self.ENABLED
		and (self.Gameplay.AllowDebugCommands or self.Gameplay.AllowTeleporting or self.Gameplay.AllowSpeedModification)
end

-- Get current test mode status
function TestMode:GetStatus()
	return {
		Enabled = self.ENABLED,
		DebugLogging = self:IsDebugLoggingEnabled(),
		VisualDebugging = self:IsVisualDebuggingEnabled(),
		GameplayDebugging = self:IsGameplayDebuggingEnabled(),
		Version = "1.0.0",
	}
end

function TestMode:EnableAll()
	self.ENABLED = true
	self.CLIENT_LOGGING_ENABLED = true
	self.SERVER_LOGGING_ENABLED = true
	print("[TEST MODE] All debugging enabled")
end

function TestMode:DisableAll()
	self.ENABLED = false
	self.CLIENT_LOGGING_ENABLED = false
	self.SERVER_LOGGING_ENABLED = false
	print("[TEST MODE] All debugging disabled")
end

function TestMode:DisableClientLogging()
	self.CLIENT_LOGGING_ENABLED = false
	print("[TEST MODE] Client logging disabled")
end

function TestMode:EnableClientLogging()
	if self.ENABLED then
		self.CLIENT_LOGGING_ENABLED = true
		print("[TEST MODE] Client logging enabled")
	end
end

function TestMode:DisableServerLogging()
	self.SERVER_LOGGING_ENABLED = false
	print("[TEST MODE] Server logging disabled")
end

function TestMode:EnableServerLogging()
	if self.ENABLED then
		self.SERVER_LOGGING_ENABLED = true
		print("[TEST MODE] Server logging enabled")
	end
end

function TestMode:EnableLogging()
	if self.ENABLED then
		self.Logging.ShowDebugLogs = true
		self.Logging.ShowPerformanceLogs = true
		self.Logging.ShowNetworkLogs = true
		print("[TEST MODE] Debug logging enabled")
	end
end

function TestMode:DisableLogging()
	self.Logging.ShowDebugLogs = false
	self.Logging.ShowPerformanceLogs = false
	self.Logging.ShowNetworkLogs = false
	print("[TEST MODE] Debug logging disabled")
end

function TestMode:PrintStatus()
	local status = self:GetStatus()
	print("=== TEST MODE STATUS ===")
	print("Enabled:", status.Enabled)
	print("Debug Logging:", status.DebugLogging)
	print("Visual Debugging:", status.VisualDebugging)
	print("Gameplay Debugging:", status.GameplayDebugging)
	print("========================")
end

return TestMode
