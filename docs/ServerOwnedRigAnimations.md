# Server-Authoritative Rig Animations

## Overview

Rig animations (kit/ability animations on the 3rd-person character rig) are now **server-authoritative**. The server creates rigs, validates animation requests, tracks active looped animations for late joiners, and **reliably broadcasts** play/stop commands to all clients. Each client plays the animation on their local copy of the rig's Animator.

This replaces the previous system where rig animations were relayed through the unreliable `VFXRep` remote with a JSON attribute fallback for reconciliation.

## Why This Changed

The old system had a fundamental reliability problem:

1. `VFXRep` is marked `unreliable = true` in `Remotes.lua`
2. Animation play/stop commands traveled: **Client A → VFXRep (unreliable) → Server → VFXRep (unreliable) → Client B**
3. Two unreliable hops meant looped animation stop requests could be silently dropped
4. A dropped stop packet caused looped animations to play forever on the remote client
5. The `RigAnimationState` player attribute was added as a patch, but only reconciled on specific triggers (character spawn, `ApplyDescription`), leaving windows where animations got stuck

## Why Not Pure Server-Side Animator Playback?

Rig parts are **anchored** and positioned every frame by the client via `BulkMoveTo`. Roblox's built-in Animator replication doesn't work properly on anchored rigs — the client's CFrame writes stomp the animation transforms. So animation playback must happen on each client's local Animator. The server's role is to **reliably relay** commands and **track state** for late joiners.

## Architecture

### Before (Old)

```
Client A (plays locally)
    ↓ VFXRep:Fire("Others", ...) [unreliable]
Server (relay only — no animation logic)
    ↓ VFXRep FireClient [unreliable]
Client B (loads track, plays on local Animator)
    + RigAnimationState attribute [JSON, reconcile on spawn/description]
```

### After (New)

```
Client A (sends request)
    ↓ Net:FireServer("RigAnimationRequest", ...) [RELIABLE]
Server (validates, tracks state, broadcasts)
    ↓ Net:FireClient("RigAnimationBroadcast", ...) [RELIABLE] to ALL clients
All Clients including A (play animation on local rig Animator)
    + Late joiners get active looped animations on ClientReplicationReady
```

## File Changes

### New Files

| File | Purpose |
|------|---------|
| `ServerScriptService/Server/Services/RigAnimation/RigAnimationService.lua` | Server service that owns rig Animators and handles play/stop requests |

### Modified Files

| File | Change |
|------|--------|
| `ReplicatedStorage/Shared/Net/Remotes.lua` | Added reliable `RigAnimationRequest` and `RigAnimationBroadcast` remotes |
| `ServerScriptService/Server/Initializer.server.lua` | Registered `RigAnimationService` (loads before `CharacterService`) |
| `ServerScriptService/Server/Services/Character/CharacterService.lua` | Calls `RigAnimationService:OnCharacterSpawned()` and `OnCharacterRemoving()` |
| `ServerScriptService/Server/Services/Replication/ReplicationService.lua` | Sends active rig animations to late joiners on `ClientReplicationReady` |
| `ReplicatedStorage/Game/Character/Rig/RigManager.lua` | `GetActiveRig()` now falls back to searching `workspace.Rigs` by `OwnerUserId` attribute (finds server-created rigs on clients) |
| `ReplicatedStorage/Game/Replication/RemoteReplicator.lua` | No longer calls `RigManager:CreateRig()` — waits for server-created rig to replicate |
| `StarterPlayer/.../AnimationController.lua` | `PlayRigAnimation`/`StopRigAnimation`/`StopAllRigAnimations` now fire reliable `RigAnimationRequest`. Listens for `RigAnimationBroadcast` to play/stop on local Animators. Removed ~200 lines of old VFXRep relay and attribute reconciliation code |
| `ReplicatedStorage/Game/Replication/ReplicationModules/RigAnimation.lua` | Kept as no-op stub with deprecation notice |

### Removed Code (from AnimationController)

- `_publishLocalRigAnimationState()` — JSON attribute publishing
- `_setLocalRigAnimationState()` / `_removeLocalRigAnimationState()` / `_clearLocalRigAnimationState()` — local state tracking
- `_decodeRemoteRigAnimationState()` — JSON attribute decoding
- `_reconcileRemoteRigAnimationState()` — attribute-based state reconciliation
- `_bindRigAnimationStateListeners()` / `_bindRigAnimationStateForPlayer()` / `_unbindRigAnimationStateForPlayer()` — per-player attribute watchers
- `_resendLocalRigStateToPlayer()` — late-joiner VFXRep resend
- `_onRemoteRigPlay()` / `_onRemoteRigStop()` / `_onRemoteRigStopAll()` — VFXRep receivers
- `_getRemoteKitTracks()` / `_playRemoteRigStateAnimation()` — remote track management
- `LocalRigAnimationState` / `OtherCharacterDesiredRigState` / `RigAnimationStateConnections` / `OtherCharacterKitTracks` — state properties
- VFXRep module registration in `Start()`

## How It Works Now

### Rig Creation (Server-Side)

1. `CharacterService:SpawnCharacter()` creates the character
2. It calls `RigAnimationService:OnCharacterSpawned(player, character)`
3. `RigAnimationService` calls `RigManager:CreateRig(player, character)` on the server
4. The rig is parented to `workspace.Rigs` and replicates to all clients automatically
5. Clients find the rig via `RigManager:GetActiveRig(player)` which searches `workspace.Rigs` by `OwnerUserId` attribute

### Playing Animations

1. Client calls `AnimationController:PlayRigAnimation("Blue", { Looped = true })`
2. Client fires `Net:FireServer("RigAnimationRequest", ...)` — **reliable** delivery guaranteed
3. Server's `RigAnimationService` validates the request and tracks the animation state
4. Server broadcasts `RigAnimationBroadcast` to **all** clients in the match — **reliable**
5. Each client (including the requester) receives the broadcast and plays the animation on their local copy of the rig's Animator

### Stopping Animations

1. Client calls `AnimationController:StopRigAnimation("Blue")`
2. Client fires `Net:FireServer("RigAnimationRequest", ...)` — **reliable**
3. Server removes the animation from its state tracking
4. Server broadcasts stop to all clients — **reliable**
5. Each client stops the track locally — **guaranteed delivery, no more stuck loops**

### Late Joiners

When a client fires `ClientReplicationReady`, the server sends all active looped rig animations via `RigAnimationBroadcast`. The joining client plays them on the local Animators, so they see the correct animation state immediately.

### Cleanup

- `CharacterService:RemoveCharacter()` calls `RigAnimationService:OnCharacterRemoving(player)` which clears server-side state
- `Players.PlayerRemoving` in `RigAnimationService` clears state
- `AnimationController:OnOtherCharacterRemoving()` cleans up `_rigAnimTracks` for the leaving player

## What Didn't Change

- **Character state animations** (walking, running, jumping, crouching) — still client-driven via `CharacterStateUpdate` / `AnimationIds` unreliable remote. These are high-frequency, non-critical animations where packet loss is acceptable.
- **Viewmodel animations** (1st-person arms/weapon) — still local-only, replicated via `ViewmodelActionUpdate` for spectators.
- **Third-person weapon animations** — still managed by `ThirdPersonWeaponManager`, separate system.
- **VFXRep for non-animation things** — Kon VFX, Sound, HonoredOne particles, Cloudskip effects all still use VFXRep.
- **Rig CFrame positioning** — `ClientReplicator` (local) and `RemoteReplicator` (remote) still move rig parts via `BulkMoveTo`. Only animation playback moved to the server.

## RigAnimationRequest Protocol

The `RigAnimationRequest` remote accepts a table with these fields:

### Play

```lua
{
    action = "Play",
    animName = "Blue",           -- Animation name from PreloadedAnimations
    Looped = true,               -- Optional, default false
    Priority = "Action4",        -- Optional, string or EnumItem
    FadeInTime = 0.15,           -- Optional, default 0.15
    Speed = 1,                   -- Optional, default 1
    StopOthers = true,           -- Optional, default true (stops other kit anims)
}
```

### Stop

```lua
{
    action = "Stop",
    animName = "Blue",           -- Animation name to stop
    fadeOut = 0.1,               -- Optional, default 0.1
}
```

### StopAll

```lua
{
    action = "StopAll",
    fadeOut = 0.15,              -- Optional, default 0.15
}
```

## Usage (Kit Developers)

The API is unchanged from the kit developer's perspective:

```lua
local animCtrl = ServiceRegistry:GetController("AnimationController")

-- Play a looped rig animation
animCtrl:PlayRigAnimation("Blue", { Looped = true, Priority = Enum.AnimationPriority.Action4 })

-- Stop a specific animation
animCtrl:StopRigAnimation("Blue", 0.1)

-- Stop all rig animations
animCtrl:StopAllRigAnimations(0.15)
```

The only difference is internal: these now fire a reliable remote to the server instead of an unreliable VFXRep event.
