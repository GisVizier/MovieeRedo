# Data API

## Architecture

```
ProfileStore (DataStore) ──▶ ProfileHandler (server module) ──▶ ReplicaServer
                                    │                                │
                                    │  PlayerDataUpdate remote       │ replicates
                                    │  (client → server)             ▼
                              PlayerDataTable (client module) ◀── ReplicaClient
```

**Server:** `ProfileHandler` loads a ProfileStore session per player, wraps it in a Replica, and subscribes the owning player. Changes to the replica auto-save to DataStore via ProfileStore.

**Client:** `PlayerDataTable` calls `Replica.RequestData()` on init. When the `"PlayerData"` replica arrives, it uses `replica.Data` as its live source. Before that, it uses mock data. All writes go through `PlayerDataUpdate` remote → server calls `replica:Set()` → replicates back.

## Data Schema (`Default.lua`)

```
GEMS: number
CROWNS: number
WINS: number
STREAK: number
EMOTES: {}
OWNED: { OWNED_EMOTES, OWNED_KITS, OWNED_PRIMARY, OWNED_SECONDARY, OWNED_MELEE }
EQUIPPED: { Kit, Primary, Secondary, Melee }
EQUIPPED_SKINS: { [weaponId] = skinId }
EQUIPPED_EMOTES: { Slot1..Slot8 = emoteId }
OWNED_SKINS: { [weaponId] = {skinId, ...} }
WEAPON_DATA: { [weaponId] = { killEffect?, ... } }
Settings: { Gameplay = {}, Controls = {}, Crosshair = {} }
```

## Files

| File | Location | Side |
|------|----------|------|
| `ProfileHandler` | `ServerScriptService.Data.ProfileHandler` | Server |
| `PlayerDataTable` | `ReplicatedStorage.PlayerDataTable` | Client |
| `Default` | `ServerScriptService.Data.Default` | Server |
| `DataConfig` | `ServerScriptService.Data.DataConfig` | Server |
| `Peekable` | `ServerScriptService.Data.Peekable` | Server |
| `ReplicaServer` | `ReplicatedStorage.Shared.ReplicaServer` | Server |
| `ReplicaClient` | `ReplicatedStorage.Shared.ReplicaClient` | Client |

---

## Server API (`ProfileHandler`)

```lua
local Data = require(game.ServerScriptService.Data.ProfileHandler)
```

### Data.GetReplica(player) → Replica?
Returns the raw Replica object. Use for direct `replica.Data` reads.
```lua
local replica = Data.GetReplica(player)
print(replica.Data.GEMS)
```

### Data.GetProfile(player) → Profile?
Returns the ProfileStore profile (has `.Data`, `.LastSavedData`).
```lua
local profile = Data.GetProfile(player)
```

### Data.SetData(player, path, value)
Set any value by path. Syncs Peekable automatically.
```lua
Data.SetData(player, { "GEMS" }, 500)
Data.SetData(player, { "EQUIPPED", "Primary" }, "Sniper")
Data.SetData(player, { "STREAK" }, 0)
```

### Data.IncrementData(player, key, amount?) → number?
Increment a top-level number. Defaults to +1. Returns new value.
```lua
Data.IncrementData(player, "WINS")        -- +1
Data.IncrementData(player, "GEMS", 100)   -- +100
Data.IncrementData(player, "GEMS", -50)   -- -50
```

---

## Client API (`PlayerDataTable`)

```lua
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
PlayerDataTable.init()  -- call once at startup (ClientInit does this)
```

### Read

| Method | Returns |
|--------|---------|
| `getData(key)` | `any` — top-level value (GEMS, WINS, etc.) |
| `getOwned(category)` | `{any}` — e.g. `getOwned("OWNED_KITS")` |
| `isOwned(category, itemId)` | `boolean` |
| `getOwnedWeaponsByType(type)` | `{any}` — type = "Kit"/"Primary"/"Secondary"/"Melee" |
| `getEquippedLoadout()` | `{ Kit, Primary, Secondary, Melee }` |
| `getEquippedSkin(weaponId)` | `string?` |
| `getOwnedSkins(weaponId)` | `{string}` |
| `isSkinOwned(weaponId, skinId)` | `boolean` |
| `getEquippedEmotes()` | `{ Slot1..Slot8 = emoteId }` |
| `isEmoteOwned(emoteId)` | `boolean` |
| `getOwnedEmotes()` | `{string}` |
| `getWeaponData(weaponId)` | `{ killEffect?, ... }?` |
| `getWeaponKillEffect(weaponId)` | `string?` |
| `getAllWeaponData()` | `{ [weaponId] = data }` |

### Write (persists to server via remote)

| Method | Params |
|--------|--------|
| `setData(key, value)` | top-level key |
| `addOwned(category, itemId)` | add to owned list |
| `setEquippedWeapon(slotType, weaponId)` | "Primary"/"Secondary"/"Melee"/"Kit" |
| `setEquippedSkin(weaponId, skinId)` | |
| `setEquippedEmote(slot, emoteId)` | "Slot1".."Slot8" |
| `addOwnedEmote(emoteId)` | |
| `setWeaponData(weaponId, data)` | |
| `setWeaponKillEffect(weaponId, effect)` | |

### Settings

| Method | Params |
|--------|--------|
| `get(category, key)` | "Gameplay"/"Controls"/"Crosshair" |
| `set(category, key, value)` | persists to server |
| `getBind(settingKey, slot)` | → `KeyCode?` |
| `setBind(settingKey, slot, keyCode)` | |
| `getConflicts(keyCode, excludeKey?, excludeSlot?)` | → conflicts list |
| `resetCategory(category)` | resets to defaults |
| `getAllSettings()` | full settings table |

### Callbacks

```lua
local disconnect = PlayerDataTable.onChanged(function(category, key, newValue, oldValue)
    print(category, key, "changed to", newValue)
end)
disconnect() -- stop listening
```

---

## Config

**`DataConfig.lua`** — bump `StoreVersion` to wipe all profiles on schema break:
```lua
return {
    DataStore = {
        StoreVersion = 1,
        Disabled = false,  -- true = mock DataStore (Studio testing)
    },
}
```

**`Peekable.lua`** — paths visible to all players (broadcast via `Replicate()`):
```lua
return {
    ["GEMS"] = true,
    ["CROWNS"] = true,
    ["WINS"] = true,
    ["STREAK"] = true,
    ["EQUIPPED"] = true,
}
```
