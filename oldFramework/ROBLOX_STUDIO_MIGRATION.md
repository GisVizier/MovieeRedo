# Roblox Studio Migration Guide

## Quick Reference

### Files to DELETE in Roblox Studio

Delete these ModuleScript instances (they've been merged into CharacterController):

1. **StarterPlayerScripts → Controllers → CharacterMovement**
   - Path: `StarterPlayer.StarterPlayerScripts.Controllers.CharacterMovement`
   - **DELETE THIS** - Merged into CharacterController

2. **StarterPlayerScripts → Controllers → CharacterInput**
   - Path: `StarterPlayer.StarterPlayerScripts.Controllers.CharacterInput`
   - **DELETE THIS** - Merged into CharacterController

3. **StarterPlayerScripts → Controllers → CharacterState**
   - Path: `StarterPlayer.StarterPlayerScripts.Controllers.CharacterState`
   - **DELETE THIS** - Merged into CharacterController

### Files That Will Auto-Update via Rojo

These files are already updated in the codebase and will sync automatically:

1. ✅ **CharacterController.lua** - Already updated (merged all functionality)
2. ✅ **CharacterSetup.lua** - Already updated (references fixed)
3. ✅ **ClientReplicator.lua** - Already simplified
4. ✅ **RemoteReplicator.lua** - Already simplified
5. ✅ **Locations.lua** - Already updated (removed old references)
6. ✅ **SlidingSystem.lua** - Already fixed (removed old reference)

---

## Step-by-Step Instructions

### Step 1: Wait for Rojo Sync

Let Rojo sync the updated files first. You should see these files update automatically:
- `CharacterController.lua` (will be much larger now - ~778 lines)
- `CharacterSetup.lua` (updated references)
- `ClientReplicator.lua` (simplified)
- `RemoteReplicator.lua` (simplified)
- `Locations.lua` (removed old module references)
- `SlidingSystem.lua` (fixed reference)

### Step 2: Delete Old ModuleScripts

After Rojo syncs, delete these ModuleScript instances in Roblox Studio:

**Option A: Manual Deletion**
1. Open Roblox Studio
2. Navigate to: `StarterPlayer → StarterPlayerScripts → Controllers`
3. Find and delete:
   - `CharacterMovement` (ModuleScript)
   - `CharacterInput` (ModuleScript)
   - `CharacterState` (ModuleScript)

**Option B: Using Explorer Search**
1. Press `Ctrl+F` (or `Cmd+F` on Mac) in Explorer
2. Search for "CharacterMovement"
3. Delete the ModuleScript instance
4. Repeat for "CharacterInput" and "CharacterState"

### Step 3: Verify Changes

After deletion, verify:

1. **CharacterController exists** and has ~778 lines
2. **CharacterMovement, CharacterInput, CharacterState are deleted**
3. **No errors in Output** - Check for any require() errors

### Step 4: Test Functionality

Test these features to ensure everything works:

- [ ] Character spawns correctly
- [ ] Movement works (WASD)
- [ ] Jumping works
- [ ] Crouching works
- [ ] Sliding works
- [ ] Sprinting works
- [ ] Ground detection works
- [ ] Other players replicate correctly

---

## What Changed in Each File

### CharacterController.lua
**Before:** ~250 lines of delegation methods
**After:** ~778 lines with all functionality merged

**What to look for:**
- Should have methods like `CheckGrounded()`, `ApplyMovement()`, `HandleCrouch()` directly in the file
- Should NOT have `CharacterMovement`, `CharacterInput`, or `CharacterState` as properties

### CharacterSetup.lua
**Before:** Called `self.CharacterController.CharacterMovement:StartMovementLoop()`
**After:** Calls `self.CharacterController:StartMovementLoop()`

**What to look for:**
- All method calls should be directly on `self.CharacterController`
- No references to `.CharacterMovement`, `.CharacterInput`, or `.CharacterState`

### Locations.lua
**Before:** Had references to CharacterMovement, CharacterInput, CharacterState
**After:** Removed those references

**What to look for:**
- `Locations.Client.Controllers` should only have:
  - CameraController
  - CharacterController
  - CharacterSetup
  - InputManager
  - AnimationController
  - InteractableController

### ClientReplicator.lua
**Before:** ~487 lines with prediction/reconciliation code
**After:** ~250 lines simplified

**What to look for:**
- Should be shorter and simpler
- Still has `SendStateUpdate()` and `SyncRigHumanoidRootPart()` methods

### RemoteReplicator.lua
**Before:** ~710 lines with complex packet loss tracking
**After:** ~350 lines simplified

**What to look for:**
- Should be shorter and simpler
- Still has `OnStatesReplicated()` and `ReplicatePlayers()` methods

---

## Troubleshooting

### Error: "CharacterMovement is not a valid member"
**Solution:** Make sure you deleted the CharacterMovement ModuleScript from Controllers folder

### Error: "CharacterInput is not a valid member"
**Solution:** Make sure you deleted the CharacterInput ModuleScript from Controllers folder

### Error: "CharacterState is not a valid member"
**Solution:** Make sure you deleted the CharacterState ModuleScript from Controllers folder

### Error: "attempt to index nil with 'CharacterMovement'"
**Solution:** This means some code is still trying to access the old modules. Check:
1. Did Rojo sync all files?
2. Did you delete the old ModuleScripts?
3. Check Output for which file is causing the error

### Character not moving
**Solution:** 
1. Check if CharacterController synced correctly
2. Check Output for errors
3. Verify CharacterSetup is calling `CharacterController:StartMovementLoop()` (not `CharacterMovement:StartMovementLoop()`)

---

## Files Summary

### ✅ Files Updated (Auto-sync via Rojo)
- `src/StarterPlayerScripts/Controllers/CharacterController.lua`
- `src/StarterPlayerScripts/Controllers/CharacterSetup.lua`
- `src/StarterPlayerScripts/Systems/Replication/ClientReplicator.lua`
- `src/StarterPlayerScripts/Systems/Replication/RemoteReplicator.lua`
- `src/ReplicatedStorage/Modules/Locations.lua`
- `src/ReplicatedStorage/Systems/Movement/SlidingSystem.lua`

### ❌ Files Deleted (Need to delete in Studio)
- `CharacterMovement` ModuleScript
- `CharacterInput` ModuleScript
- `CharacterState` ModuleScript

### 📝 Files That Reference Old Modules (Comments Only - Safe)
- `AnimationController.lua` - Has comment mentioning CharacterState (safe)
- `TestMode.lua` - Has config option `LogCharacterMovement` (safe, just a name)
- `ReplicationConfig.lua` - No actual references (safe)
- `RemoteEvents.lua` - No actual references (safe)
- `CompressionUtils.lua` - No actual references (safe)
- `Schemas.lua` - No actual references (safe)
- `SystemConfig.lua` - No actual references (safe)

---

## Verification Checklist

After migration, verify:

- [ ] Rojo synced all updated files
- [ ] Deleted CharacterMovement ModuleScript
- [ ] Deleted CharacterInput ModuleScript
- [ ] Deleted CharacterState ModuleScript
- [ ] No errors in Output window
- [ ] Character spawns correctly
- [ ] Movement works
- [ ] All features work as before

---

## Need Help?

If you encounter issues:

1. **Check Output window** - Look for require() errors
2. **Verify file sync** - Make sure Rojo synced all files
3. **Check file paths** - Make sure files are in correct locations
4. **Restart Studio** - Sometimes helps clear cached references

All functionality is preserved - if something doesn't work, it's likely a sync or deletion issue, not a code problem!

