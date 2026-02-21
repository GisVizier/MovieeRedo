local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local AimAssistConfig = require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("AimAssist"):WaitForChild("AimAssistConfig"))
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))

local SettingsCallbacks = {}

local function getLocalPlayer()
	return Players.LocalPlayer
end

local function clampNumber(value, minValue, maxValue, fallback)
	local n = tonumber(value)
	if n == nil then
		return fallback
	end
	return math.clamp(n, minValue, maxValue)
end

local function getNumericAttribute(player, name, fallback)
	if not player then
		return fallback
	end
	local value = player:GetAttribute(name)
	if type(value) == "number" then
		return value
	end
	return fallback
end

local function applyMouseSensitivityFromSettings()
	local player = getLocalPlayer()
	if not player then
		return
	end

	local hipSensitivity = getNumericAttribute(player, "MouseSensitivityScale", UserInputService.MouseDeltaSensitivity or 1)
	local adsSensitivityScale = getNumericAttribute(player, "ADSSensitivityScale", 1)
	local adsSpeedMultiplier = getNumericAttribute(player, "ADSSpeedMultiplier", 1)
	local isADSActive = player:GetAttribute("WeaponADSActive") == true

	local targetSensitivity = hipSensitivity
	if isADSActive then
		targetSensitivity = hipSensitivity * adsSensitivityScale * adsSpeedMultiplier
	end

	UserInputService.MouseDeltaSensitivity = math.clamp(targetSensitivity, 0.01, 4)
end

SettingsCallbacks.Callbacks = {
	Gameplay = {
		DisableShadows = function(value, oldValue)
			local enabled = value == 1
			Lighting.GlobalShadows = not enabled
		end,

		DisableTextures = function(value, oldValue)
			local enabled = value == 1
		end,

		DisableOthersWraps = function(value, oldValue)
			local enabled = value == 1
		end,

		DamageNumbers = function(value, oldValue)
			local enabled = value == 1
		end,

		DisableEffects = function(value, oldValue)
			local enabled = value == 1
		end,

		HideHud = function(value, oldValue)
			local enabled = value == 1
		end,

		HideTeammateDisplay = function(value, oldValue)
			local enabled = value == 1
		end,

		DisplayArea = function(value, oldValue)
		end,

		HorizontalSensitivity = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				local scale = clampNumber(value, 0, 100, 50) / 50
				player:SetAttribute("MouseSensitivityScale", math.clamp(scale, 0.01, 4))
			end
			applyMouseSensitivityFromSettings()
		end,

		VerticalSensitivity = function(value, oldValue)
		end,

		ADSSensitivity = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				local scale = clampNumber(value, 0, 100, 100) / 100
				player:SetAttribute("ADSSensitivityScale", math.clamp(scale, 0.01, 2))
			end
			applyMouseSensitivityFromSettings()
		end,

		FieldOfView = function(value, oldValue)
			local camera = workspace.CurrentCamera
			if camera then
				camera.FieldOfView = value
			end
		end,

		FieldOfViewEffects = function(value, oldValue)
			local enabled = value == 1
		end,

		ScreenShake = function(value, oldValue)
		end,

		TeamColor = function(value, oldValue)
		end,

		EnemyColor = function(value, oldValue)
		end,

		MasterVolume = function(value, oldValue)
			SoundService.RespectFilteringEnabled = true
			local volume = value / 100
			SoundService.Volume = math.clamp(volume, 0, 1)
		end,

		MusicVolume = function(value, oldValue)
			local volume = value / 100
			SoundManager:setGroupVolume("Music", volume)
			SoundManager:setGroupVolume("Ambience", volume)
		end,

		SFXVolume = function(value, oldValue)
			local volume = value / 100
			SoundManager:setGroupVolume("Guns", volume)
			SoundManager:setGroupVolume("Explosions", volume)
			SoundManager:setGroupVolume("Movement", volume)
			SoundManager:setGroupVolume("UI", volume)
		end,

		EmoteVolume = function(value, oldValue)
			local volume = value / 100
			SoundManager:setGroupVolume("Voice", volume)
		end,
	},

	Controls = {
		ToggleAim = function(value, oldValue)
			local enabled = value == 1
		end,

		ScrollEquip = function(value, oldValue)
			local enabled = value == 1
		end,

		ToggleCrouch = function(value, oldValue)
			local enabled = value == 1
		end,

		SprintSetting = function(value, oldValue)
		end,

		AutoShootMode = function(value, oldValue)
			local enabled = value == 1
		end,

		AutoShootReactionTime = function(value, oldValue)
			local ms = tonumber(value) or 0
			AimAssistConfig.AutoShoot.AcquisitionDelay = math.clamp(ms / 1000, 0, 1)
		end,

		AimAssistStrength = function(value, oldValue)
			local player = Players.LocalPlayer
			if not player then
				return
			end
			player:SetAttribute("AimAssistStrength", math.clamp(tonumber(value) or 0.5, 0, 1))
		end,

		Sprint = function(value, oldValue)
		end,

		Jump = function(value, oldValue)
		end,

		Crouch = function(value, oldValue)
		end,

		Ability = function(value, oldValue)
		end,

		Ultimate = function(value, oldValue)
		end,

		Interact = function(value, oldValue)
		end,
	},

	Crosshair = {
		CrosshairEnabled = function(value, oldValue)
			local enabled = value == 1
		end,

		CrosshairColor = function(value, oldValue)
		end,

		CrosshairSize = function(value, oldValue)
		end,

		CrosshairOpacity = function(value, oldValue)
		end,

		CrosshairGap = function(value, oldValue)
		end,

		CrosshairThickness = function(value, oldValue)
		end,
	},
}

function SettingsCallbacks.fire(category: string, key: string, value: any, oldValue: any)
	local categoryCallbacks = SettingsCallbacks.Callbacks[category]
	if not categoryCallbacks then
		return
	end

	local callback = categoryCallbacks[key]
	if not callback then
		return
	end

	local success, err = pcall(function()
		callback(value, oldValue)
	end)

	if not success then
	end
end

function SettingsCallbacks.fireAll(category: string, settings: {[string]: any})
	local categoryCallbacks = SettingsCallbacks.Callbacks[category]
	if not categoryCallbacks then
		return
	end

	for key, value in settings do
		local callback = categoryCallbacks[key]
		if callback then
			local success, err = pcall(function()
				callback(value, nil)
			end)

			if not success then
			end
		end
	end
end

function SettingsCallbacks.register(category: string, key: string, callback: (value: any, oldValue: any) -> ())
	if not SettingsCallbacks.Callbacks[category] then
		SettingsCallbacks.Callbacks[category] = {}
	end

	SettingsCallbacks.Callbacks[category][key] = callback
end

function SettingsCallbacks.unregister(category: string, key: string)
	if not SettingsCallbacks.Callbacks[category] then
		return
	end

	SettingsCallbacks.Callbacks[category][key] = nil
end

return SettingsCallbacks
