# CLAUDE.md


You are an elite Roblox programmer specializing in Luau. You refactor, debug, create, and modify code to exact specifications while maintaining production-quality standards.
CODE STANDARDS:
- Follow SOLID principles (Single Responsibility, Open/Closed, Liskov Substitution, Interface Segregation, Dependency Inversion)
- Prioritize simplicity and maintainability over complexity
- Ensure code is modular and expandable for future features
- Make production-ready: handle edge cases, validate inputs, optimize performance
- Never include comments in code
OUTPUT FORMAT (to save tokens):
Provide targeted modifications only, not entire programs unless requested.
- Identify changes using descriptive context (e.g., "In PlayerDataManager's saveData function..." or "Within the Combat module's damage calculation...")
- Show code snippets with clear before/after format:
  Current: [snippet (first 5 lines) +"..."+ snippet (last 5 lines)]
  Replace with: [improved snippet]
  Reason: [brief explanation]
ANALYSIS CHECKLIST:
Before modifying, check for:
1. Logic errors (incorrect conditionals, loops, race conditions, timing issues)
2. Roblox-specific issues (inefficient RemoteEvents, memory leaks, poor replication, client/server violations)
3. Performance bottlenecks (unnecessary loops, inefficient data structures, missing debounces)
4. Security vulnerabilities (exploitable RemoteEvents, client-only validation, insecure data handling)
5. Scalability concerns (hard-coded limits, non-modular architecture, tight coupling)

WORKFLOW:
1. Acknowledge the system and its purpose
2. Ask clarifying questions if specifications are ambiguous
3. Present modifications with clear reasoning
4. Flag potential issues or trade-offs
5. If specifications conflict with best practices, warn and suggest alternatives
Balance SOLID, KISS, DRY, YAGNI principles with practical Roblox Luau patterns—prioritize pragmatism when warranted.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Roblox FPS hero shooter project built with Rojo, a tool for syncing Roblox projects from the filesystem. This is a standard Roblox development setup using Lua scripts organized across different Roblox services.

## Development Commands

### Core Development
- **IMPORTANT**: The user handles all Rojo commands. Claude should never run these commands.
- Rojo development server keeps the project automatically synced between VS Code and Roblox Studio

### Tool Management
- Install/manage tools via Rokit: `rokit install` (preferred) or Aftman: `aftman install`
- Available tools in rokit.toml: Rojo 7.5.1, Wally 0.3.2, Selene 0.29.0, Wally-package-types 1.5.1

### Linting
- `selene src/` - Run Selene linter on source files (configured in selene.toml)

## Project Structure

The project follows Roblox's service-based architecture:

- `src/ReplicatedStorage/` - Code that runs on both client and server, shared across all players
- `src/ServerScriptService/` - Server-side scripts that handle game logic, data, and security
- `src/ServerStorage/` - Server-only storage for assets and modules not accessible to clients
- `src/StarterPlayerScripts/` - Client-side scripts that run when a player joins
- `src/StarterCharacterScripts/` - Client-side scripts that run when a player's character spawns

### Key Files
- `default.project.json` - Rojo project configuration defining the file structure mapping
- `rokit.toml` - Primary tool dependency management (Rojo 7.5.1, Wally, Selene, etc.)
- `aftman.toml` - Legacy tool management (backup for Rojo 7.5.1)
- `selene.toml` - Linter configuration (Roblox std with global_usage allowed)

## Development Workflow

1. User runs Rojo development server (always active)
2. Project stays automatically synced between VS Code and Roblox Studio
3. Edit Lua files in the `src/` directory
4. Changes appear immediately in Roblox Studio for testing

## Code Conventions

- Use `.server.lua` extension for server scripts
- Use `.client.lua` extension for client scripts  
- Use `.lua` extension for ModuleScripts
- Follow Roblox Lua naming conventions and best practices

## Custom Character System

This project uses a fully custom character system with no Humanoid dependency:

### Architecture
- **Server Initializer** (`ServerScriptService/Initializer.server.lua`) - Disables character auto-loads and starts services
- **Client Initializer** (`StarterPlayerScripts/Initializer.client.lua`) - Starts client controllers
- **Locations Module** (`ReplicatedStorage/Modules/Locations.lua`) - Central script path registry

### Key Components
- **CharacterService** - Server-side character spawning and management
- **NetworkOwnershipService** - Manages network ownership for smooth client control  
- **CharacterController** - Client-side character movement and physics
- **CameraController** - Third-person camera system for custom character
- **InputManager** - Cross-platform input handling (PC/Mobile/Controller)
- **MobileControls** - Virtual thumbsticks and buttons for mobile devices

### Character Model Requirements
- Character model should be placed in `ServerStorage/Models/Character.rbxmx`
- Must have a primary part named "Root", "HumanoidRootPart", "Torso", or "UpperTorso"
- Should include a "Feet" part for precise ground detection positioning
- Should include a "Head" part for camera attachment
- No Humanoid required - physics handled by modern VectorForce/AlignOrientation system

### Character Hierarchy Structure
The character model follows this specific hierarchy:

```
Character (Model) - Root container
├── Collider (Model) - Collision detection system
│   ├── UncrouchCheck (Model) - Collision check for standing up from crouch
│   │   ├── CollisionBody (Part)
│   │   └── CollisionHead (Part)
│   ├── Crouch (Model) - Crouched state collision geometry
│   │   ├── CrouchBody (Part)
│   │   ├── CrouchHead (Part)
│   │   └── CrouchFace (Part)
│   └── Default (Model) - Standing state collision geometry
│       ├── Body (Part)
│       ├── Feet (Part) - Used for ground detection raycasting
│       ├── Head (Part) - Camera attachment point
│       └── Face (Part)
├── Root (Part) - PrimaryPart for physics (VectorForce/AlignOrientation)
├── Rig (Model) - Optional R6 character rig for cosmetics/animations
│   ├── Head (Part) - with attachments (HairAttachment, HatAttachment, FaceFrontAttachment, FaceCenterAttachment)
│   ├── Torso (Part) - with attachments and Motor6D connections (Neck, Left/Right Shoulder, Left/Right Hip)
│   ├── Left Arm (Part) - with LeftShoulderAttachment, LeftGripAttachment
│   ├── Right Arm (Part) - with RightShoulderAttachment, RightGripAttachment
│   ├── Left Leg (Part) - with LeftFootAttachment
│   ├── Right Leg (Part) - with RightFootAttachment
│   ├── HumanoidRootPart (Part) - with RootAttachment and RootJoint Motor6D
│   ├── Humanoid - Optional, not used by custom character system
│   └── BodyColors
├── HumanoidRootPart (Part) - For voice chat recognition (direct child of Character)
├── Head (Part) - For voice chat recognition (direct child of Character)
└── Humanoid - For voice chat recognition (direct child of Character)

Key Parts Referenced by Code:
- **Root** - PrimaryPart, receives VectorForce and AlignOrientation for movement/rotation
- **Default/Feet** - Ground detection raycast origin point
- **Default/Head** - Camera attachment and positioning
- **Collider/Default/** - Active collision parts during standing
- **Collider/Crouch/** - Active collision parts during crouching/sliding
- **Collider/UncrouchCheck/** - Used to detect if player can stand up from crouch
- **HumanoidRootPart** - Direct child of Character for voice chat
- **Head** - Direct child of Character for voice chat
- **Humanoid** - Direct child of Character for voice chat
```

**Important Notes:**
- The Rig model with Humanoid is optional and kept for cosmetic purposes (accessories, animations)
- The actual character physics ignores the Humanoid completely
- All collision states (Default, Crouch, UncrouchCheck) are toggled by `CrouchUtils.lua`
- The Root part is the only part with physics constraints (VectorForce, AlignOrientation)
- **Voice Chat Parts**: HumanoidRootPart, Head, and Humanoid are now direct children of the Character model (not in a separate Humanoid model) for proper Roblox voice chat recognition

## Architecture Patterns

### RemoteEvent Management
The project uses a centralized RemoteEvent system (`RemoteEvents.lua`) that:
- Auto-creates events from `EVENT_DEFINITIONS` table
- Provides convenience methods: `RemoteEvents:FireClient()`, `RemoteEvents:ConnectServer()`
- Events are stored in `ReplicatedStorage/RemoteEvents` folder
- Add new events by updating the `EVENT_DEFINITIONS` table

### Character Spawning Critical Pattern
When spawning characters in `CharacterService`, this assignment is **crucial**:
```lua
player.Character = characterModel  -- Required for Roblox character recognition
```
Without this, the character won't be properly recognized by Roblox systems.

### Health System (Humanoid-Based)
The game uses Roblox's built-in **Humanoid health system** for damage and death:
- **Health Management**: Set via `Humanoid.MaxHealth` and `Humanoid.Health` in `CharacterService:SetupHumanoid()`
- **Damage Application**: Uses `Humanoid:TakeDamage(damage)` in `WeaponHitService:ApplyDamage()`
- **Death Detection**: `Humanoid.Died` event connected in `CharacterService:SetupHumanoid()`
- **Regeneration**: DISABLED - Default Humanoid Health script is removed to prevent auto-regen
- **Killer Tracking**: Uses Humanoid attributes (`LastDamageDealer`, `WasHeadshot`) to track who dealt final blow
- **Fall Death**: Client sets `Humanoid.Health = 0` when Y position < `DeathYThreshold`
- **Configuration**: All health values in `HealthConfig.lua` (MaxHealth, RespawnDelay, etc.)

### Physics System
- **Modern Constraints**: Uses `VectorForce` and `AlignOrientation` for player characters
- **Legacy Support**: NPCs still use `BodyVelocity` system (see NPCService)
- **Movement**: Uses `AssemblyLinearVelocity` for velocity reading (not setting)
- **Rotation**: Characters always rotate to face camera direction via `AlignOrientation`
- **Ground Detection**: Raycasting from Feet part bottom with configurable offset/distance
- **Network Ownership**: Client-side physics with `CharacterUtils:ApplyNetworkOwnership()`

### Cross-Platform Input
- **PC**: WASD movement, Space jump, mouse look, J spawn NPC, K remove NPC
- **Mobile**: Virtual thumbsticks and buttons via `MobileControls` (auto-detected on touch devices)
- **Controller**: Left stick movement, right stick look, A button jump
- **Input Flow**: Hardware → `InputManager` → `CharacterController` via callback system
- **Priority System**: Last-pressed key wins for instant direction switching (prevents stuck states)

### Network Ownership
Characters use client-side physics with server authority. `CharacterUtils:ApplyNetworkOwnership()` gives players control of their character parts for smooth movement.

### Common Debug Patterns
When debugging character issues:
1. Check if `player.Character` is properly assigned
2. Verify PrimaryPart exists and is correctly referenced after cloning
3. For movement issues, check ground detection raycast visualization
4. For input issues, add debug prints to input callbacks to trace signal flow

### Module Organization
The codebase uses a clear separation between utilities and systems:

- **`ReplicatedStorage/Systems/`** - Complex systems and state managers organized by domain:
  - `Movement/` - SlidingSystem, MovementStateManager, MovementUtils
  - `Character/` - CharacterUtils, CrouchUtils
  - `Core/` - LogService, ConfigCache
- **`ReplicatedStorage/Utils/`** - Helper functions and external libraries (MathUtils, ValidationUtils, Sera, TopbarPlus, etc.)
- **`ReplicatedStorage/Modules/Locations.lua`** - Central path registry using Systems vs Utils pattern
- **Controllers**: `StarterPlayerScripts/Controllers/` for client-side logic
- **Services**: `ServerScriptService/Services/` for server-side logic

### Configuration Architecture
Configurations are consolidated into three logical files:
- **`GameplayConfig.lua`** - Character movement, physics, sliding system settings
- **`ControlsConfig.lua`** - Input bindings, camera settings, mobile controls
- **`SystemConfig.lua`** - Network, server, logging, debug settings

Access pattern: `Config.Gameplay.Character.*`, `Config.Controls.Camera.*`, `Config.System.Debug.*`

## Key Systems

### NPC System
- **NPCService** - Manages AI-controlled characters using same character model as players
- **AI Behavior**: Random movement with idle periods, configurable in `AISettings`
- **Physics**: Uses legacy `BodyVelocity` system (different from players)
- **Controls**: J key spawns NPC, K key removes random NPC

### Camera System
- **First Person Only** - No third-person mode implemented
- **CameraController** - Handles smooth camera movement with mouse/touch/controller input
- **Crouch Integration** - Smooth camera height transitions during crouch/slide states
- **Settings**: Configurable sensitivity, angle limits, smoothness via ControlsConfig

### Mobile Support
- **MobileControls** - Auto-initializes on touch-enabled devices without keyboard
- **Virtual Controls**: Circular thumbstick for movement, touch button for jumping
- **Responsive Design**: Positioned at screen edges with proper touch handling

### Sliding System
- **Advanced Movement** - Complex sliding physics with slope detection and momentum
- **Slide Buffering** - Allows slide input during jumps with landing execution
- **State Management** - Integrated with MovementStateManager for clean transitions
- **Airborne Boost** - Landing velocity bonuses based on fall distance and air time

### Movement State System
- **Priority-based States** - Walking < Crouching < Sliding with proper transition rules
- **Callback System** - State change notifications for coordinated behavior
- **Input Integration** - Smart crouch/slide priority based on movement context

### TestMode System
- **Development Toggle** - Set `TestMode.ENABLED = false` for production builds
- **Studio Integration** - Auto-enables in Roblox Studio when `ENABLE_IN_STUDIO = true`
- **Granular Logging** - Individual flags for character movement, ground detection, input events
- **Visual Debug** - Options for raycast visualization, physics forces, character bounds

## Critical Development Patterns

### Import Path Rules
When accessing modules, always use the Locations registry to avoid hardcoded paths:
```lua
-- ✅ Correct - using Locations registry
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local MathUtils = require(Locations.Modules.Utils.MathUtils)

-- ❌ Wrong - hardcoded paths
local MovementUtils = require(ReplicatedStorage.Systems.Movement.MovementUtils)
```

### Systems vs Utils Classification
- **Systems** (`ReplicatedStorage/Systems/`) - Complex stateful objects, managers, controllers
- **Utils** (`ReplicatedStorage/Utils/`) - Pure functions, small helpers, no state

### Movement Architecture Flow
1. **Input** → `InputManager` detects hardware input (keyboard/touch/controller)
2. **Processing** → `CharacterController` processes input via callbacks
3. **State** → `MovementStateManager` handles walking/crouching/sliding transitions
4. **Physics** → `MovementUtils` applies forces via modern VectorForce constraints
5. **Specialized** → `SlidingSystem` handles complex slide physics and momentum

### Configuration Access Pattern
All configs follow the new consolidated structure:
```lua
local Config = require(Locations.Modules.Config)
-- Gameplay settings (character, sliding, physics)
Config.Gameplay.Character.WalkSpeed
Config.Gameplay.Sliding.InitialVelocity
-- Control settings (input, camera, mobile)
Config.Controls.Input.Jump
Config.Controls.Camera.MouseSensitivity
-- System settings (network, debug, logging)
Config.System.Debug.LogGroundDetection
Config.System.Network.AutoSpawnOnJoin
```

### Network Serialization with Sera
The project uses **Sera**, a high-performance buffer serialization library for efficient network data transmission:

**Key Files:**
- `Utils/Sera/` - Serialization library folder
  - `init.lua` - Core serialization library
  - `Schemas.lua` - Schema definitions for all network data
- `SERA_INTEGRATION.md` - Comprehensive integration guide

**When to Use Sera:**
- ✅ High-frequency network updates (>1 Hz)
- ✅ Complex data structures with multiple fields
- ✅ Data requiring type validation and tampering prevention
- ❌ Single primitive values (use raw RemoteEvent args)
- ❌ Very infrequent events (<0.1 Hz)

**Current Integration:**
- **Character State Replication** - Fully integrated (36 bytes, down from 48 bytes = 25% reduction)
- Uses `CompressionUtils:CompressState()` and `DecompressState()` internally
- Delta compression available for stationary players (54% total bandwidth reduction)

**Usage Pattern:**
```lua
-- 1. Get Sera modules
local Sera = require(Locations.Modules.Utils.Sera)
local SeraSchemas = require(Locations.Modules.Utils.Sera.Schemas)

-- 2. Serialize data (client-side)
local buffer = Sera.Serialize(SeraSchemas.CharacterState, {
    Position = Vector3.new(0, 5, 0),
    Rotation = 1.57,  -- radians
    Velocity = Vector3.new(10, 0, 5),
    Timestamp = os.clock(),
})
RemoteEvents:FireServer("EventName", buffer)

-- 3. Deserialize data (server-side)
RemoteEvents:ConnectServer("EventName", function(player, buffer)
    local data = Sera.Deserialize(SeraSchemas.CharacterState, buffer)
    -- data.Position, data.Rotation, data.Velocity, data.Timestamp
    -- Sera automatically validates types and prevents client tampering
end)
```

**Available Sera Types:**
- Numbers: `Sera.Uint8`, `Sera.Uint16`, `Sera.Uint32`, `Sera.Int8`, `Sera.Int16`, `Sera.Int32`, `Sera.Float32`, `Sera.Float64`
- Roblox Types: `Sera.Vector3`, `Sera.CFrame`, `Sera.LossyCFrame`, `Sera.Color3`
- Strings: `Sera.String8` (max 255), `Sera.String16` (max 65k), `Sera.String32`
- Buffers: `Sera.Buffer8`, `Sera.Buffer16`, `Sera.Buffer32`
- Other: `Sera.Boolean`, `Sera.Angle8` (1-byte angle)

**Adding New Schemas:**
1. Define schema in `Sera/Schemas.lua`:
```lua
SeraSchemas.HitRequest = Sera.Schema({
    AttackerUserId = Sera.Uint32,  -- 4 bytes
    TargetUserId = Sera.Uint32,    -- 4 bytes
    Timestamp = Sera.Float64,      -- 8 bytes
})
```

2. Use in your code (see SERA_INTEGRATION.md for full examples)

**Pre-defined Schemas Ready to Use:**
- `CharacterState` - Position, rotation, velocity, timestamp (36 bytes)
- `CharacterStateDelta` - Delta compression variant
- `AnimationState`, `HitRequest`, `RoundPhase`, `PlayerState`, `CrouchState`, `SoundRequest`, etc.

**Error Handling:**
```lua
local buf, err = Sera.Serialize(schema, data)
if not buf then
    Log:Warn("SERA", "Serialization failed", { Error = err })
    return
end
```

**Best Practices:**
- Always use Locations registry: `require(Locations.Modules.Utils.Sera)`
- Validate data types match schema exactly (Sera enforces this)
- Use smallest type possible (Uint8 instead of Uint32 if value is <255)
- Use enums for string-based states (see `Sera/Schemas.lua` Enums)
- Check SERA_INTEGRATION.md for detailed examples and troubleshooting

### Crosshair System
A modular framework for managing dynamic crosshairs that respond to player movement and weapon recoil.

**Architecture:**
- **CrosshairController** (`ReplicatedStorage/Systems/Crosshair/CrosshairController.lua`): Core logic managing update loops, velocity/recoil state, and applying crosshair modules.
- **Crosshair Modules** (`ReplicatedStorage/Systems/Crosshair/Crosshairs/`): Individual crosshair behaviors (e.g., Default, Shotgun). Define visual appearance and update logic.
- **CrosshairUIController** (`StarterPlayerScripts/Controllers/UI/CrosshairUIController.lua`): Client-side bridge connecting the system to weapon events (equip, unequip, fire).
- **Configuration** (`ReplicatedStorage/Configs/CrosshairConfig.lua`): Defines customization defaults, weapon-to-crosshair mappings, and spread parameters.

**Key Features:**
- **Velocity Response**: Crosshairs expand when moving, contract when stationary.
- **Recoil Integration**: Expands on weapon fire events with smooth recovery.
- **Customization**: Full support for changing colors, sizes, opacities, and toggling elements (dot, lines).
- **Modular Design**: Easy to add new crosshair styles by creating new modules in `Crosshairs/`.

**Utilities:**
The system relies on several core utilities in `ReplicatedStorage/Utils/`:
- **Signal**: Lightweight event handling.
- **ConnectionManager**: Grouped connection management for clean lifecycle and memory safety.
- **TweenLibrary**: Wrapper for common UI animations.

**Usage:**
The system is automatically initialized by `Initializer.client.lua`. It listens to events from `InventoryController` to swap crosshairs and apply recoil effects automatically.