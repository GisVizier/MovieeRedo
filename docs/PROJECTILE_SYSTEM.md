# Projectile System

Hybrid Client-Authoritative Projectile System with CFrame-Based Physics, Server Validation, and Lag Compensation.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [How It Works](#how-it-works)
4. [Physics System](#physics-system)
5. [Spread System](#spread-system)
6. [Projectile Types](#projectile-types)
7. [Configuration](#configuration)
8. [Networking](#networking)
9. [Validation](#validation)
10. [API Reference](#api-reference)
11. [Integration Guide](#integration-guide)
12. [Debugging](#debugging)
13. [Troubleshooting](#troubleshooting)

---

## Overview

This system provides physics-based projectile simulation for weapons that require travel time, gravity, and ballistic behavior. It integrates with the existing Hit Detection system for validation and lag compensation.

### Key Features

- **Hybrid authority**: Client predicts trajectory and hit, server validates
- **CFrame-based physics**: Smooth trajectory calculation using CFrame math
- **Configurable per-weapon**: Speed, gravity, drag, spread all in LoadoutConfig
- **Crosshair alignment**: Projectile spread matches visual crosshair expansion
- **Multiple projectile types**: Ballistic, AoE, Pierce, Ricochet
- **Lag compensation**: Uses existing PositionHistory for target validation
- **Visual replication**: All clients see projectiles via VFX system

### When to Use Projectiles vs Hitscan

| Use Projectiles | Use Hitscan |
|-----------------|-------------|
| Bows, crossbows | Sniper rifles (optional) |
| Rockets, grenades | Assault rifles |
| Slow-moving bullets | SMGs, pistols |
| Anything with visible travel time | Fast/instant weapons |

### Key Files (Planned)

| File | Location | Purpose |
|------|----------|---------|
| `ProjectileAPI.lua` | Server/Services/Combat | Public API facade |
| `ProjectileValidator.lua` | Server/Services/Combat | Server-side validation |
| `ProjectileController.lua` | Controllers/Weapon | Client-side simulation |
| `ProjectilePhysics.lua` | Shared/Util | CFrame trajectory math |
| `ProjectilePacketUtils.lua` | Shared/Util | Packet creation/parsing |
| `ProjectileVFX.lua` | Game/Replication/VFXModules | Visual effects |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           CLIENT SIDE                                │
├─────────────────────────────────────────────────────────────────────┤
│  Player fires weapon                                                 │
│       │                                                              │
│       v                                                              │
│  WeaponController: Check ammo, cooldowns, state                      │
│       │                                                              │
│       v                                                              │
│  ProjectileController:                                               │
│    1. Calculate spread (aligned with crosshair)                      │
│    2. Get initial direction from camera                              │
│    3. Spawn local visual projectile                                  │
│    4. Start physics simulation                                       │
│       │                                                              │
│       v                                                              │
│  ProjectilePhysics: CFrame-based trajectory simulation               │
│    - Apply gravity, drag each frame                                  │
│    - Raycast segment each step for collision                         │
│    - Check against Collider/Hitbox (same as hitscan)                │
│       │                                                              │
│       v                                                              │
│  On predicted hit:                                                   │
│    1. Calculate impact timestamp (fireTime + flightTime)             │
│    2. Create ProjectilePacket with hit data                          │
│    3. Send to server for validation                                  │
│    4. Play local impact effects immediately                          │
│       │                                                              │
│       v                                                              │
│  Net:FireServer("ProjectileFired", { packet = buffer })             │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               v
┌─────────────────────────────────────────────────────────────────────┐
│                           SERVER SIDE                                │
├─────────────────────────────────────────────────────────────────────┤
│  ProjectileService receives packet                                   │
│       │                                                              │
│       v                                                              │
│  ProjectilePacketUtils:ParsePacket(buffer) -> projectileData        │
│       │                                                              │
│       v                                                              │
│  ProjectileValidator:ValidateHit(shooter, projectileData, config)   │
│       │                                                              │
│       ├─> 1. Fire timestamp validation (not future, not too old)    │
│       ├─> 2. Recalculate expected flight time                       │
│       ├─> 3. Compute expected impact timestamp                      │
│       ├─> 4. Get target position at impact time (PositionHistory)   │
│       ├─> 5. Validate hit position vs historical position           │
│       ├─> 6. Line-of-sight at fire time                             │
│       ├─> 7. Trajectory obstruction check (no walls in path)        │
│       └─> 8. Statistical tracking (anti-cheat)                      │
│                                                                      │
│  If valid: Apply damage, broadcast ProjectileHitConfirmed           │
│  If invalid: Log violation, reject hit                              │
└─────────────────────────────────────────────────────────────────────┘
```

### Visual Replication Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Shooter       │     │     Server      │     │  Other Clients  │
│   (Client A)    │     │                 │     │   (Client B,C)  │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         │ Fire projectile       │                       │
         │ (local visual)        │                       │
         │──────────────────────>│                       │
         │   ProjectileFired     │                       │
         │                       │──────────────────────>│
         │                       │  ProjectileSpawned    │
         │                       │  (origin, direction,  │
         │                       │   speed, visual type) │
         │                       │                       │
         │                       │                       │ Spawn visual
         │                       │                       │ projectile
         │                       │                       │
         │ Hit detected          │                       │
         │──────────────────────>│                       │
         │   ProjectileHit       │                       │
         │                       │                       │
         │                       │ Validate...           │
         │                       │                       │
         │<──────────────────────│──────────────────────>│
         │  HitConfirmed         │  HitConfirmed         │
         │                       │                       │
         ▼                       ▼                       ▼
    Impact VFX              Apply Damage           Impact VFX
```

---

## How It Works

### 1. Client Fires Projectile

When the player clicks to fire a projectile weapon:

1. **WeaponController** checks ammo, cooldowns, and weapon state
2. **ProjectileController** calculates spread direction (aligned with crosshair)
3. Spawns a **local visual projectile** immediately (for responsiveness)
4. Begins **physics simulation** using CFrame math
5. Sends **ProjectileSpawned** event to server (for replication to others)

### 2. Physics Simulation

Each frame, the projectile:

1. Updates velocity with gravity and drag
2. Calculates next position using CFrame
3. Raycasts from current to next position
4. Checks for collision with:
   - `Collider/Hitbox` parts (players)
   - Environment (walls, floor, etc.)

### 3. Hit Detection

When projectile collides:

| Target | Behavior |
|--------|----------|
| Player Hitbox | Extract target from `OwnerUserId`, create hit packet |
| Environment | Trigger impact VFX, destroy projectile |
| Nothing (timeout) | Destroy projectile after `lifetime` seconds |

### 4. Server Validates

The server runs these validation layers:

| Layer | Check | Tolerance |
|-------|-------|-----------|
| 1 | Fire timestamp not in future | -50ms |
| 2 | Fire timestamp not too old | 500ms-1500ms (ping-scaled) |
| 3 | Recalculate flight time | ±10% of claimed time |
| 4 | Target at impact position | 5-20 studs (ping + flight time scaled) |
| 5 | Trajectory not obstructed | Raycast fire → impact |
| 6 | Fire rate respected | 85% of interval |

### 5. Damage Applied

If validation passes:
- Damage calculated (with headshot multiplier if applicable)
- Applied via CombatService
- `ProjectileHitConfirmed` broadcast to all clients for impact VFX

---

## Physics System

### CFrame-Based Trajectory

Projectiles use CFrame math for smooth, predictable trajectories:

```lua
-- Initial state
local position = origin
local velocity = direction * config.projectile.speed
local gravity = Vector3.new(0, -config.projectile.gravity, 0)
local drag = config.projectile.drag

-- Each frame update
function UpdateProjectile(dt)
    -- Apply drag (air resistance)
    velocity = velocity * (1 - drag * dt)
    
    -- Apply gravity
    velocity = velocity + gravity * dt
    
    -- Calculate next position
    local nextPosition = position + velocity * dt
    
    -- Raycast for collision
    local rayResult = workspace:Raycast(position, nextPosition - position, raycastParams)
    
    if rayResult then
        -- Hit something
        OnProjectileHit(rayResult)
    else
        -- Continue flight
        position = nextPosition
        UpdateVisual(position, velocity)
    end
end
```

### Gravity and Arc

Gravity creates the characteristic arc of projectiles:

```
        Fire Direction
             ╱
            ╱
           ╱
          ●───────╲
         ╱         ╲
        ╱           ╲         ← Gravity pulls down
       ╱             ╲
      ╱               ╲
     ╱                 ●      ← Impact point
    ▼
  Start
```

**Configuration:**
```lua
gravity = 196.2,  -- Roblox default (workspace.Gravity)
-- Higher = more drop, steeper arc
-- Lower = flatter trajectory
-- 0 = straight line (rockets)
```

### Drag (Air Resistance)

Drag slows projectiles over distance:

```lua
drag = 0,      -- No drag (maintains speed)
drag = 0.1,    -- Light drag (bullets)
drag = 0.3,    -- Medium drag (arrows)
drag = 0.5,    -- Heavy drag (thrown objects)
```

**Effect:**
```
Speed over time (drag = 0.1):
500 ────╲
        ╲
         ╲
          ╲────────────── 350 studs/sec at max range
```

### Velocity Inheritance

Projectiles can inherit shooter's velocity:

```lua
inheritVelocity = 0,    -- Projectile ignores shooter movement
inheritVelocity = 0.5,  -- 50% of shooter velocity added
inheritVelocity = 1.0,  -- Full velocity inheritance
```

**Use case:** Running and shooting - bullets go slightly in movement direction.

### Flight Time Calculation

Server recalculates expected flight time for validation:

```lua
function CalculateFlightTime(origin, hitPosition, config)
    local distance = (hitPosition - origin).Magnitude
    local speed = config.projectile.speed
    local gravity = config.projectile.gravity
    
    -- Simple estimate (no drag, small angle approximation)
    -- For accurate: use iterative simulation or quadratic formula
    local horizontalDistance = Vector3.new(hitPosition.X - origin.X, 0, hitPosition.Z - origin.Z).Magnitude
    local baseTime = horizontalDistance / speed
    
    -- Account for vertical component
    local verticalDelta = hitPosition.Y - origin.Y
    local gravityTime = math.sqrt(2 * math.abs(verticalDelta) / gravity)
    
    return baseTime + gravityTime * 0.5  -- Weighted average
end
```

---

## Spread System

### Overview

Projectile spread determines accuracy. The system supports three modes that work **alongside the existing crosshair system**.

### Spread Modes

#### 1. Cone (Random Spread)

Each shot's direction is randomly offset within a cone angle:

```
        Fire Direction
             │
             │    ← Spread Angle
            /│\
           / │ \
          /  │  \
         /   │   \
        ●────┼────●   ← Projectiles land randomly in cone
            │
```

**Config:**
```lua
spreadMode = "Cone",
baseSpread = 0.02,  -- radians
```

**Use cases:** Assault rifles, SMGs, pistols

#### 2. Pattern (Fixed Spread)

Pellets follow a predetermined pattern - same every shot:

```
        ●       ●       ●
           ●       ●
        ●     ●●●     ●      ← Fixed positions
           ●       ●
        ●       ●       ●
```

**Config:**
```lua
spreadMode = "Pattern",
spreadPattern = {
    {0, 0},           -- Center
    {0.05, 0},        -- Right
    {-0.05, 0},       -- Left
    {0, 0.05},        -- Up
    {0, -0.05},       -- Down
    {0.035, 0.035},   -- Diagonals...
    {-0.035, 0.035},
    {0.035, -0.035},
    {-0.035, -0.035},
},
-- OR use preset
spreadPattern = "Circle8",
```

**Use cases:** Shotguns, multi-projectile weapons

#### 3. None (Perfect Accuracy)

Zero spread - projectile goes exactly where aimed:

```
        Crosshair
            │
            │
            │
            ●   ← Always hits exact center
```

**Config:**
```lua
spreadMode = "None",
```

**Use cases:** Sniper rifles (scoped), fully-charged bows, lasers

### Crosshair Alignment

The projectile system reads the **same state** as the crosshair to ensure bullets land within visual bounds.

**Existing crosshair calculation (unchanged):**
```lua
-- From CrosshairController
local spreadAmount = velocitySpread + currentRecoil
local spreadX = weaponData.spreadX * spreadAmount * 4
local spreadY = weaponData.spreadY * spreadAmount * 4
```

**Projectile spread calculation:**
```lua
-- ProjectileController reads same values
local spreadAmount = GetCurrentSpreadAmount()  -- Same as crosshair
local crosshairSpread = weaponConfig.crosshair.spreadX * spreadAmount

-- Convert to angle using alignment scale
local actualSpreadAngle = weaponConfig.projectile.baseSpread + 
    (crosshairSpread * weaponConfig.projectile.crosshairSpreadScale)

-- Apply to projectile direction
local offsetX = (math.random() - 0.5) * 2 * actualSpreadAngle
local offsetY = (math.random() - 0.5) * 2 * actualSpreadAngle
local spreadDirection = aimCFrame * CFrame.Angles(offsetY, offsetX, 0)
```

### Spread Modifiers

Spread increases/decreases based on player state:

| State | Multiplier | Effect |
|-------|------------|--------|
| Standing still | 1.0x | Base accuracy |
| Moving | `movementSpreadMult` | Less accurate |
| Hipfire (not ADS) | `hipfireSpreadMult` | Less accurate |
| In air | `airSpreadMult` | Much less accurate |
| Crouching | `crouchSpreadMult` | More accurate |
| Sliding | `slideSpreadMult` | Slightly more accurate |

**Combined calculation:**
```lua
local finalSpread = baseSpread
if isMoving then finalSpread = finalSpread * movementSpreadMult end
if not isADS then finalSpread = finalSpread * hipfireSpreadMult end
if inAir then finalSpread = finalSpread * airSpreadMult end
if isCrouching then finalSpread = finalSpread * crouchSpreadMult end
```

---

## Projectile Types

### Ballistic (Default)

Standard projectiles affected by gravity.

```lua
projectile = {
    speed = 300,
    gravity = 196.2,
    drag = 0.1,
    pierce = 0,
    ricochet = 0,
    aoe = nil,
}
```

**Examples:** Arrows, slow bullets, crossbow bolts

### Pierce

Projectile passes through targets, hitting multiple enemies.

```lua
projectile = {
    pierce = 3,                -- Max 3 targets
    pierceDamageMult = 0.8,    -- 80% damage per subsequent hit
}
```

**Behavior:**
1. Hit target 1 → 100% damage
2. Continue through → Hit target 2 → 80% damage
3. Continue through → Hit target 3 → 64% damage
4. Despawn after 3 hits

### Ricochet

Projectile bounces off surfaces.

```lua
projectile = {
    ricochet = 2,              -- Max 2 bounces
    ricochetDamageMult = 0.7,  -- 70% damage after each bounce
    ricochetSpeedMult = 0.9,   -- 90% speed retained
}
```

**Behavior:**
1. Hit wall → Reflect direction, reduce damage/speed
2. Hit wall again → Reflect, reduce again
3. Hit target OR third surface → Final impact

**Reflection calculation:**
```lua
local normal = rayResult.Normal
local reflected = velocity - 2 * velocity:Dot(normal) * normal
velocity = reflected * ricochetSpeedMult
```

### AoE (Area of Effect)

Projectile explodes on impact, damaging all targets in radius.

```lua
projectile = {
    aoe = {
        radius = 15,           -- Explosion radius (studs)
        falloff = true,        -- Damage decreases from center
        falloffMin = 0.25,     -- 25% damage at edge
        friendlyFire = false,  -- Damage teammates?
        knockback = 50,        -- Push force
    },
}
```

**Damage calculation:**
```lua
local distance = (targetPosition - explosionCenter).Magnitude
local falloffFactor = 1 - (distance / radius) * (1 - falloffMin)
local finalDamage = baseDamage * math.max(falloffFactor, falloffMin)
```

**Examples:** Rockets, grenades, explosive arrows

### Charge (Wind-up)

Projectile properties scale with charge time.

```lua
projectile = {
    charge = {
        minTime = 0.2,         -- Minimum hold to fire
        maxTime = 1.5,         -- Full charge time
        minDamageMult = 0.5,   -- 50% damage at min charge
        maxDamageMult = 1.5,   -- 150% damage at full charge
        minSpeedMult = 0.6,    -- 60% speed at min charge
        maxSpeedMult = 1.2,    -- 120% speed at full charge
        minSpreadMult = 2.0,   -- 2x spread at min charge
        maxSpreadMult = 0.5,   -- 0.5x spread at full charge (more accurate)
    },
}
```

**Charge interpolation:**
```lua
local chargePercent = math.clamp((holdTime - minTime) / (maxTime - minTime), 0, 1)
local damageMult = Lerp(minDamageMult, maxDamageMult, chargePercent)
local speedMult = Lerp(minSpeedMult, maxSpeedMult, chargePercent)
local spreadMult = Lerp(minSpreadMult, maxSpreadMult, chargePercent)
```

**Examples:** Bows, charged energy weapons

---

## Configuration

### LoadoutConfig Structure

Projectile configuration lives inside each weapon's config in `LoadoutConfig.lua`:

```lua
Bow = {
    id = "Bow",
    name = "Bow",
    description = "Precision bow with charged shots.",
    imageId = "rbxassetid://...",
    weaponType = "Primary",
    rarity = "Rare",
    
    -- Existing fields (unchanged)
    maxAmmo = 30,
    clipSize = 1,
    reloadTime = 0.5,
    fireProfile = {
        mode = "Charge",
        autoReloadOnEmpty = true,
    },
    
    damage = 60,
    headshotMultiplier = 2.0,
    range = 400,
    fireRate = 60,
    
    -- Existing crosshair config (unchanged)
    crosshair = {
        type = "Bow",
        spreadX = 0.6,
        spreadY = 0.6,
        recoilMultiplier = 1.0,
    },
    
    -- NEW: Projectile configuration
    projectile = {
        -- Core physics
        speed = 250,              -- studs/second (base, affected by charge)
        gravity = 196.2,          -- gravity strength
        drag = 0.05,              -- air resistance
        lifetime = 5,             -- max seconds before despawn
        inheritVelocity = 0,      -- shooter velocity transfer (0-1)
        
        -- Spread
        spreadMode = "Cone",      -- "Cone" | "Pattern" | "None"
        baseSpread = 0.01,        -- base spread angle (radians)
        crosshairSpreadScale = 0.01,  -- alignment with crosshair visual
        movementSpreadMult = 1.3,
        hipfireSpreadMult = 1.5,
        airSpreadMult = 2.0,
        crouchSpreadMult = 0.8,
        slideSpreadMult = 1.0,
        
        -- Behaviors
        pierce = 0,               -- max targets (0 = single hit)
        pierceDamageMult = 1.0,   -- damage multiplier per pierce
        
        ricochet = 0,             -- max bounces (0 = no bounce)
        ricochetDamageMult = 0.7, -- damage multiplier per bounce
        ricochetSpeedMult = 0.9,  -- speed retained per bounce
        
        -- AoE (nil = no explosion)
        aoe = nil,
        
        -- Charge mechanics
        charge = {
            minTime = 0.3,
            maxTime = 1.2,
            minDamageMult = 0.4,
            maxDamageMult = 1.0,
            minSpeedMult = 0.5,
            maxSpeedMult = 1.0,
            minSpreadMult = 2.5,
            maxSpreadMult = 0.3,
        },
        
        -- Visual
        visual = "Arrow",         -- VFX module name
        tracerColor = Color3.fromRGB(200, 150, 100),
        tracerLength = 3,
        trailEnabled = true,
    },
}
```

### Full Config Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| **Core Physics** |
| `speed` | number | required | Initial velocity (studs/sec) |
| `gravity` | number | 196.2 | Gravity strength (0 = no drop) |
| `drag` | number | 0 | Air resistance coefficient |
| `lifetime` | number | 5 | Max flight time (seconds) |
| `inheritVelocity` | number | 0 | Shooter velocity transfer (0-1) |
| **Spread** |
| `spreadMode` | string | "Cone" | "Cone", "Pattern", or "None" |
| `baseSpread` | number | 0 | Base spread angle (radians) |
| `spreadPattern` | table/string | nil | Pattern offsets or preset name |
| `crosshairSpreadScale` | number | 0.01 | Crosshair alignment factor |
| `movementSpreadMult` | number | 1.0 | Spread while moving |
| `hipfireSpreadMult` | number | 1.0 | Spread when not ADS |
| `airSpreadMult` | number | 1.0 | Spread while airborne |
| `crouchSpreadMult` | number | 1.0 | Spread while crouching |
| `slideSpreadMult` | number | 1.0 | Spread while sliding |
| **Behaviors** |
| `pierce` | number | 0 | Max targets to pierce |
| `pierceDamageMult` | number | 1.0 | Damage mult per pierce |
| `ricochet` | number | 0 | Max surface bounces |
| `ricochetDamageMult` | number | 0.7 | Damage mult per bounce |
| `ricochetSpeedMult` | number | 0.9 | Speed retained per bounce |
| **AoE** |
| `aoe` | table/nil | nil | Explosion config (see below) |
| `aoe.radius` | number | - | Explosion radius (studs) |
| `aoe.falloff` | boolean | true | Damage decreases with distance |
| `aoe.falloffMin` | number | 0.25 | Min damage at edge (0-1) |
| `aoe.friendlyFire` | boolean | false | Damage teammates |
| `aoe.knockback` | number | 0 | Push force |
| **Charge** |
| `charge` | table/nil | nil | Charge config (see below) |
| `charge.minTime` | number | - | Min hold to fire |
| `charge.maxTime` | number | - | Full charge time |
| `charge.minDamageMult` | number | - | Damage at min charge |
| `charge.maxDamageMult` | number | - | Damage at max charge |
| `charge.minSpeedMult` | number | - | Speed at min charge |
| `charge.maxSpeedMult` | number | - | Speed at max charge |
| `charge.minSpreadMult` | number | - | Spread at min charge |
| `charge.maxSpreadMult` | number | - | Spread at max charge |
| **Visual** |
| `visual` | string | "Bullet" | VFX module name |
| `tracerColor` | Color3 | white | Tracer/trail color |
| `tracerLength` | number | 5 | Trail length (studs) |
| `trailEnabled` | boolean | true | Show trail effect |

### Example Configs

#### Rocket Launcher (AoE)

```lua
RocketLauncher = {
    -- ... base config ...
    damage = 100,
    
    projectile = {
        speed = 150,
        gravity = 0,          -- Rockets fly straight
        drag = 0,
        lifetime = 10,
        
        spreadMode = "None",  -- Perfect accuracy
        
        pierce = 0,
        ricochet = 0,
        
        aoe = {
            radius = 20,
            falloff = true,
            falloffMin = 0.3,
            friendlyFire = false,
            knockback = 100,
        },
        
        visual = "Rocket",
        trailEnabled = true,
    },
}
```

#### Shotgun (Pattern + Pierce)

```lua
Shotgun = {
    -- ... base config ...
    damage = 12,  -- Per pellet
    
    projectile = {
        speed = 400,
        gravity = 50,         -- Light drop
        drag = 0.2,
        lifetime = 1,
        
        spreadMode = "Pattern",
        spreadPattern = "Circle8",
        
        pierce = 1,           -- Can hit 2 targets
        pierceDamageMult = 0.5,
        
        visual = "Pellet",
    },
}
```

#### Sniper (Hitscan-like Projectile)

```lua
Sniper = {
    -- ... base config ...
    
    projectile = {
        speed = 800,          -- Very fast
        gravity = 30,         -- Minimal drop
        drag = 0,
        lifetime = 3,
        
        spreadMode = "None",  -- Perfect when scoped
        baseSpread = 0.005,   -- Tiny spread when not scoped
        hipfireSpreadMult = 4.0,
        
        visual = "Bullet",
        tracerColor = Color3.fromRGB(255, 200, 100),
    },
}
```

---

## Networking

### Projectile Packet Schema

**ProjectileSpawned (Client → Server → Others):** ~45 bytes

| Field | Type | Size | Description |
|-------|------|------|-------------|
| FireTimestamp | Float64 | 8 | When projectile was fired |
| Origin | Vector3 | 12 | Fire position |
| Direction | Vector3 | 12 | Initial direction (normalized) |
| Speed | Float32 | 4 | Initial speed |
| ChargePercent | Uint8 | 1 | Charge level (0-255 = 0-100%) |
| WeaponId | Uint8 | 1 | Weapon enum |
| ProjectileId | Uint32 | 4 | Unique ID for this projectile |
| SpreadSeed | Uint16 | 2 | Random seed for spread (server verification) |

**ProjectileHit (Client → Server):** ~49 bytes

| Field | Type | Size | Description |
|-------|------|------|-------------|
| FireTimestamp | Float64 | 8 | Original fire time |
| ImpactTimestamp | Float64 | 8 | When projectile hit |
| Origin | Vector3 | 12 | Fire position |
| HitPosition | Vector3 | 12 | Impact position |
| TargetUserId | Int32 | 4 | Target player (0 = environment) |
| HitPart | Uint8 | 1 | 0=None, 1=Body, 2=Head, 3=Limb |
| WeaponId | Uint8 | 1 | Weapon enum |
| ProjectileId | Uint32 | 4 | Matching spawn ID |
| PierceCount | Uint8 | 1 | How many targets already hit |
| BounceCount | Uint8 | 1 | How many times bounced |

### Remote Events

| Event | Direction | Description |
|-------|-----------|-------------|
| `ProjectileSpawned` | Client → Server | New projectile fired |
| `ProjectileReplicate` | Server → Others | Replicate to other clients |
| `ProjectileHit` | Client → Server | Projectile hit something |
| `ProjectileHitConfirmed` | Server → All | Validated hit for VFX |
| `ProjectileDestroyed` | Server → All | Projectile despawned |

### Visual Replication

Other clients receive `ProjectileReplicate` and spawn their own visual:

```lua
-- Server broadcasts
Net:FireAllClientsExcept(shooter, "ProjectileReplicate", {
    shooterUserId = shooter.UserId,
    origin = origin,
    direction = direction,
    speed = speed,
    visual = config.projectile.visual,
    projectileId = projectileId,
})

-- Other clients spawn visual
Net.OnClientEvent("ProjectileReplicate", function(data)
    ProjectileVFX:SpawnVisual(data)
end)
```

---

## Validation

### Server Validation Flow

```lua
function ProjectileValidator:ValidateHit(shooter, projectileData, weaponConfig)
    -- 1. Timestamp validation
    local valid, reason = self:_validateTimestamps(projectileData)
    if not valid then return false, reason end
    
    -- 2. Flight time validation
    valid, reason = self:_validateFlightTime(projectileData, weaponConfig)
    if not valid then return false, reason end
    
    -- 3. Position validation (using PositionHistory)
    valid, reason = self:_validateTargetPosition(shooter, projectileData, weaponConfig)
    if not valid then return false, reason end
    
    -- 4. Trajectory validation
    valid, reason = self:_validateTrajectory(projectileData, weaponConfig)
    if not valid then return false, reason end
    
    -- 5. Statistical tracking
    self:_trackStats(shooter, projectileData)
    
    return true, "Valid"
end
```

### Timestamp Validation

```lua
function ProjectileValidator:_validateTimestamps(data)
    local now = workspace:GetServerTimeNow()
    
    -- Fire timestamp not in future
    if data.FireTimestamp > now + 0.05 then
        return false, "FireTimestampInFuture"
    end
    
    -- Impact timestamp after fire
    if data.ImpactTimestamp <= data.FireTimestamp then
        return false, "ImpactBeforeFire"
    end
    
    -- Not too old (scaled by ping)
    local maxAge = self.Config.MaxTimestampAge + (shooterPing / 1000)
    if now - data.FireTimestamp > maxAge then
        return false, "TimestampTooOld"
    end
    
    return true
end
```

### Flight Time Validation

Server recalculates expected flight time:

```lua
function ProjectileValidator:_validateFlightTime(data, config)
    local claimedFlightTime = data.ImpactTimestamp - data.FireTimestamp
    
    -- Calculate expected flight time
    local distance = (data.HitPosition - data.Origin).Magnitude
    local expectedFlightTime = self:_calculateFlightTime(
        data.Origin, 
        data.HitPosition, 
        config
    )
    
    -- Allow tolerance for physics differences
    local tolerance = self.Config.FlightTimeTolerance  -- e.g., 0.15 (15%)
    local minTime = expectedFlightTime * (1 - tolerance)
    local maxTime = expectedFlightTime * (1 + tolerance)
    
    if claimedFlightTime < minTime or claimedFlightTime > maxTime then
        return false, "FlightTimeMismatch"
    end
    
    return true
end
```

### Position Validation

Uses existing PositionHistory, but at **impact timestamp**:

```lua
function ProjectileValidator:_validateTargetPosition(shooter, data, config)
    if data.TargetUserId == 0 then
        return true  -- Environment hit, no target validation
    end
    
    local target = Players:GetPlayerByUserId(data.TargetUserId)
    if not target then
        return false, "TargetNotFound"
    end
    
    -- Get target position at IMPACT time (not fire time)
    local impactTimestamp = data.ImpactTimestamp
    local rollbackTime = HitDetectionAPI:GetRollbackTime(shooter)
    local lookupTime = impactTimestamp - rollbackTime
    
    local historicalPosition = HitDetectionAPI:GetPositionAtTime(target, lookupTime)
    if not historicalPosition then
        return false, "NoPositionHistory"
    end
    
    -- Validate hit position vs historical
    local offset = (data.HitPosition - historicalPosition).Magnitude
    local tolerance = self:_calculateTolerance(shooter, target, data, config)
    
    if offset > tolerance then
        return false, "TargetNotAtPosition"
    end
    
    return true
end
```

### Tolerance Calculation

Projectiles need **wider tolerances** than hitscan due to:
- Flight time prediction errors
- Target movement during flight
- Physics simulation differences

```lua
function ProjectileValidator:_calculateTolerance(shooter, target, data, config)
    local baseTolerance = self.Config.BasePositionTolerance  -- e.g., 5 studs
    
    -- Scale with ping
    local shooterPing = HitDetectionAPI:GetPlayerPing(shooter)
    local targetPing = HitDetectionAPI:GetPlayerPing(target)
    local pingFactor = 1 + (shooterPing + targetPing) / 400
    
    -- Scale with flight time (longer flight = more error)
    local flightTime = data.ImpactTimestamp - data.FireTimestamp
    local flightFactor = 1 + flightTime * 2  -- +2 studs per second of flight
    
    -- Scale with projectile speed (faster = less error)
    local speedFactor = 300 / config.projectile.speed  -- Baseline 300 studs/sec
    
    return baseTolerance * pingFactor * flightFactor * speedFactor
end
```

### Validation Config

| Key | Default | Description |
|-----|---------|-------------|
| `MaxTimestampAge` | 2.0s | Max time in past for hits |
| `FlightTimeTolerance` | 0.15 | 15% flight time variance allowed |
| `BasePositionTolerance` | 5 studs | Base position validation |
| `MaxFlightTimeTolerance` | 8 studs | Max tolerance for long flights |
| `TrajectoryCheckPoints` | 3 | Points to check along path |

---

## API Reference

### ProjectileAPI

```lua
local ProjectileAPI = require(path.to.ProjectileAPI)
```

#### Initialization

```lua
ProjectileAPI:Init(net, hitDetectionAPI)
```

#### Projectile Spawning (Client)

```lua
-- Spawn a projectile
local projectileId = ProjectileAPI:Fire(weaponConfig, {
    origin = Vector3,
    direction = Vector3,
    chargePercent = number?,  -- 0-1, optional
})

-- Cancel/destroy a projectile
ProjectileAPI:DestroyProjectile(projectileId)
```

#### Hit Validation (Server)

```lua
-- Validate a projectile hit
local valid, reason = ProjectileAPI:ValidateHit(shooter, projectileData, weaponConfig)

-- Get active projectiles for a player
local projectiles = ProjectileAPI:GetActiveProjectiles(player)
```

#### Physics Queries

```lua
-- Predict impact point (for UI/crosshair)
local predictedHit = ProjectileAPI:PredictImpact(origin, direction, config, maxTime)
-- Returns: { position, normal, distance, flightTime, target? }

-- Calculate trajectory points (for debug visualization)
local points = ProjectileAPI:GetTrajectoryPoints(origin, direction, config, steps)
-- Returns: { Vector3, Vector3, ... }
```

#### Configuration

```lua
-- Check if weapon uses projectiles
local isProjectile = ProjectileAPI:IsProjectileWeapon(weaponConfig)

-- Get projectile config
local projectileConfig = ProjectileAPI:GetProjectileConfig(weaponConfig)
```

#### Events

```lua
-- Client events
ProjectileAPI.ProjectileFired:Connect(function(projectileId, data) end)
ProjectileAPI.ProjectileHit:Connect(function(projectileId, hitResult) end)
ProjectileAPI.ProjectileDestroyed:Connect(function(projectileId, reason) end)

-- Server events
ProjectileAPI.HitValidated:Connect(function(shooter, target, data) end)
ProjectileAPI.HitRejected:Connect(function(shooter, data, reason) end)
```

### ProjectilePhysics

```lua
local ProjectilePhysics = require(path.to.ProjectilePhysics)
```

#### Trajectory Calculation

```lua
-- Create a new trajectory simulator
local trajectory = ProjectilePhysics.new(config)

-- Step the simulation
local newPosition, newVelocity, hitResult = trajectory:Step(
    position,
    velocity,
    dt,
    raycastParams
)

-- Get position at time T
local position, velocity = trajectory:GetStateAtTime(origin, direction, speed, time)

-- Calculate full trajectory
local points, hitResult = trajectory:Simulate(origin, direction, speed, maxTime, raycastParams)
```

#### Spread Calculation

```lua
-- Calculate spread direction
local spreadDirection = ProjectilePhysics:ApplySpread(
    aimDirection,
    config,
    spreadState  -- { velocity, recoil, isADS, isCrouching, etc. }
)

-- Get pattern offsets
local offsets = ProjectilePhysics:GetPatternOffsets(patternName)
```

---

## Integration Guide

### Adding a Projectile Weapon

1. **Add projectile config** to weapon in `LoadoutConfig.lua`:

```lua
NewBow = {
    id = "NewBow",
    -- ... base config ...
    
    projectile = {
        speed = 200,
        gravity = 196.2,
        drag = 0.05,
        lifetime = 5,
        spreadMode = "Cone",
        baseSpread = 0.02,
        -- ... other fields ...
    },
}
```

2. **Create VFX module** (if new visual type):

```lua
-- Game/Replication/VFXModules/Arrow.lua
local Arrow = {}

function Arrow:Spawn(data)
    -- Create visual projectile
    local visual = arrowTemplate:Clone()
    visual.Position = data.origin
    visual.Parent = workspace.Projectiles
    return visual
end

function Arrow:Update(visual, position, velocity)
    -- Update position and rotation
    visual.CFrame = CFrame.lookAt(position, position + velocity)
end

function Arrow:Destroy(visual, hitResult)
    -- Impact effect
    if hitResult then
        -- Spawn impact particles
    end
    visual:Destroy()
end

return Arrow
```

3. **Update weapon action** to use projectile system:

```lua
-- Actions/Gun/NewBow/Attack.lua
local ProjectileAPI = require(...)

function Attack.Execute(weaponInstance, currentTime, chargePercent)
    local config = weaponInstance.Config
    
    if config.projectile then
        -- Use projectile system
        local projectileId = ProjectileAPI:Fire(config, {
            origin = weaponInstance:GetMuzzlePosition(),
            direction = weaponInstance:GetAimDirection(),
            chargePercent = chargePercent,
        })
    else
        -- Fall back to hitscan
        -- ... existing raycast code ...
    end
end
```

### Handling Both Hitscan and Projectile

The system automatically detects weapon type:

```lua
function WeaponController:Fire(weaponConfig)
    if ProjectileAPI:IsProjectileWeapon(weaponConfig) then
        -- Projectile path
        self:_fireProjectile(weaponConfig)
    else
        -- Hitscan path (existing)
        self:_fireHitscan(weaponConfig)
    end
end
```

---

## Debugging

### Debug Visualization

Press **F5** to toggle projectile debug mode:

- **Green line**: Predicted trajectory
- **Red sphere**: Actual projectile position
- **Blue sphere**: Server-validated position
- **Yellow line**: Spread cone visualization
- **Orange**: Impact point

### Debug Logging

Enable in `ProjectileValidator.lua`:

```lua
local CONFIG = {
    DebugLogging = true,
}
```

Output example:
```
[ProjectileValidator DEBUG] Player1 fired Arrow:
  Origin: (10, 5, 20)
  Direction: (0.8, 0.1, 0.6)
  Speed: 250 studs/sec
  
[ProjectileValidator DEBUG] Player1 -> Player2 (Arrow):
  Fire time: 1769236114.283
  Impact time: 1769236115.102
  Flight time: 0.819s (expected: 0.795s, diff: 3%)
  Client hitPos: (180, 8, 150)
  History pos: (179.5, 8.2, 150.1)
  Offset: 0.71 studs | Tolerance: 12.5 (base=5 * ping=1.5 * flight=1.67)
  RESULT: VALID ✓
```

### Common Debug Checks

1. **Projectile not spawning**: Check `projectile` config exists
2. **Wrong trajectory**: Verify gravity/drag values
3. **Spread too wide/narrow**: Check `baseSpread` and `crosshairSpreadScale`
4. **Validation failing**: Enable debug logging, check tolerances

---

## Troubleshooting

### Projectile Not Spawning

| Cause | Solution |
|-------|----------|
| No `projectile` config | Add `projectile = {}` to weapon config |
| Missing visual module | Create VFX module or use existing ("Bullet") |
| Ammo/cooldown blocking | Check weapon state before fire |

### Hits Not Registering

| Cause | Solution |
|-------|----------|
| Flight time mismatch | Increase `FlightTimeTolerance` |
| Position validation failing | Increase `BasePositionTolerance` |
| Timestamp too old | Increase `MaxTimestampAge` |
| No position history | Ensure target has heartbeat updates |

### Trajectory Looks Wrong

| Cause | Solution |
|-------|----------|
| Too much drop | Reduce `gravity` value |
| Slowing too fast | Reduce `drag` value |
| Wrong direction | Check camera aim calculation |
| Jittery movement | Increase physics step rate |

### Spread Not Matching Crosshair

| Cause | Solution |
|-------|----------|
| Values not aligned | Adjust `crosshairSpreadScale` |
| Modifiers different | Ensure same state checks |
| Pattern vs cone mismatch | Verify `spreadMode` setting |

### High Latency Issues

For players with 200ms+ ping:
- Increase `MaxTimestampAge` to 3.0s
- Increase `BasePositionTolerance` to 8-10 studs
- Increase `FlightTimeTolerance` to 0.25

---

## Performance

| Operation | Cost | Notes |
|-----------|------|-------|
| Trajectory step | O(1) | CFrame math per frame |
| Collision check | O(1) | Single raycast per step |
| Visual update | O(1) | CFrame assignment |
| Validation | O(1) | Fixed checks |
| Position history lookup | O(n) | n ≤ 60 samples |

### Memory Usage

| Component | Per Projectile | Notes |
|-----------|---------------|-------|
| Physics state | ~100 bytes | Position, velocity, config ref |
| Visual instance | ~500 bytes | Part + trail |
| Network packet | ~49 bytes | Serialized data |

### Optimization Tips

1. **Pool visual instances** - Reuse projectile parts
2. **Limit active projectiles** - Cap per player (e.g., 10)
3. **Reduce trail quality** - For low-end devices
4. **Skip validation for environment hits** - No target lookup needed

---

## Version History

- **v1.0** - Initial implementation
  - CFrame-based physics simulation
  - Cone/Pattern/None spread modes
  - Pierce, Ricochet, AoE behaviors
  - Charge mechanics
  - Crosshair alignment system
  - Server validation with flight time checks
  - Visual replication to all clients
  - Integration with existing HitDetection system
