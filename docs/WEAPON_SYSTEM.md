# Weapon System (Client)

## Overview
The client weapon flow lives in `WeaponController` and delegates weapon-specific behavior to
action modules (e.g., Shotgun). Viewmodel animations are played through `ViewmodelAnimator`
and loaded from animation instances in `Assets`.

## Key Components
- **WeaponController**: Input routing, ammo state, HUD updates, networking, tracer hooks.
- **Action Modules**: `ReplicatedStorage/Game/Weapons/Actions/...` (Shotgun Attack/Reload/etc.).
- **ViewmodelController/ViewmodelAnimator**: Loads and plays viewmodel animations based on
  config + animation instance attributes.
- **LoadoutConfig/ViewmodelConfig**: Weapon stats and animation mapping.

## Weapon Flow (Fire)
1. Input → `WeaponController:_onFirePressed()`
2. Shotgun uses `Shotgun.Attack.Execute(weaponInstance)`
3. `Attack` handles ammo, plays animation, performs raycast
4. Sends `WeaponFired` to server for validation
5. Local VFX plays immediately (client prediction)
6. Server confirm triggers tracer/hitmarker (optional)

## Weapon Flow (Reload – Shotgun)
1. Input → `WeaponController:Reload()`
2. Shotgun uses `Shotgun.Reload.Execute(weaponInstance)`
3. Reload plays **Start → Action (per shell) → End**
4. Ammo updates per shell; HUD updated via `ApplyState`

## Animation System
Animations are loaded from:
`ReplicatedStorage/Assets/Animations/ViewModel/{WeaponId}/Viewmodel/{AnimName}`

Attributes on animation instances drive behavior:
- `Loop` (bool)
- `Priority` (string, e.g. Action/Core)
- `FadeInTime` (number)
- `FadeOutTime` (number)
- `Weight` (number)

## Tracers / VFX
- Current tracer uses a Part + fade loop (simple, heavier cost).
- Local prediction can show tracer immediately via `RenderTracer`.
- Server confirm can also show tracers for validation/observers.
- Recommended optimization: use Beams or object pooling.

## Debug
- `DEBUG_WEAPON` gates verbose weapon logs.
- `DEBUG_VIEWMODEL` gates viewmodel animation logs.
- `SHOW_TRACERS` toggles tracer rendering.
