# Client Systems

## 📦 Drag & Drop Ready

This folder contains client-side systems. Each system folder can be moved independently.

## Systems

### 🔄 Replication/
**Network replication system** - Syncs character states between clients
- **ClientReplicator.lua** - Sends your character state to server
- **RemoteReplicator.lua** - Receives other players' states
- **ReplicationDebugger.lua** - Debug tools

### 🎨 Viewmodel/
**First-person viewmodel system** - Handles weapon rendering in first-person
- Viewmodel creation, ADS, effects, animations

## Usage

Systems are initialized automatically by `Initializer.client.lua`.

## Dependencies

- Systems use `Locations` for module paths
- Systems use `RemoteEvents` for networking
- Systems use `Config` for settings

