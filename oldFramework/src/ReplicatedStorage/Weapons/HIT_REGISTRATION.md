# Hit Registration System Documentation

## Overview

The hit registration system uses **client-side hitscan raycasting with server-side validation**. This approach provides instant feedback to players while maintaining server authority to prevent exploiting.

## Architecture

### Client-Side (Instant Feedback)
1. Player fires weapon
2. Client performs raycast immediately
3. Client shows visual feedback (hit markers, tracers, impacts)
4. Client sends hit data to server

### Server-Side (Authority & Validation)
1. Server receives hit data from client
2. Server validates hit (distance, time, position checks)
3. Server re-raycasts to confirm hit is legitimate
4. Server applies damage if validation passes
5. Server broadcasts damage to all clients

## Key Components

### 1. HitscanSystem (`Weapons/Systems/HitscanSystem.lua`)
**Purpose**: Shared raycast logic for both client and server

**Key Functions**:
- `GetTargetHitboxes(shooterCharacter)` - Gets all player hitbox folders except shooter's
- `CreateWeaponRaycastParams(shooterCharacter, cacheKey?)` - Creates optimized RaycastParams with whitelist filtering
- `PerformRaycast(origin, direction, shooterCharacter, cacheKey?)` - Performs single hitscan raycast
- `PerformSpreadRaycast(...)` - Performs multiple raycasts with spread (for shotguns)
- `IsHeadshot(hitPart)` - Checks if hit was a headshot
- `GetPlayerFromHit(hitPart)` - Gets player who owns the hit character

**Filtering Strategy**:
- Uses **whitelist (Include) filtering** to ONLY hit Hitbox parts
- Ignores all character rigs, colliders, accessories, terrain, etc.
- `RespectCanCollide = false` (CRITICAL - hitbox parts have CanCollide=false)
- `IgnoreWater = true` (bullets pass through water)
- `CollisionGroup = "Hitboxes"` (performance optimization)

**RaycastParams Caching**:
- Reuses RaycastParams objects for performance
- Cache key is typically `tostring(player.UserId)`
- Clear cache when players leave

### 2. WeaponHitService (`ServerScriptService/Services/WeaponHitService.lua`)
**Purpose**: Server-side hit validation and damage application

**Validation Steps**:
1. **Time Check**: Reject hits older than 0.5 seconds
2. **Distance Check**: Ensure hit is within weapon range + 50 stud tolerance
3. **Server Raycast**: Re-perform raycast from client's reported position
4. **Position Match**: Ensure server hit is within 50 studs of client hit

**Damage Calculation**:
- Base damage from weapon config (BodyDamage or HeadshotDamage)
- Distance-based falloff using linear interpolation
- Formula: `baseDamage * (1 - (falloffProgress * (1 - minMultiplier)))`

**Tolerance Settings**:
```lua
MAX_DISTANCE_TOLERANCE = 50 -- studs
MAX_TIME_TOLERANCE = 0.5 -- seconds
```

### 3. CollisionGroupService (`ServerScriptService/Services/CollisionGroupService.lua`)
**Purpose**: Manages collision groups for physics and raycasting

**Collision Groups**:
- `Players` - All character parts (no player-to-player collision)
- `Hitboxes` - All hitbox parts (used for weapon raycast filtering)

**Functions**:
- `Init()` - Registers collision groups and configures interactions
- `SetCharacterCollisionGroup(character)` - Assigns all character parts to "Players" group
- `SetHitboxCollisionGroup(character)` - Assigns all hitbox parts to "Hitboxes" group

### 4. CollisionUtils (`Utils/CollisionUtils.lua`)
**Purpose**: Helper functions for creating raycast/overlap parameters

**Added Function**:
- `CreateWeaponRaycastParams(targetHitboxFolders)` - Creates optimized params for weapon raycasts

### 5. Revolver Attack.lua (Example Implementation)
**Client-Side Weapon Firing**:

```lua
-- Raycast from camera (first-person accuracy)
local origin = camera.CFrame.Position
local direction = camera.CFrame.LookVector * maxRange

-- Perform raycast
local raycastResult = HitscanSystem:PerformRaycast(
    origin,
    direction,
    character,
    tostring(player.UserId)
)

-- Send to server
RemoteEvents:FireServer("WeaponFired", {
    WeaponType = "Gun",
    WeaponName = "Revolver",
    Origin = origin,
    Direction = direction,
    HitPosition = raycastResult and raycastResult.Position,
    HitPartName = raycastResult and raycastResult.Instance.Name,
    Distance = raycastResult and raycastResult.Distance,
    IsHeadshot = raycastResult and HitscanSystem:IsHeadshot(raycastResult.Instance),
    TargetPlayer = raycastResult and HitscanSystem:GetPlayerFromHit(raycastResult.Instance),
    Timestamp = os.clock(),
})
```

## Hitbox Structure

### Character Hierarchy
Based on `CrouchUtils.lua` and your custom character system:

```
Character (Model)
├── Hitbox (Folder) - Used for weapon hit detection
│   ├── Body (Part) - CanQuery=true, CanCollide=false, CollisionGroup="Hitboxes"
│   ├── Head (Part) - CanQuery=true, CanCollide=false, CollisionGroup="Hitboxes"
│   ├── LeftArm (Part)
│   ├── RightArm (Part)
│   ├── LeftLeg (Part)
│   └── RightLeg (Part)
├── Collider (Model) - Used for character physics (NOT for weapon hits)
│   ├── Default/ - Standing collision
│   └── Crouch/ - Crouching collision
└── Rig (Model) - Visual R6 rig (NOT for weapon hits)
```

**Critical Properties** (from CrouchUtils.lua:124):
- Hitbox parts: `CanQuery = true`, `CanCollide = false`, `CanTouch = true`
- Rig parts: `CanQuery = false` (line 261)
- Collider parts: Should also have `CanQuery = false`

## Why Raycasts Are Used

### Advantages
1. **Instant Hit Detection**: Perfect for hitscan weapons (no bullet drop)
2. **Precision**: Exact hit point, distance, and part detection
3. **Performance**: Highly optimized by Roblox engine
4. **Deterministic**: Consistent results every frame

### Alternatives (NOT Used)
- **Spherecast**: Volumetric detection (useful for shotguns if needed)
- **FastCast Module**: For projectiles with bullet drop/physics
- **Touched Events**: Unreliable at high speeds, physics-dependent

## Filtering: Whitelist vs Blacklist

### Why Whitelist (Include) is Used

**Security**:
- Only hitbox parts can be hit
- Exploiters can't place fake parts to shield themselves
- Clear, explicit target set

**Simplicity**:
- Don't need to exclude: terrain, workspace parts, rigs, accessories, vehicles, etc.
- Easy to understand and maintain

**Example**:
```lua
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include -- Whitelist
params.FilterDescendantsInstances = {hitboxFolder1, hitboxFolder2, ...}
params.RespectCanCollide = false -- CRITICAL for hitboxes
```

## Common Mistakes to Avoid

### 1. ❌ Using RespectCanCollide = true
```lua
-- WRONG - Hitboxes have CanCollide=false, so raycast ignores them!
params.RespectCanCollide = true

-- CORRECT
params.RespectCanCollide = false
```

### 2. ❌ Sending RaycastResult to Server
```lua
-- WRONG - RaycastResult doesn't serialize over RemoteEvents
RemoteEvents:FireServer("WeaponFired", raycastResult)

-- CORRECT - Extract serializable data
RemoteEvents:FireServer("WeaponFired", {
    HitPosition = result.Position, -- Vector3
    Distance = result.Distance,    -- number
    HitPartName = result.Instance.Name, -- string
})
```

### 3. ❌ Using Blacklist (Exclude) Filtering
```lua
-- WRONG - Must exclude terrain, all workspace parts, all rigs, all accessories...
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {character} -- Not enough!

-- CORRECT - Whitelist only hitboxes
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = {hitboxFolders}
```

### 4. ❌ Not Excluding Shooter's Own Hitbox
```lua
-- WRONG - Shooter can hit themselves
for _, player in pairs(Players:GetPlayers()) do
    table.insert(hitboxFolders, player.Character.Hitbox)
end

-- CORRECT - Exclude shooter
for _, player in pairs(Players:GetPlayers()) do
    if player.Character ~= shooterCharacter then -- Check here!
        table.insert(hitboxFolders, player.Character.Hitbox)
    end
end
```

## Performance Optimizations

### 1. Reuse RaycastParams
```lua
-- Cache params per player
local raycastParamsCache = {}

function GetParams(playerUserId)
    if raycastParamsCache[playerUserId] then
        return raycastParamsCache[playerUserId]
    end

    local params = RaycastParams.new()
    -- ... configure
    raycastParamsCache[playerUserId] = params
    return params
end
```

### 2. Use Collision Groups
```lua
-- More efficient than large FilterDescendantsInstances arrays
params.CollisionGroup = "Hitboxes"
```

### 3. Set CanQuery Correctly
```lua
-- Hitboxes
hitboxPart.CanQuery = true

-- Everything else
rigPart.CanQuery = false
colliderPart.CanQuery = false
```

### 4. Limit Ray Distance
```lua
-- Don't raycast to infinity - use weapon max range
local maxRange = weaponConfig.Damage.MaxRange or 500
local direction = lookVector * maxRange
```

## Lag Compensation (Future Enhancement)

Currently uses **tolerance-based validation** (simpler):
- 50 stud distance tolerance
- 0.5 second time tolerance

**Future: Snapshot-based rewinding** (more accurate for high-ping):
1. Server stores position history (33 snapshots/second for 1 second)
2. Client sends timestamp with hit
3. Server rewinds to client's timestamp
4. Server raycasts against historical positions
5. More accurate but more complex

## Testing Checklist

- [ ] Hitbox parts have `CanQuery=true`, `CanCollide=false`
- [ ] Rig parts have `CanQuery=false`
- [ ] Collider parts have `CanQuery=false`
- [ ] Collision groups registered ("Players", "Hitboxes")
- [ ] Hitbox parts assigned to "Hitboxes" collision group
- [ ] WeaponHitService initialized in server
- [ ] RemoteEvents "WeaponFired" and "PlayerDamaged" created
- [ ] Client raycasts from camera position
- [ ] Server validates distance and time
- [ ] Damage falloff calculated correctly
- [ ] Headshots detected properly

## Integration with Existing Systems

### CharacterService
When spawning characters, ensure:
1. Call `CollisionGroupService:SetCharacterCollisionGroup(character)`
2. Call `CollisionGroupService:SetHitboxCollisionGroup(character)`

### Health System (TODO)
When implemented, `WeaponHitService:ApplyDamage()` should:
1. Call `HealthService:DamagePlayer(targetPlayer, damage, shooterPlayer)`
2. Check if player died
3. Award kills/points to shooter
4. Respawn player if needed

### Visual Feedback (TODO)
Client-side effects to implement:
- Hit markers (crosshair feedback)
- Bullet tracers (Beam from gun to hit point)
- Impact effects (blood, sparks, dust)
- Damage numbers (floating text)
- Muzzle flash
- Screen shake/recoil

## Debug Visualization

Add to `HitscanSystem` for debugging:

```lua
function HitscanSystem:VisualizeRaycast(origin, direction, result)
    -- Create beam from origin to hit point
    local beam = Instance.new("Part")
    beam.Size = Vector3.new(0.1, 0.1, direction.Magnitude)
    beam.CFrame = CFrame.new(origin, origin + direction) * CFrame.new(0, 0, -direction.Magnitude/2)
    beam.BrickColor = result and BrickColor.new("Lime green") or BrickColor.new("Really red")
    beam.Material = Enum.Material.Neon
    beam.Anchored = true
    beam.CanCollide = false
    beam.Parent = workspace

    game:GetService("Debris"):AddItem(beam, 2)
end
```

## Summary

The hit registration system is now fully implemented with:

✅ **HitscanSystem** - Shared raycast logic with whitelist filtering
✅ **WeaponHitService** - Server-side validation and damage application
✅ **CollisionGroupService** - Hitbox collision group management
✅ **CollisionUtils** - Helper functions for weapon raycasts
✅ **Revolver Attack** - Example client-side implementation
✅ **RemoteEvents** - WeaponFired and PlayerDamaged events

**Next Steps**:
1. Implement health system integration
2. Add visual feedback (tracers, hit markers, impacts)
3. Test with multiple players
4. Fine-tune validation tolerances
5. Add lag compensation if needed
