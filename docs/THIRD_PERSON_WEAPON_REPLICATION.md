# Third-Person Weapon Replication

This document defines the current third-person weapon replication system and the required methods/patterns for future changes.

## Purpose

Replicate a player's active viewmodel weapon to other clients as a third-person cosmetic model with:
- weapon equip/unequip
- action playback (fire/reload/inspect/ads/special)
- aim pitch (look up/down)
- crouch/slide vertical offset

## Core Components

- `src/ReplicatedStorage/Game/Replication/ClientReplicator.lua`
- `src/ServerScriptService/Server/Services/Replication/ReplicationService.lua`
- `src/ReplicatedStorage/Game/Replication/RemoteReplicator.lua`
- `src/ReplicatedStorage/Game/Weapons/ThirdPersonWeaponManager.lua`
- `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Weapon/WeaponController.lua`

## Data Flow

1. Local weapon action occurs in `WeaponController`.
2. `WeaponController:_replicateViewmodelAction(...)` forwards to `ReplicationController`.
3. `ReplicationController` calls `ClientReplicator:ReplicateViewmodelAction(...)`.
4. `ClientReplicator` compresses and fires `ViewmodelActionUpdate` to server.
5. `ReplicationService` validates/relays as `ViewmodelActionReplicated`.
6. `RemoteReplicator` receives and applies action to target player's `ThirdPersonWeaponManager`.
7. On heartbeat, `RemoteReplicator` updates transform using replicated root CFrame + aim pitch + crouch state.

## Required Public Methods

### ClientReplicator

- `ReplicateViewmodelAction(weaponId, actionName, trackName, isActive)`
- `ForceLoadoutRefresh()`

Requirements:
- Do not send blank `actionName`.
- Allow empty `weaponId` only for `Unequip`.
- Preserve sequence ordering and min interval throttling.

### RemoteReplicator

- `OnViewmodelActionReplicated(compressedPayload)`
- `OnCrouchStateChanged(otherPlayer, isCrouching)`
- `_applyReplicatedViewmodelAction(remoteData, payload)`
- `_equipRemoteWeapon(remoteData)`

Requirements:
- Ignore local player's replicated actions.
- Queue action/crouch state if remote player record does not exist yet.
- Apply queued state once remote record is created.

### ThirdPersonWeaponManager

- `EquipWeapon(weaponId): boolean`
- `UnequipWeapon()`
- `ApplyReplicatedAction(actionName, trackName, isActive)`
- `SetCrouching(isCrouching)`
- `UpdateTransform(rootCFrame, aimPitch)`
- `Destroy()`

Requirements:
- Keep model root priority: `HumanoidRootPart` before `Camera`.
- Strip `Fake` model from cloned viewmodel.
- Use `SetCrouching` as authoritative override when provided.
- Keep transform root-based; do not attach to torso by default.

## Crouch Logic (Current)

Source events:
- Existing `CrouchStateChanged` remote event.
- Local movement state (`IsCrouching` or `IsSliding`) for local third-person preview path.

Behavior:
- `RemoteReplicator` stores `remoteData.IsCrouching`.
- Each heartbeat: `WeaponManager:SetCrouching(remoteData.IsCrouching)` before `UpdateTransform`.
- `ThirdPersonWeaponManager` computes stance offset from crouch head/body delta when available, else fallback offset.

## Animation Priority Rules

Use these priorities for third-person weapon tracks:
- `Idle`, `Walk`, `Run`: `Movement`
- `ADS`: `Action`
- `Fire`, `Reload`, `Inspect`, `Special`, `Equip`: `Action4`

Rationale:
- locomotion should not override high-priority action tracks.

## Action Replication Rules

Required:
- Replicate both start and stop for cancelable actions.
- Respect `isActive == false` to stop tracks where applicable.

Current caveat:
- Inspect cancellation can desync if stop-state is not replicated/handled consistently.

## Future Change Rules

- Reuse existing network events before adding new remotes.
- Keep server relay stateless and sequence-safe.
- Keep root-driven transform for stability.
- Keep action names and track names short and stable.
- Avoid per-frame expensive lookups; cache when possible.

## Debug Checklist

If remote weapon behavior is wrong:

1. Confirm `ViewmodelActionUpdate` is sent from local client.
2. Confirm `ViewmodelActionReplicated` is relayed by server.
3. Confirm remote client receives action and has `remoteData.WeaponManager`.
4. Confirm `CrouchStateChanged` arrives on remote client.
5. Confirm `SetCrouching(...)` and `UpdateTransform(...)` are both called each frame.
6. Confirm equipped weapon config has valid `ModelPath` and optional `Replication.Offset/Scale`.

