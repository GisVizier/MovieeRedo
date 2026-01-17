# Codebase Organization Guide

## Overview
This codebase is organized for easy drag-and-drop deployment and maximum clarity.

## Core Systems Structure

### 1. Movement System
**Location:** `src/ReplicatedStorage/Systems/Movement/`
- `MovementStateManager.lua` - State management (Walking, Sprinting, Crouching, Sliding)
- `MovementUtils.lua` - Physics and movement calculations
- `SlidingSystem.lua` - Advanced sliding mechanics
- `SlidingBuffer.lua` - Slide buffering logic
- `SlidingPhysics.lua` - Slide physics calculations
- `SlidingState.lua` - Slide state management
- `WallJumpUtils.lua` - Wall jump mechanics

**Usage:** Handles all character movement, physics, and state transitions.

### 2. Character System
**Location:** `src/ReplicatedStorage/Systems/Character/`
- `CharacterLocations.lua` - Part location helpers
- `CharacterUtils.lua` - Character utilities
- `CrouchUtils.lua` - Crouch mechanics
- `RagdollSystem.lua` - Ragdoll physics
- `RigManager.lua` - Rig management
- `RigRotationUtils.lua` - Rig rotation utilities

**Usage:** Character creation, setup, and visual management.

### 3. Replication System
**Location:** `src/StarterPlayerScripts/Systems/Replication/`
- `ClientReplicator.lua` - Sends local player state to server (60Hz)
- `RemoteReplicator.lua` - Receives and interpolates other players' states
- `ReplicationDebugger.lua` - Debug tools for replication

**Usage:** Network synchronization of character positions and animations.

### 4. Server Services
**Location:** `src/ServerScriptService/Services/`
- `CharacterService.lua` - Character spawning, health, attributes
- `AnimationService.lua` - Animation state tracking
- `ServerReplicator.lua` - Server-side replication relay
- `InventoryService.lua` - Weapon loadout management
- `WeaponHitService.lua` - Hit registration and damage
- `NPCService.lua` - NPC management
- `RoundService.lua` - Round/game state management
- `ArmReplicationService.lua` - Arm/head look replication
- `CollisionGroupService.lua` - Collision group management
- `GarbageCollectorService.lua` - Memory management

**Usage:** Server-side game logic and validation.

### 5. Client Controllers
**Location:** `src/StarterPlayerScripts/Controllers/`
- `CharacterController.lua` - Main character movement controller
- `CharacterSetup.lua` - Character initialization
- `ClientCharacterSetup.lua` - Visual character setup
- `CameraController.lua` - Camera management
- `InputManager.lua` - Input handling
- `AnimationController.lua` - Animation playback
- `WeaponController.lua` - Weapon handling
- `ViewmodelController.lua` - First-person viewmodel
- `InventoryController.lua` - Weapon switching
- `RagdollController.lua` - Ragdoll handling
- `InteractableController.lua` - Interaction system
- `MovementInputProcessor.lua` - Movement input processing

**Usage:** Client-side gameplay controllers.

## Configuration Files
**Location:** `src/ReplicatedStorage/Configs/`
- `GameplayConfig.lua` - Movement, physics, character settings
- `ControlsConfig.lua` - Input bindings, camera settings
- `SystemConfig.lua` - Network, debug, logging settings
- `HealthConfig.lua` - Health system settings
- `AnimationConfig.lua` - Animation settings
- `WeaponConfig.lua` - Weapon settings
- `LoadoutConfig.lua` - Loadout/weapon slot settings
- `ViewmodelConfig.lua` - Viewmodel settings
- `ReplicationConfig.lua` - Replication settings
- `RoundConfig.lua` - Round system settings
- `InteractableConfig.lua` - Interaction settings
- `AudioConfig.lua` - Audio settings

## Initialization Flow

### Server Initialization
1. `ServerScriptService/Initializer.server.lua` loads all services
2. Services initialize in order (LogService first, then others)
3. Character template moved to ReplicatedStorage for client access
4. Players connect → CharacterService spawns characters

### Client Initialization
1. `StarterPlayerScripts/Initializer.client.lua` loads all controllers
2. Controllers initialize and register with ServiceRegistry
3. Character spawns → Controllers connect to character
4. Replication systems start syncing state

## Key Features

### Character System
- **Full character creation** - Creates character with health, attributes, tools ready
- **Custom physics** - Uses VectorForce/AlignOrientation (no Humanoid dependency)
- **Client-side control** - Smooth movement with server validation
- **Health system** - Humanoid-based health with attributes

### Movement System
- **Walking/Sprinting** - Standard movement
- **Crouching** - Crouch mechanics with collision detection
- **Sliding** - Advanced sliding with momentum and buffering
- **Wall jumping** - Wall jump mechanics
- **Ground detection** - Precise raycast-based ground detection

### Replication System
- **60Hz updates** - High-frequency state synchronization
- **Delta compression** - Only sends changed data
- **Interpolation** - Smooth other players' movement
- **Animation sync** - Synchronized animations across clients

### Weapon System
- **Loadout management** - Primary/Secondary weapon slots
- **Weapon switching** - Smooth weapon switching
- **Viewmodel** - First-person weapon rendering
- **Hit registration** - Server-validated hit detection

## File Organization Principles

1. **Systems** (`ReplicatedStorage/Systems/`) - Complex stateful systems
2. **Utils** (`ReplicatedStorage/Utils/`) - Pure helper functions
3. **Controllers** (`StarterPlayerScripts/Controllers/`) - Client-side logic
4. **Services** (`ServerScriptService/Services/`) - Server-side logic
5. **Configs** (`ReplicatedStorage/Configs/`) - Configuration files

## Drag-and-Drop Ready
All folders can be moved independently:
- Movement system folder → Works standalone
- Character system folder → Works standalone
- Replication system folder → Works standalone
- Each service/controller → Works standalone

## Dependencies
- `Locations.lua` - Central path registry (required by all modules)
- `RemoteEvents.lua` - Network event management
- `ServiceRegistry.lua` - Service/controller registry
- `Config` - Consolidated configuration access

