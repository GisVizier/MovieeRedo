local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

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

local SLOT_ORDER = {"Kit", "Primary", "Secondary", "Melee"}

local HEALTH_COLORS = {
	{threshold = 0.6, color = Color3.fromRGB(70, 250, 126)},
	{threshold = 0.35, color = Color3.fromRGB(250, 220, 70)},
	{threshold = 0.2, color = Color3.fromRGB(250, 150, 50)},
	{threshold = 0, color = Color3.fromRGB(250, 70, 70)},
}

local currentTweens = {}

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

	local playerSpace = ui:FindFirstChild("PlayerSpace")
	if not playerSpace then
		warn("[HUD] PlayerSpace not found in UI - make sure the UI structure exists")
		return self
	end

	self._playerSpace = playerSpace
	
	local barHolders = playerSpace:FindFirstChild("BarHolders")
	if barHolders then
		local healthBarHolder = barHolders:FindFirstChild("HealthBarHolder")
		if healthBarHolder then
			self._healthBar = healthBarHolder:FindFirstChild("HealthBar")
			self._healthText = healthBarHolder:FindFirstChild("Text")
		end
		
		local ultBarHolder = barHolders:FindFirstChild("UltBarHolder")
		if ultBarHolder then
			self._ultBar = ultBarHolder:FindFirstChild("Bar")
		end
	end

	local playerHolder = playerSpace:FindFirstChild("PlayerHolder")
	if playerHolder then
		local holder = playerHolder:FindFirstChild("Holder")
		if holder then
			local rotHolder = holder:FindFirstChild("RotHolder")
			if rotHolder then
				self._playerImage = rotHolder:FindFirstChild("PlayerImage")
			end
		end
		self._playerHolderOriginalPosition = playerHolder.Position
	end

	if barHolders then
		self._barHoldersOriginalPosition = barHolders.Position
	end

	self:_cacheWeaponUI()

	return self
end

function module:_cacheWeaponUI()
	self._itemHolderSpace = self._ui:FindFirstChild("ItemHolderSpace", true)
	if not self._itemHolderSpace then
		return
	end

	self._itemHolderOriginalPosition = self._itemHolderSpace.Position

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
	end
end

function module:setViewedPlayer(player, character)
	self._viewedPlayer = player
	self._viewedCharacter = character
end

function module:showForPlayer(player, character)
	self:setViewedPlayer(player, character)
	self._export:show()
end

function module:_updatePlayerThumbnail()
	if not self._viewedPlayer or not self._playerImage then
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

	player:SetAttribute("Health", 100)
	player:SetAttribute("MaxHealth", 100)
	player:SetAttribute("Ultimate", 0)
	player:SetAttribute("EquippedSlot", "Primary")
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
end

function module:_setHealthBar(health, maxHealth, instant)
	if not self._healthBar or not self._healthText then
		return
	end

	local percent = math.clamp(health / maxHealth, 0, 1)
	local newOffset = calculateGradientOffset(percent)
	local newColor = getHealthColor(percent)

	self._healthText.Text = math.floor(health) .. "/" .. math.floor(maxHealth)

	local imageLabel = self._healthBar:FindFirstChild("Image")
	local whiteLabel = self._healthBar:FindFirstChild("White")
	
	if not imageLabel or not whiteLabel then
		return
	end

	local mainGradient = imageLabel:FindFirstChild("UIGradient")
	local whiteGradient = whiteLabel:FindFirstChild("UIGradient")

	if not mainGradient or not whiteGradient then
		return
	end

	if instant then
		mainGradient.Offset = newOffset
		whiteGradient.Offset = newOffset
		imageLabel.ImageColor3 = newColor
		return
	end

	cancelTweens("health_main")
	cancelTweens("health_white")
	cancelTweens("health_color")

	local mainTween = TweenService:Create(mainGradient, TweenConfig.get("Bar", "main"), {
		Offset = newOffset,
	})
	mainTween:Play()
	currentTweens["health_main"] = {mainTween}

	local colorTween = TweenService:Create(imageLabel, TweenConfig.get("Bar", "main"), {
		ImageColor3 = newColor,
	})
	colorTween:Play()
	currentTweens["health_color"] = {colorTween}

	task.delay(TweenConfig.getDelay("WhiteBar"), function()
		if not self._ui or not self._ui.Parent then
			return
		end

		cancelTweens("health_white")

		local whiteTween = TweenService:Create(whiteGradient, TweenConfig.get("Bar", "white"), {
			Offset = newOffset,
		})
		whiteTween:Play()
		currentTweens["health_white"] = {whiteTween}
	end)
end

function module:_setUltBar(ult, instant)
	if not self._ultBar then
		return
	end

	local percent = math.clamp(ult / self._maxUlt, 0, 1)
	local newOffset = calculateGradientOffset(percent)

	local imageLabel = self._ultBar:FindFirstChild("Image")
	local whiteLabel = self._ultBar:FindFirstChild("White")
	
	if not imageLabel or not whiteLabel then
		return
	end

	local mainGradient = imageLabel:FindFirstChild("UIGradient")
	local whiteGradient = whiteLabel:FindFirstChild("UIGradient")

	if not mainGradient or not whiteGradient then
		return
	end

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
	currentTweens["ult_main"] = {mainTween}

	task.delay(TweenConfig.getDelay("WhiteBar"), function()
		if not self._ui or not self._ui.Parent then
			return
		end

		cancelTweens("ult_white")

		local whiteTween = TweenService:Create(whiteGradient, TweenConfig.get("Bar", "white"), {
			Offset = newOffset,
		})
		whiteTween:Play()
		currentTweens["ult_white"] = {whiteTween}
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

		self._currentHealth = health
		self._currentMaxHealth = maxHealth

		self:_setHealthBar(health, maxHealth, false)
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

function module:_setInitialState()
	if not self._playerSpace then
		return
	end

	local playerHolder = self._playerSpace:FindFirstChild("PlayerHolder")
	local barHolders = self._playerSpace:FindFirstChild("BarHolders")

	if self._itemHolderSpace and self._itemHolderOriginalPosition then
		self._itemHolderSpace.GroupTransparency = 1
		self._itemHolderSpace.Position = UDim2.new(
			self._itemHolderOriginalPosition.X.Scale,
			self._itemHolderOriginalPosition.X.Offset,
			self._itemHolderOriginalPosition.Y.Scale + 0.1,
			self._itemHolderOriginalPosition.Y.Offset
		)
	end

	if playerHolder and self._playerHolderOriginalPosition then
		playerHolder.GroupTransparency = 1
		playerHolder.Position = UDim2.new(
			self._playerHolderOriginalPosition.X.Scale,
			self._playerHolderOriginalPosition.X.Offset,
			self._playerHolderOriginalPosition.Y.Scale + 0.1,
			self._playerHolderOriginalPosition.Y.Offset
		)
	end

	if barHolders and self._barHoldersOriginalPosition then
		barHolders.GroupTransparency = 1
		barHolders.Position = UDim2.new(
			self._barHoldersOriginalPosition.X.Scale,
			self._barHoldersOriginalPosition.X.Offset,
			self._barHoldersOriginalPosition.Y.Scale + 0.1,
			self._barHoldersOriginalPosition.Y.Offset
		)
	end
end

function module:_animateShow()
	if not self._playerSpace then
		return nil
	end

	local playerHolder = self._playerSpace:FindFirstChild("PlayerHolder")
	local barHolders = self._playerSpace:FindFirstChild("BarHolders")

	cancelTweens("show_player")
	cancelTweens("show_bars")
	cancelTweens("show_items")

	if self._itemHolderSpace and self._itemHolderOriginalPosition then
		local itemsTween = TweenService:Create(self._itemHolderSpace, TweenConfig.get("Main", "show"), {
			GroupTransparency = 0,
			Position = self._itemHolderOriginalPosition,
		})
		itemsTween:Play()
		currentTweens["show_items"] = {itemsTween}
	end

	local playerTween
	if playerHolder and self._playerHolderOriginalPosition then
		playerTween = TweenService:Create(playerHolder, TweenConfig.get("Main", "show"), {
			GroupTransparency = 0,
			Position = self._playerHolderOriginalPosition,
		})
		playerTween:Play()
		currentTweens["show_player"] = {playerTween}
	end

	task.delay(TweenConfig.getDelay("Stagger"), function()
		if not self._ui or not self._ui.Parent then
			return
		end

		cancelTweens("show_bars")

		if barHolders and self._barHoldersOriginalPosition then
			local barsTween = TweenService:Create(barHolders, TweenConfig.get("Main", "show"), {
				GroupTransparency = 0,
				Position = self._barHoldersOriginalPosition,
			})
			barsTween:Play()
			currentTweens["show_bars"] = {barsTween}
		end
	end)

	return playerTween
end

function module:_animateHide()
	if not self._playerSpace then
		return nil
	end

	local playerHolder = self._playerSpace:FindFirstChild("PlayerHolder")
	local barHolders = self._playerSpace:FindFirstChild("BarHolders")

	cancelTweens("show_player")
	cancelTweens("show_bars")
	cancelTweens("show_items")

	if self._itemHolderSpace and self._itemHolderOriginalPosition then
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
		currentTweens["show_items"] = {itemsTween}
	end

	local barsTween
	if playerHolder and self._playerHolderOriginalPosition then
		local targetPlayerPos = UDim2.new(
			self._playerHolderOriginalPosition.X.Scale,
			self._playerHolderOriginalPosition.X.Offset,
			self._playerHolderOriginalPosition.Y.Scale + 0.1,
			self._playerHolderOriginalPosition.Y.Offset
		)

		local playerTween = TweenService:Create(playerHolder, TweenConfig.get("Main", "hide"), {
			GroupTransparency = 1,
			Position = targetPlayerPos,
		})
		playerTween:Play()
		currentTweens["show_player"] = {playerTween}
	end

	if barHolders and self._barHoldersOriginalPosition then
		local targetBarsPos = UDim2.new(
			self._barHoldersOriginalPosition.X.Scale,
			self._barHoldersOriginalPosition.X.Offset,
			self._barHoldersOriginalPosition.Y.Scale + 0.1,
			self._barHoldersOriginalPosition.Y.Offset
		)

		barsTween = TweenService:Create(barHolders, TweenConfig.get("Main", "hide"), {
			GroupTransparency = 1,
			Position = targetBarsPos,
		})
		barsTween:Play()
		currentTweens["show_bars"] = {barsTween}
	end

	return barsTween
end

function module:_init()
	if self._initialized then
		self:_setupHealthConnection()
		self:_setupUltConnection()
		return
	end

	self._initialized = true

	self:_setupHealthConnection()
	self:_setupUltConnection()
end

function module:show()
	if not self._viewedPlayer then
		self._viewedPlayer = Players.LocalPlayer
	end

	self:_initPlayerData()
	self:_updatePlayerThumbnail()

	local health = self._viewedPlayer:GetAttribute("Health") or 100
	local maxHealth = self._viewedPlayer:GetAttribute("MaxHealth") or 100
	local ult = self._viewedPlayer:GetAttribute("Ultimate") or 0

	self:_setHealthBar(health, maxHealth, true)
	self:_setUltBar(ult, true)

	self._ui.Visible = true

	self:_setInitialState()
	self:_animateShow()

	self:_init()

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

	self._connections:cleanupGroup("hud_health")
	self._connections:cleanupGroup("hud_ult")

	for _, tweens in currentTweens do
		for _, tween in tweens do
			tween:Cancel()
		end
	end
	table.clear(currentTweens)

	self:_clearPlayerData()

	self._weaponData = {}
	self._selectedSlot = nil

	self._viewedPlayer = nil
	self._viewedCharacter = nil
end

return module
