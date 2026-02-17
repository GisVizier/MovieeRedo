local Replication = {}

Replication.UpdateRates = {
	ClientToServer = 30,
	ServerToClients = 30,
}

Replication.Compression = {
	UseDeltaCompression = true,
	MinPositionDelta = 0.12,
	MinRotationDelta = 0.012,
	MinVelocityDelta = 0.7,
	MinAimPitchDelta = 0.75,
}

Replication.Interpolation = {
	InterpolationUpdateRate = 60,
	InterpolationDelay = 0.1,
	EnableSmoothing = true,
	SmoothingTime = 0.08,
	RotationSmoothingTime = 0.06,
	MaxExtrapolationTime = 0.2,
}

Replication.Optimization = {
	EnableBatching = true,
	MaxBatchSize = 20,
	-- Match-scoped fanout: only replicate to players in the same match context.
	-- Competitive match -> team1 + team2 only
	-- Training -> same CurrentArea only
	-- Lobby -> no replication
	-- Set to false to rollback to global fanout behavior.
	EnableMatchScopedFanout = true,
	-- Send character states only when source player state changed.
	EnableDirtyStateBroadcast = true,
	-- If only one ready client is in server, skip state fanout.
	SkipBroadcastWhenSolo = true,
	-- Safety resend interval for dormant players so remotes self-correct.
	DormantResendInterval = 1.0,
	-- TESTING: Disable all character state replication to other clients.
	-- Set to true to completely disable movement replication for recv testing.
	DisableCharacterStateReplication = false,
}

Replication.ViewmodelActions = {
	MinInterval = 0.04,
}

return Replication
