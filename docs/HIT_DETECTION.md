# Hit Detection System

Client-Authoritative Hit Detection with Server Validation, Lag Compensation, and Anti-Cheat.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [How It Works](#how-it-works)
4. [Lag Compensation](#lag-compensation)
5. [Client-Side Colliders](#client-side-colliders)
6. [API Reference](#api-reference)
7. [Configuration](#configuration)
8. [Networking](#networking)
9. [Anti-Cheat](#anti-cheat)
10. [VFX Replication](#vfx-replication)
11. [Integration Guide](#integration-guide)
12. [Debugging](#debugging)
13. [Troubleshooting](#troubleshooting)

---

## Overview

This system provides fair, responsive hit detection for all players regardless of network conditions. It uses:

- **Client-authoritative hits**: Client reports what they hit, server validates
- **Buffer-based networking**: ~39 bytes per shot (vs ~200+ for tables)
- **Position history**: Ring buffer storing 1 second of player positions at 60Hz
- **Ping compensation**: Adaptive rollback based on measured RTT
- **Stance-aware hitboxes**: Different colliders for standing/crouched/sliding
- **Client-side collider replication**: Each client renders hitboxes for remote players
- **Double-precision timestamps**: f64 timestamps for accurate time synchronization
- **Heartbeat updates**: Position updates every 0.5s even for idle players

### Key Files

| File | Location | Purpose |
|------|----------|---------|
| `HitDetectionAPI.lua` | Server/Services/AntiCheat | Public API facade |
| `HitValidator.lua` | Server/Services/AntiCheat | Server-side hit validation |
| `PositionHistory.lua` | Server/Services/AntiCheat | Ring buffer position tracking |
| `LatencyTracker.lua` | Server/Services/AntiCheat | Ping measurement and rollback |
| `HitPacketUtils.lua` | Shared/Util | Packet creation and parsing |
| `Sera/Schemas.lua` | Shared/Util/Sera | Buffer schemas for networking |
| `CharacterController.lua` | Controllers/Character | Client-side collider replication |
| `WeaponRaycast.lua` | Controllers/Weapon/Services | Raycast against colliders |
| `ClientReplicator.lua` | Game/Replication | Position state broadcasting |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT SIDE                              │
├─────────────────────────────────────────────────────────────────┤
│  CharacterController: Replicates Collider/Hitbox to remote chars│
│       │                                                          │
│       v                                                          │
│  Player fires weapon                                             │
│       │                                                          │
│       v                                                          │
│  WeaponRaycast: Raycast against Collider/Hitbox/Standing|Crouch │
│       │         (identifies target via OwnerUserId attribute)    │
│       v                                                          │
│  HitPacketUtils:CreatePacket(hitData, weaponId)                 │
│       │         (f64 timestamp from GetServerTimeNow)            │
│       v                                                          │
│  Net:FireServer("WeaponFired", { packet = buffer })             │
│       │                                                          │
│       v                                                          │
│  Immediate local effects (muzzle flash, tracer, sound)          │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               v
┌─────────────────────────────────────────────────────────────────┐
│                         SERVER SIDE                              │
├─────────────────────────────────────────────────────────────────┤
│  ReplicationService: Stores position history (f64 timestamps)   │
│       │              Heartbeat updates every 0.5s for idle      │
│       v                                                          │
│  WeaponService receives packet                                   │
│       │                                                          │
│       v                                                          │
│  HitPacketUtils:ParsePacket(buffer) -> hitData                  │
│       │                                                          │
│       v                                                          │
│  HitValidator:ValidateHit(shooter, hitData, weaponConfig)       │
│       │                                                          │
│       ├─> 1. Timestamp validation (not future, not too old)     │
│       ├─> 2. Rate limiting (fire rate check)                    │
│       ├─> 3. Range validation (distance within weapon range)    │
│       ├─> 4. Position backtracking (ping-compensated, stale-aware)│
│       ├─> 5. Head height adjustment (for headshots)             │
│       ├─> 6. Line-of-sight (no walls between)                   │
│       └─> 7. Statistical tracking (anti-cheat)                  │
│                                                                  │
│  If valid: Apply damage, broadcast HitConfirmed                 │
│  If invalid: Log violation (debug mode), reject hit             │
└─────────────────────────────────────────────────────────────────┘
```

---

## How It Works

### 1. Client Fires

When the player clicks to fire:

1. Client raycasts against replicated `Collider/Hitbox` parts on remote characters
2. `WeaponRaycast` identifies target via `OwnerUserId` attribute
3. Creates a 39-byte buffer packet with hit info (f64 timestamp)
4. Sends `WeaponFired` event to server
5. Immediately plays local fire effects (muzzle flash, tracer)

### 2. Server Validates

The server runs these validation layers:

| Layer | Check | Tolerance |
|-------|-------|-----------|
| 1 | Timestamp not in future | -50ms |
| 2 | Timestamp not too old | 500ms-1000ms (ping-scaled) |
| 3 | Fire rate respected | 85% of interval |
| 4 | Distance within range | 120% of weapon range |
| 5 | Target at hit position | 5-15 studs (ping-scaled) |
| 6 | Stance matches claimed | Adjacent stances allowed |
| 7 | Line of sight clear | No walls between |

### 3. Damage Applied

If validation passes:
- Damage calculated (with falloff, headshot multiplier)
- Applied via CombatService
- `HitConfirmed` broadcast to all clients for VFX

---

## Lag Compensation

### Ping Measurement

Server pings each player every 1 second:

```
Server -> PingRequest(token) -> Client
Client -> PingResponse(token) -> Server
RTT = receiveTime - sentTime
```

Rolling average of 10 samples provides stable ping value.

### Rollback Calculation

```lua
rollbackTime = oneWayLatency + (jitter * 2) + processingBuffer
-- Example: 40ms + 20ms + 16ms = 76ms rollback
```

### Position Backtracking

When validating a hit at timestamp T:

1. Get shooter's ping → calculate rollback time
2. Look up target's position in PositionHistory at time T
3. Interpolate between samples for precise positioning
4. Validate hit position is within tolerance of historical position

This means **players hit what they saw on their screen**, even with latency.

### Timestamp Precision

**Critical**: All timestamps use `workspace:GetServerTimeNow()` and are stored as **f64 (double precision)**.

Unix timestamps like `1769236114.283` have 13+ significant digits. Using f32 (7 digits precision) causes:
- Precision loss → incorrect time comparisons
- Negative data age calculations
- False "TimestampTooOld" rejections

**Affected components:**
- `PositionHistory.lua`: Ring buffer stores f64 timestamps (21 bytes/sample)
- `HitPacketUtils.lua`: Packets use `Sera.Float64` for Timestamp field
- `ClientReplicator.lua`: Position updates use `GetServerTimeNow()`
- `WeaponController.lua`: Fire timestamps use `GetServerTimeNow()`

### Idle Player Handling

Delta compression normally skips updates when position hasn't changed.
This causes stale position history for idle players, leading to validation failures.

**Solution**: `ClientReplicator` forces a position update every 0.5 seconds regardless
of whether the player has moved, ensuring fresh position history data.

When position data is stale (> 0.5s old), tolerance automatically scales up to 2x at 2s age.

---

## Client-Side Colliders

### Overview

Hitbox colliders are **replicated to each client** for consistent hit detection.
When a remote player's character spawns, `CharacterController` clones hitbox parts
from the CharacterTemplate and welds them to the remote character.

This approach ensures:
- Client raycasts against actual collider parts (not rig parts)
- Each client sees correct hitbox positions for all players
- Crouch state updates toggle which colliders are queryable

### Hitbox Structure

```
Character/
├── Collider/                (Model - cloned from template)
│   ├── Hitbox/
│   │   ├── Standing/        (Model)
│   │   │   ├── Head         (Ball - standing head hitbox)
│   │   │   ├── Body         (Cylinder - standing body hitbox)
│   │   │   └── Feet         (Ball - standing feet hitbox)
│   │   └── Crouching/       (Model)
│   │       ├── Head         (Ball - crouched head hitbox)
│   │       └── Body         (Ball - crouched body hitbox)
│   ├── Default/             (Original collision shapes)
│   ├── Crouch/              (Crouch collision shapes)
│   └── UncrouchCheck/       (Uncrouch clearance check)
├── Root
├── Rig/
│   └── HumanoidRootPart
└── ...
```

### Key Properties

| Property | Standing | Crouching | Purpose |
|----------|----------|-----------|---------|
| CanCollide | false | false | Don't block movement |
| CanQuery | true | false | Active stance queryable |
| CanTouch | false | false | No touch events |
| Transparency | 1 (or 0.5 debug) | 1 (or 0.5 debug) | Invisible/Debug |
| Massless | true | true | No physics impact |

### Collider Replication Flow

1. **Remote character spawns** → `CharacterController:_onCharacterAdded()`
2. **Clone Collider model** from CharacterTemplate
3. **Set OwnerUserId attribute** on Collider (for raycast identification)
4. **Weld all hitbox parts** to character's Root using WeldConstraint
5. **Set initial CanQuery state** (Standing = true, Crouching = false)
6. **Parent Collider** to character

### Stance Switching

When crouch state changes:

```
Client A crouches
    │
    v
Net:FireServer("CrouchStateChanged", true)
    │
    v
Server broadcasts to all clients
    │
    v
Each client's CharacterController:_setRemoteColliderCrouch(character, true)
    │
    v
Standing parts: CanQuery = false
Crouching parts: CanQuery = true
```

### Raycast Detection

`WeaponRaycast:getCharacterFromPart(part)`:

1. Check if part is inside a `Collider` model
2. Get `OwnerUserId` attribute from Collider
3. Look up player by UserId (handles negative IDs for test clients)
4. Return player's character

Headshot detection checks part names:
- `Head` in any folder → Headshot
- All other parts → Body shot

### Debug Visualization

Press **F4** to toggle hitbox debug mode:
- **Red parts**: Standing hitboxes (active when not crouched)
- **Blue parts**: Crouching hitboxes (active when crouched)
- **Gray parts**: Inactive hitboxes
- **Transparency**: 0.5 (visible for debugging)
- **Material**: ForceField (distinctive appearance)

---

## API Reference

### HitDetectionAPI

```lua
local HitDetectionAPI = require(path.to.HitDetectionAPI)
```

#### Initialization

```lua
HitDetectionAPI:Init(net)
```

#### Hit Validation

```lua
-- Validate a hit
local valid, reason = HitDetectionAPI:ValidateHit(shooter, hitData, weaponConfig)

-- Store position (called by ReplicationService)
HitDetectionAPI:StorePosition(player, position, timestamp, stance)

-- Update stance (called when crouch changes)
HitDetectionAPI:SetPlayerStance(player, stance)
```

#### Latency Queries

```lua
-- Get ping in milliseconds
local ping = HitDetectionAPI:GetPlayerPing(player)

-- Get jitter (variance)
local jitter = HitDetectionAPI:GetPlayerJitter(player)

-- Get rollback time in seconds
local rollback = HitDetectionAPI:GetRollbackTime(player)

-- Get adaptive tolerances
local tolerances = HitDetectionAPI:GetAdaptiveTolerances(player)
-- Returns: { PositionTolerance, HeadTolerance, TimestampTolerance }

-- Get full latency debug info
local info = HitDetectionAPI:GetLatencyInfo(player)
-- Returns: { Ping, Jitter, Samples, RollbackTime, Tolerances }
```

#### Position History Queries

```lua
-- Get position at timestamp
local pos = HitDetectionAPI:GetPositionAtTime(player, timestamp)

-- Get stance at timestamp
local stance = HitDetectionAPI:GetStanceAtTime(player, timestamp)
local stanceName = HitDetectionAPI:GetStanceNameAtTime(player, timestamp)

-- Get both
local pos, stance = HitDetectionAPI:GetStateAtTime(player, timestamp)

-- Get time range of history
local oldest, newest = HitDetectionAPI:GetHistoryTimeRange(player)
```

#### Statistics & Anti-Cheat

```lua
-- Get player stats
local stats = HitDetectionAPI:GetPlayerStats(player)
-- Returns: { TotalShots, Hits, Headshots, HitRate, HeadshotRate, SessionDuration }

-- Get flagged players
local flagged = HitDetectionAPI:GetFlaggedPlayers()
-- Returns: { { player, reason, timestamp, value }, ... }

-- Clear flag
HitDetectionAPI:ClearPlayerFlag(player)

-- Reset stats
HitDetectionAPI:ResetPlayerStats(player)
```

#### Constants

```lua
-- Stance enum
HitDetectionAPI.Stance.Standing  -- 0
HitDetectionAPI.Stance.Crouched  -- 1
HitDetectionAPI.Stance.Sliding   -- 2
```

### HitPacketUtils

```lua
local HitPacketUtils = require(path.to.HitPacketUtils)
```

#### Client-Side (Creating Packets)

```lua
-- Create standard hit packet
local packet = HitPacketUtils:CreatePacket(hitData, "Sniper")

-- Create shotgun packet (includes pellet info)
local packet = HitPacketUtils:CreateShotgunPacket(hitData, "Shotgun")
```

#### Server-Side (Parsing Packets)

```lua
-- Parse standard packet
local hitData = HitPacketUtils:ParsePacket(packetString)

-- Parse shotgun packet
local hitData = HitPacketUtils:ParseShotgunPacket(packetString)

-- Check packet type
local isShotgun = HitPacketUtils:IsShotgunPacket(packetString)
```

---

## Configuration

### LatencyTracker Config

| Key | Default | Description |
|-----|---------|-------------|
| `PingIntervalSeconds` | 1.0 | How often to ping players |
| `SampleCount` | 10 | Rolling average sample count |
| `MaxPingMs` | 500 | Reject pings above this |
| `MinPingMs` | 5 | Reject pings below this |
| `DefaultPingMs` | 80 | Assumed ping before measurement |

### HitValidator Config

| Key | Default | Description |
|-----|---------|-------------|
| `DebugLogging` | true | Enable detailed validation logging |
| `MaxTimestampAge` | 1.0s | Max time in past for hits |
| `MaxRollbackTime` | 1.0s | Never rollback more than this |
| `MinTimestampAge` | -0.1s | Small tolerance for processing delay |
| `RangeTolerance` | 1.2 | 20% extra range allowed |
| `BasePositionTolerance` | 5 studs | Position validation tolerance |
| `BaseHeadTolerance` | 3.5 studs | Headshot validation tolerance |
| `HeadHeightOffset` | 2.5 studs | Vertical offset for head position |
| `FireRateTolerance` | 0.85 | 15% faster fire allowed |
| `MinShotsForAnalysis` | 50 | Shots before flagging accuracy |
| `SuspiciousHitRate` | 0.95 | 95%+ accuracy triggers flag |
| `SuspiciousHeadshotRate` | 0.80 | 80%+ headshot rate triggers flag |

### PositionHistory Config

| Key | Default | Description |
|-----|---------|-------------|
| `HistorySize` | 60 | Samples stored (1 second at 60Hz) |
| `SampleSize` | 21 bytes | Per-sample storage (8 bytes f64 timestamp) |
| `MaxInterpolationGap` | 0.1s | Max gap for lerp |

---

## Networking

### Hit Packet Schema (39 bytes)

| Field | Type | Size | Description |
|-------|------|------|-------------|
| Timestamp | Float64 | 8 | When shot was fired (double precision for Unix timestamps) |
| Origin | Vector3 | 12 | Shooter position |
| HitPosition | Vector3 | 12 | World hit position |
| TargetUserId | Int32 | 4 | Target player ID (0 = none) |
| HitPart | Uint8 | 1 | 0=None, 1=Body, 2=Head, 3=Limb |
| WeaponId | Uint8 | 1 | Weapon enum |
| TargetStance | Uint8 | 1 | 0=Standing, 1=Crouched, 2=Sliding |

### Shotgun Hit Packet (41 bytes)

Same as above, plus:

| Field | Type | Size | Description |
|-------|------|------|-------------|
| PelletHits | Uint8 | 1 | Pellets that hit target |
| HeadshotPellets | Uint8 | 1 | Pellets that were headshots |

### Remote Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `WeaponFired` | Client → Server | Hit packet for validation |
| `HitConfirmed` | Server → All | Validated hit for VFX |
| `PingRequest` | Server → Client | Ping challenge |
| `PingResponse` | Client → Server | Ping response |

---

## Anti-Cheat

### Validation Rejections

| Reason | Description |
|--------|-------------|
| `TimestampInFuture` | Hit claims to be in the future |
| `TimestampTooOld` | Hit is too far in the past |
| `FireRateTooFast` | Firing faster than weapon allows |
| `OutOfRange` | Hit distance exceeds weapon range |
| `TargetNotAtPosition` | Target wasn't near claimed hit position |
| `StanceMismatch` | Claimed stance doesn't match server record |
| `LineOfSightBlocked` | Wall between shooter and target |

### Statistical Tracking

Server tracks per-player:
- Total shots fired
- Hits registered
- Headshots
- Session duration

Flags raised when:
- Hit rate > 95% (over 50+ shots)
- Headshot rate > 80% (over 20+ headshots)

Flagged players are logged for admin review. Future: automatic action.

---

## VFX Replication

### Overview

The `VFXRep` module handles visual effects replication between clients.

### Target Specifiers

| Target | Behavior |
|--------|----------|
| `"Me"` | **Local execution only** - no network round-trip |
| `"Others"` | All players except sender |
| `"All"` | All players including sender |
| `{ Players = {...} }` | Specific player list |
| `{ UserIds = {...} }` | Specific user IDs |

### Optimized Local Effects

When `targetSpec == "Me"`, effects execute **immediately** on the client without
any server round-trip. This eliminates latency for self-targeted effects like:

- Kit abilities (Cloudskip, etc.)
- Personal VFX
- Viewmodel effects

```lua
-- This executes INSTANTLY (no network)
VFXRep:Fire("Me", { Module = "Cloudskip", Function = "User" }, {
    position = hrp.Position,
    Action = "upDraft",
})

-- This goes through server for replication to others
VFXRep:Fire("All", { Module = "Slide" }, { state = "Start" })
```

### Usage

```lua
local VFXRep = require(Locations.Game.Replication.ReplicationModules)

-- Initialize (client-side)
VFXRep:Init(net, false)

-- Fire effect
VFXRep:Fire(targetSpec, {
    Module = "ModuleName",      -- VFX module name
    Function = "FunctionName",  -- Function to call (default: "Execute")
}, {
    -- Data passed to the VFX function
    position = Vector3.new(...),
    -- ...
})
```

---

## Integration Guide

### Adding a New Weapon

1. Add weapon to `LoadoutConfig.lua`:
```lua
NewWeapon = {
    id = "NewWeapon",
    damage = 30,
    range = 200,
    fireRate = 400,
    headshotMultiplier = 1.5,
    -- ...
}
```

2. Add weapon ID to `Sera/Schemas.lua`:
```lua
WeaponId = {
    -- ...
    NewWeapon = 7,
}
```

3. Create `Attack.lua` in `Actions/Gun/NewWeapon/`:
```lua
local HitPacketUtils = require(...)

function Attack.Execute(weaponInstance, currentTime)
    -- ... checks ...
    local hitData = weaponInstance.PerformRaycast()
    hitData.timestamp = currentTime
    
    local packet = HitPacketUtils:CreatePacket(hitData, weaponInstance.WeaponName)
    weaponInstance.Net:FireServer("WeaponFired", {
        packet = packet,
        weaponId = weaponInstance.WeaponName,
    })
    -- ...
end
```

### Customizing Validation

To add custom validation, modify `HitValidator:ValidateHit()`:

```lua
function HitValidator:ValidateHit(shooter, hitData, weaponConfig)
    -- ... existing checks ...
    
    -- Add custom check
    local valid, reason = self:_validateCustomRule(hitData)
    if not valid then
        return false, reason
    end
    
    return true, "Valid"
end
```

---

## Debugging

### Server Debug Logging

Enable detailed hit validation logging in `HitValidator.lua`:

```lua
local CONFIG = {
    DebugLogging = true,  -- Set to true for verbose output
    -- ...
}
```

This outputs for each hit:
- Client hit position vs server history position
- Adjusted position (with head offset for headshots)
- Offset distance and tolerance
- Data age and staleness factor
- Final result (VALID ✓ or REJECTED ✗)

Example output:
```
[HitValidator DEBUG] Player1 -> Player2:
  Client hitPos: (10.0, 15.0, 20.0)
  History pos:   (10.2, 12.5, 20.1)
  Adjusted pos:  (10.2, 15.0, 20.1) [+head offset]
  Offset: 0.14 studs | Tolerance: 7.50 (base=3.5 * ping=1.50 * stale=1.43)
  Data age: 0.715s | Headshot: true
  RESULT: VALID ✓
```

### Client Debug Logging

Enable in `WeaponRaycast.lua`:

```lua
local DEBUG_LOGGING = true
```

This outputs:
- Target player and hit part
- Hit position and origin
- Whether it's a headshot
- Timestamp used

### Hitbox Visualization

Press **F4** in-game to toggle hitbox debug mode:

- **Red**: Standing hitboxes (active)
- **Blue**: Crouching hitboxes (active when crouched)
- **Gray**: Inactive hitboxes
- **Transparency**: 0.5
- **Material**: ForceField

### Common Debug Checks

1. **Check collider exists**: Look for `Character/Collider/Hitbox/Standing|Crouching`
2. **Check CanQuery**: Active stance should have `CanQuery = true`
3. **Check OwnerUserId**: Collider should have attribute matching player's UserId
4. **Check position history**: Server should show "History samples: YES"

---

## Troubleshooting

### "Invalid shot" warnings

| Reason | Cause | Solution |
|--------|-------|----------|
| `TimestampTooOld` | High latency or stale data | Check heartbeat updates, increase `MaxTimestampAge` |
| `TimestampInFuture` | Clock desync | Should be rare with `GetServerTimeNow()` |
| `TargetNotAtPosition` | Position mismatch | Check position history freshness, increase tolerance |
| `FireRateTooFast` | Client firing too fast | Check weapon fire rate config |

### Hits not registering (no target)

1. **Check colliders exist**: Verify `Collider` model on remote characters
2. **Check CanQuery state**: Active stance parts should be queryable
3. **Check OwnerUserId**: Attribute must be set on Collider model
4. **Check raycast filter**: Ensure filter doesn't exclude colliders

### Headshots not registering

1. **Check HeadHeightOffset**: Default is 2.5 studs above root
2. **Check BaseHeadTolerance**: Default is 3.5 studs
3. Enable debug logging to see offset vs tolerance

### Idle players failing validation

This was caused by delta compression stopping updates for stationary players.

**Solution implemented**: ClientReplicator sends heartbeat updates every 0.5s
even if position hasn't changed, ensuring fresh position history data.

If still occurring, check:
- `ClientReplicator.lua` has `LastForcedUpdateTime` tracking
- Position updates fire every 0.5s regardless of movement

### Stale position history

When position data is older than expected, tolerance automatically scales:
- Data age > 0.5s: tolerance increases proportionally
- Data age > 2s: tolerance capped at 2x base

### High latency players

The system automatically adapts:
- Rollback time increases with ping
- Position tolerance scales: `base * (1 + (shooterPing + targetPing) / 400)`
- Maximum ping factor capped at 2.0

For extreme latency (300ms+):
- Increase `MaxTimestampAge` to 1.5s
- Increase `BasePositionTolerance` to 7-8 studs

### Test clients (negative UserIDs)

Studio test clients use negative UserIDs (-1, -2, etc.).

The system handles this via:
- `HitPacketUtils:ParsePacket()` checks `UserId ~= 0` (not `> 0`)
- Fallback to `Players:GetPlayers()` loop if `GetPlayerByUserId` fails

### API Debugging

```lua
local api = require(path.to.HitDetectionAPI)

-- Get latency info
local latency = api:GetLatencyInfo(player)
print("Ping:", latency.Ping, "Jitter:", latency.Jitter)

-- Get position history range
local oldest, newest = api:GetHistoryTimeRange(player)
print("History from", oldest, "to", newest)

-- Get position at specific time
local pos = api:GetPositionAtTime(player, workspace:GetServerTimeNow() - 0.1)
print("Position 100ms ago:", pos)

-- Get player stats
local stats = api:GetPlayerStats(player)
print("Accuracy:", stats.HitRate * 100, "%")
```

---

## Memory Usage

| Component | Per Player | Notes |
|-----------|------------|-------|
| PositionHistory | ~1.3 KB | 60 samples × 21 bytes |
| LatencyTracker | ~40 bytes | 10 samples × 4 bytes |
| PlayerStats | ~50 bytes | Counters and timestamps |

Total: ~1.4 KB per player

---

## Performance

| Operation | Cost | Notes |
|-----------|------|-------|
| Store position | O(1) | Ring buffer write |
| Get position at time | O(n) | Linear search, n ≤ 60 |
| Ping measurement | 1 packet/sec | Unreliable event |
| Hit validation | O(1) | Fixed checks |
| Packet serialization | ~5 μs | Buffer operations |

---

## Version History

- **v1.2** - VFX & Polish
  - VFXRep "Me" optimization (local execution, no network round-trip)
  - Server and client debug logging toggles
  - Improved documentation

- **v1.1** - Precision & Reliability
  - **f64 timestamps**: Changed from f32 to f64 for Unix timestamp precision
  - **Client-side collider replication**: Hitboxes now replicated to each client
  - **Heartbeat updates**: Position updates every 0.5s even for idle players
  - **Stale data tolerance**: Tolerance scales with position data age
  - **Head height offset**: Proper vertical adjustment for headshot validation
  - **Test client support**: Handles negative UserIDs in Studio
  - **F4 hitbox debug**: Visual debugging for colliders
  - **Crouch state fixes**: Proper state management after sliding/jumping

- **v1.0** - Initial implementation
  - Buffer-based position history
  - Ping-compensated validation
  - Stance-aware hitboxes
  - Statistical anti-cheat
