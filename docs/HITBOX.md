# Hitbox Utility

Simple hitbox detection for players and tagged objects, shared by server and client.

## Overview

`Hitbox.lua` provides spatial queries for abilities:

- Sphere detection
- Box detection (optional moving hitbox)
- Raycast detection

It properly resolves player hitboxes using `Collider/Hitbox` and the `OwnerUserId` attribute.

## Usage

```lua
local Hitbox = require(path.to.Hitbox)

-- Sphere (radius)
local targets = Hitbox.GetEntitiesInSphere(position, 30, {
    Exclude = player,
    Tags = { "AimAssistTarget" },
    Visualize = true,
})

-- Box (instant)
local targets = Hitbox.GetEntitiesInBox({
    CFrame = CFrame.new(position),
    Size = Vector3.new(10, 6, 10),
    Exclude = player,
    MaxHits = 5,
    Tags = { "AimAssistTarget" },
    Visualize = true,
})

-- Box (moving projectile)
local handle = Hitbox.GetEntitiesInBox({
    CFrame = CFrame.new(startPos, targetPos),
    Size = Vector3.new(4, 4, 8),
    Exclude = player,
    Duration = 3,
    Velocity = 80, -- studs/sec along LookVector
    Tags = { "AimAssistTarget" },
    Visualize = true,
})

local hits = handle:GetHits()
handle:Stop()
```

## Return Values

`GetEntitiesInSphere` and `GetEntitiesInBox` return a list containing:

- `Player` instances
- Tagged instances (Model/BasePart) when `Tags` is provided

For duration-based calls, a handle is returned:

- `handle:GetHits()` returns the current hit list
- `handle:Stop()` ends the polling early

## Config Options

All fields are optional unless noted.

- `Exclude` (Player | {Player}) - Player(s) to exclude
- `Duration` (number) - Duration in seconds for lingering hitboxes
- `MaxHits` (number) - Stop after N unique entities
- `Velocity` (number) - Move hitbox forward along LookVector (box only)
- `Tags` ({string}) - CollectionService tags to include
- `Visualize` (boolean) - Show debug geometry
- `VisualizeDuration` (number) - Lifespan of debug geometry
- `VisualizeColor` (Color3) - Debug color

## Notes

- Player detection uses `Collider/Hitbox` parts, which match the weapon system.
- Only `CanQuery = true` hitbox parts are detected (stance-aware).
- Tags work for dummies/rigs/NPCs via `CollectionService`.
