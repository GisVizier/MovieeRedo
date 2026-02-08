# Voxel Destruction System

This project uses the `VoxelDestruction` module in `ReplicatedStorage/Shared/Modules/VoxelDestruction`. The previous VoxManager API does not apply here. This doc reflects the current, working, server-authoritative setup and the integration work completed in this repo.

## Architecture Summary

- **Authoritative destruction runs on the server.**
- **Clients only request destruction** (via kit ability requests). The server performs destruction and replicates to all clients using the `_ClientDestruction` RemoteEvent inside the module.
- **Voxel pieces are visible on the server** because their folders are parented to `workspace` on the server.
- **Debris is visible and resets quickly** (see Settings section below).

## Core Module

**Module:** `ReplicatedStorage/Shared/Modules/VoxelDestruction/init.lua`

**Entry points:**
- `Destroy(focus, overlapParams?, voxelSize?, debrisCount?, reset?)`
- `Hitbox(focus, overlapParams?, voxelSize?, debrisCount?, reset?)`
- `Repair(wallOrModel)`

The module handles:
- Part slicing and voxelization
- Debris generation
- Reset timers
- Replication to clients

### Replication Flow

1. Server calls `Destroy(...)`.
2. Server fires `_ClientDestruction` RemoteEvent to all clients with a serialized hitbox payload.
3. Each client locally runs `Destroy` with a temporary hitbox, generating matching voxel visuals.

**Important:** This is intentionally **server-only authoritative destruction** now. Clients no longer spawn local debris; they only send requests.

## Kit Integration (HonoredOne)

**Client kit:** `ReplicatedStorage/KitSystem/ClientKits/HonoredOne/init.lua`  
Sends destruction requests only. It does not spawn local voxel debris.

**Server kit:** `ReplicatedStorage/KitSystem/Kits/HonoredOne.lua`  
Receives requests and calls `VoxelDestruction.Destroy(...)` on the server, which then replicates to all clients.

### Ability Request Pipeline

The ability request send function now supports multiple sends per ability:

- `abilityRequest.Send({ allowMultiple = true, ... })`

This is required for continuous Blue destruction ticks and late sends like `blueHit` and `redHit`.

## Settings (Current)

**File:** `ReplicatedStorage/Shared/Modules/VoxelDestruction/Settings.lua`

- `DebrisDefaultBehavior = true`
- `DebrisAnchored = false` (debris falls)
- `DebrisReset = 3` (faster cleanup)
- `OnServer = true` (server authoritative)
- `OnClient = true` (clients render replicated destruction)

## Server Visibility

Voxel folders are parented to:

- **Server:** `workspace`
- **Client:** `workspace.CurrentCamera` (fallback to `workspace` if needed)

This ensures voxels are visible on the server while keeping client rendering scoped.

## Usage Guide (Server)

Example server-only usage:

```lua
local VoxelDestruction = require(ReplicatedStorage.Shared.Modules.VoxelDestruction)

local hitbox = Instance.new("Part")
hitbox.Size = Vector3.new(12, 12, 12)
hitbox.CFrame = CFrame.new(0, 10, 0)
hitbox.Anchored = true
hitbox.CanCollide = false
hitbox.CanQuery = true
hitbox.Transparency = 1
hitbox.Parent = workspace

VoxelDestruction.Destroy(hitbox, nil, 2, 5, nil)
hitbox:Destroy()
```

## Troubleshooting

If destruction does not replicate:

- Make sure the **server** is calling `VoxelDestruction.Destroy(...)`.
- Ensure client kits only send requests (no local destruction).
- Verify `OnClient = true` and `OnServer = true` in settings.
- Confirm `_ClientDestruction` RemoteEvent exists inside the module.

If debris is invisible:

- Set `DebrisDefaultBehavior = true`
- Set `DebrisAnchored = false` for falling debris
- Ensure `DebrisReset` is > 0 so cleanup runs

## Notes for New Abilities

Keep destruction modular and server-authoritative:

1. Client computes the impact position and sends it to the server.
2. Server validates (range, cooldown, etc).
3. Server calls `VoxelDestruction.Destroy(...)`.

Do not spawn debris locally in client kits.
