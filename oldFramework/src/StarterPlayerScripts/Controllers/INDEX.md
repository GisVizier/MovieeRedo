# Controllers Index - Quick Reference

## 🎯 All Controllers in This Folder

Each controller is **independent** and can be moved individually.

### 📋 Core Controllers (Load First)

| Controller | Purpose | When It Runs |
|------------|---------|--------------|
| **InputManager** | Multi-platform input (keyboard, mouse, touch, controller) | Always active |
| **CameraController** | First-person camera system | Always active |

### 🎮 Character Controllers

| Controller | Purpose | When It Runs |
|------------|---------|--------------|
| **CharacterController** | Main character movement controller | When character spawns |
| **CharacterSetup** | Character initialization and physics setup | When character spawns |
| **ClientCharacterSetup** | Visual character setup for all players | When any character spawns |
| **AnimationController** | Animation playback and management | When character spawns |
| **RagdollController** | Ragdoll system handling | On death/ragdoll |

### 🔫 Weapon Controllers

| Controller | Purpose | When It Runs |
|------------|---------|--------------|
| **WeaponController** | Weapon handling, shooting, reloading | When character spawns |
| **ViewmodelController** | First-person viewmodel (weapon in hand) | When weapon equipped |
| **InventoryController** | Weapon switching, loadout management | When character spawns |

### 🎯 Interaction Controllers

| Controller | Purpose | When It Runs |
|------------|---------|--------------|
| **InteractableController** | Interaction system (doors, buttons, etc.) | Always active |
| **MovementInputProcessor** | Processes movement input | Always active |

## 🔄 Controller Loading Order

Controllers are loaded in this order (set in `Initializer.client.lua`):

1. **InputManager** - Input system (needed by others)
2. **CameraController** - Camera system
3. **CharacterController** - Main character controller
4. **AnimationController** - Animation system
5. **InteractableController** - Interactions
6. **ClientCharacterSetup** - Visual setup
7. **ViewmodelController** - Viewmodel
8. **WeaponController** - Weapons
9. **RagdollController** - Ragdoll
10. **InventoryController** - Inventory
11. **CharacterSetup** - Character setup
12. **MovementInputProcessor** - Movement input

## 📦 Drag & Drop Ready

✅ Each controller is **independent** - you can move any controller file individually
✅ Controllers use `ServiceRegistry` to find each other
✅ Controllers use `Locations` for module paths (no hardcoded paths)

## 🎯 Quick Find

| Need to... | Controller |
|------------|------------|
| Change input bindings | `InputManager` |
| Change camera settings | `CameraController` |
| Modify movement | `CharacterController` |
| Add animations | `AnimationController` |
| Add weapon | `WeaponController` |
| Change viewmodel | `ViewmodelController` |
| Modify inventory | `InventoryController` |
| Add interaction | `InteractableController` |

## ⚙️ How Controllers Work

1. **Initialization** - Each controller has an `Init()` function
2. **Character Spawn** - Controllers connect to character via `OnCharacterSpawned()`
3. **Character Remove** - Controllers cleanup via `OnCharacterRemoving()`
4. **Service Registry** - Controllers can find each other via `ServiceRegistry`

## 📝 Adding a New Controller

1. Create new controller file in this folder
2. Add to `controllers` list in `Initializer.client.lua`
3. Controller will auto-load and initialize
4. Use `ServiceRegistry:GetController("Name")` to access from other controllers

