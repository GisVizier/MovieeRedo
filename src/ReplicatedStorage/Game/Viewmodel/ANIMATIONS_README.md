# Viewmodel Animation System

## Overview

The viewmodel animation system supports **Animation instances** directly from your assets, eliminating the need to publish animations to Roblox and use asset IDs.

## Animation Loading Priority

The system uses a **hybrid approach**:

1. **First**: Try to load Animation instance from `ReplicatedStorage.Assets.Animations.ViewModel.{WeaponId}.Viewmodel.{AnimName}`
2. **Fallback**: If not found, treat as asset ID (`rbxassetid://...`)

## Supported Animations

### **Movement Animations** (Auto-playing, looped)
- `Idle` - Standing still
- `Walk` - Walking (velocity 1-10 studs/sec)
- `Run` - Sprinting (velocity >10 studs/sec)

### **Action Animations** (Triggered)
- `Fire` - Plays when shooting (0.2-0.4s duration)
- `Reload` - Plays when pressing R key (matches weapon.reloadTime)
- `Inspect` - Plays when pressing F key (cosmetic)
- `ADS` - Aim Down Sights (looped, not yet implemented)
- `Equip` - Plays when switching to weapon (not yet implemented)

## How to Add Animations

### Method 1: Using Animation Instances (Recommended)

1. Place your animations in this structure:
```
ReplicatedStorage
  └─ Assets
     └─ Animations
        └─ ViewModel
           └─ Shotgun
              └─ Viewmodel  <-- This folder is important!
                 ├─ Idle (Animation)
                 ├─ Walk (Animation)
                 ├─ Run (Animation)
                 ├─ Fire (Animation)
                 ├─ Aim (Animation)
                 └─ Inspect (Animation)
```

2. Update `ViewmodelConfig.lua`:
```lua
Shotgun = {
    Animations = {
        Idle = "Idle",      -- Loads from Assets/Animations/ViewModel/Shotgun/Viewmodel/Idle
        Walk = "Walk",
        Run = "Run",
        Fire = "Fire",
        ADS = "Aim",        -- Maps "ADS" to Animation instance named "Aim"
        Inspect = "Inspect",
    },
},
```

3. Done! The system automatically loads the instances.

### Method 2: Using Asset IDs (Legacy)

```lua
Revolver = {
    Animations = {
        Idle = "rbxassetid://109130838280246",
        Fire = "rbxassetid://116676760515163",
        -- etc...
    },
},
```

## Current Weapon Status

| Weapon | Method | Status |
|--------|--------|--------|
| **Shotgun** | Animation Instances | ✅ Ready to use |
| **Revolver** | Asset IDs | ✅ Working |
| **AssaultRifle** | Placeholders | ⚠️ Needs animations |
| **Sniper** | Placeholders | ⚠️ Needs animations |

## Controls

| Key | Action | Description |
|-----|--------|-------------|
| **Mouse1** | Fire | Shoot weapon |
| **R** | Reload | Reload weapon (2.0s for Shotgun) |
| **F** | Inspect | Play inspect animation |
| **1-4** | Switch | Switch weapon slots |

## Animation Behavior

### Fire Animation
- **Triggered**: When you click to shoot
- **Blending**: 0.05s fade (instant feel)
- **Restart**: Yes (interrupts previous fire)
- **Looped**: No
- **Priority**: Action

### Reload Animation  
- **Triggered**: Press R key
- **Duration**: Matches `weaponConfig.reloadTime`
- **Blocks firing**: Yes
- **Blocks movement**: No
- **Looped**: No

### Inspect Animation
- **Triggered**: Press F key
- **Blocks firing**: No
- **Cosmetic only**: Yes
- **Can be interrupted**: Yes (by fire/reload)

### Movement Animations (Auto)
- **Idle/Walk/Run**: Smooth crossfade (0.18s)
- **Weight-based blending**: Multiple anims play simultaneously
- **Speed-based switching**: Automatic based on velocity
- **Grounded check**: Walk only when grounded, Run works in air

## Troubleshooting

### "Animation not playing"
- ✅ Check folder structure matches exactly: `ViewModel/{WeaponId}/Viewmodel/{AnimName}`
- ✅ Verify Animation instance exists in Studio explorer
- ✅ Check console for errors

### "Animation loads but doesn't animate"
- ✅ Verify the Animation has keyframes
- ✅ Check the rig has an AnimationController + Animator
- ✅ Ensure animation targets the correct rig hierarchy

### "Fire animation keeps looping"
- ✅ The Fire animation is marked as non-looping automatically
- ✅ Check the Animation instance's Loop property is false

## Next Steps

To complete the system:
1. ⬜ Add Equip animation trigger (plays when switching weapons)
2. ⬜ Add ADS (Aim) toggle system
3. ⬜ Add muzzle flash VFX on fire
4. ⬜ Add recoil camera shake
5. ⬜ Add fire/reload sound effects
6. ⬜ Migrate Revolver/AR/Sniper to Animation instances
