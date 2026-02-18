--[[
	Default player data structure for Anime FPS.
	Must match PlayerDataTable API and be DataStore-serializable
	(no Enum, Vector3, Color3, Instances, functions).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local SettingsConfig = require(Configs:WaitForChild("SettingsConfig"))

local function serializeForDataStore(value)
	if typeof(value) == "table" then
		local out = {}
		for k, v in value do
			out[k] = serializeForDataStore(v)
		end
		return out
	elseif typeof(value) == "EnumItem" then
		return tostring(value)
	else
		return value
	end
end

local function getDefaultSettings()
	local defaults = SettingsConfig.DefaultSettings or {}
	local serialized = {}
	for category, settings in defaults do
		serialized[category] = {}
		for key, value in settings do
			serialized[category][key] = serializeForDataStore(value)
		end
	end
	return serialized
end

return {
	-- ProfileStore metadata (set by server)
	LastOnline = 0,
	FirstJoin = nil, -- Set by OnFirstJoin for new players

	-- Stats (leaderboard, etc.) - matches mock table
	GEMS = 0,
	CROWNS = 0,
	WINS = 0,
	STREAK = 0,

	EMOTES = {},

	-- Owned items (by category) - matches mock table structure
	OWNED = {
		OWNED_EMOTES = { "Template", "SBR", "BC", "CR", "FR", "HS", "SB", "BMB" },
		OWNED_KITS = { "WhiteBeard", "Genji", "Aki", "Airborne", "HonoredOne" },
		OWNED_PRIMARY = { "Shotgun", "Sniper" },
		OWNED_SECONDARY = { "Revolver", "Shorty", "DualPistols" },
		OWNED_MELEE = { "Tomahawk", "ExecutionerBlade" },
	},

	-- Equipped loadout
	EQUIPPED = {
		Kit = nil,
		Primary = "Shotgun",
		Secondary = "Revolver",
		Melee = "Tomahawk",
	},

	EQUIPPED_SKINS = {},

	EQUIPPED_EMOTES = {
		Slot1 = "Template",
		Slot2 = "SBR",
		Slot3 = "BMB",
		Slot4 = "BC",
		Slot5 = "SB",
		Slot6 = "CR",
		Slot7 = "HS",
		Slot8 = "FR",
	},

	OWNED_SKINS = {
		Revolver = { "Energy" },
		Shotgun = { "OGPump" },
		Tomahawk = { "Cleaver" },
	},

	-- Per-weapon customization (kill effects, etc.)
	WEAPON_DATA = {},

	-- Per-category settings (Gameplay, Controls, Crosshair)
	Settings = getDefaultSettings(),
}
