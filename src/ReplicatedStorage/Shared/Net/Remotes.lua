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
	{ name = "GadgetInitRequest", description = "Client requests gadget init data" },
	{ name = "GadgetInit", description = "Server sends gadget init data" },
	{ name = "GadgetUseRequest", description = "Client requests gadget use" },
	{ name = "GadgetUseResponse", description = "Server responds to gadget use request" },

}

return Remotes
