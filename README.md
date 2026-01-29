# MovieeRedo - FPS Framework

A comprehensive Roblox FPS framework featuring custom character physics, first-person viewmodel system, kit abilities, weapon systems, and client-predicted movement.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Runtime Initialization](#runtime-initialization)
3. [Player Handling Lifecycle](#player-handling-lifecycle)
4. [Input System](#input-system)
5. [Movement System](#movement-system)
6. [Camera System](#camera-system)
7. [Character System](#character-system)
8. [Replication System](#replication-system)
9. [Weapon System](#weapon-system)
10. [Viewmodel System](#viewmodel-system)
11. [Kit System](#kit-system)
12. [Configuration](#configuration)
13. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Repo Structure

```
src/
├── ReplicatedStorage/
│   ├── Global/              # Config sources (Camera/Controls/Character/Movement/etc)
│   ├── Shared/              # Shared utilities, Net wrapper, Config aggregator
│   ├── Game/                # Gameplay modules (Movement, Weapons, Viewmodel, etc)
│   ├── Configs/             # UI & gameplay configs (LoadoutConfig, KitConfig, etc)
│   ├── CoreUI/              # UI framework and modules
│   ├── KitSystem/           # Kit abilities (server & client)
│   └── CrosshairSystem/     # Crosshair rendering
│
├── ServerScriptService/
│   └── Server/
│       ├── Initializer.server.lua    # Server entrypoint
│       ├── Registry/                 # Service registry
│       └── Services/                 # Server services
│
└── StarterPlayer/
    └── StarterPlayerScripts/
        └── Initializer/
            ├── Initializer.client.lua    # Client entrypoint
            ├── Registry/                 # Controller registry
            └── Controllers/              # Client controllers
```

### Core Design Patterns

| Pattern | Description |
|---------|-------------|
| **Registry** | Services/Controllers registered by name, accessed via `registry:TryGet("Name")` |
| **Loader** | Standardized `Init(registry, net)` → `Start()` lifecycle |
| **Locations** | Centralized module paths (`Locations.Shared`, `Locations.Game`, etc) |
| **Net** | Wrapper around RemoteEvents with named events |
| **State Machine** | `MovementStateManager` handles Walking/Sprinting/Crouching/Sliding |

### Custom Character System

The framework uses a "bean" character with separate physics and visual components:

| Component | Purpose |
|-----------|---------|
| `Root` | Physics body with VectorForce for movement |
| `Rig` | Visual R15 rig that follows Root position |
| `Collider` | Hitbox parts for raycast hit detection |
| `HumanoidRootPart` + `Head` | Anchored, for Humanoid compatibility |

---

## Runtime Initialization

### Server Boot (`Initializer.server.lua`)

```lua
1. Net:Init()                    -- Create RemoteEvents in ReplicatedStorage/Remotes
2. Registry.new()                -- Create service registry
3. Loader:Load(entries, ...)     -- Load services in order:
   ├── CollisionGroupService     -- Physics collision groups
   ├── CombatService             -- Damage, health, combat resources
   ├── CharacterService          -- Spawn/manage player characters
   ├── KitService                -- Kit abilities
   ├── MatchService              -- Match/round logic
   ├── ReplicationService        -- Server-to-client state sync
   ├── MovementService           -- Server-side movement validation
   ├── GadgetService             -- Ziplines, etc
   ├── DebugLogService           -- Logging
   ├── WeaponService             -- Server-side weapon hit validation
   ├── EmoteService              -- Emotes
   ├── DummyService              -- Training dummies
   └── KnockbackService          -- Knockback physics
```

### Client Boot (`Initializer.client.lua`)

```lua
1. Net:Init()                    -- Wait for RemoteEvents
2. SoundManager:Init()           -- Audio system
3. Registry.new()                -- Create controller registry
4. Loader:Load(entries, ...)     -- Load controllers in order:
   ├── Input                     -- InputController/InputManager
   ├── UI                        -- UIController (HUD, menus)
   ├── Character                 -- CharacterController (spawn, rigs, ragdolls)
   ├── Movement                  -- MovementController (physics movement)
   ├── AnimationController       -- Character animations
   ├── Ping                      -- PingController (latency display)
   ├── Replication               -- ReplicationController (position sync)
   ├── Camera                    -- CameraController (first/third person)
   ├── Viewmodel                 -- ViewmodelController (first-person arms)
   ├── KitVFX                    -- Kit visual effects
   ├── Weapon                    -- WeaponController (shooting, reloading)
   └── Combat                    -- CombatController (combat UI)
5. EmoteService.init()           -- Emote replication listener
```

---

## Player Handling Lifecycle

### Spawn Flow

```
Player joins game
    ↓
Server: CharacterService → PlayerAdded → fires "ServerReady" to client
    ↓
Client: CharacterController receives "ServerReady" → fires "RequestCharacterSpawn"
    ↓
Server: CharacterService:SpawnCharacter()
    ├── Creates Model with Humanoid, HumanoidRootPart, Head
    ├── Sets player.Character
    ├── Initializes CombatService resources
    ├── Registers with ReplicationService
    └── Fires "CharacterSpawned" to ALL clients
    ↓
Client: CharacterController:_onCharacterSpawned(character)
    ├── LOCAL player: _setupLocalCharacter()
    │   ├── Clones Collider, Root from CharacterTemplate
    │   ├── Sets up VectorForce on Root for physics movement
    │   ├── Creates visual Rig via RigManager
    │   ├── Sets up crouch welds
    │   ├── Notifies MovementController:OnLocalCharacterReady()
    │   ├── Notifies AnimationController:OnLocalCharacterReady()
    │   ├── Notifies ReplicationController:OnLocalCharacterReady()
    │   └── Fires "CharacterSetupComplete" to server
    │
    └── REMOTE player: _setupRemoteCharacter()
        ├── Creates Rig for remote player
        ├── Sets up Collider for hit detection
        └── Notifies AnimationController:OnOtherCharacterSpawned()
```

### Death & Respawn Flow

```
Local player dies (Humanoid.Health ≤ 0)
    ↓
CharacterController: Humanoid.Died → fires "RequestRespawn" to server
    ↓
Server: CharacterService → SpawnCharacter() (restarts spawn flow)
```

### Ragdoll Flow

```
Server: CharacterService:Ragdoll(player, duration, options)
    ├── Sets character:SetAttribute("RagdollActive", true)
    └── Fires "RagdollStarted" to ALL clients
    ↓
All Clients: CharacterController:_onRagdollStarted()
    ├── Gets visual Rig from RigManager
    ├── RagdollSystem:RagdollRig() applies physics
    └── For local player: CameraController:SetRagdollFocus(rigHead)
    ↓
After duration OR Server: CharacterService:Unragdoll(player)
    └── Fires "RagdollEnded" to ALL clients
    ↓
All Clients: CharacterController:_onRagdollEnded()
    ├── RagdollSystem:UnragdollRig() restores rig
    └── For local player: CameraController:ClearRagdollFocus()
```

---

## Input System

### Files

| File | Purpose |
|------|---------|
| `Controllers/Input/InputController.lua` | API wrapper, exposes input methods |
| `Controllers/Input/InputManager.lua` | Core input handling (keyboard, gamepad, touch) |
| `Global/Controls.lua` | Keybind configuration |

### Input Flow

```
UserInputService (WASD/gamepad/touch)
    ↓
InputManager:SetupKeyboardMouse() / SetupGamepad() / SetupTouch()
    ↓
InputManager:UpdateMovement() → fires "Movement" callbacks
    ↓
InputManager:FireCallbacks(inputType, ...)
    ↓
MovementController / WeaponController / etc receive callbacks
```

### Callback Types

| Type | Payload | Consumers |
|------|---------|-----------|
| `Movement` | `Vector2` | MovementController |
| `Jump` | `boolean` | MovementController |
| `Sprint` | `boolean` | MovementController |
| `Crouch` | `boolean` | MovementController |
| `Slide` | `boolean` | MovementController |
| `Fire` | `boolean` | WeaponController |
| `Special` | `boolean` | WeaponController (ADS) |
| `Reload` | `boolean` | WeaponController |
| `Ability` | `Enum.UserInputState` | KitController |
| `Ultimate` | `Enum.UserInputState` | KitController |

### Gameplay Enable/Disable

```lua
InputManager:SetGameplayEnabled(false)  -- Disables all gameplay input
InputManager:ResetInputState()          -- Clears all held keys
```

---

## Movement System

### Files

| File | Purpose |
|------|---------|
| `Controllers/Movement/MovementController.lua` | Main movement runtime |
| `Controllers/Movement/MovementInputProcessor.lua` | Jump/slide input decisions |
| `Game/Movement/MovementStateManager.lua` | State machine (Walk/Sprint/Crouch/Slide) |
| `Game/Movement/MovementUtils.lua` | Physics helpers |
| `Game/Movement/SlidingSystem.lua` | Slide mechanics |
| `Game/Movement/WallJumpUtils.lua` | Wall jump detection |

### Movement Loop (Heartbeat)

```lua
RunService.Heartbeat → UpdateMovement(dt)
    ├── CheckDeath()
    ├── UpdateCachedCameraRotation()
    ├── CheckGrounded() → MovementStateManager:UpdateGroundedState()
    ├── Handle slide/jump-cancel buffering (SlidingSystem)
    ├── UpdateRotation() (face camera or movement direction)
    ├── ApplyMovement() (VectorForce on Root)
    └── Update FOV/speed VFX
```

### State Machine

```
Priority: Walking (1) < Sprinting (2) < Crouching (3) < Sliding (4)

Transitions:
  Walking ↔ Sprinting (sprint key or AutoSprint)
  Walking/Sprinting → Crouching (crouch key)
  Walking/Sprinting → Sliding (crouch while moving + grounded)
  Sliding → Crouching (slide ends while crouch held)
  Crouching → Walking/Sprinting (uncrouch)
```

### Physics

The character uses a custom physics system instead of Humanoid:

- **VectorForce** on Root part applies movement forces
- **AlignOrientation** handles character rotation
- **Raycast** for ground detection
- **No Humanoid WalkSpeed** - movement is force-based

---

## Camera System

### Files

| File | Purpose |
|------|---------|
| `Controllers/Camera/CameraController.lua` | Main camera runtime |
| `Controllers/Camera/ScreenShakeController.lua` | Screen shake effects |
| `Shared/Util/FOVController.lua` | FOV effects (sprint, slide, etc) |

### Camera Loop (RenderStep)

```lua
RunService:BindToRenderStep("MovieeV2CameraController", RenderPriority.Camera + 10, ...)
    ↓
CameraController:UpdateCamera()
    ├── Enforce CameraType = Scriptable
    ├── Update angles from input
    ├── Apply crouch offset transitions
    ├── Dispatch to mode-specific update:
    │   ├── UpdateOrbitCamera()       -- Third person, rotate to movement
    │   ├── UpdateShoulderCamera()    -- Third person, over shoulder
    │   └── UpdateFirstPersonCamera() -- First person
    └── Update FOV via FOVController
```

### Camera Modes

| Mode | Description | Character Rotation |
|------|-------------|-------------------|
| `Orbit` | Third person, camera orbits character | Rotates to movement direction |
| `Shoulder` | Third person, over-shoulder view | Rotates to camera direction |
| `FirstPerson` | First person view | Rotates to camera direction |

### Mode Switching

Default key: `T` cycles through modes

```lua
CameraController:CycleCameraMode()
CameraController:SetCameraMode("FirstPerson")
```

---

## Character System

### Files

| File | Purpose |
|------|---------|
| `Controllers/Character/CharacterController.lua` | Client-side character management |
| `Controllers/Character/AnimationController.lua` | Character animations |
| `Services/Character/CharacterService.lua` | Server-side character spawning |
| `Game/Character/CharacterLocations.lua` | Part lookup helpers |
| `Game/Character/RigManager.lua` | Visual rig creation/management |
| `Game/Character/RagdollSystem.lua` | Ragdoll physics |
| `Game/Character/CrouchUtils.lua` | Crouch collider switching |

### Character Template

Located at `ReplicatedStorage/CharacterTemplate`, contains:

| Part | Purpose |
|------|---------|
| `Root` | Physics body (VectorForce attached here) |
| `Rig/` | Visual R15 rig folder |
| `Collider/` | Hitbox parts (Standing/Crouching subfolders) |
| `Humanoid` | Required for animations |
| `HumanoidRootPart` | Required for Humanoid (anchored) |
| `Head` | Required for Humanoid (anchored) |

### Animation System

The AnimationController handles character animations:

```lua
-- State → Animation mapping
STATE_ANIMATIONS = {
    Walking = "WalkingForward",
    Sprinting = "WalkingForward",
    Crouching = "CrouchWalkingForward",
    IdleStanding = "IdleStanding",
    IdleCrouching = "IdleCrouching",
}
```

Animations update based on:
- Movement state (Walking, Sprinting, Crouching, Sliding)
- Movement direction (Forward, Left, Right, Backward)
- Grounded state (Jump, Falling, Landing)

---

## Replication System

### Files

| File | Purpose |
|------|---------|
| `Controllers/Replication/ReplicationController.lua` | Client controller |
| `Game/Replication/ClientReplicator.lua` | Sends local state to server |
| `Game/Replication/RemoteReplicator.lua` | Receives/interpolates remote players |
| `Services/Replication/ReplicationService.lua` | Server broadcaster |
| `Global/Replication.lua` | Update rates, compression settings |

### Replication Flow

```
Local Client: MovementController moves Root
    ↓
ClientReplicator:SyncParts() (every Heartbeat)
    ├── Moves Rig parts to match Root
    └── Moves HumanoidRootPart/Head (anchored)
    ↓
ClientReplicator:SendStateUpdate() (throttled ~60Hz)
    ├── Compresses position/rotation/velocity/state
    └── Fires "CharacterStateUpdate" to server
    ↓
Server: ReplicationService broadcasts to other clients (batched)
    └── Fires "CharacterStateReplicated"
    ↓
Other Clients: RemoteReplicator:OnStatesReplicated()
    ├── Buffers snapshots per remote player
    └── Interpolates toward buffered states (Heartbeat loop)
```

### Compression

- Position delta threshold: ~0.1 studs
- Rotation delta threshold: ~1 degree
- Velocity delta threshold: ~0.5 studs/s
- Delta compression skips unchanged values

---

## Weapon System

See [docs/WEAPON_CONTROLLER.md](docs/WEAPON_CONTROLLER.md) for complete API reference.

### Overview

```
WeaponController (client)
    ├── WeaponAmmo (ammo management)
    ├── WeaponCooldown (cooldown tracking)
    ├── WeaponFX (visual effects)
    └── WeaponRaycast (raycast utilities)
    ↓
Action Modules (per weapon)
    ├── init.lua (lifecycle, cancel logic)
    ├── Attack.lua (fire logic)
    ├── Reload.lua (reload logic)
    ├── Inspect.lua (inspect animation)
    └── Special.lua (ADS for guns, ability for melee)
```

### Weapon Slots

| Slot | Example Weapons |
|------|-----------------|
| `Primary` | Shotgun, AssaultRifle, Sniper |
| `Secondary` | Revolver, Pistol |
| `Melee` | Knife, ExecutionerBlade |
| `Fists` | Default (kit abilities) |

---

## Viewmodel System

See [docs/VIEWMODEL_CONTROLLER.md](docs/VIEWMODEL_CONTROLLER.md) for complete API reference.

### Overview

The ViewmodelController renders first-person arms/weapons:

```
ViewmodelController
    ├── Creates rigs for each slot (Fists, Primary, Secondary, Melee)
    ├── Preloads all animations on loadout change
    ├── Applies spring-based visual effects:
    │   ├── Camera sway (rotation spring)
    │   ├── Walk bob (bob spring)
    │   ├── Slide tilt (tilt springs)
    │   └── External offset (SetOffset API)
    └── Handles ADS via updateTargetCF()
```

### Configuration

`Configs/ViewmodelConfig.lua`:

```lua
SlideTilt = {
    Enabled = true,
    AngleDeg = 18,  -- roll
    Offset = Vector3.new(0.14, -0.12, 0.06),
    RotationDeg = Vector3.new(8, 30, 0),  -- pitch, yaw, (unused)
    TransitionSpeed = 10,
},
```

---

## Kit System

See [docs/KIT_SYSTEM.md](docs/KIT_SYSTEM.md) for complete API reference.

### Architecture

```
Client                                  Server
──────                                  ──────
KitController                           KitService
    │                                       │
    ├── Input routing                       ├── Authority (validation)
    ├── Client prediction                   ├── State management
    └── UI events                           └── VFX broadcast
    ↓                                       ↓
ClientKits/                             Kits/
    └── Per-kit handlers                    └── Server logic
    ↓
KitVFXController → VFX/
    └── Visual effects for all players
```

### Ability Flow

1. Player presses ability key
2. KitController routes to ClientKit
3. ClientKit starts local prediction (animation, effects)
4. ClientKit calls `abilityRequest.Send()` to server
5. KitService validates and executes
6. Server broadcasts VFX event to ALL clients
7. VFXController plays effects for all players

---

## Configuration

### Config Sources (`Global/`)

| File | Purpose |
|------|---------|
| `Camera.lua` | Camera modes, smoothing, FOV |
| `Character.lua` | Character physics, collider settings |
| `Movement.lua` | Walk/sprint/crouch speeds, jump force |
| `Controls.lua` | Keybinds |
| `Replication.lua` | Update rates, compression |
| `System.lua` | Network settings, logging |

### Config Aggregator

`Shared/Config/Config.lua` aggregates all Global/* configs.

### ConfigCache

`Shared/Util/ConfigCache.lua` precomputes commonly-used values for hot paths:

```lua
ConfigCache.WALK_SPEED
ConfigCache.SPRINT_SPEED
ConfigCache.MOVEMENT_FORCE
ConfigCache.GRAVITY
-- etc
```

---

## Troubleshooting

### Movement Issues

| Issue | Check |
|-------|-------|
| Player not moving | `MovementController:UpdateMovement()` → `ApplyMovement()` |
| Wrong speed | `ConfigCache.lua` (WALK_SPEED, SPRINT_SPEED) |
| Not grounded | `MovementUtils:CheckGrounded()` raycast |
| Drifting | VectorForce on Root part, damping settings |

### Jump/Wall-Jump Issues

| Issue | Check |
|-------|-------|
| Jump not working | `MovementInputProcessor:OnJumpPressed()` |
| Wall-jump failing | `WallJumpUtils:AttemptWallJump()` raycast |
| Jump-cancel broken | `SlidingSystem` buffering logic |

### Camera Issues

| Issue | Check |
|-------|-------|
| Camera fighting | Other camera scripts (PlayerModule) |
| Not scriptable | `CameraController:UpdateCamera()` enforces it |
| Wrong mode | `CameraController.CurrentMode` |

### Replication Issues

| Issue | Check |
|-------|-------|
| Remote players jitter | `RemoteReplicator` interpolation/buffer delay |
| Position lag | `ClientReplicator` send rate, compression thresholds |
| Not updating | `CharacterStateUpdate` remote, delta suppression |

### Viewmodel Issues

| Issue | Check |
|-------|-------|
| Not visible | Camera mode must be FirstPerson |
| Wrong weapon | `ViewmodelController._activeSlot` |
| No animations | `ViewmodelAnimator:PreloadRig()` was called |

### Kit Issues

| Issue | Check |
|-------|-------|
| Ability not firing | ClientKit must call `abilityRequest.Send()` |
| VFX only local | VFX module must exist in `KitSystem/VFX/` |
| Cooldown wrong | Server kit must return `true` on success |

---

## Network Remotes

All remotes defined in `Shared/Net/Remotes.lua`:

### Character/Spawn

| Remote | Direction | Purpose |
|--------|-----------|---------|
| `ServerReady` | S→C | Server finished initializing |
| `RequestCharacterSpawn` | C→S | Client requests spawn |
| `RequestRespawn` | C→S | Client requests respawn |
| `CharacterSpawned` | S→C* | Character model ready |
| `CharacterRemoving` | S→C* | Character being removed |
| `CharacterSetupComplete` | C→S | Client finished setup |

### Replication

| Remote | Direction | Purpose |
|--------|-----------|---------|
| `CharacterStateUpdate` | C→S | Position/state update (unreliable) |
| `CharacterStateReplicated` | S→C* | Batched remote states (unreliable) |
| `RequestInitialStates` | C→S | Request current state snapshot |

### Combat/Kit

| Remote | Direction | Purpose |
|--------|-----------|---------|
| `KitRequest` | C→S | Kit actions (equip, ability, etc) |
| `KitState` | S→C | Kit state sync and events |
| `WeaponFired` | C→S | Weapon fire notification |
| `HitConfirmed` | S→C | Hit confirmation from server |

### Misc

| Remote | Direction | Purpose |
|--------|-----------|---------|
| `CrouchStateChanged` | C→S, S→C* | Crouch visual replication |
| `RagdollStarted` / `RagdollEnded` | S→C* | Ragdoll lifecycle |
| `ToggleRagdollTest` | C→S | Debug ragdoll toggle |

*C→S = Client to Server, S→C = Server to Client, S→C* = Server to All Clients

---

## Additional Documentation

- [docs/WEAPON_CONTROLLER.md](docs/WEAPON_CONTROLLER.md) - Weapon system API
- [docs/VIEWMODEL_CONTROLLER.md](docs/VIEWMODEL_CONTROLLER.md) - Viewmodel system API
- [docs/KIT_SYSTEM.md](docs/KIT_SYSTEM.md) - Kit abilities API
- [docs/CAMERA_CONTROLLER.md](docs/CAMERA_CONTROLLER.md) - Camera system
- [docs/COMBAT_SYSTEM.md](docs/COMBAT_SYSTEM.md) - Combat/damage system
- [docs/AIM_ASSIST.md](docs/AIM_ASSIST.md) - Aim assist system
- [docs/RAGDOLL_SYSTEM.md](docs/RAGDOLL_SYSTEM.md) - Ragdoll physics
- [docs/GADGET_SYSTEM.md](docs/GADGET_SYSTEM.md) - Gadgets (Zipline, etc)

---

*Last updated: January 2026*
