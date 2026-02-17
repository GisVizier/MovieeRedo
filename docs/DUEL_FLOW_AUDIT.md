# Duel Flow Audit

## Summary

The Duel flow is **correct and complete**. A few bugs were fixed and minor notes documented.

---

## Flow Verification

| Phase | Status | Notes |
|-------|--------|-------|
| Queue → CreateMatch | ✓ | QueueService countdown → CreateMatch with Duel mode |
| Map Selection (20s) | ✓ | ShowMapSelection → SubmitMapVote → MapVoteUpdate → MapVoteResult |
| Map Load + Teleport | ✓ | _loadMapAndTeleport → MatchTeleport → MatchTeleportReady |
| Loadout (30s, frozen) | ✓ | _startLoadoutPhase → ShowRoundLoadout → SubmitLoadout, early confirm halves timer |
| Round Start | ✓ | _startMatchRound → unfreeze, revive, MatchStart, RoundStart |
| Elimination | ✓ | OnPlayerKilled → _deadThisRound → team wipe check → score or _resetRound |
| Round Reset | ✓ | _resetRound: revive, freeze, teleport, 10s delay → next round |
| Match End | ✓ | EndMatch → MatchEnd → lobby return delay → _cleanupMatch → ReturnToLobby |

---

## Fixes Applied

1. **`_returnPlayersToLobby`** – Fixed `for i, userId in userIds` → `for i, userId in ipairs(userIds)` (Lua requires an iterator for table iteration).

2. **`SubmitMapVote`** – Added validation that `mapId` is in `match._mapPool` to prevent invalid map selection.

3. **`MATCH_ROUND_SYSTEM.md`** – Clarified that round reset does not show loadout between rounds; M-key loadout changes do not persist.

---

## Known Limitations (Not Bugs)

- **showLoadoutOnRoundReset** – Config flag exists but is never used. Round reset goes straight to the next round after 10s freeze.
- **M-key loadout during between rounds** – Opens loadout UI, but `SubmitLoadout` is rejected (state ≠ loadout_selection). Changes do not persist.
- **MapConfig vs ServerStorage.Maps** – MapConfig IDs (DirtyDepo, ApexArena, etc.) must match folder/model names in `ServerStorage.Maps`.
- **FireAllClients** – MatchStart, RoundStart, ScoreUpdate, RoundKill broadcast to all players. Could use `_fireMatchClients` for match-only if spectators are added later.

---

## Map Pool (Duel = 2 players)

For 2 players, `MapConfig.getMapsForPlayerCount(2)` returns:
- TrainingGrounds (1–99)
- DirtyDepo (2–4)
- ApexArena (2–12)

Ensure `ServerStorage.Maps` contains models/folders with these exact names.
