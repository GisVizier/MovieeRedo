# AGENT.md

> **Complete AI Agent Guide for Roblox FPS Hero Shooter Development**

This document provides comprehensive guidance for AI agents working on this codebase. It consolidates architecture patterns, development workflows, system interactions, and critical implementation details.

---

## TABLE OF CONTENTS

1. [Project Overview](#project-overview)
2. [Development Environment](#development-environment)
3. [Project Structure](#project-structure)
4. [Core Systems Architecture](#core-systems-architecture)
5. [Critical Development Patterns](#critical-development-patterns)
6. [Network Architecture](#network-architecture)
7. [Configuration System](#configuration-system)
8. [RemoteEvent System](#remoteevent-system)
9. [Character System](#character-system)
10. [Movement Systems](#movement-systems)
11. [Weapon System](#weapon-system)
12. [Round System](#round-system)
13. [Common Tasks & Examples](#common-tasks--examples)
14. [Debugging & Troubleshooting](#debugging--troubleshooting)
15. [Performance Optimization](#performance-optimization)
16. [Security & Anti-Cheat](#security--anti-cheat)

---

## PROJECT OVERVIEW

### What is This Project?

A high-performance Roblox FPS hero shooter featuring:
- **Custom character physics** (no Humanoid dependency for movement)
- **Client-authoritative movement** with server relay
- **Advanced movement mechanics** (sliding, wall jumping, sprinting, crouching)
- **60Hz network replication** using UnreliableRemoteEvent
- **Modern constraint-based physics** (VectorForce, AlignOrientation)
- **Hero shooter mechanics** (kits, abilities, ultimates, loadouts)

### Key Statistics

| Metric | Value | Notes |
|--------|-------|-------|
| **Total Files** | 138+ Lua files | Organized across Services, Controllers, Systems, Utils |
| **Update Rate** | 60 Hz | Both client→server and server→clients |
| **Network Bandwidth** | ~2.4 KB/s per player | 40 bytes × 60 Hz (compressed) |
| **Max Players** | 20+ | Tested with 20 players = ~48 KB/s per client |
| **Physics System** | Modern Constraints | VectorForce + AlignOrientation |
| **RemoteEvents** | 50+ events | Centralized management system |

### Technology Stack

- **Rojo 7.5.1** - Filesystem sync tool
- **Sera** - High-performance buffer serialization library
- **UnreliableRemoteEvent** - High-frequency networking (60Hz)
- **Rokit/Aftman** - Tool dependency management
- **Selene 0.29.0** - Lua linter

---

## DEVELOPMENT ENVIRONMENT

### Tool Management

**⚠️ CRITICAL: User handles all Rojo commands. AI agents should NEVER run Rojo.**

- **Install tools:** `rokit install` (preferred) or `aftman install`
- **Available tools:** Rojo 7.5.1, Wally 0.3.2, Selene 0.29.0, Wally-package-types 1.5.1
- **Rojo server:** User runs manually, auto-syncs files to Roblox Studio
- **Linting:** `selene src/` - Run Selene linter on source files

### Development Workflow

```
1. User runs Rojo development server (always active)
2. Project stays automatically synced between VS Code and Roblox Studio
3. Edit Lua files in the `src/` directory
4. Changes appear immediately in Roblox Studio for testing
5. (Optional) Run linter: selene src/
```

### File Extensions

- `.server.lua` - Server scripts (ServerScriptService)
- `.client.lua` - Client scripts (StarterPlayerScripts)
- `.lua` - ModuleScripts (shared code)

---

## PROJECT STRUCTURE

### Directory Layout

```
src/
├── ReplicatedStorage/
│   ├── Configs/                    # Configuration files
│   │   ├── GameplayConfig.lua      # Movement, physics, sliding
│   │   ├── ControlsConfig.lua      # Input, camera, mobile
│   │   ├── SystemConfig.lua        # Network, debug, logging
│   │   ├── ReplicationConfig.lua   # Network settings
│   │   ├── HealthConfig.lua         # Health values, respawn
│   │   ├── AnimationConfig.lua     # Animation IDs, enums
│   │   ├── AudioConfig.lua         # Sound settings
│   │   ├── WeaponConfig.lua         # Weapon settings
│   │   ├── KitConfig.lua           # Kit/hero definitions
│   │   ├── LoadoutConfig.lua       # Loadout system
│   │   ├── RoundConfig.lua         # Round system settings
│   │   ├── ViewmodelConfig.lua     # Viewmodel settings
│   │   ├── InteractableConfig.lua  # Interactable objects
│   │   └── init.lua                # Config aggregator
│   ├── Modules/
│   │   ├── Locations.lua           # ⚠️ CRITICAL: Path registry
│   │   └── RemoteEvents.lua        # Centralized event management
│   ├── Systems/                    # Complex stateful systems
│   │   ├── Movement/
│   │   │   ├── MovementStateManager.lua
│   │   │   ├── MovementUtils.lua
│   │   │   ├── SlidingSystem.lua
│   │   │   ├── SlidingBuffer.lua
│   │   │   ├── SlidingPhysics.lua
│   │   │   ├── SlidingState.lua
│   │   │   └── WallJumpUtils.lua
│   │   ├── Character/
│   │   │   ├── CharacterUtils.lua
│   │   │   ├── CharacterLocations.lua
│   │   │   ├── CrouchUtils.lua
│   │   │   ├── RagdollSystem.lua
│   │   │   ├── RigManager.lua
│   │   │   └── RigRotationUtils.lua
│   │   ├── Core/
│   │   │   ├── LogService.lua
│   │   │   ├── ConfigCache.lua
│   │   │   ├── SoundManager.lua
│   │   │   ├── MouseLockManager.lua
│   │   │   └── UserSettings.lua
│   │   └── Round/
│   │       ├── PlayerStateManager.lua
│   │       ├── NPCStateManager.lua
│   │       └── CombinedStateManager.lua
│   ├── Utils/                      # Pure utility functions
│   │   ├── MathUtils.lua
│   │   ├── ValidationUtils.lua
│   │   ├── CompressionUtils.lua
│   │   ├── PartUtils.lua
│   │   ├── CollisionUtils.lua
│   │   ├── WallDetectionUtils.lua
│   │   ├── ServiceLoader.lua
│   │   ├── ServiceRegistry.lua
│   │   └── Sera/                   # Serialization library
│   │       ├── init.lua
│   │       └── Schemas.lua
│   ├── Weapons/
│   │   ├── Actions/
│   │   │   ├── Gun/                # Gun weapon types
│   │   │   └── Melee/              # Melee weapon types
│   │   ├── Configs/                # Weapon configuration
│   │   ├── Managers/
│   │   │   └── WeaponManager.lua
│   │   └── Systems/
│   │       ├── HitscanSystem.lua
│   │       └── WeaponAnimationService.lua
│   └── TestMode.lua               # Development mode toggle
│
├── ServerScriptService/
│   ├── Initializer.server.lua      # Server entry point
│   └── Services/
│       ├── CharacterService.lua    # Character spawning/death
│       ├── ServerReplicator.lua    # State broadcast
│       ├── WeaponHitService.lua    # Damage validation
│       ├── AnimationService.lua    # Animation replication
│       ├── ArmReplicationService.lua # Arm look replication
│       ├── NPCService.lua          # AI character management
│       ├── RoundService.lua        # Round system
│       ├── InventoryService.lua    # Inventory management
│       ├── KitService.lua         # Kit/hero abilities
│       ├── CollisionGroupService.lua
│       ├── GarbageCollectorService.lua
│       └── LogServiceInitializer.lua
│
├── ServerStorage/
│   ├── Models/
│   │   └── Character.rbxmx         # Character template
│   ├── Maps/                       # Map assets
│   └── Modules/
│       ├── MapSelector.lua
│       ├── MapLoader.lua
│       ├── SpawnManager.lua
│       └── Phases/
│           ├── IntermissionPhase.lua
│           ├── RoundStartPhase.lua
│           ├── RoundPhase.lua
│           └── RoundEndPhase.lua
│
└── StarterPlayerScripts/
    ├── Initializer.client.lua      # Client entry point
    ├── Controllers/
    │   ├── CharacterController.lua # Movement orchestration
    │   ├── CharacterSetup.lua      # Weld/physics setup
    │   ├── CharacterMovement.lua  # Movement processing
    │   ├── CharacterInput.lua     # Input handling
    │   ├── CharacterState.lua     # State management
    │   ├── ClientCharacterSetup.lua
    │   ├── CameraController.lua    # First-person camera
    │   ├── InputManager.lua        # Multi-platform input
    │   ├── AnimationController.lua # Animation playback
    │   ├── RagdollController.lua   # Ragdoll handling
    │   ├── WeaponController.lua    # Weapon handling
    │   ├── ViewmodelController.lua # Viewmodel management
    │   ├── InventoryController.lua # Inventory UI
    │   ├── KitController.lua      # Kit abilities
    │   ├── InteractableController.lua
    │   └── MovementInputProcessor.lua
    ├── Systems/
    │   ├── Replication/
    │   │   ├── ClientReplicator.lua   # Send state to server
    │   │   └── RemoteReplicator.lua   # Receive other players
    │   └── Viewmodel/
    │       └── [Viewmodel system files]
    └── UI/
        ├── UIManager.lua
        ├── MobileControls.lua      # Mobile virtual controls
        └── ChatMonitor.lua
```

---

## CORE SYSTEMS ARCHITECTURE

### System Architecture Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                          CLIENT LAYER                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  InputManager → CharacterController → MovementStateManager    │
│       ↓                ↓                        ↓                │
│  CameraController → MovementUtils → SlidingSystem             │
│       ↓                ↓                        ↓                │
│  Physics Engine (VectorForce + AlignOrientation)               │
│       ↓                                                         │
│  ClientReplicator (60Hz to server)                              │
└─────────────────────────────┬───────────────────────────────────┘
                              │ CharacterStateUpdate
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                          SERVER LAYER                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ServerReplicator (validate & relay)                            │
│       ↓                                                         │
│  Broadcast to all clients (CharacterStateReplicated)            │
│                                                                 │
│  CharacterService → WeaponHitService → RoundService             │
│       ↓                ↓                    ↓                  │
│  KitService → InventoryService → AnimationService              │
└─────────────────────────────┬───────────────────────────────────┘
                              │ CharacterStateReplicated
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    OTHER CLIENTS (Observers)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  RemoteReplicator (interpolate & smooth)                       │
│       ↓                                                         │
│  AnimationController → RagdollController                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## CRITICAL DEVELOPMENT PATTERNS

### ⚠️ Import Path Rules

**ALWAYS use Locations registry - NEVER hardcode paths:**

```lua
-- ✅ CORRECT - Uses Locations registry
local Locations = require(ReplicatedStorage.Modules.Locations)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local MathUtils = require(Locations.Modules.Utils.MathUtils)
local Config = require(Locations.Modules.Config)

-- ❌ WRONG - Hardcoded paths (breaks when files move)
local MovementUtils = require(ReplicatedStorage.Systems.Movement.MovementUtils)
```

**Why?**
- Prevents circular dependencies
- Single source of truth for module paths
- Easy refactoring (change path in one place)
- Works across client/server boundaries

### Systems vs Utils Classification

| Category | Purpose | Examples | Characteristics |
|----------|---------|----------|-----------------|
| **Systems** | Complex stateful objects | SlidingSystem, MovementStateManager, RagdollSystem, RoundService | - Require initialization<br>- Have internal state<br>- Use callbacks<br>- Complex logic<br>- Lifecycle management |
| **Utils** | Pure utility functions | MathUtils, ValidationUtils, CompressionUtils, PartUtils | - No internal state<br>- Pure functions<br>- Reusable<br>- Simple helpers<br>- No lifecycle |

**When to use Systems:**
- Managing state over time
- Coordinating multiple components
- Complex lifecycle (init → update → cleanup)
- Event-driven behavior

**When to use Utils:**
- Mathematical calculations
- Data transformation
- Validation checks
- One-off operations
- Helper functions

### Character Setup Order (CRITICAL)

**Server-side:**
```lua
1. Clone character model from ServerStorage
2. Set player.Character = characterModel  -- ⚠️ REQUIRED for voice chat
3. Move to spawn location
4. Fire CharacterSpawned event
```

**Client-side:**
```lua
1. Wait for character model
2. Wait for Rig to be created (if using visual rig)
3. CrouchUtils:SetupLegacyWelds()  -- Weld collision parts
4. MovementUtils:SetupPhysicsConstraints()  -- VectorForce/AlignOrientation
5. CharacterUtils:ApplyNetworkOwnership()  -- Client-side physics control
6. Initialize systems (MovementStateManager, AnimationController, etc.)
7. Fire CharacterSetupComplete event
```

**⚠️ Order matters!** Welds → Constraints → Ownership → Systems

### Network Event Types

**High-frequency (60Hz):** Use `UnreliableRemoteEvent`
- CharacterStateUpdate
- CharacterStateReplicated
- ArmLookUpdate
- ArmLookReplicated

**Critical events:** Use `RemoteEvent` (reliable)
- CharacterSpawned
- PlayerKilled
- WeaponFired
- ServerCorrection

**Why UnreliableRemoteEvent?**
- RemoteEvent at 60Hz causes ~24% artificial packet loss due to throttling
- UnreliableRemoteEvent allows true 60Hz with only natural network packet loss (~0-2%)
- Position updates can tolerate occasional packet loss (interpolation handles it)

### Velocity Handling Pattern

```lua
-- ✅ CORRECT - Read velocity
local velocity = primaryPart.AssemblyLinearVelocity

-- ✅ CORRECT - Apply force (never set velocity directly)
VectorForce.Force = direction * speed * MOVEMENT_FORCE

-- ❌ WRONG - Never set velocity directly
primaryPart.AssemblyLinearVelocity = velocity  -- Breaks physics!
```

---

## NETWORK ARCHITECTURE

### Network Replication Flow

**Client → Server (60Hz):**
```
1. Client simulates movement (VectorForce physics)
2. ClientReplicator captures state (position, rotation, velocity, timestamp)
3. CompressionUtils:CompressState() → 40 bytes via Sera
4. RemoteEvents:FireServer("CharacterStateUpdate", buffer)
5. Server receives, validates, caches
```

**Server → Clients (60Hz):**
```
1. Server batches all player states
2. CompressionUtils:CompressState() for each player
3. RemoteEvents:FireAllClients("CharacterStateReplicated", batch)
4. Clients receive via RemoteReplicator
5. Interpolation & smoothing applied
```

### Network Data Format

**CharacterState (40 bytes):**
- Position: Vector3 (12 bytes)
- Rotation: Float32 Y-only (4 bytes)
- Velocity: Vector3 (12 bytes)
- Timestamp: Float64 (8 bytes)
- Animation: Uint8 enum (1 byte)
- State flags: Uint8 (1 byte)
- Padding: 2 bytes

**Delta Compression:**
- Only send if position changed > 0.1 studs
- Idle players send 0 bytes/s
- Moving players: ~2.4 KB/s (40 bytes × 60 Hz)

### Bandwidth Summary

| Scenario | Bandwidth |
|----------|-----------|
| Idle player | 0 bytes/s (delta compression) |
| Moving player | ~2.4 KB/s (40 bytes × 60 Hz) |
| 20 players (per client) | ~48 KB/s (receiving all states) |

---

## CONFIGURATION SYSTEM

### Config Access Pattern

```lua
local Config = require(Locations.Modules.Config)

-- Gameplay settings
Config.Gameplay.Character.WalkSpeed        -- 16 studs/s
Config.Gameplay.Character.SprintSpeed      -- 24 studs/s
Config.Gameplay.Sliding.InitialVelocity   -- 45 studs/s
Config.Gameplay.Physics.MovementForce     -- 10000

-- Control settings
Config.Controls.Input.Jump                 -- Enum.KeyCode.Space
Config.Controls.Camera.MouseSensitivity   -- 0.4
Config.Controls.Mobile.ThumbstickSize     -- 120

-- System settings
Config.System.Debug.LogGroundDetection     -- false
Config.System.Network.AutoSpawnOnJoin      -- true
Config.System.Replication.UpdateRates.ClientToServer  -- 60

-- Health settings
Config.Health.MaxHealth                    -- 150
Config.Health.RespawnDelay                 -- 0

-- Animation settings
Config.Animation.Animations.Walk.Id        -- Animation ID
Config.Animation.AnimationEnum.Walk        -- 1 (for network)

-- Weapon settings
Config.Weapon.FireRate                     -- 600 RPM
Config.Weapon.Damage                       -- 30

-- Kit settings
Config.Kit.AbilityCooldown                 -- 10 seconds
Config.Kit.UltimateChargeRate             -- 1 per second
```

### Config File Organization

| File | Purpose | Key Settings |
|------|---------|--------------|
| **GameplayConfig.lua** | Movement, physics, sliding | WalkSpeed, SprintSpeed, Sliding, Physics constants |
| **ControlsConfig.lua** | Input, camera, mobile | Keybinds, MouseSensitivity, MobileControls |
| **SystemConfig.lua** | Network, debug, logging | UpdateRates, Debug flags, Logging categories |
| **ReplicationConfig.lua** | Network replication | Compression, Anti-cheat thresholds |
| **HealthConfig.lua** | Health system | MaxHealth, RespawnDelay, DeathYThreshold |
| **AnimationConfig.lua** | Animation system | Animation IDs, AnimationEnum, Loop flags |
| **AudioConfig.lua** | Sound system | Sound IDs, Volume levels |
| **WeaponConfig.lua** | Weapon system | FireRate, Damage, Range, Falloff |
| **KitConfig.lua** | Kit/hero system | Kit definitions, Abilities, Ultimates |
| **LoadoutConfig.lua** | Loadout system | Slot definitions, Weapon assignments |
| **RoundConfig.lua** | Round system | Round duration, Phase timings |
| **ViewmodelConfig.lua** | Viewmodel system | Viewmodel settings, Animations |
| **InteractableConfig.lua** | Interactable objects | Interaction ranges, Cooldowns |

---

## REMOTEEVENT SYSTEM

### Event Management

**Centralized System:** All events defined in `RemoteEvents.lua`

**Adding New Events:**
```lua
-- 1. Add to EVENT_DEFINITIONS table
local EVENT_DEFINITIONS = {
    -- ... existing events ...
    { 
        name = "NewEventName", 
        description = "Event description",
        unreliable = true  -- Optional: for high-frequency events
    },
}

-- 2. Use via RemoteEvents module
RemoteEvents:FireServer("NewEventName", arg1, arg2)
RemoteEvents:FireClient("NewEventName", player, arg1, arg2)
RemoteEvents:ConnectServer("NewEventName", function(player, ...)
    -- Handler code
end)
```

### Available RemoteEvents

**Character Events:**
- `ServerReady` - Server initialization complete
- `CharacterSpawned` - Character spawned successfully
- `CharacterRemoving` - Character being removed
- `RequestCharacterSpawn` - Client requests spawn
- `RequestRespawn` - Client requests respawn
- `CharacterSetupComplete` - Client setup finished

**NPC Events:**
- `RequestNPCSpawn` - Spawn NPC (J key)
- `RequestNPCRemoveOne` - Remove NPC (K key)

**Audio Events:**
- `PlaySoundRequest` - Client requests sound replication
- `PlaySound` - Server broadcasts sound
- `StopSoundRequest` - Client requests stop sound
- `StopSound` - Server broadcasts stop sound

**Round System Events:**
- `PhaseChanged` - Round phase changed
- `PlayerStateChanged` - Player state changed (Lobby/Runner/Tagger/Ghost)
- `NPCStateChanged` - NPC state changed
- `MapLoaded` - New map loaded
- `RoundResults` - Round end results
- `TaggerSelected` - Tagger selected
- `PlayerTagged` - Runner tagged
- `AFKToggle` - AFK status toggle

**Animation Events:**
- `PlayAnimation` - Server tells client to play animation
- `StopAnimation` - Server tells client to stop animation

**Weapon Events:**
- `WeaponFired` - Client shoots weapon (hit data)
- `PlayerDamaged` - Server applies damage

**Health Events:**
- `PlayerHealthChanged` - Health changed
- `PlayerDied` - Client notifies death
- `PlayerKilled` - Server broadcasts kill
- `PlayerRagdolled` - Player ragdolled

**Replication Events (UnreliableRemoteEvent):**
- `CharacterStateUpdate` - Client → Server (60Hz)
- `CharacterStateReplicated` - Server → Clients (60Hz)
- `ServerCorrection` - Server corrects client position
- `RequestInitialStates` - Client requests late-join sync
- `ArmLookUpdate` - Client → Server arm look
- `ArmLookReplicated` - Server → Clients arm look

**Inventory/Loadout Events:**
- `RequestLoadout` - Client requests loadout
- `LoadoutData` - Server sends loadout
- `SwitchWeapon` - Client switches weapon slot
- `WeaponSwitched` - Server confirms switch
- `UpdateLoadoutSlot` - Client updates slot

**Kit/Ability Events:**
- `UseAbility` - Client uses ability
- `AbilityUsed` - Server confirms ability
- `AbilityCooldownUpdate` - Server sends cooldown
- `UseUltimate` - Client uses ultimate
- `UltimateUsed` - Server confirms ultimate
- `UltChargeUpdate` - Server sends ult charge
- `GrantUltCharge` - Server grants charge
- `ResetUltCharge` - Server resets charge

---

## CHARACTER SYSTEM

### Character Model Structure

```
Character (Model)
├── Collider (Model) - Collision detection
│   ├── UncrouchCheck (Model) - Stand-up collision check
│   │   ├── CollisionBody (Part)
│   │   └── CollisionHead (Part)
│   ├── Crouch (Model) - Crouched collision geometry
│   │   ├── CrouchBody (Part)
│   │   ├── CrouchHead (Part)
│   │   └── CrouchFace (Part)
│   └── Default (Model) - Standing collision geometry
│       ├── Body (Part)
│       ├── Feet (Part) - Ground detection raycast origin
│       ├── Head (Part) - Camera attachment point
│       └── Face (Part)
├── Root (Part) - PrimaryPart, physics (VectorForce/AlignOrientation)
├── Rig (Model) - Optional R6 rig for cosmetics/animations
│   ├── Head (Part) - with attachments
│   ├── Torso (Part) - with Motor6D connections
│   ├── Left Arm (Part)
│   ├── Right Arm (Part)
│   ├── Left Leg (Part)
│   ├── Right Leg (Part)
│   ├── HumanoidRootPart (Part)
│   ├── Humanoid - Optional, not used by custom system
│   └── BodyColors
├── HumanoidRootPart (Part) - Voice chat recognition
├── Head (Part) - Voice chat recognition
└── Humanoid - Voice chat recognition
```

**Key Parts:**
- **Root** - PrimaryPart, receives VectorForce and AlignOrientation
- **Default/Feet** - Ground detection raycast origin
- **Default/Head** - Camera attachment point
- **Collider/Default/** - Active collision during standing
- **Collider/Crouch/** - Active collision during crouching/sliding
- **Collider/UncrouchCheck/** - Detects if player can stand up

### Character Spawning Flow

```
1. Player joins game
       ↓
2. Server: CharacterService:SpawnCharacter()
   - Creates minimal Humanoid model (voice chat only)
   - player.Character = characterModel  -- ⚠️ CRITICAL!
   - Moves to spawn location
   - Fires CharacterSpawned event
       ↓
3. Client: CharacterSetup:OnCharacterSpawned()
   - Waits for Rig to be created (if using visual rig)
   - CrouchUtils:SetupLegacyWelds() (weld collision parts)
   - MovementUtils:SetupPhysicsConstraints() (VectorForce/AlignOrientation)
   - CharacterUtils:ApplyNetworkOwnership() (client control)
   - Fires CharacterSetupComplete event
       ↓
4. Client: Systems initialize
   - MovementStateManager, AnimationController, InputManager
   - Start physics update loop (RunService.Heartbeat)
   - Start state replication (60Hz to server)
       ↓
5. Character ready for gameplay
```

### Health System

**Humanoid-Based Health:**
- **Health Management:** `Humanoid.MaxHealth` and `Humanoid.Health` in `CharacterService:SetupHumanoid()`
- **Damage Application:** `Humanoid:TakeDamage(damage)` in `WeaponHitService:ApplyDamage()`
- **Death Detection:** `Humanoid.Died` event connected in `CharacterService:SetupHumanoid()`
- **Regeneration:** DISABLED - Default Humanoid Health script removed
- **Killer Tracking:** Humanoid attributes (`LastDamageDealer`, `WasHeadshot`)
- **Fall Death:** Client sets `Humanoid.Health = 0` when Y < `DeathYThreshold`
- **Configuration:** All values in `HealthConfig.lua`

### Death & Respawn Flow

```
1. Death trigger (health = 0 OR fall off world)
       ↓
2. Humanoid.Died event fires on server
       ↓
3. Server: CharacterService:OnPlayerDeath()
   - Get killer from Humanoid attributes
   - Broadcast PlayerKilled to all clients
       ↓
4. All clients: Ragdoll dead character
   - RagdollSystem:RagdollCharacter()
   - FadeOutRagdoll() after delay
       ↓
5. Server waits RespawnDelay (0 seconds default)
       ↓
6. Server calls CharacterService:SpawnCharacter()
   - (Spawning flow repeats)
```

---

## MOVEMENT SYSTEMS

### Movement State Priority

```
Walking (1) < Sprinting (2) < Crouching (3) < Sliding (4)
```

**State Transitions:**
- Lower priority states can transition to higher priority
- Higher priority states block lower priority transitions
- Sliding has highest priority (momentum-based)

### Movement Update Flow

```
1. Input detected (WASD, touch, controller)
       ↓
2. InputManager fires "Movement" callback
       ↓
3. CharacterController receives input
   - Calculates camera-relative movement direction
   - Checks movement state (Walking/Sprinting/Crouching/Sliding)
   - Gets speed for current state
       ↓
4. Apply physics
   - VectorForce.Force = direction × speed × MOVEMENT_FORCE
   - AlignOrientation.CFrame = camera rotation (Y-only)
       ↓
5. Roblox physics engine simulates (client-side)
       ↓
6. ClientReplicator sends state to server (60Hz)
   - Position, rotation, velocity, timestamp
   - Compressed to 40 bytes via Sera
       ↓
7. Server receives, caches, and broadcasts to all clients
       ↓
8. Other clients interpolate position (RemoteReplicator)
```

### Sliding System

**Features:**
- Advanced sliding physics with slope detection
- Slide buffering (allows slide input during jumps)
- Momentum preservation
- Airborne boost on landing

**State Management:**
- Integrated with MovementStateManager
- Priority-based transitions
- Callback system for state changes

### Ground Detection

**5-Point Raycast System:**
- Origin: `Default/Feet` part bottom
- 5 raycasts: center + 4 corners
- Configurable offset and distance
- Cached results (100ms cache)

### Wall Jump System

**WallJumpUtils:**
- Wall detection via raycasts
- Jump execution with boost
- Direction calculation
- Integration with movement system

---

## WEAPON SYSTEM

### Weapon Hit Flow

```
1. Client detects hit (raycast/hitbox)
       ↓
2. Client sends hit data to server
   - WeaponFired RemoteEvent
   - Includes: attacker, target, damage, timestamp, etc.
       ↓
3. Server: WeaponHitService:ValidateAndProcessHit()
   - Validate weapon config exists
   - Validate hit timing (lag compensation via frame history)
   - Calculate damage with falloff
       ↓
4. Server: WeaponHitService:ApplyDamage()
   - humanoid:TakeDamage(damage)
   - Set attributes: LastDamageDealer, WasHeadshot
   - Fire PlayerHealthChanged to all clients
       ↓
5. If health = 0, trigger death flow
```

### Weapon Configuration

**WeaponConfig.lua:**
- FireRate (RPM)
- Damage
- Range
- Falloff
- Spread
- Recoil

**Weapon System Structure:**
- `Weapons/Actions/Gun/` - Gun weapon types
- `Weapons/Actions/Melee/` - Melee weapon types
- `Weapons/Managers/WeaponManager.lua` - Weapon management
- `Weapons/Systems/HitscanSystem.lua` - Hit detection
- `Weapons/Systems/WeaponAnimationService.lua` - Animation handling

---

## ROUND SYSTEM

### Round Phases

1. **IntermissionPhase** - Pre-round setup
2. **RoundStartPhase** - Round beginning
3. **RoundPhase** - Active gameplay
4. **RoundEndPhase** - Round conclusion

### Player States

- **Lobby** - Waiting in lobby
- **Runner** - Active player (not tagger)
- **Tagger** - Player selected as tagger
- **Ghost** - Dead player

### Round Flow

```
1. IntermissionPhase
   - Map selection
   - Player assignment
   - Tagger selection
       ↓
2. RoundStartPhase
   - Countdown
   - Spawn players
   - Initialize round
       ↓
3. RoundPhase
   - Active gameplay
   - Tagging mechanics
   - State updates
       ↓
4. RoundEndPhase
   - Calculate results
   - Display winners
   - Transition to intermission
```

---

## COMMON TASKS & EXAMPLES

### Spawn Character

```lua
-- Server-side
local CharacterService = require(Locations.Server.Services.CharacterService)
local spawnCFrame = CFrame.new(0, 5, 0)
CharacterService:SpawnCharacter(player, spawnCFrame)
```

### Change Movement State

```lua
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local States = MovementStateManager.States

MovementStateManager:TransitionTo(States.Sliding, {
    Direction = movementDirection,
    InitialVelocity = currentVelocity
})
```

### Fire Network Event

```lua
local RemoteEvents = require(Locations.Modules.RemoteEvents)

-- Client → Server
RemoteEvents:FireServer("EventName", arg1, arg2, ...)

-- Server → Client
RemoteEvents:FireClient("EventName", player, arg1, arg2, ...)

-- Server → All Clients
RemoteEvents:FireAllClients("EventName", arg1, arg2, ...)

-- Connect handlers
RemoteEvents:ConnectServer("EventName", function(player, ...)
    -- Server handler
end)

RemoteEvents:ConnectClient("EventName", function(...)
    -- Client handler
end)
```

### Access Configuration

```lua
local Config = require(Locations.Modules.Config)

-- Gameplay settings
local walkSpeed = Config.Gameplay.Character.WalkSpeed
local sprintSpeed = Config.Gameplay.Character.SprintSpeed

-- Control settings
local jumpKey = Config.Controls.Input.Jump
local mouseSensitivity = Config.Controls.Camera.MouseSensitivity

-- System settings
local updateRate = Config.System.Replication.UpdateRates.ClientToServer
local debugEnabled = Config.System.Debug.LogGroundDetection
```

### Apply Physics Force

```lua
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local Config = require(Locations.Modules.Config)

-- Get character parts
local root = character.PrimaryPart
local vectorForce = root:FindFirstChild("VectorForce")
local alignOrientation = root:FindFirstChild("AlignOrientation")

-- Calculate movement direction (camera-relative)
local camera = workspace.CurrentCamera
local cameraCFrame = camera.CFrame
local movementDirection = (cameraCFrame.LookVector * inputZ + cameraCFrame.RightVector * inputX).Unit

-- Apply force
local speed = Config.Gameplay.Character.WalkSpeed
local movementForce = Config.Gameplay.Physics.MovementForce
vectorForce.Force = movementDirection * speed * movementForce

-- Apply rotation (Y-only)
local cameraYAngle = math.atan2(cameraCFrame.LookVector.X, cameraCFrame.LookVector.Z)
alignOrientation.CFrame = CFrame.Angles(0, cameraYAngle, 0)
```

### Play Animation

```lua
local AnimationController = require(Locations.Client.Controllers.AnimationController)
local AnimationConfig = require(Locations.Modules.Config).Animation

-- Preload animation (if not already loaded)
AnimationController:PreloadAnimation(AnimationConfig.Animations.Walk.Id)

-- Play animation
AnimationController:PlayStateAnimation(AnimationConfig.AnimationEnum.Walk)
```

### Add New RemoteEvent

```lua
-- 1. Add to RemoteEvents.lua EVENT_DEFINITIONS
{ 
    name = "NewEvent", 
    description = "New event description",
    unreliable = false  -- true for high-frequency
}

-- 2. Use in code
RemoteEvents:FireServer("NewEvent", data)
RemoteEvents:ConnectServer("NewEvent", function(player, data)
    -- Handler
end)
```

### Add New Configuration

```lua
-- 1. Add to appropriate Config file (e.g., GameplayConfig.lua)
return {
    Character = {
        WalkSpeed = 16,
        SprintSpeed = 24,
        NewSetting = 100,  -- Add here
    },
}

-- 2. Access via Config
local Config = require(Locations.Modules.Config)
local value = Config.Gameplay.Character.NewSetting
```

---

## DEBUGGING & TROUBLESHOOTING

### Common Issues

**1. Character Not Spawning:**
- Check `player.Character` assignment on server
- Verify PrimaryPart exists after cloning
- Check CharacterSpawned event firing
- Verify client CharacterSetup completing

**2. Movement Not Working:**
- Check ground detection raycast visualization
- Verify VectorForce and AlignOrientation exist
- Check network ownership applied
- Verify InputManager callbacks connected

**3. Network Replication Issues:**
- Check RemoteEvent type (UnreliableRemoteEvent for 60Hz)
- Verify compression working (check buffer size)
- Check server receiving updates (add debug prints)
- Verify client receiving broadcasts

**4. Input Not Responding:**
- Check InputManager initialization
- Verify keybinds in ControlsConfig
- Check callback connections
- Add debug prints to input callbacks

**5. Animation Not Playing:**
- Verify animation ID in AnimationConfig
- Check AnimationController preloading
- Verify AnimationEnum matches
- Check animation replication working

### Debug Tools

**TestMode System:**
```lua
local TestMode = require(Locations.Modules.TestMode)

-- Enable test mode
TestMode.ENABLED = true

-- Enable specific debug flags
TestMode.Debug.CharacterMovement = true
TestMode.Debug.GroundDetection = true
TestMode.Debug.InputEvents = true
TestMode.Visual.Raycasts = true
```

**LogService:**
```lua
local Log = require(Locations.Modules.Systems.Core.LogService)

-- Register category
Log:RegisterCategory("MY_SYSTEM", "My system description")

-- Log messages
Log:Info("MY_SYSTEM", "Info message", { Data = value })
Log:Warn("MY_SYSTEM", "Warning message", { Data = value })
Log:Error("MY_SYSTEM", "Error message", { Data = value })
Log:Debug("MY_SYSTEM", "Debug message", { Data = value })
```

**Visual Debug:**
- Raycast visualization (TestMode.Visual.Raycasts)
- Physics force visualization
- Character bounds visualization
- Ground detection visualization

---

## PERFORMANCE OPTIMIZATION

### Network Optimization

**1. Compression:**
- Position: 12 bytes (full precision)
- Rotation: 4 bytes (Y-only)
- Velocity: 12 bytes (full precision)
- Animation: 1 byte (enum instead of string = 95% reduction)
- **Total: 40 bytes per update**

**2. Delta Compression:**
```lua
-- Only send if position changed > threshold
if (newPosition - oldPosition).Magnitude < 0.1 then
    return  -- Skip update (idle players send 0 bytes/s)
end
```

**3. Batch Broadcasting:**
```lua
-- Send all player states in single packet
RemoteEvents:FireAllClients("CharacterStateReplicated", batch)
```

### CPU Optimization

**1. Raycast Caching:**
```lua
-- Cache ground detection results for 100ms
local cached = raycastCache[cacheKey]
if cached and (currentTime - cached.timestamp) < 0.1 then
    return cached.result
end
```

**2. Update Rate Limiting:**
```lua
-- Only update at configured rate (60Hz)
if (tick() - lastUpdate) < (1 / 60) then
    return  -- Too soon
end
```

**3. Part Optimization:**
```lua
-- Rig parts are massless and non-colliding (visual only)
part.Massless = true
part.CanCollide = false
```

### Memory Optimization

**1. Frame History Limiting:**
```lua
-- Only store last 60 frames (1 second at 60Hz)
if #frameHistory > 60 then
    table.remove(frameHistory, 1)  -- Remove oldest
end
```

**2. Cleanup on Disconnect:**
```lua
Players.PlayerRemoving:Connect(function(player)
    PlayerStates[player] = nil
    ViolationCounts[player] = nil
    -- ... other cleanup
end)
```

---

## SECURITY & ANTI-CHEAT

### Current State

**Status:** Anti-cheat infrastructure exists but **validation is commented out**

**Location:** `ServerScriptService/Services/ServerReplicator.lua`

### Planned Validations

**1. Speed Validation:**
```lua
local distance = (newPosition - oldPosition).Magnitude
local speed = distance / deltaTime

if speed > (MAX_SPEED * TOLERANCE) then
    -- Flag exploit + server correction
end
```

**2. Teleport Detection:**
```lua
if distance > TELEPORT_THRESHOLD and deltaTime < 0.1 then
    -- Flag teleport exploit
end
```

**3. Timestamp Validation:**
```lua
local timeDrift = math.abs(clientTimestamp - serverTime)
if timeDrift > MAX_TIMESTAMP_DRIFT then
    -- Reject update (clock manipulation)
end
```

**4. Vertical Speed Validation:**
```lua
local verticalSpeed = math.abs(newPosition.Y - oldPosition.Y) / deltaTime
if verticalSpeed > MAX_VERTICAL_SPEED then
    -- Flag flying exploit
end
```

### Lag Compensation

**Purpose:** Validate hits at the time the client fired (account for network delay)

**Implementation:**
```lua
-- Server stores frame history (last 1 second of positions)
function ServerReplicator:AddToFrameHistory(player, state)
    table.insert(playerData.FrameHistory, {
        State = state,
        Timestamp = state.Timestamp,
    })
    
    -- Limit to 60 frames (1 second at 60Hz)
    if #playerData.FrameHistory > 60 then
        table.remove(playerData.FrameHistory, 1)
    end
end

-- Rewind player position for hit validation
function WeaponHitService:ValidateHit(attacker, target, hitData)
    -- Get target's position at time of shot (account for ping)
    local targetStateAtHitTime = ServerReplicator:GetPlayerStateAtTime(
        target,
        hitData.Timestamp
    )
    
    -- Validate hit using rewound position
    if self:IsHitValid(hitData, targetStateAtHitTime) then
        self:ApplyDamage(target, damage, isHeadshot, attacker)
    end
end
```

---

## QUICK REFERENCE

### Critical Patterns

**1. Character Setup Order:**
```
Welds → Physics Constraints → Network Ownership → System Init
```

**2. Network Event Types:**
```
High-frequency (60Hz): UnreliableRemoteEvent
Critical (death, damage): RemoteEvent (reliable)
```

**3. Movement State Priority:**
```
Walking < Sprinting < Crouching < Sliding
```

**4. Velocity Handling:**
```
READ: primaryPart.AssemblyLinearVelocity
WRITE: vectorForce.Force (never set velocity directly)
```

**5. Import Pattern:**
```
Always use Locations registry - never hardcode paths
```

### Common Code Snippets

**Get Character Parts:**
```lua
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local root = CharacterLocations:GetRoot(character)
local feet = CharacterLocations:GetFeet(character)
local head = CharacterLocations:GetHead(character)
```

**Apply Movement:**
```lua
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
MovementUtils:ApplyMovement(character, direction, speed)
```

**Check Ground:**
```lua
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local isGrounded, groundNormal = MovementUtils:IsGrounded(character)
```

**Change Crouch State:**
```lua
local CrouchUtils = require(Locations.Modules.Systems.Character.CrouchUtils)
CrouchUtils:SetCrouchState(character, true)  -- true = crouch, false = stand
```

---

## DOCUMENTATION INDEX

| Document | Purpose | Key Topics |
|----------|---------|------------|
| **AGENT.md** (this file) | AI agent guide | Complete system reference, patterns, examples |
| **CLAUDE.md** | Developer guide | Project overview, conventions, workflows |
| **docs/ARCHITECTURE_OVERVIEW.md** | Master overview | System diagrams, data flow, patterns |
| **docs/CHARACTER_SYSTEM.md** | Character lifecycle | Spawning, setup, welds, network ownership, death/respawn |
| **docs/NETWORK_REPLICATION.md** | State synchronization | Compression, Sera, UnreliableRemoteEvent, interpolation |
| **docs/MOVEMENT_SYSTEMS.md** | Movement mechanics | States, physics, sliding, wall jumping, ground detection |
| **docs/WEAPON_SYSTEM_SETUP.md** | Weapon implementation | Hit validation, damage, weapon configs |
| **docs/INPUT_AND_CAMERA.md** | Input & camera | Multi-platform input, camera system, mobile controls |
| **docs/ANIMATION_AND_RAGDOLL.md** | Animation system | Animation playback, replication, ragdoll system |

---

## ONBOARDING CHECKLIST

### For New AI Agents

- [ ] Read AGENT.md (this file) completely
- [ ] Understand Locations registry pattern
- [ ] Understand Systems vs Utils classification
- [ ] Understand character setup order
- [ ] Understand network event types
- [ ] Understand configuration access pattern
- [ ] Review common code examples
- [ ] Understand debugging tools
- [ ] Review performance optimization patterns
- [ ] Understand security/anti-cheat architecture

### First Tasks

1. **Read AGENT.md** (understand overall system)
2. **Review Locations.lua** (understand path registry)
3. **Review RemoteEvents.lua** (understand event system)
4. **Review Config files** (understand configuration structure)
5. **Review CharacterService** (understand character spawning)
6. **Review CharacterController** (understand movement flow)
7. **Review ServerReplicator** (understand network replication)
8. **Add a debug print** to test understanding
9. **Make a small change** (e.g., modify walk speed)
10. **Test in Studio** (verify change works)

---

## NOTES FOR AI AGENTS

### ⚠️ Critical Rules

1. **NEVER run Rojo commands** - User handles all Rojo operations
2. **ALWAYS use Locations registry** - Never hardcode module paths
3. **ALWAYS use RemoteEvents module** - Never create RemoteEvent instances directly
4. **ALWAYS follow character setup order** - Welds → Constraints → Ownership → Systems
5. **ALWAYS use UnreliableRemoteEvent for 60Hz** - RemoteEvent causes throttling
6. **NEVER set velocity directly** - Always use VectorForce.Force
7. **ALWAYS use Config module** - Never hardcode configuration values
8. **ALWAYS check TestMode** - Respect TestMode.ENABLED flag
9. **ALWAYS use LogService** - Never use print() or warn() directly
10. **ALWAYS follow Systems vs Utils pattern** - Classify modules correctly

### Common Mistakes to Avoid

- ❌ Hardcoding module paths (use Locations registry)
- ❌ Setting velocity directly (use VectorForce)
- ❌ Using RemoteEvent for high-frequency updates (use UnreliableRemoteEvent)
- ❌ Forgetting `player.Character = characterModel` on server
- ❌ Skipping network ownership setup
- ❌ Not following weld → constraints → ownership order
- ❌ Creating RemoteEvent instances directly (use RemoteEvents module)
- ❌ Hardcoding configuration values (use Config module)
- ❌ Using print() instead of LogService
- ❌ Mixing Systems and Utils patterns

### When in Doubt

1. **Check Locations.lua** - Find correct module path
2. **Check RemoteEvents.lua** - Find correct event name
3. **Check Config files** - Find configuration values
4. **Check existing code** - Find similar patterns
5. **Check documentation** - Review relevant docs/ files
6. **Ask for clarification** - Don't guess critical patterns

---

**Last Updated:** Generated from codebase analysis
**Version:** 1.0.0
**Maintained By:** AI Agent System

