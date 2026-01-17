# 📁 Folder Map - Visual Guide

## 🎯 Complete Folder Structure (Drag & Drop Ready)

```
src/
│
├── 📦 ReplicatedStorage/              [SHARED - Client & Server]
│   │
│   ├── 📋 Configs/                    [ALL CONFIGURATION]
│   │   ├── GameplayConfig.lua        → Movement, physics, character settings
│   │   ├── ControlsConfig.lua         → Input, camera, keybinds
│   │   ├── SystemConfig.lua           → Network, debug, logging
│   │   ├── HealthConfig.lua           → Health system settings
│   │   ├── AnimationConfig.lua        → Animation IDs and settings
│   │   ├── WeaponConfig.lua           → Weapon settings
│   │   ├── LoadoutConfig.lua          → Weapon slots (Primary/Secondary)
│   │   ├── ViewmodelConfig.lua        → First-person viewmodel
│   │   ├── ReplicationConfig.lua      → Network replication settings
│   │   ├── RoundConfig.lua            → Round system settings
│   │   ├── InteractableConfig.lua     → Interaction settings
│   │   └── AudioConfig.lua            → Sound settings
│   │
│   ├── 🔧 Modules/                    [CORE MODULES - Don't Move]
│   │   ├── Locations.lua              → ⚠️ PATH REGISTRY (everything uses this)
│   │   └── RemoteEvents.lua           → Network event management
│   │
│   ├── 🎮 Systems/                    [GAMEPLAY SYSTEMS]
│   │   │
│   │   ├── Movement/                  [✅ DRAG & DROP READY]
│   │   │   ├── MovementStateManager.lua → Walking/Sprinting/Crouching/Sliding states
│   │   │   ├── MovementUtils.lua        → Physics calculations
│   │   │   ├── SlidingSystem.lua        → Sliding mechanics
│   │   │   ├── SlidingBuffer.lua        → Slide buffering
│   │   │   ├── SlidingPhysics.lua       → Slide physics
│   │   │   ├── SlidingState.lua         → Slide state
│   │   │   └── WallJumpUtils.lua        → Wall jump mechanics
│   │   │
│   │   ├── Character/                 [✅ DRAG & DROP READY]
│   │   │   ├── CharacterLocations.lua   → Part location helpers
│   │   │   ├── CharacterUtils.lua       → Character utilities
│   │   │   ├── CrouchUtils.lua          → Crouch mechanics
│   │   │   ├── RagdollSystem.lua        → Ragdoll physics
│   │   │   ├── RigManager.lua           → Rig management
│   │   │   └── RigRotationUtils.lua     → Rig rotation
│   │   │
│   │   ├── Core/                      [⚠️ CORE - Don't Move]
│   │   │   ├── LogService.lua           → Logging system
│   │   │   ├── ConfigCache.lua          → Config loader
│   │   │   ├── SoundManager.lua         → Audio system
│   │   │   ├── MouseLockManager.lua     → Mouse lock
│   │   │   └── UserSettings.lua         → User preferences
│   │   │
│   │   └── Round/                     [✅ DRAG & DROP READY]
│   │       ├── PlayerStateManager.lua   → Player state
│   │       ├── NPCStateManager.lua      → NPC state
│   │       └── CombinedStateManager.lua → Combined state
│   │
│   ├── 🛠️ Utils/                      [UTILITY FUNCTIONS]
│   │   ├── MathUtils.lua               → Math helpers
│   │   ├── NumberUtils.lua              → Number helpers
│   │   ├── TableUtils.lua               → Table helpers
│   │   ├── TimerUtils.lua               → Timer helpers
│   │   ├── CompressionUtils.lua         → Data compression
│   │   ├── ServiceLoader.lua            → Module loader
│   │   ├── ServiceRegistry.lua          → Service registry
│   │   └── [More utilities...]
│   │
│   └── 🔫 Weapons/                     [✅ DRAG & DROP READY]
│       ├── Actions/
│       │   ├── Gun/                    → Gun weapons
│       │   └── Melee/                  → Melee weapons
│       ├── Configs/                    → Weapon configs
│       ├── Managers/                    → Weapon manager
│       └── Systems/                     → Hit detection, animations
│
├── 🖥️ ServerScriptService/             [SERVER-ONLY]
│   │
│   ├── Initializer.server.lua          → Server entry point
│   │
│   └── Services/                       [✅ DRAG & DROP READY - Each Independent]
│       ├── LogServiceInitializer.lua  → Logging setup
│       ├── GarbageCollectorService.lua → Memory cleanup
│       ├── CollisionGroupService.lua   → Collision groups
│       ├── CharacterService.lua        → Character spawning
│       ├── ServerReplicator.lua        → Network relay
│       ├── AnimationService.lua        → Animation tracking
│       ├── NPCService.lua              → NPC management
│       ├── RoundService.lua            → Round management
│       ├── WeaponHitService.lua        → Hit validation
│       ├── ArmReplicationService.lua   → Arm look replication
│       └── InventoryService.lua        → Inventory management
│
├── 💾 ServerStorage/                   [SERVER-ONLY STORAGE]
│   ├── Models/                         → Character templates
│   ├── Maps/                           → Map assets
│   └── Modules/                        → Server modules
│       ├── MapSelector.lua
│       ├── MapLoader.lua
│       ├── SpawnManager.lua
│       └── Phases/                     → Round phases
│
└── 🎯 StarterPlayerScripts/            [CLIENT-ONLY]
    │
    ├── Initializer.client.lua          → Client entry point
    │
    ├── Controllers/                    [✅ DRAG & DROP READY - Each Independent]
    │   ├── InputManager.lua            → Input handling
    │   ├── CameraController.lua         → Camera system
    │   ├── CharacterController.lua      → Main character controller
    │   ├── CharacterSetup.lua           → Character initialization
    │   ├── ClientCharacterSetup.lua     → Visual character setup
    │   ├── AnimationController.lua      → Animation playback
    │   ├── WeaponController.lua         → Weapon handling
    │   ├── ViewmodelController.lua      → First-person viewmodel
    │   ├── InventoryController.lua      → Weapon switching
    │   ├── RagdollController.lua       → Ragdoll system
    │   ├── InteractableController.lua   → Interactions
    │   └── MovementInputProcessor.lua   → Movement input
    │
    ├── Systems/                        [CLIENT SYSTEMS]
    │   │
    │   ├── Replication/                 [✅ DRAG & DROP READY]
    │   │   ├── ClientReplicator.lua     → Send state to server
    │   │   ├── RemoteReplicator.lua     → Receive from server
    │   │   └── ReplicationDebugger.lua  → Debug tools
    │   │
    │   └── Viewmodel/                   [✅ DRAG & DROP READY]
    │       └── [Viewmodel system files]
    │
    └── UI/                              [✅ DRAG & DROP READY]
        ├── UIManager.lua                → UI manager
        ├── MobileControls.lua           → Mobile controls
        └── ChatMonitor.lua              → Chat monitor
```

## 🎯 Legend

- ✅ **DRAG & DROP READY** - Can be moved independently
- ⚠️ **CORE** - Don't move (everything depends on it)
- 📋 **CONFIG** - Configuration files
- 🎮 **GAMEPLAY** - Gameplay systems
- 🔧 **CORE** - Core systems
- 🛠️ **UTILS** - Utility functions
- 🖥️ **SERVER** - Server-only code
- 🎯 **CLIENT** - Client-only code

## 📦 Drag & Drop Folders

These folders work independently:

1. ✅ **Movement/** - Complete movement system
2. ✅ **Character/** - Complete character system
3. ✅ **Weapons/** - Complete weapon system
4. ✅ **Round/** - Round management
5. ✅ **Replication/** - Network sync
6. ✅ **Services/** - Server services (each independent)
7. ✅ **Controllers/** - Client controllers (each independent)
8. ✅ **UI/** - User interface
9. ✅ **Utils/** - Utility functions

## 🚫 Don't Move

- ⚠️ **Modules/** - Contains Locations.lua (path registry)
- ⚠️ **Systems/Core/** - Core systems everything depends on
- ⚠️ **Configs/** - Keep together for easy access

## 🎯 Quick Find

| Need to... | Look in... |
|------------|------------|
| Change movement speed | `Configs/GameplayConfig.lua` |
| Change camera | `Configs/ControlsConfig.lua` |
| Modify movement | `Systems/Movement/` |
| Modify character | `Systems/Character/` |
| Add weapon | `Weapons/Actions/` |
| Server logic | `ServerScriptService/Services/` |
| Client logic | `StarterPlayerScripts/Controllers/` |
| Network code | `StarterPlayerScripts/Systems/Replication/` |

