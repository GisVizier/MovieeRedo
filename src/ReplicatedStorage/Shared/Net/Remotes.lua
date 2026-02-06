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
	{ name = "RagdollStarted", description = "Server notifies clients that ragdoll started" },
	{ name = "RagdollEnded", description = "Server notifies clients that ragdoll ended" },

	{ name = "CharacterStateUpdate", description = "Client state update", unreliable = true },
	{ name = "CharacterStateReplicated", description = "Server broadcast state batch", unreliable = true },
	{ name = "ServerCorrection", description = "Server correction to client" },
	{ name = "RequestInitialStates", description = "Client requests initial states" },
	{ name = "ClientReplicationReady", description = "Client signals ready to receive replication" },

	-- Match / loadout gating
	{ name = "SubmitLoadout", description = "Client submits selected loadout and ready" },
	{ name = "StartMatch", description = "Server notifies clients match started" },

	-- VFX replication (generic)
	{ name = "VFXRep", description = "VFX replication", unreliable = true },

	-- Kit system
	{ name = "KitRequest", description = "Client requests kit actions (purchase/equip/ability)" },
	{ name = "KitState", description = "Server sends kit state/events" },

	-- Weapon system (hitscan)
	{ name = "WeaponFired", description = "Client sends weapon fire data for validation" },
	{ name = "HitConfirmed", description = "Server broadcasts validated hit", unreliable = true },

	-- Projectile system
	{ name = "ProjectileSpawned", description = "Client spawned a projectile" },
	{ name = "ProjectileHit", description = "Client reports projectile hit" },
	{ name = "ProjectileReplicate", description = "Server replicates projectile to other clients", unreliable = true },
	{ name = "ProjectileHitConfirmed", description = "Server broadcasts validated projectile hit", unreliable = true },
	{ name = "ProjectileDestroyed", description = "Server notifies projectile destruction", unreliable = true },

	-- Debug logging
	{ name = "DebugLog", description = "Client debug log forwarding" },

	-- Emote system
	{ name = "EmotePlay", description = "Client requests emote playback" },
	{ name = "EmoteStop", description = "Client requests emote stop" },
	{ name = "EmoteReplicate", description = "Server broadcasts emote to clients" },

	-- Combat system
	{ name = "CombatStateUpdate", description = "Server sends combat state to client" },
	{ name = "DamageDealt", description = "Server broadcasts damage for damage numbers" },
	{ name = "StatusEffectUpdate", description = "Server sends status effect changes" },

	-- Ping measurement (for lag compensation)
	{ name = "PingRequest", description = "Server sends ping challenge", unreliable = true },
	{ name = "PingResponse", description = "Client responds to ping challenge", unreliable = true },

	-- Gadget system
	{ name = "GadgetInitRequest", description = "Client requests gadget init" },
	{ name = "GadgetInit", description = "Server sends all gadgets to client" },
	{ name = "GadgetUseRequest", description = "Client requests gadget use" },
	{ name = "GadgetUseResponse", description = "Server responds to gadget use" },
	{ name = "GadgetAreaLoaded", description = "Server sends area gadgets to client" },

	-- Knockback system
	{ name = "KnockbackRequest", description = "Client requests knockback on another player" },
	{ name = "Knockback", description = "Server sends knockback to target client" },

	-- Queue system
	{ name = "QueuePadUpdate", description = "Server updates pad occupancy state" },
	{ name = "QueueCountdownStart", description = "Server starts queue countdown" },
	{ name = "QueueCountdownTick", description = "Server sends countdown tick" },
	{ name = "QueueCountdownCancel", description = "Server cancels queue countdown" },
	{ name = "QueueMatchReady", description = "Queue complete, transitioning to match" },

	-- Round system
	{ name = "MatchTeleport", description = "Server tells client to teleport for match" },
	{ name = "MatchTeleportReady", description = "Client confirms teleport complete" },
	{ name = "MatchStart", description = "Match has started" },
	{ name = "RoundStart", description = "New round beginning" },
	{ name = "RoundKill", description = "Kill occurred during round" },
	{ name = "ScoreUpdate", description = "Match score changed" },
	{ name = "ShowRoundLoadout", description = "Show loadout UI between rounds" },
	{ name = "MatchEnd", description = "Match complete, winner declared" },
	{ name = "ReturnToLobby", description = "Teleport players back to lobby" },
	{ name = "PlayerJoinedMatch", description = "Player joined match (training mode)" },
	{ name = "PlayerLeftMatch", description = "Player left match" },
	{ name = "PlayerRespawned", description = "Player respawned (training mode)" },

	-- Training entry flow
	{ name = "ShowTrainingLoadout", description = "Server tells client to show loadout UI for training entry" },
	{ name = "TrainingLoadoutConfirmed", description = "Server confirms loadout and sends spawn data for training" },
}

return Remotes
