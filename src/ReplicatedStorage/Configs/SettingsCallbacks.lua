local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local AimAssistConfig = require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("AimAssist"):WaitForChild("AimAssistConfig"))
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))
local ServiceRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("ServiceRegistry"))

local SettingsCallbacks = {}
local ADS_SENSITIVITY_BASE_MULT = 0.75
local DisableTexturesState = {
	enabled = false,
	tracked = {},
	descendantAddedConnection = nil,
}
local HideHudState = {
	enabled = false,
	hiddenModules = {},
	moduleShowConnection = nil,
	pendingApply = false,
}
local HUD_HIDE_ALLOWED_MODULES = {
	["Loadout"] = true,
	["Map"] = true,
	["Settings"] = true,
	["_Settings"] = true,
	["UnHide"] = true,
	["stats"] = true,
	["Stats"] = true,
}

local function getLocalPlayer()
	return Players.LocalPlayer
end

local function getCoreUI()
	local uiController = ServiceRegistry:GetController("UI")
	if uiController and type(uiController.GetCoreUI) == "function" then
		return uiController:GetCoreUI()
	end
	return nil
end

local function shouldShowHudInCurrentContext()
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	return player:GetAttribute("InLobby") ~= true
end

local function getUnHideUI()
	local player = Players.LocalPlayer
	if not player then
		return nil
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	local screenGui = playerGui:FindFirstChild("Gui")
	if not screenGui then
		return nil
	end

	local unHide = screenGui:FindFirstChild("UnHide", true)
	if unHide and unHide:IsA("GuiObject") then
		return unHide
	end

	return nil
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
	local adsSensitivityScale = getNumericAttribute(player, "ADSSensitivityScale", ADS_SENSITIVITY_BASE_MULT)
	local adsSpeedMultiplier = getNumericAttribute(player, "ADSSpeedMultiplier", 1)
	local isADSActive = player:GetAttribute("WeaponADSActive") == true

	local targetSensitivity = hipSensitivity
	if isADSActive then
		targetSensitivity = hipSensitivity * adsSensitivityScale * adsSpeedMultiplier * ADS_SENSITIVITY_BASE_MULT
	end

	UserInputService.MouseDeltaSensitivity = math.clamp(targetSensitivity, 0.01, 4)
end

local function isSettingEnabled(value)
	if value == true then
		return true
	end
	if type(value) == "number" then
		return value == 1
	end
	if type(value) == "string" then
		local lowered = string.lower(value)
		return lowered == "enabled" or lowered == "true" or lowered == "on"
	end
	return false
end

local function hasHumanoidAncestor(instance)
	local current = instance
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return true
		end
		current = current.Parent
	end
	return false
end

local function shouldAffectForDisableTextures(instance)
	if not instance or not instance.Parent then
		return false
	end

	if hasHumanoidAncestor(instance) then
		return false
	end

	return instance:IsA("BasePart") or instance:IsA("Decal") or instance:IsA("Texture")
end

local function getTrackedEntry(instance)
	local tracked = DisableTexturesState.tracked
	local entry = tracked[instance]
	if not entry then
		entry = {}
		tracked[instance] = entry
	end
	return entry
end

local function applyDisableTexturesToInstance(instance)
	if not DisableTexturesState.enabled then
		return
	end

	if not shouldAffectForDisableTextures(instance) then
		return
	end

	local entry = getTrackedEntry(instance)

	if instance:IsA("BasePart") then
		if entry.material == nil then
			entry.material = instance.Material
		end
		if entry.materialVariant == nil then
			local ok, result = pcall(function()
				return instance.MaterialVariant
			end)
			if ok then
				entry.materialVariant = result
			end
		end

		instance.Material = Enum.Material.SmoothPlastic
		pcall(function()
			instance.MaterialVariant = ""
		end)

		if instance:IsA("MeshPart") then
			if entry.textureID == nil then
				entry.textureID = instance.TextureID
			end
			instance.TextureID = ""
		end
	end

	if instance:IsA("Decal") or instance:IsA("Texture") then
		if entry.transparency == nil then
			entry.transparency = instance.Transparency
		end
		instance.Transparency = 1
	end
end

local function restoreDisableTexturesInstance(instance, entry)
	if not instance or not entry then
		return
	end

	if instance:IsA("BasePart") then
		if entry.material ~= nil then
			instance.Material = entry.material
		end
		if entry.materialVariant ~= nil then
			pcall(function()
				instance.MaterialVariant = entry.materialVariant
			end)
		end
		if instance:IsA("MeshPart") and entry.textureID ~= nil then
			instance.TextureID = entry.textureID
		end
	end

	if (instance:IsA("Decal") or instance:IsA("Texture")) and entry.transparency ~= nil then
		instance.Transparency = entry.transparency
	end
end

local function connectDisableTexturesWatcher()
	if DisableTexturesState.descendantAddedConnection then
		return
	end

	DisableTexturesState.descendantAddedConnection = workspace.DescendantAdded:Connect(function(instance)
		applyDisableTexturesToInstance(instance)
	end)
end

local function disconnectDisableTexturesWatcher()
	local connection = DisableTexturesState.descendantAddedConnection
	if connection then
		connection:Disconnect()
		DisableTexturesState.descendantAddedConnection = nil
	end
end

local function applyDisableTexturesToWorkspace()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		applyDisableTexturesToInstance(descendant)
	end
end

local function restoreDisableTexturesAll()
	local restoreList = {}
	for instance, entry in pairs(DisableTexturesState.tracked) do
		table.insert(restoreList, { instance = instance, entry = entry })
	end

	for _, item in ipairs(restoreList) do
		local instance = item.instance
		local entry = item.entry
		if instance and instance.Parent then
			restoreDisableTexturesInstance(instance, entry)
		end
		DisableTexturesState.tracked[instance] = nil
	end
end

local function setDisableTexturesEnabled(enabled)
	enabled = enabled == true
	if DisableTexturesState.enabled == enabled then
		return
	end

	DisableTexturesState.enabled = enabled
	if enabled then
		connectDisableTexturesWatcher()
		applyDisableTexturesToWorkspace()
	else
		disconnectDisableTexturesWatcher()
		restoreDisableTexturesAll()
	end
end

local function shouldKeepHudModule(moduleName)
	if moduleName == "PlayerList" then
		return false
	end
	return HUD_HIDE_ALLOWED_MODULES[moduleName] == true
end

local function disconnectHideHudConnection()
	local connection = HideHudState.moduleShowConnection
	if not connection then
		return
	end

	if typeof(connection) == "RBXScriptConnection" then
		connection:Disconnect()
	elseif type(connection) == "table" and connection.disconnect then
		connection:disconnect()
	end

	HideHudState.moduleShowConnection = nil
end

local function setUnHideVisible(coreUi, visible)
	if coreUi then
		if visible then
			coreUi:show("UnHide", true)
		else
			coreUi:hide("UnHide")
		end

		local ui = coreUi:getUI("UnHide")
		if ui and ui:IsA("GuiObject") then
			ui.Visible = visible
		end
		return
	end

	local fallbackUi = getUnHideUI()
	if fallbackUi then
		fallbackUi.Visible = visible
	end
end

local function applyHideHudState(enabled)
	local coreUi = getCoreUI()

	if enabled == true and HideHudState.enabled == true then
		setUnHideVisible(coreUi, true)
		return
	end

	if enabled ~= true and HideHudState.enabled ~= true then
		setUnHideVisible(coreUi, false)
		return
	end

	if enabled ~= true then
		HideHudState.enabled = false
		HideHudState.pendingApply = false
		disconnectHideHudConnection()
		setUnHideVisible(coreUi, false)

		local restoreState = HideHudState.hiddenModules
		HideHudState.hiddenModules = {}
		if not coreUi then
			task.spawn(function()
				for _ = 1, 120 do
					if HideHudState.enabled then
						return
					end

					local liveCoreUi = getCoreUI()
					if liveCoreUi then
						for moduleName, state in pairs(restoreState) do
							if state.wasOpen then
								liveCoreUi:show(moduleName, true)
							else
								local ui = liveCoreUi:getUI(moduleName)
								if ui and ui:IsA("GuiObject") and state.wasVisible then
									ui.Visible = true
								end
							end
						end
						if shouldShowHudInCurrentContext() and liveCoreUi:getUI("HUD") then
							liveCoreUi:show("HUD", true)
						end
						return
					end

					task.wait(0.25)
				end
			end)
			return
		end

		for moduleName, state in pairs(restoreState) do
			if state.wasOpen then
				coreUi:show(moduleName, true)
			else
				local ui = coreUi:getUI(moduleName)
				if ui and ui:IsA("GuiObject") and state.wasVisible then
					ui.Visible = true
				end
			end
		end
		if shouldShowHudInCurrentContext() and coreUi:getUI("HUD") then
			coreUi:show("HUD", true)
		end
		return
	end

	HideHudState.enabled = true
	HideHudState.hiddenModules = {}

	if not coreUi then
		if not HideHudState.pendingApply then
			HideHudState.pendingApply = true
			task.spawn(function()
				for _ = 1, 120 do
					if not HideHudState.enabled then
						HideHudState.pendingApply = false
						return
					end

					local liveCoreUi = getCoreUI()
					if liveCoreUi then
						HideHudState.pendingApply = false
						applyHideHudState(true)
						return
					end

					task.wait(0.25)
				end
				HideHudState.pendingApply = false
			end)
		end

		setUnHideVisible(nil, true)
		return
	end
	HideHudState.pendingApply = false

	if coreUi then
		for moduleName, _ in pairs(coreUi._modules or {}) do
			if not shouldKeepHudModule(moduleName) then
				local ui = coreUi:getUI(moduleName)
				local wasVisible = ui and ui:IsA("GuiObject") and ui.Visible == true or false
				local wasOpen = coreUi:isOpen(moduleName)

				if wasVisible or wasOpen then
					HideHudState.hiddenModules[moduleName] = {
						wasOpen = wasOpen,
						wasVisible = wasVisible,
					}
				end

				if wasOpen then
					coreUi:hide(moduleName)
				elseif ui and ui:IsA("GuiObject") then
					ui.Visible = false
				end
			end
		end

		disconnectHideHudConnection()
		HideHudState.moduleShowConnection = coreUi.onModuleShow:connect(function(moduleName)
			if not HideHudState.enabled or shouldKeepHudModule(moduleName) then
				return
			end

			task.defer(function()
				local liveCoreUi = getCoreUI()
				if not liveCoreUi then
					return
				end

				if liveCoreUi:isOpen(moduleName) then
					liveCoreUi:hide(moduleName)
				end

				local liveUi = liveCoreUi:getUI(moduleName)
				if liveUi and liveUi:IsA("GuiObject") then
					liveUi.Visible = false
				end
			end)
		end)
	end

	setUnHideVisible(coreUi, true)
end

SettingsCallbacks.Callbacks = {
	Gameplay = {
		DisableShadows = function(value, oldValue)
			local enabled = value == 1
			Lighting.GlobalShadows = not enabled
		end,

		DisableTextures = function(value, oldValue)
			setDisableTexturesEnabled(isSettingEnabled(value))
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
			applyHideHudState(isSettingEnabled(value))
		end,

		HideMuzzleFlash = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("HideMuzzleFlashEnabled", isSettingEnabled(value))
			end
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
