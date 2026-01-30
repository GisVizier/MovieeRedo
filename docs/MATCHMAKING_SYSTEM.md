# Matchmaking System

A simple, modular matchmaking and round system. Supports both **Training** (infinite) and **Competitive** (lives) modes in a single service.

## Quick Start

### Competitive Mode (Duel, 2v2, etc.)
1. Place queue pads in lobby with tag `QueuePad` and `Team` attribute
2. Tag arena spawns with `ArenaSpawn_Team1` / `ArenaSpawn_Team2`
3. Players step on pads → countdown → match starts

### Training Mode
1. Tag training spawns with `TrainingSpawn`
2. Call `RoundService:StartMatch({ mode = "Training" })`
3. Players can join/leave anytime, respawn forever

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
    },
    -- Add custom modes here
}

-- Queue settings (competitive)
MatchmakingConfig.Queue.CountdownDuration = 5
MatchmakingConfig.Queue.PadTag = "QueuePad"

-- Spawn tags
MatchmakingConfig.Spawns.Team1Tag = "ArenaSpawn_Team1"
MatchmakingConfig.Spawns.Team2Tag = "ArenaSpawn_Team2"
MatchmakingConfig.Spawns.TrainingTag = "TrainingSpawn"
MatchmakingConfig.Spawns.LobbyTag = "LobbySpawn"
```

---

## API Reference

### RoundService (Server)

```lua
-- Start a match
RoundService:StartMatch({
    mode = "Training",      -- or "Duel", "TwoVTwo", etc.
    mapId = "ApexArena",    -- optional
    -- For competitive modes:
    team1 = { userId1 },
    team2 = { userId2 },
    -- For training mode:
    players = { userId1, userId2 },  -- optional, can join later
})

-- End current match
RoundService:EndMatch()

-- Manual round control
RoundService:StartRound()
RoundService:EndRound()

-- Player management (training mode)
RoundService:AddPlayer(player)      -- Join midway
RoundService:RemovePlayer(player)   -- Leave match

-- Kill handling (call from CombatService)
RoundService:OnPlayerKilled(killerPlayer, victimPlayer)

-- Queries
RoundService:GetActiveMatch()       -- Current match data
RoundService:GetScores()            -- { Team1 = n, Team2 = n } or nil
RoundService:GetPlayers()           -- All players in match
RoundService:GetMode()              -- Current mode ID
RoundService:GetPlayerTeam(player)  -- "Team1", "Team2", or nil
RoundService:IsPlayerInMatch(player)
```

### QueueService (Server)

```lua
-- Query queue state
QueueService:GetQueuedPlayers()     -- { Team1 = {}, Team2 = {} }
QueueService:IsPlayerQueued(player) -- boolean

-- Admin controls
QueueService:ForceStartMatch()      -- Skip countdown
QueueService:SetGamemode(gamemodeId)
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
| `QueuePadUpdate` | `{ padId, team, occupied, playerId }` | Pad state changed |
| `QueueCountdownStart` | `{ duration }` | Countdown began |
| `QueueCountdownTick` | `{ remaining }` | Countdown update |
| `QueueCountdownCancel` | `{ }` | Countdown cancelled |
| `QueueMatchReady` | `{ team1, team2 }` | Match starting |

### Round Events

| Event | Data | Description |
|-------|------|-------------|
| `MatchStart` | `{ mode, mapId }` | Match started |
| `RoundStart` | `{ roundNumber, scores }` | Round began |
| `RoundKill` | `{ killerId, victimId }` | Kill occurred |
| `ScoreUpdate` | `{ team1Score, team2Score }` | Score changed |
| `ShowRoundLoadout` | `{ duration, scores }` | Show loadout UI |
| `MatchEnd` | `{ winnerId, winnerTeam, finalScores }` | Match complete |
| `ReturnToLobby` | `{ }` | Return to lobby |
| `PlayerJoinedMatch` | `{ playerId }` | Player joined (training) |
| `PlayerLeftMatch` | `{ playerId }` | Player left |
| `PlayerRespawned` | `{ }` | Player respawned |

---

## Workspace Setup

### Queue Pads (Competitive)

```
Lobby/
  QueuePad_Team1  (Tag: "QueuePad", Attr: Team="Team1")
  QueuePad_Team2  (Tag: "QueuePad", Attr: Team="Team2")
```

### Arena Spawns (Competitive)

```
Maps/ApexArena/
  ArenaSpawn_Team1  (Tag: "ArenaSpawn_Team1", Attr: MapId="ApexArena")
  ArenaSpawn_Team2  (Tag: "ArenaSpawn_Team2", Attr: MapId="ApexArena")
```

### Training Spawns

```
TrainingArea/
  TrainingSpawn_1  (Tag: "TrainingSpawn")
  TrainingSpawn_2
  TrainingSpawn_3
```

### Lobby Return

```
Lobby/
  LobbySpawn  (Tag: "LobbySpawn")
```

---

## Mode Behaviors

### Training Mode

```
Player joins → Spawn at random TrainingSpawn
Player dies  → Respawn after 2s at random spawn
              → Can open loadout UI anytime
              → No scoring, no rounds
Player leaves → Just removed from match
Match ends   → Only via RoundService:EndMatch()
```

### Competitive Mode (Duel, 2v2, etc.)

```
Queue fills  → 5 second countdown
Countdown    → Map select → Loadout → Match starts
Player kills → Killer's team +1 score
              → Both players reset to spawns
              → Loadout UI for 15s
              → Next round starts
Score = target → Match ends → Victory screen
              → Return to lobby after 5s
```

---

## Usage Examples

### Start Training Match

```lua
local RoundService = registry:Get("Round")

RoundService:StartMatch({
    mode = "Training",
    mapId = "ApexArena",
})
```

### Start Competitive Match

```lua
RoundService:StartMatch({
    mode = "Duel",
    mapId = "ApexArena",
    team1 = { player1.UserId },
    team2 = { player2.UserId },
})
```

### Join Training Midway

```lua
-- Player walks into training zone, call:
RoundService:AddPlayer(player)
```

### Handle Kill in Combat

```lua
-- In your CombatService when a player dies:
local RoundService = registry:Get("Round")
if RoundService:GetActiveMatch() then
    RoundService:OnPlayerKilled(killerPlayer, victimPlayer)
end
```

---

## Adding Custom Modes

```lua
-- In MatchmakingConfig.lua
MatchmakingConfig.Modes.CustomMode = {
    name = "Custom Mode",
    hasTeams = true,
    hasScoring = true,
    playersPerTeam = 3,
    scoreToWin = 7,
    allowJoinMidway = false,
    roundResetDelay = 3,
    loadoutSelectionTime = 10,
    showLoadoutOnRoundReset = true,
    lobbyReturnDelay = 5,
    returnToLobbyOnEnd = true,
}
```

Then use it:

```lua
RoundService:StartMatch({
    mode = "CustomMode",
    team1 = { ... },
    team2 = { ... },
})
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
│       └── Services/
│           ├── Queue/
│           │   └── QueueService.lua    # Queue pads & countdown
│           └── Round/
│               └── RoundService.lua    # Match & round management
│
└── StarterPlayer/
    └── StarterPlayerScripts/
        └── Initializer/
            └── Controllers/
                └── Queue/
                    └── QueueController.lua  # Client UI
```
