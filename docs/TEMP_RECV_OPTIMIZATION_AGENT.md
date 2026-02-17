# Temp Recv Optimization Agent

Temporary planning doc to drive `recv` reduction work without breaking gameplay replication.

## Goal

Reduce client receive bandwidth (`recv`) while preserving:
- smooth remote movement
- correct hit validation windows
- stable animation/viewmodel replication
- lobby/match/training state transitions

Gameplay quality is the hard priority:
- never accept recv gains that reduce hit fairness, movement readability, or action consistency
- optimization is successful only if gameplay remains unchanged or better

Target ranges (practical):
- solo server: below current baseline (focus first)
- 1v1: ~20-40 during normal movement
- 2v2 active combat: keep spikes controlled and short

## Recv Budget By Scale (Gameplay-First)

Use these as operating expectations, not hard failures:
- 1 player solo: target low baseline; stable idle recv is the priority
- 4 players mostly idle: target ~15-20 recv
- 4 players active combat: temporary spikes are acceptable if gameplay is stable
- 20 players active server: spikes up to ~90 recv are acceptable

Interpretation rule:
- if recv is within/near budget but gameplay degrades, fail the change
- if recv spikes above budget briefly under heavy combat/load but gameplay remains correct, this can still pass

## Pre-Flight Rules (Must Hold Before Any Optimization)

1. Hit detection safety first
- Never reduce position history quality below what `HitValidator` and `ProjectileValidator` need.
- Keep server-side position/stance history writes reliable, even when client broadcast is reduced.

2. Separate ingest from fanout
- Safe optimization target is fanout (what server rebroadcasts), not ingestion (what server records for validation).

3. Explicit wake conditions for dormancy
- Any idle/dormant optimization must wake instantly on:
  - movement delta
  - stance changes (crouch/slide)
  - animation changes
  - aim changes above threshold
  - fire/reload/inspect/weapon action events

4. Controlled rollout only
- Every phase ships behind config toggles for immediate rollback.

## Current Data Flow (Where Recv Comes From)

Character state pipeline:
- `src/ReplicatedStorage/Game/Replication/ClientReplicator.lua`
- `src/ServerScriptService/Server/Services/Replication/ReplicationService.lua`
- `src/ReplicatedStorage/Game/Replication/RemoteReplicator.lua`

Viewmodel action pipeline:
- `src/ReplicatedStorage/Game/Replication/ClientReplicator.lua`
- `src/ServerScriptService/Server/Services/Replication/ReplicationService.lua`
- `src/ReplicatedStorage/Game/Replication/RemoteReplicator.lua`
- `src/ReplicatedStorage/Game/Weapons/ThirdPersonWeaponManager.lua`

VFX/Sound relay pipeline:
- `src/ReplicatedStorage/Game/Replication/ReplicationModules/init.lua`
- `src/ReplicatedStorage/Game/Replication/ReplicationModules/Sound.lua`

Replication knobs:
- `src/ReplicatedStorage/Global/Replication.lua`

## Known High-Recv Drivers In This Codebase

1. Global fanout for state replication
- `ReplicationService:BroadcastStates()` currently sends all player states to all ready clients.
- This includes self state (client drops it later), which still costs recv.

2. High default tick rates
- `ClientToServer = 60`, `ServerToClients = 60` in `Replication.lua`.

3. Forced heartbeat updates
- Client sends forced state every `0.5s` even if unchanged.

4. Animation retransmit window
- Client continues sending for `1.0s` after animation change.

5. Viewmodel action cadence
- `ViewmodelActions.MinInterval = 0.03` can create dense action traffic.

6. Unscoped snapshots/relays
- Initial state snapshots and viewmodel snapshots/actions are not match-scoped.

7. VFXRep broad targets
- `"Others"`/`"All"` traffic can hit players outside relevant gameplay scope.

8. Duplicate ready signaling paths
- `ClientReplicationReady` is fired in multiple startup points.

## Break-Risk Areas (What Can Regress)

1. Hit validation quality
- `HitValidator:StorePosition(...)` uses replicated position history.
- Too-aggressive send reduction can hurt lag compensation and hit fairness.

2. Remote smoothness
- Interpolation buffer in `RemoteReplicator` relies on consistent updates.
- Too low update rate or too high deltas can cause stutter/teleport feel.

3. Animation correctness
- AnimationId + retransmit logic protects against packet drop.
- Over-cutting retransmit can cause missed state transitions remotely.

4. Crouch stance correctness
- `CrouchStateChanged` drives stance/hitbox assumptions.
- Desync here can break visuals and hit detection expectations.

5. Join-in-progress correctness
- `SendInitialStatesToPlayer` and `SendViewmodelActionSnapshotToPlayer` must still fully hydrate new clients.

6. Lobby/training transitions
- Existing `InLobby` logic interacts with third-person/viewmodel behavior.
- Match/lobby filters must not hide expected training/lobby entities.

## Phased Fix Plan

### Phase 0: Baseline and Guardrails

Collect before/after numbers in these scenarios:
- solo lobby
- solo training/combat movement
- 1v1 duel
- 2v2 active combat

Track:
- recv average + peak
- remote movement smoothness
- hit registration consistency
- missing animation/action reports
- reason-level validation failures (`TargetNotAtPosition`, `StanceMismatch`, `LineOfSightBlocked`)

### Phase 1: Low-Risk, High-Impact

1. Remove self-echo state traffic
- In `ReplicationService:BroadcastStates`, exclude receiver's own state from their payload.
- Optional: if only one ready player, skip state broadcast entirely.

2. Tune replication rates conservatively
- `Replication.lua`: start with `30/30` (from `60/60`).

3. Tune delta and heartbeat carefully
- Increase deltas slightly.
- Move forced heartbeat from `0.5s` to `0.75-1.0s` only if hit validation remains stable.

4. Reduce animation retransmit window
- Test `1.0s -> 0.4-0.6s`.

5. Slightly relax viewmodel action min interval
- `0.03 -> 0.04-0.06` if actions remain responsive.

### Phase 2: Scope By Match/Area

1. Add replication group filter helper in `ReplicationService`
- Same-match players only for:
  - `BroadcastStates`
  - `SendInitialStatesToPlayer`
  - viewmodel action relay
  - viewmodel action snapshot

2. Apply similar relevance filtering to VFXRep
- Avoid relaying gameplay VFX/Sound to non-match clients.

3. Keep training/lobby policy explicit
- Define allowed cross-visibility rules (if any).

### Phase 3: Structural Optimization

1. Interest management
- Distance/radius relevance for state + VFX.

2. Payload compaction
- Replace repeated strings (`weaponId/action/track`) with compact IDs where practical.

3. Channel separation
- Keep critical events reliable, move continuous state to drop-tolerant channels where supported.

## Validation Checklist Per Phase

1. No regressions in:
- firing/hit confirmation
- crouch/slide stance behavior
- join-in-progress hydration
- emote/lobby weapon hiding/restoring
- projectile validation pass rate / false reject rate

2. Remote quality checks:
- no obvious jitter increase
- no animation lockups
- no missing weapon action replication

3. Metrics:
- recv reduced in all baseline scenarios
- spikes smaller or less frequent

## Rollback Triggers

Rollback latest change if any of these appear:
- hit registration complaints increase
- remote movement visibly choppy
- common animation desync reports
- frequent missing viewmodel/third-person actions
- spike in server-side reject reasons tied to lag compensation/stance checks

Hard rollback rule:
- if gameplay regresses, rollback even if recv improves significantly

## Execution Order Recommendation

Recommended order for implementation:
1. self-echo removal
2. single-player broadcast skip
3. rate/delta tuning
4. match-scoped state/action/snapshot filtering
5. VFX/Sound scope filtering
6. advanced compaction/interest management

## Owner Notes

- Keep changes behind small config toggles where possible.
- Ship one phase at a time and compare recv + gameplay quality after each phase.
- Remove this temp doc once final optimization doc is merged.
- For high-pop tests, treat ~90 recv spikes at ~20 active players as acceptable when gameplay remains stable.
