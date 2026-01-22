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

	-- Ragdoll system
	{ name = "ToggleRagdollTest", description = "Client requests ragdoll toggle (test key)" },
	{ name = "RagdollStarted", description = "Server notifies clients that ragdoll started" },
	{ name = "RagdollEnded", description = "Server notifies clients that ragdoll ended" },

	{ name = "CharacterStateUpdate", description = "Client state update", unreliable = true },
	{ name = "CharacterStateReplicated", description = "Server broadcast state batch", unreliable = true },
	{ name = "ServerCorrection", description = "Server correction to client" },
	{ name = "RequestInitialStates", description = "Client requests initial states" },

	-- Match / loadout gating
	{ name = "SubmitLoadout", description = "Client submits selected loadout and ready" },
	{ name = "StartMatch", description = "Server notifies clients match started" },

	-- VFX replication (generic)
	{ name = "VFXRep", description = "VFX replication", unreliable = true },

	-- Kit system
	{ name = "KitRequest", description = "Client requests kit actions (purchase/equip/ability)" },
	{ name = "KitState", description = "Server sends kit state/events" },

	-- Weapon system
	{ name = "WeaponFired", description = "Client sends weapon fire data for validation" },
	{ name = "HitConfirmed", description = "Server broadcasts validated hit", unreliable = true },

	-- Debug logging
	{ name = "DebugLog", description = "Client debug log forwarding" },

	-- Emote system
	{ name = "EmotePlay", description = "Client requests emote playback" },
	{ name = "EmoteStop", description = "Client requests emote stop" },
	{ name = "EmoteReplicate", description = "Server broadcasts emote to clients" },

}

return Remotes
