# Ragdoll System

## Overview

The Ragdoll System provides physics-based ragdoll effects for R6 visual rigs. It's designed to work with the game's "bean" character architecture where the visual rig is separate from the physics body.

## Architecture

```
Character Model (Bean)
├── Root (physics part - movement)
├── HumanoidRootPart (anchored, invisible)
├── Head (anchored, invisible)
├── Humanoid
└── Collider/ (hitboxes)

Visual Rig (workspace.Rigs/)
├── HumanoidRootPart (normally anchored)
├── Torso
├── Head
├── Left Arm / Right Arm
├── Left Leg / Right Leg
└── Motor6Ds (Neck, Shoulders, Hips, RootJoint)
```

### How It Works

1. **Normal State**: Visual rig follows the Root part via `BulkMoveTo()` in ClientReplicator
2. **Ragdoll State**: 
   - **Anchor** the character's Root part (freezes in place, no physics conflicts)
   - MovementController stops applying forces (checks `RagdollActive` attribute)
   - Convert Motor6Ds → BallSocketConstraints with joint limits
   - Enable physics on rig parts (CanCollide, unanchor)
   - Apply initial velocity/fling to rig
3. **Recovery**: 
   - Get rig's final position (where it landed)
   - Teleport Root to that position
   - Restore motors, disable physics
   - Unanchor Root, resume movement

## API Reference

### Server-Side (CharacterService)

```lua
-- Simple API for abilities, weapons, and game systems
CharacterService:Ragdoll(player, duration, options)
CharacterService:Unragdoll(player)
CharacterService:IsRagdolled(player) -> boolean
```

**Parameters:**
- `player` - The Player to ragdoll
- `duration` - Time in seconds before auto-recovery (nil = permanent until Unragdoll called)
- `options` - Optional table:
  - `FlingDirection`: Vector3 - Direction to fling the ragdoll
  - `FlingStrength`: number - Force of fling (default: 50)
  - `Velocity`: Vector3 - Direct velocity to apply

**Examples:**
```lua
-- Ragdoll for 3 seconds
CharacterService:Ragdoll(player, 3)

-- Ragdoll with knockback direction
CharacterService:Ragdoll(player, 2, {
    FlingDirection = (player.Character.PrimaryPart.Position - explosionOrigin).Unit,
    FlingStrength = 80
})

-- Permanent ragdoll (death)
CharacterService:Ragdoll(player, nil)
```

### Client-Side (RagdollSystem)

```lua
-- Low-level rig manipulation (used internally)
RagdollSystem:RagdollRig(rig, options) -> boolean
RagdollSystem:UnragdollRig(rig) -> boolean
RagdollSystem:IsRagdolled(rig) -> boolean
```

## Joint Limits

R6 joint configurations for realistic ragdoll physics:

| Joint | Upper Angle | Twist Lower | Twist Upper | Friction |
|-------|-------------|-------------|-------------|----------|
| Neck | 45° | -60° | 60° | 10 |
| Shoulders | 110° | -85° | 85° | 5 |
| Hips | 90° | -45° | 45° | 5 |
| RootJoint | 30° | -45° | 45° | 15 |

## Physics Properties

```lua
Ragdoll = {
    Density = 0.7,
    Friction = 0.5,
    Elasticity = 0,
    HeadDensity = 0.7,
    HeadFriction = 0.3,
}
```

## Collision Groups

Ragdoll parts are placed in a `Ragdolls` collision group that:
- Does NOT collide with `Players` (the character's physics body)
- DOES collide with `Default` (world geometry)

This prevents the ragdoll from fighting with the character's Root part.

## Network Flow

```
1. Server: CharacterService:Ragdoll(player, duration, options)
   └── Sets character:SetAttribute("RagdollActive", true)
   └── Fires "RagdollStarted" to all clients with velocity/fling data
   └── Schedules auto-recovery if duration provided

2. Client: CharacterController receives "RagdollStarted"
   └── MovementController sees RagdollActive, zeros VectorForce
   └── RagdollSystem:RagdollRig(rig, options):
       └── ANCHORS the character Root (no physics interference)
       └── Applies velocity to rig BEFORE converting joints
       └── Converts Motor6Ds → BallSocketConstraints
       └── Enables physics on rig parts (collision, unanchor)
   └── ClientReplicator stops moving rig (checks RagdollActive)

3. Server: CharacterService:Unragdoll(player) [after duration or manual]
   └── Sets character:SetAttribute("RagdollActive", false)
   └── Fires "RagdollEnded" to all clients

4. Client: CharacterController receives "RagdollEnded"
   └── RagdollSystem:UnragdollRig(rig):
       └── Gets rig's final position (where ragdoll landed)
       └── Teleports Root to that position
       └── Restores motors, disables physics on rig
       └── UNANCHORS Root, restores physics forces
   └── Restarts collision enforcement
   └── ClientReplicator resumes moving rig
```

## Testing

Press **G** to toggle ragdoll on your character (debug keybind).

## Integration Examples

### Weapon Kill Effect
```lua
-- In weapon damage handler
if victim.Humanoid.Health <= 0 then
    local direction = (victim.PrimaryPart.Position - attacker.PrimaryPart.Position).Unit
    CharacterService:Ragdoll(victimPlayer, nil, {
        FlingDirection = direction,
        FlingStrength = 60
    })
end
```

### Explosion Knockback
```lua
local function onExplosion(origin, radius, force)
    for _, player in Players:GetPlayers() do
        local char = player.Character
        if char and char.PrimaryPart then
            local distance = (char.PrimaryPart.Position - origin).Magnitude
            if distance <= radius then
                local direction = (char.PrimaryPart.Position - origin).Unit
                local strength = force * (1 - distance / radius)
                CharacterService:Ragdoll(player, 2, {
                    FlingDirection = direction,
                    FlingStrength = strength
                })
            end
        end
    end
end
```

### Stun Ability
```lua
function StunAbility:Activate(target)
    CharacterService:Ragdoll(target, self.StunDuration)
end
```

## File Locations

- `src/ReplicatedStorage/Game/Character/Rig/RagdollSystem.lua` - Core ragdoll logic
- `src/ServerScriptService/Server/Services/Character/CharacterService.lua` - Server API
- `src/StarterPlayer/.../Controllers/Character/CharacterController.lua` - Client handling
- `src/ReplicatedStorage/Global/Character.lua` - Ragdoll config values

## Migration from Old Framework

The old framework (in `src/ReplicatedStorage/Ragdoll/`) used a different approach:
- Ragdolled the live character directly
- Used `Motor6D.Part0 = nil` instead of `.Enabled = false`
- Had a PlayerStates attribute system

The new system:
- Ragdolls the separate visual rig
- Uses `.Enabled = false` for cleaner restoration
- Uses character attributes directly
- Integrates with the bean physics system
