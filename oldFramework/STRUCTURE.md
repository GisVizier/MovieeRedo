# STRUCTURE.md

This document summarizes the v2 layout and conventions.

## v2 Root

- `src_v2/ReplicatedStorage/`
  - `Assets/` (Studio-managed assets; unknown instances preserved)
  - `Global/` (source-of-truth config modules)
    - `Camera/`, `Character/`, `Controls/`, `Movement/`, `Replication/`, `System/`
  - `Shared/`
    - `Net/` (network schema + wrappers)
    - `Util/` (shared utilities like Locations, Loader, WeldUtils, ConfigCache, Sera)
    - `Types/` (shared types like AnimationIds)
  - `Game/`
    - `Character/` (character domain modules)
      - `Rig/` (rig + ragdoll)
    - `Movement/` (movement domain modules)
    - `Replication/` (replication domain modules)

- `src_v2/ServerScriptService/`
  - `Server/`
    - `Initializer.server.lua`
    - `Registry/`
    - `Services/` (Character, Replication, Movement, Collision)

- `src_v2/StarterPlayerScripts/`
  - `Initializer/`
    - `Initializer.client.lua`
    - `Registry/`
    - `Controllers/` (Input, Character, Movement, Replication, Camera, AnimationController)

- `src_v2/ServerStorage/`
  - `Models/` (Character template instances)

## Module Convention (MANDATORY)

All v2 modules use the folder + `init.lua` convention:
- Module `X` = folder `X/` with `init.lua` inside
- No standalone `X.lua` for v2 modules

## Net Convention

- Remotes schema: `ReplicatedStorage/Shared/Net/Remotes/`
- Remote instances folder: `ReplicatedStorage/Remotes`

## Notes

- `Global/*` modules are authoritative configs.
- `Metadata/` is reserved for instance data (e.g., animations).

## Current Status (v2 Port)

- **Net/Registry/Loader**: stable; Rojo `v2.project.json` mapping ok.
- **Character**: server spawn + client setup working; rig optional; ragdoll present.
- **Movement**: core movement (run/walk/jump/slide/crouch) works.
- **Replication**: basic character/movement replication active; Sera schema copied.
- **Animations**: local playback works; remote looped animations not stopping correctly.

## Known Issues (Active)

- **Slope tech**: slope magnet + slope walk not working (affects walk up/down and slide on slopes).
- **Rig collision**: rig parts still collidable/queryable in some cases (affects crouch/uncrouch and slope logic).
- **Sliding end**: slide does not stop correctly when standing (likely tied to crouch/rig clearance).

## Next Fixes (Planned)

- Force rig parts `CanCollide=false`, `CanQuery=false`, `CanTouch=false` on creation + local setup.
- Exclude rig container from any character overlap checks if needed.
- Port old animation category stop logic for other players (State/Idle/Airborne/Action).
- Re-verify slope magnet + ground checks after rig collision fixes.
