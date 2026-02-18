# Replica

State replication library for Roblox. Handles server → client data sync with subscription control and change listeners.

## Architecture

```
Server (ReplicaServer)                    Client (ReplicaClient)
─────────────────────                    ─────────────────────
Replica.New() creates replica            Replica.RequestData() requests replicas
replica:Set() updates data               Replica.OnNew(token, fn) receives replicas
replica:Subscribe(player)                replica.Data holds synced state
replica:Replicate() broadcasts           replica:OnSet(path, fn) / OnChange(fn)
replica:ListenToSet(path, fn) [server]   replica:OnSet(path, fn) / OnChange(fn)
replica:ListenToChange(fn) [server]
```

## Files

| File | Location | Side |
|------|----------|------|
| `ReplicaServer` | `ReplicatedStorage.Shared.ReplicaServer` | Server |
| `ReplicaClient` | `ReplicatedStorage.Shared.ReplicaClient` | Client |
| `ReplicaShared` | `ReplicatedStorage.Shared.ReplicaShared` | Both |

---

## ReplicaServer (Server)

### Replica.Token(name: string) → ReplicaToken
Create a unique token for a replica type. One token per unique name.

```lua
local DataToken = Replica.Token("PlayerData")
local PeekToken = Replica.Token("PeekableData")
```

### Replica.New(params) → Replica
Create a new replica.

```lua
local replica = Replica.New({
    Token = DataToken,
    Data = { GEMS = 0, WINS = 0 },
    Tags = { UserId = player.UserId },
})
```

| Param | Type | Description |
|-------|------|-------------|
| `Token` | ReplicaToken | Required. Unique token for this replica type. |
| `Data` | table | Initial data. Must be serializable (no Enum, Vector3, functions). |
| `Tags` | table | Metadata (e.g. `UserId`). |
| `WriteLib` | ModuleScript? | Optional. Client-side write functions. |

### Replica.FromId(id: number) → Replica?
Get a replica by ID.

### Replica Members

| Member | Type | Description |
|--------|------|-------------|
| `Token` | string | Token name. |
| `Data` | table | Live data. Mutate via `Set`, `SetValues`, etc. |
| `Id` | number | Unique replica ID. |
| `Tags` | table | Metadata. |
| `Maid` | Maid | Cleanup on Destroy. |

### Replica Methods (Server)

| Method | Description |
|--------|-------------|
| `replica:Set(path, value)` | Set a value at path. Replicates to clients. |
| `replica:SetValues(path, values)` | Set multiple keys at path. |
| `replica:TableInsert(path, value, index?)` | Insert into array. |
| `replica:TableRemove(path, index)` | Remove from array. |
| `replica:Subscribe(player)` | Subscribe a player to this replica. |
| `replica:Unsubscribe(player)` | Unsubscribe. |
| `replica:Replicate()` | Broadcast to all clients (no per-player subscription). |
| `replica:DontReplicate()` | Stop replicating. |
| `replica:FireClient(player, ...)` | Fire event to one client. |
| `replica:FireAllClients(...)` | Fire event to all subscribed clients. |
| `replica:Destroy()` | Destroy replica and cleanup. |

### Server-Side Change Listeners

Listen when data changes on the server (e.g. for UI updates).

| Method | Description |
|--------|-------------|
| `replica:ListenToSet(path, fn)` | Fire when `path` is set. `fn(value, oldValue)`. |
| `replica:ListenToChange(fn)` | Fire on any change. `fn(action, path, param1, param2)`. |

```lua
local replica = Data.GetReplica(player)
local conn = replica:ListenToChange(function(action, path, param1, param2)
    if action == "Set" and path[1] == "CROWNS" then
        -- refresh overhead
    end
end)
-- Later: conn:Disconnect()
```

---

## ReplicaClient (Client)

### Replica.RequestData()
Request replicas from the server. Call once at startup (e.g. `PlayerDataTable.init()`).

### Replica.OnNew(token: string, listener: (replica) -> ()) → Connection
Called when a new replica of this token is received.

```lua
Replica.OnNew("PlayerData", function(replica)
    if replica.Tags.UserId == LocalPlayer.UserId then
        -- my data
    end
end)

Replica.OnNew("PeekableData", function(replica)
    -- other players' public data (CROWNS, WINS, etc.)
end)
```

### Replica.FromId(id: number) → Replica?
Get a replica by ID.

### Replica Members (Client)

| Member | Type | Description |
|--------|------|-------------|
| `Token` | string | Token name. |
| `Data` | table | Synced data from server. Read-only. |
| `Id` | number | Replica ID. |
| `Tags` | table | Metadata. |

### Replica Methods (Client)

| Method | Description |
|--------|-------------|
| `replica:OnSet(path, fn)` | Fire when `path` is set. `fn(value, oldValue)`. |
| `replica:OnChange(fn)` | Fire on any change. `fn(action, path, param1, param2)`. |
| `replica:FireServer(...)` | Fire event to server. |
| `replica:GetChild(token)` | Get child replica by token. |

```lua
replica:OnChange(function(action, path, param1, param2)
    if action == "Set" and path[1] == "CROWNS" then
        -- refresh UI
    end
end)
```

---

## Usage in This Project

### ProfileHandler (Server)
- Creates `PlayerData` replica per player (from ProfileStore).
- Creates `PeekableData` replica per player (from ProfileStore, subset of data).
- `PlayerData` uses `Subscribe(player)` — only that player receives it.
- `PeekableData` uses `Replicate()` — all clients receive it (for leaderboards, overheads).

### OverheadService (Server)
- Uses `Data.GetReplica(player)` to get the player’s `PlayerData` replica.
- Reads `replica.Data.CROWNS`, `replica.Data.WINS`, `replica.Data.STREAK`.
- Uses `replica:ListenToChange(fn)` to refresh overhead when data changes.

### PlayerDataTable (Client)
- Calls `Replica.RequestData()` on init.
- Uses `Replica.OnNew("PlayerData", function(replica) ...)` to get own data.
- Uses `replica:OnChange(...)` for debug logging.

---

## Constraints

- **No gaps in numeric tables** — Replica cannot replicate sparse arrays.
- **No non-string/numeric keys** — Only string and number keys allowed.
- **Serializable values only** — No Enum, Vector3, Color3, Instances, functions.
