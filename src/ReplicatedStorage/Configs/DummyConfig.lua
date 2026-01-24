--[[
	DummyConfig.lua
	Configuration values for the Dummy Target System
]]

local DummyConfig = {}

-- Spawn markers location
DummyConfig.SpawnFolder = "workspace.World.DummySpawns"
DummyConfig.MarkerName = "DummySpawn"

-- Template location
DummyConfig.TemplatePath = "ServerStorage.Models.Dummy"

-- Dummy settings
DummyConfig.Health = 150
DummyConfig.MaxHealth = 150

-- Respawn settings
DummyConfig.RespawnDelay = 3  -- Seconds after death before respawn

-- Spawn emote settings
DummyConfig.SpawnEmote = {
	Enabled = true,
	LoopDuration = 30,  -- Stop looped emotes after this many seconds
	ReplicateDistance = 150,  -- Only send emote to players within this distance (studs)
}

-- Combat integration
DummyConfig.CombatEnabled = true  -- Enable CombatService integration

return DummyConfig
