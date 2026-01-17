# Character Controllers

## 📦 Drag & Drop Ready

All character-related controllers are grouped together in this folder.

## Controllers

- **CharacterController.lua** - Main character movement controller
- **CharacterSetup.lua** - Character initialization and physics setup
- **ClientCharacterSetup.lua** - Visual character setup for all players
- **AnimationController.lua** - Animation playback and management
- **RagdollController.lua** - Ragdoll system handling

## Usage

All controllers are loaded automatically by `Initializer.client.lua`.

## Dependencies

- Controllers use `Locations` for module paths
- Controllers use `RemoteEvents` for networking
- Controllers use `Config` for settings

