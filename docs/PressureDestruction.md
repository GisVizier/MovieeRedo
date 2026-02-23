# Pressure-Based Destruction System

## Overview

The Pressure Destruction System allows weapons to break through breakable walls and surfaces, similar to Rainbow Six Siege's soft destruction mechanics. The system accumulates "pressure" from bullet impacts and triggers destruction when thresholds are met.

Glass exception: breakable parts with `Enum.Material.Glass` bypass pressure accumulation and voxel instantly on hit.

## How It Works

### Flow

1. **Client**: Weapon fires → Impact detected on surface → Send impact data to server
2. **Server**: Validate impact distance → Accumulate pressure → Trigger destruction when threshold met
3. **VoxelDestruction**: Server creates hitbox → Finds all "Breakable" tagged parts → Creates destruction

### Key Concepts

- **Pressure**: A value from weapon config (`destructionPressure`) that determines how much "force" each bullet applies
- **Zones**: For non-shotgun weapons, nearby impacts accumulate pressure in a zone
- **Clusters**: For shotgun weapons, all pellets from one shot are grouped together
- **Range Multiplier**: Closer shots penetrate deeper and create bigger holes

## Architecture

### Client-Side (`PressureDestruction/init.lua`)

**Purpose**: Collect bullet impacts and send to server

**Key Functions**:
- `RegisterImpact(position, normal, part, pressure, isShotgun, shotId)`
  - Called by `WeaponRaycast` (hitscan) or `WeaponProjectile` (projectiles)
  - Shotguns: Groups pellets by `shotId`, sends as cluster
  - Other weapons: Sends immediately as single impact

**Shotgun Grouping**:
- Each shotgun shot gets a unique `shotId` (from `GenerateShotId()`)
- All pellets with same `shotId` are collected for `CLUSTER_WINDOW` (15ms)
- Then sent as one cluster to server

### Server-Side (`PressureDestructionService.lua`)

**Purpose**: Validate impacts, accumulate pressure, trigger destruction

**Two Modes**:

#### 1. Shotgun Mode (Cluster)
- All pellets from one shot arrive together
- Server calculates bounding sphere of all pellet impacts
- Total pressure = `pressure_per_pellet × pellet_count`
- Instant destruction (no accumulation needed)

#### 2. Single Impact Mode (Zone)
- Each bullet creates/updates a pressure zone
- Zones have `ZONE_RADIUS` (2.5 studs) - nearby impacts accumulate
- When zone pressure ≥ `MIN_PRESSURE` (60) → instant destruction
- If zone expires without threshold → still creates small hole

**Validation**:
- Distance check: Impact must be within `MAX_IMPACT_DISTANCE` (1000 studs) of player
- Uses `ReplicationService.PlayerStates` for accurate player position
- Rate limiting: Max `MAX_IMPACTS_PER_SECOND` (50) per player

## Configuration

### Weapon Config (`LoadoutConfig.lua`)

Each weapon has a `destructionPressure` value:

```lua
Sniper = {
    -- ...
    destructionPressure = 100,  -- One shot = big hole
}

Shotgun = {
    -- ...
    destructionPressure = 30,   -- Per pellet (8 pellets = 240 total)
}

Shorty = {
    -- ...
    destructionPressure = 50,   -- Per pellet (6 pellets = 300 total) - SHREDS walls
}

AssaultRifle = {
    -- ...
    destructionPressure = 28,   -- ~3 hits to break
}
```

**Pressure Guidelines**:
- **100+**: One-shot destruction (Sniper)
- **40-60**: 2-3 hits (Revolver, Shorty)
- **25-35**: 3-4 hits (Shotgun, AR)
- **15-20**: Many hits (Pistols, SMG)

### Server Config (`PressureDestructionService.lua`)

```lua
CONFIG = {
    -- Validation
    MAX_IMPACT_DISTANCE = 1000,     -- Max range for valid impacts
    MAX_IMPACTS_PER_SECOND = 50,    -- Rate limit
    
    -- Shotgun cluster
    CLUSTER_WINDOW = 0.015,         -- 15ms to collect pellets
    
    -- Pressure zones (non-shotgun)
    ZONE_RADIUS = 2.5,              -- Nearby impacts accumulate
    ZONE_LIFETIME = 0.08,           -- 80ms window
    MIN_PRESSURE = 60,               -- Threshold for instant break
    
    -- Hole sizing
    MIN_HOLE_SIZE = 1.5,            -- Minimum radius (studs)
    MAX_HOLE_SIZE = 12,             -- Maximum radius (studs)
    PRESSURE_TO_SIZE = 0.06,        -- pressure × this = radius
    
    -- VoxelDestruction
    VOXEL_SIZE = 2,                 -- Chunk size
    DEBRIS_COUNT = 4,               -- Debris pieces
    DESTRUCTION_DEPTH = 3,          -- Base penetration depth
}
```

## Range-Based Mechanics

The system scales destruction based on distance from player to impact:

### Penetration Depth
- **Close Range** (≤15 studs): 2× deeper penetration
- **Medium Range** (15-100 studs): Linear falloff from 2× to 1×
- **Far Range** (>100 studs): Normal depth

### Hole Size
- **Close Range** (≤15 studs): 1.5× bigger holes
- **Medium Range** (15-100 studs): Linear falloff from 1.5× to 1×
- **Far Range** (>100 studs): Normal size

**Why**: Close-range shots have more energy → deeper penetration and bigger holes.

## Hitbox Creation

When destruction triggers:

1. **Calculate center**: `position + (normal × penetrationDepth)`
   - Pushes hitbox **into** the wall, not on surface
   - Penetration depth scales with range

2. **Create hitbox**:
   - Size: `radius × 2` (width/height), `penetrationDepth` (depth)
   - CFrame: Faces along surface normal
   - Material: Neon (for debug visibility)

3. **VoxelDestruction**:
   - Finds all parts with "Breakable" tag overlapping hitbox
   - Creates voxel-based destruction
   - Replicates to all clients

## Adding New Weapons

1. **Add `destructionPressure` to weapon config**:
   ```lua
   MyWeapon = {
       -- ... other config ...
       destructionPressure = 35,  -- Your value
   }
   ```

2. **That's it!** The system automatically:
   - Detects if it's a shotgun (checks `fireProfile.mode == "Shotgun"`)
   - Uses appropriate mode (cluster vs zone)
   - Applies range multipliers
   - Triggers destruction

## Debug Mode

Set `DEBUG = true` in `PressureDestructionService.lua` to see:
- **Red neon hitboxes** at destruction points
- **Console logs** for all impact events
- **Validation failures** and rate limits

Hitboxes show:
- Size (width/height = hole diameter, depth = penetration)
- Position (center of destruction)
- Orientation (facing along surface normal)

## Troubleshooting

### Bullets not breaking walls?
- Check: Part has "Breakable" tag (via CollectionService)
- Check: `destructionPressure` is high enough (≥60 for instant, or accumulates)
- Check: Distance validation passing (within 1000 studs)
- Check: Rate limit not exceeded (50 impacts/sec)

### Hitbox visible but no destruction?
- Hitbox might be on surface instead of inside wall
- Check: Normal direction is correct (points INTO wall)
- Check: Penetration depth is sufficient
- Check: VoxelDestruction can find "Breakable" parts

### Shotgun not working?
- Check: `fireProfile.mode == "Shotgun"` in weapon config
- Check: `shotId` is being generated and passed correctly
- Check: Cluster window (15ms) is long enough for all pellets

## Performance

- **Client**: Minimal overhead (just sends impact data)
- **Server**: 
  - Rate limiting prevents spam
  - Zones expire quickly (80ms)
  - Clusters finalize fast (15ms)
- **VoxelDestruction**: Handles replication and debris automatically

## Future Improvements

Potential enhancements:
- Material-specific pressure resistance (concrete vs wood)
- Penetration through multiple walls
- Bullet type modifiers (AP rounds, etc.)
- Visual feedback (bullet holes, cracks)
