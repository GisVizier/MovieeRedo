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
	{ name = "ViewmodelActionUpdate", description = "Client viewmodel action update" },
	{ name = "ViewmodelActionReplicated", description = "Server broadcasts viewmodel actions" },
	{ name = "ViewmodelActionSnapshot", description = "Server sends active viewmodel action snapshot" },
	{ name = "ServerCorrection", description = "Server correction to client" },
	{ name = "RequestInitialStates", description = "Client requests initial states" },
	{ name = "ClientReplicationReady", description = "Client signals ready to receive replication" },

	-- Match / loadout gating
	{ name = "SubmitLoadout", description = "Client submits selected loadout and ready" },
	{ name = "LoadoutReady", description = "Client signals all 4 loadout slots filled" },
	{ name = "LoadoutLocked", description = "Server signals loadout is locked, timer jumping to 5s" },

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
	{ name = "ProjectileHitBatch", description = "Client reports multiple projectile hits" },
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
	{ name = "DamageDealt", description = "Server broadcasts damage/heal events for client combat UI" },
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
	{ name = "RoundOutcome", description = "Round ended with outcome (win/lose/draw) for player" },
	{ name = "ShowRoundLoadout", description = "Show loadout UI between rounds" },
	{
		name = "LoadoutTimerHalved",
		description = "Server notifies clients that loadout timer was halved after all players confirmed",
	},
	{ name = "MatchEnd", description = "Match complete, winner declared" },
	{ name = "ReturnToLobby", description = "Teleport players back to lobby" },
	{ name = "PlayerJoinedMatch", description = "Player joined match (training mode)" },
	{ name = "PlayerLeftMatch", description = "Player left match" },
	{ name = "PlayerRespawned", description = "Player respawned (training mode)" },

	-- Map selection (competitive)
	{ name = "ShowMapSelection", description = "Server tells clients to show map voting UI" },
	{ name = "SubmitMapVote", description = "Client sends map vote to server" },
	{ name = "MapVoteUpdate", description = "Server broadcasts a player's map vote" },
	{ name = "MapVoteResult", description = "Server announces winning map" },
	{ name = "BetweenRoundFreeze", description = "Server tells clients round reset freeze started" },

	-- Training entry flow
	{ name = "ShowTrainingLoadout", description = "Server tells client to show loadout UI for training entry" },
	{ name = "TrainingLoadoutConfirmed", description = "Server confirms loadout and sends spawn data for training" },

	-- Voxel destruction system
	{ name = "VoxelDebris", description = "Server sends debris creation data to clients", unreliable = true },

	-- Debug / testing
	{ name = "RequestTestDeath", description = "Client requests self-kill for testing respawn flow" },

	-- Overhead system
	{ name = "SetPlatform", description = "Client sends platform type to server" },

	-- Player data (Replica + client updates)
	{ name = "PlayerDataUpdate", description = "Client sends data path/value to persist via server" },

	-- Storm system
	{ name = "StormStart", description = "Server notifies storm phase has begun" },
	{ name = "StormUpdate", description = "Server broadcasts storm radius update", unreliable = true },
	{ name = "StormEnter", description = "Player entered the storm zone" },
	{ name = "StormLeave", description = "Player left the storm zone (safe)" },
	{ name = "StormSound", description = "Server triggers storm sound effect" },
}

return Remotes
