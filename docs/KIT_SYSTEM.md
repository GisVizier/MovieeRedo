# Kit System Documentation

> Complete API reference for the Kit System — abilities, ultimates, VFX, and client-server architecture.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [File Structure](#file-structure)
3. [KitConfig](#kitconfig)
4. [KitService (Server)](#kitservice-server)
5. [KitController (Client)](#kitcontroller-client)
6. [Server Kit Modules](#server-kit-modules)
7. [Client Kit Modules](#client-kit-modules)
8. [VFX System](#vfx-system)
9. [Types Reference](#types-reference)
10. [Complete Flow Examples](#complete-flow-examples)
11. [Creating a New Kit](#creating-a-new-kit)

---

## Architecture Overview

The Kit System uses a **client-server split architecture** with three main layers:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           KIT SYSTEM ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   CLIENT SIDE                              SERVER SIDE                   │
│   ════════════                             ═══════════                   │
│                                                                          │
│   ┌─────────────────┐                     ┌─────────────────┐           │
│   │  KitController  │◄────KitState────────│   KitService    │           │
│   │  (Input Router) │─────KitRequest─────►│ (Authority)     │           │
│   └────────┬────────┘                     └────────┬────────┘           │
│            │                                       │                     │
│            ▼                                       ▼                     │
│   ┌─────────────────┐                     ┌─────────────────┐           │
│   │   ClientKits/   │                     │     Kits/       │           │
│   │  (Prediction)   │                     │ (Server Logic)  │           │
│   └────────┬────────┘                     └────────┬────────┘           │
│            │                                       │                     │
│            │                                       │                     │
│   ┌────────▼────────┐                              │                     │
│   │ KitVFXController│◄─────────Events──────────────┘                     │
│   └────────┬────────┘                                                    │
│            │                                                             │
│            ▼                                                             │
│   ┌─────────────────┐                                                    │
│   │  VFXController  │                                                    │
│   └────────┬────────┘                                                    │
│            │                                                             │
│            ▼                                                             │
│   ┌─────────────────┐                                                    │
│   │      VFX/       │                                                    │
│   │ (Visual Effects)│                                                    │
│   └─────────────────┘                                                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

| Direction | Remote | Payload | Purpose |
|-----------|--------|---------|---------|
| Client → Server | `KitRequest` | `{ action, kitId?, abilityType?, inputState?, extraData? }` | Request actions |
| Server → Client | `KitState` | State or Event message | Sync state & broadcast events |

### Key Principles

1. **Server Authority**: All kit equipping, ability validation, and state changes happen server-side
2. **Client Prediction**: Clients can start animations/effects before server confirmation
3. **Interrupt Recovery**: If server rejects, client receives interrupt to cancel prediction
4. **VFX Broadcast**: Effects replicate to ALL clients via events

---

## File Structure

```
src/
├── ReplicatedStorage/
│   ├── Configs/
│   │   └── KitConfig.lua              # Kit metadata & stats
│   │
│   └── KitSystem/
│       ├── Types.lua                  # Type definitions
│       ├── KitService.lua             # Server implementation (shared)
│       ├── KitController.lua          # Client implementation
│       │
│       ├── Kits/                      # Server kit modules
│       │   ├── Template.lua
│       │   ├── WhiteBeard.lua
│       │   ├── Airborne.lua
│       │   ├── HonoredOne.lua
│       │   └── ...
│       │
│       ├── ClientKits/                # Client kit modules
│       │   ├── Template.lua
│       │   ├── WhiteBeard.lua
│       │   ├── Airborne.lua
│       │   ├── HonoredOne.lua
│       │   └── ...
│       │
│       └── VFX/                       # Per-kit VFX handlers
│           ├── WhiteBeard.lua
│           ├── Airborne.lua
│           ├── HonoredOne.lua
│           └── ...
│
├── ServerScriptService/
│   └── Server/Services/Kit/
│       └── KitService.lua             # Server bootstrap
│
└── StarterPlayer/StarterPlayerScripts/
    └── Initializer/Controllers/
        └── KitVFX/
            └── KitVFXController.lua   # VFX event listener
```

---

## KitConfig

**Path**: `src/ReplicatedStorage/Configs/KitConfig.lua`

Central configuration for all kit metadata, stats, and UI data.

### Data Types

```lua
export type AbilityData = {
    Name: string,
    Description: string,
    Video: string?,
    Damage: number?,
    DamageType: string?,
    Destruction: string?,
    Cooldown: number,
}

export type PassiveData = {
    Name: string,
    Description: string,
    Video: string?,
    PassiveType: string?,
}

export type UltimateData = {
    Name: string,
    Description: string,
    Video: string?,
    Damage: number?,
    DamageType: string?,
    Destruction: string?,
    UltCost: number,
}

export type KitData = {
    Icon: string,
    Name: string,
    Description: string,
    Rarity: string,
    Price: number,
    Module: string,
    Ability: AbilityData,
    Passive: PassiveData,
    Ultimate: UltimateData,
}
```

### Kit Definition Example

```lua
KitConfig.Kits = {
    WhiteBeard = {
        Icon = "rbxassetid://72158182932036",
        Name = "WHITE BEARD",
        Description = "A colossal warrior whose titan-hammer cracks the earth...",
        Rarity = "Legendary",
        Price = 1250,
        Module = "WhiteBeard",  -- Module name in Kits/ and ClientKits/

        Ability = {
            Name = "QUAKE BALL",
            Description = "Condenses seismic energy into a crackling sphere...",
            Video = "",
            Damage = 45,
            DamageType = "Projectile",
            Destruction = "Huge",
            Cooldown = 8,
        },

        Passive = {
            Name = "EARTHSHAKER",
            Description = "Your presence rattles the battlefield...",
            Video = "",
            PassiveType = "Aura",
        },

        Ultimate = {
            Name = "GURA GURA NO MI",
            Description = "Unleash the full power of the tremor fruit...",
            Video = "",
            Damage = 120,
            DamageType = "AOE",
            Destruction = "Mega",
            UltCost = 100,
        },
    },
}
```

### Rarity Info

```lua
KitConfig.RarityInfo = {
    Legendary = { TEXT = "LEGENDARY", COLOR = Color3.fromRGB(255, 209, 43) },
    Mythic    = { TEXT = "MYTHIC",    COLOR = Color3.fromRGB(255, 67, 70) },
    Epic      = { TEXT = "EPIC",      COLOR = Color3.fromRGB(180, 76, 255) },
    Rare      = { TEXT = "RARE",      COLOR = Color3.fromRGB(125, 188, 255) },
    Common    = { TEXT = "COMMON",    COLOR = Color3.fromRGB(203, 208, 218) },
}
```

### Input Config

```lua
KitConfig.Input = {
    AbilityKey = Enum.KeyCode.E,
    UltimateKey = Enum.KeyCode.Q,
}
```

### Functions

#### `getKit(kitId: string): KitData?`
Returns the full kit data table for a given kit ID, or `nil` if not found.

```lua
local kit = KitConfig.getKit("WhiteBeard")
print(kit.Name)  -- "WHITE BEARD"
print(kit.Ability.Cooldown)  -- 8
```

#### `getKitIds(): {string}`
Returns an array of all kit IDs.

```lua
local ids = KitConfig.getKitIds()
-- { "WhiteBeard", "Mob", "ChainsawMan", "Genji", "Aki", "HonoredOne", "Airborne" }
```

#### `getAbilityCooldown(kitId: string): number`
Returns the ability cooldown in seconds.

```lua
local cd = KitConfig.getAbilityCooldown("WhiteBeard")  -- 8
```

#### `getUltimateCost(kitId: string): number`
Returns the ultimate energy cost.

```lua
local cost = KitConfig.getUltimateCost("WhiteBeard")  -- 100
```

#### `buildKitData(kitId: string, state: KitRuntimeState?): {[string]: any}?`
Builds a runtime UI data table with cooldown state calculated.

```lua
local uiData = KitConfig.buildKitData("WhiteBeard", {
    abilityCooldownEndsAt = os.clock() + 5,
    ultimate = 75,
})

-- Returns:
-- {
--     KitId = "WhiteBeard",
--     KitName = "WHITE BEARD",
--     Icon = "rbxassetid://...",
--     Rarity = "Legendary",
--     AbilityName = "QUAKE BALL",
--     AbilityCooldown = 8,
--     AbilityOnCooldown = true,
--     AbilityCooldownRemaining = 5,
--     UltimateName = "GURA GURA NO MI",
--     UltCost = 100,
--     HasPassive = true,
--     PassiveName = "EARTHSHAKER",
-- }
```

---

## KitService (Server)

**Path**: `src/ReplicatedStorage/KitSystem/KitService.lua`

The authoritative server-side service that manages all kit state, validation, and replication.

### Constructor

#### `KitService.new(net): KitService`
Creates a new KitService instance.

| Parameter | Type | Description |
|-----------|------|-------------|
| `net` | `any` | Network module with `FireClient`, `FireAllClients`, `ConnectServer` |

```lua
local kitService = KitService.new(Net)
```

### Lifecycle

#### `start(): KitService`
Initializes the service, connects player events, and listens for `KitRequest` remote.

```lua
kitService:start()
```

### Internal State Management

#### `_ensurePlayer(player: Player): PlayerInfo`
Creates or returns existing player kit data.

**Default PlayerInfo:**
```lua
{
    gems = 15000,
    ownedKits = { "WhiteBeard", "Genji", "Aki", "Airborne", "HonoredOne" },
    equippedKitId = nil,
    ultimate = 0,
    abilityCooldownEndsAt = 0,
}
```

#### `_isOwned(info, kitId: string): boolean`
Checks if player owns a kit.

#### `_applyAttributes(player: Player, info)`
Syncs player data to Roblox attributes:
- `Gems` (number)
- `OwnedKits` (JSON string)
- `Ultimate` (number)
- `KitData` (JSON string or nil)

### Kit Instance Management

#### `_loadKit(kitId: string): (KitDef?, string?)`
Requires the server kit module from `Kits/`.

Returns `(module, nil)` on success or `(nil, errorCode)` on failure.

Error codes: `"InvalidKit"`, `"MissingKitsFolder"`, `"MissingKitModule"`, `"BadKitModule"`

#### `_ensureKitInstance(player: Player, info): KitInstance?`
Creates or returns the active kit instance for a player.
- Tears down previous kit if swapping
- Calls `kit:SetCharacter()` and `kit:OnEquipped()`
- Fires `KitEquipped` event to all clients

#### `_destroyKit(player: Player, reason: string?)`
Destroys the active kit instance.
- Calls `kit:OnUnequipped()` and `kit:Destroy()`
- Fires `KitUnequipped` event to all clients

### State Replication

#### `_fireState(player: Player, info, state)`
Sends a full state update to one client.

**Message structure:**
```lua
{
    kind = "State",
    serverNow = os.clock(),
    equippedKitId = string?,
    ultimate = number,
    abilityCooldownEndsAt = number,
    lastAction = string?,
    lastError = string?,
}
```

#### `_fireEvent(player: Player, eventName: string, payload)`
Sends an event to one client.

#### `_fireEventAll(eventName: string, payload)`
Broadcasts an event to ALL clients.

**Event message structure:**
```lua
{
    kind = "Event",
    event = eventName,
    serverTime = os.clock(),
    playerId = number?,
    kitId = string?,
    effect = string?,
    abilityType = string?,
    position = Vector3?,
    extraData = { position = Vector3 },
}
```

### Core Actions

#### `_purchase(player: Player, info, kitId: string)`
Handles kit purchase.
- Validates kit exists
- Checks not already owned
- Checks sufficient gems
- Deducts price and adds to owned list

#### `_equip(player: Player, info, kitId: string)`
Handles kit equip.
- Validates kit exists and is owned
- Sets `equippedKitId`
- Creates kit instance
- Resets cooldowns

#### `_activateAbility(player: Player, info, abilityType: string, inputState, extraData)`
Handles ability/ultimate activation.

**Validation sequence:**
1. Check kit is equipped
2. Check character exists
3. Check cooldown (ability) or energy (ultimate)
4. Call `kit:OnAbility()` or `kit:OnUltimate()`
5. If returns `true`:
   - Update cooldowns/energy
   - Fire `AbilityActivated` to all clients
6. If returns `false`:
   - Fire `AbilityInterrupted` to requesting client only

### Public API

#### `addUltimate(player: Player, amount: number)`
Adds ultimate energy to a player.

```lua
kitService:addUltimate(player, 25)
```

#### `ReplicateVFXAll(eventName: string, payload)`
Broadcasts a custom VFX event to all clients.

**Contract:**
- `payload.kitId`: string (required)
- `payload.effect`: string (required)
- `payload.extraData.position`: Vector3 (required)

```lua
kitService:ReplicateVFXAll("CustomHit", {
    kitId = "WhiteBeard",
    effect = "Ability",
    extraData = { position = hitPosition },
})
```

### Remote Handler

The service listens for `KitRequest` remote and routes based on `action`:

| Action | Handler | Payload Fields |
|--------|---------|----------------|
| `"PurchaseKit"` | `_purchase` | `kitId` |
| `"EquipKit"` | `_equip` | `kitId` |
| `"ActivateAbility"` | `_activateAbility` | `abilityType`, `inputState`, `extraData` |
| `"RequestKitState"` | `_fireState` | (none) |

---

## KitController (Client)

**Path**: `src/ReplicatedStorage/KitSystem/KitController.lua`

Client-side controller that handles input, prediction, and UI state.

### Constructor

#### `KitController.new(player?, coreUi?, net?, inputController?): KitController`

| Parameter | Type | Description |
|-----------|------|-------------|
| `player` | `Player?` | Defaults to `LocalPlayer` |
| `coreUi` | `any?` | UI system with `emit()` method |
| `net` | `any?` | Network module |
| `inputController` | `any?` | Input system with `ConnectToInput()` |

```lua
local kitController = KitController.new(player, coreUi, net, inputController)
```

### Lifecycle

#### `init(): KitController`
Initializes the controller:
- Connects to `KitState` remote
- Binds `Ability` and `Ultimate` inputs

```lua
kitController:init()
```

#### `destroy()`
Cleans up all connections and kit instances.

### Client Kit Loading

#### `_loadClientKit(kitId: string?): ClientKit?`
Loads and caches the client kit module from `ClientKits/`.
- Returns cached instance if same kit
- Tears down previous kit if swapping
- Returns `nil` if module doesn't exist

### Input Handling

#### `_onAbilityInput(abilityType: string, inputState)`
Handles ability/ultimate input.

**Builds an `AbilityRequest` object:**
```lua
{
    kitId = string?,
    abilityType = "Ability" | "Ultimate",
    inputState = Enum.UserInputState,
    player = Player,
    character = Model?,
    humanoidRootPart = BasePart?,
    timestamp = number,
    Send = function(extraData?)  -- Call to replicate to server
}
```

**Routing:**
- `inputState == Begin` → `ClientKit[abilityType]:OnStart(request)`
- `inputState ~= Begin` → `ClientKit[abilityType]:OnEnded(request)`
- Falls back to immediate server call if no client kit

#### `_interruptClientKit(reason: string)`
Interrupts active client kit handlers with a reason.

**Reasons:**
- `"Swap"` — Kit being changed
- `"KitChanged"` — Server confirmed kit change
- `"Destroy"` — Controller being destroyed
- `"ServerInterrupted"` — Server rejected ability

### Server Communication

#### `requestPurchaseKit(kitId: string)`
Fires `KitRequest` with action `"PurchaseKit"`.

#### `requestEquipKit(kitId: string)`
Fires `KitRequest` with action `"EquipKit"`.

#### `requestActivateAbility(abilityType: string, inputState, extraData?)`
Fires `KitRequest` with action `"ActivateAbility"`.

### Event Handling

#### `_onKitMessage(message)`
Routes incoming `KitState` messages:
- `kind == "Event"` → `_onKitEvent()`
- Otherwise → `_onKitState()`

#### `_onKitState(state)`
Updates local state and emits UI events:
- `KitEquipped` when kit changes to a valid ID
- `KitUnequipped` when kit changes to nil
- `KitError` when `lastError` is present

#### `_onKitEvent(event)`
Handles broadcast events:

| Event | Emitted Events |
|-------|---------------|
| `KitEquipped` | `KitEquipped(kitId, playerId)` |
| `KitUnequipped` | `KitUnequipped(kitId, playerId)` |
| `AbilityActivated` | `KitLocalAbilityActivated` (if local), `KitAbilityActivated` |
| `AbilityEnded` | `KitLocalAbilityEnded` (if local), `KitAbilityEnded` |
| `AbilityInterrupted` | Calls `OnInterrupt`, emits `KitLocalAbilityInterrupted`, `KitAbilityInterrupted` |

### UI Events Emitted

| Event | Arguments | When |
|-------|-----------|------|
| `KitEquipped` | `kitId, playerId?` | Kit equipped (local or broadcast) |
| `KitUnequipped` | `kitId?, playerId?` | Kit unequipped |
| `KitError` | `errorCode` | Server returned error |
| `KitLocalAbilityActivated` | `kitId, abilityType` | Local player's ability started |
| `KitLocalAbilityEnded` | `kitId, abilityType` | Local player's ability ended |
| `KitLocalAbilityInterrupted` | `kitId, abilityType` | Local player's ability rejected |
| `KitAbilityActivated` | `kitId, playerId, abilityType` | Any player's ability started |
| `KitAbilityEnded` | `kitId, playerId, abilityType` | Any player's ability ended |
| `KitAbilityInterrupted` | `kitId, playerId, abilityType` | Any player's ability rejected |

---

## Server Kit Modules

**Path**: `src/ReplicatedStorage/KitSystem/Kits/*.lua`

Server-side kit logic that validates and executes abilities.

### Interface

```lua
local Kit = {}
Kit.__index = Kit

-- Constructor: receives context with player, character, config, service
function Kit.new(ctx: KitContext): Kit

-- Called when character respawns
function Kit:SetCharacter(character: Model?)

-- Cleanup
function Kit:Destroy()

-- Called when kit is equipped
function Kit:OnEquipped()

-- Called when kit is unequipped
function Kit:OnUnequipped()

-- Ability activation handler
-- Return true to allow, false to reject
function Kit:OnAbility(inputState: Enum.UserInputState, clientData: any?): boolean

-- Ultimate activation handler
-- Return true to allow, false to reject
function Kit:OnUltimate(inputState: Enum.UserInputState, clientData: any?): boolean

return Kit
```

### Context Object

```lua
{
    player = Player,
    character = Model?,
    kitId = string,
    kitConfig = KitData,
    service = KitService,  -- Can call service:ReplicateVFXAll(), etc.
}
```

### Template

```lua
local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
    local self = setmetatable({}, Kit)
    self._ctx = ctx
    return self
end

function Kit:SetCharacter(character)
    self._ctx.character = character
end

function Kit:Destroy()
    -- Cleanup connections, effects, etc.
end

function Kit:OnEquipped()
    -- Setup passive effects, etc.
end

function Kit:OnUnequipped()
    -- Cleanup passive effects
end

function Kit:OnAbility(_inputState, _clientData)
    -- Validate and execute ability
    -- Return true if successful
    return true
end

function Kit:OnUltimate(_inputState, _clientData)
    -- Validate and execute ultimate
    -- Return true if successful
    return true
end

return Kit
```

### Example: Ability with Server Validation

```lua
function Kit:OnAbility(inputState, clientData)
    if inputState ~= Enum.UserInputState.Begin then
        return true  -- Allow end events
    end
    
    local character = self._ctx.character
    if not character then
        return false  -- Reject: no character
    end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return false  -- Reject: no root part
    end
    
    -- Validate client data
    local origin = clientData and clientData.origin
    if typeof(origin) ~= "Vector3" then
        return false  -- Reject: invalid data
    end
    
    -- Check distance sanity
    if (origin - hrp.Position).Magnitude > 10 then
        return false  -- Reject: client position too far
    end
    
    -- Execute ability logic
    self:_fireQuakeBall(origin, hrp.CFrame.LookVector)
    
    return true  -- Allow
end
```

---

## Client Kit Modules

**Path**: `src/ReplicatedStorage/KitSystem/ClientKits/*.lua`

Client-side kit handlers for input, prediction, and local effects.

### Interface

```lua
local Kit = {}
Kit.__index = Kit

Kit.Ability = {}
Kit.Ultimate = {}

-- Called when ability key is PRESSED
function Kit.Ability:OnStart(abilityRequest: AbilityRequest)

-- Called when ability key is RELEASED
function Kit.Ability:OnEnded(abilityRequest: AbilityRequest)

-- Called when ability is interrupted/rejected
function Kit.Ability:OnInterrupt(abilityRequest: AbilityRequest, reason: string)

-- Same for Ultimate
function Kit.Ultimate:OnStart(abilityRequest: AbilityRequest)
function Kit.Ultimate:OnEnded(abilityRequest: AbilityRequest)
function Kit.Ultimate:OnInterrupt(abilityRequest: AbilityRequest, reason: string)

-- Constructor
function Kit.new(ctx: KitContext): Kit

-- Cleanup
function Kit:Destroy()

return Kit
```

### AbilityRequest Object

```lua
{
    kitId = string?,
    abilityType = "Ability" | "Ultimate",
    inputState = Enum.UserInputState,
    player = Player,
    character = Model?,
    humanoidRootPart = BasePart?,
    timestamp = number,
    Send = function(extraData?)  -- Call to replicate to server
}
```

### Key Pattern: Manual Send

The client kit decides **when** to call `abilityRequest.Send()`. This enables:

| Pattern | Implementation |
|---------|---------------|
| **Instant** | Call `Send()` immediately in `OnStart` |
| **Charge** | Store request, call `Send({ chargeAmount = x })` in `OnEnded` |
| **Aim** | Wait for valid target, then call `Send({ targetId = id })` |
| **Cancel** | Don't call `Send()` at all if player cancels |

### Template

```lua
local Kit = {}
Kit.__index = Kit

Kit.Ability = {}

function Kit.Ability:OnStart(abilityRequest)
    -- Start local prediction
    -- Play animation, sound, etc.
    
    -- Replicate to server
    abilityRequest.Send({
        origin = abilityRequest.humanoidRootPart.Position,
    })
end

function Kit.Ability:OnEnded(abilityRequest)
    -- Handle release
    abilityRequest.Send()
end

function Kit.Ability:OnInterrupt(_abilityRequest, _reason)
    -- Cancel local prediction
    -- Stop animation, destroy effects, etc.
end

Kit.Ultimate = {}

function Kit.Ultimate:OnStart(abilityRequest)
    abilityRequest.Send()
end

function Kit.Ultimate:OnEnded(abilityRequest)
    abilityRequest.Send()
end

function Kit.Ultimate:OnInterrupt(_abilityRequest, _reason)
end

function Kit.new(ctx)
    local self = setmetatable({}, Kit)
    self._ctx = ctx
    self.Ability = Kit.Ability
    self.Ultimate = Kit.Ultimate
    return self
end

function Kit:Destroy()
end

return Kit
```

### Example: Charge Ability

```lua
Kit.Ability = {
    _chargeStart = nil,
    _charging = false,
}

function Kit.Ability:OnStart(abilityRequest)
    -- Start charging
    self._chargeStart = os.clock()
    self._charging = true
    self._pendingRequest = abilityRequest
    
    -- Play charge animation
    -- Start charge VFX
end

function Kit.Ability:OnEnded(abilityRequest)
    if not self._charging then
        return
    end
    
    local chargeTime = os.clock() - self._chargeStart
    local chargePercent = math.clamp(chargeTime / 2, 0, 1)  -- 2 second max charge
    
    self._charging = false
    
    -- Send with charge data
    abilityRequest.Send({
        chargePercent = chargePercent,
        origin = abilityRequest.humanoidRootPart.Position,
    })
end

function Kit.Ability:OnInterrupt(_abilityRequest, _reason)
    self._charging = false
    self._pendingRequest = nil
    -- Cancel charge VFX
end
```

---

## VFX System

The VFX system routes server events to per-kit visual effect handlers.

### VFXController

**Path**: `src/ReplicatedStorage/Shared/Util/VFXController.lua`

Central dispatcher that routes events to kit-specific VFX modules.

#### `Dispatch(message)`
Routes a `KitState` event to the appropriate VFX handler.

**Routing path:**
```
KitSystem/VFX/{kitId}.lua[effect][event](props)
```

**Example:**
```lua
-- Message: { kitId = "WhiteBeard", effect = "Ability", event = "AbilityActivated", ... }
-- Routes to: VFX/WhiteBeard.lua.Ability.AbilityActivated(props)
```

### KitVFXController

**Path**: `src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/KitVFX/KitVFXController.lua`

Listens for `KitState` events and forwards to `VFXController`.

### VFX Module Interface

**Path**: `src/ReplicatedStorage/KitSystem/VFX/*.lua`

```lua
local KitVFX = {}

KitVFX.Ability = {}

function KitVFX.Ability.AbilityActivated(props)
    -- Play ability start VFX
end

function KitVFX.Ability.AbilityEnded(props)
    -- Play ability end VFX
end

function KitVFX.Ability.AbilityInterrupted(props)
    -- Play ability cancel VFX
end

KitVFX.Ultimate = {}

function KitVFX.Ultimate.AbilityActivated(props)
    -- Play ultimate start VFX
end

function KitVFX.Ultimate.AbilityEnded(props)
    -- Play ultimate end VFX
end

function KitVFX.Ultimate.AbilityInterrupted(props)
    -- Play ultimate cancel VFX
end

return KitVFX
```

### Props Object

```lua
{
    position = Vector3,       -- World position from extraData
    playerId = number,        -- Player who triggered
    kitId = string,           -- Kit ID
    effect = string,          -- "Ability" or "Ultimate"
    event = string,           -- "AbilityActivated", "AbilityEnded", "AbilityInterrupted"
    abilityType = string,     -- Same as effect
    raw = table,              -- Full original message
}
```

### Example VFX Module

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VFXPlayer = require(...)

local WhiteBeard = {}

WhiteBeard.Ability = {}

function WhiteBeard.Ability.AbilityActivated(props)
    local pos = props.position
    if not pos then return end
    
    -- Spawn cast VFX
    local template = ReplicatedStorage.Assets.VFX.WhiteBeard.QuakeBall_Cast
    VFXPlayer:Play(template:Clone(), pos)
end

function WhiteBeard.Ability.AbilityEnded(props)
    -- Optional: play release VFX
end

function WhiteBeard.Ability.AbilityInterrupted(props)
    -- Optional: play fizzle VFX
end

-- Custom event handler for hits
function WhiteBeard.Ability.TargetHit(props)
    local pos = props.position
    if not pos then return end
    
    local template = ReplicatedStorage.Assets.VFX.WhiteBeard.QuakeBall_Hit
    VFXPlayer:Play(template:Clone(), pos)
end

WhiteBeard.Ultimate = {}

function WhiteBeard.Ultimate.AbilityActivated(props)
    -- Big earthquake VFX
end

function WhiteBeard.Ultimate.AbilityEnded(props)
end

function WhiteBeard.Ultimate.AbilityInterrupted(props)
end

return WhiteBeard
```

---

## Types Reference

**Path**: `src/ReplicatedStorage/KitSystem/Types.lua`

### KitState
Server-to-client state sync payload.

```lua
export type KitState = {
    kind: string?,                    -- "State"
    equippedKitId: string?,           -- Currently equipped kit
    ultimate: number?,                -- Ultimate energy
    abilityCooldownEndsAt: number?,   -- When ability cooldown ends
    serverNow: number?,               -- Server timestamp
    lastAction: string?,              -- Last action performed
    lastError: string?,               -- Error code if failed
}
```

### KitEvent
Server-to-client event broadcast payload.

```lua
export type KitEvent = {
    kind: string,                     -- "Event"
    event: string,                    -- Event name
    playerId: number?,                -- Player who triggered
    kitId: string?,                   -- Kit ID
    effect: string?,                  -- "Ability" or "Ultimate"
    abilityType: string?,             -- Same as effect
    inputState: any?,                 -- Input state
    position: Vector3?,               -- World position
    extraData: any?,                  -- Additional data
    serverTime: number?,              -- Server timestamp
    reason: string?,                  -- Reason for interrupt
}
```

### KitRequest
Client-to-server action request payload.

```lua
export type KitRequest = {
    action: string,                   -- "PurchaseKit", "EquipKit", "ActivateAbility", "RequestKitState"
    kitId: string?,                   -- For purchase/equip
    abilityType: string?,             -- "Ability" or "Ultimate"
    inputState: any?,                 -- Input state
    extraData: any?,                  -- Client data for ability
}
```

### KitContext
Context passed to kit module constructors.

```lua
export type KitContext = {
    player: Player,
    character: Model?,
    kitId: string,
    kitConfig: any,                   -- KitData from KitConfig
    service: any,                     -- KitService (server only)
}
```

### ActionModule
Interface for ability handlers.

```lua
export type ActionModule = {
    onStart: (self: ActionModule) -> (),
    onInterrupt: (self: ActionModule, reason: string) -> (),
    onEnd: (self: ActionModule) -> (),
}
```

### KitModule
Interface for full kit modules.

```lua
export type KitModule = {
    new: (ctx: KitContext) -> KitModule,
    SetCharacter: (self: KitModule, character: Model?) -> (),
    Destroy: (self: KitModule) -> (),
    OnEquipped: (self: KitModule) -> (),
    OnUnequipped: (self: KitModule) -> (),
    OnAbility: (self: KitModule, inputState: any, extraData: any?) -> boolean,
    OnUltimate: (self: KitModule, inputState: any, extraData: any?) -> boolean,
}
```

---

## Complete Flow Examples

### Flow 1: Player Uses Ability (Success)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. Player presses E                                                      │
│    └─► InputController fires "Ability" input                            │
├─────────────────────────────────────────────────────────────────────────┤
│ 2. KitController._onAbilityInput("Ability", Begin)                      │
│    └─► Loads ClientKits/WhiteBeard.lua                                  │
│    └─► Calls WhiteBeard.Ability:OnStart(abilityRequest)                 │
├─────────────────────────────────────────────────────────────────────────┤
│ 3. ClientKit does local prediction                                       │
│    └─► Plays "QuakeBall_Cast" animation                                 │
│    └─► Spawns local charge effect                                       │
│    └─► Calls abilityRequest.Send({ origin = hrp.Position })             │
├─────────────────────────────────────────────────────────────────────────┤
│ 4. KitController fires KitRequest remote                                │
│    └─► { action = "ActivateAbility", abilityType = "Ability",           │
│          inputState = Begin, extraData = { origin = Vector3 } }         │
├─────────────────────────────────────────────────────────────────────────┤
│ 5. KitService._activateAbility() runs                                   │
│    └─► Validates cooldown: PASS                                         │
│    └─► Validates character: PASS                                        │
│    └─► Calls serverKit:OnAbility(Begin, { origin = ... })               │
│    └─► Server kit returns true                                          │
│    └─► Updates cooldown: abilityCooldownEndsAt = now + 8                │
│    └─► Fires AbilityActivated to ALL clients                            │
├─────────────────────────────────────────────────────────────────────────┤
│ 6. All clients receive AbilityActivated event                           │
│    └─► KitVFXController receives message                                │
│    └─► VFXController:Dispatch(message)                                  │
│    └─► Routes to VFX/WhiteBeard.Ability.AbilityActivated(props)         │
│    └─► VFX plays for all players                                        │
└─────────────────────────────────────────────────────────────────────────┘
```

### Flow 2: Player Uses Ability (Rejected - On Cooldown)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1-4. Same as success flow...                                            │
├─────────────────────────────────────────────────────────────────────────┤
│ 5. KitService._activateAbility() runs                                   │
│    └─► Validates cooldown: FAIL (still 3 seconds remaining)             │
│    └─► Fires AbilityInterrupted to LOCAL client only                    │
├─────────────────────────────────────────────────────────────────────────┤
│ 6. Local client receives AbilityInterrupted event                       │
│    └─► KitController calls ClientKit.Ability:OnInterrupt(req, "Server") │
│    └─► ClientKit cancels local prediction                               │
│    └─► Stops charge animation, destroys effects                         │
│    └─► Emits KitLocalAbilityInterrupted to UI                           │
└─────────────────────────────────────────────────────────────────────────┘
```

### Flow 3: Player Equips Kit

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. UI calls kitController:requestEquipKit("WhiteBeard")                 │
├─────────────────────────────────────────────────────────────────────────┤
│ 2. KitController fires KitRequest                                       │
│    └─► { action = "EquipKit", kitId = "WhiteBeard" }                    │
├─────────────────────────────────────────────────────────────────────────┤
│ 3. KitService._equip() runs                                             │
│    └─► Validates kit exists: PASS                                       │
│    └─► Validates ownership: PASS                                        │
│    └─► Sets equippedKitId = "WhiteBeard"                                │
│    └─► Calls _ensureKitInstance()                                       │
│        └─► Destroys previous kit (if any)                               │
│        └─► Loads Kits/WhiteBeard.lua                                    │
│        └─► Creates instance: kitDef.new(ctx)                            │
│        └─► Calls kit:SetCharacter(character)                            │
│        └─► Calls kit:OnEquipped()                                       │
│        └─► Fires KitEquipped to ALL clients                             │
│    └─► Updates player attributes (KitData JSON)                         │
│    └─► Fires State to requesting client                                 │
├─────────────────────────────────────────────────────────────────────────┤
│ 4. All clients receive KitEquipped event                                │
│    └─► KitController emits "KitEquipped" to UI                          │
│    └─► UI updates to show new kit                                       │
├─────────────────────────────────────────────────────────────────────────┤
│ 5. Local client receives State update                                   │
│    └─► KitController updates _state                                     │
│    └─► If kitId changed, loads ClientKits/WhiteBeard.lua                │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Creating a New Kit

### Step 1: Add to KitConfig

```lua
-- src/ReplicatedStorage/Configs/KitConfig.lua

KitConfig.Kits.MyNewKit = {
    Icon = "rbxassetid://123456789",
    Name = "MY NEW KIT",
    Description = "An awesome new kit with cool abilities.",
    Rarity = "Epic",
    Price = 500,
    Module = "MyNewKit",  -- Must match filename in Kits/ and ClientKits/

    Ability = {
        Name = "COOL ABILITY",
        Description = "Does something cool.",
        Damage = 30,
        DamageType = "Projectile",
        Destruction = "Medium",
        Cooldown = 6,
    },

    Passive = {
        Name = "PASSIVE BUFF",
        Description = "Gives a passive bonus.",
        PassiveType = "Buff",
    },

    Ultimate = {
        Name = "MEGA ULTIMATE",
        Description = "Unleashes ultimate power.",
        Damage = 100,
        DamageType = "AOE",
        Destruction = "Huge",
        UltCost = 100,
    },
}
```

### Step 2: Create Server Kit Module

```lua
-- src/ReplicatedStorage/KitSystem/Kits/MyNewKit.lua

local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
    local self = setmetatable({}, Kit)
    self._ctx = ctx
    self._passiveConnection = nil
    return self
end

function Kit:SetCharacter(character)
    self._ctx.character = character
end

function Kit:Destroy()
    if self._passiveConnection then
        self._passiveConnection:Disconnect()
        self._passiveConnection = nil
    end
end

function Kit:OnEquipped()
    -- Setup passive effects
    print("[MyNewKit] Equipped for", self._ctx.player.Name)
end

function Kit:OnUnequipped()
    -- Cleanup passive effects
    print("[MyNewKit] Unequipped for", self._ctx.player.Name)
end

function Kit:OnAbility(inputState, clientData)
    if inputState ~= Enum.UserInputState.Begin then
        return true
    end
    
    local character = self._ctx.character
    if not character then
        return false
    end
    
    -- Execute ability server logic
    print("[MyNewKit] Ability activated!")
    
    -- Example: Replicate custom VFX event
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then
        self._ctx.service:ReplicateVFXAll("ProjectileFired", {
            kitId = self._ctx.kitId,
            effect = "Ability",
            extraData = { position = hrp.Position },
        })
    end
    
    return true
end

function Kit:OnUltimate(inputState, clientData)
    if inputState ~= Enum.UserInputState.Begin then
        return true
    end
    
    local character = self._ctx.character
    if not character then
        return false
    end
    
    -- Execute ultimate server logic
    print("[MyNewKit] Ultimate activated!")
    
    return true
end

return Kit
```

### Step 3: Create Client Kit Module

```lua
-- src/ReplicatedStorage/KitSystem/ClientKits/MyNewKit.lua

local MyNewKit = {}
MyNewKit.__index = MyNewKit

MyNewKit.Ability = {}

function MyNewKit.Ability:OnStart(abilityRequest)
    -- Local prediction: play animation immediately
    local character = abilityRequest.character
    if character then
        local animator = character:FindFirstChild("Humanoid")
            and character.Humanoid:FindFirstChild("Animator")
        if animator then
            -- Play ability animation
        end
    end
    
    -- Send to server with position data
    local hrp = abilityRequest.humanoidRootPart
    abilityRequest.Send({
        origin = hrp and hrp.Position or nil,
        direction = hrp and hrp.CFrame.LookVector or nil,
    })
end

function MyNewKit.Ability:OnEnded(abilityRequest)
    abilityRequest.Send()
end

function MyNewKit.Ability:OnInterrupt(_abilityRequest, reason)
    -- Cancel local prediction
    print("[MyNewKit Client] Ability interrupted:", reason)
end

MyNewKit.Ultimate = {}

function MyNewKit.Ultimate:OnStart(abilityRequest)
    -- Play ultimate startup animation/effect
    abilityRequest.Send()
end

function MyNewKit.Ultimate:OnEnded(abilityRequest)
    abilityRequest.Send()
end

function MyNewKit.Ultimate:OnInterrupt(_abilityRequest, reason)
    print("[MyNewKit Client] Ultimate interrupted:", reason)
end

function MyNewKit.new(ctx)
    local self = setmetatable({}, MyNewKit)
    self._ctx = ctx
    self.Ability = MyNewKit.Ability
    self.Ultimate = MyNewKit.Ultimate
    return self
end

function MyNewKit:Destroy()
end

return MyNewKit
```

### Step 4: Create VFX Module

```lua
-- src/ReplicatedStorage/KitSystem/VFX/MyNewKit.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MyNewKit = {}

MyNewKit.Ability = {}

function MyNewKit.Ability.AbilityActivated(props)
    local pos = props.position
    if not pos then return end
    
    -- Spawn ability cast VFX at position
    print("[MyNewKit VFX] Ability activated at", pos)
    
    -- Example:
    -- local template = ReplicatedStorage.Assets.VFX.MyNewKit.AbilityCast
    -- local vfx = template:Clone()
    -- vfx.CFrame = CFrame.new(pos)
    -- vfx.Parent = workspace
    -- Debris:AddItem(vfx, 3)
end

function MyNewKit.Ability.AbilityEnded(props)
    print("[MyNewKit VFX] Ability ended")
end

function MyNewKit.Ability.AbilityInterrupted(props)
    print("[MyNewKit VFX] Ability interrupted")
end

-- Custom event handler
function MyNewKit.Ability.ProjectileFired(props)
    local pos = props.position
    if not pos then return end
    
    print("[MyNewKit VFX] Projectile fired from", pos)
    -- Spawn projectile VFX
end

MyNewKit.Ultimate = {}

function MyNewKit.Ultimate.AbilityActivated(props)
    local pos = props.position
    if not pos then return end
    
    print("[MyNewKit VFX] Ultimate activated at", pos)
    -- Big ultimate VFX
end

function MyNewKit.Ultimate.AbilityEnded(props)
    print("[MyNewKit VFX] Ultimate ended")
end

function MyNewKit.Ultimate.AbilityInterrupted(props)
    print("[MyNewKit VFX] Ultimate interrupted")
end

return MyNewKit
```

### Step 5: Add to Owned Kits (for testing)

In `KitService.lua`, add your kit to the default owned list:

```lua
function KitService:_ensurePlayer(player: Player)
    -- ...
    local owned = { "WhiteBeard", "Genji", "Aki", "Airborne", "HonoredOne", "MyNewKit" }
    -- ...
end
```

---

## Error Codes

| Code | Meaning |
|------|---------|
| `InvalidKit` | Kit ID doesn't exist in KitConfig |
| `AlreadyOwned` | Player already owns this kit |
| `InsufficientFunds` | Not enough gems |
| `NotOwned` | Player doesn't own this kit |
| `NoKitEquipped` | No kit equipped when trying ability |
| `NoCharacter` | Character doesn't exist or isn't loaded |
| `BadAbilityType` | Invalid ability type (not "Ability" or "Ultimate") |
| `MissingKitsFolder` | KitSystem/Kits folder not found |
| `MissingKitModule` | Kit module script not found |
| `BadKitModule` | Kit module failed to load or has wrong format |
| `BadKitInstance` | Kit instance creation failed |
| `BadRequest` | Malformed request payload |
| `BadAction` | Unknown action type |

---

## Best Practices

### Server Side
1. **Always validate** client data — never trust clientData blindly
2. **Use distance checks** to validate positions
3. **Return false** from OnAbility/OnUltimate to reject, true to allow
4. **Use ReplicateVFXAll** for custom VFX events (hits, explosions, etc.)

### Client Side
1. **Start prediction immediately** in OnStart for responsive feel
2. **Handle OnInterrupt** to cancel prediction cleanly
3. **Only call Send()** when you want server execution
4. **Use extraData** to pass aim direction, targets, charge amounts

### VFX
1. **Always check props.position** before using
2. **Use Debris:AddItem** or manual cleanup for spawned effects
3. **Consider all players** — VFX should make sense from any perspective
4. **Pool frequently-used effects** for performance

---

## Debugging

### Enable Debug Prints

The system has built-in debug prints:

```lua
-- KitService
print("[KitService] ActivateAbility", { ... })
print("[KitService] AbilityActivated", { ... })
print("[KitService] AbilityInterrupted", { ... })

-- KitController
print("[KitController] ActivateAbility request", { ... })

-- KitVFXController
print("[KitVFXController] KitState Event", { ... })
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Ability not firing | ClientKit not calling `Send()` | Check OnStart calls `abilityRequest.Send()` |
| VFX not playing | Missing VFX module | Create `VFX/{KitId}.lua` |
| VFX only local | Using wrong position | Use `extraData.position` from server event |
| Cooldown not working | Server kit returning false | Check server kit returns `true` on success |
| Kit not loading | Wrong Module name | Ensure KitConfig.Module matches filename |

---

*Last updated: January 2026*
