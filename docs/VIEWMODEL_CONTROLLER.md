# ViewmodelController

First-person viewmodel system for displaying weapon models attached to the camera.

## Overview

The ViewmodelController manages first-person viewmodel rigs that render weapons from the player's perspective. It handles:

- Creating and caching viewmodel rigs for the player's loadout
- Preloading models and animations for instant weapon switching
- Spring-based visual effects (sway, bob, tilt)
- Kit ability animations (played on the Fists rig)
- ADS (aim down sights) integration

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     ViewmodelController                          │
├─────────────────────────────────────────────────────────────────┤
│  Rig Management                                                  │
│  ├── _rigStorage (Folder at ReplicatedStorage)                  │
│  ├── _storedRigs { Fists, Primary, Secondary, Melee }           │
│  └── _cachedKitTracks { [kitId] = { Ability, Ultimate } }       │
├─────────────────────────────────────────────────────────────────┤
│  Visual Effects (Springs)                                        │
│  ├── rotation (camera sway)                                      │
│  ├── bob (walk/run head bob)                                     │
│  ├── tiltRot/tiltPos (slide tilt)                               │
│  └── externalPos/externalRot (SetOffset)                        │
├─────────────────────────────────────────────────────────────────┤
│  Animation                                                       │
│  ├── ViewmodelAnimator (movement animations)                    │
│  └── Kit animation tracks (ability/ultimate)                    │
└─────────────────────────────────────────────────────────────────┘
```

## Lifecycle

```
Init() → Start() → CreateLoadout() → SetActiveSlot() → [gameplay] → Destroy()
                        │
                        ├── _destroyAllRigs()
                        ├── _createAllRigsForLoadout()
                        │   ├── Create Fists rig
                        │   ├── Create Primary rig
                        │   ├── Create Secondary rig
                        │   ├── Create Melee rig
                        │   ├── PreloadRig() for each
                        │   └── _preloadKitAnimations()
                        └── ContentProvider:PreloadAsync()
```

## Public API

### Init(registry, net)

Initializes the controller with the service registry and network layer.

```lua
ViewmodelController:Init(registry, net)
```

**Parameters:**
- `registry` - Service registry for accessing other controllers
- `net` - Network layer for listening to server events

**Behavior:**
- Creates ViewmodelAnimator instance
- Initializes spring effects
- Listens for `StartMatch` and `KitState` network events
- Listens for `SelectedLoadout` attribute changes on LocalPlayer
- Sets up equip hotkeys (1, 2, 3)

---

### Start()

Called after all controllers have initialized. Currently a no-op.

```lua
ViewmodelController:Start()
```

---

### CreateLoadout(loadout)

Creates viewmodel rigs for the given loadout. Destroys existing rigs first.

```lua
ViewmodelController:CreateLoadout({
    Primary = "Shotgun",
    Secondary = "Revolver",
    Melee = "Knife",
    Kit = "WhiteBeard"
})
```

**Parameters:**
- `loadout` - Table with weapon IDs for Primary, Secondary, Melee slots

**Behavior:**
1. Destroys all existing rigs via `_destroyAllRigs()`
2. Creates new rigs via `_createAllRigsForLoadout()`
   - Fists (always created as fallback)
   - Primary, Secondary, Melee (if present in loadout)
3. Preloads all animations via `ViewmodelAnimator:PreloadRig()`
4. Preloads kit animations via `_preloadKitAnimations()`
5. Calls `ContentProvider:PreloadAsync()` for models
6. Equips Primary slot by default

---

### SetActiveSlot(slot)

Switches to a different weapon slot. Handles equip animations and HUD updates.

```lua
ViewmodelController:SetActiveSlot("Secondary")
```

**Parameters:**
- `slot` - One of: `"Primary"`, `"Secondary"`, `"Melee"`, `"Fists"`

**Behavior:**
- Falls back to `"Fists"` if slot doesn't exist
- Unparents all inactive rigs
- Parents active rig to camera (if in first-person)
- Binds animator to active rig (uses preloaded tracks)
- Plays equip animation
- Updates `EquippedSlot` attribute on LocalPlayer for HUD

---

### GetActiveSlot()

Returns the currently equipped slot name.

```lua
local slot = ViewmodelController:GetActiveSlot()
-- Returns: "Primary", "Secondary", "Melee", or "Fists"
```

---

### GetActiveRig()

Returns the ViewmodelRig for the currently equipped slot.

```lua
local rig = ViewmodelController:GetActiveRig()
-- rig.Model - The viewmodel Model instance
-- rig.Animator - The Animator instance
-- rig.Anchor - The anchor BasePart for positioning
```

---

### GetRigForSlot(slot)

Returns the ViewmodelRig for a specific slot.

```lua
local fistsRig = ViewmodelController:GetRigForSlot("Fists")
```

**Parameters:**
- `slot` - One of: `"Primary"`, `"Secondary"`, `"Melee"`, `"Fists"`

---

### PlayViewmodelAnimation(name, fade?, restart?)

Plays an animation on the current viewmodel.

```lua
ViewmodelController:PlayViewmodelAnimation("Fire", 0.05, true)
```

**Parameters:**
- `name` - Animation name (e.g., "Idle", "Walk", "Fire", "Reload")
- `fade` - Fade time in seconds (default: 0.1)
- `restart` - If true, restarts the animation if already playing

---

### PlayWeaponTrack(name, fade?)

Plays an animation and returns the AnimationTrack for further control.

```lua
local track = ViewmodelController:PlayWeaponTrack("Reload", 0.1)
if track then
    track.Stopped:Once(function()
        -- Reload finished
    end)
end
```

**Parameters:**
- `name` - Animation name
- `fade` - Fade time in seconds (default: 0.1)

**Returns:** `AnimationTrack` or `nil`

---

### SetOffset(offset)

Applies a CFrame offset to the viewmodel with smooth spring interpolation.

```lua
local resetOffset = ViewmodelController:SetOffset(CFrame.new(0, -0.1, 0.2))

-- Later, reset the offset:
resetOffset()
```

**Parameters:**
- `offset` - CFrame offset to apply

**Returns:** Function to reset the offset back to zero

---

### updateTargetCF(func)

Overrides the viewmodel's target CFrame calculation. Used for ADS.

```lua
local resetADS = ViewmodelController:updateTargetCF(function(normalAlign, baseOffset)
    return {
        align = adsAlignCFrame,
        blend = adsBlend,  -- 0 = hip, 1 = full ADS
        effectsMultiplier = 0.25  -- Reduce bob/sway in ADS
    }
end)

-- Later, exit ADS:
resetADS()
```

**Parameters:**
- `func` - Function receiving `(normalAlign, baseOffset)` and returning:
  - `{ align = CFrame, blend = number, effectsMultiplier = number }` for blended ADS
  - Or a raw CFrame for legacy behavior

**Returns:** Function to reset back to normal hip-fire

---

### Destroy()

Cleans up all resources when the controller is destroyed.

```lua
ViewmodelController:Destroy()
```

**Behavior:**
- Disconnects all event connections
- Unbinds render loop
- Destroys all cached rigs
- Destroys storage folder
- Unbinds animator

---

## Internal Functions

### _ensureRigStorage()

Creates or returns the storage folder for preloading rigs off-screen.

- Location: `ReplicatedStorage.ViewmodelRigStorage`
- Rigs stored at position `(0, 10000, 0)`

---

### _destroyAllRigs()

Destroys all stored rigs and clears the kit animation cache.

Called by `CreateLoadout()` before creating new rigs.

---

### _createAllRigsForLoadout(loadout)

Creates all rigs for a loadout with full preloading:

1. Creates Fists, Primary, Secondary, Melee rigs
2. Positions rigs at `(0, 10000, 0)` in storage folder
3. Preloads weapon animations via `ViewmodelAnimator:PreloadRig()`
4. Preloads kit animations via `_preloadKitAnimations()`
5. Calls `ContentProvider:PreloadAsync()` for all model assets

---

### _preloadKitAnimations(fistsRig)

Preloads all kit animations from `ViewmodelConfig.Kits` on the Fists rig.

- Caches tracks in `_cachedKitTracks[kitId].Ability[animName]`
- Caches tracks in `_cachedKitTracks[kitId].Ultimate[animName]`
- Primes tracks by playing/stopping at weight 0

---

### _playKitAnim(kitId, abilityType, name)

Plays a kit animation, using cached tracks if available.

```lua
-- Called internally by _onLocalAbilityBegin/_onLocalAbilityEnd
self:_playKitAnim("WhiteBeard", "Ability", "Charge")
```

---

### _render(dt)

Per-frame render loop that positions the viewmodel based on camera and spring effects.

- Runs at `RenderPriority.Camera + 11` (after CameraController)
- Applies rotation sway from camera movement
- Applies walk/run bob based on velocity
- Applies slide tilt when sliding
- Blends hip and ADS targets when `_targetCFOverride` is set

---

## Spring Effects Configuration

Springs provide smooth, responsive visual feedback. Configuration constants:

| Spring | Speed | Damper | Purpose |
|--------|-------|--------|---------|
| rotation | 18 | 0.85 | Camera sway |
| bob | 14 | 0.85 | Walk/run head bob |
| tiltRot | 12 | 0.9 | Slide rotation |
| tiltPos | 12 | 0.9 | Slide position tuck |
| externalPos | 12 | 0.85 | SetOffset position |
| externalRot | 12 | 0.85 | SetOffset rotation |

**Movement Effects:**
- `ROTATION_SENSITIVITY = -3.2` - Camera delta multiplier
- `BOB_FREQ = 6` - Walk bob frequency
- `BOB_AMP_X = 0.04`, `BOB_AMP_Y = 0.03` - Walk bob amplitude
- `SLIDE_ROLL = 14°`, `SLIDE_PITCH = 6°` - Slide tilt angles
- `SLIDE_TUCK = (0.12, -0.12, 0.18)` - Slide position offset

---

## Kit Integration

Kit abilities (Ability/Ultimate) use the Fists viewmodel for animations:

1. When ability activates: `SetActiveSlot("Fists")`
2. Play kit animation: `_playKitAnim(kitId, "Ability", "Charge")`
3. When ability ends: Play "Release" animation
4. Return to previous slot

**Kit animations are preloaded** when `CreateLoadout()` is called:
- All kits from `ViewmodelConfig.Kits` are preloaded
- Animations are cached in `_cachedKitTracks`
- `_playKitAnim()` uses cached tracks for instant playback

---

## Preloading System

The preloading system ensures instant weapon switching with no loading stutter:

```
CreateLoadout()
├── _createAllRigsForLoadout()
│   ├── Clone model from ReplicatedStorage.Assets.ViewModels
│   ├── Position at (0, 10000, 0) off-screen
│   ├── ViewmodelAnimator:PreloadRig()
│   │   ├── Load all animation tracks
│   │   └── Prime tracks (play/stop at weight 0)
│   └── Collect MeshParts/Decals/Textures
├── _preloadKitAnimations()
│   ├── Load all kit ability/ultimate animations
│   └── Cache tracks in _cachedKitTracks
└── ContentProvider:PreloadAsync() (async)
    └── Preload all model/animation assets
```

**Benefits:**
- Zero stutter when switching weapons
- Instant kit ability animations
- Models fully loaded before first equip

---

## Related Files

- `ViewmodelConfig.lua` - Model paths, offsets, animation IDs
- `ViewmodelAnimator.lua` - Animation playback and movement states
- `ViewmodelRig.lua` - Rig wrapper class
- `ViewmodelAppearance.lua` - Shirt/appearance binding
- `ViewmodelEffects.lua` - Visual effects utilities
- `Spring.lua` - Spring physics for smooth interpolation
