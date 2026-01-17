# Weapon System

## 📦 Drag & Drop Ready

This folder contains the complete weapon system. You can move this entire folder independently.

## What's Inside

- **Actions/** - Weapon action scripts
  - **Gun/** - Gun weapons (Shotgun, AssaultRifle, SniperRifle, Revolver)
  - **Melee/** - Melee weapons (Knife)
- **Configs/** - Weapon configuration files
- **Managers/** - Weapon management system
- **Systems/** - Hit detection and weapon animations

## Usage

Weapons are managed by `WeaponController` on the client and `WeaponHitService` on the server.

## Adding New Weapons

1. Create weapon config in `Configs/`
2. Create weapon actions in `Actions/[Type]/[WeaponName]/`
3. Add to `LoadoutConfig` if needed

## Dependencies

- Uses `Config.Weapon` for settings
- Uses `Locations` for module paths
