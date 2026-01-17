# Network Replication System

## 📦 Drag & Drop Ready

This folder contains the complete network replication system. You can move this entire folder independently.

## What's Inside

- **ClientReplicator.lua** - Sends local player state to server (60Hz)
- **RemoteReplicator.lua** - Receives and interpolates other players' states
- **ReplicationDebugger.lua** - Debug tools for replication

## How It Works

1. **ClientReplicator** - Your character sends position/rotation/velocity to server
2. **ServerReplicator** (in ServerScriptService) - Server broadcasts to all clients
3. **RemoteReplicator** - Other clients receive and smoothly interpolate your character

## Usage

Replication runs automatically. No manual setup needed.

## Dependencies

- Uses `Config.Replication` for settings
- Uses `Locations` for module paths
- Uses `CompressionUtils` for data compression

