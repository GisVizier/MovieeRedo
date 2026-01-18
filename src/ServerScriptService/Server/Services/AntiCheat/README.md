# Anti-Cheat System

## Overview

This anti-cheat system validates client movement states to prevent common exploits like speed hacking, teleportation, and flying.

## What It Catches

✅ **Speed Hacking** - Players moving faster than 120 studs/second  
✅ **Teleportation** - Instant position changes  
✅ **Flying/NoClip** - Extended airborne time or impossible upward movement  

## How It Works

1. Client sends position/velocity updates (60Hz)
2. Server validates each state against physical limits
3. Invalid states are rejected (not broadcasted to other players)
4. After 6 violations, player is kicked

### Validation Checks

**Speed Check:**
- Maximum velocity: 120 studs/second (accounts for sliding + abilities)
- Rejects: velocity.Magnitude > 120

**Teleport Check:**
- Maximum distance per second: 150 studs
- Rejects: position_delta > (150 * deltaTime)

**Flight Check:**
- Maximum airborne time: 3.0 seconds
- Maximum upward velocity (while airborne >1s): 20 studs/sec
- Rejects: extended flight or impossible upward movement

## Configuration

Edit constants in `MovementValidator.lua`:

```lua
local MAX_SPEED = 120 -- Increase if legit players trigger
local MAX_DISTANCE_PER_SEC = 150 -- Tighten for stricter detection
local MAX_AIRBORNE_TIME = 3.0 -- Account for slide jump combos
local MAX_AIRBORNE_UPWARD_VEL = 20 -- Jump cancel vertical boost
```

## Tuning Guide

### If Legitimate Players Are Getting Kicked:

1. **Check logs** for violation type
2. **Increase tolerance:**
   - Speed violations → Increase `MAX_SPEED` by 10-20
   - Teleport violations → Increase `MAX_DISTANCE_PER_SEC` by 20-30
   - Flight violations → Increase `MAX_AIRBORNE_TIME` by 0.5s

### If Exploiters Are Bypassing:

1. **Decrease tolerances** (more strict)
2. **Review violation thresholds:**
   ```lua
   if data.Violations >= 6 then -- Lower to 4-5 for faster kicks
   ```

## Testing

### Normal Gameplay Test:
1. Play normally for 5 minutes
2. Try all movement mechanics (slide, jump cancel, wall jump)
3. Check console - should see no violations

### Exploit Simulation Test:
1. Set a test script to modify velocity to 500
2. Should see violation warnings in console
3. After 6 violations, player should be kicked

## Monitoring

Check server console for violation warnings:
```
[AntiCheat] PlayerName (12345) - Speed violation: 245.3 (Total violations: 1)
[AntiCheat] PlayerName (12345) - Teleport violation: 320.8 (Total violations: 2)
```

## Limitations

- **Cannot catch subtle exploits** (speeds just under limit)
- **Client-side hacks undetectable** (ESP, aimbot)
- **Requires tuning** based on your game's mechanics

## Integration

Already integrated into `ReplicationService.lua`:
- Initialized in `ReplicationService:Init()`
- Validates in `ReplicationService:OnClientStateUpdate()`
- Invalid states are silently rejected

## Performance

- **CPU Impact:** <1% (simple math checks)
- **Memory:** ~100 bytes per player
- **Network:** No additional network traffic
