local ReplicationConfig = {}

-- =============================================================================
-- UPDATE RATES (Hz = updates per second)
-- =============================================================================

ReplicationConfig.UpdateRates = {
	ClientToServer = 60, -- Client sends state to server 60 times/second (16.6ms interval) - maximum smoothness
	ServerToClients = 60, -- Server broadcasts to clients 60 times/second (16.6ms interval) - REVERTED (30Hz caused 38% loss!)
	LocalSimulation = 0, -- Run at framerate (Heartbeat), 0 = uncapped

	-- CRITICAL: These high rates are ONLY possible with UnreliableRemoteEvent!
	-- Using RemoteEvent at 60Hz causes Roblox throttling → ~24% artificial packet loss
	-- UnreliableRemoteEvent bypasses throttling → natural packet loss (~5-10% is normal for high-frequency UDP-like transmission)
	-- See RemoteEvents.lua for event configuration (CharacterStateUpdate/CharacterStateReplicated = unreliable)
}

-- =============================================================================
-- COMPRESSION SETTINGS
-- =============================================================================

ReplicationConfig.Compression = {
	-- FULL PRECISION MODE - No compression on position/velocity
	-- Position: float32 (6+ decimal places, ~0.000001 studs precision)
	-- Velocity: float32 (6+ decimal places, ~0.000001 studs/sec precision)
	-- Rotation: int16 (~0.57 degrees precision - sufficient for character facing)

	-- Delta compression
	UseDeltaCompression = true, -- Only send changed values
	MinPositionDelta = 0.1, -- Minimum position change to send update (studs)
	MinRotationDelta = 0.01, -- Minimum rotation change to send update (radians ~0.57 degrees) - Lower for smoother rotation
	MinVelocityDelta = 0.5, -- Minimum velocity change to send update (studs/second)
}

-- =============================================================================
-- ANTI-CHEAT SETTINGS
-- =============================================================================

ReplicationConfig.AntiCheat = {
	-- Speed validation
	MaxSpeed = 150, -- Maximum horizontal speed (studs/second) - accounts for sliding
	MaxVerticalSpeed = 100, -- Maximum vertical speed (studs/second) - accounts for jumping
	SpeedTolerance = 1.25, -- Allow 25% over max speed for latency/physics variance

	-- Teleport detection
	TeleportDistanceThreshold = 100, -- Flag movements >100 studs in single update
	TeleportTimeWindow = 0.1, -- Time window for teleport detection (seconds)

	-- Violation handling
	MaxViolationsPerWindow = 5, -- Max violations before action
	ViolationWindowDuration = 10, -- Violation tracking window (seconds)
	ViolationAction = "Kick", -- "Kick" or "Warn" or "Correct"

	-- Timestamp validation
	MaxTimestampDrift = 1.0, -- Max client-server timestamp difference (seconds)
	AllowFutureTimestamps = false, -- Reject timestamps from the future

	-- Validation toggles
	EnableSpeedValidation = true,
	EnableTeleportDetection = true,
	EnableTimestampValidation = true,
}

-- =============================================================================
-- CLIENT-SIDE PREDICTION
-- =============================================================================

ReplicationConfig.Prediction = {
	-- Input history buffer for reconciliation
	MaxHistoryDuration = 1.0, -- Store last 1 second of inputs
	MaxHistoryEntries = 120, -- Store last 120 input frames (~1 second at 120fps, or 2 seconds at 60Hz)

	-- Reconciliation settings
	EnableReconciliation = true, -- Apply server corrections
	ReconciliationThreshold = 1.5, -- Only reconcile if >1.5 studs off
	ReconciliationMode = "Lerp", -- "Snap" (instant) or "Lerp" (smooth)
	ReconciliationSpeed = 0.2, -- Lerp duration (seconds)
}

-- =============================================================================
-- INTERPOLATION (for other players)
-- =============================================================================

ReplicationConfig.Interpolation = {
	-- Fixed timestep interpolation (framerate-independent)
	InterpolationUpdateRate = 60, -- Hz - Everyone interpolates at 60Hz regardless of display FPS (fairness)

	-- Interpolation settings
	InterpolationDelay = 0.1, -- Buffer 100ms of states for smooth interpolation (6 states at 60Hz)
	InterpolationMode = "Velocity", -- "Linear" or "Cubic" or "Velocity" - Velocity uses physics prediction

	-- Smoothing (time-based, not frame-based)
	EnableSmoothing = true,
	SmoothingTime = 0.08, -- Time to reach target (seconds) - lower = snappier, higher = smoother
	RotationSmoothingTime = 0.06, -- Faster rotation for responsive turning

	-- Snap prevention
	MaxSnapDistance = 15, -- If player moves >15 studs instantly, teleport instead of lerp

	-- Velocity-based prediction
	UseVelocityPrediction = true, -- Use velocity for smoother prediction between states
	VelocityBlendFactor = 0.7, -- How much to trust velocity vs pure position lerp (0.0-1.0)
	
	-- Extrapolation (predict future position when packets are delayed)
	MaxExtrapolationTime = 0.2, -- Maximum time to extrapolate forward (seconds)
}

-- =============================================================================
-- NETWORK OPTIMIZATION
-- =============================================================================

ReplicationConfig.Optimization = {
	-- Batch multiple player states into single packet
	EnableBatching = true,
	MaxBatchSize = 20, -- Max players per batch

	-- Only replicate players within range
	EnableCulling = false, -- Disabled by default (small maps)
	CullingDistance = 300, -- Only replicate players within 300 studs

	-- Adaptive update rates based on importance
	EnableAdaptiveRates = false, -- Disabled for now
	ClosePlayerUpdateRate = 30, -- Higher rate for nearby players
	FarPlayerUpdateRate = 10, -- Lower rate for distant players
	AdaptiveDistanceThreshold = 100, -- Distance threshold for adaptive rates
}

-- =============================================================================
-- SERVER-AUTHORITATIVE FRAME HISTORY (for lag compensation & hit detection)
-- =============================================================================

ReplicationConfig.ServerHistory = {
	-- Store frame-accurate player positions for server-side validation
	EnableFrameHistory = true,
	HistoryDuration = 1.0, -- Store last 1 second of frames (60 frames at 60Hz)
	MaxHistoryEntries = 120, -- Maximum frames to store per player (2 seconds at 60Hz for better lag compensation)

	-- Lag compensation settings
	EnableLagCompensation = true,
	MaxCompensationTime = 0.2, -- Max 200ms lookback for hit detection
}

-- =============================================================================
-- DEBUG SETTINGS
-- =============================================================================

ReplicationConfig.Debug = {
	LogClientUpdates = false, -- Log every client→server update
	LogServerBroadcasts = false, -- Log every server→clients broadcast
	LogValidationFailures = true, -- Log anti-cheat violations
	LogInterpolation = false, -- Log interpolation for other players (DISABLE to reduce spam, enable to debug packet loss)
	LogReconciliation = false, -- Log server corrections
	LogFrameHistory = false, -- Log frame history operations

	-- Visual debug
	ShowPredictionError = false, -- Draw line showing prediction vs server position
	ShowInterpolationPath = false, -- Draw interpolation path for other players
	ShowValidationBounds = false, -- Draw validation spheres around players
}

return ReplicationConfig
