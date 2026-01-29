# Ragdoll System

## Overview

Clone-based ragdoll system for the bean character architecture. Creates a physics-enabled **clone** of the rig for ragdoll simulation, keeping the original rig untouched. On recovery, the clone is destroyed and the character appears where it landed.

## Architecture

```
ON RAGDOLL:
1. Clone the visual rig
2. Setup physics constraints on clone
3. Hide original rig (Transparency = 1)
4. Anchor character Root
5. Clone ragdolls with physics

ON RECOVERY:
1. Get clone's final position
2. Destroy clone
3. Show original rig (Transparency = 0)
4. Position Root at clone's final location
5. Unanchor Root - done!
```

## Why Clone-Based?

**Problems with modifying the original rig:**
- Complex state save/restore (motors, properties, humanoid state)
- Race conditions with CollisionUtils heartbeat loop
- Limbs don't snap back to correct positions
- Motors need C0/C1 restoration

**Clone approach benefits:**
- Original rig stays pristine - no state to manage
- Clone is disposable - just destroy it
- Simple recovery - position Root at clone location
- No CollisionUtils conflicts

## API

### Server
```lua
local RagdollModule = require(ReplicatedStorage.Ragdoll.Ragdoll)

-- Ragdoll player for 3 seconds with knockback
RagdollModule.Ragdoll(player, Vector3.new(0, 100, 0), 3)

-- Manual recovery
RagdollModule.GetBackUp(player)

-- Check state
RagdollModule.IsRagdolled(player) --> boolean
```

### Client
```lua
-- Same API - automatically forwards to server
RagdollModule.Ragdoll(LocalPlayer, Vector3.new(0, 50, 0), 3)
RagdollModule.GetBackUp(LocalPlayer)
```

### Test Script
```lua
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = game.Players.LocalPlayer
local RagdollModule = require(game.ReplicatedStorage.Ragdoll.Ragdoll)

UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.R then
        RagdollModule.Ragdoll(LocalPlayer, Vector3.new(0, 100, -50), 3)
    elseif input.KeyCode == Enum.KeyCode.G then
        RagdollModule.GetBackUp(LocalPlayer)
    end
end)
```

## How Clone is Created (4thAxis Style)

The ragdoll uses a **JointCollider** system from the original 4thAxis ragdoll script. This creates natural-feeling physics:

```lua
local function createRagdollClone(rig)
    local clone = rig:Clone()
    
    -- For each Motor6D, create BallSocketConstraint
    for _, motor in clone:GetDescendants() do
        if motor:IsA("Motor6D") then
            -- Create attachments
            -- Create BallSocketConstraint with joint limits
            -- Key physics properties for natural movement:
            constraint.Radius = 0.15
            constraint.MaxFrictionTorque = 50
            constraint.Restitution = 0
            -- Disable the motor
        end
    end
    
    -- Set humanoid to physics state
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    humanoid.PlatformStand = true
    
    -- VISUAL PARTS DON'T COLLIDE - only JointColliders do
    for _, part in clone:GetDescendants() do
        part.CanCollide = false  -- Visual parts
        part.Massless = false
        part.Anchored = false
        part.CollisionGroup = "Ragdolls"
    end
    
    -- Create invisible JointColliders for main limbs
    -- These handle all collision - makes ragdoll feel natural
    for limbName, limb in mainLimbs do
        local collider = Instance.new("Part")
        collider.Size = COLLIDER_SIZES[limbName]
        collider.Transparency = 1
        collider.CanCollide = true
        collider.Massless = true
        collider.CollisionGroup = "Ragdolls"
        -- Weld to limb
        local weld = Instance.new("Weld")
        weld.Part0 = collider
        weld.Part1 = limb
        collider.Parent = limb
    end
    
    return clone
end
```

### Why JointColliders?

The 4thAxis ragdoll system uses **separate invisible collision parts** for each limb instead of making the visual parts collideable. This provides:

1. **Cleaner collision geometry** - Simple boxes instead of complex visual meshes
2. **Consistent behavior** - Doesn't depend on visual mesh shapes
3. **Better performance** - Simpler collision calculations
4. **Natural-looking physics** - Parts settle naturally on ground

### Collider Sizes

| Limb | Size |
|------|------|
| Head | 1×1×1 |
| Torso | 2×2×1 |
| Arms | 1×2×1 |
| Legs | 1×2×1 |

## Collision Groups

- **Ragdolls** - doesn't collide with self or "Players", DOES collide with "Default" (world)

## Joint Configuration

| Joint | Upper Angle | Twist Range | Twist Enabled |
|-------|-------------|-------------|---------------|
| Neck | 45° | -70° to 70° | Yes |
| Shoulders | 110° | -85° to 85° | Yes |
| Hips | 90° | -45° to 45° | No |

## Integration

### RigManager
Calls `RagdollModule.SetupRig(player, rig, character)` when rig is created. This just registers the rig - no constraints are created until ragdoll starts.

### MovementController
Checks `character:GetAttribute("RagdollActive")` and zeroes movement forces when true.

### Camera
Should follow the ragdoll clone's head during ragdoll. Use `RagdollModule.GetRig(player)` to get the current ragdoll clone (or original rig if not ragdolled).

## Files

- `src/ReplicatedStorage/Ragdoll/Ragdoll.lua` - Core module
- `src/ReplicatedStorage/Modules/Ragdoll.lua` - Alias
