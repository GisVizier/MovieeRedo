# R6IKSolver — Inverse Kinematics for Roblox R6 Characters

A production-ready, **client-side only** inverse kinematics solver for R6 rigs. Drives arms, legs, and torso pitch using a 2-joint Law of Cosines solver. Designed for aim systems, procedural animation, and custom rig overlays.

---

## Integration Checklist

| Step | Action |
|------|--------|
| 1 | Copy `R6IKSolver.luau` → ReplicatedStorage |
| 2 | Copy `R6IK_Bootstrap.client.lua` → StarterPlayerScripts (or use Quick Start code below) |
| 3 | Set **StarterPlayer > Character > RigType** = R6 |
| 4 | Play (arms use Solver attachments if present, else mouse) |

---

## Quick Start (Drag & Drop)

### 1. Copy the module
- Copy `R6IKSolver.luau` into **ReplicatedStorage** (or any shared location).

### 2. Add a LocalScript
Create a **LocalScript** in `StarterPlayer > StarterPlayerScripts`, or copy `R6IK_Bootstrap.client.lua`. The bootstrap drives arms toward **Solver** attachment positions (`Left Arm.Solver`, `Right Arm.Solver`) on a child model; if none found, it falls back to mouse.

```lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local R6IKSolver = require(ReplicatedStorage:WaitForChild("R6IKSolver"))

local player = Players.LocalPlayer
local ik = nil

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Torso")
	character:WaitForChild("HumanoidRootPart")
	
	-- R6 only
	if character:FindFirstChildOfClass("Humanoid").RigType ~= Enum.HumanoidRigType.R6 then
		return
	end
	
	ik = R6IKSolver.new(character)
	ik:setEnabled("RightArm", true)
	ik:setEnabled("LeftArm", true)
end)

RunService.RenderStepped:Connect(function(dt)
	if not ik then return end
	local char = player.Character
	if not char then return end
	
	local mouse = player:GetMouse()
	local torso = char:FindFirstChild("Torso")
	if not torso then return end
	
	-- Raycast for mouse world position
	local ray = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500)
	local target = result and result.Position or (ray.Origin + ray.Direction * 10)
	
	-- Pole: behind character, slightly down (elbow direction)
	local pole = torso.Position + torso.CFrame.LookVector * -2 + Vector3.new(0, -1, 0)
	
	ik:setArmTarget("Right", target, pole)
	ik:setArmTarget("Left", target, pole)
	ik:update(dt)
end)
```

### 3. Set avatar to R6
In **StarterPlayer > Character > RigType**, set to **R6**.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| **Rig type** | R6 only (not R15) |
| **Character structure** | Standard R6: `Torso`, `HumanoidRootPart`, `Left Arm`, `Right Arm`, `Left Leg`, `Right Leg` |
| **Motor6Ds** | `Torso["Left Shoulder"]`, `Torso["Right Shoulder"]`, `Torso["Left Hip"]`, `Torso["Right Hip"]`, `HumanoidRootPart["RootJoint"]` |
| **Run context** | Client (LocalScript) only |

---

## Full API Reference

### Constructor

```lua
local ik = R6IKSolver.new(character: Model, config: {[string]: any}?)
```

Creates a new solver for the given R6 character. Call **once per character** (e.g. in `CharacterAdded`).

**Parameters:**
- `character` — The R6 character Model
- `config` — Optional config overrides (see [Config](#config))

**Returns:** Solver instance

---

### Target setters (call each frame before `update`)

#### `ik:setArmTarget(side, position, poleVector?)`

| Param | Type | Description |
|-------|------|-------------|
| `side` | `"Left"` \| `"Right"` | Which arm |
| `position` | `Vector3` | World position for hand/end-effector |
| `poleVector` | `Vector3?` | World position for elbow direction (optional) |

**Example:**
```lua
ik:setArmTarget("Right", mouseWorldPos, torso.Position + torso.CFrame.LookVector * -2)
```

---

#### `ik:setLegTarget(side, position, poleVector?)`

| Param | Type | Description |
|-------|------|-------------|
| `side` | `"Left"` \| `"Right"` | Which leg |
| `position` | `Vector3` | World position for foot |
| `poleVector` | `Vector3?` | World position for knee direction (optional) |

**Example (ground plant):**
```lua
local footPos = character["Left Leg"].Position + Vector3.new(0, -1, 0) -- raycast to ground
ik:setLegTarget("Left", footPos, character.Torso.Position + Vector3.new(0, 2, 0))
```

---

#### `ik:setTorsoPitch(radians)`

| Param | Type | Description |
|-------|------|-------------|
| `radians` | `number` | Pitch angle (positive = look up, negative = look down) |

**Example (camera aim):**
```lua
local cam = workspace.CurrentCamera
local look = cam.CFrame.LookVector
local pitch = math.asin(-look.Y)
ik:setTorsoPitch(pitch)
```

---

### Update

#### `ik:update(dt)`

Applies IK and lerps Motor6D C0 values. Call every frame (e.g. in `RenderStepped`).

| Param | Type | Description |
|-------|------|-------------|
| `dt` | `number` | Delta time (from `RenderStepped` or `Heartbeat`) |

---

### Enable / disable limbs

#### `ik:setEnabled(limbName, on)`

| Param | Type | Description |
|-------|------|-------------|
| `limbName` | `string` | `"LeftArm"` \| `"RightArm"` \| `"LeftLeg"` \| `"RightLeg"` \| `"Torso"` |
| `on` | `boolean` | `true` = IK controls limb, `false` = animation controls limb |

When disabled, the limb snaps back to its original C0.

---

### Configuration

#### `ik:setLimbSmoothing(limbName, alpha?)`

Per-limb smoothing override. `alpha` 0 = frozen, 1 = instant. `nil` = use global config.

#### `ik:setLimbOverrideAnimation(limbName, override?)`

Per-limb animation override. `true` = zero `Motor6D.Transform` (IK wins), `false` = blend with animation. `nil` = use global config.

#### `ik:setArmSegments(upper, lower)`  
#### `ik:setLegSegments(upper, lower)`

Change virtual segment lengths at runtime (default 1, 1).

---

### Reset & destroy

#### `ik:reset(limbName?)`

Restores limb(s) to animation control. `limbName` = one limb, `nil` = all limbs.

#### `ik:destroy()`

Full cleanup: restores all Motor6D C0s and clears references. Call when character is removed.

---

## Config

Pass to `R6IKSolver.new(character, config)`:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `smoothing` | `number` | `0.3` | Lerp alpha (0=frozen, 1=snap) |
| `overrideAnimation` | `boolean` | `true` | Zero `Motor6D.Transform` on IK limbs |
| `armSegments` | `{upper, lower}` | `{1, 1}` | Virtual arm segment lengths |
| `legSegments` | `{upper, lower}` | `{1, 1}` | Virtual leg segment lengths |
| `armClamp` | `{joint1, joint2}` | `{[-π,π], [-π,π]}` | Shoulder/elbow angle limits (radians) |
| `legClamp` | `{joint1, joint2}` | `{[-1.2,1.8], [-2.5,0.1]}` | Hip/knee angle limits |
| `torsoPitchClamp` | `[min, max]` | `[-0.8, 0.8]` | Torso pitch limits (±46°) |
| `torsoPitchSmoothing` | `number` | `0.2` | Torso pitch lerp alpha |

**Example:**
```lua
ik = R6IKSolver.new(character, {
	smoothing = 0.4,
	overrideAnimation = true,
	armClamp = {
		joint1 = { -math.pi, math.pi },
		joint2 = { -math.pi, 0.1 },
	},
})
```

---

## Features

| Feature | Description |
|---------|-------------|
| **2-joint IK** | Law of Cosines solver for shoulder→elbow→hand and hip→knee→foot |
| **Pole vector** | Control elbow/knee bend direction |
| **Animation override** | Zeros `Motor6D.Transform` so IK fully controls pose |
| **Animation blend** | Optional: `overrideAnimation=false` to blend with animations |
| **Per-limb control** | Enable/disable arms, legs, torso independently |
| **Smoothing** | Per-frame lerp for smooth motion |
| **Angle clamping** | Prevent impossible poses |
| **Torso pitch** | Aim up/down via RootJoint |

---

## Motor6D math

```
Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
```

- **Override mode** (`overrideAnimation=true`): Set `Transform = CFrame.new()` each frame. IK C0 fully controls pose.
- **Blend mode** (`overrideAnimation=false`): Use `Transform` from animations. IK and animation coexist (may fight).

---

## Transferring to another game

### Files to copy

| Use case | Files |
|----------|-------|
| **Minimal** (arms track mouse) | `R6IKSolver.luau`, `R6IK_Bootstrap.client.lua` |
| **Custom** (your own targets) | `R6IKSolver.luau` only + your script |

### Minimal transfer (R6IKSolver only)

1. Copy `R6IKSolver.luau` to ReplicatedStorage.
2. Copy `R6IK_Bootstrap.client.lua` to StarterPlayerScripts (or add the Quick Start LocalScript above).
3. Set RigType to R6.

### With custom model overlay (e.g. Shorty)

If you attach a custom model (e.g. weapon rig) to the character:

1. **Weld** the overlay’s root to `HumanoidRootPart` only (do not weld arms).
2. Use **Attachments** (e.g. `Solver`) on the overlay arms as IK targets.
3. Zero the overlay’s arm `Motor6D.Transform` when IK is solving so animations don’t fight:

```lua
if overlayModel then
	local hrp = overlayModel:FindFirstChild("HumanoidRootPart")
	if hrp then
		local lm = hrp:FindFirstChild("Left Arm")
		local rm = hrp:FindFirstChild("Right Arm")
		if lm and lm:IsA("Motor6D") then lm.Transform = CFrame.new() end
		if rm and rm:IsA("Motor6D") then rm.Transform = CFrame.new() end
	end
end
```

### Archivable requirement

If cloning a model that has `HumanoidRootPart`, `Left Arm`, `Right Arm` with `Archivable=false`, set `Archivable=true` on the source and descendants before cloning, or set it in Studio before play.

---

## Rojo project structure

```json
{
  "ReplicatedStorage": {
    "R6IKSolver": { "$path": "src/shared/R6IKSolver.luau" }
  },
  "StarterPlayer": {
    "StarterPlayerScripts": {
      "Client": { "$path": "src/client" }
    }
  }
}
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Arms don’t move | Ensure `ik:setEnabled("RightArm", true)` (and Left) and `ik:update(dt)` are called every frame |
| Arms snap/jitter | Increase `smoothing` (e.g. 0.5) or use `setLimbSmoothing` |
| Animation fights IK | Set `overrideAnimation = true` in config |
| Wrong bend direction | Adjust pole vector (e.g. behind character for elbows) |
| "needs an R6 character with a Torso" | Character is R15 or missing Torso; use R6 |
| Cloned model missing parts | Set `Archivable=true` on source model in Studio before play |
