# Weapon Hit Registration - Testing Guide

## Quick Start Testing

### Step 1: Start the Server
1. Open Roblox Studio
2. Open your project
3. Press **F5** to start a local server with 2 players

**What happens**: WeaponHitService should initialize and log:
```
[WEAPON_HIT] WeaponHitService initialized
[COLLISION] Created hitbox collision group
```

### Step 2: Give Yourself a Weapon (Temporary Test Code)

Since the weapon system isn't fully integrated yet, you'll need to manually create a weapon instance for testing. Add this **temporary test code** to a client controller:

**Option A: Create a test script** (`StarterPlayerScripts/TestWeapon.client.lua`):

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Locations = require(ReplicatedStorage.Modules.Locations)
local WeaponManager = require(Locations.Modules.Weapons.Managers.WeaponManager)

local localPlayer = Players.LocalPlayer

-- Wait for character
localPlayer.CharacterAdded:Connect(function(character)
    -- Wait a bit for character to fully load
    task.wait(2)

    print("[TEST] Creating test weapon...")

    -- Initialize a Revolver weapon instance
    local weaponInstance = WeaponManager:InitializeWeapon(localPlayer, "Gun", "Revolver")

    if weaponInstance then
        print("[TEST] Weapon created successfully!")
        print("[TEST] Press LEFT MOUSE BUTTON to fire")
        print("[TEST] Press R to reload")

        -- Equip the weapon
        WeaponManager:EquipWeapon(localPlayer, weaponInstance)

        -- Fire on mouse click
        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end

            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                WeaponManager:AttackWeapon(localPlayer, weaponInstance)
            elseif input.KeyCode == Enum.KeyCode.R then
                WeaponManager:ReloadWeapon(localPlayer, weaponInstance)
            end
        end)
    else
        warn("[TEST] Failed to create weapon!")
    end
end)
```

**Option B: Use the console** (F9 in Studio):
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Locations = require(ReplicatedStorage.Modules.Locations)
local WeaponManager = require(Locations.Modules.Weapons.Managers.WeaponManager)

local player = Players.LocalPlayer
local weaponInstance = WeaponManager:InitializeWeapon(player, "Gun", "Revolver")

WeaponManager:EquipWeapon(player, weaponInstance)

-- Fire on click
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        WeaponManager:AttackWeapon(player, weaponInstance)
    end
end)
```

### Step 3: Test Shooting

With 2 players in the test server:

1. **Look at the other player**
2. **Click to fire**
3. **Check the Output window** (View → Output)

**Expected output (if HIT)**:
```
[Revolver] Firing for player: Player1
[Revolver] HIT! {
    ["Part"] = "Head",  -- or "Body", "LeftArm", etc.
    ["Distance"] = 45.2,
    ["Headshot"] = true
}
[Revolver] Ammo remaining: 5 / 6

-- Server-side:
[WEAPON_HIT] Valid hit confirmed {
    ["Shooter"] = "Player1",
    ["Target"] = "Player2",
    ["Damage"] = 85,  -- 85 for headshot, 35 for body
    ["Headshot"] = true,
    ["Distance"] = 45.2,
    ["HitPart"] = "Head"
}
```

**Expected output (if MISS)**:
```
[Revolver] Firing for player: Player1
[Revolver] MISS - no hit detected
[Revolver] Ammo remaining: 5 / 6
```

### Step 4: Verify Hit Detection

**What to check**:
- ✅ Client raycast hits the Hitbox parts (Head, Body, Arms, Legs)
- ✅ Client raycast IGNORES Rig parts, Collider parts, terrain
- ✅ Server validates the hit
- ✅ Headshot damage (85) vs body damage (35)
- ✅ Distance-based damage falloff (shoot from far away = less damage)
- ✅ Can't shoot yourself (shooter excluded from raycast)

## Common Issues & Solutions

### Issue 1: "No Hitbox folder found in character"

**Problem**: Character doesn't have a Hitbox folder

**Solution**: Make sure your character template has the Hitbox folder structure:
```
Character (Model)
└── Hitbox (Folder)
    ├── Body (Part)
    ├── Head (Part)
    ├── LeftArm (Part)
    ├── RightArm (Part)
    ├── LeftLeg (Part)
    └── RightLeg (Part)
```

All hitbox parts should have:
- `CanQuery = true`
- `CanCollide = false`
- `CanTouch = true`
- `CollisionGroup = "Hitboxes"`

### Issue 2: Raycast hits nothing

**Problem**: RaycastParams filtering issue

**Check**:
1. Are hitbox parts visible? (Transparency < 1)
2. Do hitbox parts have `CanQuery = true`?
3. Is `RespectCanCollide = false` in RaycastParams?
4. Are there any other players in the game to shoot?

**Debug**: Add visualization to HitscanSystem:
```lua
-- Add to HitscanSystem:PerformRaycast() after the raycast
local beam = Instance.new("Part")
beam.Size = Vector3.new(0.1, 0.1, direction.Magnitude)
beam.CFrame = CFrame.new(origin, origin + direction) * CFrame.new(0, 0, -direction.Magnitude/2)
beam.BrickColor = result and BrickColor.new("Lime green") or BrickColor.new("Really red")
beam.Material = Enum.Material.Neon
beam.Anchored = true
beam.CanCollide = false
beam.Parent = workspace
game:GetService("Debris"):AddItem(beam, 2)
```

### Issue 3: Server rejects all hits

**Problem**: Server validation failing

**Check Output for warnings**:
- "Distance check failed" → Increase `MAX_DISTANCE_TOLERANCE` in WeaponHitService
- "Hit too old" → Check client/server clock sync
- "Hit position mismatch" → Server raycast not matching client

**Temporary fix for testing**: Increase tolerances in WeaponHitService.lua:
```lua
local MAX_DISTANCE_TOLERANCE = 100 -- Was 50
local MAX_TIME_TOLERANCE = 1.0 -- Was 0.5
```

### Issue 4: Weapon not firing

**Problem**: WeaponManager not working

**Check**:
1. Did you create the weapon instance? (`WeaponManager:InitializeWeapon()`)
2. Did you equip it? (`WeaponManager:EquipWeapon()`)
3. Is the player character loaded?
4. Check Output for errors

### Issue 5: "Event not found: WeaponFired"

**Problem**: RemoteEvents not initialized

**Solution**: The RemoteEvents are auto-created by `RemoteEvents:Init()` in RemoteEvents.lua. Make sure:
1. Server has started fully
2. No errors in Output during initialization
3. Check `ReplicatedStorage/RemoteEvents` folder exists with "WeaponFired" RemoteEvent

## Advanced Testing

### Test Distance Falloff

Shoot from different distances and verify damage scaling:

```lua
-- At 0-10 studs: Full damage (35 body, 85 headshot)
-- At 100 studs: ~67.5% damage
-- At 200 studs (max range): 50% damage (17.5 body, 42.5 headshot)
```

### Test Fire Rate

Hold down mouse button and verify RPM limit:
- Revolver: 120 RPM = 0.5 second cooldown between shots
- Should see "Cooldown not ready" messages if firing too fast

### Test Ammo System

Fire 6 shots and verify:
- Ammo goes from 6 → 5 → 4 → 3 → 2 → 1 → 0
- Auto-reload triggers when mag is empty
- Reserve ammo decreases

### Test Multiple Players

With 3+ players:
1. Player A shoots Player B → Should hit
2. Player A shoots Player C → Should hit
3. Player A tries to shoot themselves → Should NOT hit (excluded from raycast)

## Performance Testing

### Check Raycast Performance

Open MicroProfiler (Ctrl+F6 in Studio):
1. Fire weapon rapidly
2. Look for "Raycast" spikes
3. Target: <0.5ms per shot on client, <1ms on server

### Memory Usage

Check if RaycastParams caching works:
- Fire 100 shots
- Memory should NOT increase significantly (params are reused)

## Visual Testing Checklist

Since visual feedback isn't implemented yet, these are TODOs:

- [ ] Bullet tracer appears from gun to hit point
- [ ] Hit marker shows on crosshair when hitting enemy
- [ ] Impact effect (blood/sparks) appears at hit location
- [ ] Muzzle flash shows when firing
- [ ] Camera recoil applies
- [ ] Damage numbers float above target

## Integration Testing

Once health system is implemented:

- [ ] Shooting player reduces their health
- [ ] Headshots do more damage than body shots
- [ ] Player dies at 0 health
- [ ] Killer gets credit for kill
- [ ] Player respawns after death

## Server Authority Testing

Try to exploit (in a safe testing environment):

1. **Speed hack test**: Move very fast and shoot → Server should still validate
2. **Teleport test**: Teleport and shoot → Server should reject if position mismatch is too large
3. **Fake hit test**: Manually send fake hit data via RemoteEvent → Server should reject

**Note**: Full anti-cheat isn't implemented yet, but basic validation (distance/time) should catch obvious exploits.

## Next Steps After Testing

Once basic hit detection works:

1. **Add visual feedback** - Tracers, hit markers, impact effects
2. **Implement health system** - Actually apply damage to players
3. **Add more weapons** - Use Revolver as template for Assault Rifle, Pistol, etc.
4. **Add weapon switching** - Allow players to swap between weapons
5. **Add recoil patterns** - Camera kick for each weapon
6. **Add sounds** - Gun fire, reload, dry fire, hit sounds
7. **Optimize** - Profile and tune performance

## Quick Debug Commands

Add these to your test script for faster iteration:

```lua
-- Give infinite ammo
weaponInstance.State.CurrentAmmo = 999
weaponInstance.State.ReserveAmmo = 999

-- Teleport to another player
local targetPlayer = game.Players:FindFirstChild("Player2")
if targetPlayer and targetPlayer.Character then
    localPlayer.Character:SetPrimaryPartCFrame(
        targetPlayer.Character.PrimaryPart.CFrame * CFrame.new(0, 0, -10)
    )
end

-- Enable raycast visualization
getgenv().DEBUG_RAYCASTS = true

-- Print all hitbox parts
for _, player in pairs(game.Players:GetPlayers()) do
    local hitbox = player.Character and player.Character:FindFirstChild("Hitbox")
    if hitbox then
        print(player.Name, "hitbox parts:", hitbox:GetChildren())
    end
end
```

## Troubleshooting Checklist

Before asking for help, verify:

- [ ] Server started without errors
- [ ] WeaponHitService initialized (check Output)
- [ ] Hitbox collision group registered
- [ ] Character has Hitbox folder
- [ ] Hitbox parts have CanQuery=true, CanCollide=false
- [ ] Weapon instance created successfully
- [ ] RemoteEvent "WeaponFired" exists in ReplicatedStorage
- [ ] Both players are in the same server
- [ ] Shooting from within max range (500 studs default)
- [ ] Looking at the other player when firing
- [ ] No errors in Output window

If all checks pass and it still doesn't work, check the full Output log for warnings/errors and share them for debugging.
