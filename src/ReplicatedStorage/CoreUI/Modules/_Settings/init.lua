local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Configs = require(ReplicatedStorage.Configs)
local SettingsConfig = Configs.SettingsConfig
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
local TweenConfig = require(script.TweenConfig)
local DefaultCrosshairModule = require(
	ReplicatedStorage:WaitForChild("CrosshairSystem"):WaitForChild("Crosshairs"):WaitForChild("Default")
)

local module = {}
module.__index = module

local TAB_MAP = {
	{ holder = "VideoHolder", categoryKey = "Video", sourceCategory = "Gameplay" },
	{ holder = "PersonalHolder", categoryKey = nil },
	{ holder = "KeybindsHolder", categoryKey = "Controls" },
	{ holder = "GameHolder", categoryKey = "Gameplay", sourceCategory = "Gameplay" },
	{ holder = "CrossHairHolder", categoryKey = "Crosshair" },
	{ holder = "AudioHolder", categoryKey = "Audio" },
}

local DEFAULT_TAB = "VideoHolder"

local currentTweens = {}

local function cancelTweenGroup(key)
	local tweens = currentTweens[key]
	if not tweens then
		return
	end

	for _, tween in ipairs(tweens) do
		tween:Cancel()
	end
	currentTweens[key] = nil
end

local function isPointerInput(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isBindableKeyInput(input)
	return input.UserInputType == Enum.UserInputType.Keyboard
		or tostring(input.UserInputType):find("Gamepad", 1, true) ~= nil
end

local function getDirectChildrenByName(parent, name)
	local list = {}
	if not parent then
		return list
	end

	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			table.insert(list, child)
		end
	end

	return list
end

local function toAssetId(asset)
	if typeof(asset) == "number" then
		return "rbxassetid://" .. tostring(asset)
	end
	if typeof(asset) ~= "string" then
		return nil
	end
	if asset == "" then
		return nil
	end
	if string.find(asset, "rbxassetid://", 1, true) then
		return asset
	end
	if string.match(asset, "^%d+$") then
		return "rbxassetid://" .. asset
	end
	return asset
end

local function keyCodeDisplay(keyCode)
	if keyCode == nil then
		return "-"
	end
	return keyCode.Name
end

local function clampIndex(index, count)
	if count <= 0 then
		return 1
	end
	local numericIndex = tonumber(index) or 1
	local roundedIndex = math.floor(numericIndex + 0.5)
	return math.clamp(roundedIndex, 1, count)
end

local function toNumber(value, fallback)
	local numeric = tonumber(value)
	if numeric == nil then
		return fallback
	end
	return numeric
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

local function mapLegacyBrightnessPresetIndex(value)
	local numeric = tonumber(value)
	if numeric == nil then
		return 3
	end

	if numeric < 60 then
		return 1
	end
	if numeric < 90 then
		return 2
	end
	if numeric < 130 then
		return 3
	end
	if numeric < 170 then
		return 4
	end
	return 5
end

local function snapToStep(value, minValue, step)
	if step <= 0 then
		return value
	end
	local offset = value - minValue
	return (math.round(offset / step) * step) + minValue
end

local function findBooleanOptionIndex(options, targetValue)
	if not options then
		return nil
	end

	for index, option in ipairs(options) do
		if typeof(option) == "table" and typeof(option.Value) == "boolean" and option.Value == targetValue then
			return index
		end
	end

	return nil
end

local function resolveOptionIndex(config, storedValue)
	local options = config and config.Options
	if typeof(options) ~= "table" or #options == 0 then
		return nil
	end

	if typeof(storedValue) == "number" then
		return clampIndex(storedValue, #options)
	end

	if typeof(storedValue) == "boolean" then
		return findBooleanOptionIndex(options, storedValue)
			or (storedValue and 1 or math.min(2, #options))
	end

	local defaultIndex = toNumber(config.Default, 1)
	return clampIndex(defaultIndex, #options)
end

local function resolveToggleState(config, storedValue)
	local options = config.Options
	if typeof(options) == "table" and #options > 0 then
		if typeof(storedValue) == "number" then
			local index = clampIndex(storedValue, #options)
			local option = options[index]
			if typeof(option) == "table" and typeof(option.Value) == "boolean" then
				return option.Value, index
			end
			return index == 1, index
		end

		if typeof(storedValue) == "boolean" then
			local index = findBooleanOptionIndex(options, storedValue)
				or (storedValue and 1 or math.min(2, #options))
			return storedValue, index
		end

		local defaultIndex = clampIndex(toNumber(config.Default, 1), #options)
		local defaultOption = options[defaultIndex]
		if typeof(defaultOption) == "table" and typeof(defaultOption.Value) == "boolean" then
			return defaultOption.Value, defaultIndex
		end
		return defaultIndex == 1, defaultIndex
	end

	if typeof(storedValue) == "boolean" then
		return storedValue, storedValue and 1 or 2
	end

	if typeof(config.Default) == "boolean" then
		return config.Default, config.Default and 1 or 2
	end

	return false, 2
end

local function isEnabledDisabledDisplay(options)
	if typeof(options) ~= "table" or #options ~= 2 then
		return false
	end

	local first = string.lower(tostring(options[1].Display or ""))
	local second = string.lower(tostring(options[2].Display or ""))
	local pairA = first == "enabled" and second == "disabled"
	local pairB = first == "disabled" and second == "enabled"
	local pairC = first == "true" and second == "false"
	local pairD = first == "false" and second == "true"

	return pairA or pairB or pairC or pairD
end

local function isBooleanToggleConfig(config)
	if config.SettingType ~= "toggle" then
		return false
	end

	local options = config.Options
	if typeof(options) ~= "table" or #options ~= 2 then
		return false
	end

	local bothBooleanValues = typeof(options[1].Value) == "boolean" and typeof(options[2].Value) == "boolean"
	return bothBooleanValues or isEnabledDisabledDisplay(options)
end

local CROSSHAIR_ADVANCED_KEYS = {
	DividerAdvanced = true,
	DividerAdvancedTop = true,
	DividerAdvancedBottom = true,
	DividerAdvancedLeft = true,
	DividerAdvancedRight = true,
	DividerAdvancedDot = true,
	TopLineColor = true,
	TopLineOpacity = true,
	TopLineThickness = true,
	TopLineLength = true,
	TopLineRoundness = true,
	TopLineRotation = true,
	TopLineGap = true,
	BottomLineColor = true,
	BottomLineOpacity = true,
	BottomLineThickness = true,
	BottomLineLength = true,
	BottomLineRoundness = true,
	BottomLineRotation = true,
	BottomLineGap = true,
	LeftLineColor = true,
	LeftLineOpacity = true,
	LeftLineThickness = true,
	LeftLineLength = true,
	LeftLineRoundness = true,
	LeftLineRotation = true,
	LeftLineGap = true,
	RightLineColor = true,
	RightLineOpacity = true,
	RightLineThickness = true,
	RightLineLength = true,
	RightLineRoundness = true,
	RightLineRotation = true,
	RightLineGap = true,
	DotColor = true,
	DotOpacity = true,
	DotRoundness = true,
}

local GAMEPLAY_ONLY_KEYS = {
	DividerGameplay = true,
	DamageNumbers = true,
	DisableEffects = true,
	HideTeammateDisplay = true,
	DividerSensitivity = true,
	OverallSensitivity = true,
	ControllerSensitivity = true,
	MobileSensitivity = true,
	ADSSensitivity = true,
	SensX = true,
	SensY = true,
	CameraSmoothing = true,
	InvertY = true,
	InvertX = true,
	DividerMovemnt = true,
	ToggleCrouch = true,
	ToggleSprint = true,
	AutoSprint = true,
	AutoSlide = true,
	WallJumpAssist = true,
	DividerCombat = true,
	ToggleAim = true,
	EasyCycle = true,
	AimAssist = true,
	AimAssistStrength = true,
	AutoShoot = true,
	DividerAbility = true,
	EasyAbility = true,
	DividerMobileLayout = true,
	ArrangeMobileButtons = true,
	ResetMobileButtons = true,
}

local function getSettingsListForDisplayCategory(categoryKey)
	if categoryKey == "Video" then
		local baseList = SettingsConfig.getSettingsList("Gameplay")
		local filtered = {}
		for _, item in ipairs(baseList) do
			if not GAMEPLAY_ONLY_KEYS[item.key] then
				table.insert(filtered, item)
			end
		end
		return filtered, "Gameplay"
	end

	if categoryKey == "Gameplay" then
		local baseList = SettingsConfig.getSettingsList("Gameplay")
		local filtered = {}
		for _, item in ipairs(baseList) do
			if GAMEPLAY_ONLY_KEYS[item.key] then
				table.insert(filtered, item)
			end
		end
		return filtered, "Gameplay"
	end

	return SettingsConfig.getSettingsList(categoryKey), categoryKey
end

local function setRowInteractionEnabled(row, enabled)
	if not row then
		return
	end

	local function apply(target)
		if target:IsA("GuiButton") then
			target.Active = enabled
			target.AutoButtonColor = enabled
			target.Selectable = enabled
		elseif target:IsA("GuiObject") then
			target.Active = enabled
		elseif target:IsA("UIDragDetector") then
			target.Enabled = enabled
		end
	end

	apply(row)
	for _, descendant in ipairs(row:GetDescendants()) do
		apply(descendant)
	end
end

local function getMultileControls(row)
	if not row then
		return nil
	end

	local rowBody = row:FindFirstChild("Frame")
	if not rowBody or not rowBody:IsA("Frame") then
		rowBody = row
	end

	local contentRoot = rowBody and rowBody:FindFirstChild("Frame")
	if not contentRoot or not contentRoot:IsA("Frame") then
		contentRoot = rowBody
	end
	if not contentRoot then
		return nil
	end

	local valueLabel = contentRoot:FindFirstChild("Username")
	if valueLabel and not valueLabel:IsA("TextLabel") then
		valueLabel = nil
	end
	if not valueLabel then
		for _, child in ipairs(contentRoot:GetChildren()) do
			if child:IsA("TextLabel") then
				valueLabel = child
				break
			end
		end
	end

	local dotsContainer = nil
	for _, child in ipairs(contentRoot:GetChildren()) do
		if child:IsA("Frame") and child:FindFirstChildWhichIsA("UIListLayout") then
			dotsContainer = child
			break
		end
	end

	local dotTemplate = nil
	if dotsContainer then
		for _, child in ipairs(dotsContainer:GetChildren()) do
			if child:IsA("Frame") then
				dotTemplate = child
				break
			end
		end
	end

	local arrows = {}
	for _, child in ipairs(contentRoot:GetChildren()) do
		if child:IsA("ImageButton") then
			table.insert(arrows, child)
		end
	end
	table.sort(arrows, function(a, b)
		local ax = a.Position.X.Scale + (a.Position.X.Offset / 10000)
		local bx = b.Position.X.Scale + (b.Position.X.Offset / 10000)
		return ax < bx
	end)

	local leftArrow = arrows[1]
	local rightArrow = #arrows >= 2 and arrows[#arrows] or nil

	return {
		rowBody = rowBody,
		contentRoot = contentRoot,
		valueLabel = valueLabel,
		dotsContainer = dotsContainer,
		dotTemplate = dotTemplate,
		leftArrow = leftArrow,
		rightArrow = rightArrow,
	}
end

local function getInfoOptionControls(slot)
	if not slot then
		return nil
	end

	local label = slot:FindFirstChild("Username", true)
	if label and not label:IsA("TextLabel") then
		label = nil
	end
	if not label then
		label = slot:FindFirstChildWhichIsA("TextLabel", true)
	end

	local button = nil
	if slot:IsA("GuiButton") then
		button = slot
	else
		button = slot:FindFirstChildWhichIsA("ImageButton", true)
	end

	local image = slot:FindFirstChild("ImageLabel", true)
	if image and not image:IsA("ImageLabel") then
		image = nil
	end
	if not image then
		image = slot:FindFirstChildWhichIsA("ImageLabel", true)
	end

	return {
		label = label,
		button = button,
		image = image,
	}
end

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections

	self._initialized = false
	self._buttonsActive = false
	self._currentTab = nil
	self._selectedSetting = nil
	self._deviceType = "PC"

	self._tabs = {}
	self._settingRows = {}
	self._keybindUpdaters = {}
	self._multileUpdaters = {}
	self._infoOptionSlots = {}
	self._infoPreviewSettingKey = nil
	self._infoPreviewOptionIndex = nil
	self._awaitingKeybind = nil

	self._currentImageIndex = 1
	self._currentInfoImages = nil
	self._imageCarouselTask = nil
	self._crosshairPreviewRoot = nil
	self._crosshairPreviewFrame = nil
	self._crosshairPreviewModule = nil
	self._crosshairPreviewCustomization = nil
	self._hiddenModulesWhileActive = {}
	self._playerListWasOpen = false
	self._modulesToHideWhileActive = {
		"Start",
		"Actions",
		"Catgory",
		"Kits",
		"Party",
		"Settings",
		"Map",
		"Loadout",
		"Black",
		"TallFade",
		"HUD",
		"Emotes",
		"Dialogue",
		"Spec",
		"Lobby",
		"Kill",
		"Storm",
	}

	self._originals = {
		bgTransparency = 0,
		settingsTransparency = 0,
		settingsPosition = nil,
		topBarPosition = nil,
		infoTransparency = 0,
		infoPosition = nil,
		backHolderPosition = nil,
	}

	self:_cacheUIReferences()
	self:_cacheOriginals()

	return self
end

function module:_buildCrosshairPreviewCustomization()
	local crosshairCategory = SettingsConfig.Categories.Crosshair
	local settings = crosshairCategory and crosshairCategory.Settings

	local function getColorFromSetting(settingKey, value)
		local colorSetting = settings and settings[settingKey]
		local colorOptions = colorSetting and colorSetting.Options
		if typeof(colorOptions) ~= "table" or #colorOptions == 0 then
			return Color3.fromRGB(255, 255, 255)
		end

		if typeof(value) == "number" then
			local index = math.clamp(math.floor(value + 0.5), 1, #colorOptions)
			local option = colorOptions[index]
			if option and typeof(option.Color) == "Color3" then
				return option.Color
			end
		end

		if typeof(value) == "string" then
			for _, option in ipairs(colorOptions) do
				if typeof(option) == "table" then
					local optionValue = tostring(option.Value or "")
					local optionDisplay = tostring(option.Display or "")
					if optionValue == value or optionDisplay == value then
						if typeof(option.Color) == "Color3" then
							return option.Color
						end
					end
				end
			end
		end

		local first = colorOptions[1]
		return (first and typeof(first.Color) == "Color3") and first.Color or Color3.fromRGB(255, 255, 255)
	end

	local function getBool(settingKey, defaultValue)
		local raw = PlayerDataTable.get("Crosshair", settingKey)
		if raw == nil then
			return defaultValue
		end
		return isSettingEnabled(raw)
	end

	local function getNumber(settingKey, defaultValue, minValue, maxValue)
		local raw = PlayerDataTable.get("Crosshair", settingKey)
		local value = toNumber(raw, defaultValue)
		return math.clamp(value, minValue, maxValue)
	end

	local disabled = isSettingEnabled(PlayerDataTable.get("Crosshair", "CrosshairDisabled"))
	local advanced = getBool("AdvancedStyleSettings", false)
	local scalePercent = getNumber("CrosshairSize", 100, 50, 200)
	local opacityPercent = getNumber("CrosshairOpacity", 100, 0, 100)
	local gap = getNumber("CrosshairGap", 10, 0, 50)
	local colorValue = PlayerDataTable.get("Crosshair", "CrosshairColor")

	return {
		showDot = (not disabled) and getBool("ShowDot", true),
		showTopLine = (not disabled) and getBool("ShowTopLine", true),
		showBottomLine = (not disabled) and getBool("ShowBottomLine", true),
		showLeftLine = (not disabled) and getBool("ShowLeftLine", true),
		showRightLine = (not disabled) and getBool("ShowRightLine", true),
		lineThickness = getNumber("CrosshairThickness", 2, 1, 12),
		lineLength = getNumber("CrosshairLineLength", 10, 2, 40),
		gapFromCenter = gap,
		dotSize = getNumber("DotSize", 3, 1, 20),
		rotation = getNumber("GlobalRotation", 0, -180, 180),
		cornerRadius = getNumber("CrosshairRoundness", 0, 0, 20),
		mainColor = getColorFromSetting("CrosshairColor", colorValue),
		outlineColor = getColorFromSetting("OutlineColor", PlayerDataTable.get("Crosshair", "OutlineColor")),
		outlineThickness = getNumber("OutlineThickness", 0, 0, 6),
		outlineOpacity = getNumber("OutlineOpacity", 100, 0, 100) / 100,
		opacity = opacityPercent / 100,
		scale = scalePercent / 100,
		dynamicSpreadEnabled = getBool("DynamicSpreadEnabled", true),
		recoilSpreadMultiplier = getNumber("RecoilSpreadMultiplier", 1, 0, 5),
		spread = {
			movement = getNumber("MovementSpreadMultiplier", 1, 0, 5),
			sprint = getNumber("SprintSpreadMultiplier", 1, 0, 5),
			air = getNumber("AirSpreadMultiplier", 1, 0, 5),
			crouch = getNumber("CrouchSpreadMultiplier", 1, 0, 5),
		},
		advancedStyleSettings = advanced,
		perLineStyles = {
			Top = {
				color = getColorFromSetting("TopLineColor", PlayerDataTable.get("Crosshair", "TopLineColor")),
				opacity = getNumber("TopLineOpacity", 100, 0, 100) / 100,
				thickness = getNumber("TopLineThickness", 2, 1, 12),
				length = getNumber("TopLineLength", 10, 2, 40),
				roundness = getNumber("TopLineRoundness", 0, 0, 20),
				rotation = getNumber("TopLineRotation", 0, -180, 180),
				gap = getNumber("TopLineGap", gap, -50, 50),
			},
			Bottom = {
				color = getColorFromSetting("BottomLineColor", PlayerDataTable.get("Crosshair", "BottomLineColor")),
				opacity = getNumber("BottomLineOpacity", 100, 0, 100) / 100,
				thickness = getNumber("BottomLineThickness", 2, 1, 12),
				length = getNumber("BottomLineLength", 10, 2, 40),
				roundness = getNumber("BottomLineRoundness", 0, 0, 20),
				rotation = getNumber("BottomLineRotation", 0, -180, 180),
				gap = getNumber("BottomLineGap", gap, -50, 50),
			},
			Left = {
				color = getColorFromSetting("LeftLineColor", PlayerDataTable.get("Crosshair", "LeftLineColor")),
				opacity = getNumber("LeftLineOpacity", 100, 0, 100) / 100,
				thickness = getNumber("LeftLineThickness", 2, 1, 12),
				length = getNumber("LeftLineLength", 10, 2, 40),
				roundness = getNumber("LeftLineRoundness", 0, 0, 20),
				rotation = getNumber("LeftLineRotation", 0, -180, 180),
				gap = getNumber("LeftLineGap", gap, -50, 50),
			},
			Right = {
				color = getColorFromSetting("RightLineColor", PlayerDataTable.get("Crosshair", "RightLineColor")),
				opacity = getNumber("RightLineOpacity", 100, 0, 100) / 100,
				thickness = getNumber("RightLineThickness", 2, 1, 12),
				length = getNumber("RightLineLength", 10, 2, 40),
				roundness = getNumber("RightLineRoundness", 0, 0, 20),
				rotation = getNumber("RightLineRotation", 0, -180, 180),
				gap = getNumber("RightLineGap", gap, -50, 50),
			},
		},
		dotStyle = {
			color = getColorFromSetting("DotColor", PlayerDataTable.get("Crosshair", "DotColor")),
			opacity = getNumber("DotOpacity", 100, 0, 100) / 100,
			size = getNumber("DotSize", 3, 1, 20),
			roundness = getNumber("DotRoundness", 0, 0, 20),
		},
	}
end

function module:_ensureCrosshairPreview()
	if self._crosshairPreviewRoot and self._crosshairPreviewRoot.Parent and self._crosshairPreviewModule then
		return true
	end

	if not self._infoImageHolder then
		return false
	end

	local root = self._infoImageHolder:FindFirstChild("CrosshairPreview")
	if not root then
		root = Instance.new("Frame")
		root.Name = "CrosshairPreview"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromScale(1, 1)
		root.Position = UDim2.fromScale(0, 0)
		root.ZIndex = 20
		root.Visible = false
		root.Parent = self._infoImageHolder
	end

	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local crosshairGui = playerGui and playerGui:FindFirstChild("Crosshair")
	local templateContainer = crosshairGui and crosshairGui:FindFirstChild("Frame")
	local template = templateContainer and templateContainer:FindFirstChild("Default")
	if not (template and template:IsA("Frame")) then
		return false
	end

	for _, child in ipairs(root:GetChildren()) do
		child:Destroy()
	end

	local previewFrame = template:Clone()
	previewFrame.Name = "PreviewCrosshair"
	previewFrame.Visible = true
	previewFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	previewFrame.Position = UDim2.fromScale(0.5, 0.5)
	previewFrame.Parent = root
	local previewScale = previewFrame:FindFirstChildOfClass("UIScale")
	if previewScale then
		previewScale.Scale = previewScale.Scale * 1.85
	else
		local scaleObj = Instance.new("UIScale")
		scaleObj.Scale = 1.85
		scaleObj.Parent = previewFrame
	end

	local hitmarker = previewFrame:FindFirstChild("Hitmarker", true)
	if hitmarker and hitmarker:IsA("GuiObject") then
		hitmarker.Visible = false
	end

	local previewModule = DefaultCrosshairModule.new(previewFrame)
	if not previewModule then
		previewFrame:Destroy()
		return false
	end

	self._crosshairPreviewRoot = root
	self._crosshairPreviewFrame = previewFrame
	self._crosshairPreviewModule = previewModule
	self._crosshairPreviewCustomization = self:_buildCrosshairPreviewCustomization()
	self._crosshairPreviewModule:ApplyCustomization(self._crosshairPreviewCustomization)

	self._connections:cleanupGroup("crosshairPreview")
	self._connections:track(RunService, "RenderStepped", function(dt)
		if not self._crosshairPreviewModule or not self._crosshairPreviewRoot or not self._crosshairPreviewRoot.Visible then
			return
		end

		local now = tick()
		local moveAmount = ((math.sin(now * 1.35) + 1) * 0.5) * 16
		self._crosshairPreviewModule:Update(dt, {
			velocity = Vector3.new(moveAmount, 0, 0),
			speed = moveAmount,
			weaponData = {
				spreadX = 1,
				spreadY = 1,
				recoilMultiplier = 1,
			},
			customization = self._crosshairPreviewCustomization,
			dt = dt,
			isCrouching = false,
			isSliding = false,
			isSprinting = moveAmount > 11,
			isGrounded = true,
			isADS = false,
		})
	end, "crosshairPreview")

	return true
end

function module:_hideCrosshairPreview()
	self._connections:cleanupGroup("crosshairPreview")
	if self._crosshairPreviewRoot then
		self._crosshairPreviewRoot.Visible = false
	end
end

function module:_updateCrosshairPreview()
	if not self:_ensureCrosshairPreview() then
		return
	end

	self._crosshairPreviewCustomization = self:_buildCrosshairPreviewCustomization()
	if self._crosshairPreviewModule then
		self._crosshairPreviewModule:ApplyCustomization(self._crosshairPreviewCustomization)
	end
	if self._crosshairPreviewRoot then
		self._crosshairPreviewRoot.Visible = true
	end
end

function module:_cacheUIReferences()
	self._topBar = self._ui:FindFirstChild("TopBar")
	self._templatesRoot = self._ui:FindFirstChild("Templates")

	self._backHolder = self._ui:FindFirstChild("Frame")
	local exactBackButton = self._backHolder and self._backHolder:FindFirstChild("Frame")
	if exactBackButton and not exactBackButton:IsA("GuiButton") then
		exactBackButton = nil
	end
	self._backButton = exactBackButton
		or (self._backHolder and (
			self._backHolder:FindFirstChildWhichIsA("ImageButton", true)
			or self._backHolder:FindFirstChildWhichIsA("TextButton", true)
		))

	self._bgCanvas = self._ui:FindFirstChild("BG")
	self._settingsCanvas = self._ui:FindFirstChild("Settings")
	self._scrollFrame = self._settingsCanvas and self._settingsCanvas:FindFirstChild("Frame")
	if self._scrollFrame and not self._scrollFrame:IsA("ScrollingFrame") then
		self._scrollFrame = nil
	end

	self._infoPanel = self._ui:FindFirstChild("Info")
	self._infoRoot = self._infoPanel and self._infoPanel:FindFirstChild("Frame")

	local infoUsernames = getDirectChildrenByName(self._infoRoot, "Username")
	self._infoTitleLabel = infoUsernames[1]
	self._infoDescriptionLabel = infoUsernames[2] or infoUsernames[1]

	self._infoImageFrame = self._infoRoot and self._infoRoot:FindFirstChild("ImageFrame")
	self._infoVideoFrame = self._infoRoot and self._infoRoot:FindFirstChild("VideoFrame")
	self._infoOptionsContainer = self._infoRoot and self._infoRoot:FindFirstChild("Options")
	self._infoOptionSlots = {}
	if self._infoOptionsContainer then
		for _, child in ipairs(self._infoOptionsContainer:GetChildren()) do
			if child:IsA("GuiObject") then
				table.insert(self._infoOptionSlots, child)
				child.Visible = false
			end
		end

		table.sort(self._infoOptionSlots, function(a, b)
			return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
		end)

		self._infoOptionsContainer.Visible = false
	end

	self._infoImageHolder = self._infoImageFrame and self._infoImageFrame:FindFirstChild("Holder")
	self._infoImageCanvas = self._infoImageHolder and self._infoImageHolder:FindFirstChildWhichIsA("CanvasGroup")
	self._infoCurrentImage = self._infoImageCanvas and self._infoImageCanvas:FindFirstChild("Current")
	self._infoNextImage = self._infoImageCanvas and self._infoImageCanvas:FindFirstChild("Next")

	self._infoVideoHolder = self._infoVideoFrame and self._infoVideoFrame:FindFirstChild("VideoHolder")
	self._infoVideoPlayer = self._infoVideoHolder and self._infoVideoHolder:FindFirstChild("VideoFrame")
end

function module:_cacheOriginals()
	if self._bgCanvas then
		self._originals.bgTransparency = self._bgCanvas.GroupTransparency
	end

	if self._settingsCanvas then
		self._originals.settingsTransparency = self._settingsCanvas.GroupTransparency
		self._originals.settingsPosition = self._settingsCanvas.Position
	end

	if self._topBar then
		self._originals.topBarPosition = self._topBar.Position
	end

	if self._infoPanel and self._infoPanel:IsA("CanvasGroup") then
		self._originals.infoTransparency = self._infoPanel.GroupTransparency
	end

	if self._infoPanel and self._infoPanel:IsA("GuiObject") then
		self._originals.infoPosition = self._infoPanel.Position
	end

	if self._backHolder and self._backHolder:IsA("GuiObject") then
		self._originals.backHolderPosition = self._backHolder.Position
	end
end

function module:_init()
	if self._initialized then
		self:_reconnect()
		self:_selectTab(self._currentTab or DEFAULT_TAB, true)
		return
	end

	self._initialized = true
	self:_detectDeviceType()

	SettingsConfig.init(self._templatesRoot)
	PlayerDataTable.init()

	self:_cacheTopBarButtons()
	self:_applyPersonalThumbnail()
	self:_resetAllTabVisuals()
	self:_setupTopBar()
	self:_setupBackButton()
	self:_selectTab(DEFAULT_TAB, true)
end

function module:_detectDeviceType()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		self._deviceType = "Mobile"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		self._deviceType = "Console"
	else
		self._deviceType = "PC"
	end
end

function module:_applyPersonalThumbnail()
	local personalTab = self._tabs.PersonalHolder
	if not personalTab or not personalTab.playerImage then
		return
	end

	local player = Players.LocalPlayer
	if not player then
		return
	end

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420
			)
		end)
		if ok and content and personalTab.playerImage and personalTab.playerImage.Parent then
			personalTab.playerImage.Image = content
		end
	end)
end

function module:_reconnect()
	self._connections:cleanupGroup("topbar")
	self._connections:cleanupGroup("back")
	self:_setupTopBar()
	self:_setupBackButton()
end

function module:_hideOtherUiWhileActive()
	table.clear(self._hiddenModulesWhileActive)

	for _, moduleName in ipairs(self._modulesToHideWhileActive) do
		if self._export:isOpen(moduleName) then
			self._hiddenModulesWhileActive[moduleName] = true
			self._export:hide(moduleName)
		end
	end

	self._playerListWasOpen = self._export:isOpen("PlayerList")
	if self._playerListWasOpen then
		self._export:hide("PlayerList")
	end
	self._export:emit("PlayerList_SetVisibility", false)
end

function module:_restoreUiAfterClose()
	for moduleName in pairs(self._hiddenModulesWhileActive) do
		self._export:show(moduleName, true)
	end
	table.clear(self._hiddenModulesWhileActive)

	if self._playerListWasOpen then
		self._export:show("PlayerList", true)
	end
	self._playerListWasOpen = false
	self._export:emit("PlayerList_SetVisibility", true)
end

function module:_cacheTopBarButtons()
	table.clear(self._tabs)
	if not self._topBar then
		return
	end

	for _, tabDef in ipairs(TAB_MAP) do
		local holder = self._topBar:FindFirstChild(tabDef.holder)
		if not holder then
			continue
		end

		local button = holder:FindFirstChild("Frame")
		if not button or not button:IsA("ImageButton") then
			button = holder:FindFirstChildWhichIsA("ImageButton")
		end
		if not button then
			continue
		end

		local label = button:FindFirstChild("Username", true)
		if label and not label:IsA("TextLabel") then
			label = nil
		end

		local image = button:FindFirstChildWhichIsA("ImageLabel")

		local textLabels = {}
		for _, descendant in ipairs(button:GetDescendants()) do
			if descendant:IsA("TextLabel") then
				table.insert(textLabels, descendant)
			end
		end

		local strokes = {}
		for _, textLabel in ipairs(textLabels) do
			local stroke = textLabel:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				table.insert(strokes, stroke)
			end
		end

		local playerImage = nil
		if tabDef.holder == "PersonalHolder" then
			playerImage = button:FindFirstChild("PlayerImage", true)
			if playerImage and not playerImage:IsA("ImageLabel") then
				playerImage = nil
			end
		end

		self._tabs[tabDef.holder] = {
			button = button,
			label = label,
			image = image,
			textLabels = textLabels,
			strokes = strokes,
			playerImage = playerImage,
			skipImageVisual = tabDef.holder == "PersonalHolder",
			categoryKey = tabDef.categoryKey,
		}
	end
end

function module:_setTabVisual(tabData, selected)
	if tabData.button then
		tabData.button.BackgroundTransparency = selected and TweenConfig.Values.SelectedButtonTransparency
			or TweenConfig.Values.DeselectedButtonTransparency
	end

	for _, textLabel in ipairs(tabData.textLabels or {}) do
		textLabel.TextColor3 = selected and TweenConfig.Values.SelectedTextColor
			or TweenConfig.Values.DeselectedTextColor
	end

	for _, stroke in ipairs(tabData.strokes or {}) do
		stroke.Color = TweenConfig.Values.SelectedStrokeColor
		stroke.Transparency = selected and 0 or 1
		stroke.Enabled = selected
	end

	if tabData.image and not tabData.skipImageVisual then
		tabData.image.ImageColor3 = selected and TweenConfig.Values.SelectedImageColor
			or TweenConfig.Values.DeselectedImageColor
	end
end

function module:_resetAllTabVisuals()
	for _, tabData in pairs(self._tabs) do
		self:_setTabVisual(tabData, false)
	end
end

function module:_setupTopBar()
	for holderName, tabData in pairs(self._tabs) do
		local tabKey = holderName
		local button = tabData.button
		local hovering = false

		self._connections:track(button, "Activated", function()
			if not self._buttonsActive then
				return
			end
			self:_selectTab(tabKey)
		end, "topbar")

		self._connections:track(button, "MouseEnter", function()
			if hovering or self._currentTab == tabKey then
				return
			end
			hovering = true

			if tabData.button then
				cancelTweenGroup("tab_hover_" .. tabKey)
				local tween = TweenService:Create(tabData.button, TweenConfig.create("TabHover"), {
					BackgroundTransparency = TweenConfig.Values.HoverButtonTransparency,
				})
				tween:Play()
				currentTweens["tab_hover_" .. tabKey] = { tween }
			end
		end, "topbar")

		self._connections:track(button, "MouseLeave", function()
			if not hovering then
				return
			end
			hovering = false
			if self._currentTab == tabKey then
				return
			end

			if tabData.button then
				cancelTweenGroup("tab_hover_" .. tabKey)
				local tween = TweenService:Create(tabData.button, TweenConfig.create("TabHoverOut"), {
					BackgroundTransparency = TweenConfig.Values.DeselectedButtonTransparency,
				})
				tween:Play()
				currentTweens["tab_hover_" .. tabKey] = { tween }
			end
		end, "topbar")
	end
end

function module:_selectTab(holderName, forceRefresh, preferredSettingKey)
	if not forceRefresh and self._currentTab == holderName then
		return
	end

	if self._currentTab and self._tabs[self._currentTab] then
		self:_animateTabDeselect(self._currentTab)
	end

	self._currentTab = holderName
	self:_animateTabSelect(holderName)

	local previousSelectedSetting = self._selectedSetting
	self:_clearSettings()

	local tabData = self._tabs[holderName]
	local categoryKey = tabData and tabData.categoryKey
	if categoryKey then
		local targetSettingKey = preferredSettingKey or previousSelectedSetting
		self:_populateSettings(categoryKey, targetSettingKey)
	else
		self:_clearInfoPanel()
	end
end

function module:_animateTabSelect(holderName)
	local tabData = self._tabs[holderName]
	if not tabData then
		return
	end

	cancelTweenGroup("tab_state_" .. holderName)
	local tweens = {}

	if tabData.button then
		local tween = TweenService:Create(tabData.button, TweenConfig.create("TabSelect"), {
			BackgroundTransparency = TweenConfig.Values.SelectedButtonTransparency,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	for _, textLabel in ipairs(tabData.textLabels or {}) do
		local tween = TweenService:Create(textLabel, TweenConfig.create("TabSelect"), {
			TextColor3 = TweenConfig.Values.SelectedTextColor,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	for _, stroke in ipairs(tabData.strokes or {}) do
		stroke.Enabled = true
		local tween = TweenService:Create(stroke, TweenConfig.create("TabSelect"), {
			Color = TweenConfig.Values.SelectedStrokeColor,
			Transparency = 0,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	if tabData.image and not tabData.skipImageVisual then
		local tween = TweenService:Create(tabData.image, TweenConfig.create("TabSelect"), {
			ImageColor3 = TweenConfig.Values.SelectedImageColor,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	currentTweens["tab_state_" .. holderName] = tweens
end

function module:_animateTabDeselect(holderName)
	local tabData = self._tabs[holderName]
	if not tabData then
		return
	end

	cancelTweenGroup("tab_state_" .. holderName)
	local tweens = {}

	if tabData.button then
		local tween = TweenService:Create(tabData.button, TweenConfig.create("TabDeselect"), {
			BackgroundTransparency = TweenConfig.Values.DeselectedButtonTransparency,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	for _, textLabel in ipairs(tabData.textLabels or {}) do
		local tween = TweenService:Create(textLabel, TweenConfig.create("TabDeselect"), {
			TextColor3 = TweenConfig.Values.DeselectedTextColor,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	for _, stroke in ipairs(tabData.strokes or {}) do
		stroke.Enabled = true
		local tween = TweenService:Create(stroke, TweenConfig.create("TabDeselect"), {
			Transparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			if self._currentTab ~= holderName then
				stroke.Enabled = false
			end
		end)
		table.insert(tweens, tween)
	end

	if tabData.image and not tabData.skipImageVisual then
		local tween = TweenService:Create(tabData.image, TweenConfig.create("TabDeselect"), {
			ImageColor3 = TweenConfig.Values.DeselectedImageColor,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	currentTweens["tab_state_" .. holderName] = tweens
end

function module:_clearSettings()
	self:_stopAwaitingKeybind(true)
	self:_stopImageCarousel()
	self:_stopVideo()
	self:_hideCrosshairPreview()

	for _, rowData in ipairs(self._settingRows) do
		if rowData.row and rowData.row.Parent then
			rowData.row:Destroy()
		end
	end

	table.clear(self._settingRows)
	table.clear(self._keybindUpdaters)
	table.clear(self._multileUpdaters)
	self._selectedSetting = nil

	self._connections:cleanupGroup("settingRows")
	self._connections:cleanupGroup("keybindCapture")
	self._connections:cleanupGroup("infoOptions")
end

function module:_resolveSettingRenderType(config)
	if config.SettingType == "toggle" then
		if isBooleanToggleConfig(config) then
			return "toggle"
		end
		return "Multile"
	end

	return config.SettingType
end

function module:_populateSettings(categoryKey, preferredSettingKey)
	if not self._scrollFrame then
		return
	end

	self._scrollFrame.Visible = true
	local settingsList, sourceCategory = getSettingsListForDisplayCategory(categoryKey)
	sourceCategory = sourceCategory or categoryKey
	local firstSelectableSetting = nil
	local lastLayoutOrder = 0

	for index, settingData in ipairs(settingsList) do
		if categoryKey == "Crosshair" and CROSSHAIR_ADVANCED_KEYS[settingData.key] then
			local advancedEnabled = isSettingEnabled(PlayerDataTable.get("Crosshair", "AdvancedStyleSettings"))
			if not advancedEnabled then
				continue
			end
		end

		local available = SettingsConfig.isSettingAllowedOnDevice(settingData.config, self._deviceType)
		local row, renderType = self:_createSettingRow(sourceCategory, settingData.key, settingData.config, index, available)
		if not row then
			continue
		end
		lastLayoutOrder = math.max(lastLayoutOrder, row.LayoutOrder or index)

		local rowData = {
			key = settingData.key,
			config = settingData.config,
			renderType = renderType or settingData.config.SettingType,
			row = row,
			category = sourceCategory,
			available = available,
		}
		table.insert(self._settingRows, rowData)

		if not firstSelectableSetting and available and settingData.config.SettingType ~= "divider" then
			firstSelectableSetting = settingData.key
		end
	end

	local resetRow = self:_createResetRow(sourceCategory, lastLayoutOrder + 1)
	if resetRow then
		table.insert(self._settingRows, {
			key = "__reset_" .. tostring(categoryKey),
			config = {
				Name = "Reset To Default",
				Description = "Reset this category to default settings.",
				SettingType = "reset",
			},
			renderType = "reset",
			row = resetRow,
			category = categoryKey,
			available = true,
		})
	end

	local targetSetting = nil
	if type(preferredSettingKey) == "string" and preferredSettingKey ~= "" then
		local preferredRow = self:_findRowData(preferredSettingKey)
		if preferredRow and preferredRow.available and preferredRow.renderType ~= "divider" then
			targetSetting = preferredSettingKey
		end
	end

	if not targetSetting then
		targetSetting = firstSelectableSetting
	end

	if targetSetting then
		self:_selectSetting(targetSetting)
	else
		self:_clearInfoPanel()
	end
end

function module:_createResetRow(categoryKey, order)
	if not self._scrollFrame then
		return nil
	end
	if type(categoryKey) ~= "string" or categoryKey == "" then
		return nil
	end

	local template = SettingsConfig.Templates.Reset
	if not template then
		return nil
	end

	local row = template:Clone()
	row.Name = "ResetButton"
	row.LayoutOrder = order or 9999
	row.Visible = true
	row.Parent = self._scrollFrame

	local action = row:FindFirstChild("Action", true)
	local holder = action and action:FindFirstChild("HOLDER", true)
	local holderLabel = holder and holder:FindFirstChildWhichIsA("TextLabel", true)
	if holderLabel and holderLabel:IsA("TextLabel") then
		holderLabel.Text = "RESET TO DEFAULT"
	end

	local titleLabel = row:FindFirstChild("Username", true)
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = "RESET"
	end

	local function triggerReset()
		if not self._buttonsActive then
			return
		end
		if not PlayerDataTable.resetCategory(categoryKey) then
			return
		end
		self:_selectTab(self._currentTab or DEFAULT_TAB, true)
	end

	local function bindResetClick(target)
		if not target then
			return false
		end
		if target:IsA("GuiButton") then
			target.Active = true
			target.AutoButtonColor = false
			target.Selectable = false
			self._connections:track(target, "Activated", triggerReset, "settingRows")
			return true
		end
		return false
	end

	if not bindResetClick(action) then
		local button = row:FindFirstChildWhichIsA("GuiButton", true)
		if not bindResetClick(button) then
			self._connections:track(row, "InputBegan", function(input)
				if not isPointerInput(input) then
					return
				end
				triggerReset()
			end, "settingRows")
		end
	end

	return row
end

function module:_createSettingRow(categoryKey, settingKey, config, order, available)
	local renderType = self:_resolveSettingRenderType(config)
	local row = nil
	if available then
		row = SettingsConfig.cloneTemplate(renderType)
	else
		row = SettingsConfig.cloneUnavailableTemplate(renderType) or SettingsConfig.cloneTemplate(renderType)
	end

	if not row then
		return nil
	end

	row.Name = "Setting_" .. settingKey
	row.LayoutOrder = order
	row.Visible = true
	row.Parent = self._scrollFrame

	local rowBody = row:FindFirstChild("Frame")
	if not rowBody or not rowBody:IsA("Frame") then
		rowBody = row
	end

	local titleLabel = rowBody:FindFirstChild("Username")
	if not titleLabel then
		titleLabel = rowBody:FindFirstChildWhichIsA("TextLabel", true)
	end
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = config.Name
	end

	local rowIcon = rowBody:FindFirstChild("ImageLabel")
	if rowIcon and rowIcon:IsA("ImageLabel") then
		if typeof(config.Icon) == "string" and config.Icon ~= "" then
			rowIcon.Image = config.Icon
			rowIcon.Visible = true
		else
			rowIcon.Visible = false
		end
	end

	if renderType == "toggle" and available then
		self:_setupToggleRow(categoryKey, settingKey, config, row)
	elseif renderType == "Multile" and available then
		self:_setupMultileRow(categoryKey, settingKey, config, row)
	elseif renderType == "slider" and available then
		self:_setupSliderRow(categoryKey, settingKey, config, row)
	elseif renderType == "keybind" and available then
		self:_setupKeybindRow(settingKey, row)
	elseif renderType == "action" and available then
		self:_setupActionRow(categoryKey, settingKey, config, row)
	end

	if renderType ~= "divider" and available then
		self:_setupRowSelect(settingKey, row, rowBody)
		self:_setupRowHover(settingKey, row, rowBody)
		self:_setRowSelectedVisual(row, false)
	end

	if not available then
		setRowInteractionEnabled(row, false)
		if rowBody and rowBody:IsA("Frame") then
			rowBody.BackgroundTransparency = 1
		end
		local holder = row:FindFirstChild("HOLDER", true)
		local valueLabel = holder and holder:FindFirstChild("TextLabel", true)
		if valueLabel and valueLabel:IsA("TextLabel") then
			valueLabel.Text = "UNAVAILABLE"
		end
	end

	return row, renderType
end

function module:_setupActionRow(categoryKey, settingKey, config, row)
	local actionContainer = row:FindFirstChild("Action", true)
	local holder = actionContainer and actionContainer:FindFirstChild("HOLDER", true)
	local holderLabel = holder and holder:FindFirstChildWhichIsA("TextLabel", true)
	if holderLabel and holderLabel:IsA("TextLabel") then
		holderLabel.Text = tostring(config.ActionLabel or "APPLY")
	end

	local function triggerAction()
		if not self._buttonsActive then
			return
		end
		self:_selectSetting(settingKey)

		local currentValue = PlayerDataTable.get(categoryKey, settingKey)
		local numericValue = tonumber(currentValue) or 0
		PlayerDataTable.set(categoryKey, settingKey, numericValue + 1)
	end

	local function bindAction(target)
		if not target then
			return false
		end
		if target:IsA("GuiButton") then
			target.Active = true
			target.AutoButtonColor = false
			target.Selectable = false
			self._connections:track(target, "Activated", triggerAction, "settingRows")
			return true
		end
		return false
	end

	if not bindAction(actionContainer) then
		local button = row:FindFirstChildWhichIsA("GuiButton", true)
		if not bindAction(button) then
			self._connections:track(row, "InputBegan", function(input)
				if not isPointerInput(input) then
					return
				end
				triggerAction()
			end, "settingRows")
		end
	end
end

function module:_setupRowSelect(settingKey, row, rowBody)
	local function bindClick(target)
		if not target then
			return
		end

		self._connections:track(target, "InputBegan", function(input)
			if not isPointerInput(input) then
				return
			end
			if not self._buttonsActive then
				return
			end
			self:_selectSetting(settingKey)
		end, "settingRows")
	end

	bindClick(row)
	if rowBody ~= row then
		bindClick(rowBody)
	end
end

function module:_setupRowHover(settingKey, row, rowBody)
	if self._deviceType ~= "PC" then
		return
	end

	local function bindHover(target)
		if not target or not target:IsA("GuiObject") then
			return
		end

		target.Active = true

		self._connections:track(target, "MouseEnter", function()
			if not self._buttonsActive then
				return
			end
			if self._selectedSetting == settingKey then
				return
			end

			local etc = row:FindFirstChild("Etc")
			if not etc or not etc:IsA("GuiObject") then
				return
			end

			local key = "row_hover_" .. row.Name
			cancelTweenGroup(key)
			local tween = TweenService:Create(etc, TweenConfig.create("TabHover"), {
				BackgroundTransparency = TweenConfig.Values.HoverIndicatorTransparency,
			})
			tween:Play()
			currentTweens[key] = { tween }
		end, "settingRows")

		self._connections:track(target, "MouseLeave", function()
			if self._selectedSetting == settingKey then
				return
			end

			local etc = row:FindFirstChild("Etc")
			if not etc or not etc:IsA("GuiObject") then
				return
			end

			local key = "row_hover_" .. row.Name
			cancelTweenGroup(key)
			local tween = TweenService:Create(etc, TweenConfig.create("TabHoverOut"), {
				BackgroundTransparency = TweenConfig.Values.DeselectedIndicatorTransparency,
			})
			tween:Play()
			currentTweens[key] = { tween }
		end, "settingRows")
	end

	bindHover(row)
	if rowBody ~= row then
		bindHover(rowBody)
	end
end

function module:_setRowSelectedVisual(row, selected)
	local key = row.Name
	cancelTweenGroup("row_state_" .. key)

	local tweens = {}
	local uiScale = row:FindFirstChildWhichIsA("UIScale", true)
	if uiScale then
		local tween = TweenService:Create(uiScale, TweenConfig.create(selected and "RowSelect" or "RowDeselect"), {
			Scale = selected and TweenConfig.Values.RowSelectedScale or 1,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	local etc = row:FindFirstChild("Etc")
	if etc and etc:IsA("GuiObject") then
		local ok = pcall(function()
			return etc.BackgroundTransparency
		end)
		if ok then
			local tween = TweenService:Create(etc, TweenConfig.create(selected and "RowSelect" or "RowDeselect"), {
				BackgroundTransparency = selected and TweenConfig.Values.SelectedIndicatorTransparency
					or TweenConfig.Values.DeselectedIndicatorTransparency,
			})
			tween:Play()
			table.insert(tweens, tween)
		else
			etc.Visible = selected
		end
	end

	local selectFrame = row:FindFirstChild("Select", true)
	if selectFrame then
		local bottomBar = selectFrame:FindFirstChild("BottomBar")
		if bottomBar and bottomBar:IsA("Frame") then
			local tween = TweenService:Create(bottomBar, TweenConfig.create(selected and "RowSelect" or "RowDeselect"), {
				BackgroundTransparency = selected and 0 or 1,
			})
			tween:Play()
			table.insert(tweens, tween)
		end

		local glow = selectFrame:FindFirstChild("Glow")
		local glowGradient = glow and glow:FindFirstChild("UIGradient")
		if glowGradient and glowGradient:IsA("UIGradient") then
			local tween = TweenService:Create(glowGradient, TweenConfig.create(selected and "RowSelect" or "RowDeselect"), {
				Offset = selected and Vector2.new(0, 0) or Vector2.new(0, 1),
			})
			tween:Play()
			table.insert(tweens, tween)
		end
	end

	if #tweens > 0 then
		currentTweens["row_state_" .. key] = tweens
	end
end

function module:_findRowData(settingKey)
	for _, rowData in ipairs(self._settingRows) do
		if rowData.key == settingKey then
			return rowData
		end
	end
	return nil
end

function module:_selectSetting(settingKey)
	if self._selectedSetting == settingKey then
		return
	end

	self:_deselectSetting()
	self._selectedSetting = settingKey

	local rowData = self:_findRowData(settingKey)
	if not rowData then
		return
	end

	self:_setRowSelectedVisual(rowData.row, true)
	self:_updateInfoPanel(rowData)
end

function module:_deselectSetting()
	if not self._selectedSetting then
		return
	end

	local rowData = self:_findRowData(self._selectedSetting)
	self._selectedSetting = nil

	if rowData then
		self:_setRowSelectedVisual(rowData.row, false)
	end
end

function module:_clearInfoOptions()
	self._connections:cleanupGroup("infoOptions")
	self._infoPreviewSettingKey = nil
	self._infoPreviewOptionIndex = nil

	if not self._infoOptionsContainer then
		return
	end

	for _, slot in ipairs(self._infoOptionSlots) do
		if slot and slot.Parent == self._infoOptionsContainer then
			slot.Visible = false
		end
	end

	self._infoOptionsContainer.Visible = false
end

function module:_populateInfoOptions(rowData)
	if not self._infoOptionsContainer then
		return
	end

	self:_clearInfoOptions()

	local options = rowData.config and rowData.config.Options
	if typeof(options) ~= "table" or #options == 0 then
		return
	end

	if #self._infoOptionSlots == 0 then
		for _, child in ipairs(self._infoOptionsContainer:GetChildren()) do
			if child:IsA("GuiObject") then
				table.insert(self._infoOptionSlots, child)
				child.Visible = false
			end
		end
		table.sort(self._infoOptionSlots, function(a, b)
			return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
		end)
	end

	if #self._infoOptionSlots > 0 and #self._infoOptionSlots < #options then
		local baseSlot = self._infoOptionSlots[1]
		for _ = (#self._infoOptionSlots + 1), #options do
			local clone = baseSlot:Clone()
			clone.Visible = false
			clone.Parent = self._infoOptionsContainer
			table.insert(self._infoOptionSlots, clone)
		end
	end

	if #self._infoOptionSlots == 0 then
		return
	end

	local selectedIndex = nil
	local updater = self._multileUpdaters[rowData.key]
	if updater and updater.getIndex then
		selectedIndex = updater.getIndex()
	end
	if selectedIndex == nil then
		local storedValue = PlayerDataTable.get(rowData.category, rowData.key)
		selectedIndex = resolveOptionIndex(rowData.config, storedValue)
	end
	selectedIndex = clampIndex(toNumber(selectedIndex, rowData.config.Default or 1), #options)

	if self._infoPreviewSettingKey ~= rowData.key then
		self._infoPreviewSettingKey = rowData.key
		self._infoPreviewOptionIndex = selectedIndex
	else
		self._infoPreviewOptionIndex = clampIndex(toNumber(self._infoPreviewOptionIndex, selectedIndex), #options)
	end

	local layout = self._infoOptionsContainer:FindFirstChildWhichIsA("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Parent = self._infoOptionsContainer
		layout.FillDirection = Enum.FillDirection.Horizontal
	end
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	self._infoOptionsContainer.Visible = true

	local function applyPreview(optionIndex)
		local clampedIndex = clampIndex(toNumber(optionIndex, selectedIndex), #options)
		self._infoPreviewSettingKey = rowData.key
		self._infoPreviewOptionIndex = clampedIndex

		for i, slot in ipairs(self._infoOptionSlots) do
			if slot and slot.Parent == self._infoOptionsContainer and i <= #options then
				local option = options[i]
				local controls = getInfoOptionControls(slot)
				local isSelected = i == clampedIndex
				local hasOptionColor = typeof(option.Color) == "Color3"
				local optionColor = hasOptionColor and option.Color or Color3.fromRGB(230, 230, 230)

				if controls and controls.label then
					controls.label.TextColor3 = isSelected and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
				end

				if slot:IsA("GuiObject") then
					slot.BackgroundColor3 = optionColor
					slot.BackgroundTransparency = isSelected and 0 or 1
				end

				if controls and controls.button then
					controls.button.Active = true
					controls.button.AutoButtonColor = false
					controls.button.Selectable = false
				end

				if controls and controls.image then
					controls.image.ImageColor3 = Color3.fromRGB(0, 0, 0)
					controls.image.Visible = isSelected
					controls.image.ImageTransparency = isSelected and 0 or 1
				end
			end
		end

		self:_applyInfoMedia(rowData)
	end

	local function bindPreview(target, optionIndex)
		if not target then
			return
		end

		if target:IsA("GuiButton") then
			self._connections:track(target, "Activated", function()
				if not self._buttonsActive then
					return
				end
				applyPreview(optionIndex)
			end, "infoOptions")
			return
		end

		if target:IsA("GuiObject") then
			self._connections:track(target, "InputBegan", function(input)
				if not self._buttonsActive then
					return
				end
				if not isPointerInput(input) then
					return
				end

				applyPreview(optionIndex)
			end, "infoOptions")
		end
	end

	for optionIndex, slot in ipairs(self._infoOptionSlots) do
		local option = options[optionIndex]
		if option and slot and slot.Parent == self._infoOptionsContainer then
			slot.Visible = true
			if slot:IsA("GuiButton") then
				slot.Active = true
				slot.AutoButtonColor = false
				slot.Selectable = false
			end
			slot.LayoutOrder = optionIndex
			slot.Name = "Option_" .. tostring(optionIndex)

			local controls = getInfoOptionControls(slot)
			if controls and controls.label then
				controls.label.Text = tostring(option.Display or "")
			end

			bindPreview(slot, optionIndex)
			if controls and controls.button and controls.button ~= slot then
				controls.button.Active = true
				controls.button.AutoButtonColor = false
				controls.button.Selectable = false
				bindPreview(controls.button, optionIndex)
			end
		elseif slot and slot.Parent == self._infoOptionsContainer then
			slot.Visible = false
		end
	end

	applyPreview(self._infoPreviewOptionIndex or selectedIndex)
end

function module:_getSelectedOptionImage(rowData)
	if not rowData or not rowData.config then
		return nil
	end

	local config = rowData.config
	local options = config.Options
	if typeof(options) ~= "table" or #options == 0 then
		return nil
	end

	local selectedIndex = nil
	if self._infoPreviewSettingKey == rowData.key then
		selectedIndex = self._infoPreviewOptionIndex
	else
		local updater = self._multileUpdaters[rowData.key]
		if updater and updater.getIndex then
			selectedIndex = updater.getIndex()
		end
		if selectedIndex == nil then
			local storedValue = PlayerDataTable.get(rowData.category, rowData.key)
			selectedIndex = resolveOptionIndex(config, storedValue)
		end
	end

	if selectedIndex == nil then
		return nil
	end
	selectedIndex = clampIndex(toNumber(selectedIndex, 1), #options)

	local option = options[selectedIndex]
	if typeof(option) ~= "table" then
		return nil
	end

	return toAssetId(option.Image)
end

function module:_applyInfoMedia(rowData)
	local config = rowData and rowData.config or {}
	local isCrosshairSetting = rowData and rowData.category == "Crosshair"

	self:_stopImageCarousel()
	self:_stopVideo()
	self._currentInfoImages = nil
	self:_hideCrosshairPreview()

	if isCrosshairSetting and self._infoImageFrame then
		if self._infoVideoFrame then
			self._infoVideoFrame.Visible = false
		end
		self._infoImageFrame.Visible = true
		local crosshairCategory = SettingsConfig.Categories and SettingsConfig.Categories.Crosshair
		local crosshairColorSetting = crosshairCategory and crosshairCategory.Settings and crosshairCategory.Settings.CrosshairColor
		local crosshairImages = crosshairColorSetting and crosshairColorSetting.Image
		if typeof(crosshairImages) == "table" and #crosshairImages > 0 then
			self._currentInfoImages = crosshairImages
			self:_startImageCarousel(crosshairImages)
		elseif config.Image and #config.Image > 0 then
			self._currentInfoImages = config.Image
			self:_startImageCarousel(config.Image)
		end
		self:_updateCrosshairPreview()
		return
	end

	local selectedOptionImage = self:_getSelectedOptionImage(rowData)
	if selectedOptionImage and self._infoImageFrame then
		if self._infoVideoFrame then
			self._infoVideoFrame.Visible = false
		end
		self._infoImageFrame.Visible = true
		self._currentInfoImages = { selectedOptionImage }
		self:_startImageCarousel(self._currentInfoImages)
		return
	end

	if config.Video and self._infoVideoFrame then
		if self._infoImageFrame then
			self._infoImageFrame.Visible = false
		end
		self._infoVideoFrame.Visible = true
		self:_playVideo(config.Video)
		return
	end

	if config.Image and #config.Image > 0 and self._infoImageFrame then
		if self._infoVideoFrame then
			self._infoVideoFrame.Visible = false
		end
		self._infoImageFrame.Visible = true
		self._currentInfoImages = config.Image
		self:_startImageCarousel(config.Image)
		return
	end

	if self._infoVideoFrame then
		self._infoVideoFrame.Visible = false
	end
	if self._infoImageFrame then
		self._infoImageFrame.Visible = false
	end
end

function module:_updateInfoPanel(rowData)
	local config = rowData and rowData.config or {}
	local available = rowData and rowData.available

	if self._infoTitleLabel and self._infoTitleLabel:IsA("TextLabel") then
		self._infoTitleLabel.Text = config.Name or ""
	end

	if self._infoDescriptionLabel and self._infoDescriptionLabel:IsA("TextLabel") then
		local descriptionText = config.Description or ""
		if available == false then
			descriptionText = descriptionText
				.. "\n\nUnavailable on "
				.. tostring(self._deviceType)
				.. "."
		end
		self._infoDescriptionLabel.Text = descriptionText
	end

	local hasOptionList = rowData
		and available
		and typeof(config.Options) == "table"
		and #config.Options > 0

	if hasOptionList then
		self:_populateInfoOptions(rowData)
	else
		self:_clearInfoOptions()
	end

	self:_applyInfoMedia(rowData)
end

function module:_clearInfoPanel()
	self:_stopImageCarousel()
	self:_stopVideo()
	self._currentInfoImages = nil
	self:_clearInfoOptions()
	self:_hideCrosshairPreview()

	if self._infoTitleLabel and self._infoTitleLabel:IsA("TextLabel") then
		self._infoTitleLabel.Text = ""
	end
	if self._infoDescriptionLabel and self._infoDescriptionLabel:IsA("TextLabel") then
		self._infoDescriptionLabel.Text = ""
	end

	if self._infoVideoFrame then
		self._infoVideoFrame.Visible = false
	end
	if self._infoImageFrame then
		self._infoImageFrame.Visible = false
	end
end

function module:_startImageCarousel(images)
	if not self._infoCurrentImage or not self._infoNextImage then
		return
	end
	if #images == 0 then
		return
	end

	if self._infoImageCanvas then
		for _, child in ipairs(self._infoImageCanvas:GetChildren()) do
			if child.Name == "NextClone" and child:IsA("ImageLabel") then
				child:Destroy()
			end
		end
	end

	self._currentImageIndex = 1
	self._infoCurrentImage.Image = images[1]
	self._infoNextImage.Visible = false

	if #images <= 1 then
		return
	end

	local originalPosition = self._infoCurrentImage.Position
	local canvas = self._infoImageCanvas
	if not canvas then
		return
	end

	self._imageCarouselTask = task.spawn(function()
		while true do
			task.wait(TweenConfig.Durations.ImageCarouselInterval)

			if not self._buttonsActive then
				break
			end
			if not self._infoImageFrame or not self._infoImageFrame.Visible then
				break
			end

			self._currentImageIndex = (self._currentImageIndex % #images) + 1

			local nextClone = self._infoNextImage:Clone()
			nextClone.Name = "NextClone"
			nextClone.Visible = true
			nextClone.Image = images[self._currentImageIndex]
			nextClone.Position = UDim2.new(
				originalPosition.X.Scale,
				originalPosition.X.Offset,
				originalPosition.Y.Scale - 1,
				originalPosition.Y.Offset
			)
			nextClone.Parent = canvas

			local tween = TweenService:Create(nextClone, TweenConfig.create("ImageCarouselSwap"), {
				Position = originalPosition,
			})
			tween:Play()
			tween.Completed:Wait()

			self._infoCurrentImage.Image = images[self._currentImageIndex]
			self._infoCurrentImage.Position = originalPosition
			nextClone:Destroy()
		end
	end)
end

function module:_stopImageCarousel()
	if self._imageCarouselTask then
		task.cancel(self._imageCarouselTask)
		self._imageCarouselTask = nil
	end

	if self._infoImageCanvas then
		for _, child in ipairs(self._infoImageCanvas:GetChildren()) do
			if child.Name == "NextClone" and child:IsA("ImageLabel") then
				child:Destroy()
			end
		end
	end

	if self._infoNextImage then
		self._infoNextImage.Visible = false
	end
end

function module:_playVideo(videoId)
	if not self._infoVideoPlayer then
		return
	end
	if not self._infoVideoPlayer:IsA("VideoFrame") then
		return
	end

	self._infoVideoPlayer.Video = videoId
	self._infoVideoPlayer.Looped = true
	self._infoVideoPlayer.Playing = true
end

function module:_stopVideo()
	if not self._infoVideoPlayer then
		return
	end
	if self._infoVideoPlayer:IsA("VideoFrame") then
		self._infoVideoPlayer.Playing = false
	end
end

function module:_flashArrowRed(arrow)
	if not arrow or not arrow:IsA("ImageButton") then
		return
	end

	self._arrowOriginalColors = self._arrowOriginalColors or {}
	local arrowKey = arrow:GetFullName()
	if not self._arrowOriginalColors[arrowKey] then
		self._arrowOriginalColors[arrowKey] = arrow.ImageColor3
	end

	cancelTweenGroup("arrow_" .. arrowKey)
	local tweens = {}

	local colorTween = TweenService:Create(arrow, TweenConfig.create("Flash"), {
		ImageColor3 = TweenConfig.Values.FlashRedColor,
	})
	colorTween:Play()
	table.insert(tweens, colorTween)

	local uiScale = arrow:FindFirstChildWhichIsA("UIScale")
	if uiScale then
		local pressTween = TweenService:Create(
			uiScale,
			TweenInfo.new(TweenConfig.Durations.ArrowPress, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Scale = TweenConfig.Values.ArrowPressScale }
		)
		pressTween:Play()
		table.insert(tweens, pressTween)
	end

	colorTween.Completed:Once(function(state)
		if state ~= Enum.PlaybackState.Completed then
			return
		end

		local revertTween = TweenService:Create(arrow, TweenConfig.create("Flash"), {
			ImageColor3 = self._arrowOriginalColors[arrowKey],
		})
		revertTween:Play()

		if uiScale then
			local scaleRevert = TweenService:Create(
				uiScale,
				TweenInfo.new(TweenConfig.Durations.ArrowPress, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Scale = 1 }
			)
			scaleRevert:Play()
		end
	end)

	currentTweens["arrow_" .. arrowKey] = tweens
end

function module:_setupToggleRow(categoryKey, settingKey, config, row)
	local rowBody = row:FindFirstChild("Frame")
	local toggleContainer = rowBody and rowBody:FindFirstChild("Frame")
	local toggleButton = toggleContainer and toggleContainer:FindFirstChild("Frame")
	if toggleButton and not toggleButton:IsA("ImageButton") then
		toggleButton = row:FindFirstChildWhichIsA("ImageButton", true)
	end
	if not toggleButton or not toggleButton:IsA("GuiButton") then
		return
	end

	local knob = toggleButton:FindFirstChild("Frame")
	if knob and not knob:IsA("Frame") then
		knob = nil
	end

	local storedValue = PlayerDataTable.get(categoryKey, settingKey)
	local enabled, currentIndex = resolveToggleState(config, storedValue)

	local knobOffPosition = UDim2.new(0.1, 0, 0.122, 0)
	local knobOnPosition = UDim2.new(0.478, 0, 0.122, 0)

	local function updateDisplay(animate)
		local buttonColor = enabled and Color3.fromRGB(100, 255, 50) or Color3.fromRGB(255, 255, 255)
		local buttonTransparency = enabled and 0 or 0.35

		if animate then
			cancelTweenGroup("toggle_state_" .. settingKey)
			local tweens = {}

			local toggleTween = TweenService:Create(toggleButton, TweenConfig.create("TabSelect"), {
				BackgroundColor3 = buttonColor,
				BackgroundTransparency = buttonTransparency,
			})
			toggleTween:Play()
			table.insert(tweens, toggleTween)

			if knob and knobOffPosition and knobOnPosition then
				local knobTween = TweenService:Create(knob, TweenConfig.create("TabSelect"), {
					Position = enabled and knobOnPosition or knobOffPosition,
				})
				knobTween:Play()
				table.insert(tweens, knobTween)
			end

			currentTweens["toggle_state_" .. settingKey] = tweens
			return
		end

		toggleButton.BackgroundColor3 = buttonColor
		toggleButton.BackgroundTransparency = buttonTransparency
		if knob then
			knob.Position = enabled and knobOnPosition or knobOffPosition
		end
	end

	local function setValue(nextEnabled, save)
		enabled = nextEnabled

		local options = config.Options
		if typeof(options) == "table" and #options > 0 then
			currentIndex = findBooleanOptionIndex(options, enabled)
				or (enabled and 1 or math.min(2, #options))
			if save then
				PlayerDataTable.set(categoryKey, settingKey, currentIndex)
			end
		elseif save then
			PlayerDataTable.set(categoryKey, settingKey, enabled)
		end

		updateDisplay(save)

		if self._selectedSetting == settingKey then
			local rowData = self:_findRowData(settingKey)
			if rowData then
				self:_updateInfoPanel(rowData)
			end
		end

		if save and categoryKey == "Crosshair" and settingKey == "AdvancedStyleSettings" then
			self:_selectTab(self._currentTab or DEFAULT_TAB, true, settingKey)
		end
	end

	local function setIndex(nextIndex, save)
		local options = config.Options
		if typeof(options) ~= "table" or #options == 0 then
			return
		end

		local clampedIndex = clampIndex(nextIndex, #options)
		currentIndex = clampedIndex

		local option = options[clampedIndex]
		local nextEnabled = enabled
		if typeof(option) == "table" and typeof(option.Value) == "boolean" then
			nextEnabled = option.Value
		else
			nextEnabled = clampedIndex == 1
		end

		setValue(nextEnabled, save)
	end

	updateDisplay(false)

	if typeof(config.Options) == "table" and #config.Options > 0 then
		self._multileUpdaters[settingKey] = {
			setIndex = setIndex,
			getIndex = function()
				return currentIndex
			end,
			updateDisplay = function()
				updateDisplay(false)
			end,
		}
	end

	self._connections:track(toggleButton, "Activated", function()
		if not self._buttonsActive then
			return
		end
		self:_selectSetting(settingKey)
		setValue(not enabled, true)
	end, "settingRows")
end

function module:_setupMultileRow(categoryKey, settingKey, config, row)
	local options = config.Options
	if typeof(options) ~= "table" or #options == 0 then
		return
	end

	local controls = getMultileControls(row)
	if not controls then
		return
	end

	local optionDots = {}
	if controls.dotsContainer and controls.dotTemplate then
		for _, child in ipairs(controls.dotsContainer:GetChildren()) do
			if child:IsA("Frame") and child ~= controls.dotTemplate then
				child:Destroy()
			end
		end
		controls.dotTemplate.Visible = false

		for optionIndex, option in ipairs(options) do
			local dotFrame = controls.dotTemplate:Clone()
			dotFrame.Name = "Dot_" .. tostring(optionIndex)
			dotFrame.LayoutOrder = optionIndex
			dotFrame.Visible = true
			dotFrame.Parent = controls.dotsContainer

			local dotImage = dotFrame:FindFirstChild("ImageLabel", true)
			optionDots[optionIndex] = {
				frame = dotFrame,
				image = dotImage and dotImage:IsA("ImageButton") and dotImage or nil,
				option = option,
			}
		end
	end

	local savedValue = PlayerDataTable.get(categoryKey, settingKey)
	local currentIndex = clampIndex(toNumber(savedValue, config.Default or 1), #options)
	if settingKey == "Brightness" and type(savedValue) == "number" and savedValue > #options then
		local migratedIndex = clampIndex(mapLegacyBrightnessPresetIndex(savedValue), #options)
		currentIndex = migratedIndex
		PlayerDataTable.set(categoryKey, settingKey, migratedIndex)
	end

	local function updateDisplay()
		local selectedOption = options[currentIndex]
		local accentColor = selectedOption and selectedOption.Color

		if controls.valueLabel then
			controls.valueLabel.Text = tostring(selectedOption and selectedOption.Display or "")
			controls.valueLabel.TextColor3 = typeof(accentColor) == "Color3" and accentColor or Color3.fromRGB(255, 255, 255)
		end

		for optionIndex, dotData in ipairs(optionDots) do
			local selected = optionIndex == currentIndex
			local optionColor = typeof(dotData.option.Color) == "Color3" and dotData.option.Color or Color3.fromRGB(255, 255, 255)

			if dotData.frame then
				dotData.frame.BackgroundColor3 = optionColor
				dotData.frame.BackgroundTransparency = selected and 0 or 0.8
			end

			if dotData.image then
				dotData.image.ImageColor3 = optionColor
				dotData.image.ImageTransparency = selected and 0 or 1
			end
		end
	end

	local function setIndex(nextIndex, save, limitArrow)
		local clamped = clampIndex(nextIndex, #options)
		if clamped == currentIndex then
			if limitArrow then
				self:_flashArrowRed(limitArrow)
			end
			return
		end

		currentIndex = clamped
		if save then
			PlayerDataTable.set(categoryKey, settingKey, currentIndex)
		end
		updateDisplay()

		if self._selectedSetting == settingKey then
			local rowData = self:_findRowData(settingKey)
			if rowData then
				self:_updateInfoPanel(rowData)
			end
		end
	end

	local function bindDotSelect(target, optionIndex)
		if not target then
			return
		end

		self._connections:track(target, "InputBegan", function(input)
			if not self._buttonsActive then
				return
			end
			if not isPointerInput(input) then
				return
			end
			self:_selectSetting(settingKey)
			setIndex(optionIndex, true)
		end, "settingRows")
	end

	for optionIndex, dotData in ipairs(optionDots) do
		bindDotSelect(dotData.frame, optionIndex)
		bindDotSelect(dotData.image, optionIndex)
	end

	if controls.leftArrow and controls.leftArrow:IsA("GuiButton") then
		self._connections:track(controls.leftArrow, "Activated", function()
			if not self._buttonsActive then
				return
			end
			self:_selectSetting(settingKey)
			setIndex(currentIndex - 1, true, controls.leftArrow)
		end, "settingRows")
	end

	if controls.rightArrow and controls.rightArrow:IsA("GuiButton") then
		self._connections:track(controls.rightArrow, "Activated", function()
			if not self._buttonsActive then
				return
			end
			self:_selectSetting(settingKey)
			setIndex(currentIndex + 1, true, controls.rightArrow)
		end, "settingRows")
	end

	self._multileUpdaters[settingKey] = {
		setIndex = setIndex,
		getIndex = function()
			return currentIndex
		end,
		updateDisplay = updateDisplay,
	}

	updateDisplay()
end

function module:_setupSliderRow(categoryKey, settingKey, config, row)
	local slider = config.Slider
	if not slider then
		return
	end

	local leftButton = row:FindFirstChild("Left", true)
	local rightButton = row:FindFirstChild("Right", true)

	local holder = row:FindFirstChild("HOLDER", true)
	if holder and holder:IsA("GuiObject") then
		holder.Active = true
	end

	local drag = holder and holder:FindFirstChild("Drag")
	local dragDetector = drag and drag:FindFirstChildWhichIsA("UIDragDetector")
	local dragLabel = drag and drag:FindFirstChildWhichIsA("TextLabel", true)
	local fillFrame = nil
	if holder then
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("Frame") and child.Name == "Frame" and child:FindFirstChild("UIGradient") then
				fillFrame = child
				break
			end
		end
	end
	if not fillFrame and holder then
		fillFrame = holder:FindFirstChild("Frame")
	end
	local fillGradient = fillFrame and fillFrame:FindFirstChild("UIGradient")

	local minValue = slider.Min
	local maxValue = slider.Max
	local stepValue = slider.Step or 1
	local minPadding = TweenConfig.Values.SliderMinPadding or 0
	local maxPadding = TweenConfig.Values.SliderMaxPadding or 0
	local gradientOffset = TweenConfig.Values.SliderGradientOffset or 1

	local currentValue = PlayerDataTable.get(categoryKey, settingKey)
	currentValue = toNumber(currentValue, slider.Default or minValue)
	currentValue = math.clamp(snapToStep(currentValue, minValue, stepValue), minValue, maxValue)

	local range = maxValue - minValue
	local handleWidthScale = 0

	local function getDecimalPlaces(step)
		local stepText = tostring(step)
		local decimalPart = stepText:match("%.(%d+)")
		return decimalPart and #decimalPart or 0
	end

	local function formatValue(value)
		local decimals = getDecimalPlaces(stepValue)
		if decimals <= 0 then
			return tostring(math.floor(value + 0.5))
		end
		local formatted = string.format("%." .. tostring(decimals) .. "f", value)
		formatted = formatted:gsub("%.?0+$", "")
		if formatted == "-0" then
			formatted = "0"
		end
		return formatted
	end

	local function getMinPos()
		return handleWidthScale + minPadding
	end

	local function getMaxPos()
		return 1 - maxPadding
	end

	local function normalized(value)
		if range <= 0 then
			return 0
		end
		return math.clamp((value - minValue) / range, 0, 1)
	end

	local function valueToPosition(value)
		local percent = normalized(value)
		local minPos = getMinPos()
		local maxPos = getMaxPos()
		if maxPos <= minPos then
			return minPos
		end
		return minPos + percent * (maxPos - minPos)
	end

	local function positionToValue(position)
		local minPos = getMinPos()
		local maxPos = getMaxPos()
		if maxPos <= minPos then
			return minValue
		end
		local normalizedPos = (position - minPos) / (maxPos - minPos)
		normalizedPos = math.clamp(normalizedPos, 0, 1)
		return minValue + normalizedPos * range
	end

	local function updateDisplay(value)
		if dragLabel then
			dragLabel.Text = formatValue(value)
		end

		if drag then
			local position = valueToPosition(value)
			drag.Position = UDim2.new(position, 0, drag.Position.Y.Scale, drag.Position.Y.Offset)
		end

		if fillGradient and fillGradient:IsA("UIGradient") then
			local percent = normalized(value)
			fillGradient.Offset = Vector2.new((percent - 1) + gradientOffset, 0)
		end
	end

	local function refreshSelectedInfo()
		if self._selectedSetting ~= settingKey then
			return
		end
		local rowData = self:_findRowData(settingKey)
		if rowData then
			self:_updateInfoPanel(rowData)
		end
	end

	local function setValue(nextValue, save, limitArrow)
		local snapped = snapToStep(nextValue, minValue, stepValue)
		local clamped = math.clamp(snapped, minValue, maxValue)
		if clamped == currentValue then
			if limitArrow then
				self:_flashArrowRed(limitArrow)
			end
			return
		end
		currentValue = clamped
		if save then
			PlayerDataTable.set(categoryKey, settingKey, currentValue)
		end
		updateDisplay(currentValue)
		refreshSelectedInfo()
	end

	local function setFromAbsoluteX(absX, save)
		if not holder or not holder:IsA("GuiObject") then
			return
		end

		local holderAbsSize = holder.AbsoluteSize.X
		if holderAbsSize <= 0 then
			return
		end

		local dragWidth = drag and drag.AbsoluteSize.X or 0
		if handleWidthScale == 0 and dragWidth > 0 then
			handleWidthScale = dragWidth / holderAbsSize
		end

		local holderAbsPos = holder.AbsolutePosition.X
		local relativeX = (absX - holderAbsPos) / holderAbsSize
		relativeX = math.clamp(relativeX, getMinPos(), getMaxPos())

		local rawValue = positionToValue(relativeX)
		local snappedValue = snapToStep(rawValue, minValue, stepValue)
		local nextValue = math.clamp(snappedValue, minValue, maxValue)
		local changed = nextValue ~= currentValue
		currentValue = nextValue
		updateDisplay(currentValue)

		if save and changed then
			PlayerDataTable.set(categoryKey, settingKey, currentValue)
		end
		if changed then
			refreshSelectedInfo()
		end
	end

	if drag and holder then
		task.defer(function()
			if not drag.Parent or not holder.Parent then
				return
			end
			if drag.AbsoluteSize.X > 0 and holder.AbsoluteSize.X > 0 then
				handleWidthScale = drag.AbsoluteSize.X / holder.AbsoluteSize.X
			end
			updateDisplay(currentValue)
		end)
	else
		updateDisplay(currentValue)
	end

	if leftButton and leftButton:IsA("GuiButton") then
		self._connections:track(leftButton, "Activated", function()
			if not self._buttonsActive then
				return
			end
			self:_selectSetting(settingKey)
			setValue(currentValue - stepValue, true, leftButton)
		end, "settingRows")
	end

	if rightButton and rightButton:IsA("GuiButton") then
		self._connections:track(rightButton, "Activated", function()
			if not self._buttonsActive then
				return
			end
			self:_selectSetting(settingKey)
			setValue(currentValue + stepValue, true, rightButton)
		end, "settingRows")
	end

	if holder and holder:IsA("GuiObject") then
		self._connections:track(holder, "InputBegan", function(input)
			if not self._buttonsActive then
				return
			end
			if not isPointerInput(input) then
				return
			end
			self:_selectSetting(settingKey)
			setFromAbsoluteX(input.Position.X, true)
		end, "settingRows")
	end

	if dragDetector and holder and drag then
		self._connections:track(dragDetector, "DragStart", function()
			if not self._buttonsActive then
				return
			end
			self:_selectSetting(settingKey)
		end, "settingRows")

		self._connections:track(dragDetector, "DragContinue", function()
			if not self._buttonsActive then
				return
			end

			local holderAbsSize = holder.AbsoluteSize.X
			if holderAbsSize <= 0 then
				return
			end

			local dragWidth = drag.AbsoluteSize.X
			if dragWidth <= 0 then
				return
			end

			if handleWidthScale == 0 then
				handleWidthScale = dragWidth / holderAbsSize
			end

			local dragAbsPos = drag.AbsolutePosition.X
			local dragRightEdge = dragAbsPos + dragWidth
			setFromAbsoluteX(dragRightEdge, true)
		end, "settingRows")

		self._connections:track(dragDetector, "DragEnd", function()
			PlayerDataTable.set(categoryKey, settingKey, currentValue)
		end, "settingRows")
	end
end

function module:_setupKeybindRow(settingKey, row)
	local slots = {
		{ key = "PC", names = { "PC" } },
		{ key = "PC2", names = { "PC2" } },
		{ key = "Console", names = { "Console", "CONSOLE" } },
	}
	local slotRenderers = {}

	local function refresh()
		local binds = PlayerDataTable.get("Controls", settingKey)
		if typeof(binds) ~= "table" then
			binds = {}
		end

		for slot, renderer in pairs(slotRenderers) do
			if renderer.label then
				renderer.label.Text = keyCodeDisplay(binds[slot])
			end
		end
	end

	for _, slotData in ipairs(slots) do
		local slotKey = slotData.key
		local slotTarget = nil
		for _, slotName in ipairs(slotData.names) do
			slotTarget = row:FindFirstChild(slotName, true)
			if slotTarget then
				break
			end
		end
		if not slotTarget then
			continue
		end

		local label = slotTarget:FindFirstChildWhichIsA("TextLabel", true)
		slotRenderers[slotKey] = {
			label = label,
		}

		if slotTarget:IsA("GuiButton") then
			self._connections:track(slotTarget, "Activated", function()
				if not self._buttonsActive then
					return
				end
				self:_selectSetting(settingKey)
				self:_startAwaitingKeybind(settingKey, slotKey, label)
			end, "settingRows")
		else
			self._connections:track(slotTarget, "InputBegan", function(input)
				if not isPointerInput(input) then
					return
				end
				if not self._buttonsActive then
					return
				end
				self:_selectSetting(settingKey)
				self:_startAwaitingKeybind(settingKey, slotKey, label)
			end, "settingRows")
		end
	end

	self._keybindUpdaters[settingKey] = refresh
	refresh()
end

function module:_refreshKeybindRows()
	for _, updater in pairs(self._keybindUpdaters) do
		updater()
	end
end

function module:_applyKeybind(settingKey, slot, keyCode)
	if keyCode then
		local conflicts = PlayerDataTable.getConflicts(keyCode, settingKey, slot)
		for _, conflict in ipairs(conflicts) do
			PlayerDataTable.setBind(conflict.settingKey, conflict.slot, nil)
		end
	end

	PlayerDataTable.setBind(settingKey, slot, keyCode)
	self:_refreshKeybindRows()
end

function module:_startAwaitingKeybind(settingKey, slot, label)
	self:_stopAwaitingKeybind(true)

	self._awaitingKeybind = {
		settingKey = settingKey,
		slot = slot,
		label = label,
		previousText = label and label.Text or nil,
	}

	if label then
		label.Text = "..."
	end

	self._connections:track(UserInputService, "InputBegan", function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if not self._awaitingKeybind then
			return
		end
		if not isBindableKeyInput(input) then
			return
		end

		local keyCode = input.KeyCode
		if keyCode == Enum.KeyCode.Unknown then
			return
		end

		if keyCode == Enum.KeyCode.Escape then
			self:_stopAwaitingKeybind(true)
			return
		end

		local targetKeyCode = keyCode
		if keyCode == Enum.KeyCode.Delete or keyCode == Enum.KeyCode.Backspace then
			targetKeyCode = nil
		elseif SettingsConfig.isKeyBlocked(keyCode) then
			return
		end

		self:_applyKeybind(self._awaitingKeybind.settingKey, self._awaitingKeybind.slot, targetKeyCode)
		self:_stopAwaitingKeybind(false)
	end, "keybindCapture")
end

function module:_stopAwaitingKeybind(cancelled)
	if self._awaitingKeybind and cancelled then
		local label = self._awaitingKeybind.label
		if label and self._awaitingKeybind.previousText then
			label.Text = self._awaitingKeybind.previousText
		end
	end

	self._awaitingKeybind = nil
	self._connections:cleanupGroup("keybindCapture")
	self:_refreshKeybindRows()
end

function module:_setupBackButton()
	local holder = self._backHolder
	if not holder then
		return
	end

	local function onBackRequested()
		if not self._buttonsActive then
			return
		end
		self:_close()
	end

	local function trackBackTarget(target)
		if target:IsA("GuiButton") then
			self._connections:track(target, "Activated", onBackRequested, "back")
		elseif target:IsA("GuiObject") then
			target.Active = true
			self._connections:track(target, "InputBegan", function(input)
				if not isPointerInput(input) then
					return
				end
				onBackRequested()
			end, "back")
		end
	end

	trackBackTarget(holder)

	if self._backButton and self._backButton ~= holder then
		trackBackTarget(self._backButton)
	end

	for _, descendant in ipairs(holder:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			trackBackTarget(descendant)
		end
	end
end

function module:_close()
	self._export:hide("_Settings")
end

function module:_setButtonsActive(active)
	self._buttonsActive = active
end

function module:transitionIn()
	self._ui.Visible = true
	self:_hideOtherUiWhileActive()
	self:_setButtonsActive(false)

	local bg = self._bgCanvas
	local settings = self._settingsCanvas
	local topBar = self._topBar
	local infoPanel = self._infoPanel
	local backHolder = self._backHolder

	if infoPanel then
		infoPanel.Visible = true
	end

	if bg then
		bg.GroupTransparency = 1
	end

	if settings then
		settings.GroupTransparency = 1
		if self._originals.settingsPosition then
			local orig = self._originals.settingsPosition
			settings.Position = UDim2.new(
				orig.X.Scale + TweenConfig.Values.SideSlideOffset,
				orig.X.Offset,
				orig.Y.Scale,
				orig.Y.Offset
			)
		end
	end

	if infoPanel and infoPanel:IsA("CanvasGroup") then
		infoPanel.GroupTransparency = 1
	end

	if infoPanel and infoPanel:IsA("GuiObject") and self._originals.infoPosition then
		local orig = self._originals.infoPosition
		infoPanel.Position = UDim2.new(
			orig.X.Scale - TweenConfig.Values.InfoSlideOffset,
			orig.X.Offset,
			orig.Y.Scale,
			orig.Y.Offset
		)
	end

	if backHolder and self._originals.backHolderPosition then
		local orig = self._originals.backHolderPosition
		backHolder.Position = UDim2.new(
			orig.X.Scale - TweenConfig.Values.SideSlideOffset,
			orig.X.Offset,
			orig.Y.Scale,
			orig.Y.Offset
		)
	end

	if topBar and self._originals.topBarPosition then
		local orig = self._originals.topBarPosition
		topBar.Position = UDim2.new(
			orig.X.Scale,
			orig.X.Offset,
			orig.Y.Scale - TweenConfig.Values.TopBarSlideOffset,
			orig.Y.Offset
		)
	end

	cancelTweenGroup("show")
	cancelTweenGroup("hide")

	local tweenInfo = TweenConfig.create("Show")
	local topBarTweenInfo = TweenConfig.create("TopBarShow")
	local tweens = {}

	if bg then
		local tween = TweenService:Create(bg, tweenInfo, {
			GroupTransparency = TweenConfig.Values.BGVisibleTransparency,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	if settings then
		local transparencyTween = TweenService:Create(settings, tweenInfo, {
			GroupTransparency = self._originals.settingsTransparency,
		})
		local positionTween = TweenService:Create(settings, tweenInfo, {
			Position = self._originals.settingsPosition,
		})
		transparencyTween:Play()
		positionTween:Play()
		table.insert(tweens, transparencyTween)
		table.insert(tweens, positionTween)
	end

	if infoPanel and infoPanel:IsA("CanvasGroup") then
		local infoTween = TweenService:Create(infoPanel, tweenInfo, {
			GroupTransparency = self._originals.infoTransparency,
		})
		infoTween:Play()
		table.insert(tweens, infoTween)
	end

	if infoPanel and infoPanel:IsA("GuiObject") and self._originals.infoPosition then
		local infoPositionTween = TweenService:Create(infoPanel, tweenInfo, {
			Position = self._originals.infoPosition,
		})
		infoPositionTween:Play()
		table.insert(tweens, infoPositionTween)
	end

	if backHolder and self._originals.backHolderPosition then
		local backTween = TweenService:Create(backHolder, tweenInfo, {
			Position = self._originals.backHolderPosition,
		})
		backTween:Play()
		table.insert(tweens, backTween)
	end

	if topBar and self._originals.topBarPosition then
		local topBarTween = TweenService:Create(topBar, topBarTweenInfo, {
			Position = self._originals.topBarPosition,
		})
		topBarTween:Play()
		table.insert(tweens, topBarTween)
	end

	currentTweens.show = tweens

	local finalTween = tweens[#tweens]
	if finalTween then
		finalTween.Completed:Once(function(state)
			if state ~= Enum.PlaybackState.Completed then
				return
			end
			self:_setButtonsActive(true)
		end)
	else
		self:_setButtonsActive(true)
	end

	self:_init()
end

function module:transitionOut()
	self:_setButtonsActive(false)
	self._export:setModuleState(nil, false)

	self:_stopAwaitingKeybind(true)
	self:_stopImageCarousel()
	self:_stopVideo()

	local bg = self._bgCanvas
	local settings = self._settingsCanvas
	local topBar = self._topBar
	local infoPanel = self._infoPanel
	local backHolder = self._backHolder

	cancelTweenGroup("show")
	cancelTweenGroup("hide")

	local tweenInfo = TweenConfig.create("Hide")
	local topBarTweenInfo = TweenConfig.create("TopBarHide")
	local tweens = {}

	if bg then
		local tween = TweenService:Create(bg, tweenInfo, { GroupTransparency = 1 })
		tween:Play()
		table.insert(tweens, tween)
	end

	if settings and self._originals.settingsPosition then
		local orig = self._originals.settingsPosition
		local positionTween = TweenService:Create(settings, tweenInfo, {
			Position = UDim2.new(
				orig.X.Scale + TweenConfig.Values.SideSlideOffset,
				orig.X.Offset,
				orig.Y.Scale,
				orig.Y.Offset
			),
		})
		local transparencyTween = TweenService:Create(settings, tweenInfo, { GroupTransparency = 1 })
		positionTween:Play()
		transparencyTween:Play()
		table.insert(tweens, positionTween)
		table.insert(tweens, transparencyTween)
	end

	if infoPanel and infoPanel:IsA("CanvasGroup") then
		local infoTween = TweenService:Create(infoPanel, tweenInfo, {
			GroupTransparency = 1,
		})
		infoTween:Play()
		table.insert(tweens, infoTween)
	end

	if infoPanel and infoPanel:IsA("GuiObject") and self._originals.infoPosition then
		local orig = self._originals.infoPosition
		local infoPositionTween = TweenService:Create(infoPanel, tweenInfo, {
			Position = UDim2.new(
				orig.X.Scale - TweenConfig.Values.InfoSlideOffset,
				orig.X.Offset,
				orig.Y.Scale,
				orig.Y.Offset
			),
		})
		infoPositionTween:Play()
		table.insert(tweens, infoPositionTween)
	end

	if backHolder and self._originals.backHolderPosition then
		local orig = self._originals.backHolderPosition
		local backTween = TweenService:Create(backHolder, tweenInfo, {
			Position = UDim2.new(
				orig.X.Scale - TweenConfig.Values.SideSlideOffset,
				orig.X.Offset,
				orig.Y.Scale,
				orig.Y.Offset
			),
		})
		backTween:Play()
		table.insert(tweens, backTween)
	end

	if topBar and self._originals.topBarPosition then
		local orig = self._originals.topBarPosition
		local topBarTween = TweenService:Create(topBar, topBarTweenInfo, {
			Position = UDim2.new(
				orig.X.Scale,
				orig.X.Offset,
				orig.Y.Scale - TweenConfig.Values.TopBarSlideOffset,
				orig.Y.Offset
			),
		})
		topBarTween:Play()
		table.insert(tweens, topBarTween)
	end

	currentTweens.hide = tweens

	local finalTween = tweens[#tweens]
	if finalTween then
		finalTween.Completed:Wait()
	end

	self._ui.Visible = false
	if infoPanel then
		infoPanel.Visible = false
	end
	self:_clearSettings()
	self:_clearInfoPanel()
	self:_restoreUiAfterClose()
end

function module:show()
	self:transitionIn()
end

function module:hide()
	self:transitionOut()
	return true
end

function module:_cleanup()
	self:_clearSettings()
	self:_clearInfoPanel()
	self:_restoreUiAfterClose()

	self._connections:cleanupGroup("topbar")
	self._connections:cleanupGroup("back")

	for _, tweens in pairs(currentTweens) do
		for _, tween in ipairs(tweens) do
			tween:Cancel()
		end
	end
	table.clear(currentTweens)

	self._initialized = false
	self._buttonsActive = false
	self._currentTab = nil
	self._selectedSetting = nil
	self:_resetAllTabVisuals()

	if self._bgCanvas then
		self._bgCanvas.GroupTransparency = self._originals.bgTransparency
	end
	if self._settingsCanvas then
		self._settingsCanvas.GroupTransparency = self._originals.settingsTransparency
		if self._originals.settingsPosition then
			self._settingsCanvas.Position = self._originals.settingsPosition
		end
	end
	if self._topBar and self._originals.topBarPosition then
		self._topBar.Position = self._originals.topBarPosition
	end
	if self._infoPanel and self._originals.infoPosition then
		self._infoPanel.Position = self._originals.infoPosition
		self._infoPanel.Visible = false
	end
	if self._infoPanel and self._infoPanel:IsA("CanvasGroup") then
		self._infoPanel.GroupTransparency = self._originals.infoTransparency
	end
	if self._backHolder and self._originals.backHolderPosition then
		self._backHolder.Position = self._originals.backHolderPosition
	end
end

return module
