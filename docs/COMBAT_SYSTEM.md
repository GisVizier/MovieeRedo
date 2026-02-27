# Combat Resource System

A comprehensive combat management system for handling health, shields, ultimate charge, i-frames, status effects, kill effects, and damage numbers.

## Architecture Overview

```
Server Side                           Shared (ReplicatedStorage)           Client Side
─────────────                         ────────────────────────────         ───────────
CombatService ────────────────────────► CombatResource                     CombatController
    │                                        │                                  │
    ├─► StatusEffectManager                  ├─► CombatConfig                   ├─► DamageNumbers
    │       │                                │                                  │
    │       └─► StatusEffects/               └─► CombatTypes                    │
    │           ├─► Burn.lua                                                    │
    │           ├─► Bleed.lua                                                   │
    │           ├─► Heal.lua                                                    │
    │           └─► Frozen.lua                                                  │
    │                                                                           │
    └─► KillEffects ◄─────────────────────────────────────────────────────────►│
            ├─► Ragdoll.lua
            └─► (more effects)
```

## Core Components

### CombatResource (`ReplicatedStorage/Combat/CombatResource.lua`)

Per-player resource container managing health, shield, ultimate, and i-frames.

#### Health API

```lua
resource:GetHealth()              -- Returns current health
resource:GetMaxHealth()           -- Returns max health
resource:SetHealth(value)         -- Sets health (clamped)
resource:SetMaxHealth(value)      -- Sets max health
resource:Heal(amount, options?)   -- Heals player, returns actual amount healed
resource:TakeDamage(amount, options?) -- Applies damage through shield/health pipeline
resource:Kill(killer?, killEffect?)   -- Kills player instantly
resource:IsAlive()                -- Returns true if health > 0 and not dead
resource:IsDead()                 -- Returns true if dead
resource:Revive(health?)          -- Revives dead player
```

#### Shield API (Disabled by default)

```lua
resource:GetShield()              -- Returns current shield
resource:GetMaxShield()           -- Returns max shield
resource:SetShield(value)         -- Sets shield
resource:SetMaxShield(value)      -- Sets max shield
resource:GetOvershield()          -- Returns current overshield
resource:AddOvershield(amount)    -- Adds overshield
resource:GetTotalShield()         -- Returns shield + overshield
resource:TickShieldRegen(dt)      -- Updates shield regeneration
```

#### Ultimate API

```lua
resource:GetUltimate()            -- Returns current ult charge
resource:GetMaxUltimate()         -- Returns max ult (default 100)
resource:SetUltimate(value)       -- Sets ult (clamped)
resource:SetMaxUltimate(value)    -- Sets max ult
resource:AddUltimate(amount)      -- Adds ult charge
resource:SpendUltimate(amount)    -- Spends ult, returns true if successful
resource:IsUltFull()              -- Returns true if ult >= max
```

#### I-Frame API

```lua
resource:GrantIFrames(duration)   -- Grants invulnerability for duration
resource:SetInvulnerable(bool)    -- Manual toggle (infinite until disabled)
resource:IsInvulnerable()         -- Returns current invulnerability state
```

#### Events

```lua
resource.OnHealthChanged          -- (newHealth, oldHealth, source?)
resource.OnMaxHealthChanged       -- (newMax, oldMax)
resource.OnShieldChanged          -- (newShield, oldShield)
resource.OnOvershieldChanged      -- (newOvershield, oldOvershield)
resource.OnUltimateChanged        -- (newUlt, oldUlt)
resource.OnUltimateFull           -- ()
resource.OnUltimateSpent          -- (amount)
resource.OnDamaged                -- (totalDamage, source, info)
resource.OnHealed                 -- (amount, source)
resource.OnDeath                  -- (killer?, weaponId?)
resource.OnInvulnerabilityChanged -- (isInvulnerable)
```

---

### CombatService (`ServerScriptService/Server/Services/Combat/CombatService.lua`)

Server-authoritative combat management.

#### Initialization

```lua
-- Called automatically when player character spawns
combatService:InitializePlayer(player, options?)
-- options: { maxHealth?, maxShield?, maxUltimate? }
```

#### Damage API

```lua
local result = combatService:ApplyDamage(targetPlayer, damage, {
    source = attackerPlayer,       -- Who dealt the damage
    isTrueDamage = false,          -- Bypasses shields and i-frames
    isHeadshot = false,            -- Headshot indicator
    weaponId = "Shotgun",          -- Weapon used
    damageType = "Bullet",         -- Damage type for effects
    skipIFrames = false,           -- Bypass i-frame check only
})
-- Returns: { healthDamage, shieldDamage, overshieldDamage, blocked, killed }

combatService:Heal(player, amount, { source?, healType? })
combatService:Kill(player, killer?, killEffect?)
```

#### Ultimate API

```lua
combatService:AddUltimate(player, amount)
combatService:SpendUltimate(player, amount) -- Returns boolean
```

#### I-Frame API

```lua
combatService:GrantIFrames(player, duration)
combatService:SetInvulnerable(player, boolean)
combatService:IsInvulnerable(player) -- Returns boolean
```

#### Status Effects API

```lua
combatService:ApplyStatusEffect(player, "Burn", {
    duration = 5,           -- Required: effect duration
    tickRate = 0.5,         -- Optional: override default tick rate
    source = attackerPlayer, -- Optional: who applied effect
    damagePerTick = 10,     -- Effect-specific setting
})

combatService:RemoveStatusEffect(player, "Burn", reason?)
combatService:RemoveAllStatusEffects(player, reason?)
```

---

### StatusEffectManager (`ReplicatedStorage/Combat/StatusEffectManager.lua`)

Manages active status effects for a single player.

#### API

```lua
manager:Apply(effectId, settings)     -- Apply or refresh effect
manager:Remove(effectId, reason?)     -- Remove effect
manager:RemoveAll(reason?)            -- Remove all effects
manager:Has(effectId)                 -- Check if effect is active
manager:GetRemaining(effectId)        -- Get remaining duration
manager:GetActiveEffects()            -- Get all active {effectId: duration}
manager:Tick(deltaTime)               -- Process all effects
manager:NotifyDamage(damage, source?) -- Notify effects of damage (for breakOnDamage)
```

---

## Status Effects

### Creating a New Effect

Create a module in `ReplicatedStorage/Combat/StatusEffects/`:

```lua
local MyEffect = {}
MyEffect.Id = "MyEffect"
MyEffect.DefaultTickRate = 0.5  -- Optional, defaults to config

function MyEffect:OnApply(target, settings, combatResource)
    -- Called when effect is first applied
    local character = target.Character
    if character then
        character:SetAttribute("MyEffectVFX", true)
    end
end

function MyEffect:OnTick(target, settings, deltaTime, combatResource)
    -- Called every tick while active
    -- Return false to remove effect early
    if combatResource then
        combatResource:TakeDamage(settings.damagePerTick or 5, {
            source = settings.source,
            damageType = "MyEffect",
        })
    end
    return true  -- Continue effect
end

function MyEffect:OnRemove(target, settings, reason, combatResource)
    -- Called when effect is removed
    local character = target.Character
    if character then
        character:SetAttribute("MyEffectVFX", nil)
    end
end

return MyEffect
```

### Built-in Effects

| Effect | Description | Settings |
|--------|-------------|----------|
| **Burn** | Damage over time | `damagePerTick` (default 10), `tickRate` (default 0.5) |
| **Bleed** | Forces walk speed, disables sprint | `damagePerTick` (optional DoT) |
| **Heal** | Healing over time | `healPerTick` (default 5), `tickRate` (default 0.25) |
| **Frozen** | Stops movement, low friction, breaks on damage | `friction` (default 0.02), `breakOnDamage` (default true) |

---

## Kill Effects

### Creating a New Kill Effect

Create a module in `ReplicatedStorage/Combat/KillEffects/`:

```lua
local MyKillEffect = {}
MyKillEffect.Id = "MyKillEffect"
MyKillEffect.Name = "My Kill Effect"

function MyKillEffect:Execute(victim, killer, weaponId, options)
    local character = victim.Character
    if not character then return end
    
    -- Set attributes for client VFX systems
    character:SetAttribute("KillEffect", "MyKillEffect")
    character:SetAttribute("KillerId", killer and killer.UserId or nil)
    
    -- Perform effect logic
    -- ...
end

return MyKillEffect
```

### Player Weapon Kill Effect Customization

Players can customize kill effects per weapon via `PlayerDataTable`:

```lua
-- Set custom kill effect for a weapon
PlayerDataTable.setWeaponKillEffect("Shotgun", "Disintegrate")

-- Get kill effect for a weapon
local effect = PlayerDataTable.getWeaponKillEffect("Shotgun")
-- Returns: "Disintegrate" or nil (uses default)

-- Get all weapon data
local data = PlayerDataTable.getAllWeaponData()
```

---

## Configuration

### CombatConfig (`ReplicatedStorage/Combat/CombatConfig.lua`)

```lua
CombatConfig = {
    -- Default resources
    DefaultMaxHealth = 150,
    DefaultMaxShield = 100,
    DefaultMaxOvershield = 50,
    DefaultMaxUltimate = 100,
    
    -- Ultimate gain rates
    UltGain = {
        DamageDealt = 0.15,    -- 15% of damage dealt
        DamageTaken = 0.10,    -- 10% of damage taken
        Kill = 25,             -- Flat per kill
        Assist = 10,           -- Flat per assist
    },
    
    -- Shield (disabled by default)
    Shield = {
        Enabled = false,
        RegenDelay = 3.0,      -- Seconds after damage
        RegenRate = 15,        -- Per second
    },
    
    -- I-Frames
    IFrames = {
        DefaultDuration = 0.2,
    },
    
    -- Death
    Death = {
        DefaultKillEffect = "Ragdoll",
    },
    
    -- Damage numbers
    DamageNumbers = {
        Enabled = true,
        Mode = "Add",          -- "Add" | "Stacked" | "Disabled"
        HeadshotScale = 1.3,
        CriticalScale = 1.5,
        FloatSpeed = 2,
        FadeTime = 1.0,
        FadeDuration = 0.3,
        Colors = {
            Normal = Color3.fromRGB(233, 233, 233),
            Headshot = Color3.fromRGB(255, 200, 50),
            Critical = Color3.fromRGB(255, 80, 80),
            Heal = Color3.fromRGB(100, 255, 100),
        },
    },
}
```

`Mode` behavior:
- `Add`: cumulative per-target popup (Fortnite-style `Cumulative`).
- `Stacked`: separate popup per hit, stacked vertically per target (Fortnite-style `List`).
- `Disabled`: no damage numbers shown.

---

## Network Events

### Server -> Client

| Event | Description | Payload |
|-------|-------------|---------|
| `CombatStateUpdate` | Combat state sync | `{ health, maxHealth, shield, overshield, ultimate, maxUltimate, statusEffects }` |
| `DamageDealt` | Damage number display | `{ targetUserId, attackerUserId?, damage, isHeadshot, isCritical, isHeal?, damageNumbersMode?, position }` |
| `StatusEffectUpdate` | Effect changes | `{ [effectId]: remainingDuration }` |
| `PlayerKilled` | Kill notification | `{ victimUserId, killerUserId?, weaponId?, killEffect? }` |

---

## Integration Points

### WeaponService Integration

Damage from weapons routes through CombatService:

```lua
-- In WeaponService:ApplyDamageToCharacter
local combatService = self._registry:TryGet("CombatService")
if combatService and victimPlayer then
    combatService:ApplyDamage(victimPlayer, damage, {
        source = shooter,
        isHeadshot = isHeadshot,
        weaponId = weaponId,
    })
end
```

### MovementController Integration

Status effects affect movement:

- **Frozen**: Zeroes `VectorForce.Force`, allows physics sliding
- **Bleed**: Prevents sprinting, forces walk speed

```lua
-- In MovementController:UpdateMovement
if self.Character:GetAttribute("Frozen") then
    self.VectorForce.Force = Vector3.zero
    return
end

-- In MovementController:HandleSprint
if self.Character:GetAttribute("Bleed") then
    MovementStateManager:TransitionTo(States.Walking)
    return
end
```

### CharacterService Integration

Combat resources initialize on character spawn:

```lua
-- In CharacterService:SpawnCharacter
local combatService = self._registry:TryGet("CombatService")
if combatService then
    combatService:InitializePlayer(player)
end
```

---

## Usage Examples

### Basic Damage

```lua
local combatService = registry:Get("CombatService")

-- Apply 50 damage from shooter with headshot
combatService:ApplyDamage(targetPlayer, 50, {
    source = shooterPlayer,
    isHeadshot = true,
    weaponId = "Sniper",
})
```

### Status Effect Application

```lua
-- Apply burn for 5 seconds doing 15 damage per tick
combatService:ApplyStatusEffect(targetPlayer, "Burn", {
    duration = 5,
    damagePerTick = 15,
    source = attackerPlayer,
})

-- Apply freeze for 3 seconds that breaks on any damage
combatService:ApplyStatusEffect(targetPlayer, "Frozen", {
    duration = 3,
    breakOnDamage = true,
})
```

### Ultimate Management

```lua
-- Check if player can use ultimate
local resource = combatService:GetResource(player)
if resource and resource:IsUltFull() then
    -- Spend 100 ult for ability
    if combatService:SpendUltimate(player, 100) then
        -- Execute ultimate ability
    end
end
```

### I-Frame Grants

```lua
-- Grant 0.5 second i-frames after dodge
combatService:GrantIFrames(player, 0.5)

-- Make player invulnerable during cutscene
combatService:SetInvulnerable(player, true)
-- Later...
combatService:SetInvulnerable(player, false)
```

---

## Player Attributes

The combat system syncs state to player attributes for UI:

| Attribute | Type | Description |
|-----------|------|-------------|
| `Health` | number | Current health |
| `MaxHealth` | number | Maximum health |
| `Shield` | number | Current shield |
| `Overshield` | number | Current overshield |
| `Ultimate` | number | Current ultimate charge |
| `MaxUltimate` | number | Maximum ultimate |

Status effects set attributes on the **Character**:

| Attribute | Type | Description |
|-----------|------|-------------|
| `Burn` | boolean | Burn effect active |
| `Bleed` | boolean | Bleed effect active |
| `Heal` | boolean | Heal effect active |
| `Frozen` | boolean | Frozen effect active |
| `BurnVFX` | boolean | Burn VFX should play |
| `BleedVFX` | boolean | Bleed VFX should play |
| `HealVFX` | boolean | Heal VFX should play |
| `FrozenVFX` | boolean | Frozen VFX should play |
