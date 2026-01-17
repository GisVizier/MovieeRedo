# Server Services

## 📦 Drag & Drop Ready

Each service in this folder is independent and can be moved individually.

## Services

- **LogServiceInitializer.lua** - Initializes logging system (loads first)
- **GarbageCollectorService.lua** - Memory cleanup and garbage collection
- **CollisionGroupService.lua** - Manages collision groups
- **CharacterService.lua** - Character spawning, health, attributes
- **ServerReplicator.lua** - Network state relay to clients
- **AnimationService.lua** - Animation state tracking
- **NPCService.lua** - NPC management and spawning
- **RoundService.lua** - Round/game state management
- **WeaponHitService.lua** - Hit registration and damage validation
- **ArmReplicationService.lua** - Arm/head look replication
- **InventoryService.lua** - Inventory and loadout management

## Usage

All services are loaded by `Initializer.server.lua` and registered in `ServiceRegistry`.

## Dependencies

- Services use `Locations` for module paths
- Services use `RemoteEvents` for networking
- Services use `Config` for settings

