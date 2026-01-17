# Reorganization Plan

## Current Structure → New Structure

### ✅ Keep As-Is (Already Well Organized):
- `Configs/` - Already perfect
- `ServerScriptService/Services/` - Already perfect
- `StarterPlayerScripts/Controllers/` - Already perfect
- `StarterPlayerScripts/Systems/` - Already perfect
- `StarterPlayerScripts/UI/` - Already perfect

### 🔄 Minor Improvements Needed:

The current structure is actually quite good! The main improvements would be:

1. **Rename `Systems/` to `Gameplay/`** for clarity
   - `ReplicatedStorage/Systems/Movement/` → `ReplicatedStorage/Gameplay/Movement/`
   - `ReplicatedStorage/Systems/Character/` → `ReplicatedStorage/Gameplay/Character/`
   - `ReplicatedStorage/Systems/Round/` → `ReplicatedStorage/Gameplay/Round/`

2. **Move Core systems to top level**
   - `ReplicatedStorage/Systems/Core/` → `ReplicatedStorage/Core/Systems/`
   - `ReplicatedStorage/Modules/` → `ReplicatedStorage/Core/Modules/`

3. **Move Weapons into Gameplay**
   - `ReplicatedStorage/Weapons/` → `ReplicatedStorage/Gameplay/Weapons/`

## ⚠️ Important Considerations:

1. **Locations.lua** - Must be updated to reflect new paths
2. **All require() statements** - Use Locations.lua (already done)
3. **Rojo sync** - Will need to resync after moving files

## 🎯 Recommended Action:

**Option 1: Keep Current Structure** (Recommended)
- Current structure is already well-organized
- Just add better documentation
- Less risk of breaking things

**Option 2: Reorganize** (More work, cleaner structure)
- Move folders as described above
- Update Locations.lua
- Test everything works

## 📋 If Reorganizing:

1. Update `Locations.lua` first
2. Move folders in file system
3. Update any hardcoded paths (should be none if using Locations)
4. Test in Roblox Studio
5. Resync with Rojo

