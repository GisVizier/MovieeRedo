# Match & Round System

## Flow

```
Queue Pad (both teams step on)
  → Match Created (no map yet)
  → Map Selection (20s) — players vote from pool
  → Map Loaded at remote position
  → Players Teleported to map
  → Loadout Phase (30s, frozen) — pick weapons
    → All confirm early? Halve remaining timer
  → Round Start (unfreeze, FPS camera, HUD)
  → Elimination round — no respawns, team wipe ends round
  → Round Over (10s freeze, preserve ult)
  → Next round (no loadout phase between rounds)
  → Match ends when a team reaches scoreToWin
  → Players returned to lobby
```

## Phases

### Map Selection (20s)
- Server fires `ShowMapSelection` to match players with map pool + duration
- Clients show Map UI (team lineup, map cards, vote blips)
- Client clicks map → `SubmitMapVote` to server
- Server broadcasts `MapVoteUpdate` so other players see blips
- Timer expires or all voted → server picks winning map (most votes, random tiebreak)
- Server loads map via MapLoaderService, allocates position

### Loadout Phase (30s, players frozen)
- Server fires `ShowRoundLoadout` with `duration = 30`
- Server sets `ExternalMoveMult = 0` on match players (freezes movement)
- Client shows Loadout UI, camera switches to Orbit
- Players pick Kit + Primary + Secondary + Melee
- On `SubmitLoadout`: if ALL players submitted, halve remaining loadout timer
- Timer expires → server sets `ExternalMoveMult = 1`, fires `RoundStart`

### During Round (Elimination)
- Players fight, no respawns within the round
- On kill → check if victim's entire team is wiped
  - Not wiped → continue (dead player stays dead)
  - Team wiped → other team wins the round, round score +1
- Check match win condition (scoreToWin)
  - Won → `MatchEnd`, return to lobby
  - Not won → Round Reset

### Round Reset (10s between rounds)
- Round ends → server **immediately** revives all players, teleports to initial spawns
- Players are **frozen** for 10s (no movement, no abilities, no weapons)
- Players are in **first person**, HUD visible
- Press **M** to optionally view loadout during the 10s (changes do not persist; previous loadout kept)
- **Preserves ultimate meter** across rounds
- After 10s → unfreeze, round starts (no loadout phase between rounds)

## Key Timers

| Phase | Duration |
|-------|----------|
| Map Selection | 20s |
| Loadout | 30s (halved on early confirm) |
| Between Rounds | 10s |

## Network Events (New)

| Event | Direction | Data |
|-------|-----------|------|
| `ShowMapSelection` | S→C | `{ matchId, duration, mapPool, teams, players }` |
| `SubmitMapVote` | C→S | `{ mapId }` |
| `MapVoteUpdate` | S→C | `{ mapId, oduserId }` |
| `MapVoteResult` | S→C | `{ matchId, winningMapId }` |
| `BetweenRoundFreeze` | S→C | `{ matchId, duration, roundNumber, scores }` |

## Files Modified

- `MatchmakingConfig.lua` — timers, flags
- `Remotes.lua` — new events
- `MatchManager.lua` — map selection phase, elimination rounds, freeze, ult preservation
- `UIController.lua` — wire Map module into competitive flow
- `Map/init.lua` — competitive mode, server duration, vote wiring
- `Loadout/init.lua` — server duration support
- `CombatService.lua` — ult preservation on competitive death

## Notes
- **MapConfig vs ServerStorage.Maps**: MapConfig IDs (DirtyDepo, ApexArena, etc.) must match folder/model names in `ServerStorage.Maps`.
- **showLoadoutOnRoundReset**: Config flag exists but is not implemented; rounds reset directly without loadout phase.

## Future Work (Not Implemented)
- Spectate camera (killer free-spectate 10s, dead team locked to allies)
- Sudden death storm (shrink zone on time limit)
- Post-round kill cam
