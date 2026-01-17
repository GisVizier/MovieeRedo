# Configuration Files

## 📋 All Game Settings

All configuration files are in this folder. Keep them together for easy access.

## Config Files

- **GameplayConfig.lua** - Movement speeds, physics, character settings
- **ControlsConfig.lua** - Input bindings, camera settings, sensitivity
- **SystemConfig.lua** - Network settings, debug options, logging
- **HealthConfig.lua** - Health system settings
- **AnimationConfig.lua** - Animation IDs and settings
- **WeaponConfig.lua** - Weapon settings
- **LoadoutConfig.lua** - Weapon slots (Primary/Secondary)
- **ViewmodelConfig.lua** - First-person viewmodel settings
- **ReplicationConfig.lua** - Network replication settings
- **RoundConfig.lua** - Round system settings
- **InteractableConfig.lua** - Interaction settings
- **AudioConfig.lua** - Sound settings

## Usage

All configs are loaded by `ConfigCache` and accessible via `require(Locations.Modules.Config)`.

## Modifying Settings

Just edit the config file directly. Changes take effect on next game start.

