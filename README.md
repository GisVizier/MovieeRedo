# AnimeFPSProject

Documentation for the current workspace project (Roblox experience) with a focus on **runtime movement + camera**, and the supporting systems (input, replication, character spawn, ragdoll, config).

## Repo map (high-level)

- `src/ReplicatedStorage/Global/`: **Config sources** (Camera / Controls / Character / Movement / Replication / System).
- `src/ReplicatedStorage/Shared/`: Shared utilities + net wrapper (`Shared/Net`) + config aggregator (`Shared/Config/Config.lua`).
- `src/ReplicatedStorage/Game/`: Shared “gameplay” modules used by client and/or server (movement utilities, replication helpers, rig helpers, etc).
- `src/StarterPlayer/StarterPlayerScripts/Initializer/`: Client boot and controller modules.
- `src/ServerScriptService/Server/`: Server boot and services.

## Boot / wiring (client + server)

Both sides follow the same pattern:

- Call `Net:Init()` to create/find `ReplicatedStorage/Remotes` and bind `RemoteEvent` / `UnreliableRemoteEvent` instances.
- Create a `Registry`.
- Call `Loader:Load(entries, registry, Net)`:
  - `Init(registry, net)` for each entry (if present)
  - registers into the registry (if not already registered)
  - then calls `Start()` for each entry (if present)

Files:

- Client entrypoint: `src/StarterPlayer/StarterPlayerScripts/Initializer/Initializer.client.lua`
- Server entrypoint: `src/ServerScriptService/Server/Initializer.server.lua`
- Loader: `src/ReplicatedStorage/Shared/Util/Loader.lua`
- Registry (client): `src/StarterPlayer/StarterPlayerScripts/Initializer/Registry/Registry.lua`
- Registry (server): `src/ServerScriptService/Server/Registry/Registry.lua`
- Net wrapper + remotes list: `src/ReplicatedStorage/Shared/Net/Net.lua`, `src/ReplicatedStorage/Shared/Net/Remotes.lua`

### Client controllers loaded

From `Initializer.client.lua` the client loads (in order):

- `Input` → `Controllers/Input/InputController.lua`
- `Character` → `Controllers/Character/CharacterController.lua` (spawn/rig/ragdoll wiring)
- `Movement` → `Controllers/Movement/MovementController.lua` (note: the module table inside is named `CharacterController`)
- `AnimationController` → `Controllers/Character/AnimationController.lua`
- `Replication` → `Controllers/Replication/ReplicationController.lua`
- `Camera` → `Controllers/Camera/CameraController.lua`

### Server services loaded

From `Initializer.server.lua` the server loads:

- `CollisionGroupService` → `Services/Collision/CollisionGroupService.lua`
- `CharacterService` → `Services/Character/CharacterService.lua`
- `ReplicationService` → `Services/Replication/ReplicationService.lua`
- `MovementService` → `Services/Movement/MovementService.lua` (currently stubbed)

## Config map (where to tune things)

`src/ReplicatedStorage/Shared/Config/Config.lua` aggregates config from `ReplicatedStorage/Global/*`:

- Movement/character physics: `src/ReplicatedStorage/Global/Character.lua`, `src/ReplicatedStorage/Global/Movement.lua`
- Camera (modes, smoothing, FOV): `src/ReplicatedStorage/Global/Camera.lua`
- Replication (rates/compression/interp): `src/ReplicatedStorage/Global/Replication.lua`
- Controls/keybinds: `src/ReplicatedStorage/Global/Controls.lua`
- System/network/logging/humanoid defaults: `src/ReplicatedStorage/Global/System.lua`

`src/ReplicatedStorage/Shared/Util/ConfigCache.lua` precomputes commonly-used values (movement force, walk speed, gravity, etc) for hot paths like `MovementUtils`.

## Character lifecycle (spawn/respawn wiring)

### Server side: `CharacterService`

Key responsibilities:

- Disables Roblox auto-character: `Players.CharacterAutoLoads = false`
- On `PlayerAdded`: fires `ServerReady` and sends `CharacterSpawned` events for existing players.
- Handles spawn/respawn:
  - remote `RequestCharacterSpawn` → `SpawnCharacter(player)`
  - remote `RequestRespawn` → `SpawnCharacter(player)` (only after client setup complete)
- Tracks “client setup complete” gating via remote `CharacterSetupComplete`.
- Replicates crouch visual state (`CrouchStateChanged`) from one player to all other clients.
- Manages ragdoll creation/cleanup and broadcasts `RagdollStarted` / `RagdollEnded`.

Source: `src/ServerScriptService/Server/Services/Character/CharacterService.lua`

### Client side: `CharacterController`

Key responsibilities:

- On `ServerReady` → fires `RequestCharacterSpawn` once.
- On `CharacterSpawned(character)`:
  - If local: clones missing parts from `ReplicatedStorage/CharacterTemplate`, sets up physics constraints on `Root`, creates rig (if enabled), sets up crouch welds, then notifies server `CharacterSetupComplete` and requests initial replication states (`RequestInitialStates`).
  - If remote: creates/attaches a rig and prepares it for replicated motion.
- On local death: fires `RequestRespawn`.
- Handles ragdoll events:
  - On local ragdoll: saves camera mode and calls `CameraController:SetRagdollFocus(ragdollHead)`
  - On ragdoll end: restores camera mode via `CameraController:ClearRagdollFocus()` + `SetCameraMode(savedMode)`

Source: `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Character/CharacterController.lua`

## Input system (PC / mobile / controller)

### Main modules

- Input API entry: `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Input/InputController.lua`
- Input state + keybind handling: `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Input/InputManager.lua`
- Keybind config: `src/ReplicatedStorage/Global/Controls.lua`

### How input reaches movement

`MovementController.lua` (movement runtime controller) connects to `InputManager:ConnectToInput(...)` for:

- `Movement` (Vector2) → updates movement state and movement direction
- `Jump` (bool) → forwarded to `MovementInputProcessor`
- `Sprint` / `Crouch` / `Slide` (bool)

Jump-specific decision logic lives in:

- `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Movement/MovementInputProcessor.lua`

## Movement system (runtime hot path)

### Where movement runs

Movement updates run on **Heartbeat**:

- `RunService.Heartbeat` → `StartMovementLoop()` → `UpdateMovement(deltaTime)`

Main module file:

- `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Movement/MovementController.lua`

### Core runtime functions to know

In the movement controller (same file as above), the most important per-frame functions are:

- `StartMovementLoop()`: binds the Heartbeat connection and calls `UpdateMovement(dt)`.
- `UpdateMovement(dt)`: orchestrates the frame:
  - `CheckDeath()`
  - `UpdateCachedCameraRotation()`
  - `CheckGrounded()` → updates `MovementStateManager` grounded state
  - slide buffering/jump-cancel buffering hooks into `SlidingSystem`
  - if not sliding: `UpdateRotation()` + `ApplyMovement()`
  - updates camera FOV momentum and speed VFX (`FOVController`, `VFXController`)
- `UpdateRotation()`: rotates either to camera yaw (Shoulder/FirstPerson) or to movement direction (Orbit) by consulting `CameraController:ShouldRotateCharacterToCamera()`.
- `ApplyMovement()`: computes and applies forces via `VectorForce` and resolves wall-stuck/edge cases.
- `ApplyAirborneDownforce(dt)`: optional airborne gravity damping behavior.
- `CanUncrouch()` / `StartUncrouchChecking()` / `StopUncrouchChecking()`: continuous overlap checks for safe uncrouch.

Supporting systems used by the hot path:

- Movement state machine: `src/ReplicatedStorage/Game/Movement/MovementStateManager.lua`
  - `TransitionTo(state)`
  - `UpdateMovementState(isMoving)`
  - `UpdateGroundedState(isGrounded)`
- Shared physics helpers: `src/ReplicatedStorage/Game/Movement/MovementUtils.lua`
  - `SetupPhysicsConstraints(primaryPart)` (creates `VectorForce` + `AlignOrientation`)
  - `CheckGrounded(character, primaryPart, raycastParams)`
  - `CalculateMovementForce(...)`
  - `ApplyJump(primaryPart, isGrounded, ...)`
- Jump input routing: `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Movement/MovementInputProcessor.lua`
  - `OnJumpPressed() / OnJumpReleased()`
  - `ProcessJumpInput(isImmediatePress)`
  - `HandleSlidingJump()` (jump-cancel)
  - `HandleNormalJump(isImmediatePress)` (normal jump or wall-jump decision)
  - `HandleWallJump()`
- Wall-jump: `src/ReplicatedStorage/Game/Movement/WallJumpUtils.lua`
  - `AttemptWallJump(...)` / `ExecuteWallJump(...)`
- Sliding: `src/ReplicatedStorage/Game/Movement/SlidingSystem.lua`
  - `StartSlide(...)`, `UpdateSlide(dt)`, `StopSlide(...)`
  - buffering APIs: `StartSlideBuffer(...)`, `CancelSlideBuffer(...)`
  - jump-cancel APIs (delegated into submodules): `ExecuteJumpCancel(...)`, `CanBufferJumpCancel()`, etc.

### State machine notes (movement)

The state machine is priority-based:

- Walking < Sprinting < Crouching < Sliding

Implementation: `src/ReplicatedStorage/Game/Movement/MovementStateManager.lua`

Also note that the movement state manager handles **visual crouch replication**:

- `UpdateVisualCrouchForState(state)` toggles crouch visuals and fires `Net:FireServer("CrouchStateChanged", isCrouching)`.

## Camera system (runtime hot path)

### Where camera runs

Camera updates run on **RenderStep**:

- `RunService:BindToRenderStep("MovieeV2CameraController", Enum.RenderPriority.Camera.Value + 10, ...)`
- Per-frame: `CameraController:UpdateCamera()`

Main module file:

- `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Camera/CameraController.lua`

### Modes + important runtime functions

Modes are configured in `src/ReplicatedStorage/Global/Camera.lua`:

- `Orbit`
- `Shoulder`
- `FirstPerson`

Core functions:

- `SetupInput()` + `SetupTouchCamera()`: mouse/controller/touch camera input.
- `CycleCameraMode()` / `ApplyCameraModeSettings()`: mode switching (default key: `T`).
- `UpdateCamera()` (RenderStep hot path):
  - enforces `CameraType = Scriptable`
  - updates angles from input
  - applies crouch offsets
  - dispatches into the active mode:
    - `UpdateOrbitCamera(camera, dt)`
    - `UpdateShoulderCamera(camera, dt)`
    - `UpdateFirstPersonCamera(camera, dt)`
  - updates FOV through `FOVController`
- Movement integration point:
  - `ShouldRotateCharacterToCamera()` tells movement whether to rotate to camera yaw (Shoulder/FirstPerson) or to movement direction (Orbit).

Camera effects:

- FOV momentum/effects: `src/ReplicatedStorage/Shared/Util/FOVController.lua`
  - Heartbeat loop that lerps `workspace.CurrentCamera.FieldOfView`
  - `AddEffect("Sprint"|"Slide")`, `UpdateMomentum(speed)` used by movement/camera
- Screen shake: `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Camera/ScreenShakeController.lua`

## Networking / replication

### Remotes (single source of truth)

All remotes are defined in:

- `src/ReplicatedStorage/Shared/Net/Remotes.lua`

Key ones:

- `ServerReady`: server → client, server finished initializing
- `RequestCharacterSpawn`: client → server, spawn request
- `RequestRespawn`: client → server, respawn request
- `CharacterSpawned`: server → clients, a character model is in workspace
- `CharacterRemoving`: server → clients, character is being removed
- `CharacterSetupComplete`: client → server, local client finished attaching template/rig/etc
- `CrouchStateChanged`: client → server (and server → other clients), replicate crouch visuals
- `ToggleRagdollTest`: client → server, debug ragdoll toggle
- `RagdollStarted` / `RagdollEnded`: server → clients, ragdoll lifecycle
- `CharacterStateUpdate` (unreliable): client → server, movement replication packet
- `CharacterStateReplicated` (unreliable): server → clients, batched states for remote players
- `RequestInitialStates`: client → server, request current state snapshot for all players

### Client → server → clients flow

Config: `src/ReplicatedStorage/Global/Replication.lua`

- **Client sender**: `src/ReplicatedStorage/Game/Replication/ClientReplicator.lua`
  - Heartbeat loop
  - `SendStateUpdate()` fires `Net:FireServer("CharacterStateUpdate", compressedState)`
  - uses `CompressionUtils` + delta suppression (don’t send if unchanged beyond thresholds)
- **Server broadcaster**: `src/ServerScriptService/Server/Services/Replication/ReplicationService.lua`
  - `OnClientStateUpdate(player, compressedState)` stores latest state per player
  - Heartbeat loop broadcasts `CharacterStateReplicated` at configured rate (batching supported)
- **Client receiver/interpolator**: `src/ReplicatedStorage/Game/Replication/RemoteReplicator.lua`
  - `OnStatesReplicated(batch)` buffers snapshots per remote player
  - Heartbeat loop `ReplicatePlayers(dt)` interpolates toward buffered states and updates anchored remote “bean” + rig via `BulkMoveTo`

## Collision groups

Server configures collision groups at startup:

- `Players` do not collide with other `Players`
- `Hitboxes` do not collide with `Players` or other `Hitboxes`
- `Ragdolls` do not collide with `Players` or `Hitboxes`

Source: `src/ServerScriptService/Server/Services/Collision/CollisionGroupService.lua`

## “Where do I look when X breaks?”

- Movement feels wrong / player not moving:
  - `MovementController.lua` → `UpdateMovement()` + `ApplyMovement()`
  - `MovementUtils.lua` → `CalculateMovementForce()` + `CheckGrounded()`
  - `ConfigCache.lua` to confirm runtime constants (walk speed, movement force, gravity, etc)
- Jump / wall-jump / jump-cancel issues:
  - `MovementInputProcessor.lua` (decision tree)
  - `SlidingSystem.lua` (jump-cancel + buffering)
  - `WallJumpUtils.lua`
- Camera overwritten / not scriptable:
  - `CameraController.lua` → `UpdateCamera()` (it hard-enforces `CameraType = Scriptable`)
  - look for other camera scripts (ex: PlayerModule) fighting it
- Other players jitter / replication issues:
  - `ClientReplicator.lua` (send cadence + delta suppression)
  - `ReplicationService.lua` (broadcast cadence + batching)
  - `RemoteReplicator.lua` (buffer delay + interpolation)

# rewriteFPS
# rewriteFPS
