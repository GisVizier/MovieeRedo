# Matchmaking System

A modular matchmaking system supporting **multiple concurrent matches** with dynamic map loading. Supports both **Training** (infinite) and **Competitive** (1v1, 2v2, etc.) modes.

## Quick Start

### Competitive Mode (1v1 Duel)
1. Create queue pad in lobby: `1v1` model with `Team1` and `Team2` children
2. Tag the `1v1` model with `QueuePad`
3. Store arena map in `ServerStorage/Maps/Map` with `SpawnLocations/Spawn1` and `Spawn2`
4. Tag lobby spawns with `LobbySpawn`
5. Players step on Team1/Team2 pads → countdown → map loads → match starts

### Training Mode
1. Tag training spawns with `TrainingSpawn`
2. Players use AreaTeleport gadget to enter training area
3. Players can join/leave anytime, respawn forever

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         QUEUE PAD                                │
│  1v1 [Tagged: "QueuePad"]                                       │
│   ├── Team1 (zone detection)                                    │
│   │   ├── Inner                                                 │
│   │   └── Outer                                                 │
│   └── Team2 (zone detection)                                    │
│       ├── Inner                                                 │
│       └── Outer                                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    Player steps on Team1 or Team2
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      QueueService                                │
│  - Detects players in Team1/Team2 zones                         │
│  - Tracks queued players per pad: { [padName]: {Team1, Team2} } │
│  - Starts countdown when both teams have required players       │
│  - On countdown complete → requests match from MatchManager     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      MatchManager                                │
│  - Creates new Match instances                                  │
│  - Tracks all active matches: { [matchId]: MatchData }          │
│  - Allocates map positions (5000, 7000, 9000...)               │
│  - Handles scoring, rounds, win conditions                      │
│  - Recycles positions when matches end                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                   MapLoaderService                               │
│  - Clones map from ServerStorage/Maps                           │
│  - Parents to Workspace at allocated position                   │
│  - Returns spawn references (Spawn1, Spawn2)                    │
│  - Destroys map when match ends                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Modes

| Mode | Teams | Scoring | Join Midway | Win Condition |
|------|-------|---------|-------------|---------------|
| **Training** | No | No | Yes | None (infinite) |
| **Duel** | 1v1 | Yes | No | First to 5 |
| **TwoVTwo** | 2v2 | Yes | No | First to 10 |
| **ThreeVThree** | 3v3 | Yes | No | First to 15 |
| **FourVFour** | 4v4 | Yes | No | First to 20 |

---

## Configuration

All settings in `ReplicatedStorage/Configs/MatchmakingConfig.lua`:

```lua
-- Mode configuration
MatchmakingConfig.Modes = {
    Training = {
        hasTeams = false,
        hasScoring = false,
        allowJoinMidway = true,
        respawnDelay = 2,
    },
    Duel = {
        hasTeams = true,
        hasScoring = true,
        playersPerTeam = 1,
        scoreToWin = 5,
        loadoutSelectionTime = 15,
        roundResetDelay = 2,
        lobbyReturnDelay = 5,
    },
}

-- Mode name mapping (queue pad name → mode ID)
MatchmakingConfig.ModeNameMapping = {
    ["1v1"] = "Duel",
    ["2v2"] = "TwoVTwo",
    ["3v3"] = "ThreeVThree",
    ["4v4"] = "FourVFour",
}

-- Map positioning (for concurrent matches)
MatchmakingConfig.MapPositioning = {
    StartOffset = Vector3.new(5000, 0, 0),  -- Far from lobby
    Increment = Vector3.new(2000, 0, 0),     -- 2000 studs apart
    MaxConcurrentMaps = 10,
}

-- Queue settings
MatchmakingConfig.Queue.CountdownDuration = 5
MatchmakingConfig.Queue.PadTag = "QueuePad"
MatchmakingConfig.Queue.DefaultZoneSize = Vector3.new(8, 10, 8)

-- Spawn tags
MatchmakingConfig.Spawns.LobbyTag = "LobbySpawn"
MatchmakingConfig.Spawns.TrainingTag = "TrainingSpawn"
```

---

## API Reference

### MatchManager (Server)

```lua
-- Create a new match (called by QueueService)
MatchManager:CreateMatch({
    mode = "Duel",
    team1 = { userId1 },
    team2 = { userId2 },
    mapId = "Map",  -- optional, defaults to MatchmakingConfig.DefaultMap
}) -- returns matchId

-- End a match
MatchManager:EndMatch(matchId, winnerTeam)

-- Query matches
MatchManager:GetMatch(matchId)           -- Match data or nil
MatchManager:GetMatchForPlayer(player)   -- Match data or nil
MatchManager:GetActiveMatches()          -- { [matchId] = matchData }
MatchManager:GetPlayerTeam(match, player) -- "Team1", "Team2", or nil

-- Kill handling (call from CombatService)
MatchManager:OnPlayerKilled(killerPlayer, victimPlayer)
```

### MapLoaderService (Server)

```lua
-- Load a map at a position
MapLoaderService:LoadMap(mapId, position) -- returns { instance, spawns }

-- Unload a map
MapLoaderService:UnloadMap(mapInstance)

-- Get spawn references
MapLoaderService:GetSpawns(mapInstance) -- { Team1 = spawn, Team2 = spawn }

-- Query
MapLoaderService:GetAvailableMaps()  -- { "Map", ... }
MapLoaderService:GetLoadedMaps()     -- Active maps info
```

### QueueService (Server)

```lua
-- Query queue state
QueueService:GetQueuedPlayers(padName) -- { Team1 = {}, Team2 = {} }
QueueService:IsPlayerQueued(player)    -- boolean

-- Admin controls
QueueService:ForceStartMatch(padName)  -- Skip countdown
```

### RoundService (Server)

Now handles only Training mode:

```lua
-- Training mode
RoundService:AddPlayer(player)        -- Join training
RoundService:RemovePlayer(player)     -- Leave training
RoundService:IsPlayerInTraining(player)
RoundService:GetTrainingPlayers()
```

### QueueController (Client)

```lua
QueueController:IsInQueue()             -- boolean
QueueController:GetCountdownRemaining() -- number or nil
```

---

## Network Events

### Queue Events

| Event | Data | Description |
|-------|------|-------------|
| `QueuePadUpdate` | `{ padName, team, occupied, playerId }` | Pad state changed |
| `QueueCountdownStart` | `{ padName, duration }` | Countdown began |
| `QueueCountdownTick` | `{ padName, remaining }` | Countdown update |
| `QueueCountdownCancel` | `{ padName }` | Countdown cancelled |
| `QueueMatchReady` | `{ padName, team1, team2, mode }` | Match starting |

### Match Events

| Event | Data | Description |
|-------|------|-------------|
| `MatchStart` | `{ matchId, mode, team1, team2 }` | Match created |
| `RoundStart` | `{ matchId, roundNumber, scores }` | Round began |
| `RoundKill` | `{ matchId, killerId, victimId }` | Kill occurred |
| `ScoreUpdate` | `{ matchId, team1Score, team2Score }` | Score changed |
| `ShowRoundLoadout` | `{ matchId, duration, scores }` | Show loadout UI |
| `MatchEnd` | `{ matchId, winnerId, winnerTeam, finalScores }` | Match complete |
| `ReturnToLobby` | `{ matchId }` | Return to lobby |
| `PlayerLeftMatch` | `{ matchId, playerId }` | Player left |

### Map Events

| Event | Data | Description |
|-------|------|-------------|
| `MapLoaded` | `{ mapId, mapName }` | Map cloned to workspace |
| `MapUnloaded` | `{ mapId, mapName }` | Map destroyed |

---

## Workspace Setup

### Queue Pads (Lobby)

```
Lobby/
  Gadgets/
    Queue Pads/
      1v1  (Tag: "QueuePad")
        ├── Team1
        │   ├── Inner (BasePart - detection zone)
        │   └── Outer (BasePart - visual)
        └── Team2
            ├── Inner
            └── Outer
      2v2  (Tag: "QueuePad")
        ├── Team1
        └── Team2
```

### Map Template (ServerStorage)

```
ServerStorage/
  Maps/
    Map  (Model)
      ├── Base (geometry)
      ├── Bedrock (geometry)
      └── SpawnLocations
          ├── Spawn1 (Team1 spawn)
          └── Spawn2 (Team2 spawn)
```

### Lobby Return Spawns

```
Lobby/
  LobbySpawn  (Tag: "LobbySpawn")
```

### Training Area

```
TrainingArea/
  TrainingSpawn_1  (Tag: "TrainingSpawn")
  TrainingSpawn_2
  TrainingSpawn_3
```

---

## Match Flow

### Competitive Match (1v1 Duel)

```
1. Player A steps on 1v1/Team1 → added to queue
2. Player B steps on 1v1/Team2 → added to queue
3. Both teams have 1 player → 5s countdown starts
4. Countdown complete:
   a. QueueService calls MatchManager:CreateMatch()
   b. MatchManager allocates position (e.g., X=5000)
   c. MapLoaderService clones map to position
   d. Players teleported to Spawn1/Spawn2
   e. MatchStart event fired
5. Gameplay:
   - Player kills tracked per match
   - Killer's team gets +1 score
   - Both players respawn at their spawns
   - Loadout UI for 15s between rounds
6. Match ends (first to 5):
   a. Winner announced
   b. 5s delay
   c. Players teleported to lobby
   d. Map destroyed
   e. Position recycled to pool
```

### Multiple Concurrent Matches

```
Match 1: Loaded at X=5000
Match 2: Loaded at X=7000
Match 3: Loaded at X=9000
...
Match 10: Loaded at X=23000

When Match 1 ends → X=5000 returned to pool
New match → Uses X=5000 again
```

---

## File Structure

```
src/
├── ReplicatedStorage/
│   └── Configs/
│       └── MatchmakingConfig.lua       # All mode & queue settings
│
├── ServerScriptService/
│   └── Server/
│       ├── Initializer.server.lua      # Service registration
│       └── Services/
│           ├── Map/
│           │   └── MapLoaderService.lua    # Map cloning & positioning
│           ├── Match/
│           │   ├── MatchManager.lua        # Multi-match management
│           │   └── MatchService.lua        # Loadout handling
│           ├── Queue/
│           │   └── QueueService.lua        # Queue pads & countdown
│           └── Round/
│               └── RoundService.lua        # Training mode only
│
└── StarterPlayer/
    └── StarterPlayerScripts/
        └── Initializer/
            └── Controllers/
                └── Queue/
                    └── QueueController.lua  # Client UI
```

---

## Combat Integration

To integrate kills with the matchmaking system:

```lua
-- In CombatService when a player dies:
local MatchManager = registry:TryGet("MatchManager")
local RoundService = registry:TryGet("Round")

if MatchManager then
    local match = MatchManager:GetMatchForPlayer(victimPlayer)
    if match then
        -- Player is in a competitive match
        MatchManager:OnPlayerKilled(killerPlayer, victimPlayer)
        return
    end
end

if RoundService and RoundService:IsPlayerInTraining(victimPlayer) then
    -- Player is in training mode - handled by RoundService
    return
end
```

---

## Adding Custom Modes

```lua
-- In MatchmakingConfig.lua

-- 1. Add the mode definition
MatchmakingConfig.Modes.FiveVFive = {
    name = "5v5",
    hasTeams = true,
    hasScoring = true,
    playersPerTeam = 5,
    scoreToWin = 25,
    allowJoinMidway = false,
    roundResetDelay = 3,
    loadoutSelectionTime = 10,
    showLoadoutOnRoundReset = true,
    lobbyReturnDelay = 5,
    returnToLobbyOnEnd = true,
}

-- 2. Add the pad name mapping
MatchmakingConfig.ModeNameMapping["5v5"] = "FiveVFive"
```

Then create a queue pad named `5v5` with `Team1` and `Team2` children.

---

## StreamingEnabled Note

For maps to not render from lobby:
- Ensure `Workspace.StreamingEnabled = true`
- Maps placed 5000+ studs away will naturally not stream to players in lobby
- When players teleport to map, it streams in for them
