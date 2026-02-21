# Party System

## Overview

Server-authoritative party system allowing players to group up and queue for team-based game modes together. Party members always play on the same team.

## Architecture

```
Client (PlayerList module)          Server (PartyService)
─────────────────────────           ────────────────────
PlayerShow card                     _parties[partyId]
  → InviteParty button  ──────►    InvitePlayer()
                                      │
Invite banner (5s timer)  ◄──────   PartyInviteReceived
  → Accept / Decline     ──────►    AcceptInvite() / DeclineInvite()
                                      │
PartyUpdate event         ◄──────   Broadcast to all members
PlayerList InParty section            └── sets Player attributes
```

## Server: PartyService

**Location**: `ServerScriptService.Server.Services.Party.PartyService`

### Data Structures

| Field | Type | Description |
|---|---|---|
| `_parties[partyId]` | table | `{ id, leaderId, members={userId,...}, maxSize=5, createdAt }` |
| `_playerToParty[userId]` | string | Maps player to their partyId |
| `_pendingInvites[targetUserId]` | table | `{ fromUserId, partyId, expiresAt, timeoutThread }` |

### Constants

| Name | Default | Description |
|---|---|---|
| `MAX_PARTY_SIZE` | 5 | Maximum members per party |
| `INVITE_TIMEOUT` | 5 | Seconds before invite auto-declines |

### Public API

| Method | Description |
|---|---|
| `GetParty(player)` | Returns party data or nil |
| `GetPartyMembers(player)` | Returns `{userId, ...}` for queue integration |
| `IsInParty(player)` | Boolean check |
| `GetPartySize(player)` | Number of members |
| `IsPartyLeader(player)` | Boolean check |

### Internal Flow

1. **Invite**: Leader clicks "PARTY INVITE" on PlayerShow → `PartyInviteSend` remote → server validates → creates party if leader has none → sends `PartyInviteReceived` to target
2. **Accept**: Target clicks "ACCEPT" or receives event → `PartyInviteResponse(accept=true)` → server adds to party → broadcasts `PartyUpdate` to all members
3. **Decline / Timeout**: Target clicks "DECLINE" or 5s expires → `PartyInviteResponse(accept=false)` → server notifies sender
4. **Busy**: If target already has a pending invite → server fires `PartyInviteBusy` to sender
5. **Kick**: Leader calls kick method → `_removeMember(party, target, true)` → fires `PartyKicked` to kicked player → if ≤1 member left, auto-disbands → otherwise `PartyUpdate` broadcast
6. **Leave**: Non-leader fires `PartyLeave` → `_removeMember(party, player, false)` → fires `PartyDisbanded` to leaving player (NOT `PartyKicked`) → if ≤1 member left, auto-disbands → otherwise `PartyUpdate` broadcast
7. **Disband**: Leader fires `PartyLeave` → `_disbandParty` → fires `PartyDisbanded` to ALL members
8. **Disconnect**: `PlayerRemoving` → if leader, disband; if non-leader, start offline grace timer (300s) → auto-removed if not back

### Player Attributes Set

| Attribute | Value | Description |
|---|---|---|
| `InParty` | boolean | Whether player is in a party |
| `PartyId` | string | Current party ID |
| `PartyLeader` | boolean | Whether player is party leader |

## Client: PlayerList Integration

### PlayerShow Card

Located at `game.StarterGui.Gui.PlayerList.PlayerShow`. Shown when a player row is clicked in the PlayerList.

**Elements populated**:
- `Frame.userHolder.PlayerImage` — headshot thumbnail
- `Frame.userHolder.NameHolder.Username` — display name
- `Frame.userHolder.Status` — @username
- `Frame.Status.Aim` — "IN GAME" / "Lobby" / "In Party"
- `Frame.InPartyDisplay.NameHolder.Username` — "CLOSED PARTY" (static for now)
- `Frame.InPartyDisplay.NameHolder.Icon` — "X/5" member count
- `Frame.InviteParty` — sends invite when clicked (hidden if not applicable)

**Visibility rules**:
- `InviteParty` visible when: you are party leader (or have no party), target is not in your party, target is not in a match
- `InPartyDisplay` visible when: target is in a party

### Invite Banner

Located at `game.StarterGui.Gui.PlayerList.Holder.Frame.Frame.Holder.ScrollingFrame.Invite`. Shown inside the PlayerList scroll area when an invite is received.

**Elements**:
- `InviteHolder.Username` — inviter display name
- `InviteHolder.Invited` — "HAS INVITED YOU!"
- `InviteHolder.PlayerImage` — inviter thumbnail
- `LoadingHolder.Accept` (first) — ACCEPT button
- `LoadingHolder.Accept` (second) — DECLINE button
- `_` — progress bar frame, tweened from full width to 0 over INVITE_TIMEOUT seconds

**Behavior**:
- One invite at a time
- 5-second timer (adjustable via `INVITE_TIMEOUT`)
- Auto-declines on expiration
- Accept/Decline fires `PartyInviteResponse` to server

### InParty Section

Players in the same party appear in the "IN PARTY" section of the PlayerList with a shared party color applied to their glow effect.

## Remote Events

| Remote | Direction | Payload |
|---|---|---|
| `PartyInviteSend` | Client → Server | `{ targetUserId }` |
| `PartyInviteReceived` | Server → Client | `{ fromUserId, fromDisplayName, fromUsername, partyId, timeout }` |
| `PartyInviteResponse` | Client → Server | `{ accept = bool }` |
| `PartyUpdate` | Server → Client | `{ partyId, leaderId, members = {userId,...}, maxSize }` |
| `PartyInviteBusy` | Server → Client | `{ targetUserId, reason }` |
| `PartyInviteDeclined` | Server → Client | `{ targetUserId }` |
| `PartyKick` | Client → Server | `{ targetUserId }` |
| `PartyLeave` | Client → Server | `{}` |
| `PartyDisbanded` | Server → Client | `{ partyId }` — sent on voluntary leave, disband, or timeout removal |
| `PartyKicked` | Server → Client | `{ partyId }` — sent ONLY when a player is kicked by the leader |

## Queue Integration

**QueueService changes**:
- When a player enters a queue zone, check if they are in a party
- If in a party: ALL party members must also be in zones for the same pad
- Party members fill one team (always Team1 side of their pad zones)
- Countdown only starts when both teams have required players
- Block queuing if party size doesn't match mode's `playersPerTeam`

## Match Integration

**MatchManager changes**:
- `CreateMatch` receives party info from QueueService
- Party members are placed on the same team
- On match end, party persists — members return to lobby still grouped
- On disconnect, player is removed from both match AND party

## Cross-Server Persistence

Party data persists across servers via:

- **MemoryStoreService**: Party data stored in HashMaps keyed by partyId (TTL = 3600s). Player→party mapping in separate HashMap.
- **MessagingService**: Topic `PartyEvents` broadcasts update/disband/kick actions to other servers in real-time.
- **On player join**: Checks MemoryStore for existing party membership. If found, restores local party state and broadcasts update.
- **Offline grace**: Non-leader disconnect starts a 300s timer. If they rejoin any server within that window, party is restored. If not, they are auto-removed.
- **Leader disconnect**: Party is immediately disbanded for all members across all servers.

## Files Modified

| File | Change |
|---|---|
| `Services/Party/PartyService.lua` | **NEW** — Server-side party logic |
| `Shared/Net/Remotes.lua` | **EDIT** — Add 9 party remotes |
| `Server/Initializer.server.lua` | **EDIT** — Register PartyService |
| `CoreUI/Modules/PlayerList/init.lua` | **EDIT** — PlayerShow + Invite + InParty |
| `CoreUI/Modules/Party.lua` | **EDIT** — Wire to real server data |
| `Controllers/UI/UIController.lua` | **EDIT** — Wire party network events |
| `Services/Queue/QueueService.lua` | **EDIT** — Party-aware queuing |
| `Services/Match/MatchManager.lua` | **EDIT** — Party-aware team assignment |
