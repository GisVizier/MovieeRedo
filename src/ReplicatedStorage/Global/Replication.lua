local Replication = {}

Replication.UpdateRates = {
	ClientToServer = 60,
	ServerToClients = 60,
}

Replication.Compression = {
	UseDeltaCompression = true,
	MinPositionDelta = 0.1,
	MinRotationDelta = 0.01,
	MinVelocityDelta = 0.5,
	MinAimPitchDelta = 0.5,
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
}

Replication.ViewmodelActions = {
	MinInterval = 0.03,
}

return Replication
