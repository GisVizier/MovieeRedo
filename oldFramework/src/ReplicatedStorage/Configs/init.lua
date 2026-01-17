local Config = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ConfigsFolder = ReplicatedStorage.Configs

-- Import consolidated config modules
Config.Gameplay = require(ConfigsFolder:WaitForChild("GameplayConfig"))
Config.Controls = require(ConfigsFolder:WaitForChild("ControlsConfig"))
Config.System = require(ConfigsFolder:WaitForChild("SystemConfig"))
Config.Audio = require(ConfigsFolder:WaitForChild("AudioConfig"))
Config.Animation = require(ConfigsFolder:WaitForChild("AnimationConfig"))
Config.Interactable = require(ConfigsFolder:WaitForChild("InteractableConfig"))
Config.Round = require(ConfigsFolder:WaitForChild("RoundConfig"))
Config.Health = require(ConfigsFolder:WaitForChild("HealthConfig"))
-- Config.Weapon archived - focus on movement only

-- Validate configuration at startup (only in test mode)
local function validateConfiguration()
	-- Only validate in test environments to avoid blocking production
	local TestMode = require(ReplicatedStorage:WaitForChild("TestMode"))
	if not TestMode.ENABLED then
		return
	end

	-- Delayed require to avoid circular dependencies
	local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
	local ConfigValidator = require(Locations.Modules.Utils.ConfigValidator)

	local success, err = pcall(function()
		ConfigValidator:ValidateConfig(Config)
	end)

	if not success then
		warn("[CONFIG] Validation failed:", err)
		warn("[CONFIG] Game will continue but config validation should be fixed")
	end
end

-- Run validation
validateConfiguration()

return Config
