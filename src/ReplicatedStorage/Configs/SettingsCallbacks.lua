local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local AimAssistConfig = require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("AimAssist"):WaitForChild("AimAssistConfig"))
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))
local ServiceRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("ServiceRegistry"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))
local SettingsConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("SettingsConfig"))

local SettingsCallbacks = {}
local ADS_SENSITIVITY_BASE_MULT = 0.75
local DisableTexturesState = {
	enabled = false,
	tracked = {},
	descendantAddedConnection = nil,
}
local DisableShadowsState = {
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
local BRIGHTNESS_BLOOM_NAME = "_SettingsBrightnessBloom"
local BRIGHTNESS_DEFAULT_INDEX = 3
local BRIGHTNESS_PRESETS = {
	[1] = {
		exposure = -0.65,
		bloomEnabled = false,
		bloomIntensity = 0,
		bloomSize = 24,
		bloomThreshold = 1.1,
	},
	[2] = {
		exposure = -0.25,
		bloomEnabled = false,
		bloomIntensity = 0,
		bloomSize = 24,
		bloomThreshold = 1.1,
	},
	[3] = {
		exposure = 0,
		bloomEnabled = false,
		bloomIntensity = 0,
		bloomSize = 24,
		bloomThreshold = 1.1,
	},
	[4] = {
		exposure = 0.2,
		bloomEnabled = false,
		bloomIntensity = 0,
		bloomSize = 24,
		bloomThreshold = 1.1,
	},
	[5] = {
		exposure = 0.25,
		bloomEnabled = true,
		bloomIntensity = 0.35,
		bloomSize = 24,
		bloomThreshold = 1.1,
	},
}

local isSettingEnabled

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

local function applyDisplayAreaScale(value)
	local numeric = tonumber(value)
	if numeric == nil then
		numeric = 100
	end
	local percent = math.clamp(numeric, 50, 150)
	local scale = percent / 100

	local player = getLocalPlayer()
	if player then
		player:SetAttribute("SettingsDisplayAreaScale", scale)
		player:SetAttribute("SettingsDisplayAreaPercent", percent)
	end

	local coreUi = getCoreUI()
	if coreUi and type(coreUi.setScaleToScreenMultiplier) == "function" then
		coreUi:setScaleToScreenMultiplier(scale)
	end
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

local function getCrosshairColorFromSetting(settingKey, value)
	local category = SettingsConfig.Categories.Crosshair
	local setting = category and category.Settings and category.Settings[settingKey]
	local options = setting and setting.Options
	if typeof(options) ~= "table" or #options == 0 then
		return Color3.fromRGB(255, 255, 255)
	end

	if typeof(value) == "number" then
		local index = math.clamp(math.floor(value + 0.5), 1, #options)
		local option = options[index]
		if option and typeof(option.Color) == "Color3" then
			return option.Color
		end
	end

	if typeof(value) == "string" then
		for _, option in ipairs(options) do
			if typeof(option) == "table" then
				local optionValue = option.Value
				local optionDisplay = option.Display
				if tostring(optionValue) == value or tostring(optionDisplay) == value then
					if typeof(option.Color) == "Color3" then
						return option.Color
					end
				end
			end
		end
	end

	local first = options[1]
	return (first and typeof(first.Color) == "Color3") and first.Color or Color3.fromRGB(255, 255, 255)
end

local function applyCrosshairSettingsFromAttributes()
	local player = getLocalPlayer()
	if not player then
		return
	end

	local disabled = player:GetAttribute("SettingsCrosshairDisabled")
	if type(disabled) ~= "boolean" then
		disabled = false
	end

	local scalePercent = player:GetAttribute("SettingsCrosshairSize")
	if type(scalePercent) ~= "number" then
		scalePercent = 100
	end
	scalePercent = math.clamp(scalePercent, 50, 200)

	local opacityPercent = player:GetAttribute("SettingsCrosshairOpacity")
	if type(opacityPercent) ~= "number" then
		opacityPercent = 100
	end
	opacityPercent = math.clamp(opacityPercent, 10, 100)

	local gap = player:GetAttribute("SettingsCrosshairGap")
	if type(gap) ~= "number" then
		gap = 10
	end
	gap = math.clamp(gap, 0, 50)

	local thickness = player:GetAttribute("SettingsCrosshairThickness")
	if type(thickness) ~= "number" then
		thickness = 2
	end
	thickness = math.clamp(thickness, 1, 10)

	local function readNumber(name, defaultValue, minValue, maxValue)
		local value = player:GetAttribute(name)
		if type(value) ~= "number" then
			value = defaultValue
		end
		return math.clamp(value, minValue, maxValue)
	end

	local function readBoolean(name, defaultValue)
		local value = player:GetAttribute(name)
		if type(value) ~= "boolean" then
			return defaultValue
		end
		return value
	end

	local advanced = readBoolean("SettingsCrosshairAdvancedStyleSettings", false)
	local showTop = readBoolean("SettingsCrosshairShowTopLine", true)
	local showBottom = readBoolean("SettingsCrosshairShowBottomLine", true)
	local showLeft = readBoolean("SettingsCrosshairShowLeftLine", true)
	local showRight = readBoolean("SettingsCrosshairShowRightLine", true)
	local showDot = readBoolean("SettingsCrosshairShowDot", true)

	local mainColor = getCrosshairColorFromSetting("CrosshairColor", player:GetAttribute("SettingsCrosshairColor"))
	local outlineColor = getCrosshairColorFromSetting("OutlineColor", player:GetAttribute("SettingsCrosshairOutlineColor"))
	local baseOpacity = opacityPercent / 100
	local baseThickness = readNumber("SettingsCrosshairThickness", thickness, 1, 12)
	local baseLength = readNumber("SettingsCrosshairLineLength", 10, 2, 40)
	local baseRoundness = readNumber("SettingsCrosshairRoundness", 0, 0, 20)
	local baseGap = gap

	local customization = {
		showDot = (not disabled) and showDot,
		showTopLine = (not disabled) and showTop,
		showBottomLine = (not disabled) and showBottom,
		showLeftLine = (not disabled) and showLeft,
		showRightLine = (not disabled) and showRight,
		lineThickness = baseThickness,
		lineLength = baseLength,
		gapFromCenter = baseGap,
		dotSize = readNumber("SettingsCrosshairDotSize", 3, 1, 20),
		rotation = readNumber("SettingsCrosshairGlobalRotation", 0, -180, 180),
		cornerRadius = baseRoundness,
		mainColor = mainColor,
		outlineColor = outlineColor,
		outlineThickness = readNumber("SettingsCrosshairOutlineThickness", 0, 0, 6),
		outlineOpacity = readNumber("SettingsCrosshairOutlineOpacity", 100, 0, 100) / 100,
		opacity = baseOpacity,
		scale = scalePercent / 100,
		dynamicSpreadEnabled = readBoolean("SettingsCrosshairDynamicSpreadEnabled", true),
		recoilSpreadMultiplier = readNumber("SettingsCrosshairRecoilSpreadMultiplier", 1, 0, 5),
		spread = {
			movement = readNumber("SettingsCrosshairMovementSpreadMultiplier", 1, 0, 5),
			sprint = readNumber("SettingsCrosshairSprintSpreadMultiplier", 1, 0, 5),
			air = readNumber("SettingsCrosshairAirSpreadMultiplier", 1, 0, 5),
			crouch = readNumber("SettingsCrosshairCrouchSpreadMultiplier", 1, 0, 5),
		},
		advancedStyleSettings = advanced,
		perLineStyles = {
			Top = {
				color = getCrosshairColorFromSetting("TopLineColor", player:GetAttribute("SettingsCrosshairTopLineColor")) or mainColor,
				opacity = readNumber("SettingsCrosshairTopLineOpacity", opacityPercent, 0, 100) / 100,
				thickness = readNumber("SettingsCrosshairTopLineThickness", baseThickness, 1, 12),
				length = readNumber("SettingsCrosshairTopLineLength", baseLength, 2, 40),
				roundness = readNumber("SettingsCrosshairTopLineRoundness", baseRoundness, 0, 20),
				rotation = readNumber("SettingsCrosshairTopLineRotation", 0, -180, 180),
				gap = readNumber("SettingsCrosshairTopLineGap", baseGap, 0, 50),
			},
			Bottom = {
				color = getCrosshairColorFromSetting("BottomLineColor", player:GetAttribute("SettingsCrosshairBottomLineColor")) or mainColor,
				opacity = readNumber("SettingsCrosshairBottomLineOpacity", opacityPercent, 0, 100) / 100,
				thickness = readNumber("SettingsCrosshairBottomLineThickness", baseThickness, 1, 12),
				length = readNumber("SettingsCrosshairBottomLineLength", baseLength, 2, 40),
				roundness = readNumber("SettingsCrosshairBottomLineRoundness", baseRoundness, 0, 20),
				rotation = readNumber("SettingsCrosshairBottomLineRotation", 0, -180, 180),
				gap = readNumber("SettingsCrosshairBottomLineGap", baseGap, 0, 50),
			},
			Left = {
				color = getCrosshairColorFromSetting("LeftLineColor", player:GetAttribute("SettingsCrosshairLeftLineColor")) or mainColor,
				opacity = readNumber("SettingsCrosshairLeftLineOpacity", opacityPercent, 0, 100) / 100,
				thickness = readNumber("SettingsCrosshairLeftLineThickness", baseThickness, 1, 12),
				length = readNumber("SettingsCrosshairLeftLineLength", baseLength, 2, 40),
				roundness = readNumber("SettingsCrosshairLeftLineRoundness", baseRoundness, 0, 20),
				rotation = readNumber("SettingsCrosshairLeftLineRotation", 0, -180, 180),
				gap = readNumber("SettingsCrosshairLeftLineGap", baseGap, 0, 50),
			},
			Right = {
				color = getCrosshairColorFromSetting("RightLineColor", player:GetAttribute("SettingsCrosshairRightLineColor")) or mainColor,
				opacity = readNumber("SettingsCrosshairRightLineOpacity", opacityPercent, 0, 100) / 100,
				thickness = readNumber("SettingsCrosshairRightLineThickness", baseThickness, 1, 12),
				length = readNumber("SettingsCrosshairRightLineLength", baseLength, 2, 40),
				roundness = readNumber("SettingsCrosshairRightLineRoundness", baseRoundness, 0, 20),
				rotation = readNumber("SettingsCrosshairRightLineRotation", 0, -180, 180),
				gap = readNumber("SettingsCrosshairRightLineGap", baseGap, 0, 50),
			},
		},
		dotStyle = {
			color = getCrosshairColorFromSetting("DotColor", player:GetAttribute("SettingsCrosshairDotColor")) or mainColor,
			opacity = readNumber("SettingsCrosshairDotOpacity", opacityPercent, 0, 100) / 100,
			size = readNumber("SettingsCrosshairDotSize", 3, 1, 20),
			roundness = readNumber("SettingsCrosshairDotRoundness", baseRoundness, 0, 20),
		},
	}

	local weaponController = ServiceRegistry:GetController("Weapon")
	local crosshairController = weaponController and weaponController._crosshair
	if crosshairController and type(crosshairController.SetCustomization) == "function" then
		crosshairController:SetCustomization(customization)
	end
end

local function setCrosshairSetting(player, attrName, value, minValue, maxValue, fallback, asBoolean)
	if not player then
		return
	end
	if asBoolean then
		player:SetAttribute(attrName, isSettingEnabled(value))
		return
	end
	player:SetAttribute(attrName, clampNumber(value, minValue, maxValue, fallback))
end

isSettingEnabled = function(value)
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

local function resolveBrightnessPresetIndex(value)
	if type(value) == "number" then
		local rounded = math.floor(value + 0.5)
		if rounded >= 1 and rounded <= #BRIGHTNESS_PRESETS then
			return rounded
		end

		local oldSliderValue = math.clamp(value, 0, 200)
		if oldSliderValue < 60 then
			return 1
		end
		if oldSliderValue < 90 then
			return 2
		end
		if oldSliderValue < 130 then
			return 3
		end
		if oldSliderValue < 170 then
			return 4
		end
		return 5
	end

	if type(value) == "string" then
		local lowered = string.lower(value)
		if lowered == "darker" then
			return 1
		end
		if lowered == "dark" then
			return 2
		end
		if lowered == "default" then
			return 3
		end
		if lowered == "bright" then
			return 4
		end
		if lowered == "bright+bloom" or lowered == "bright + bloom" or lowered == "brightbloom" then
			return 5
		end
	end

	return BRIGHTNESS_DEFAULT_INDEX
end

local function getBrightnessBloomEffect()
	local existing = Lighting:FindFirstChild(BRIGHTNESS_BLOOM_NAME)
	if existing then
		if existing:IsA("BloomEffect") then
			return existing
		end
		existing:Destroy()
	end

	local bloom = Instance.new("BloomEffect")
	bloom.Name = BRIGHTNESS_BLOOM_NAME
	bloom.Enabled = false
	bloom.Intensity = 0
	bloom.Size = 24
	bloom.Threshold = 1.1
	bloom.Parent = Lighting
	return bloom
end

local function applyBrightnessPreset(value)
	local presetIndex = resolveBrightnessPresetIndex(value)
	local preset = BRIGHTNESS_PRESETS[presetIndex] or BRIGHTNESS_PRESETS[BRIGHTNESS_DEFAULT_INDEX]
	if not preset then
		return BRIGHTNESS_DEFAULT_INDEX
	end

	Lighting.ExposureCompensation = preset.exposure

	local bloom = getBrightnessBloomEffect()
	bloom.Enabled = preset.bloomEnabled
	bloom.Intensity = preset.bloomIntensity
	bloom.Size = preset.bloomSize
	bloom.Threshold = preset.bloomThreshold

	return presetIndex
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

local function shouldAffectForDisableShadows(instance)
	if not instance or not instance.Parent then
		return false
	end

	if hasHumanoidAncestor(instance) then
		return false
	end

	return instance:IsA("BasePart")
end

local function applyDisableShadowsToInstance(instance)
	if not DisableShadowsState.enabled then
		return
	end

	if not shouldAffectForDisableShadows(instance) then
		return
	end

	local tracked = DisableShadowsState.tracked
	local entry = tracked[instance]
	if not entry then
		entry = {
			castShadow = instance.CastShadow,
		}
		tracked[instance] = entry
	end

	instance.CastShadow = false
end

local function connectDisableShadowsWatcher()
	if DisableShadowsState.descendantAddedConnection then
		return
	end

	DisableShadowsState.descendantAddedConnection = workspace.DescendantAdded:Connect(function(instance)
		applyDisableShadowsToInstance(instance)
	end)
end

local function disconnectDisableShadowsWatcher()
	local connection = DisableShadowsState.descendantAddedConnection
	if connection then
		connection:Disconnect()
		DisableShadowsState.descendantAddedConnection = nil
	end
end

local function applyDisableShadowsToWorkspace()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		applyDisableShadowsToInstance(descendant)
	end
end

local function restoreDisableShadowsAll()
	local tracked = DisableShadowsState.tracked
	local restoreList = {}
	for instance, entry in pairs(tracked) do
		table.insert(restoreList, { instance = instance, entry = entry })
	end

	for _, item in ipairs(restoreList) do
		local instance = item.instance
		local entry = item.entry
		if instance and instance.Parent and entry and entry.castShadow ~= nil then
			instance.CastShadow = entry.castShadow
		end
		tracked[instance] = nil
	end
end

local function setDisableShadowsEnabled(enabled)
	enabled = enabled == true
	if DisableShadowsState.enabled == enabled then
		return
	end

	DisableShadowsState.enabled = enabled
	Lighting.GlobalShadows = not enabled

	if enabled then
		connectDisableShadowsWatcher()
		applyDisableShadowsToWorkspace()
	else
		disconnectDisableShadowsWatcher()
		restoreDisableShadowsAll()
	end
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
			setDisableShadowsEnabled(isSettingEnabled(value))
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
			applyDisplayAreaScale(value)
		end,

		Brightness = function(value, oldValue)
			local presetIndex = applyBrightnessPreset(value)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsBrightnessPreset", presetIndex)
			end
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
			local fov = clampNumber(value, 30, 120, 70)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsBaseFOV", fov)
			end
			FOVController:SetSettingsBaseFOV(fov)
		end,

		FieldOfViewEffects = function(value, oldValue)
			local enabled = isSettingEnabled(value)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsFOVEffectsEnabled", enabled)
			end
			FOVController:SetEffectsEnabled(enabled)
		end,

		FOVZoomStrength = function(value, oldValue)
			local strengthPercent = clampNumber(value, 0, 100, 100)
			local strengthScale = strengthPercent / 100
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsFOVZoomStrength", strengthScale)
			end
			FOVController:SetADSZoomStrength(strengthScale)
		end,

		ScreenShake = function(value, oldValue)
			local scale = clampNumber(value, 0, 3, 1)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsScreenShakeScale", scale)
				player:SetAttribute("SettingsScreenShakeEnabled", scale > 0)
			end

			local screenShakeController = ServiceRegistry:GetController("ScreenShake")
			if screenShakeController and type(screenShakeController.SetIntensityScale) == "function" then
				screenShakeController:SetIntensityScale(scale)
			end
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
		CrosshairDisabled = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsCrosshairDisabled", isSettingEnabled(value))
			end
			applyCrosshairSettingsFromAttributes()
		end,

		ForceDefaultCrosshair = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsCrosshairForceDefault", isSettingEnabled(value))
			end
			local weaponController = ServiceRegistry:GetController("Weapon")
			if weaponController and type(weaponController.RefreshCrosshair) == "function" then
				weaponController:RefreshCrosshair()
			end
			applyCrosshairSettingsFromAttributes()
		end,

		DisableSlideRotation = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsCrosshairDisableSlideRotation", isSettingEnabled(value))
			end
		end,

		AdvancedStyleSettings = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				local enabled = isSettingEnabled(value)
				player:SetAttribute("SettingsCrosshairAdvancedStyleSettings", enabled)
				if enabled ~= true then
					local baseColor = player:GetAttribute("SettingsCrosshairColor")
					if baseColor == nil then
						baseColor = 1
					end
					player:SetAttribute("SettingsCrosshairTopLineColor", baseColor)
					player:SetAttribute("SettingsCrosshairBottomLineColor", baseColor)
					player:SetAttribute("SettingsCrosshairLeftLineColor", baseColor)
					player:SetAttribute("SettingsCrosshairRightLineColor", baseColor)
					player:SetAttribute("SettingsCrosshairDotColor", baseColor)
				end
			end
			applyCrosshairSettingsFromAttributes()
		end,

		ShowTopLine = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairShowTopLine", value, 0, 1, 1, true)
			applyCrosshairSettingsFromAttributes()
		end,
		ShowBottomLine = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairShowBottomLine", value, 0, 1, 1, true)
			applyCrosshairSettingsFromAttributes()
		end,
		ShowLeftLine = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairShowLeftLine", value, 0, 1, 1, true)
			applyCrosshairSettingsFromAttributes()
		end,
		ShowRightLine = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairShowRightLine", value, 0, 1, 1, true)
			applyCrosshairSettingsFromAttributes()
		end,
		ShowDot = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairShowDot", value, 0, 1, 1, true)
			applyCrosshairSettingsFromAttributes()
		end,

		CrosshairColor = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsCrosshairColor", value)
				if player:GetAttribute("SettingsCrosshairAdvancedStyleSettings") ~= true then
					player:SetAttribute("SettingsCrosshairTopLineColor", value)
					player:SetAttribute("SettingsCrosshairBottomLineColor", value)
					player:SetAttribute("SettingsCrosshairLeftLineColor", value)
					player:SetAttribute("SettingsCrosshairRightLineColor", value)
					player:SetAttribute("SettingsCrosshairDotColor", value)
				end
			end
			applyCrosshairSettingsFromAttributes()
		end,

		CrosshairSize = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsCrosshairSize", clampNumber(value, 50, 200, 100))
			end
			applyCrosshairSettingsFromAttributes()
		end,

		CrosshairOpacity = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsCrosshairOpacity", clampNumber(value, 10, 100, 100))
			end
			applyCrosshairSettingsFromAttributes()
		end,

		CrosshairGap = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsCrosshairGap", clampNumber(value, 0, 50, 10))
			end
			applyCrosshairSettingsFromAttributes()
		end,

		CrosshairThickness = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsCrosshairThickness", clampNumber(value, 1, 10, 2))
			end
			applyCrosshairSettingsFromAttributes()
		end,

		CrosshairLineLength = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairLineLength", value, 2, 40, 10)
			applyCrosshairSettingsFromAttributes()
		end,
		CrosshairRoundness = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairRoundness", value, 0, 20, 0)
			applyCrosshairSettingsFromAttributes()
		end,
		GlobalRotation = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairGlobalRotation", value, -180, 180, 0)
			applyCrosshairSettingsFromAttributes()
		end,
		DotSize = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairDotSize", value, 1, 20, 3)
			applyCrosshairSettingsFromAttributes()
		end,

		OutlineColor = function(value, oldValue)
			local player = getLocalPlayer()
			if player then
				player:SetAttribute("SettingsCrosshairOutlineColor", value)
			end
			applyCrosshairSettingsFromAttributes()
		end,
		OutlineThickness = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairOutlineThickness", value, 0, 6, 0)
			applyCrosshairSettingsFromAttributes()
		end,
		OutlineOpacity = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairOutlineOpacity", value, 0, 100, 100)
			applyCrosshairSettingsFromAttributes()
		end,

		DynamicSpreadEnabled = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairDynamicSpreadEnabled", value, 0, 1, 1, true)
			applyCrosshairSettingsFromAttributes()
		end,
		MovementSpreadMultiplier = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairMovementSpreadMultiplier", value, 0, 5, 1)
			applyCrosshairSettingsFromAttributes()
		end,
		SprintSpreadMultiplier = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairSprintSpreadMultiplier", value, 0, 5, 1)
			applyCrosshairSettingsFromAttributes()
		end,
		AirSpreadMultiplier = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairAirSpreadMultiplier", value, 0, 5, 1)
			applyCrosshairSettingsFromAttributes()
		end,
		CrouchSpreadMultiplier = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairCrouchSpreadMultiplier", value, 0, 5, 1)
			applyCrosshairSettingsFromAttributes()
		end,
		RecoilSpreadMultiplier = function(value, oldValue)
			setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairRecoilSpreadMultiplier", value, 0, 5, 1)
			applyCrosshairSettingsFromAttributes()
		end,

		TopLineColor = function(value, oldValue) local p = getLocalPlayer(); if p then p:SetAttribute("SettingsCrosshairTopLineColor", value) end; applyCrosshairSettingsFromAttributes() end,
		TopLineOpacity = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairTopLineOpacity", value, 0, 100, 100); applyCrosshairSettingsFromAttributes() end,
		TopLineThickness = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairTopLineThickness", value, 1, 12, 2); applyCrosshairSettingsFromAttributes() end,
		TopLineLength = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairTopLineLength", value, 2, 40, 10); applyCrosshairSettingsFromAttributes() end,
		TopLineRoundness = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairTopLineRoundness", value, 0, 20, 0); applyCrosshairSettingsFromAttributes() end,
		TopLineRotation = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairTopLineRotation", value, -180, 180, 0); applyCrosshairSettingsFromAttributes() end,
		TopLineGap = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairTopLineGap", value, 0, 50, 10); applyCrosshairSettingsFromAttributes() end,

		BottomLineColor = function(value, oldValue) local p = getLocalPlayer(); if p then p:SetAttribute("SettingsCrosshairBottomLineColor", value) end; applyCrosshairSettingsFromAttributes() end,
		BottomLineOpacity = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairBottomLineOpacity", value, 0, 100, 100); applyCrosshairSettingsFromAttributes() end,
		BottomLineThickness = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairBottomLineThickness", value, 1, 12, 2); applyCrosshairSettingsFromAttributes() end,
		BottomLineLength = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairBottomLineLength", value, 2, 40, 10); applyCrosshairSettingsFromAttributes() end,
		BottomLineRoundness = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairBottomLineRoundness", value, 0, 20, 0); applyCrosshairSettingsFromAttributes() end,
		BottomLineRotation = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairBottomLineRotation", value, -180, 180, 0); applyCrosshairSettingsFromAttributes() end,
		BottomLineGap = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairBottomLineGap", value, 0, 50, 10); applyCrosshairSettingsFromAttributes() end,

		LeftLineColor = function(value, oldValue) local p = getLocalPlayer(); if p then p:SetAttribute("SettingsCrosshairLeftLineColor", value) end; applyCrosshairSettingsFromAttributes() end,
		LeftLineOpacity = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairLeftLineOpacity", value, 0, 100, 100); applyCrosshairSettingsFromAttributes() end,
		LeftLineThickness = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairLeftLineThickness", value, 1, 12, 2); applyCrosshairSettingsFromAttributes() end,
		LeftLineLength = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairLeftLineLength", value, 2, 40, 10); applyCrosshairSettingsFromAttributes() end,
		LeftLineRoundness = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairLeftLineRoundness", value, 0, 20, 0); applyCrosshairSettingsFromAttributes() end,
		LeftLineRotation = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairLeftLineRotation", value, -180, 180, 0); applyCrosshairSettingsFromAttributes() end,
		LeftLineGap = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairLeftLineGap", value, 0, 50, 10); applyCrosshairSettingsFromAttributes() end,

		RightLineColor = function(value, oldValue) local p = getLocalPlayer(); if p then p:SetAttribute("SettingsCrosshairRightLineColor", value) end; applyCrosshairSettingsFromAttributes() end,
		RightLineOpacity = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairRightLineOpacity", value, 0, 100, 100); applyCrosshairSettingsFromAttributes() end,
		RightLineThickness = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairRightLineThickness", value, 1, 12, 2); applyCrosshairSettingsFromAttributes() end,
		RightLineLength = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairRightLineLength", value, 2, 40, 10); applyCrosshairSettingsFromAttributes() end,
		RightLineRoundness = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairRightLineRoundness", value, 0, 20, 0); applyCrosshairSettingsFromAttributes() end,
		RightLineRotation = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairRightLineRotation", value, -180, 180, 0); applyCrosshairSettingsFromAttributes() end,
		RightLineGap = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairRightLineGap", value, 0, 50, 10); applyCrosshairSettingsFromAttributes() end,

		DotColor = function(value, oldValue) local p = getLocalPlayer(); if p then p:SetAttribute("SettingsCrosshairDotColor", value) end; applyCrosshairSettingsFromAttributes() end,
		DotOpacity = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairDotOpacity", value, 0, 100, 100); applyCrosshairSettingsFromAttributes() end,
		DotRoundness = function(value, oldValue) setCrosshairSetting(getLocalPlayer(), "SettingsCrosshairDotRoundness", value, 0, 20, 0); applyCrosshairSettingsFromAttributes() end,
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
		warn(string.format("[SettingsCallbacks] %s.%s failed: %s", tostring(category), tostring(key), tostring(err)))
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
				warn(string.format("[SettingsCallbacks] fireAll %s.%s failed: %s", tostring(category), tostring(key), tostring(err)))
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
