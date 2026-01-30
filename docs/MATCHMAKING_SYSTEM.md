# Matchmaking System

A simple, modular matchmaking system for queue-based matches. Supports 1v1 through NvN with zero code changes.

## Quick Start

1. **Place queue pads** in your lobby
2. **Tag them** with `QueuePad` and set `Team` attribute
3. **Tag arena spawns** with `ArenaSpawn_Team1` / `ArenaSpawn_Team2`
4. **Done** - players step on pads, countdown starts, match begins

---

## Configuration

All settings in `ReplicatedStorage/Configs/MatchmakingConfig.lua`:

```lua
-- Queue
MatchmakingConfig.Queue.CountdownDuration = 5       -- Seconds before match
MatchmakingConfig.Queue.PadTag = "QueuePad"         -- CollectionService tag

-- Match
MatchmakingConfig.Match.ScoreToWin = 5              -- First to X wins
MatchmakingConfig.Match.LoadoutSelectionTime = 15   -- Between rounds

-- Gamemodes (add as many as you want)
MatchmakingConfig.Gamemodes = {
    Duel = { playersPerTeam = 1, scoreToWin = 5 },
    TwoVTwo = { playersPerTeam = 2, scoreToWin = 10 },
}
```

---

## Workspace Setup

### Queue Pads

| Property | Value | Description |
|----------|-------|-------------|
| Tag | `QueuePad` | CollectionService tag |
| Attribute: `Team` | `"Team1"` or `"Team2"` | Which team this pad queues for |
| Attribute: `ZoneSize` | `Vector3` (optional) | Detection zone size, default 8x10x8 |

**Example naming:** `QueuePad_Team1`, `QueuePad_Team2`

### Arena Spawns

| Property | Value | Description |
|----------|-------|-------------|
| Tag | `ArenaSpawn_Team1` | Team 1 spawn points |
| Tag | `ArenaSpawn_Team2` | Team 2 spawn points |
| Attribute: `MapId` | `"ApexArena"` etc | Links spawn to specific map |

**Example naming:** `ArenaSpawn_Team1_1`, `ArenaSpawn_Team2_1`

### Lobby Return

| Property | Value |
|----------|-------|
| Tag | `LobbySpawn` |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                         SERVER                                │
│                                                               │
│   QueueService              RoundService                      │
│   ├── Zone detection        ├── Score tracking                │
│   ├── Countdown logic       ├── Round loop                    │
│   └── Match creation        └── Spawn management              │
│                                                               │
└──────────────────────────────────────────────────────────────┘
                              │
                         Network Events
                              │
┌──────────────────────────────────────────────────────────────┐
│                         CLIENT                                │
│                                                               │
│   QueueController                                             │
│   ├── Countdown UI                                            │
│   ├── Pad visuals                                             │
│   └── Event handling                                          │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

## API Reference

### QueueService (Server)

```lua
-- Get queued players
local queued = QueueService:GetQueuedPlayers()
-- Returns: { Team1 = { player1 }, Team2 = { player2 } }

-- Check if player is in queue
local inQueue = QueueService:IsPlayerQueued(player)

-- Force start (admin/debug)
QueueService:ForceStartMatch()
```

### RoundService (Server)

```lua
-- Get current match
local match = RoundService:GetActiveMatch()

-- Get scores
local scores = RoundService:GetScores()
-- Returns: { Team1 = 3, Team2 = 2 }

-- Hook into kills (call from CombatService)
RoundService:OnPlayerKilled(killerPlayer, victimPlayer)

-- Force end match
RoundService:EndMatch("forfeit")
```

### QueueController (Client)

```lua
-- Check queue status
local inQueue = QueueController:IsInQueue()

-- Get countdown
local remaining = QueueController:GetCountdownRemaining()
```

---

## Network Events

### Queue Events

| Event | Data | Description |
|-------|------|-------------|
| `QueuePadUpdate` | `{ padId, team, occupied, playerId }` | Pad state changed |
| `QueueCountdownStart` | `{ duration }` | Countdown began |
| `QueueCountdownTick` | `{ remaining }` | Countdown update |
| `QueueCountdownCancel` | `{ }` | Player left, reset |
| `QueueMatchReady` | `{ team1, team2 }` | Match starting |

### Round Events

| Event | Data | Description |
|-------|------|-------------|
| `RoundStart` | `{ roundNumber, scores }` | Round began |
| `RoundKill` | `{ killerId, victimId }` | Kill occurred |
| `ScoreUpdate` | `{ team1Score, team2Score }` | Score changed |
| `ShowRoundLoadout` | `{ duration, scores }` | Show loadout UI |
| `MatchEnd` | `{ winnerId, winnerTeam, finalScores }` | Match complete |
| `ReturnToLobby` | `{ }` | Go back to lobby |

---

## Scaling to NvN

### Add a new gamemode:

```lua
MatchmakingConfig.Gamemodes.FourVFour = {
    name = "4v4",
    playersPerTeam = 4,
    scoreToWin = 20,
}
```

### Add pads (4 per team for 4v4):

```
Lobby/
  QueuePad_Team1_1  (Tag: QueuePad, Team: "Team1")
  QueuePad_Team1_2
  QueuePad_Team1_3
  QueuePad_Team1_4
  QueuePad_Team2_1  (Tag: QueuePad, Team: "Team2")
  QueuePad_Team2_2
  QueuePad_Team2_3
  QueuePad_Team2_4
```

### Add spawns (4 per team):

```
Map/
  ArenaSpawn_Team1_1  (Tag: ArenaSpawn_Team1)
  ArenaSpawn_Team1_2
  ArenaSpawn_Team1_3
  ArenaSpawn_Team1_4
  ArenaSpawn_Team2_1  (Tag: ArenaSpawn_Team2)
  ...
```

**That's it.** Zero code changes needed.

---

## Match Flow

```
1. Players step on pads
   └── Pad turns green

2. Both teams full
   └── 5 second countdown starts
   └── Countdown GUI shows

3. Player steps off
   └── Countdown cancels
   └── GUI hides

4. Countdown completes
   └── Map selection UI shows

5. Map selected
   └── Loadout UI shows (30s)

6. Loadout complete
   └── Players teleport to arena
   └── HUD shows, round starts

7. Player killed
   └── Killer's team +1 score
   └── Both players reset to spawns
   └── Loadout UI shows (15s)

8. Score reaches target
   └── Match ends
   └── Victory screen
   └── Return to lobby
```

---

## File Structure

```
src/
├── ReplicatedStorage/
│   └── Configs/
│       └── MatchmakingConfig.lua
│
├── ServerScriptService/
│   └── Server/
│       └── Services/
│           ├── Queue/
│           │   └── QueueService.lua
│           └── Round/
│               └── RoundService.lua
│
└── StarterPlayer/
    └── StarterPlayerScripts/
        └── Initializer/
            └── Controllers/
                └── Queue/
                    └── QueueController.lua
```

---

## Integration with Combat

In your `CombatService` or wherever you handle player death:

```lua
-- When a player is killed
local RoundService = registry:Get("Round")
if RoundService:GetActiveMatch() then
    RoundService:OnPlayerKilled(killerPlayer, victimPlayer)
end
```

---

## Debug Commands (Optional)

```lua
-- Force start with current players
QueueService:ForceStartMatch()

-- End current match
RoundService:EndMatch("admin")

-- Get queue state
print(QueueService:GetQueuedPlayers())
```
