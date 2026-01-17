# Client Controllers

## 📦 Drag & Drop Ready - Organized by Category

Controllers are organized into folders by category. Each folder can be moved independently.

## Folder Structure

### 🎮 Character/
All character-related controllers:
- **CharacterController.lua** - Main character movement controller
- **CharacterSetup.lua** - Character initialization and setup
- **ClientCharacterSetup.lua** - Visual character setup for all players
- **AnimationController.lua** - Animation playback and management
- **RagdollController.lua** - Ragdoll system handling

### ⌨️ Input/
All input-related controllers:
- **InputManager.lua** - Multi-platform input handling (keyboard, mouse, touch, controller)
- **MovementInputProcessor.lua** - Movement input processing

### 🔫 Weapon/
All weapon-related controllers:
- **WeaponController.lua** - Weapon handling and shooting
- **ViewmodelController.lua** - First-person viewmodel management
- **InventoryController.lua** - Weapon switching and loadout

### 📷 Camera/
Camera controller:
- **CameraController.lua** - First-person camera system

### 🎯 Interaction/
Interaction controller:
- **InteractableController.lua** - Interaction system

## Usage

All controllers are loaded by `Initializer.client.lua` and registered in `ServiceRegistry`.
The `ServiceLoader` automatically searches subfolders, so controllers work regardless of folder structure.

## Dependencies

- Controllers use `Locations` for module paths
- Controllers use `RemoteEvents` for networking
- Controllers use `Config` for settings

