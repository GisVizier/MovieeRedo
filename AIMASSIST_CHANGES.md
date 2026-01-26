# Aim Assist System Changes

## Summary

Transformed the aim assist from a **jarring snap system** to a **smooth, tiered magnetic pull** that:
- Respects your camera sensitivity
- Scales based on your action state (idle/ADS/firing/both)
- Provides continuous gentle assistance instead of instant corrections

---

## What Changed

### 1. **Removed Snap Behavior**
- **Before**: Instantly rotated camera when entering ADS (Fortnite-style snap)
- **After**: Smooth continuous pull that feels like magnetic drift
- All weapon configs now have `adsSnap.enabled = false`

### 2. **Added Tiered State System**
The system now scales strength based on what you're doing:

| State | Multiplier | When Active |
|-------|------------|-------------|
| **Idle** | 0.3x | Just holding weapon |
| **Firing Only** | 0.7x | Shooting but not ADS |
| **ADS Only** | 1.0x | Aiming down sights |
| **ADS + Firing** | 1.0x + ADS Boost | Both (strongest) |

**Example**: Base centering of 0.1
- Idle: 0.03 pull strength (gentle)
- Firing: 0.07 pull strength (medium)
- ADS: 0.1 pull strength (normal)
- ADS + Firing: 0.15 pull strength (0.1 × 1.5 boost = strongest)

### 3. **Sensitivity Integration**
- Lower camera sensitivity = proportionally gentler pull
- Formula: `pullStrength = baseStrength × stateMultiplier × sensitivityMultiplier`
- Ensures aim assist never overpowers your input

### 4. **Reduced Base Values**
Lowered centering values for smoother magnetic feel:

| Weapon | Old Centering | New Centering | Feel |
|--------|--------------|---------------|------|
| Sniper | 0.3 | 0.08 | Precise drift |
| AR | 0.4 | 0.1 | Balanced pull |
| Shotgun | 0.5 | 0.12 | Stronger close-range |
| Revolver | 0.35 | 0.09 | Gentle nudge |

---

## How It Works Now

### When You Equip a Weapon
```
✓ Gentle idle pull (30% strength)
  - Barely noticeable
  - Won't interfere with exploration
```

### When You Start Shooting
```
✓ Stronger pull activates (70% strength)
  - Helps track moving targets
  - Still respects your control
```

### When You ADS
```
✓ Full pull strength (100% + boost)
  - NO snap/jerk
  - Smooth magnetic drift toward target
  - Gets stronger while firing
```

### When You ADS + Fire
```
✓ Maximum assistance (100% + 1.5x boost)
  - Strongest pull to help you stay on target
  - Still smooth, never snaps
  - Scales with your sensitivity
```

---

## Technical Implementation

### Files Modified

1. **[AimAssistConfig.lua](src/ReplicatedStorage/Game/AimAssist/AimAssistConfig.lua)**
   - Added `StateMultipliers` for tiered system

2. **[AimAssist/init.lua](src/ReplicatedStorage/Game/AimAssist/init.lua)**
   - Added state tracking (`isADS`, `isFiring`)
   - Added `sensitivityMultiplier`
   - New methods: `setADSState()`, `setFiringState()`, `setSensitivityMultiplier()`
   - Updated strength calculation to use state + sensitivity

3. **[WeaponController.lua](src/StarterPlayer/StarterPlayerScripts/Initializer/Controllers/Weapon/WeaponController.lua)**
   - Removed snap logic from `_updateAimAssistADS()`
   - Added firing state tracking in `_onFirePressed()` and `_stopAutoFire()`
   - Added `_updateAimAssistSensitivity()` method
   - Now passes ADS/firing states to aim assist

4. **[LoadoutConfig.lua](src/ReplicatedStorage/Configs/LoadoutConfig.lua)**
   - Disabled snap on all weapons
   - Reduced centering values (0.08-0.12 range)
   - Adjusted friction/tracking for balance

### State Flow

```
Player Action → WeaponController → AimAssist
              ↓
    Updates state flags (isADS, isFiring)
              ↓
    Calculates state multiplier
              ↓
    Applies: base × state × sensitivity × easing
              ↓
    Smooth magnetic pull applied to camera
```

---

## Configuration Guide

### Adjusting Pull Strength

**To make aim assist stronger:**
```lua
-- In LoadoutConfig.lua weapon config
centering = 0.15,  -- Increase from 0.1
```

**To make it gentler:**
```lua
centering = 0.05,  -- Decrease from 0.1
```

### Adjusting State Multipliers

**In AimAssistConfig.lua:**
```lua
StateMultipliers = {
    Idle = 0.3,        -- 30% when just holding
    Firing = 0.7,      -- 70% when shooting
    ADS = 1.0,         -- 100% when aiming
    ADSFiring = 1.0,   -- 100% + boost when both
}
```

### Adjusting ADS Boost

**In weapon config:**
```lua
adsBoost = {
    Friction = 1.4,    -- 40% stronger slowdown
    Tracking = 1.3,    -- 30% stronger following
    Centering = 1.5,   -- 50% stronger pull
},
```

---

## Testing Checklist

- [ ] Idle: Gentle pull doesn't interfere with normal movement
- [ ] Firing: Pull activates smoothly, helps track targets
- [ ] ADS: Pull strengthens without snapping
- [ ] ADS + Firing: Maximum assistance feels responsive
- [ ] Low sensitivity: Pull scales down appropriately
- [ ] High sensitivity: Pull scales up appropriately
- [ ] All weapons: No jarring snaps, smooth magnetic feel

---

## Future Improvements

1. **Player-customizable sensitivity**: Allow players to set camera sens in settings
2. **Per-method state multipliers**: Different multipliers for friction/tracking/centering
3. **Distance-based scaling**: Gentler pull at long range, stronger at close range
4. **Velocity prediction**: Lead moving targets slightly for projectile weapons
