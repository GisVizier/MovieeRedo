local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local LoadoutConfig = require(Configs.LoadoutConfig)
local KitConfig = require(Configs.KitConfig)
local ActionsIcon = require(Configs.ActionsIcon)
local SharedConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Config"))
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
local TweenConfig = require(script.TweenConfig)

local module = {}
module.__index = module

type HealthBar = CanvasGroup & {
	Image: ImageLabel & {
		UIGradient: UIGradient,
	},
	White: ImageLabel & {
		UIGradient: UIGradient,
	},
	Bg: ImageLabel,
}

type UltBar = CanvasGroup & {
	Image: ImageLabel & {
		UIGradient: UIGradient,
	},
	White: ImageLabel & {
		UIGradient: UIGradient,
	},
	Bg: ImageLabel,
}

type HealthBarHolder = CanvasGroup & {
	HealthBar: HealthBar,
	Text: TextLabel,
	SideBar: ImageLabel,
	UnderHealthBg: ImageLabel,
}

type UltBarHolder = CanvasGroup & {
	Bg: ImageLabel,
	Bar: UltBar,
}

type BarHolders = CanvasGroup & {
	HealthBarHolder: HealthBarHolder,
	UltBarHolder: UltBarHolder,
}

type PlayerHolder = CanvasGroup & {
	Holder: CanvasGroup & {
		RotHolder: CanvasGroup & {
			PlayerImage: ImageLabel,
		},
	},
	Bg: ImageLabel,
}

type UI = Frame

local SLOT_ORDER = { "Kit", "Primary", "Secondary", "Melee" }

local HEALTH_COLORS = {
	{ threshold = 0.6, color = Color3.fromRGB(70, 250, 126) },
	{ threshold = 0.35, color = Color3.fromRGB(250, 220, 70) },
	{ threshold = 0.2, color = Color3.fromRGB(250, 150, 50) },
	{ threshold = 0, color = Color3.fromRGB(250, 70, 70) },
}

local HEALTH_SHAKE_STEPS = 7
local HEALTH_SHAKE_X_RANGE = 10
local HEALTH_SHAKE_Y_RANGE = 6
local HEALTH_SHAKE_TWEEN = TweenInfo.new(0.025, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local healthShakeRandom = Random.new()

local ROUND_SHAKE_STEPS = 5
local ROUND_SHAKE_X_RANGE = 4
local ROUND_SHAKE_Y_RANGE = 3
local ROUND_SHAKE_TWEEN_INFO = TweenInfo.new(0.04, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local roundShakeRandom = Random.new()

local WIN_COLOR = Color3.fromRGB(86, 198, 55)
local LOSE_COLOR = Color3.fromRGB(198, 55, 55)
local DRAW_COLOR = Color3.fromRGB(150, 150, 150)
local ROUND_START_BAR_COLOR = Color3.fromRGB(0, 0, 0)
local STORM_BAR_COLOR = Color3.fromRGB(184, 43, 255)
local STORM_TEXT_COLOR = Color3.fromRGB(229, 25, 29)
local TIMER_FLASH_COLOR = Color3.fromRGB(255, 60, 60)
local TIMER_NORMAL_COLOR = Color3.fromRGB(255, 255, 255)

local currentTweens = {}
local CONTROLLER_INPUT_TYPES = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
}
local KEY_LABEL_OVERRIDES = {
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "TRIANGLE",
	[Enum.KeyCode.ButtonL1] = "L1",
	[Enum.KeyCode.ButtonR1] = "R1",
	[Enum.KeyCode.ButtonL2] = "L2",
	[Enum.KeyCode.ButtonR2] = "R2",
	[Enum.KeyCode.ButtonL3] = "L3",
	[Enum.KeyCode.ButtonR3] = "R3",
	[Enum.KeyCode.DPadUp] = "D-PAD UP",
	[Enum.KeyCode.DPadDown] = "D-PAD DOWN",
	[Enum.KeyCode.DPadLeft] = "D-PAD LEFT",
	[Enum.KeyCode.DPadRight] = "D-PAD RIGHT",
}
local USER_INPUT_LABEL_OVERRIDES = {
	[Enum.UserInputType.MouseButton1] = "M1",
	[Enum.UserInputType.MouseButton2] = "M2",
	[Enum.UserInputType.MouseButton3] = "M3",
}
local ACTION_KEY_ALIASES = {
	Ability = { "Ability", "ControllerAbility" },
	QuickMelee = { "QuickMelee", "ControllerQuickMelee" },
	Ultimate = { "Ultimate", "ControllerUltimate" },
	Reload = { "Reload", "ControllerReload" },
	Fire = { "Fire", "ControllerFire" },
	Special = { "Special", "ControllerSpecial" },
}
local BUMPER_BIND_ACTIONS = {
	Lb = "CycleWeaponLeft",
	Rb = "CycleWeaponRight",
}
local BUMPER_FALLBACK_BINDS = {
	Lb = Enum.KeyCode.ButtonL1,
	Rb = Enum.KeyCode.ButtonR1,
}
local COUNTER_DISCONNECTED_COLOR = Color3.fromRGB(0, 0, 0)
local COUNTER_DEAD_COLOR = Color3.fromRGB(90, 90, 90)
local InputIcons = nil
local InputIconsMode = "none"
local inputIconCache = {}

do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local util = shared and shared:FindFirstChild("Util")
	local inputIconsModule = util and util:FindFirstChild("InputIcons")
	if inputIconsModule then
		local ok, resolver = pcall(require, inputIconsModule)
		if ok and type(resolver) == "function" then
			InputIcons = resolver
			InputIconsMode = "function"
		elseif ok and type(resolver) == "table" then
			InputIcons = resolver
			InputIconsMode = "table"
		end
	end
end

local function cancelTweens(key)
	if currentTweens[key] then
		for _, tween in currentTweens[key] do
			tween:Cancel()
		end
		currentTweens[key] = nil
	end
end

local function getHealthColor(percent)
	for _, data in HEALTH_COLORS do
		if percent >= data.threshold then
			return data.color
		end
	end
	return HEALTH_COLORS[#HEALTH_COLORS].color
end

local function calculateGradientOffset(percent)
	return Vector2.new(percent, 0.5)
end

local function withOffset(position: UDim2, xOffset: number, yOffset: number): UDim2
	return UDim2.new(position.X.Scale, position.X.Offset + xOffset, position.Y.Scale, position.Y.Offset + yOffset)
end

local function getRarityColor(rarityName)
	return LoadoutConfig.getRarityColor(rarityName)
end

local function getCounterUserId(entry)
	local entryType = typeof(entry)
	if entryType == "Instance" and entry:IsA("Player") then
		return entry.UserId
	end

	if type(entry) == "number" then
		return entry
	end

	if type(entry) == "string" then
		return tonumber(entry)
	end

	if type(entry) ~= "table" then
		return nil
	end

	local raw = entry.userId or entry.UserId or entry.id or entry.Id
	local rawType = typeof(raw)
	if rawType == "Instance" and raw:IsA("Player") then
		return raw.UserId
	end
	if type(raw) == "number" then
		return raw
	end
	if type(raw) == "string" then
		return tonumber(raw)
	end

	return nil
end

local function getScoreFromLabel(label)
	if not label or not label:IsA("TextLabel") then
		return 0
	end

	local score = tonumber(label.Text)
	if score then
		return score
	end

	local numericText = string.match(label.Text, "%d+")
	if numericText then
		return tonumber(numericText) or 0
	end

	return 0
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

local function normalizeBindValue(bindValue)
	local function enumLookup(enumType, memberName)
		if type(memberName) ~= "string" or memberName == "" then
			return nil
		end

		local ok, value = pcall(function()
			return enumType[memberName]
		end)
		if ok then
			return value
		end
		return nil
	end

	if typeof(bindValue) == "EnumItem" then
		return bindValue
	end

	if type(bindValue) == "string" then
		local memberName = bindValue:match("Enum%.[%w_]+%.([%w_]+)$") or bindValue
		local asKeyCode = enumLookup(Enum.KeyCode, memberName)
		if asKeyCode then
			return asKeyCode
		end
		local asInputType = enumLookup(Enum.UserInputType, memberName)
		if asInputType then
			return asInputType
		end
		return bindValue
	end

	if type(bindValue) == "table" and type(bindValue.Name) == "string" then
		local memberName = bindValue.Name:match("Enum%.[%w_]+%.([%w_]+)$") or bindValue.Name
		local asKeyCode = enumLookup(Enum.KeyCode, memberName)
		if asKeyCode then
			return asKeyCode
		end
		local asInputType = enumLookup(Enum.UserInputType, memberName)
		if asInputType then
			return asInputType
		end
	end

	return bindValue
end

local function getBindCacheKey(bindValue)
	local normalized = normalizeBindValue(bindValue)
	local valueType = typeof(normalized)
	if valueType == "EnumItem" then
		return "enum:" .. tostring(normalized), normalized
	end
	if valueType == "string" then
		return "string:" .. normalized, normalized
	end
	return "other:" .. tostring(normalized), normalized
end

local function getInputIconAsset(bindValue)
	if not InputIcons or bindValue == nil then
		return nil
	end

	local cacheKey, normalized = getBindCacheKey(bindValue)
	local cached = inputIconCache[cacheKey]
	if cached ~= nil then
		return cached or nil
	end

	local image = nil
	if InputIconsMode == "function" then
		local ok, result = pcall(InputIcons, normalized, "Filled")
		if ok and typeof(result) == "string" and result ~= "" then
			image = result
		end
	elseif InputIconsMode == "table" then
		local isGamepad = false
		if typeof(normalized) == "EnumItem" and normalized.EnumType == Enum.KeyCode then
			local keyName = normalized.Name
			isGamepad = keyName:match("^Button") ~= nil or keyName:match("^DPad") ~= nil or keyName == "Menu"
		end

		local deviceKey = isGamepad and "Gamepad" or "Keyboard"
		local light = InputIcons.Light
		local dark = InputIcons.Dark
		local fromLight = type(light) == "table" and type(light[deviceKey]) == "table" and light[deviceKey][normalized] or nil
		local fromDark = type(dark) == "table" and type(dark[deviceKey]) == "table" and dark[deviceKey][normalized] or nil
		if typeof(fromLight) == "string" and fromLight ~= "" then
			image = fromLight
		elseif typeof(fromDark) == "string" and fromDark ~= "" then
			image = fromDark
		end
	end

	local contentId = toAssetId(image)
	if contentId == nil then
		inputIconCache[cacheKey] = false
		return nil
	end

	inputIconCache[cacheKey] = contentId
	return contentId
end

function module:_isControllerInputActive()
	local lastInputType = UserInputService:GetLastInputType()
	return CONTROLLER_INPUT_TYPES[lastInputType] == true
end

function module:_getActionKeyCandidates(actionKey, isController)
	if not isController then
		return { actionKey }
	end

	local aliases = ACTION_KEY_ALIASES[actionKey]
	if type(aliases) == "table" and #aliases > 0 then
		return aliases
	end

	return { actionKey }
end

function module:_formatKeybindLabel(keybind)
	if typeof(keybind) == "EnumItem" then
		if keybind.EnumType == Enum.KeyCode then
			local label = KEY_LABEL_OVERRIDES[keybind]
			if label then
				return label
			end

			local keyName = keybind.Name
			keyName = keyName:gsub("Button", "")
			keyName = keyName:gsub("DPad", "D-PAD ")
			return keyName
		end

		if keybind.EnumType == Enum.UserInputType then
			return USER_INPUT_LABEL_OVERRIDES[keybind] or keybind.Name
		end
	end

	if type(keybind) == "string" then
		return ActionsIcon.getKeyDisplayName(keybind)
	end

	return ""
end

function module:_getActionKeyLabel(actionKey, fallback)
	local isController = self:_isControllerInputActive()
	local primarySlot = isController and "Console" or "PC"
	local secondarySlot = isController and nil or "PC2"
	local keyCandidates = self:_getActionKeyCandidates(actionKey, isController)

	for _, candidateKey in ipairs(keyCandidates) do
		local primaryBound = PlayerDataTable.getBind(candidateKey, primarySlot)
		local primaryBoundLabel = self:_formatKeybindLabel(primaryBound)
		if primaryBoundLabel ~= "" and primaryBoundLabel ~= "NONE" then
			return primaryBoundLabel
		end

		if secondarySlot then
			local secondaryBound = PlayerDataTable.getBind(candidateKey, secondarySlot)
			local secondaryBoundLabel = self:_formatKeybindLabel(secondaryBound)
			if secondaryBoundLabel ~= "" and secondaryBoundLabel ~= "NONE" then
				return secondaryBoundLabel
			end
		end
	end

	local controls = SharedConfig and SharedConfig.Controls
	if not controls then
		return fallback or ""
	end

	local keybinds = isController and controls.CustomizableControllerKeybinds
		or controls.CustomizableKeybinds
	if type(keybinds) ~= "table" then
		return fallback or ""
	end

	for _, keybindInfo in ipairs(keybinds) do
		for _, candidateKey in ipairs(keyCandidates) do
			if keybindInfo.Key == candidateKey then
				local primaryLabel = self:_formatKeybindLabel(keybindInfo.DefaultPrimary)
				if primaryLabel ~= "" then
					return primaryLabel
				end

				local secondaryLabel = self:_formatKeybindLabel(keybindInfo.DefaultSecondary)
				if secondaryLabel ~= "" then
					return secondaryLabel
				end

				break
			end
		end
	end

	return fallback or ""
end

function module.start(export, ui: UI)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections
	self._initialized = false

	self._viewedPlayer = nil
	self._currentHealth = 0
	self._currentMaxHealth = 100
	self._currentUlt = 0
	self._maxUlt = 100

	self._weaponTemplates = {}
	self._weaponData = {}
	self._selectedSlot = nil
	self._spectateSlotCache = nil -- pre-built weapon/kit data for spectated players
	self._cooldownThreads = {}
	self._lastKitId = nil  -- Track kit for ult reset between rounds
	self._healthShakeToken = 0
	self._roundShakeToken = 0
	self._counterPlayerByUserId = {}
	self._counterPlayerStateByUserId = {}
	self._counterFrame = nil
	self._counterOriginalPosition = nil
	self._counterHiddenPosition = nil
	self._counterTimerLabel = nil
	self._counterTimerDefaultText = nil
	self._counterTimerThread = nil
	self._counterTimerGeneration = 0
	self._hideCounterInTraining = false

	local playerSpace = ui.PlayerSpace

	self._playerSpace = playerSpace
	self._healthBar = playerSpace.BarHolders.HealthBarHolder.HealthBar
	self._healthText = playerSpace.BarHolders.HealthBarHolder.Text
	self._ultBar = playerSpace.BarHolders.UltBarHolder.Bar

	self._playerImage = playerSpace.PlayerHolder.Holder.RotHolder.PlayerImage

	self._playerHolderOriginalPosition = playerSpace.PlayerHolder.Position
	self._barHoldersOriginalPosition = playerSpace.BarHolders.Position

	self:_cacheWeaponUI()
	self:_cacheMatchUI()
	self:_cacheKillfeedUI()
	self:_cacheRoundUI()
	self:_setupMatchListeners()

	return self
end

function module:_playHealthDamageShake()
	local barHolders = self._playerSpace and self._playerSpace:FindFirstChild("BarHolders")
	if not barHolders or not self._barHoldersOriginalPosition then
		return
	end

	self._healthShakeToken += 1
	local shakeToken = self._healthShakeToken

	cancelTweens("hud_health_shake")
	barHolders.Position = self._barHoldersOriginalPosition

	task.spawn(function()
		for _ = 1, HEALTH_SHAKE_STEPS do
			if self._healthShakeToken ~= shakeToken then
				return
			end

			if not self._ui or not self._ui.Parent or not self._ui.Visible then
				return
			end

			local xOffset = healthShakeRandom:NextInteger(-HEALTH_SHAKE_X_RANGE, HEALTH_SHAKE_X_RANGE)
			local yOffset = healthShakeRandom:NextInteger(-HEALTH_SHAKE_Y_RANGE, HEALTH_SHAKE_Y_RANGE)
			if xOffset == 0 and yOffset == 0 then
				yOffset = 1
			end

			local tween = TweenService:Create(barHolders, HEALTH_SHAKE_TWEEN, {
				Position = withOffset(self._barHoldersOriginalPosition, xOffset, yOffset),
			})
			currentTweens["hud_health_shake"] = { tween }
			tween:Play()
			tween.Completed:Wait()
		end

		if self._healthShakeToken == shakeToken and self._ui and self._ui.Parent then
			barHolders.Position = self._barHoldersOriginalPosition
		end

		currentTweens["hud_health_shake"] = nil
	end)
end

function module:_cacheMatchUI()
	local counter = self._ui:FindFirstChild("Counter", true)
	if not counter then
		return
	end

	self._counterFrame = counter
	self._counterOriginalPosition = counter.Position
	self._counterHiddenPosition = self:_getCounterHiddenPosition()

	local timer = counter:FindFirstChild("Timer")
	local timerValueLabel = nil
	if timer then
		local directTimer = timer:FindFirstChild("Timer")
		if directTimer and directTimer:IsA("TextLabel") then
			timerValueLabel = directTimer
		else
			for _, descendant in ipairs(timer:GetDescendants()) do
				if descendant:IsA("TextLabel") and descendant.Name == "Timer" then
					timerValueLabel = descendant
					break
				end
			end
		end

		if not timerValueLabel then
			local legacyRound = timer:FindFirstChild("RoundNumber")
			if legacyRound and legacyRound:IsA("TextLabel") then
				timerValueLabel = legacyRound
			else
				local legacyText = timer:FindFirstChild("Text")
				if legacyText and legacyText:IsA("TextLabel") then
					timerValueLabel = legacyText
				end
			end
		end
	end

	self._counterTimerLabel = timerValueLabel
	self._counterTimerDefaultText = timerValueLabel and timerValueLabel.Text or nil

	local redScore = counter:FindFirstChild("RedScore")
	self._redScoreLabel = redScore and redScore:FindFirstChild("Text")

	local blueScore = counter:FindFirstChild("BlueScore")
	self._blueScoreLabel = blueScore and blueScore:FindFirstChild("Text")

	if (not self._redScoreLabel or not self._blueScoreLabel) and timer then
		local scorePanels = {}
		for _, child in ipairs(timer:GetChildren()) do
			if child:IsA("CanvasGroup") and child.Name == "Timer" then
				table.insert(scorePanels, child)
			end
		end

		if #scorePanels >= 2 then
			table.sort(scorePanels, function(a, b)
				return a.Position.X.Scale < b.Position.X.Scale
			end)

			if not self._blueScoreLabel then
				self._blueScoreLabel = scorePanels[1]:FindFirstChild("Text")
			end
			if not self._redScoreLabel then
				self._redScoreLabel = scorePanels[#scorePanels]:FindFirstChild("Text")
			end
		end
	end

	self._yourTeamFrame = counter:FindFirstChild("YourTeam")
	self._enemyTeamFrame = counter:FindFirstChild("EnemyTeam")

	self._yourTeamTemplate = self:_getTeamPlayerTemplate(self._yourTeamFrame)
	self._enemyTeamTemplate = self:_getTeamPlayerTemplate(self._enemyTeamFrame)

	self._yourTeamSlots = {}
	self._enemyTeamSlots = {}
	self._counterPlayerByUserId = {}
	self._counterPlayerStateByUserId = {}

	self._matchTeam1 = {}
	self._matchTeam2 = {}
end

function module:_getCounterHiddenPosition()
	if not self._counterOriginalPosition then
		return nil
	end

	local offset = 106
	if self._counterFrame then
		local sizeOffset = self._counterFrame.Size.Y.Offset
		if sizeOffset > 0 then
			offset = sizeOffset
		else
			local absoluteSize = self._counterFrame.AbsoluteSize.Y
			if absoluteSize > 0 then
				offset = absoluteSize
			end
		end
	end

	return UDim2.new(
		self._counterOriginalPosition.X.Scale,
		self._counterOriginalPosition.X.Offset,
		self._counterOriginalPosition.Y.Scale,
		self._counterOriginalPosition.Y.Offset - offset - 10
	)
end

function module:_resolveCounterUserId(entry)
	return getCounterUserId(entry)
end

function module:_getCounterState(userId)
	if type(userId) ~= "number" then
		return nil
	end

	self._counterPlayerStateByUserId = self._counterPlayerStateByUserId or {}

	local state = self._counterPlayerStateByUserId[userId]
	if not state then
		state = {
			disconnected = false,
			dead = false,
			chatting = false,
			chatText = nil,
			imageColor = nil,
		}
		self._counterPlayerStateByUserId[userId] = state
	end

	return state
end

function module:_getCounterHolder(userId)
	if type(userId) ~= "number" then
		return nil
	end

	self._counterPlayerByUserId = self._counterPlayerByUserId or {}

	local holder = self._counterPlayerByUserId[userId]
	if holder and holder.Parent then
		return holder
	end

	local function findInSlots(slots)
		if type(slots) ~= "table" then
			return nil
		end

		for _, slot in ipairs(slots) do
			if slot and slot:GetAttribute("CounterUserId") == userId then
				return slot
			end
		end

		return nil
	end

	holder = findInSlots(self._yourTeamSlots) or findInSlots(self._enemyTeamSlots)
	if holder then
		self._counterPlayerByUserId[userId] = holder
	end

	return holder
end

function module:_untrackCounterHolder(holder)
	if not holder then
		return
	end

	self._counterPlayerByUserId = self._counterPlayerByUserId or {}

	for userId, mappedHolder in self._counterPlayerByUserId do
		if mappedHolder == holder then
			self._counterPlayerByUserId[userId] = nil
		end
	end

	pcall(function()
		holder:SetAttribute("CounterUserId", nil)
	end)
end

function module:_resetCounterHolderVisuals(holder)
	if not holder then
		return
	end

	local playerImage = holder:FindFirstChild("PlayerImage", true)
	if playerImage and playerImage:IsA("ImageLabel") then
		local defaultImageColor = holder:GetAttribute("CounterDefaultImageColor")
		if typeof(defaultImageColor) ~= "Color3" then
			defaultImageColor = Color3.new(1, 1, 1)
			holder:SetAttribute("CounterDefaultImageColor", defaultImageColor)
		end
		playerImage.ImageColor3 = defaultImageColor
	end

	local disconnectedIcon = holder:FindFirstChild("Disconnected", true)
	if disconnectedIcon and disconnectedIcon:IsA("GuiObject") then
		disconnectedIcon.Visible = false
	end

	local diedIcon = holder:FindFirstChild("Died", true)
	if diedIcon and diedIcon:IsA("GuiObject") then
		diedIcon.Visible = false
	end

	local chatBubble = holder:FindFirstChild("chat", true)
	if chatBubble and chatBubble:IsA("GuiObject") then
		chatBubble.Visible = false
	end
end

function module:_setCounterChatText(chatContainer, chatText)
	if not chatContainer or type(chatText) ~= "string" then
		return
	end

	local sanitized = string.sub(chatText, 1, 200)

	local setAny = false
	for _, descendant in ipairs(chatContainer:GetDescendants()) do
		if descendant:IsA("TextLabel") and descendant.Name == "Temp" then
			descendant.Text = sanitized
			setAny = true
		end
	end

	if not setAny then
		local fallbackLabel = chatContainer:FindFirstChildWhichIsA("TextLabel", true)
		if fallbackLabel then
			fallbackLabel.Text = sanitized
		end
	end
end

function module:_applyCounterPlayerState(userId)
	local state = self:_getCounterState(userId)
	local holder = self:_getCounterHolder(userId)
	if not state or not holder then
		return
	end

	local playerImage = holder:FindFirstChild("PlayerImage", true)
	if playerImage and playerImage:IsA("ImageLabel") then
		local defaultImageColor = holder:GetAttribute("CounterDefaultImageColor")
		if typeof(defaultImageColor) ~= "Color3" then
			defaultImageColor = Color3.new(1, 1, 1)
			holder:SetAttribute("CounterDefaultImageColor", defaultImageColor)
		end

		if typeof(state.imageColor) ~= "Color3" then
			state.imageColor = defaultImageColor
		end

		if state.disconnected then
			playerImage.ImageColor3 = COUNTER_DISCONNECTED_COLOR
		elseif state.dead then
			playerImage.ImageColor3 = COUNTER_DEAD_COLOR
		else
			playerImage.ImageColor3 = state.imageColor
		end
	end

	local disconnectedIcon = holder:FindFirstChild("Disconnected", true)
	if disconnectedIcon and disconnectedIcon:IsA("GuiObject") then
		disconnectedIcon.Visible = state.disconnected == true
	end

	local diedIcon = holder:FindFirstChild("Died", true)
	if diedIcon and diedIcon:IsA("GuiObject") then
		diedIcon.Visible = state.dead == true
	end

	local chatBubble = holder:FindFirstChild("chat", true)
	if chatBubble and chatBubble:IsA("GuiObject") then
		chatBubble.Visible = state.chatting == true
		if state.chatting and type(state.chatText) == "string" and state.chatText ~= "" then
			self:_setCounterChatText(chatBubble, state.chatText)
		end
	end
end

function module:_applyEntryCounterState(userId, entry)
	if type(entry) ~= "table" then
		return
	end

	local state = self:_getCounterState(userId)
	if not state then
		return
	end

	local disconnected = entry.disconnected
	if disconnected == nil then
		disconnected = entry.isDisconnected
	end
	if disconnected ~= nil then
		state.disconnected = disconnected == true
	end

	local dead = entry.dead
	if dead == nil then
		dead = entry.isDead
	end
	if dead ~= nil then
		state.dead = dead == true
	end

	local chatting = entry.chatting
	if chatting == nil then
		chatting = entry.isChatting
	end
	if chatting == nil and type(entry.chat) == "boolean" then
		chatting = entry.chat
	end
	if chatting ~= nil then
		state.chatting = chatting == true
	end

	local chatText = entry.chatText
	if type(chatText) ~= "string" then
		if type(entry.chatMessage) == "string" then
			chatText = entry.chatMessage
		elseif type(entry.message) == "string" then
			chatText = entry.message
		elseif type(entry.chat) == "string" then
			chatText = entry.chat
		end
	end
	if chatText ~= nil then
		state.chatText = chatText
	end
	if state.chatting == false then
		state.chatText = nil
	end
end

function module:_getTeamPlayerTemplate(teamFrame)
	local template = nil

	if teamFrame then
		for _, child in ipairs(teamFrame:GetChildren()) do
			if child.Name == "PlayerHolder" and child:IsA("GuiObject") then
				child.Visible = false
				if not template then
					template = child
				end
			end
		end
	end

	if not template and self._counterFrame then
		local configuration = self._counterFrame:FindFirstChild("Template")
		local fallbackTemplate = configuration and configuration:FindFirstChild("PlayerHolder", true)
		if fallbackTemplate and fallbackTemplate:IsA("GuiObject") then
			fallbackTemplate.Visible = false
			template = fallbackTemplate
		end
	end

	return template
end

function module:_teamHasUserId(teamEntries, userId)
	if type(teamEntries) ~= "table" or type(userId) ~= "number" then
		return false
	end

	for _, entry in ipairs(teamEntries) do
		local entryUserId = self:_resolveCounterUserId(entry)
		if entryUserId == userId then
			return true
		end
	end

	return false
end

function module:SetCounterPlayers(matchData)
	if type(matchData) ~= "table" then
		return
	end

	local team1 = matchData.team1
	local team2 = matchData.team2
	local playersList = nil

	if team1 == nil and type(matchData.teams) == "table" then
		team1 = matchData.teams.team1
		team2 = matchData.teams.team2
	end

	if type(matchData.players) == "table" then
		playersList = matchData.players
	elseif #matchData > 0 then
		playersList = matchData
	end

	if type(team1) ~= "table" then
		team1 = {}
	end
	if type(team2) ~= "table" then
		team2 = {}
	end

	if #team1 == 0 and #team2 == 0 and type(playersList) == "table" then
		local parsedTeam1 = {}
		local parsedTeam2 = {}
		local hasTeamMetadata = false

		for _, entry in ipairs(playersList) do
			local teamValue = type(entry) == "table" and (entry.team or entry.teamId or entry.Team or entry.TeamId)
				or nil
			local normalizedTeam = teamValue
			if type(normalizedTeam) == "string" then
				normalizedTeam = string.lower(normalizedTeam)
			end

			if normalizedTeam == 2 or normalizedTeam == "team2" or normalizedTeam == "blue" then
				table.insert(parsedTeam2, entry)
				hasTeamMetadata = true
			else
				if normalizedTeam == 1 or normalizedTeam == "team1" or normalizedTeam == "red" then
					hasTeamMetadata = true
				end
				table.insert(parsedTeam1, entry)
			end
		end

		if hasTeamMetadata then
			team1 = parsedTeam1
			team2 = parsedTeam2
		else
			team1 = playersList
		end
	end

	self._matchTeam1 = team1
	self._matchTeam2 = team2

	self:_populateMatchTeams()
end

function module:_setupMatchListeners()
	self._export:on("MatchStart", function(matchData)
		self:_onMatchStart(matchData)
	end)

	-- Hide health/loadout bars when Loadout UI is shown
	self._export:on("LoadoutOpened", function()
		self:_hideHealthAndLoadoutBars()
	end)

	-- Show health/loadout bars when Loadout UI is hidden  
	self._export:on("LoadoutClosed", function()
		self:_showHealthAndLoadoutBars()
	end)

	-- Training ground: hide counter (top bar) when HUD is shown
	self._export:on("TrainingHUDShow", function()
		self._hideCounterInTraining = true
	end)

	-- Refresh HUD icons when player changes weapon in loadout selection
	self._export:on("LoadoutWeaponChanged", function(data)
		self:_refreshWeaponData()
	end)

	self._export:on("RoundStart", function(data)
		self:_onRoundStart(data)
		self:_hideMToChangePrompt()
	end)

	self._export:on("BetweenRoundFreeze", function(data)
		-- Don't show "M to change" prompt anymore.
		-- Loadout UI is now opened directly by UIController.
		-- Just update the score if provided.
		if data and data.scores then
			self:SetCounterScore(data.scores.Team1, data.scores.Team2)
		end
		self:_syncCounterTimerFromData(data)
	end)

	self._export:on("ScoreUpdate", function(data)
		self:_onScoreUpdate(data)
	end)

	self._export:on("RoundKill", function(data)
		if type(data) == "table" and data.victimId then
			self:SetCounterPlayerDead(data.victimId, true)
		end
	end)

	self._export:on("ReturnToLobby", function()
		self:_clearMatchTeams()
		self:_clearKillfeedEntries()
		self:_hideMToChangePrompt()
		self:_stopCounterTimer(true)
	end)

	self._export:on("PlayerKilled", function(data)
		self:_onPlayerKilled(data)
	end)
end

function module:_onMatchStart(matchData)
	self:SetCounterPlayers(matchData)
end

function module:_populateMatchTeams()
	local localPlayer = Players.LocalPlayer
	local localUserId = localPlayer and localPlayer.UserId or nil

	local team1 = self._matchTeam1 or {}
	local team2 = self._matchTeam2 or {}

	local localIsTeam1 = localUserId and self:_teamHasUserId(team1, localUserId) or false
	local localIsTeam2 = localUserId and self:_teamHasUserId(team2, localUserId) or false

	local yourTeamEntries = team1
	local enemyTeamEntries = team2

	if localIsTeam2 and not localIsTeam1 then
		yourTeamEntries = team2
		enemyTeamEntries = team1
	end

	-- Track whether the local player's team is swapped relative to team1/team2,
	-- so score labels display on the correct side (YourTeam vs EnemyTeam).
	self._scoreSwapped = localIsTeam2 and not localIsTeam1

	self._yourTeamSlots = self._yourTeamSlots or {}
	self._enemyTeamSlots = self._enemyTeamSlots or {}

	self:_populateTeamSlots(self._yourTeamFrame, self._yourTeamTemplate, self._yourTeamSlots, yourTeamEntries)
	self:_populateTeamSlots(self._enemyTeamFrame, self._enemyTeamTemplate, self._enemyTeamSlots, enemyTeamEntries)
end

function module:_populateTeamSlots(teamFrame, template, slotCache, teamEntries)
	if not teamFrame or not template or type(slotCache) ~= "table" or type(teamEntries) ~= "table" then
		return
	end

	for i = #slotCache + 1, #teamEntries do
		local clone = template:Clone()
		clone.Visible = true
		clone.Parent = teamFrame
		table.insert(slotCache, clone)
	end

	for i = #slotCache, #teamEntries + 1, -1 do
		self:_untrackCounterHolder(slotCache[i])
		slotCache[i]:Destroy()
		table.remove(slotCache, i)
	end

	for i, entry in ipairs(teamEntries) do
		local holder = slotCache[i]
		if holder then
			local userId = self:_resolveCounterUserId(entry)
			holder.LayoutOrder = i
			self:_untrackCounterHolder(holder)
			self:_resetCounterHolderVisuals(holder)

			if not userId then
				holder.Visible = false
				continue
			end

			holder.Visible = true
			holder:SetAttribute("CounterUserId", userId)
			self._counterPlayerByUserId[userId] = holder

			self:_setTeamPlayerThumbnail(holder, userId)
			self:_applyEntryCounterState(userId, entry)
			self:_applyCounterPlayerState(userId)
		end
	end
end

function module:_setTeamPlayerThumbnail(holder, userId)
	if not holder or not userId then
		return
	end

	local image = holder:FindFirstChild("PlayerImage", true)
	if not image or not image:IsA("ImageLabel") then
		return
	end

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)
		if success and content then
			image.Image = content
		end
	end)
end

function module:_formatCounterTimer(seconds)
	local clamped = math.max(0, math.ceil(seconds))
	local mins = math.floor(clamped / 60)
	local secs = clamped % 60
	return string.format("%d:%02d", mins, secs)
end

function module:_setCounterTimerText(text)
	if self._counterTimerLabel and self._counterTimerLabel:IsA("TextLabel") then
		self._counterTimerLabel.Text = tostring(text)
	end
end

function module:_stopCounterTimer(resetText)
	self._counterTimerGeneration += 1

	if self._counterTimerThread then
		pcall(task.cancel, self._counterTimerThread)
		self._counterTimerThread = nil
	end

	if resetText then
		local fallbackText = self._counterTimerDefaultText or "0:00"
		self:_setCounterTimerText(fallbackText)
	end
	
	-- Cancel any ongoing flash tween and reset timer color to normal
	cancelTweens("timer_flash")
	if self._counterTimerLabel and self._counterTimerLabel:IsA("TextLabel") then
		self._counterTimerLabel.TextColor3 = TIMER_NORMAL_COLOR
	end
end

function module:_startCounterTimer(durationSeconds)
	if type(durationSeconds) ~= "number" or durationSeconds <= 0 then
		return
	end

	self:_stopCounterTimer(false)
	self._counterTimerGeneration += 1
	local generation = self._counterTimerGeneration
	local endTime = os.clock() + durationSeconds

	self:_setCounterTimerText(self:_formatCounterTimer(durationSeconds))
	
	-- Reset timer color to normal and cancel any existing flash
	cancelTweens("timer_flash")
	if self._counterTimerLabel and self._counterTimerLabel:IsA("TextLabel") then
		self._counterTimerLabel.TextColor3 = TIMER_NORMAL_COLOR
	end
	
	-- Track flash state
	local isFlashing = false

	self._counterTimerThread = task.spawn(function()
		while self._ui and self._ui.Parent and generation == self._counterTimerGeneration do
			local remaining = endTime - os.clock()
			if remaining <= 0 then
				self:_setCounterTimerText("0:00")
				-- Reset to normal color when timer ends
				cancelTweens("timer_flash")
				if self._counterTimerLabel and self._counterTimerLabel:IsA("TextLabel") then
					self._counterTimerLabel.TextColor3 = TIMER_NORMAL_COLOR
				end
				break
			end

			self:_setCounterTimerText(self:_formatCounterTimer(remaining))
			
			-- Start smooth flashing when ≤30 seconds remaining
			if remaining <= 30 and not isFlashing and self._counterTimerLabel and self._counterTimerLabel:IsA("TextLabel") then
				isFlashing = true
				-- Flash loop in separate thread
				task.spawn(function()
					local flashIn = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
					local flashOut = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
					
					while generation == self._counterTimerGeneration and self._counterTimerLabel and self._counterTimerLabel.Parent do
						-- Fade to red
						cancelTweens("timer_flash")
						local toRed = TweenService:Create(self._counterTimerLabel, flashIn, { TextColor3 = TIMER_FLASH_COLOR })
						currentTweens["timer_flash"] = { toRed }
						toRed:Play()
						toRed.Completed:Wait()
						
						if generation ~= self._counterTimerGeneration then break end
						
						-- Fade back to normal
						cancelTweens("timer_flash")
						local toNormal = TweenService:Create(self._counterTimerLabel, flashOut, { TextColor3 = TIMER_NORMAL_COLOR })
						currentTweens["timer_flash"] = { toNormal }
						toNormal:Play()
						toNormal.Completed:Wait()
					end
					
					-- Ensure color is reset when flash loop ends
					if self._counterTimerLabel and self._counterTimerLabel:IsA("TextLabel") then
						self._counterTimerLabel.TextColor3 = TIMER_NORMAL_COLOR
					end
				end)
			end
			
			task.wait(0.1)
		end

		-- When timer thread ends, ensure flash is cancelled and color is reset
		cancelTweens("timer_flash")
		if self._counterTimerLabel and self._counterTimerLabel:IsA("TextLabel") then
			self._counterTimerLabel.TextColor3 = TIMER_NORMAL_COLOR
		end

		if generation == self._counterTimerGeneration then
			self._counterTimerThread = nil
		end
	end)
end

function module:_syncCounterTimerFromData(data)
	if type(data) ~= "table" then
		return false
	end

	local duration = data.remaining or data.duration or data.timeLeft or data.timer or data.roundDuration
	if type(duration) == "number" and duration > 0 then
		self:_startCounterTimer(duration)
		return true
	end

	local timerText = data.timerText
	if type(timerText) == "string" and timerText ~= "" then
		self:_stopCounterTimer(false)
		self:_setCounterTimerText(timerText)
		return true
	end

	return false
end

function module:_onRoundStart(data)
	if type(data) ~= "table" then
		return
	end

	local appliedTimer = self:_syncCounterTimerFromData(data)
	if not appliedTimer then
		self:_stopCounterTimer(false)
		self:_setCounterTimerText("0:00")
	end

	-- Refresh all counter player states (players are revived between rounds)
	self:RefreshCounterPlayers()
end

function module:_showMToChangePrompt(data)
	if not self._ui or not self._ui.Parent then
		return
	end

	-- Cancel any existing timer
	if self._betweenRoundTimerThread then
		task.cancel(self._betweenRoundTimerThread)
		self._betweenRoundTimerThread = nil
	end

	-- Create "M to change" label
	if not self._mToChangeLabel then
		local label = Instance.new("TextLabel")
		label.Name = "MToChangePrompt"
		label.Text = "M to change"
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -100)
		label.Size = UDim2.new(0, 200, 0, 28)
		label.Parent = self._ui
		self._mToChangeLabel = label
	end

	-- Create timer label
	if not self._betweenRoundTimerLabel then
		local timerLabel = Instance.new("TextLabel")
		timerLabel.Name = "BetweenRoundTimer"
		timerLabel.Text = "10"
		timerLabel.Font = Enum.Font.GothamBold
		timerLabel.TextSize = 28
		timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		timerLabel.BackgroundTransparency = 1
		timerLabel.AnchorPoint = Vector2.new(0.5, 1)
		timerLabel.Position = UDim2.new(0.5, 0, 1, -60)
		timerLabel.Size = UDim2.new(0, 120, 0, 36)
		timerLabel.Parent = self._ui
		self._betweenRoundTimerLabel = timerLabel
	end

	self._mToChangeLabel.Visible = true
	self._betweenRoundTimerLabel.Visible = true

	local duration = (data and type(data.duration) == "number") and data.duration or 10
	local remaining = math.ceil(duration)

	local function updateTimerText(secs)
		if self._betweenRoundTimerLabel then
			self._betweenRoundTimerLabel.Text = tostring(secs) .. "s"
		end
	end

	updateTimerText(remaining)

	-- Countdown loop
	self._betweenRoundTimerThread = task.spawn(function()
		local startTime = os.clock()
		while remaining > 0 do
			task.wait(1)
			if not self._betweenRoundTimerLabel or not self._betweenRoundTimerLabel.Parent then
				return
			end
			remaining = math.max(0, math.ceil(duration - (os.clock() - startTime)))
			updateTimerText(remaining)
		end
		self._betweenRoundTimerThread = nil
	end)
end

function module:_hideMToChangePrompt()
	if self._betweenRoundTimerThread then
		task.cancel(self._betweenRoundTimerThread)
		self._betweenRoundTimerThread = nil
	end

	if self._mToChangeLabel then
		self._mToChangeLabel.Visible = false
	end

	if self._betweenRoundTimerLabel then
		self._betweenRoundTimerLabel.Visible = false
	end
end

function module:_hideHealthAndLoadoutBars()
	-- Track that loadout UI is open so _animateShow doesn't override
	self._loadoutUIOpen = true

	-- Hide health bar, player holder, and loadout bar when Loadout UI is open
	if self._playerSpace then
		local barHolders = self._playerSpace:FindFirstChild("BarHolders")
		if barHolders then
			barHolders.Visible = false
		end
		local playerHolder = self._playerSpace:FindFirstChild("PlayerHolder")
		if playerHolder and playerHolder:IsA("CanvasGroup") then
			playerHolder.GroupTransparency = 1
		end
	end

	if self._itemHolderSpace then
		self._itemHolderSpace.Visible = false
	end
end

function module:_showHealthAndLoadoutBars()
	-- Track that loadout UI is closed
	self._loadoutUIOpen = false

	-- Show health bar, player holder, and loadout bar when Loadout UI is closed
	if self._playerSpace then
		local barHolders = self._playerSpace:FindFirstChild("BarHolders")
		if barHolders then
			barHolders.Visible = true
		end
		local playerHolder = self._playerSpace:FindFirstChild("PlayerHolder")
		if playerHolder and playerHolder:IsA("CanvasGroup") then
			playerHolder.GroupTransparency = 0
		end
	end

	-- Don't show loadout bar on mobile (it's hidden by default there)
	if self._itemHolderSpace and not UserInputService.TouchEnabled then
		self._itemHolderSpace.Visible = true
	end
end

function module:_onScoreUpdate(data)
	if type(data) ~= "table" then
		return
	end

	if data.team1Score ~= nil or data.team2Score ~= nil or data.redScore ~= nil or data.blueScore ~= nil then
		self:SetCounterScore(data.redScore or data.team1Score, data.blueScore or data.team2Score)
		return
	end

	local teamKey = data.teamKey
	if teamKey == nil then
		teamKey = data.team
	end

	if teamKey ~= nil then
		self:AddCounterScore(teamKey, data.amount or data.points or 1)
	end
end

function module:_clearMatchTeams()
	self:_clearTeamSlots(self._yourTeamSlots)
	self:_clearTeamSlots(self._enemyTeamSlots)
	self._matchTeam1 = {}
	self._matchTeam2 = {}
	self._scoreSwapped = false
	self._counterPlayerByUserId = {}
	self._counterPlayerStateByUserId = {}
end

function module:_clearTeamSlots(slotCache)
	if not slotCache then
		return
	end
	for i = #slotCache, 1, -1 do
		self:_resetCounterHolderVisuals(slotCache[i])
		self:_untrackCounterHolder(slotCache[i])
		slotCache[i]:Destroy()
		table.remove(slotCache, i)
	end
end

function module:SetCounterScore(team1Score, team2Score)
	-- UI layout: LEFT = Your team (blue), RIGHT = Enemy team (red)
	-- Determine which score goes where based on local player's team
	local yourTeamScore, enemyTeamScore

	if self._scoreSwapped then
		-- Local player is on Team2
		yourTeamScore = team2Score
		enemyTeamScore = team1Score
	else
		-- Local player is on Team1
		yourTeamScore = team1Score
		enemyTeamScore = team2Score
	end

	-- LEFT side = your team score (blue label)
	if self._blueScoreLabel and yourTeamScore ~= nil then
		self._blueScoreLabel.Text = tostring(yourTeamScore)
	end
	-- RIGHT side = enemy team score (red label)
	if self._redScoreLabel and enemyTeamScore ~= nil then
		self._redScoreLabel.Text = tostring(enemyTeamScore)
	end
end

function module:AddCounterScore(teamKey, amount)
	local delta = type(amount) == "number" and amount or 1

	local normalized = teamKey
	if type(normalized) == "string" then
		normalized = string.lower(normalized)
	end

	-- Determine if the scoring team is the local player's team or enemy team
	local isTeam1 = normalized == 1 or normalized == "team1" or normalized == "red" or normalized == "r"
	local isTeam2 = normalized == 2 or normalized == "team2" or normalized == "blue" or normalized == "b"

	if not isTeam1 and not isTeam2 then
		return
	end

	-- Determine which label to update based on whether scoring team is "your team" or "enemy"
	local targetLabel = nil
	local isYourTeam = (isTeam1 and not self._scoreSwapped) or (isTeam2 and self._scoreSwapped)

	if isYourTeam then
		-- Your team scored → update LEFT (blue) label
		targetLabel = self._blueScoreLabel
	else
		-- Enemy team scored → update RIGHT (red) label
		targetLabel = self._redScoreLabel
	end

	if not targetLabel then
		return
	end

	local currentScore = getScoreFromLabel(targetLabel)
	targetLabel.Text = tostring(currentScore + delta)
end

function module:SetCounterPlayerDisconnected(userId, isDisconnected)
	local resolvedUserId = self:_resolveCounterUserId(userId)
	local state = self:_getCounterState(resolvedUserId)
	if not state then
		return
	end

	state.disconnected = isDisconnected == true
	if state.disconnected then
		state.chatting = false
		state.chatText = nil
	end

	self:_applyCounterPlayerState(resolvedUserId)
end

function module:SetCounterPlayerDead(userId, isDead)
	local resolvedUserId = self:_resolveCounterUserId(userId)
	local state = self:_getCounterState(resolvedUserId)
	if not state then
		return
	end

	state.dead = isDead == true
	self:_applyCounterPlayerState(resolvedUserId)
end

function module:SetCounterPlayerChatting(userId, isChatting, chatText)
	local resolvedUserId = self:_resolveCounterUserId(userId)
	local state = self:_getCounterState(resolvedUserId)
	if not state then
		return
	end

	state.chatting = isChatting == true
	if type(chatText) == "string" then
		state.chatText = chatText
	elseif state.chatting == false then
		state.chatText = nil
	end

	self:_applyCounterPlayerState(resolvedUserId)

	if state.chatting then
		local generation = (state._chatGeneration or 0) + 1
		state._chatGeneration = generation
		task.delay(5, function()
			if state._chatGeneration == generation and state.chatting then
				state.chatting = false
				state.chatText = nil
				self:_applyCounterPlayerState(resolvedUserId)
			end
		end)
	end
end

function module:RefreshCounterPlayer(userId)
	local resolvedUserId = self:_resolveCounterUserId(userId)
	local state = self:_getCounterState(resolvedUserId)
	if not state then
		return
	end

	state.disconnected = false
	state.dead = false
	state.chatting = false
	state.chatText = nil
	state.imageColor = nil

	local holder = self:_getCounterHolder(resolvedUserId)
	if holder then
		self:_resetCounterHolderVisuals(holder)
	end

	self:_applyCounterPlayerState(resolvedUserId)
end

function module:RefreshCounterPlayers(userList)
	if type(userList) == "table" then
		for _, entry in ipairs(userList) do
			local userId = self:_resolveCounterUserId(entry)
			if userId then
				self:RefreshCounterPlayer(userId)
			end
		end
		return
	end

	for userId in self._counterPlayerByUserId do
		self:RefreshCounterPlayer(userId)
	end
end

function module:ShowCounter()
	if not self._counterFrame or not self._counterOriginalPosition then
		return
	end

	if not self._counterHiddenPosition then
		self._counterHiddenPosition = self:_getCounterHiddenPosition()
	end

	cancelTweens("show_counter")

	self._counterFrame.Visible = true
	if self._counterHiddenPosition then
		self._counterFrame.Position = self._counterHiddenPosition
	end

	local tween = TweenService:Create(self._counterFrame, TweenConfig.get("Counter", "show"), {
		Position = self._counterOriginalPosition,
	})
	tween:Play()
	currentTweens["show_counter"] = { tween }

	return tween
end

function module:HideCounter()
	if not self._counterFrame or not self._counterOriginalPosition then
		return
	end

	local hiddenPosition = self._counterHiddenPosition or self:_getCounterHiddenPosition()
	if not hiddenPosition then
		return
	end

	self._counterHiddenPosition = hiddenPosition

	cancelTweens("show_counter")

	local tween = TweenService:Create(self._counterFrame, TweenConfig.get("Counter", "hide"), {
		Position = hiddenPosition,
	})
	tween:Play()
	currentTweens["show_counter"] = { tween }

	tween.Completed:Once(function()
		if self._counterFrame then
			self._counterFrame.Visible = false
		end
	end)

	return tween
end

-- =============================================================================
-- KILLFEED
-- =============================================================================

local KILLFEED_ENTRY_DURATION = 5

function module:_cacheKillfeedUI()
	local screenGui = self._ui and self._ui.Parent
	if not screenGui or not screenGui:IsA("ScreenGui") then
		return
	end

	local killfeed = screenGui:FindFirstChild("Killfeed")
	if not killfeed and self._playerSpace then
		killfeed = self._playerSpace:FindFirstChild("Killfeed")
	end

	-- Create killfeed container if it doesn't exist
	if not killfeed then
		killfeed = Instance.new("Frame")
		killfeed.Name = "Killfeed"
		killfeed.Size = UDim2.new(0, 320, 0, 300)
		killfeed.Position = UDim2.new(1, -10, 0, 80)
		killfeed.AnchorPoint = Vector2.new(1, 0)
		killfeed.BackgroundTransparency = 1
		killfeed.BorderSizePixel = 0
		killfeed.ClipsDescendants = true
		killfeed.Parent = screenGui

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = killfeed
	end

	self._killfeedContainer = killfeed
	self._killfeedContainer.Visible = true

	-- Try to find existing template, or create one
	local assetsGui = ReplicatedStorage:FindFirstChild("Assets")
	assetsGui = assetsGui and assetsGui:FindFirstChild("Gui")
	local template = assetsGui and assetsGui:FindFirstChild("KillfeedTemplate")

	if not template then
		template = self:_createKillfeedTemplate()
	end

	self._killfeedTemplate = template
	self._killfeedEntries = {}
end

function module:_createKillfeedTemplate()
	-- Build a killfeed entry: [KillerAvatar KillerName] ⚔ [VictimName VictimAvatar]
	local entry = Instance.new("Frame")
	entry.Name = "KillfeedTemplate"
	entry.Size = UDim2.new(1, 0, 0, 32)
	entry.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	entry.BackgroundTransparency = 0.3
	entry.BorderSizePixel = 0
	entry.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = entry

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = entry

	-- Attacker section (left)
	local attacker = Instance.new("Frame")
	attacker.Name = "Attacker"
	attacker.Size = UDim2.new(0.4, 0, 1, 0)
	attacker.Position = UDim2.fromScale(0, 0)
	attacker.BackgroundTransparency = 1
	attacker.Parent = entry

	local attackerImage = Instance.new("ImageLabel")
	attackerImage.Name = "PlayerImage"
	attackerImage.Size = UDim2.new(0, 24, 0, 24)
	attackerImage.Position = UDim2.new(0, 0, 0.5, 0)
	attackerImage.AnchorPoint = Vector2.new(0, 0.5)
	attackerImage.BackgroundTransparency = 1
	attackerImage.ScaleType = Enum.ScaleType.Crop
	attackerImage.Parent = attacker

	local attackerCorner = Instance.new("UICorner")
	attackerCorner.CornerRadius = UDim.new(1, 0)
	attackerCorner.Parent = attackerImage

	local attackerInfo = Instance.new("Frame")
	attackerInfo.Name = "Info"
	attackerInfo.Size = UDim2.new(1, -28, 1, 0)
	attackerInfo.Position = UDim2.new(0, 28, 0, 0)
	attackerInfo.BackgroundTransparency = 1
	attackerInfo.Parent = attacker

	local attackerText = Instance.new("TextLabel")
	attackerText.Name = "Text"
	attackerText.Size = UDim2.fromScale(1, 1)
	attackerText.BackgroundTransparency = 1
	attackerText.Font = Enum.Font.GothamBold
	attackerText.TextSize = 12
	attackerText.TextColor3 = Color3.fromRGB(255, 100, 100)
	attackerText.TextXAlignment = Enum.TextXAlignment.Left
	attackerText.TextTruncate = Enum.TextTruncate.AtEnd
	attackerText.Text = ""
	attackerText.Parent = attackerInfo

	-- Weapon icon (center)
	local weapon = Instance.new("Frame")
	weapon.Name = "Weapon"
	weapon.Size = UDim2.new(0.2, 0, 1, 0)
	weapon.Position = UDim2.fromScale(0.4, 0)
	weapon.BackgroundTransparency = 1
	weapon.Parent = entry

	local swordIcon = Instance.new("TextLabel")
	swordIcon.Name = "Icon"
	swordIcon.Size = UDim2.fromScale(1, 1)
	swordIcon.BackgroundTransparency = 1
	swordIcon.Font = Enum.Font.GothamBold
	swordIcon.TextSize = 14
	swordIcon.TextColor3 = Color3.fromRGB(200, 200, 200)
	swordIcon.Text = ">"
	swordIcon.Parent = weapon

	-- Attacked section (right)
	local attacked = Instance.new("Frame")
	attacked.Name = "Attacked"
	attacked.Size = UDim2.new(0.4, 0, 1, 0)
	attacked.Position = UDim2.fromScale(0.6, 0)
	attacked.BackgroundTransparency = 1
	attacked.Parent = entry

	local attackedInfo = Instance.new("Frame")
	attackedInfo.Name = "Info"
	attackedInfo.Size = UDim2.new(1, -28, 1, 0)
	attackedInfo.Position = UDim2.new(0, 0, 0, 0)
	attackedInfo.BackgroundTransparency = 1
	attackedInfo.Parent = attacked

	local attackedText = Instance.new("TextLabel")
	attackedText.Name = "Text"
	attackedText.Size = UDim2.fromScale(1, 1)
	attackedText.BackgroundTransparency = 1
	attackedText.Font = Enum.Font.GothamBold
	attackedText.TextSize = 12
	attackedText.TextColor3 = Color3.fromRGB(100, 150, 255)
	attackedText.TextXAlignment = Enum.TextXAlignment.Right
	attackedText.TextTruncate = Enum.TextTruncate.AtEnd
	attackedText.Text = ""
	attackedText.Parent = attackedInfo

	local attackedImage = Instance.new("ImageLabel")
	attackedImage.Name = "PlayerImage"
	attackedImage.Size = UDim2.new(0, 24, 0, 24)
	attackedImage.Position = UDim2.new(1, 0, 0.5, 0)
	attackedImage.AnchorPoint = Vector2.new(1, 0.5)
	attackedImage.BackgroundTransparency = 1
	attackedImage.ScaleType = Enum.ScaleType.Crop
	attackedImage.Parent = attacked

	local attackedCorner = Instance.new("UICorner")
	attackedCorner.CornerRadius = UDim.new(1, 0)
	attackedCorner.Parent = attackedImage

	return entry
end

function module:_onPlayerKilled(data)
	if type(data) ~= "table" then
		return
	end

	local victimUserId = self:_resolveCounterUserId(data.victimUserId or data.victim or data.userId)
	if victimUserId then
		self:SetCounterPlayerDead(victimUserId, true)
	end

	if not self._killfeedContainer or not self._killfeedTemplate then
		return
	end

	local entry = self._killfeedTemplate:Clone()
	entry.Name = "KillfeedEntry"
	entry.Visible = true
	entry.Parent = self._killfeedContainer

	self._killfeedEntries = self._killfeedEntries or {}
	table.insert(self._killfeedEntries, entry)

	self:_populateKillEntry(entry, data)

	-- Pop-in: scale up fast then ease back to 1
	local uiScale = entry:FindFirstChildWhichIsA("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = entry
	end
	uiScale.Scale = 0
	local popUp = TweenService:Create(
		uiScale,
		TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	popUp:Play()

	self:_scheduleEntryHide(entry)
end

function module:_populateKillEntry(entry, data)
	local killerUserId = data.killerUserId
	local victimUserId = data.victimUserId
	local weaponId = data.weaponId

	local killer = killerUserId and Players:GetPlayerByUserId(killerUserId)
	local killerName = killer and killer.DisplayName or "Unknown"
	local killerPremium = killer and killer.MembershipType == Enum.MembershipType.Premium
	local killerVerified = killer and killer.HasVerifiedBadge

	local victim = victimUserId and Players:GetPlayerByUserId(victimUserId)
	local victimName = victim and victim.DisplayName or "Unknown"
	local victimPremium = victim and victim.MembershipType == Enum.MembershipType.Premium
	local victimVerified = victim and victim.HasVerifiedBadge

	local attacker = entry:FindFirstChild("Attacker", true)
	if attacker then
		self:_setKillfeedPlayerSection(attacker, killerUserId, killerName, killerPremium, killerVerified)
	end

	local attacked = entry:FindFirstChild("Attacked", true)
	if attacked then
		self:_setKillfeedPlayerSection(attacked, victimUserId, victimName, victimPremium, victimVerified)
	end

	local weaponFrame = entry:FindFirstChild("Weapon", true)
	if weaponFrame and weaponId then
		-- Remove the existing template icon
		local existingIcon = weaponFrame:FindFirstChildWhichIsA("ImageLabel")
		if existingIcon then
			existingIcon:Destroy()
		end

		-- Clone the weapon icon from the Configuration folder inside the killfeed
		local configFolder = self._killfeedContainer and self._killfeedContainer:FindFirstChild("Configuration")
		local iconTemplate = configFolder and configFolder:FindFirstChild(weaponId)
		if iconTemplate and iconTemplate:IsA("ImageLabel") then
			local iconClone = iconTemplate:Clone()
			iconClone.Position = UDim2.fromScale(0.5, 0.5)
			iconClone.AnchorPoint = Vector2.new(0.5, 0.5)
			iconClone.Parent = weaponFrame
		end
	end
end

function module:_setKillfeedPlayerSection(section, userId, name, isPremium, isVerified)
	local playerImage = section:FindFirstChild("PlayerImage", true)
	if playerImage and playerImage:IsA("ImageLabel") and userId then
		task.spawn(function()
			local ok, thumb = pcall(function()
				return Players:GetUserThumbnailAsync(
					userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size420x420
				)
			end)
			if ok and thumb then
				playerImage.Image = thumb
			end
		end)
	end

	local info = section:FindFirstChild("Info", true)
	if not info then
		local mainFrame = section:FindFirstChild("Frame")
		info = mainFrame and mainFrame:FindFirstChild("Info")
	end
	if info then
		local textLabel = info:FindFirstChild("Text")
		if textLabel and textLabel:IsA("TextLabel") then
			textLabel.Text = name
		end

		local premiumLabel = info:FindFirstChild("Premium")
		if premiumLabel then
			premiumLabel.Visible = isPremium == true
		end

		local verifiedLabel = info:FindFirstChild("Verified")
		if verifiedLabel then
			verifiedLabel.Visible = isVerified == true
		end
	end
end

function module:_scheduleEntryHide(entry)
	task.delay(KILLFEED_ENTRY_DURATION, function()
		if not entry or not entry.Parent then
			return
		end
		self:_hideKillfeedEntry(entry)
	end)
end

function module:_clearKillfeedEntries()
	if not self._killfeedEntries then
		return
	end
	for i = #self._killfeedEntries, 1, -1 do
		local entry = self._killfeedEntries[i]
		if entry and entry.Parent then
			entry:Destroy()
		end
		table.remove(self._killfeedEntries, i)
	end
end

function module:_hideKillfeedEntry(entry)
	if self._killfeedEntries then
		for i, e in ipairs(self._killfeedEntries) do
			if e == entry then
				table.remove(self._killfeedEntries, i)
				break
			end
		end
	end
	if not entry or not entry.Parent then
		return
	end

	-- Scale down before destroying
	local uiScale = entry:FindFirstChildWhichIsA("UIScale")
	if uiScale then
		local shrink = TweenService:Create(
			uiScale,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Scale = 0 }
		)
		shrink:Play()
		shrink.Completed:Once(function()
			if entry and entry.Parent then
				entry:Destroy()
			end
		end)
	else
		entry:Destroy()
	end
end

function module:_cacheWeaponUI()
	self._itemHolderSpace = self._ui:FindFirstChild("ItemHolderSpace", true)
	if not self._itemHolderSpace then
		return
	end

	self._itemHolderOriginalPosition = self._itemHolderSpace.Position

	self._ammoCounter = self._ui:FindFirstChild("Counter", true)
	self._ammoCounterAmmo = self._ammoCounter and self._ammoCounter:FindFirstChild("Ammo", true)
	self._ammoCounterMax = self._ammoCounter and self._ammoCounter:FindFirstChild("Max", true)
	self._ammoCounterReloading = self._ammoCounter and self._ammoCounter:FindFirstChild("Reloading", true)
	self._ammoCounterAmmoColor = self._ammoCounterAmmo and self._ammoCounterAmmo.TextColor3
	self._ammoCounterMaxColor = self._ammoCounterMax and self._ammoCounterMax.TextColor3

	local actionsFrame = self._itemHolderSpace:FindFirstChild("Actions") or self._itemHolderSpace
	self._itemListFrame = actionsFrame:FindFirstChild("ItemHolder")
	self._weaponTemplateSource = self._itemListFrame and self._itemListFrame:FindFirstChild("Item1")
	self._abilityTemplateSource = self._itemListFrame and self._itemListFrame:FindFirstChild("Ability")
	self._actionsListFrame = self._itemHolderSpace:FindFirstChild("ListFrame")
	self._actionsTemplate = self._actionsListFrame and self._actionsListFrame:FindFirstChild("ActionFrame")

	if not self._weaponTemplateSource then
		self._weaponTemplateSource = actionsFrame:FindFirstChild("Item1", true)
	end
	if not self._abilityTemplateSource then
		self._abilityTemplateSource = actionsFrame:FindFirstChild("Ability", true)
	end
	if not self._actionsTemplate then
		self._actionsTemplate = actionsFrame:FindFirstChild("ActionFrame", true)
	end

	if self._weaponTemplateSource then
		self._weaponTemplateSource.Visible = false
	end
	if self._abilityTemplateSource then
		self._abilityTemplateSource.Visible = false
	end
	if self._actionsTemplate then
		self._actionsTemplate.Visible = false
	end

	self._itemDesc = actionsFrame:FindFirstChild("ItemDesc") or self._ui:FindFirstChild("ItemDesc", true)
	if self._itemDesc then
		self._itemDescActions = self._itemDesc:FindFirstChild("Actions")
		if self._itemDescActions then
			self._itemDescOriginalPos = self._itemDescActions.Position
		end

		local actionsFrame = self._itemDescActions and self._itemDescActions:FindFirstChild("Actions")
		local ammoFrame = actionsFrame and actionsFrame:FindFirstChild("Ammo")
		local infoFrame = actionsFrame and actionsFrame:FindFirstChild("Info")
		local rarityFrame = infoFrame and infoFrame:FindFirstChild("Rarity")

		self._itemDescAmmoFrame = ammoFrame
		self._itemDescAmmo = ammoFrame and ammoFrame:FindFirstChild("Ammo")
		self._itemDescMax = ammoFrame and ammoFrame:FindFirstChild("Max")
		self._itemDescAmmoColor = self._itemDescAmmo and self._itemDescAmmo.TextColor3
		self._itemDescMaxColor = self._itemDescMax and self._itemDescMax.TextColor3
		self._itemDescName = infoFrame and infoFrame:FindFirstChild("name")
		self._itemDescRarityText = rarityFrame and rarityFrame:FindFirstChild("RarityText")
		self._itemDescRarityLabels = {}

		if rarityFrame then
			for _, child in rarityFrame:GetChildren() do
				if child:IsA("TextLabel") then
					table.insert(self._itemDescRarityLabels, child)
				end
			end
		end

		-- Cache LB/RB bumper icons — they live inside this same Info frame
		if infoFrame then
			local lb = infoFrame:FindFirstChild("Lb")
			local rb = infoFrame:FindFirstChild("Rb")
			if lb or rb then
				self._bumperInfoFrame = infoFrame
				self._bumperLb = lb
				self._bumperRb = rb
				self._bumperDefaultImages = {
					Lb = lb and lb.Image or nil,
					Rb = rb and rb.Image or nil,
				}
				-- Keep Lb/Rb hidden by default; visibility toggled by _updateBumperVisibility
				if lb then
					lb.Visible = false
				end
				if rb then
					rb.Visible = false
				end
			end
		end
	end
end

function module:setViewedPlayer(player, character)
	self._viewedPlayer = player
	self._viewedCharacter = character
end

-- Build weapon/kit slot data from spectated player's SelectedLoadout attribute.
-- This bypasses the attribute-write system (_syncFromSelectedLoadout) which only
-- works for LocalPlayer. Data is stored in _spectateSlotCache and read by
-- getWeaponData / getKitData instead of player attributes.
function module:_buildSpectateSlotCache(player)
	self._spectateSlotCache = {}
	if not player then return end

	local raw = player:GetAttribute("SelectedLoadout")
	local decoded = self:_decodeAttribute(raw)
	if type(decoded) ~= "table" then return end

	local loadout = decoded.loadout
	if type(loadout) ~= "table" and decoded.Kit ~= nil then
		loadout = decoded
	end
	if type(loadout) ~= "table" then return end

	for _, slotType in ipairs({ "Primary", "Secondary", "Melee" }) do
		local weaponId = loadout[slotType]
		local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)
		if weaponConfig then
			self._spectateSlotCache[slotType] = {
				Gun = weaponConfig.name,
				GunId = weaponConfig.id,
				GunType = weaponConfig.weaponType,
				Ammo = weaponConfig.clipSize,
				MaxAmmo = weaponConfig.maxAmmo,
				ClipSize = weaponConfig.clipSize,
				Reloading = false,
				OnCooldown = false,
				Cooldown = weaponConfig.cooldown or 0,
				ReloadTime = weaponConfig.reloadTime or 0,
				Rarity = weaponConfig.rarity,
			}
		end
	end

	local kitId = loadout.Kit
	if kitId then
		local kitData = KitConfig.buildKitData(kitId, { abilityCooldownEndsAt = 0, ultimate = 0 })
		self._spectateSlotCache["Kit"] = kitData
	end
end

-- Lightweight weapon connection for spectating: only watches EquippedSlot/DisplaySlot
-- (no SelectedLoadout write-back, no PrimaryData writes — those are read-only via cache).
function module:_setupSpectateWeaponConnections(player)
	self._connections:cleanupGroup("hud_weapons")
	if not player then return end

	self._connections:track(player, "AttributeChanged", function(attributeName)
		if attributeName == "EquippedSlot" or attributeName == "DisplaySlot" then
			if player:GetAttribute("DisplaySlot") == "Ability" then
				self:_setSelectedSlot("Kit")
			else
				local slot = player:GetAttribute("EquippedSlot") or "Primary"
				self:_setSelectedSlot(slot)
			end
			return
		end
		-- Rebuild cache if the spectated player swaps loadouts mid-match
		if attributeName == "SelectedLoadout" then
			self:_buildSpectateSlotCache(player)
			self:_refreshWeaponData()
		end
	end, "hud_weapons")
end

-- Switch the full HUD (health bar + loadout + ult) to track a spectated player.
-- Health/MaxHealth/Ultimate/MaxUltimate are set server-side so all clients can
-- read them. Weapon/kit data is built locally from SelectedLoadout via cache.
function module:setSpectateTarget(player)
	self:setViewedPlayer(player)
	self:_setupHealthConnection()
	self:_setupUltConnection()
	self:_buildSpectateSlotCache(player)
	self:_setupSpectateWeaponConnections(player)
	self:_refreshWeaponData()
	self:_updatePlayerThumbnail()
	-- Bars are hidden on death; restore them so spectators see the full HUD
	self:_showHealthAndLoadoutBars()
end

-- Restore the full HUD to track LocalPlayer again after spectating ends.
function module:clearSpectateTarget()
	self._spectateSlotCache = nil
	self:setViewedPlayer(Players.LocalPlayer)
	self:_setupHealthConnection()
	self:_setupUltConnection()
	self:_setupWeaponConnections()
	self:_refreshWeaponData()
	self:_updatePlayerThumbnail()
	-- Re-show bars for the respawned local player
	self:_showHealthAndLoadoutBars()
end

function module:showForPlayer(player, character)
	self:setViewedPlayer(player, character)
	self._export:show()
end

function module:_updatePlayerThumbnail()
	if not self._viewedPlayer then
		return
	end

	local userId = self._viewedPlayer.UserId
	self._playerImage.Image = "rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=420&h=420"
end

function module:_initPlayerData()
	if not self._viewedPlayer then
		return
	end

	local player = self._viewedPlayer
	local hasKitData = player:GetAttribute("KitData") ~= nil

	PlayerDataTable.init()
	local equipped = PlayerDataTable.getEquippedLoadout()

	player:SetAttribute("Health", 100)
	player:SetAttribute("MaxHealth", 100)
	player:SetAttribute("Ultimate", 0)
	player:SetAttribute("EquippedSlot", "Primary")
	player:SetAttribute("DisplaySlot", nil)

	local kitId = equipped.Kit
	if not hasKitData then
		local kitData = kitId and KitConfig.buildKitData(kitId, { abilityCooldownEndsAt = 0, ultimate = 0 }) or nil
		player:SetAttribute("KitData", kitData and HttpService:JSONEncode(kitData) or nil)
	end

	local weaponTypes = { "Primary", "Secondary", "Melee" }

	for _, slotType in weaponTypes do
		local weaponId = equipped[slotType]
		local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)

		if weaponConfig then
			local weaponData = {
				Gun = weaponConfig.name,
				GunId = weaponConfig.id,
				GunType = weaponConfig.weaponType,
				Ammo = weaponConfig.clipSize,
				MaxAmmo = weaponConfig.maxAmmo,
				ClipSize = weaponConfig.clipSize,
				Reloading = false,
				OnCooldown = false,
				Cooldown = weaponConfig.cooldown or 0,
				ReloadTime = weaponConfig.reloadTime or 0,
				Rarity = weaponConfig.rarity,
			}

			local jsonData = HttpService:JSONEncode(weaponData)
			player:SetAttribute(slotType .. "Data", jsonData)
		else
			player:SetAttribute(slotType .. "Data", nil)
		end
	end
end

function module:_clearPlayerData()
	if not self._viewedPlayer then
		return
	end

	local player = self._viewedPlayer

	player:SetAttribute("Health", nil)
	player:SetAttribute("MaxHealth", nil)
	player:SetAttribute("Ultimate", nil)
	player:SetAttribute("EquippedSlot", nil)
	player:SetAttribute("DisplaySlot", nil)
	player:SetAttribute("KitData", nil)

	local weaponTypes = { "Primary", "Secondary", "Melee" }

	for _, slotType in weaponTypes do
		player:SetAttribute(slotType .. "Data", nil)
	end
end

function module:_decodeAttribute(attributeValue)
	if type(attributeValue) == "table" then
		return attributeValue
	end

	if type(attributeValue) ~= "string" then
		return nil
	end

	local success, data = pcall(function()
		return HttpService:JSONDecode(attributeValue)
	end)

	if success then
		return data
	end

	return nil
end

-- Prefer syncing from server authoritative SelectedLoadout (MatchService sets it on submit).
-- Returns true if a loadout was successfully applied.
function module:_syncFromSelectedLoadout(): boolean
	if not self._viewedPlayer then
		return false
	end

	local raw = self._viewedPlayer:GetAttribute("SelectedLoadout")
	local decoded = self:_decodeAttribute(raw)
	if type(decoded) ~= "table" then
		return false
	end

	local loadout = decoded.loadout
	if type(loadout) ~= "table" and decoded.Kit ~= nil then
		-- Some builds store the loadout directly.
		loadout = decoded
	end
	if type(loadout) ~= "table" then
		return false
	end

	-- Sync to PlayerDataTable so skin resolution works consistently.
	PlayerDataTable.init()
	for _, slotType in ipairs(SLOT_ORDER) do
		local weaponId = loadout[slotType]
		if weaponId ~= nil then
			PlayerDataTable.setEquippedWeapon(slotType, weaponId)
		end
	end

	-- Seed KitData for HUD ability slot template.
	do
		local kitId = loadout.Kit
		local kitData = kitId and KitConfig.buildKitData(kitId, { abilityCooldownEndsAt = 0, ultimate = 0 }) or nil
		self._viewedPlayer:SetAttribute("KitData", kitData and HttpService:JSONEncode(kitData) or nil)
	end

	-- Seed weapon data blobs for HUD (Primary/Secondary/Melee).
	for _, slotType in ipairs({ "Primary", "Secondary", "Melee" }) do
		local weaponId = loadout[slotType]
		local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)

		if weaponConfig then
			local weaponData = {
				Gun = weaponConfig.name,
				GunId = weaponConfig.id,
				GunType = weaponConfig.weaponType,
				Ammo = weaponConfig.clipSize,
				MaxAmmo = weaponConfig.maxAmmo,
				ClipSize = weaponConfig.clipSize,
				Reloading = false,
				OnCooldown = false,
				Cooldown = weaponConfig.cooldown or 0,
				ReloadTime = weaponConfig.reloadTime or 0,
				Rarity = weaponConfig.rarity,
			}

			self._viewedPlayer:SetAttribute(slotType .. "Data", HttpService:JSONEncode(weaponData))
		else
			self._viewedPlayer:SetAttribute(slotType .. "Data", nil)
		end
	end

	-- Ensure EquippedSlot exists so HUD selection highlights correctly.
	if self._viewedPlayer:GetAttribute("EquippedSlot") == nil then
		self._viewedPlayer:SetAttribute("EquippedSlot", "Primary")
	end

	return true
end

function module:getWeaponData(slotType)
	-- During spectate: return pre-built cache instead of player attribute (can't read remote attrs)
	if self._spectateSlotCache then
		return self._spectateSlotCache[slotType] or nil
	end
	if not self._viewedPlayer then
		return nil
	end

	local jsonData = self._viewedPlayer:GetAttribute(slotType .. "Data")
	return self:_decodeAttribute(jsonData)
end

function module:getKitData()
	-- During spectate: return pre-built cache instead of player attribute
	if self._spectateSlotCache then
		return self._spectateSlotCache["Kit"] or nil
	end
	if not self._viewedPlayer then
		return nil
	end

	local jsonData = self._viewedPlayer:GetAttribute("KitData")
	return self:_decodeAttribute(jsonData)
end

function module:getCurrentWeaponData()
	if not self._viewedPlayer then
		return nil
	end

	local equippedSlot = self._viewedPlayer:GetAttribute("EquippedSlot")
	if not equippedSlot then
		return nil
	end

	return self:getWeaponData(equippedSlot)
end

function module:_applyRarity(template, color)
	if not template or not color then
		return
	end

	local rarity = template:FindFirstChild("Rarity", true)
	if rarity and rarity:IsA("CanvasGroup") then
		rarity.GroupColor3 = color
	end

	local bar = template:FindFirstChild("Bar", true)
	if bar and bar:IsA("ImageLabel") then
		bar.ImageColor3 = color
	end

	local bgRarity = template:FindFirstChild("BgRarity", true)
	if bgRarity and bgRarity:IsA("ImageLabel") then
		bgRarity.ImageColor3 = color
	end
end

function module:_getWeaponImage(weaponId)
	if not weaponId then
		return nil
	end

	local skinId = PlayerDataTable.getEquippedSkin(weaponId)
	if skinId then
		local skin = LoadoutConfig.getWeaponSkin(weaponId, skinId)
		if skin and skin.imageId then
			local weapon = LoadoutConfig.getWeapon(weaponId)
			return skin.imageId, weapon and weapon.rarity or nil
		end
	end

	local weapon = LoadoutConfig.getWeapon(weaponId)
	if weapon then
		return weapon.imageId, weapon.rarity
	end

	return nil
end

function module:_setupTemplateReloadState(templateData, isReloading, reloadTime)
	if not templateData or not templateData.reloading or not templateData.reloadGradient then
		return
	end

	local function clearReloadFlag()
		if not self._viewedPlayer or not templateData.slot or templateData.slot == "Kit" then
			return
		end

		local attributeName = templateData.slot .. "Data"
		local jsonData = self._viewedPlayer:GetAttribute(attributeName)
		local data = self:_decodeAttribute(jsonData)
		if not data then
			return
		end

		if data.Reloading == false then
			return
		end

		data.Reloading = false

		local success, encoded = pcall(function()
			return HttpService:JSONEncode(data)
		end)

		if success then
			self._viewedPlayer:SetAttribute(attributeName, encoded)
		end
	end

	local key = "reload_" .. templateData.slot
	cancelTweens(key)

	if not isReloading then
		templateData.reloading.GroupTransparency = 0
		templateData.reloadGradient.Offset = Vector2.new(0.5, -1)
		if templateData.reloadBg then
			templateData.reloadBg.ImageTransparency = 1
		end
		return
	end

	templateData.reloading.GroupTransparency = 0
	templateData.reloadGradient.Offset = Vector2.new(0.5, 0)
	if templateData.reloadBg then
		templateData.reloadBg.ImageTransparency = 1
	end

	local tweens = {}

	if templateData.reloadBg then
		local fadeIn = TweenService:Create(templateData.reloadBg, TweenConfig.get("Reload", "fadeIn"), {
			ImageTransparency = TweenConfig.Values.ReloadBgVisible,
		})
		fadeIn:Play()
		table.insert(tweens, fadeIn)
	end

	local duration = reloadTime and reloadTime > 0 and reloadTime or TweenConfig.Values.ReloadDuration
	local gradientTween = TweenService:Create(
		templateData.reloadGradient,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{
			Offset = Vector2.new(0.5, -1),
		}
	)
	gradientTween:Play()
	table.insert(tweens, gradientTween)

	gradientTween.Completed:Once(function()
		clearReloadFlag()
		if templateData.reloadBg then
			local fadeOut = TweenService:Create(templateData.reloadBg, TweenConfig.get("Reload", "fadeOut"), {
				ImageTransparency = 1,
			})
			fadeOut:Play()
			table.insert(tweens, fadeOut)
			fadeOut.Completed:Once(function()
				if templateData.reloading then
					templateData.reloading.GroupTransparency = 0
				end
			end)
		else
			templateData.reloading.GroupTransparency = 0
		end
	end)

	currentTweens[key] = tweens
end

function module:_cancelCooldownThread(slotType)
	if self._cooldownThreads[slotType] then
		task.cancel(self._cooldownThreads[slotType])
		self._cooldownThreads[slotType] = nil
	end
end

function module:_setupCooldownText(templateData, isOnCooldown, cooldownTime)
	if not templateData or not templateData.ammoLabel then
		return
	end

	local slotType = templateData.slot
	self:_cancelCooldownThread(slotType)

	local ammoLabel = templateData.ammoLabel
	local ammoFrame = templateData.ammoFrame
	local key = "cooldown_text_" .. slotType
	cancelTweens(key)

	if not isOnCooldown then
		if ammoFrame then
			ammoFrame.BackgroundTransparency = 1
		end
		ammoLabel.TextTransparency = 1
		ammoLabel.Text = ""
		return
	end

	local duration = cooldownTime and cooldownTime > 0 and cooldownTime or TweenConfig.Values.ReloadDuration
	ammoLabel.TextTransparency = 0
	ammoLabel.Text = string.format("%.1f", duration)

	local fadeTween = TweenService:Create(ammoLabel, TweenConfig.get("CooldownText", "fadeIn"), {
		TextTransparency = 0,
	})
	fadeTween:Play()

	self._cooldownThreads[slotType] = task.spawn(function()
		local startTime = tick()
		while true do
			local elapsed = tick() - startTime
			local remaining = duration - elapsed
			if remaining <= 0 then
				break
			end
			ammoLabel.Text = string.format("%.1f", remaining)
			task.wait()
		end

		ammoLabel.Text = "READY"
		task.wait(TweenConfig.Values.CooldownReadyDelay)

		if not ammoLabel or not ammoLabel.Parent then
			return
		end

		cancelTweens(key)
		local fadeOut = TweenService:Create(ammoLabel, TweenConfig.get("CooldownText", "fadeOut"), {
			TextTransparency = 1,
		})
		fadeOut:Play()
		currentTweens[key] = { fadeOut }
		fadeOut.Completed:Once(function()
			ammoLabel.Text = ""
		end)

		self._cooldownThreads[slotType] = nil
	end)
end

function module:_setupCooldownBar(templateData, isOnCooldown, cooldownTime)
	if not templateData or not templateData.cooldownFrame or not templateData.cooldownGradient then
		return
	end

	local key = "cooldown_bar_" .. templateData.slot
	cancelTweens(key)

	if not isOnCooldown then
		templateData.cooldownFrame.Visible = false
		templateData.cooldownGradient.Offset = Vector2.new(0, 0)
		return
	end

	local duration = cooldownTime and cooldownTime > 0 and cooldownTime or TweenConfig.Values.ReloadDuration

	templateData.cooldownFrame.Visible = true
	templateData.cooldownGradient.Offset = Vector2.new(0, 0)

	local gradTween = TweenService:Create(
		templateData.cooldownGradient,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Offset = Vector2.new(-1, 0) }
	)
	gradTween:Play()

	gradTween.Completed:Once(function()
		templateData.cooldownFrame.Visible = false
		templateData.cooldownGradient.Offset = Vector2.new(0, 0)
	end)

	currentTweens[key] = { gradTween }
end

function module:_cancelCooldownBar(slotType)
	local key = "cooldown_bar_" .. slotType
	cancelTweens(key)

	local templateData = self._weaponTemplates[slotType]
	if templateData and templateData.cooldownFrame then
		templateData.cooldownFrame.Visible = false
		templateData.cooldownGradient.Offset = Vector2.new(0, 0)
	end
end

function module:_isControllerActive()
	local lastInput = UserInputService:GetLastInputType()
	return lastInput == Enum.UserInputType.Gamepad1
		or lastInput == Enum.UserInputType.Gamepad2
		or lastInput == Enum.UserInputType.Gamepad3
		or lastInput == Enum.UserInputType.Gamepad4
end

function module:_updateBumperIcons()
	local defaults = self._bumperDefaultImages or {}
	local leftBind = PlayerDataTable.getBind(BUMPER_BIND_ACTIONS.Lb, "Console") or BUMPER_FALLBACK_BINDS.Lb
	local rightBind = PlayerDataTable.getBind(BUMPER_BIND_ACTIONS.Rb, "Console") or BUMPER_FALLBACK_BINDS.Rb
	local leftIcon = getInputIconAsset(leftBind) or defaults.Lb
	local rightIcon = getInputIconAsset(rightBind) or defaults.Rb

	if self._bumperLb and leftIcon then
		self._bumperLb.Image = leftIcon
	end
	if self._bumperRb and rightIcon then
		self._bumperRb.Image = rightIcon
	end
end

function module:_updateBumperVisibility()
	self:_updateBumperIcons()
	local isController = self:_isControllerActive()

	-- Toggle Lb/Rb icons individually (the parent Info frame holds other always-visible content)
	if self._bumperLb then
		self._bumperLb.Visible = isController
	end
	if self._bumperRb then
		self._bumperRb.Visible = isController
	end

	-- Toggle slot keybind labels: show on PC, hide on controller
	for _, data in self._weaponTemplates do
		if data.slotFrame then
			data.slotFrame.Visible = not isController
		end
	end
end

function module:_animateBumperPress(side)
	local label = side == "Lb" and self._bumperLb or self._bumperRb
	if not label then
		return
	end

	-- Ensure UIScale exists for animation
	local uiScale = label:FindFirstChild("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = label
	end

	local key = "bumper_" .. side
	cancelTweens(key)

	uiScale.Scale = 1
	local pressDown =
		TweenService:Create(uiScale, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 0.8,
		})
	local pressUp = TweenService:Create(uiScale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})

	pressDown:Play()
	pressDown.Completed:Once(function()
		pressUp:Play()
	end)

	currentTweens[key] = { pressDown, pressUp }
end

function module:_createTemplate(slotType, templateSource, iconImage, rarityColor, order)
	if not templateSource or not self._itemListFrame then
		return nil
	end

	local template = templateSource:Clone()
	template.Name = "Slot_" .. slotType
	template.Visible = true
	template.LayoutOrder = order
	template.Parent = self._itemListFrame

	local uiScale = template:FindFirstChild("UIScale")
	if uiScale then
		uiScale.Scale = TweenConfig.Values.DeselectedScale
	end

	if iconImage then
		local iconHolder = template:FindFirstChild("IconHolder", true)
		if iconHolder then
			local icon = iconHolder:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				icon.Image = iconImage
			end

			local bg = iconHolder:FindFirstChild("bg")
			if bg and bg:IsA("ImageLabel") then
				bg.Image = iconImage
			end

			local reloadIcon = iconHolder:FindFirstChild("Reloading", true)
			if reloadIcon then
				local reloadIconImage = reloadIcon:FindFirstChild("Icon")
				if reloadIconImage and reloadIconImage:IsA("ImageLabel") then
					reloadIconImage.Image = iconImage
				end
			end
		end
	end

	self:_applyRarity(template, rarityColor)

	local reloading = template:FindFirstChild("Reloading", true)
	local reloadGradient = reloading and reloading:FindFirstChild("UIGradient")
	local reloadBg = reloading and reloading:FindFirstChild("Bg")
	local reloadGradImage = reloading and reloading:FindFirstChild("grad")
	local ammoFrame = template:FindFirstChild("Frame")
	local ammoLabel = ammoFrame and ammoFrame:FindFirstChild("Ammo")

	if reloadBg and rarityColor then
		reloadBg.ImageColor3 = rarityColor
	end

	if reloading and reloading:IsA("CanvasGroup") then
		reloading.GroupTransparency = 0
	end
	if reloadGradient then
		reloadGradient.Offset = Vector2.new(0.5, -1)
	end
	if reloadBg then
		reloadBg.ImageTransparency = 1
	end
	if reloadGradImage and iconImage then
		reloadGradImage.Image = iconImage
	end

	-- Set slot keybind label (PC only — hidden on controller)
	local slotFrame = template:FindFirstChild("Slot")
	local inputFrame = slotFrame and slotFrame:FindFirstChild("InputFrame")
	local kbImage = inputFrame and inputFrame:FindFirstChild("KeyboardImageLabel")
	local actionLabel = kbImage and kbImage:FindFirstChild("ActionLabel")

	local SLOT_KEYBIND_MAP = {
		Primary = "EquipPrimary",
		Secondary = "EquipSecondary",
		Melee = "EquipMelee",
	}
	local bindAction = SLOT_KEYBIND_MAP[slotType]
	if actionLabel and bindAction then
		local boundKey = PlayerDataTable.getBind(bindAction, "PC")
		local displayName = ActionsIcon.getKeyDisplayName(boundKey)
		actionLabel.Text = displayName
	end

	-- Hide slot frame on controller (uses LB/RB cycling instead)
	if slotFrame then
		local isController = self:_isControllerActive()
		slotFrame.Visible = not isController
	end

	-- Cache cooldown bar elements
	local cooldownFrame = template:FindFirstChild("Cooldown")
	local cooldownBig = cooldownFrame and cooldownFrame:FindFirstChild("Frame")
	cooldownBig = cooldownBig and cooldownBig:FindFirstChild("Big")
	local cooldownGradient = cooldownBig and cooldownBig:FindFirstChild("UIGradient")

	if cooldownFrame then
		cooldownFrame.Visible = false
	end

	local data = {
		slot = slotType,
		template = template,
		uiScale = uiScale,
		reloading = reloading,
		reloadGradient = reloadGradient,
		reloadBg = reloadBg,
		ammoFrame = ammoFrame,
		ammoLabel = ammoLabel,
		actionLabel = actionLabel,
		bindAction = bindAction,
		slotFrame = slotFrame,
		cooldownFrame = cooldownFrame,
		cooldownGradient = cooldownGradient,
	}

	self._weaponTemplates[slotType] = data

	return data
end

function module:_clearTemplates()
	for _, data in self._weaponTemplates do
		if data.template and data.template.Parent then
			data.template:Destroy()
		end
	end
	table.clear(self._weaponTemplates)
end

function module:_buildLoadoutTemplates()
	if not self._itemListFrame then
		return
	end

	local order = 1
	local activeSlots = {}

	local kitData = self:getKitData()
	if kitData and self._abilityTemplateSource then
		activeSlots.Kit = true
		if not self._weaponTemplates.Kit then
			local rarityInfo = kitData.Rarity and KitConfig.RarityInfo[kitData.Rarity]
			local rarityColor = rarityInfo and rarityInfo.COLOR or Color3.new(1, 1, 1)
			self:_createTemplate("Kit", self._abilityTemplateSource, kitData.Icon, rarityColor, order)
		else
			self._weaponTemplates.Kit.template.LayoutOrder = order
		end
		order += 1
	end

	for _, slotType in { "Primary", "Secondary", "Melee" } do
		local data = self:getWeaponData(slotType)
		if data and self._weaponTemplateSource then
			activeSlots[slotType] = true
			if not self._weaponTemplates[slotType] then
				local weaponId = data.GunId or data.Gun
				local imageId, rarityName = self:_getWeaponImage(weaponId)
				local rarityColor = getRarityColor(rarityName)
				self:_createTemplate(slotType, self._weaponTemplateSource, imageId, rarityColor, order)
			else
				self._weaponTemplates[slotType].template.LayoutOrder = order
			end
			order += 1
		end
	end

	for slotType, data in self._weaponTemplates do
		if not activeSlots[slotType] then
			if data.template and data.template.Parent then
				data.template:Destroy()
			end
			self._weaponTemplates[slotType] = nil
		end
	end
end

function module:_setSelectedSlot(slotType)
	local previousSlot = self._selectedSlot
	self._selectedSlot = slotType

	-- Cancel cooldown bar on the previous slot when swapping weapons (reload cancel)
	if previousSlot and previousSlot ~= slotType and previousSlot ~= "Kit" then
		self:_cancelCooldownBar(previousSlot)
	end

	for slot, data in self._weaponTemplates do
		local targetScale = slot == slotType and TweenConfig.Values.SelectedScale or TweenConfig.Values.DeselectedScale
		if data.uiScale then
			local key = "select_" .. slot
			cancelTweens(key)
			local tween = TweenService:Create(data.uiScale, TweenConfig.get("Selection", "update"), {
				Scale = targetScale,
			})
			tween:Play()
			currentTweens[key] = { tween }
		end
	end

	if slotType == "Kit" then
		local kitData = self:getKitData()
		if kitData then
			self:_updateItemDesc(kitData)
			self:_animateItemDesc()
		else
			self:_hideItemDesc()
		end
	elseif slotType then
		local data = self._weaponData[slotType]
		if data then
			self:_updateItemDesc(data)
			self:_animateItemDesc()
		else
			self:_hideItemDesc()
		end
	else
		self:_hideItemDesc()
	end

	self:_populateActions(slotType)
end

function module:_updateItemDesc(weaponData)
	if not weaponData then
		return
	end

	local isKitData = weaponData.AbilityName ~= nil or weaponData.KitName ~= nil
	if isKitData then
		if self._itemDescAmmo then
			self._itemDescAmmo.Text = ""
		end
		if self._itemDescMax then
			self._itemDescMax.Text = ""
		end
		if self._ammoCounterAmmo then
			self._ammoCounterAmmo.Text = ""
		end
		if self._ammoCounterMax then
			self._ammoCounterMax.Text = ""
		end

		if self._ammoCounterReloading then
			local isOnCooldown = weaponData.AbilityOnCooldown == true
			if self._ammoCounterReloading:IsA("TextLabel") then
				self._ammoCounterReloading.Text = "COOLDOWN"
			end
			if self._ammoCounterReloading:IsA("GuiObject") then
				self._ammoCounterReloading.Visible = isOnCooldown
			elseif self._ammoCounterReloading:IsA("CanvasGroup") then
				self._ammoCounterReloading.GroupTransparency = isOnCooldown and 0 or 1
			end
		end

		if self._itemDescName then
			self._itemDescName.Text = tostring(weaponData.AbilityName or weaponData.KitName or "ABILITY")
		end

		if self._itemDescRarityText then
			local rarityName = weaponData.Rarity or "Common"
			self._itemDescRarityText.Text = tostring(rarityName):upper()
			local rarityInfo = KitConfig.RarityInfo[rarityName]
			local rarityColor = rarityInfo and rarityInfo.COLOR or Color3.new(1, 1, 1)
			for _, label in self._itemDescRarityLabels do
				label.TextColor3 = rarityColor
			end
		end

		return
	end

	local maxAmmo = weaponData.MaxAmmo or 0
	local ammo = weaponData.Ammo or 0
	local clipSize = weaponData.ClipSize or 0

	-- Check if weapon uses ammo (melee weapons don't)
	local usesAmmo = clipSize > 0 or maxAmmo > 0

	-- Hide entire ammo frame when weapon doesn't use ammo
	if self._itemDescAmmoFrame then
		self._itemDescAmmoFrame.Visible = usesAmmo
	end

	-- Only update ammo text elements
	if self._itemDescAmmo then
		self._itemDescAmmo.Text = usesAmmo and tostring(ammo) or ""
	end

	if self._itemDescMax then
		self._itemDescMax.Text = usesAmmo and tostring(maxAmmo) or ""
	end

	if self._ammoCounterAmmo then
		self._ammoCounterAmmo.Text = usesAmmo and tostring(ammo) or ""
	end

	if self._ammoCounterMax then
		self._ammoCounterMax.Text = usesAmmo and tostring(maxAmmo) or ""
	end

	if usesAmmo then
		local outOfAmmo = ammo <= 0 and maxAmmo <= 0
		local emptyColor = Color3.fromRGB(250, 70, 70)

		if self._itemDescAmmo then
			self._itemDescAmmo.TextColor3 = outOfAmmo and emptyColor or self._itemDescAmmoColor
		end
		if self._itemDescMax then
			self._itemDescMax.TextColor3 = outOfAmmo and emptyColor or self._itemDescMaxColor
		end
		if self._ammoCounterAmmo then
			self._ammoCounterAmmo.TextColor3 = outOfAmmo and emptyColor or self._ammoCounterAmmoColor
		end
		if self._ammoCounterMax then
			self._ammoCounterMax.TextColor3 = outOfAmmo and emptyColor or self._ammoCounterMaxColor
		end
	end

	if self._ammoCounterReloading then
		local isReloading = weaponData.Reloading == true and usesAmmo
		if self._ammoCounterReloading:IsA("TextLabel") then
			self._ammoCounterReloading.Text = "RELOADING"
		end
		if self._ammoCounterReloading:IsA("GuiObject") then
			self._ammoCounterReloading.Visible = isReloading
		elseif self._ammoCounterReloading:IsA("CanvasGroup") then
			self._ammoCounterReloading.GroupTransparency = isReloading and 0 or 1
		end
	end

	if self._itemDescName then
		self._itemDescName.Text = tostring(weaponData.Gun or weaponData.GunId or "WEAPON")
	end

	if self._itemDescRarityText then
		local rarityName = weaponData.Rarity or "Common"
		self._itemDescRarityText.Text = tostring(rarityName):upper()
		local rarityColor = getRarityColor(rarityName)
		for _, label in self._itemDescRarityLabels do
			label.TextColor3 = rarityColor
		end
	end
end

function module:_clearActions()
	if not self._actionsListFrame then
		return
	end

	for _, child in self._actionsListFrame:GetChildren() do
		if child.Name:match("^Action_") then
			child:Destroy()
		end
	end
end

function module:_getActionBind(actionKey)
	local isController = self:_isControllerInputActive()
	local primarySlot = isController and "Console" or "PC"
	local secondarySlot = isController and nil or "PC2"
	local keyCandidates = self:_getActionKeyCandidates(actionKey, isController)

	for _, candidateKey in ipairs(keyCandidates) do
		local primaryBound = PlayerDataTable.getBind(candidateKey, primarySlot)
		if primaryBound ~= nil then
			return primaryBound
		end

		if secondarySlot then
			local secondaryBound = PlayerDataTable.getBind(candidateKey, secondarySlot)
			if secondaryBound ~= nil then
				return secondaryBound
			end
		end
	end

	local controls = SharedConfig and SharedConfig.Controls
	if not controls then
		return nil
	end

	local keybinds = isController and controls.CustomizableControllerKeybinds
		or controls.CustomizableKeybinds
	if type(keybinds) ~= "table" then
		return nil
	end

	for _, keybindInfo in ipairs(keybinds) do
		for _, candidateKey in ipairs(keyCandidates) do
			if keybindInfo.Key == candidateKey then
				if keybindInfo.DefaultPrimary ~= nil then
					return keybindInfo.DefaultPrimary
				end
				if keybindInfo.DefaultSecondary ~= nil then
					return keybindInfo.DefaultSecondary
				end
				break
			end
		end
	end

	return nil
end

function module:_setupControlsBindingListener()
	if self._controlsChangedDisconnect then
		self._controlsChangedDisconnect()
		self._controlsChangedDisconnect = nil
	end

	local watchedKeys = {
		Ability = true,
		ControllerAbility = true,
		QuickMelee = true,
		ControllerQuickMelee = true,
		CycleWeaponLeft = true,
		CycleWeaponRight = true,
	}

	self._controlsChangedDisconnect = PlayerDataTable.onChanged(function(category, key)
		if category ~= "Controls" or not watchedKeys[key] then
			return
		end

		self:_updateBumperVisibility()

		local slot = self._selectedSlot
		if not slot and self._viewedPlayer then
			slot = self._viewedPlayer:GetAttribute("EquippedSlot") or "Primary"
		end

		if slot and slot ~= "Kit" then
			self:_populateActions(slot)
		end
	end)
end

function module:_getActionList(slotType, weaponData)
	local actions = {}
	if not slotType or slotType == "Kit" then
		return actions
	end

	local weaponId = weaponData and (weaponData.GunId or weaponData.Gun)
	local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)
	local actionFlags = weaponConfig and weaponConfig.actions
	if not weaponId then
	elseif not weaponConfig then
	elseif not actionFlags then
	end

	local canQuickMelee = actionFlags and actionFlags.canQuickUseMelee
	local canQuickAbility = actionFlags and actionFlags.canQuickUseAblility

	if actionFlags == nil then
		if weaponConfig and weaponConfig.weaponType then
			canQuickMelee = weaponConfig.weaponType ~= "Melee"
			canQuickAbility = true
		else
			canQuickMelee = slotType ~= "Melee"
			canQuickAbility = true
		end
	end

	if canQuickMelee and slotType ~= "Melee" then
		table.insert(actions, {
			id = "QuickMelee",
			label = "QUICK MELEE",
			key = self:_getActionKeyLabel("QuickMelee", "F"),
			bindAction = "QuickMelee",
		})
	end

	if canQuickAbility then
		table.insert(actions, {
			id = "QuickAbility",
			label = "USE ABILITY",
			key = self:_getActionKeyLabel("Ability", "E"),
			bindAction = "Ability",
		})
	end

	return actions
end

function module:_populateActions(slotType)
	self:_clearActions()

	if not self._actionsListFrame or not self._actionsTemplate then
		return
	end

	local weaponData = slotType and self._weaponData[slotType]
	local actions = self:_getActionList(slotType, weaponData)

	for i, action in ipairs(actions) do
		local actionFrame = self._actionsTemplate:Clone()
		actionFrame.Name = "Action_" .. action.id
		actionFrame.Visible = true
		actionFrame.LayoutOrder = i
		actionFrame.Parent = self._actionsListFrame

		local contentFrame = actionFrame:FindFirstChild("ContentFrame")
		local actionLabel = contentFrame and contentFrame:FindFirstChild("ActionLabel")
		if actionLabel and actionLabel:IsA("TextLabel") then
			actionLabel.Text = action.label
		end

		local inputFrame = nil
		local legacyInputFrame = nil
		if contentFrame then
			for _, child in ipairs(contentFrame:GetChildren()) do
				if child.Name == "InputFrame" then
					if child:IsA("ImageLabel") then
						inputFrame = child
						break
					elseif child:IsA("Frame") and not legacyInputFrame then
						legacyInputFrame = child
					end
				end
			end
		end
		if not inputFrame then
			inputFrame = legacyInputFrame
		end
		if legacyInputFrame and inputFrame ~= legacyInputFrame then
			legacyInputFrame.Visible = false
		end

		local keyContainer = inputFrame and inputFrame:IsA("Frame") and inputFrame:FindFirstChild("KeyboardImageLabel")
			or nil
		local keyLabel = keyContainer and keyContainer:FindFirstChild("ActionLabel")
		local boundInput = action.bindAction and self:_getActionBind(action.bindAction) or nil
		local inputIcon = getInputIconAsset(boundInput)

		if inputFrame and inputFrame:IsA("ImageLabel") then
			if inputIcon then
				inputFrame.Image = inputIcon
				inputFrame.Visible = true
			else
				inputFrame.Visible = false
			end
		elseif keyContainer and keyContainer:IsA("ImageLabel") then
			local iconImage = keyContainer:FindFirstChild("Icon")
			if iconImage and not iconImage:IsA("ImageLabel") then
				iconImage:Destroy()
				iconImage = nil
			end
			if not iconImage then
				iconImage = Instance.new("ImageLabel")
				iconImage.Name = "Icon"
				iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
				iconImage.BackgroundTransparency = 1
				iconImage.BorderSizePixel = 0
				iconImage.Position = UDim2.fromScale(0.5, 0.5)
				iconImage.Size = UDim2.fromScale(0.85, 0.85)
				iconImage.ZIndex = keyContainer.ZIndex + 1
				iconImage.Parent = keyContainer
			end

			if inputIcon then
				iconImage.Image = inputIcon
				iconImage.Visible = true
				if keyLabel and keyLabel:IsA("TextLabel") then
					keyLabel.Visible = false
				end
			else
				iconImage.Visible = false
				if keyLabel and keyLabel:IsA("TextLabel") then
					keyLabel.Visible = true
					keyLabel.Text = action.key
				end
			end
		elseif keyLabel and keyLabel:IsA("TextLabel") then
			keyLabel.Text = action.key
		end
	end
end

function module:_animateItemDesc()
	if not self._itemDescActions or not self._itemDescOriginalPos then
		return
	end

	cancelTweens("item_desc")

	local startPos = UDim2.new(
		self._itemDescOriginalPos.X.Scale + TweenConfig.Values.ItemDescOffset,
		self._itemDescOriginalPos.X.Offset,
		self._itemDescOriginalPos.Y.Scale,
		self._itemDescOriginalPos.Y.Offset
	)

	self._itemDescActions.Position = startPos
	self._itemDescActions.GroupTransparency = 1

	local tween = TweenService:Create(self._itemDescActions, TweenConfig.get("ItemDesc", "show"), {
		Position = self._itemDescOriginalPos,
		GroupTransparency = 0,
	})
	tween:Play()
	currentTweens["item_desc"] = { tween }
end

function module:_hideItemDesc()
	if not self._itemDescActions or not self._itemDescOriginalPos then
		return
	end

	cancelTweens("item_desc")

	local startPos = UDim2.new(
		self._itemDescOriginalPos.X.Scale + TweenConfig.Values.ItemDescOffset,
		self._itemDescOriginalPos.X.Offset,
		self._itemDescOriginalPos.Y.Scale,
		self._itemDescOriginalPos.Y.Offset
	)

	local tween = TweenService:Create(self._itemDescActions, TweenConfig.get("ItemDesc", "hide"), {
		Position = startPos,
		GroupTransparency = 1,
	})
	tween:Play()
	currentTweens["item_desc"] = { tween }
end

function module:_setHealthBar(health, maxHealth, instant)
	local percent = math.clamp(health / maxHealth, 0, 1)
	local newOffset = calculateGradientOffset(percent)
	local newColor = getHealthColor(percent)

	self._healthText.Text = math.floor(health) .. "/" .. math.floor(maxHealth)

	local mainGradient = self._healthBar.Image.UIGradient
	local whiteGradient = self._healthBar.White.UIGradient

	if instant then
		mainGradient.Offset = newOffset
		whiteGradient.Offset = newOffset
		self._healthBar.Image.ImageColor3 = newColor
		return
	end

	cancelTweens("health_main")
	cancelTweens("health_white")
	cancelTweens("health_color")

	local mainTween = TweenService:Create(mainGradient, TweenConfig.get("Bar", "main"), {
		Offset = newOffset,
	})
	mainTween:Play()
	currentTweens["health_main"] = { mainTween }

	local colorTween = TweenService:Create(self._healthBar.Image, TweenConfig.get("Bar", "main"), {
		ImageColor3 = newColor,
	})
	colorTween:Play()
	currentTweens["health_color"] = { colorTween }

	task.delay(TweenConfig.getDelay("WhiteBar"), function()
		if not self._ui or not self._ui.Parent then
			return
		end

		cancelTweens("health_white")

		local whiteTween = TweenService:Create(whiteGradient, TweenConfig.get("Bar", "white"), {
			Offset = newOffset,
		})
		whiteTween:Play()
		currentTweens["health_white"] = { whiteTween }
	end)
end

function module:_setUltBar(ult, instant)
	local percent = math.clamp(ult / self._maxUlt, 0, 1)
	local newOffset = calculateGradientOffset(percent)

	local mainGradient = self._ultBar.Image.UIGradient
	local whiteGradient = self._ultBar.White.UIGradient

	if instant then
		mainGradient.Offset = newOffset
		whiteGradient.Offset = newOffset
		return
	end

	cancelTweens("ult_main")
	cancelTweens("ult_white")

	local mainTween = TweenService:Create(mainGradient, TweenConfig.get("Bar", "main"), {
		Offset = newOffset,
	})
	mainTween:Play()
	currentTweens["ult_main"] = { mainTween }

	task.delay(TweenConfig.getDelay("WhiteBar"), function()
		if not self._ui or not self._ui.Parent then
			return
		end

		cancelTweens("ult_white")

		local whiteTween = TweenService:Create(whiteGradient, TweenConfig.get("Bar", "white"), {
			Offset = newOffset,
		})
		whiteTween:Play()
		currentTweens["ult_white"] = { whiteTween }
	end)
end

function module:_setupHealthConnection()
	if not self._viewedPlayer then
		return
	end

	self._connections:cleanupGroup("hud_health")

	local function onHealthChanged()
		local health = self._viewedPlayer:GetAttribute("Health") or 100
		local maxHealth = self._viewedPlayer:GetAttribute("MaxHealth") or 100
		local previousHealth = self._currentHealth

		self._currentHealth = health
		self._currentMaxHealth = maxHealth

		self:_setHealthBar(health, maxHealth, false)

		if type(previousHealth) == "number" and health < previousHealth then
			self:_playHealthDamageShake()
		end
	end

	self._connections:track(self._viewedPlayer, "AttributeChanged", function(attributeName)
		if attributeName == "Health" or attributeName == "MaxHealth" then
			onHealthChanged()
		end
	end, "hud_health")

	onHealthChanged()
end

function module:_setupUltConnection()
	if not self._viewedPlayer then
		return
	end

	self._connections:cleanupGroup("hud_ult")

	local function onUltChanged()
		local ult = self._viewedPlayer:GetAttribute("Ultimate") or 0
		self._currentUlt = ult
		self:_setUltBar(ult, false)
	end

	self._connections:track(self._viewedPlayer, "AttributeChanged", function(attributeName)
		if attributeName == "Ultimate" then
			onUltChanged()
		end
	end, "hud_ult")

	onUltChanged()
end

function module:_refreshWeaponData()
	for _, slotType in SLOT_ORDER do
		self:_updateSlotData(slotType)
	end

	local selectedSlot = nil
	if self._viewedPlayer and self._viewedPlayer:GetAttribute("DisplaySlot") == "Ability" then
		selectedSlot = "Kit"
	else
		selectedSlot = self._viewedPlayer and self._viewedPlayer:GetAttribute("EquippedSlot")
		if not selectedSlot then
			selectedSlot = "Primary"
		end
	end
	self:_setSelectedSlot(selectedSlot)
end

function module:_updateSlotData(slotType)
	local data
	if slotType == "Kit" then
		data = self:getKitData()
		-- Fallback to PlayerDataTable if no KitData attribute (e.g., during loadout selection)
		if not data then
			local equipped = PlayerDataTable.getEquippedLoadout()
			local kitId = equipped and equipped.Kit
			if kitId then
				local kitConfig = KitConfig.getKit(kitId)
				if kitConfig then
					data = { Icon = kitConfig.Icon, Rarity = kitConfig.Rarity, Name = kitConfig.Name }
				end
			end
		end
	else
		data = self:getWeaponData(slotType)
		-- Fallback to PlayerDataTable if no *Data attribute (e.g., during loadout selection)
		if not data then
			local equipped = PlayerDataTable.getEquippedLoadout()
			local weaponId = equipped and equipped[slotType]
			if weaponId then
				local weaponConfig = LoadoutConfig.getWeapon(weaponId)
				if weaponConfig then
					data = { GunId = weaponId, Gun = weaponId }
				end
			end
		end
	end

	self._weaponData[slotType] = data

	self:_buildLoadoutTemplates()

	local templateData = self._weaponTemplates[slotType]
	if not templateData or not data then
		return
	end

	if slotType ~= "Kit" then
		local weaponId = data.GunId or data.Gun
		local imageId, rarityName = self:_getWeaponImage(weaponId)
		if imageId then
			local icon = templateData.template:FindFirstChild("Icon", true)
			if icon and icon:IsA("ImageLabel") then
				icon.Image = imageId
			end
		end

		if rarityName then
			local rarityColor = getRarityColor(rarityName)
			self:_applyRarity(templateData.template, rarityColor)
			if templateData.reloadBg and rarityColor then
				templateData.reloadBg.ImageColor3 = rarityColor
			end
		end
	else
		local iconHolder = templateData.template:FindFirstChild("IconHolder", true)
		if iconHolder then
			local icon = iconHolder:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				icon.Image = data.Icon or icon.Image
			end
		end

		local rarityInfo = data.Rarity and KitConfig.RarityInfo[data.Rarity]
		if rarityInfo then
			self:_applyRarity(templateData.template, rarityInfo.COLOR)
			if templateData.reloadBg then
				templateData.reloadBg.ImageColor3 = rarityInfo.COLOR
			end
		end
	end

	if slotType ~= "Kit" then
		self:_setupTemplateReloadState(templateData, data.Reloading == true, data.ReloadTime)
		self:_setupCooldownText(templateData, data.Reloading == true, data.ReloadTime)
		self:_setupCooldownBar(templateData, data.Reloading == true, data.ReloadTime)
	else
		local isOnCooldown = data.AbilityOnCooldown == true
		local cooldownTime = data.AbilityCooldownRemaining or data.AbilityCooldown
		self:_setupTemplateReloadState(templateData, isOnCooldown, cooldownTime)
		self:_setupCooldownText(templateData, isOnCooldown, cooldownTime)
		self:_setupCooldownBar(templateData, isOnCooldown, cooldownTime)
	end

	if self._selectedSlot == slotType and slotType ~= "Kit" then
		self:_updateItemDesc(data)
		self:_populateActions(slotType)
	end
end

function module:_setupWeaponConnections()
	if not self._viewedPlayer then
		return
	end

	self._connections:cleanupGroup("hud_weapons")

	self._connections:track(self._viewedPlayer, "AttributeChanged", function(attributeName)
		if attributeName == "SelectedLoadout" then
			if self:_syncFromSelectedLoadout() then
				self:_refreshWeaponData()
			end
			return
		end

		if attributeName == "EquippedSlot" then
			if self._viewedPlayer:GetAttribute("DisplaySlot") == "Ability" then
				self:_setSelectedSlot("Kit")
			else
				local slot = self._viewedPlayer:GetAttribute("EquippedSlot")
				if slot then
					self:_setSelectedSlot(slot)
				end
			end
			return
		end

		if attributeName == "DisplaySlot" then
			if self._viewedPlayer:GetAttribute("DisplaySlot") == "Ability" then
				self:_setSelectedSlot("Kit")
			else
				local slot = self._viewedPlayer:GetAttribute("EquippedSlot") or "Primary"
				self:_setSelectedSlot(slot)
			end
			return
		end

		if attributeName == "KitData" then
			self:_updateSlotData("Kit")
			return
		end

		for _, slotType in { "Primary", "Secondary", "Melee" } do
			if attributeName == slotType .. "Data" then
				self:_updateSlotData(slotType)
				return
			end
		end
	end, "hud_weapons")

	-- Keep quick-action key labels in sync when input platform changes
	-- (keyboard/mouse <-> controller).
	self._connections:track(UserInputService, "LastInputTypeChanged", function()
		local slot = self._selectedSlot
		if not slot and self._viewedPlayer then
			slot = self._viewedPlayer:GetAttribute("EquippedSlot") or "Primary"
		end

		if slot and slot ~= "Kit" then
			self:_populateActions(slot)
		end
	end, "hud_weapons")
end

function module:_setupBumperConnections()
	if not self._bumperLb and not self._bumperRb then
		return
	end

	self._connections:cleanupGroup("hud_bumpers")

	self:_updateBumperVisibility()

	self._connections:track(UserInputService, "LastInputTypeChanged", function()
		self:_updateBumperVisibility()
	end, "hud_bumpers")

	self._connections:track(UserInputService, "InputBegan", function(input)
		if not self:_isControllerActive() then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonL1 then
			self:_animateBumperPress("Lb")
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			self:_animateBumperPress("Rb")
		end
	end, "hud_bumpers")
end

function module:_setInitialState()
	local playerHolder = self._playerSpace.PlayerHolder
	local barHolders = self._playerSpace.BarHolders

	if self._itemHolderSpace and self._itemHolderOriginalPosition then
		if UserInputService.TouchEnabled then
			-- Hide bottom HUD bar on mobile; MobileControls shows compact ammo instead
			self._itemHolderSpace.Visible = false
		else
			self._itemHolderSpace.GroupTransparency = 1
			self._itemHolderSpace.Position = UDim2.new(
				self._itemHolderOriginalPosition.X.Scale,
				self._itemHolderOriginalPosition.X.Offset,
				self._itemHolderOriginalPosition.Y.Scale + 0.1,
				self._itemHolderOriginalPosition.Y.Offset
			)
		end
	end

	playerHolder.GroupTransparency = 1
	playerHolder.Position = UDim2.new(
		self._playerHolderOriginalPosition.X.Scale,
		self._playerHolderOriginalPosition.X.Offset,
		self._playerHolderOriginalPosition.Y.Scale + 0.1,
		self._playerHolderOriginalPosition.Y.Offset
	)

	barHolders.GroupTransparency = 1
	barHolders.Position = UDim2.new(
		self._barHoldersOriginalPosition.X.Scale,
		self._barHoldersOriginalPosition.X.Offset,
		self._barHoldersOriginalPosition.Y.Scale + 0.1,
		self._barHoldersOriginalPosition.Y.Offset
	)

	if self._counterFrame and self._counterOriginalPosition then
		if not self._counterHiddenPosition then
			self._counterHiddenPosition = self:_getCounterHiddenPosition()
		end
		self._counterFrame.Visible = true
		if self._counterHiddenPosition then
			self._counterFrame.Position = self._counterHiddenPosition
		end
	end
end

function module:_animateShow()
	local playerHolder = self._playerSpace.PlayerHolder
	local barHolders = self._playerSpace.BarHolders

	cancelTweens("show_player")
	cancelTweens("show_bars")
	cancelTweens("show_items")
	cancelTweens("show_counter")

	-- If loadout UI is open, don't animate player/bars/items (they should stay hidden)
	-- Only show the counter (score display)
	if self._loadoutUIOpen then
		self:ShowCounter()
		return nil
	end

	-- Training ground: skip counter (no score/timer needed)
	local hideCounterInTraining = self._hideCounterInTraining
	if hideCounterInTraining then
		self._hideCounterInTraining = false
	end

	-- Skip bottom bar animation on mobile (hidden; MobileControls shows compact ammo)
	if not UserInputService.TouchEnabled and self._itemHolderSpace and self._itemHolderOriginalPosition then
		local itemsTween = TweenService:Create(self._itemHolderSpace, TweenConfig.get("Main", "show"), {
			GroupTransparency = 0,
			Position = self._itemHolderOriginalPosition,
		})
		itemsTween:Play()
		currentTweens["show_items"] = { itemsTween }
	end

	local playerTween = TweenService:Create(playerHolder, TweenConfig.get("Main", "show"), {
		GroupTransparency = 0,
		Position = self._playerHolderOriginalPosition,
	})
	playerTween:Play()
	currentTweens["show_player"] = { playerTween }

	task.delay(TweenConfig.getDelay("Stagger"), function()
		if not self._ui or not self._ui.Parent then
			return
		end

		cancelTweens("show_bars")

		local barsTween = TweenService:Create(barHolders, TweenConfig.get("Main", "show"), {
			GroupTransparency = 0,
			Position = self._barHoldersOriginalPosition,
		})
		barsTween:Play()
		currentTweens["show_bars"] = { barsTween }
	end)

	if hideCounterInTraining then
		self:HideCounter()
	else
		self:ShowCounter()
	end

	return playerTween
end

function module:_animateHide()
	local playerHolder = self._playerSpace.PlayerHolder
	local barHolders = self._playerSpace.BarHolders

	cancelTweens("show_player")
	cancelTweens("show_bars")
	cancelTweens("show_items")
	cancelTweens("show_counter")

	-- Skip bottom bar on mobile (already hidden)
	if not UserInputService.TouchEnabled and self._itemHolderSpace and self._itemHolderOriginalPosition then
		local targetItemsPos = UDim2.new(
			self._itemHolderOriginalPosition.X.Scale,
			self._itemHolderOriginalPosition.X.Offset,
			self._itemHolderOriginalPosition.Y.Scale + 0.1,
			self._itemHolderOriginalPosition.Y.Offset
		)

		local itemsTween = TweenService:Create(self._itemHolderSpace, TweenConfig.get("Main", "hide"), {
			GroupTransparency = 1,
			Position = targetItemsPos,
		})
		itemsTween:Play()
		currentTweens["show_items"] = { itemsTween }
	end

	local targetPlayerPos = UDim2.new(
		self._playerHolderOriginalPosition.X.Scale,
		self._playerHolderOriginalPosition.X.Offset,
		self._playerHolderOriginalPosition.Y.Scale + 0.1,
		self._playerHolderOriginalPosition.Y.Offset
	)

	local targetBarsPos = UDim2.new(
		self._barHoldersOriginalPosition.X.Scale,
		self._barHoldersOriginalPosition.X.Offset,
		self._barHoldersOriginalPosition.Y.Scale + 0.1,
		self._barHoldersOriginalPosition.Y.Offset
	)

	local playerTween = TweenService:Create(playerHolder, TweenConfig.get("Main", "hide"), {
		GroupTransparency = 1,
		Position = targetPlayerPos,
	})
	playerTween:Play()
	currentTweens["show_player"] = { playerTween }

	local barsTween = TweenService:Create(barHolders, TweenConfig.get("Main", "hide"), {
		GroupTransparency = 1,
		Position = targetBarsPos,
	})
	barsTween:Play()
	currentTweens["show_bars"] = { barsTween }

	self:HideCounter()

	return barsTween
end

function module:_init()
	if self._initialized then
		self:_setupHealthConnection()
		self:_setupUltConnection()
		self:_setupWeaponConnections()
		self:_refreshWeaponData()
		self:_updateBumperVisibility()
		self:_setupControlsBindingListener()
		return
	end

	self._initialized = true

	self:_buildLoadoutTemplates()
	self:_setupHealthConnection()
	self:_setupUltConnection()
	self:_setupWeaponConnections()
	self:_refreshWeaponData()
	self:_setupBumperConnections()
	self:_setupControlsBindingListener()
end

function module:show()
	if not self._viewedPlayer then
		self._viewedPlayer = Players.LocalPlayer
	end

	-- Prefer the real server-selected loadout (Option A: show HUD on StartMatch).
	-- Fallback to mock data only if SelectedLoadout isn't available (studio/UI testing).
	if not self:_syncFromSelectedLoadout() then
		self:_initPlayerData()
	end
	self:_updatePlayerThumbnail()

	local health = self._viewedPlayer:GetAttribute("Health") or 100
	local maxHealth = self._viewedPlayer:GetAttribute("MaxHealth") or 100
	local ult = self._viewedPlayer:GetAttribute("Ultimate") or 0

	self:_setHealthBar(health, maxHealth, true)
	self:_setUltBar(ult, true)

	self._ui.Visible = true

	if self._killfeedContainer then
		self._killfeedContainer.Visible = true
	end

	self:_setInitialState()
	self:_animateShow()

	self:_init()

	-- Re-populate match teams if we have cached team data (e.g., showing HUD after round reset)
	local hasTeamData = (self._matchTeam1 and #self._matchTeam1 > 0) or (self._matchTeam2 and #self._matchTeam2 > 0)
	local slotsEmpty = (not self._yourTeamSlots or #self._yourTeamSlots == 0)
		and (not self._enemyTeamSlots or #self._enemyTeamSlots == 0)
	if hasTeamData and slotsEmpty then
		self:_populateMatchTeams()
	end

	return true
end

function module:hide()
	local lastTween = self:_animateHide()

	if lastTween then
		lastTween.Completed:Wait()
	end

	self._ui.Visible = false

	return true
end

function module:_cleanup()
	self._initialized = false
	self:_stopCounterTimer(false)

	self._connections:cleanupGroup("hud_health")
	self._connections:cleanupGroup("hud_ult")
	self._connections:cleanupGroup("hud_weapons")
	self._connections:cleanupGroup("hud_bumpers")
	if self._controlsChangedDisconnect then
		self._controlsChangedDisconnect()
		self._controlsChangedDisconnect = nil
	end

	for slotType in self._cooldownThreads do
		self:_cancelCooldownThread(slotType)
	end
	table.clear(self._cooldownThreads)

	for _, tweens in currentTweens do
		for _, tween in tweens do
			tween:Cancel()
		end
	end
	table.clear(currentTweens)

	-- Do NOT clear live player attributes here (health/loadout may be owned by gameplay).
	self:_clearTemplates()
	-- Do NOT clear match teams here - only clear on ReturnToLobby event
	-- self:_clearMatchTeams()

	self._weaponData = {}
	self._selectedSlot = nil
	self._healthShakeToken += 1
	self._counterPlayerByUserId = {}
	self._counterPlayerStateByUserId = {}

	self._viewedPlayer = nil
	self._viewedCharacter = nil
end

-- Force trigger cooldown animation for a slot (for melee specials, etc.)
-- slotType: "Primary", "Secondary", "Melee", or "Kit"
-- duration: cooldown duration in seconds
function module:ForceCooldown(slotType: string, duration: number)
	if not slotType or not duration then
		return
	end

	local templateData = self._weaponTemplates[slotType]
	if not templateData then
		return
	end

	self:_setupTemplateReloadState(templateData, true, duration)
	self:_setupCooldownText(templateData, true, duration)
	self:_setupCooldownBar(templateData, true, duration)
end

-- Clear all loadout slots (Kit, Primary, Secondary, Melee)
-- Destroys UI templates, cancels tweens/cooldowns, and resets ALL state
function module:ClearLoadoutSlots()
	-- Cancel all cooldown threads
	for slotType in self._cooldownThreads do
		self:_cancelCooldownThread(slotType)
	end
	table.clear(self._cooldownThreads)

	-- Cancel all slot-related tweens
	for _, slotType in SLOT_ORDER do
		cancelTweens("select_" .. slotType)
		cancelTweens("reload_" .. slotType)
		cancelTweens("cooldown_text_" .. slotType)
		cancelTweens("cooldown_bar_" .. slotType)
	end
	cancelTweens("item_desc")

	-- Destroy all weapon templates
	self:_clearTemplates()

	-- Clear weapon data cache
	table.clear(self._weaponData)

	-- Reset selected slot
	self._selectedSlot = nil

	-- Hide item description
	self:_hideItemDesc()

	-- Clear actions list
	self:_clearActions()

	-- Clear player weapon attributes if we have a viewed player
	if self._viewedPlayer then
		for _, slotType in { "Primary", "Secondary", "Melee" } do
			self._viewedPlayer:SetAttribute(slotType .. "Data", nil)
		end
		self._viewedPlayer:SetAttribute("KitData", nil)
		self._viewedPlayer:SetAttribute("EquippedSlot", nil)
		self._viewedPlayer:SetAttribute("DisplaySlot", nil)
	end
	
end

-- Rebuild all loadout slots from current player data
-- Optionally pass a loadout table to override current equipped loadout
-- Resets ult bar to 0 if kit changed from last round
function module:RebuildLoadoutSlots(loadoutOverride: {[string]: string}?)
	if not self._viewedPlayer then
		self._viewedPlayer = Players.LocalPlayer
	end

	-- FORCE clear templates and weapon data so they get recreated with new icons
	-- This is necessary because show() may have already rebuilt templates with old data
	self:_clearTemplates()
	table.clear(self._weaponData)

	local newKitId = nil

	-- If loadout override provided, apply it first
	if loadoutOverride then
		newKitId = loadoutOverride.Kit
		
		if newKitId then
			local kitData = KitConfig.buildKitData(newKitId, { abilityCooldownEndsAt = 0, ultimate = 0 })
			self._viewedPlayer:SetAttribute("KitData", kitData and HttpService:JSONEncode(kitData) or nil)
		end

		for _, slotType in { "Primary", "Secondary", "Melee" } do
			local weaponId = loadoutOverride[slotType]
			local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)

			if weaponConfig then
				local weaponData = {
					Gun = weaponConfig.name,
					GunId = weaponConfig.id,
					GunType = weaponConfig.weaponType,
					Ammo = weaponConfig.clipSize,
					MaxAmmo = weaponConfig.maxAmmo,
					ClipSize = weaponConfig.clipSize,
					Reloading = false,
					OnCooldown = false,
					Cooldown = weaponConfig.cooldown or 0,
					ReloadTime = weaponConfig.reloadTime or 0,
					Rarity = weaponConfig.rarity,
				}
				self._viewedPlayer:SetAttribute(slotType .. "Data", HttpService:JSONEncode(weaponData))
			else
				self._viewedPlayer:SetAttribute(slotType .. "Data", nil)
			end
		end
	else
		-- Try syncing from server's SelectedLoadout first
		if not self:_syncFromSelectedLoadout() then
			-- Fall back to PlayerDataTable equipped loadout
			self:_initPlayerData()
		end
		
		-- Get the kit ID from the loaded data
		local kitData = self:getKitData()
		newKitId = kitData and kitData.KitId
	end

	-- Check if kit changed and reset ult bar
	if newKitId and newKitId ~= self._lastKitId then
		self._viewedPlayer:SetAttribute("Ultimate", 0)
		self:_setUltBar(0, true)
	end
	self._lastKitId = newKitId

	-- Set default equipped slot
	if not self._viewedPlayer:GetAttribute("EquippedSlot") then
		self._viewedPlayer:SetAttribute("EquippedSlot", "Primary")
	end

	-- Rebuild templates and refresh UI
	self:_buildLoadoutTemplates()
	self:_refreshWeaponData()

	-- Update bumper visibility for controller support
	self:_updateBumperVisibility()
	
end

-- Reset ult bar to 0 (call when kit changes between rounds)
function module:ResetUltBar()
	if self._viewedPlayer then
		self._viewedPlayer:SetAttribute("Ultimate", 0)
	end
	self:_setUltBar(0, true)
end

-- Cache the Desc round-result UI elements from the HUD
function module:_cacheRoundUI()
	local desc = self._ui:FindFirstChild("Desc", true)
	if not desc then return end

	self._roundDesc = desc
	self._roundDescOriginalPos = desc.Position

	local holder = desc:FindFirstChild("Holder")
	if not holder then return end
	self._roundHolder = holder

	local lw = holder:FindFirstChild("LW")
	if not lw then return end
	self._roundLW = lw
	self._roundLWOriginalPos = lw.Position

	-- Direct TextLabel child of LW is the "ROUND" label
	self._roundTextLabel = lw:FindFirstChild("TextLabel")
	if self._roundTextLabel then
		self._roundTextLabelOriginalPos = self._roundTextLabel.Position
	end

	self._roundRigh = lw:FindFirstChild("Righ")
	if self._roundRigh then
		self._roundRighOriginalPos = self._roundRigh.Position
	end

	self._roundLeft = lw:FindFirstChild("Left")
	if self._roundLeft then
		self._roundLeftOriginalPos = self._roundLeft.Position
	end

	self._roundBar = lw:FindFirstChild("Frame")
	self._roundTimer = holder:FindFirstChild("Timer")
end

-- Show the round-end result screen with animation.
-- outcome: "win", "lose", or "draw"
function module:RoundEnd(outcome)
	if not self._roundDesc then return end

	cancelTweens("round_end")
	cancelTweens("round_shake")
	cancelTweens("round_text_fade")
	cancelTweens("round_start")
	cancelTweens("round_hide")
	-- Also cancel storm tweens so storm notification doesn't persist
	cancelTweens("storm_entrance")
	cancelTweens("storm_shake")
	cancelTweens("storm_hide")

	-- Resolve color and text
	local barColor, outcomeText
	if outcome == "win" then
		barColor = WIN_COLOR
		outcomeText = "WON"
	elseif outcome == "lose" then
		barColor = LOSE_COLOR
		outcomeText = "LOST"
	else
		barColor = DRAW_COLOR
		outcomeText = "DRAW"
	end

	-- ALWAYS reset main label to "ROUND" (in case StormStarted set it to "STORM")
	if self._roundTextLabel then
		self._roundTextLabel.Text = "ROUND"
		self._roundTextLabel.TextColor3 = Color3.fromRGB(229, 229, 229) -- Reset to default color
	end

	-- Update the outcome text inside Left and Righ canvas groups
	if self._roundRigh then
		local label = self._roundRigh:FindFirstChildWhichIsA("TextLabel")
		if label then label.Text = outcomeText end
	end
	if self._roundLeft then
		local label = self._roundLeft:FindFirstChildWhichIsA("TextLabel")
		if label then label.Text = outcomeText end
	end

	-- Apply outcome color to the bar
	if self._roundBar then
		self._roundBar.BackgroundColor3 = barColor
	end

	self._roundDesc.Visible = true

	local textLabel = self._roundTextLabel
	local righ = self._roundRigh
	local left = self._roundLeft

	-- Set start positions for the entrance animation
	if textLabel then
		-- Start high above origin as specified
		textLabel.Position = UDim2.new(0.507, 0, -0.329, 0)
		textLabel.TextTransparency = 1
	end
	if righ then
		-- Start below origin
		local orig = self._roundRighOriginalPos
		righ.Position = UDim2.new(orig.X.Scale, orig.X.Offset, orig.Y.Scale + 0.55, orig.Y.Offset)
		righ.GroupTransparency = 1
	end
	if left then
		-- Start above origin
		local orig = self._roundLeftOriginalPos
		left.Position = UDim2.new(orig.X.Scale, orig.X.Offset, orig.Y.Scale - 0.55, orig.Y.Offset)
		left.GroupTransparency = 1
	end

	-- Phase 1: Smooth slide in + fade in
	local slideInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInfo  = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local entranceTweens = {}

	if textLabel then
		local t1 = TweenService:Create(textLabel, slideInfo, { Position = self._roundTextLabelOriginalPos })
		local t2 = TweenService:Create(textLabel, fadeInfo,  { TextTransparency = 0.35 })
		t1:Play()
		t2:Play()
		table.insert(entranceTweens, t1)
		table.insert(entranceTweens, t2)
	end
	if righ then
		local t = TweenService:Create(righ, slideInfo, {
			Position = self._roundRighOriginalPos,
			GroupTransparency = 0,
		})
		t:Play()
		table.insert(entranceTweens, t)
	end
	if left then
		local t = TweenService:Create(left, slideInfo, {
			Position = self._roundLeftOriginalPos,
			GroupTransparency = 0,
		})
		t:Play()
		table.insert(entranceTweens, t)
	end

	currentTweens["round_end"] = entranceTweens

	-- Phase 2: Shake (separate task that can exit early)
	task.spawn(function()
		task.wait(0.35)

		-- Gentle shake
		local lw = self._roundLW
		if lw and self._roundLWOriginalPos then
			local lwOrigPos = self._roundLWOriginalPos

			self._roundShakeToken += 1
			local shakeToken = self._roundShakeToken

			cancelTweens("round_shake")

			for _ = 1, ROUND_SHAKE_STEPS do
				if self._roundShakeToken ~= shakeToken then break end
				if not self._roundDesc or not self._roundDesc.Parent then break end

				local xOff = roundShakeRandom:NextInteger(-ROUND_SHAKE_X_RANGE, ROUND_SHAKE_X_RANGE)
				local yOff = roundShakeRandom:NextInteger(-ROUND_SHAKE_Y_RANGE, ROUND_SHAKE_Y_RANGE)
				if xOff == 0 and yOff == 0 then yOff = 1 end

				local tween = TweenService:Create(lw, ROUND_SHAKE_TWEEN_INFO, {
					Position = withOffset(lwOrigPos, xOff, yOff),
				})
				currentTweens["round_shake"] = { tween }
				tween:Play()
				tween.Completed:Wait()
			end

			if self._roundShakeToken == shakeToken and lw and lw.Parent then
				lw.Position = lwOrigPos
			end
			currentTweens["round_shake"] = nil
		end
	end)

	-- Phase 3: Hold + Phase 4: Hide (ALWAYS runs after delay)
	task.delay(4.0, function()
		if not self._roundDesc or not self._roundDesc.Parent then return end

		cancelTweens("round_hide")

		-- Slower, smoother fade out including the color bar
		local hideInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local hideTweens = {}

		if textLabel then
			local t = TweenService:Create(textLabel, hideInfo, { TextTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end
		if righ then
			local t = TweenService:Create(righ, hideInfo, { GroupTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end
		if left then
			local t = TweenService:Create(left, hideInfo, { GroupTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end
		-- Fade out the color bar frame
		if self._roundBar then
			local t = TweenService:Create(self._roundBar, hideInfo, { BackgroundTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end

		currentTweens["round_hide"] = hideTweens

		task.wait(0.85)
		if self._roundDesc and self._roundDesc.Parent then
			self._roundDesc.Visible = false
			-- Reset transparencies for next time
			if self._roundBar then
				self._roundBar.BackgroundTransparency = 0
			end
			if righ then
				righ.GroupTransparency = 0
			end
			if left then
				left.GroupTransparency = 0
			end
		end
	end)
end

-- Show the round-start screen: fades down and in, bar is black.
-- @param roundNumber number - The round number to display (e.g., 1, 2, 3)
function module:RoundStart(roundNumber)
	if not self._roundDesc then return end

	cancelTweens("round_end")
	cancelTweens("round_shake")
	cancelTweens("round_text_fade")
	cancelTweens("round_start")
	cancelTweens("round_hide")
	-- Also cancel storm tweens so storm notification doesn't persist
	cancelTweens("storm_entrance")
	cancelTweens("storm_shake")
	cancelTweens("storm_hide")

	-- ALWAYS reset main label to "ROUND" (in case StormStarted set it to "STORM")
	if self._roundTextLabel then
		self._roundTextLabel.Text = "ROUND"
		self._roundTextLabel.TextColor3 = Color3.fromRGB(229, 229, 229) -- Reset to default color
	end

	-- Bar turns black for round start
	if self._roundBar then
		self._roundBar.BackgroundColor3 = ROUND_START_BAR_COLOR
	end

	-- Set the round number in Left and Right labels
	local roundText = tostring(roundNumber or 1)
	if self._roundRigh then
		local label = self._roundRigh:FindFirstChildWhichIsA("TextLabel")
		if label then label.Text = roundText end
	end
	if self._roundLeft then
		local label = self._roundLeft:FindFirstChildWhichIsA("TextLabel")
		if label then label.Text = roundText end
	end

	self._roundDesc.Visible = true

	local textLabel = self._roundTextLabel
	local righ      = self._roundRigh
	local left      = self._roundLeft
	local lw        = self._roundLW

	-- Start everything invisible and above origin (slide down into place)
	if textLabel then
		textLabel.Position = UDim2.new(0.507, 0, -0.329, 0)
		textLabel.TextTransparency = 1
	end
	if righ and self._roundRighOriginalPos then
		local orig = self._roundRighOriginalPos
		righ.Position = UDim2.new(orig.X.Scale, orig.X.Offset, orig.Y.Scale - 0.5, orig.Y.Offset)
		righ.GroupTransparency = 1
	end
	if left and self._roundLeftOriginalPos then
		local orig = self._roundLeftOriginalPos
		left.Position = UDim2.new(orig.X.Scale, orig.X.Offset, orig.Y.Scale - 0.5, orig.Y.Offset)
		left.GroupTransparency = 1
	end

	-- Phase 1: Smooth slide down + fade in
	local slideInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local startTweens = {}

	if textLabel then
		local t1 = TweenService:Create(textLabel, slideInfo, { Position = self._roundTextLabelOriginalPos })
		local t2 = TweenService:Create(textLabel, fadeInfo, { TextTransparency = 0.35 })
		t1:Play()
		t2:Play()
		table.insert(startTweens, t1)
		table.insert(startTweens, t2)
	end
	if righ then
		local t = TweenService:Create(righ, slideInfo, {
			Position = self._roundRighOriginalPos,
			GroupTransparency = 0,
		})
		t:Play()
		table.insert(startTweens, t)
	end
	if left then
		local t = TweenService:Create(left, slideInfo, {
			Position = self._roundLeftOriginalPos,
			GroupTransparency = 0,
		})
		t:Play()
		table.insert(startTweens, t)
	end

	currentTweens["round_start"] = startTweens

	-- Phase 2: Shake (separate task that can exit early)
	task.spawn(function()
		task.wait(0.35)

		-- Gentle shake
		if lw and self._roundLWOriginalPos then
			local lwOrigPos = self._roundLWOriginalPos
			self._roundShakeToken += 1
			local shakeToken = self._roundShakeToken

			cancelTweens("round_shake")

			for _ = 1, ROUND_SHAKE_STEPS do
				if self._roundShakeToken ~= shakeToken then break end
				if not self._roundDesc or not self._roundDesc.Parent then break end

				local xOff = roundShakeRandom:NextInteger(-ROUND_SHAKE_X_RANGE, ROUND_SHAKE_X_RANGE)
				local yOff = roundShakeRandom:NextInteger(-ROUND_SHAKE_Y_RANGE, ROUND_SHAKE_Y_RANGE)
				if xOff == 0 and yOff == 0 then yOff = 1 end

				local tween = TweenService:Create(lw, ROUND_SHAKE_TWEEN_INFO, {
					Position = withOffset(lwOrigPos, xOff, yOff),
				})
				currentTweens["round_shake"] = { tween }
				tween:Play()
				tween.Completed:Wait()
			end

			if self._roundShakeToken == shakeToken and lw and lw.Parent then
				lw.Position = lwOrigPos
			end
			currentTweens["round_shake"] = nil
		end
	end)

	-- Phase 3: Hide after hold (ALWAYS runs after delay)
	task.delay(2.0, function()
		if not self._roundDesc or not self._roundDesc.Parent then return end

		cancelTweens("round_hide")

		-- Slower, smoother fade out including the color bar
		local hideInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local hideTweens = {}

		if textLabel then
			local t = TweenService:Create(textLabel, hideInfo, { TextTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end
		if righ then
			local t = TweenService:Create(righ, hideInfo, { GroupTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end
		if left then
			local t = TweenService:Create(left, hideInfo, { GroupTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end
		-- Fade out the color bar frame
		if self._roundBar then
			local t = TweenService:Create(self._roundBar, hideInfo, { BackgroundTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end

		currentTweens["round_hide"] = hideTweens

		task.wait(0.85)
		if self._roundDesc and self._roundDesc.Parent then
			self._roundDesc.Visible = false
			-- Reset transparencies for next time
			if self._roundBar then
				self._roundBar.BackgroundTransparency = 0
			end
			if righ then
				righ.GroupTransparency = 0
			end
			if left then
				left.GroupTransparency = 0
			end
		end
	end)
end

-- Show "STORM INCOMING" announcement with purple bar and red text
-- Uses separate "storm_" tween keys so it won't be cancelled by RoundEnd/RoundStart
function module:StormStarted()
	if not self._roundDesc then return end

	-- Cancel any existing round/storm animations
	cancelTweens("round_end")
	cancelTweens("round_shake")
	cancelTweens("round_text_fade")
	cancelTweens("round_start")
	cancelTweens("round_hide")
	cancelTweens("storm_entrance")
	cancelTweens("storm_shake")
	cancelTweens("storm_hide")

	-- Purple bar for storm
	if self._roundBar then
		self._roundBar.BackgroundColor3 = STORM_BAR_COLOR
		self._roundBar.BackgroundTransparency = 0
	end

	-- Set "INCOMING" text in Left and Right labels
	if self._roundRigh then
		local label = self._roundRigh:FindFirstChildWhichIsA("TextLabel")
		if label then label.Text = "INCOMING" end
	end
	if self._roundLeft then
		local label = self._roundLeft:FindFirstChildWhichIsA("TextLabel")
		if label then label.Text = "INCOMING" end
	end

	-- Set "STORM" text with red color
	if self._roundTextLabel then
		self._roundTextLabel.Text = "STORM"
		self._roundTextLabel.TextColor3 = STORM_TEXT_COLOR
	end

	self._roundDesc.Visible = true

	local textLabel = self._roundTextLabel
	local righ      = self._roundRigh
	local left      = self._roundLeft
	local lw        = self._roundLW

	-- Start everything invisible and above origin (slide down into place)
	if textLabel then
		textLabel.Position = UDim2.new(0.507, 0, -0.329, 0)
		textLabel.TextTransparency = 1
	end
	if righ and self._roundRighOriginalPos then
		local orig = self._roundRighOriginalPos
		righ.Position = UDim2.new(orig.X.Scale, orig.X.Offset, orig.Y.Scale - 0.5, orig.Y.Offset)
		righ.GroupTransparency = 1
	end
	if left and self._roundLeftOriginalPos then
		local orig = self._roundLeftOriginalPos
		left.Position = UDim2.new(orig.X.Scale, orig.X.Offset, orig.Y.Scale - 0.5, orig.Y.Offset)
		left.GroupTransparency = 1
	end

	-- Phase 1: Smooth slide down + fade in (using storm-specific key)
	local slideInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local entranceTweens = {}

	if textLabel then
		local t1 = TweenService:Create(textLabel, slideInfo, { Position = self._roundTextLabelOriginalPos })
		local t2 = TweenService:Create(textLabel, fadeInfo, { TextTransparency = 0.35 })
		t1:Play()
		t2:Play()
		table.insert(entranceTweens, t1)
		table.insert(entranceTweens, t2)
	end
	if righ then
		local t = TweenService:Create(righ, slideInfo, {
			Position = self._roundRighOriginalPos,
			GroupTransparency = 0,
		})
		t:Play()
		table.insert(entranceTweens, t)
	end
	if left then
		local t = TweenService:Create(left, slideInfo, {
			Position = self._roundLeftOriginalPos,
			GroupTransparency = 0,
		})
		t:Play()
		table.insert(entranceTweens, t)
	end

	-- Store in storm-specific key so RoundEnd won't cancel it
	currentTweens["storm_entrance"] = entranceTweens

	-- Phase 2: Shake (separate task, uses storm-specific key)
	task.spawn(function()
		task.wait(0.35)

		-- Gentle shake
		if lw and self._roundLWOriginalPos then
			local lwOrigPos = self._roundLWOriginalPos
			self._roundShakeToken += 1
			local shakeToken = self._roundShakeToken

			cancelTweens("storm_shake")

			for _ = 1, ROUND_SHAKE_STEPS do
				if self._roundShakeToken ~= shakeToken then break end
				if not self._roundDesc or not self._roundDesc.Parent then break end

				local xOff = roundShakeRandom:NextInteger(-ROUND_SHAKE_X_RANGE, ROUND_SHAKE_X_RANGE)
				local yOff = roundShakeRandom:NextInteger(-ROUND_SHAKE_Y_RANGE, ROUND_SHAKE_Y_RANGE)
				if xOff == 0 and yOff == 0 then yOff = 1 end

				local tween = TweenService:Create(lw, ROUND_SHAKE_TWEEN_INFO, {
					Position = withOffset(lwOrigPos, xOff, yOff),
				})
				currentTweens["storm_shake"] = { tween }
				tween:Play()
				tween.Completed:Wait()
			end

			if self._roundShakeToken == shakeToken and lw and lw.Parent then
				lw.Position = lwOrigPos
			end
			currentTweens["storm_shake"] = nil
		end
	end)

	-- Phase 3: Hide after hold (ALWAYS runs after delay - uses storm-specific key)
	task.delay(3.5, function()
		if not self._roundDesc or not self._roundDesc.Parent then return end

		cancelTweens("storm_hide")

		-- Slower, smoother fade out including the color bar
		local hideInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		local hideTweens = {}

		if textLabel then
			local t = TweenService:Create(textLabel, hideInfo, { TextTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end
		if righ then
			local t = TweenService:Create(righ, hideInfo, { GroupTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end
		if left then
			local t = TweenService:Create(left, hideInfo, { GroupTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end
		-- Fade out the color bar frame
		if self._roundBar then
			local t = TweenService:Create(self._roundBar, hideInfo, { BackgroundTransparency = 1 })
			t:Play()
			table.insert(hideTweens, t)
		end

		currentTweens["storm_hide"] = hideTweens

		task.wait(0.85)
		if self._roundDesc and self._roundDesc.Parent then
			self._roundDesc.Visible = false
			-- Reset transparencies for next time
			if self._roundBar then
				self._roundBar.BackgroundTransparency = 0
			end
			if righ then
				righ.GroupTransparency = 0
			end
			if left then
				left.GroupTransparency = 0
			end
			-- Reset text color back to default for other uses
			if textLabel then
				textLabel.TextColor3 = Color3.fromRGB(229, 229, 229)
			end
		end
	end)
end

return module
