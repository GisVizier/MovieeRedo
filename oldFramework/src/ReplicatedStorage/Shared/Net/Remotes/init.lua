local Remotes = {
	{ name = "ServerReady", description = "Server finished initializing" },
	{ name = "RequestCharacterSpawn", description = "Client requests character spawn" },
	{ name = "RequestRespawn", description = "Client requests respawn" },
	{ name = "CharacterSpawned", description = "Character spawned" },
	{ name = "CharacterRemoving", description = "Character removing" },
	{ name = "CharacterSetupComplete", description = "Client finished character setup" },
	{ name = "CrouchStateChanged", description = "Crouch visual replication" },

	{ name = "PlayerHealthChanged", description = "Health update for a player" },
	{ name = "PlayerDied", description = "Client notifies server of death" },
	{ name = "PlayerKilled", description = "Server broadcasts kill event" },
	{ name = "PlayerRagdolled", description = "Server broadcasts ragdoll info" },

	{ name = "CharacterStateUpdate", description = "Client state update", unreliable = true },
	{ name = "CharacterStateReplicated", description = "Server broadcast state batch", unreliable = true },
	{ name = "ServerCorrection", description = "Server correction to client" },
	{ name = "RequestInitialStates", description = "Client requests initial states" },
}

return Remotes
