# VoxManager

A high-performance voxel-based destruction system for Roblox. Blow stuff up, then regenerate it back.

## Quick Start

```lua
local VoxManager = require(game.ReplicatedStorage.VoxManager)

-- Explode at a position
VoxManager:explode(Vector3.new(0, 10, 0))

-- Regenerate everything
VoxManager:regenerateAll()
```

That's it. Two lines.

---

## API Reference

### `VoxManager:explode(position, radius?, options?)`

Destroy parts at a position.

```lua
-- Basic - uses defaults (radius 10, voxelSize 1)
VoxManager:explode(position)

-- With radius
VoxManager:explode(position, 15)

-- With options
VoxManager:explode(position, 10, {
    voxelSize = 2,        -- Size of resulting voxels (default: 1)
    debris = true,        -- Show debris particles (default: true)
    debrisAmount = 10,    -- Number of debris pieces (default: 5)
    ignore = {"Bedrock"}, -- Parts to ignore by name (default: {"Bedrock"})
    debugColors = false,  -- Random colors for debugging (default: false)
})
```

**Returns:** `boolean` - Success

---

### `VoxManager:regenerateAll()`

Restore all destroyed parts to their original state.

```lua
local restoredParts = VoxManager:regenerateAll()
print("Restored", #restoredParts, "parts")
```

**Returns:** `{Part}` - Array of restored parts

---

### `VoxManager:setDefaults(options)`

Set default options for all future explosions.

```lua
VoxManager:setDefaults({
    radius = 15,
    voxelSize = 2,
    debris = true,
    debrisAmount = 8,
    ignore = {"Bedrock", "Baseplate", "SpawnLocation"},
})

-- Now all calls use these defaults
VoxManager:explode(position)  -- Uses radius 15, voxelSize 2, etc.
```

---

### `VoxManager:cleanup()`

Clean up all voxels and regeneration data. Call when resetting.

```lua
VoxManager:cleanup()
```

---

## Examples

### Basic Destruction Ability

```lua
-- Server Script
local VoxManager = require(game.ReplicatedStorage.VoxManager)
local RemoteEvent = game.ReplicatedStorage.DestroyAbility

RemoteEvent.OnServerEvent:Connect(function(player, position)
    VoxManager:explode(position, 12)
end)
```

### Regenerating After Delay

```lua
local VoxManager = require(game.ReplicatedStorage.VoxManager)

-- Destroy something
VoxManager:explode(position, 10)

-- Wait 5 seconds, then restore
task.delay(5, function()
    VoxManager:regenerateAll()
end)
```

### Hollow Purple Projectile

```lua
local VoxManager = require(game.ReplicatedStorage.VoxManager)

local function fireHollowPurple(origin, direction)
    local projectile = Instance.new("Part")
    projectile.Shape = Enum.PartType.Ball
    projectile.Size = Vector3.new(6, 6, 6)
    projectile.Position = origin
    projectile.Anchored = false
    projectile.CanCollide = false
    projectile.Color = Color3.fromRGB(128, 0, 255)
    projectile.Material = Enum.Material.Neon
    projectile.Parent = workspace

    -- Move forward (ignores gravity)
    local velocity = Instance.new("LinearVelocity")
    velocity.VectorVelocity = direction * 100
    velocity.MaxForce = math.huge
    velocity.Attachment0 = Instance.new("Attachment", projectile)
    velocity.Parent = projectile

    -- Voxelize on touch
    local touched = {}
    projectile.Touched:Connect(function(hit)
        if touched[hit] or hit.Name == "Bedrock" then return end
        touched[hit] = true
        VoxManager:explode(hit.Position, 8)
    end)

    -- Destroy after 5 seconds
    game.Debris:AddItem(projectile, 5)
end
```

### Custom Defaults Per Ability

```lua
local VoxManager = require(game.ReplicatedStorage.VoxManager)

-- Small precise explosion
local function smallExplosion(pos)
    VoxManager:explode(pos, 5, {
        voxelSize = 0.5,
        debris = true,
        debrisAmount = 3,
    })
end

-- Big destruction
local function bigExplosion(pos)
    VoxManager:explode(pos, 25, {
        voxelSize = 3,
        debris = true,
        debrisAmount = 20,
    })
end
```

### Client-Side Debris (Performance)

```lua
-- Server
local VoxManager = require(game.ReplicatedStorage.VoxManager)
local DebrisRemote = game.ReplicatedStorage.VoxelDebris

VoxManager:setDebrisCallback(function(pos, radius, amount, size, info)
    DebrisRemote:FireAllClients(pos, radius, amount, size, info)
end)

-- Client
DebrisRemote.OnClientEvent:Connect(function(pos, radius, amount, size, info)
    -- Create local debris particles here
end)
```

---

## Default Values

| Option | Default | Description |
|--------|---------|-------------|
| `radius` | `10` | Explosion radius in studs |
| `voxelSize` | `1` | Minimum voxel size |
| `debris` | `true` | Show debris particles |
| `debrisAmount` | `5` | Number of debris pieces |
| `debrisSize` | `0.3` | Debris size multiplier |
| `ignore` | `{"Bedrock"}` | Part names to ignore |
| `debugColors` | `false` | Random colors for debugging |

---

## How It Works

1. **Octree Subdivision** - Recursively splits parts into 8 octants to create spherical cutouts
2. **Greedy Meshing** - Merges adjacent voxels into larger blocks (reduces part count)
3. **Object Pooling** - Reuses parts to avoid garbage collection lag
4. **Instance Caching** - Original parts are cached (not destroyed) for perfect regeneration

---

## Performance Tips

- Use larger `voxelSize` for better performance (1-2 for small, 3-4 for large explosions)
- Use `setDebrisCallback` to move debris to client-side
- Call `cleanup()` when done to free memory
- Parts named "Bedrock" are ignored by default

---

## Credits

- Octree system: https://devforum.roblox.com/t/dynamic-octree-system/2177042
- Greedy meshing: https://devforum.roblox.com/t/consume-everything-how-greedy-meshing-works/452717
