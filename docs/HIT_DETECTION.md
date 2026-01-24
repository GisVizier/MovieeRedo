# Hit Detection System

Client-Authoritative Hit Detection with Server Validation, Lag Compensation, and Anti-Cheat.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [How It Works](#how-it-works)
4. [Lag Compensation](#lag-compensation)
5. [Bean Colliders](#bean-colliders)
6. [API Reference](#api-reference)
7. [Configuration](#configuration)
8. [Networking](#networking)
9. [Anti-Cheat](#anti-cheat)
10. [Integration Guide](#integration-guide)
11. [Troubleshooting](#troubleshooting)

---

## Overview

This system provides fair, responsive hit detection for all players regardless of network conditions. It uses:

- **Client-authoritative hits**: Client reports what they hit, server validates
- **Buffer-based networking**: ~35 bytes per shot (vs ~200+ for tables)
- **Position history**: Ring buffer storing 1 second of player positions at 60Hz
- **Ping compensation**: Adaptive rollback based on measured RTT
- **Stance-aware hitboxes**: Different colliders for standing/crouched/sliding

### Key Files

| File | Purpose |
|------|---------|
| `HitDetectionAPI.lua` | Public API facade |
| `HitValidator.lua` | Server-side hit validation |
| `PositionHistory.lua` | Ring buffer position tracking |
| `LatencyTracker.lua` | Ping measurement and rollback |
| `HitPacketUtils.lua` | Packet creation and parsing |
| `Sera/Schemas.lua` | Buffer schemas for networking |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT SIDE                              │
├─────────────────────────────────────────────────────────────────┤
│  Player fires weapon                                             │
│       │                                                          │
│       v                                                          │
│  Raycast against bean collider (Body/Head/CrouchBody/CrouchHead)│
│       │                                                          │
│       v                                                          │
│  HitPacketUtils:CreatePacket(hitData, weaponId)                 │
│       │                                                          │
│       v                                                          │
│  Net:FireServer("WeaponFired", { packet = buffer })             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               v
┌─────────────────────────────────────────────────────────────────┐
│                         SERVER SIDE                              │
├─────────────────────────────────────────────────────────────────┤
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
│       ├─> 4. Position backtracking (ping-compensated)           │
│       ├─> 5. Stance validation (hitbox type matches)            │
│       ├─> 6. Line-of-sight (no walls between)                   │
│       └─> 7. Statistical tracking (anti-cheat)                  │
│                                                                  │
│  If valid: Apply damage, broadcast HitConfirmed                 │
│  If invalid: Log violation, reject hit                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## How It Works

### 1. Client Fires

When the player clicks to fire:

1. Client performs raycast against bean colliders
2. Creates a 35-byte buffer packet with hit info
3. Sends `WeaponFired` event to server

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

---

## Bean Colliders (HitboxService)

### Overview

HitboxService creates invisible hitbox parts under each character for consistent hit detection.
Follows the same pattern as DummyService's collider setup.

### Hitbox Structure

```
Character/
├── Hitbox/              (Folder)
│   ├── Body             (Standing body hitbox)
│   ├── Head             (Standing head hitbox)
│   ├── CrouchBody       (Crouched body hitbox)
│   └── CrouchHead       (Crouched head hitbox)
├── HumanoidRootPart
├── Torso
└── ...
```

### Hitbox Dimensions

| Stance | Part | Size (W x H x D) | Offset from HRP |
|--------|------|------------------|-----------------|
| Standing | Body | 2.5 x 3 x 1.5 | (0, 0, 0) |
| Standing | Head | 1.3 x 1.3 x 1.3 | (0, 2.2, 0) |
| Crouched | Body | 2.8 x 2 x 1.5 | (0, -0.5, 0) |
| Crouched | Head | 1.2 x 1.2 x 1.2 | (0, 1.0, 0) |

### Hitbox Properties

| Property | Value | Purpose |
|----------|-------|---------|
| CanCollide | false | Don't block movement |
| CanQuery | true/false | Toggle for stance |
| CanTouch | false | No touch events |
| Transparency | 1 | Invisible |
| Massless | true | No physics impact |
| CollisionGroup | "Hitboxes" | Separate collision |

### Stance Switching

When crouch state changes:
1. Client sends `CrouchStateChanged` event
2. Server calls `HitboxService:OnCrouchStateChanged()`
3. Active stance beans: `CanQuery = true`
4. Inactive stance beans: `CanQuery = false`

### Raycast Detection

`WeaponRaycast.lua` traverses up from hit part to find character:
- `Character/Hitbox/Part` → Character
- `Dummy/Root/Part` → Dummy

Headshot detection checks part names:
- `Head`, `CrouchHead`, `HitboxHead` → Headshot

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
| `MaxTimestampAge` | 1.0s | Max time in past for hits |
| `RangeTolerance` | 1.2 | 20% extra range allowed |
| `BasePositionTolerance` | 5 studs | Position validation tolerance |
| `BaseHeadTolerance` | 2.5 studs | Headshot validation tolerance |
| `FireRateTolerance` | 0.85 | 15% faster fire allowed |

### PositionHistory Config

| Key | Default | Description |
|-----|---------|-------------|
| `HistorySize` | 60 | Samples stored (1 second at 60Hz) |
| `SampleSize` | 17 bytes | Per-sample storage |
| `MaxInterpolationGap` | 0.1s | Max gap for lerp |

---

## Networking

### Hit Packet Schema (35 bytes)

| Field | Type | Size | Description |
|-------|------|------|-------------|
| Timestamp | Float32 | 4 | When shot was fired |
| Origin | Vector3 | 12 | Shooter position |
| HitPosition | Vector3 | 12 | World hit position |
| TargetUserId | Int32 | 4 | Target player ID (0 = none) |
| HitPart | Uint8 | 1 | 0=None, 1=Body, 2=Head, 3=Limb |
| WeaponId | Uint8 | 1 | Weapon enum |
| TargetStance | Uint8 | 1 | 0=Standing, 1=Crouched, 2=Sliding |

### Shotgun Hit Packet (37 bytes)

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

## Troubleshooting

### "Invalid shot" warnings

Check the reason code:
- `TimestampTooOld`: Player has high latency, increase `MaxTimestampAge`
- `TargetNotAtPosition`: Tolerance too tight, check `BasePositionTolerance`
- `FireRateTooFast`: Client-side fire rate check not matching server

### Hits not registering

1. Check that bean colliders have `CanQuery = true`
2. Verify `CrouchStateChanged` events are being sent
3. Check that position history is being updated (60Hz)

### High latency players

The system automatically adapts:
- Rollback time increases with ping
- Position tolerance scales with ping
- Timestamp tolerance scales with ping

If still issues, consider:
- Increasing `MaxTimestampAge` to 1.5s
- Increasing `BasePositionTolerance` to 7-8 studs

### Debugging

```lua
-- Get full debug info for a player
local api = require(path.to.HitDetectionAPI)

local latency = api:GetLatencyInfo(player)
print("Ping:", latency.Ping, "Jitter:", latency.Jitter)

local stats = api:GetPlayerStats(player)
print("Accuracy:", stats.HitRate * 100, "%")

local pos = api:GetPositionAtTime(player, os.clock() - 0.1)
print("Position 100ms ago:", pos)
```

---

## Memory Usage

| Component | Per Player | Notes |
|-----------|------------|-------|
| PositionHistory | ~1 KB | 60 samples × 17 bytes |
| LatencyTracker | ~40 bytes | 10 samples × 4 bytes |
| PlayerStats | ~50 bytes | Counters and timestamps |

Total: ~1.1 KB per player

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

- **v1.0** - Initial implementation
  - Buffer-based position history
  - Ping-compensated validation
  - Stance-aware hitboxes
  - Statistical anti-cheat
