local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Configs)
local KitsConfig = Configs.KitsConfig
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)

local module = {}
module.__index = module

local TWEEN_SHOW = TweenInfo.new(0.85, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_HIDE = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TWEEN_SELECT = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_HOVER = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_HOVER_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_FILTER = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_INFO_SHOW = TweenInfo.new(0.67, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_HOLD = TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local TWEEN_CARD_FLASH = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.15)
local TWEEN_CARD_SLIDE = TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_PURCHASE_POP = TweenInfo.new(0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_PURCHASE_SHRINK = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.1)
local TWEEN_INSUFFICIENT_FLASH = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 3, true)

local HOLD_FOV_OFFSET = 10
local HOLD_FLASH_TARGET = 0.85

local currentTweens = {}

local function cancelTweenGroup(key)
	if currentTweens[key] then
		for _, tween in currentTweens[key] do
			tween:Cancel()
		end
		currentTweens[key] = nil
	end
end

-- Called once when CoreUI initializes all modules
function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections

	-- Runtime state (reset on hide)
	self._kitCards = {}
	self._selectedKitId = nil
	self._statsBarOpen = false
	self._statsBarType = nil
	self._activeActionHolder = nil
	self._filterOpen = false
	self._filterRarity = false
	self._filterPrice = false
	self._filterAZ = false
	self._filterCheckboxes = {}
	self._searchQuery = ""
	self._isHoldingBuy = false
	self._originalCameraFOV = nil

	-- Cache references to UI elements (done once in start)
	self._info = ui:FindFirstChild("Info")
	self._searchHolder = ui:FindFirstChild("SearchHolder")
	self._filterDropDown = self._searchHolder and self._searchHolder:FindFirstChild("FilterDropDown")
	self._buyFrame = ui:FindFirstChild("BuyButton")
	self._flashingFrame = ui:FindFirstChild("Flashing")
	self._redFlashingFrame = ui:FindFirstChild("RedFlashing")
	self._hud = ui:FindFirstChild("Hud")
	self._scrollingFrame = self._hud and self._hud:FindFirstChild("ScrollingFrame")
	self._insufficientFunds = false

	-- Cache buy button elements
	self:_cacheBuyElements()

	-- Set initial hidden states for elements that start hidden
	self:_setInitialStates()

	return self
end

function module:_cacheBuyElements()
	if not self._buyFrame then
		return
	end

	local holder = self._buyFrame:FindFirstChild("Holder")
	if not holder then
		return
	end

	local button = holder:FindFirstChild("BuyButton")
	if not button then
		return
	end

	local select = button:FindFirstChild("Select")
	local holding = button:FindFirstChild("Holding")
	local holdingGradient = holding and holding:FindFirstChild("UIGradient")
	local textHolder = button:FindFirstChild("TextHolder")
	local cost = textHolder and textHolder:FindFirstChild("Cost")
	local costIcon = textHolder and textHolder:FindFirstChild("ImageLabel")
	local text = self._buyFrame:FindFirstChild("Text")
	local text1 = self._buyFrame:FindFirstChild("Text1")

	self._buyElements = {
		frame = self._buyFrame,
		button = button,
		select = select,
		holding = holding,
		holdingGradient = holdingGradient,
		cost = cost,
		costIcon = costIcon,
		text = text,
		text1 = text1,
	}

	-- Cache original values for buy button
	self._buyOriginals = {
		holdingOffset = holdingGradient and holdingGradient.Offset or Vector2.new(-0.1, 0),
		holdingColor = holding and holding.BackgroundColor3 or Color3.new(0, 0, 0),
		textTransparency = text and text.TextTransparency or 0,
		text1Transparency = text1 and text1.TextTransparency or 0,
		flashingTransparency = self._flashingFrame and self._flashingFrame.ImageTransparency or 1,
		redFlashingTransparency = self._redFlashingFrame and self._redFlashingFrame.ImageTransparency or 1,
		costTextColor = cost and cost.TextColor3 or Color3.new(1, 1, 1),
	}
end

function module:_setInitialStates()
	-- Info panel starts hidden
	if self._info then
		self._info.Visible = false
		self._info.GroupTransparency = 1
	end

	-- Filter dropdown starts hidden
	if self._filterDropDown then
		self._filterDropDown.GroupTransparency = 1
		self._filterDropDown.Visible = false
	end

	-- Buy button starts hidden
	if self._buyFrame then
		self._buyFrame.Visible = false
		self._buyFrame.GroupTransparency = 1
	end

	if self._buyElements then
		if self._buyElements.select then
			self._buyElements.select.BackgroundTransparency = 1
		end
		if self._buyElements.text then
			self._buyElements.text.TextTransparency = 1
		end
		if self._buyElements.text1 then
			self._buyElements.text1.TextTransparency = 1
		end
		if self._buyElements.holdingGradient then
			self._buyElements.holdingGradient.Offset = Vector2.new(-0.1, 0)
		end
	end
end

function module:_setupConnections()
	-- Close button
	local closeButton = self._ui:FindFirstChild("CloseButton")
	if closeButton then
		self._connections:track(closeButton, "Activated", function()
			self:_close()
		end, "ui")
	end

	-- Filter button and checkboxes
	self:_setupFilter()

	-- Search
	self:_setupSearch()

	-- Info panel action holders
	self:_setupInfoPanel()

	-- Buy button
	self:_setupBuyButton()
end

function module:_close()
	self._export:hide()

	local startModule = self._export:getModule("Start")
	if startModule and startModule.showAll then
		startModule:showAll()
	end
end

function module:_setupFilter()
	if not self._searchHolder then
		return
	end

	local filterButton = self._searchHolder:FindFirstChild("Filter")
	if filterButton then
		self._connections:track(filterButton, "Activated", function()
			self:_toggleFilter()
		end, "ui")
	end

	if not self._filterDropDown then
		return
	end

	self:_setupFilterCheckbox(self._filterDropDown, "Rarity", "filterRarity")
	self:_setupFilterCheckbox(self._filterDropDown, "Price", "filterPrice")
	self:_setupFilterCheckbox(self._filterDropDown, "A-Z", "filterAZ")
end

function module:_setupFilterCheckbox(filterDropDown, filterName: string, stateKey: string)
	local holder = filterDropDown:FindFirstChild("Holder")
	if not holder then
		return
	end

	local filterFrame = holder:FindFirstChild(filterName)
	if not filterFrame then
		return
	end

	local checkbox = filterFrame:FindFirstChild("checkbox")
	if not checkbox then
		return
	end

	local checkOn = checkbox:FindFirstChild("CheckOn")
	if checkOn then
		checkOn.Visible = false
		checkOn.Size = UDim2.fromScale(0, 0)
	end

	self._filterCheckboxes[stateKey] = { checkbox = checkbox, checkOn = checkOn }

	self._connections:track(checkbox, "Activated", function()
		local wasActive = self["_" .. stateKey]

		self._filterRarity = false
		self._filterPrice = false
		self._filterAZ = false

		for _, data in self._filterCheckboxes do
			if data.checkOn then
				data.checkOn.Visible = false
				data.checkOn.Size = UDim2.fromScale(0, 0)
			end
		end

		if not wasActive then
			self["_" .. stateKey] = true
			if checkOn then
				checkOn.Visible = true
				TweenService:Create(checkOn, TWEEN_SELECT, { Size = UDim2.fromScale(1, 1) }):Play()
			end
		end

		self:_applyFilters()
	end, "ui")
end

function module:_toggleFilter()
	self._filterOpen = not self._filterOpen

	if not self._filterDropDown then
		return
	end

	local originals = self._export:getOriginals("SearchHolder.FilterDropDown")
	if not originals then
		return
	end

	cancelTweenGroup("filter")

	local origPos = originals.Position
	local hiddenPos = UDim2.new(origPos.X.Scale + 0.07, origPos.X.Offset, origPos.Y.Scale, origPos.Y.Offset)
	local tweens = {}

	if self._filterOpen then
		self._filterDropDown.Position = hiddenPos
		self._filterDropDown.GroupTransparency = 1
		self._filterDropDown.Visible = true
		local tween = TweenService:Create(self._filterDropDown, TWEEN_FILTER, {
			GroupTransparency = 0,
			Position = origPos,
		})
		tween:Play()
		table.insert(tweens, tween)
	else
		local tween = TweenService:Create(self._filterDropDown, TWEEN_FILTER, {
			GroupTransparency = 1,
			Position = hiddenPos,
		})
		tween:Play()
		table.insert(tweens, tween)

		tween.Completed:Once(function()
			if not self._filterOpen then
				self._filterDropDown.Visible = false
			end
		end)
	end

	currentTweens["filter"] = tweens
end

function module:_setupSearch()
	if not self._searchHolder then
		return
	end

	local searchBar = self._searchHolder:FindFirstChild("SearchBar")
	if not searchBar then
		return
	end

	local textBox = searchBar:FindFirstChild("TextBox")
	if not textBox then
		return
	end

	local textChangedConn = textBox:GetPropertyChangedSignal("Text"):Connect(function()
		self._searchQuery = textBox.Text
		self:_applyFilters()
	end)
	self._connections:add(textChangedConn, "ui")

	self._connections:track(textBox, "FocusLost", function()
		self._searchQuery = textBox.Text
		self:_applyFilters()
	end, "ui")
end

function module:_applyFilters()
	local allKitIds = KitsConfig.getKitIds()
	local query = (self._searchQuery or ""):lower()
	local filtered = {}

	for _, kitId in allKitIds do
		local kitData = KitsConfig.getKit(kitId)
		if not kitData then
			continue
		end

		if query == "" or (kitData.Name or ""):lower():find(query, 1, true) then
			table.insert(filtered, kitId)
		end
	end

	if self._filterRarity then
		local order = { Mythic = 1, Legendary = 2, Epic = 3, Rare = 4, Common = 5 }
		table.sort(filtered, function(a, b)
			local kA, kB = KitsConfig.getKit(a), KitsConfig.getKit(b)
			local oA, oB = order[kA.Rarity] or 99, order[kB.Rarity] or 99
			return oA == oB and (kA.Name or "") < (kB.Name or "") or oA < oB
		end)
	elseif self._filterAZ then
		table.sort(filtered, function(a, b)
			return (KitsConfig.getKit(a).Name or "") < (KitsConfig.getKit(b).Name or "")
		end)
	elseif self._filterPrice then
		table.sort(filtered, function(a, b)
			return (KitsConfig.getKit(a).Price or 0) < (KitsConfig.getKit(b).Price or 0)
		end)
	end

	local filteredSet = {}
	for i, kitId in filtered do
		filteredSet[kitId] = i
	end

	for kitId, cardData in self._kitCards do
		if cardData.card then
			local order = filteredSet[kitId]
			cardData.card.Visible = order ~= nil
			cardData.card.LayoutOrder = order or 0
		end
	end
end

function module:_isKitOwned(kitId: string): boolean
	return PlayerDataTable.isOwned("OWNED_KITS", kitId)
end

function module:_applyLockedState(card, isLocked: boolean)
	local locked = card:FindFirstChild("Locked")
	if locked then
		locked.Visible = isLocked
	end

	local holder = card:FindFirstChild("Holder")
	if not holder then
		return
	end

	local itemFrame = holder:FindFirstChild("itemFrame")
	if not itemFrame then
		return
	end

	local holderStuff = itemFrame:FindFirstChild("HolderStuff")
	if holderStuff then
		local bg = holderStuff:FindFirstChild("BG")
		if bg then
			bg.GroupColor3 = isLocked and Color3.fromRGB(75, 75, 75) or Color3.fromRGB(255, 255, 255)
		end

		local icon = holderStuff:FindFirstChild("Icon")
		if icon then
			icon.ImageColor3 = isLocked and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
		end
	end

	local lowBar = itemFrame:FindFirstChild("LowBar")
	if lowBar then
		local kitIcon = lowBar:FindFirstChild("KitIcon")
		if kitIcon then
			kitIcon.ImageColor3 = isLocked and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
		end
	end
end

function module:_setupInfoPanel()
	if not self._info then
		return
	end

	local scrollingFrame = self._info:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then
		return
	end

	local infoHolder = scrollingFrame:FindFirstChild("InfoHolder")
	if infoHolder then
		local infoFrame = infoHolder:FindFirstChild("InfoFrame")
		if infoFrame then
			for _, actionType in { "Ability", "Passive", "Ultimate" } do
				self:_setupActionHolder(infoFrame, actionType)
			end
		end
	end

	local statsBar = scrollingFrame:FindFirstChild("StatsBar")
	if statsBar then
		self:_setupStatsBar(statsBar)
	end
end

function module:_setupActionHolder(infoFrame, actionType: string)
	local holder = infoFrame:FindFirstChild(actionType .. "Holder")
	if not holder then
		return
	end

	local viewButton = holder:FindFirstChild("ViewButton")
	if not viewButton then
		return
	end

	self:_setupButtonHover(viewButton, "viewHover_" .. actionType:lower(), "ui")

	self._connections:track(viewButton, "Activated", function()
		self:_onViewButtonClicked(actionType, holder)
	end, "ui")
end

function module:_setupButtonHover(button, tweenKey: string, group: string)
	local isHovering = false
	local flash = button:FindFirstChild("Flash")
	local stroke = button:FindFirstChild("UIStroke")
	local strokeGradient = stroke and stroke:FindFirstChild("UIGradient")
	local origRotation = strokeGradient and strokeGradient.Rotation or 90

	self._connections:track(button, "MouseEnter", function()
		if isHovering then
			return
		end
		isHovering = true

		cancelTweenGroup(tweenKey)
		local tweens = {}

		if flash then
			local t = TweenService:Create(flash, TWEEN_HOVER, { BackgroundTransparency = 0.75 })
			t:Play()
			table.insert(tweens, t)
		end

		if strokeGradient then
			local t = TweenService:Create(strokeGradient, TWEEN_HOVER, { Rotation = 0 })
			t:Play()
			table.insert(tweens, t)
		end

		currentTweens[tweenKey] = tweens
	end, group)

	self._connections:track(button, "MouseLeave", function()
		if not isHovering then
			return
		end
		isHovering = false

		cancelTweenGroup(tweenKey)
		local tweens = {}

		if flash then
			local t = TweenService:Create(flash, TWEEN_HOVER_OUT, { BackgroundTransparency = 1 })
			t:Play()
			table.insert(tweens, t)
		end

		if strokeGradient then
			local t = TweenService:Create(strokeGradient, TWEEN_HOVER_OUT, { Rotation = origRotation })
			t:Play()
			table.insert(tweens, t)
		end

		currentTweens[tweenKey] = tweens
	end, group)
end

function module:_onViewButtonClicked(actionType: string, holder)
	if not self._selectedKitId then
		return
	end

	local kitData = KitsConfig.getKit(self._selectedKitId)
	if not kitData or not kitData[actionType] then
		return
	end

	if self._statsBarOpen and self._statsBarType == actionType then
		self:_hideStatsBar()
		return
	end

	if self._statsBarOpen and self._activeActionHolder then
		self._activeActionHolder.Visible = true
	end

	self._activeActionHolder = holder
	holder.Visible = false

	self:_showStatsBar(actionType, kitData[actionType])
end

function module:_setupStatsBar(statsBar)
	local statsFrame = statsBar:FindFirstChild("StatsFrame")
	if not statsFrame then
		return
	end

	local mainFrameInfo = statsFrame:FindFirstChild("MainFrameInfo")
	if not mainFrameInfo then
		return
	end

	local closeButton = mainFrameInfo:FindFirstChild("CloseButton")
	if closeButton then
		self._connections:track(closeButton, "Activated", function()
			self:_hideStatsBar()
		end, "ui")

		self:_setupButtonHover(closeButton, "closeButtonHover", "ui")
	end
end

function module:_showStatsBar(actionType: string, actionData)
	if not self._info then
		return
	end

	local scrollingFrame = self._info:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then
		return
	end

	local statsBar = scrollingFrame:FindFirstChild("StatsBar")
	if not statsBar then
		return
	end

	local statsFrame = statsBar:FindFirstChild("StatsFrame")
	if not statsFrame then
		return
	end

	self._statsBarOpen = true
	self._statsBarType = actionType

	local mainFrameInfo = statsFrame:FindFirstChild("MainFrameInfo")
	if mainFrameInfo then
		local text = mainFrameInfo:FindFirstChild("CurrentFrameText")
		if text then
			text.Text = actionData.Name or ""
		end
	end

	local shortDesc = statsFrame:FindFirstChild("ShortDescription")
	if shortDesc and shortDesc:FindFirstChild("Holder") then
		local holder = shortDesc.Holder
		if holder:FindFirstChild("Text") then
			holder.Text.Text = actionData.Name or ""
		end
		if holder:FindFirstChild("Description") and holder.Description:FindFirstChild("Text") then
			holder.Description.Text.Text = actionData.Description or ""
		end
	end

	statsBar.Visible = true

	cancelTweenGroup("statsBar")

	statsFrame.GroupTransparency = 1
	statsFrame.Position = UDim2.new(0.072, 0, 0.15, 0)

	local tween = TweenService:Create(statsFrame, TWEEN_INFO_SHOW, {
		GroupTransparency = 0,
		Position = UDim2.new(0.072, 0, 0.005, 0),
	})
	tween:Play()

	currentTweens["statsBar"] = { tween }
end

function module:_hideStatsBar()
	if not self._statsBarOpen then
		return
	end

	if not self._info then
		return
	end

	local scrollingFrame = self._info:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then
		return
	end

	local statsBar = scrollingFrame:FindFirstChild("StatsBar")
	if statsBar then
		statsBar.Visible = false
	end

	if self._activeActionHolder then
		self._activeActionHolder.Visible = true
		self._activeActionHolder = nil
	end

	self._statsBarOpen = false
	self._statsBarType = nil
end

function module:_setupBuyButton()
	local e = self._buyElements
	if not e or not e.button then
		return
	end

	self:_setupBuyButtonHover()
	self:_setupBuyButtonHold()
end

function module:_setupBuyButtonHover()
	local e = self._buyElements
	if not e or not e.button then
		return
	end

	local isHovering = false

	self._connections:track(e.button, "MouseEnter", function()
		if isHovering or self._isHoldingBuy then
			return
		end
		isHovering = true

		cancelTweenGroup("buyHover")
		local tweens = {}

		if e.select then
			local t = TweenService:Create(e.select, TWEEN_HOVER, { BackgroundTransparency = 0.5 })
			t:Play()
			table.insert(tweens, t)
		end

		if e.text then
			local t = TweenService:Create(e.text, TWEEN_HOVER, { TextTransparency = self._buyOriginals.textTransparency })
			t:Play()
			table.insert(tweens, t)
		end

		if e.text1 then
			local t = TweenService:Create(e.text1, TWEEN_HOVER, { TextTransparency = self._buyOriginals.text1Transparency })
			t:Play()
			table.insert(tweens, t)
		end

		currentTweens["buyHover"] = tweens
	end, "ui")

	self._connections:track(e.button, "MouseLeave", function()
		if not isHovering then
			return
		end
		isHovering = false

		if self._isHoldingBuy then
			return
		end

		cancelTweenGroup("buyHover")
		local tweens = {}

		if e.select then
			local t = TweenService:Create(e.select, TWEEN_HOVER_OUT, { BackgroundTransparency = 1 })
			t:Play()
			table.insert(tweens, t)
		end

		if e.text then
			local t = TweenService:Create(e.text, TWEEN_HOVER_OUT, { TextTransparency = 1 })
			t:Play()
			table.insert(tweens, t)
		end

		if e.text1 then
			local t = TweenService:Create(e.text1, TWEEN_HOVER_OUT, { TextTransparency = 1 })
			t:Play()
			table.insert(tweens, t)
		end

		currentTweens["buyHover"] = tweens
	end, "ui")
end

function module:_setupBuyButtonHold()
	local e = self._buyElements
	if not e or not e.button then
		return
	end

	local camera = workspace.CurrentCamera

	local function startHold()
		if self._isHoldingBuy then
			return
		end
		if not self._selectedKitId then
			return
		end
		if self:_isKitOwned(self._selectedKitId) then
			return
		end

		local kitData = KitsConfig.getKit(self._selectedKitId)
		local price = kitData and kitData.Price or 0
		local currentGems = PlayerDataTable.getData("GEMS") or 0
		if currentGems < price then
			self:_showInsufficientFunds()
			return
		end

		self._isHoldingBuy = true
		self._originalCameraFOV = camera and camera.FieldOfView or 70

		cancelTweenGroup("buyHold")
		local tweens = {}

		if e.select then
			local t = TweenService:Create(e.select, TWEEN_HOVER, { BackgroundTransparency = 1 })
			t:Play()
			table.insert(tweens, t)
		end

		if e.holding then
			local t = TweenService:Create(e.holding, TWEEN_HOLD, { BackgroundColor3 = Color3.new(1, 1, 1) })
			t:Play()
			table.insert(tweens, t)
		end

		if e.holdingGradient then
			e.holdingGradient.Offset = Vector2.new(-0.1, 0)
			local t = TweenService:Create(e.holdingGradient, TWEEN_HOLD, { Offset = Vector2.new(1, 0) })
			t:Play()
			table.insert(tweens, t)

			t.Completed:Once(function(state)
				if state == Enum.PlaybackState.Completed and self._isHoldingBuy then
					self:_onBuyComplete()
				end
			end)
		end

		if self._flashingFrame then
			local t = TweenService:Create(self._flashingFrame, TWEEN_HOLD, { ImageTransparency = HOLD_FLASH_TARGET })
			t:Play()
			table.insert(tweens, t)
		end

		if camera then
			local t = TweenService:Create(camera, TWEEN_HOLD, { FieldOfView = self._originalCameraFOV - HOLD_FOV_OFFSET })
			t:Play()
			table.insert(tweens, t)
		end

		currentTweens["buyHold"] = tweens
	end

	local function endHold()
		if not self._isHoldingBuy then
			return
		end
		self._isHoldingBuy = false

		cancelTweenGroup("buyHold")
		local tweens = {}

		if e.holdingGradient then
			local t = TweenService:Create(e.holdingGradient, TWEEN_HOVER_OUT, { Offset = Vector2.new(-0.1, 0) })
			t:Play()
			table.insert(tweens, t)
		end

		if e.holding then
			local t = TweenService:Create(e.holding, TWEEN_HOVER_OUT, { BackgroundColor3 = self._buyOriginals.holdingColor })
			t:Play()
			table.insert(tweens, t)
		end

		if e.select then
			local t = TweenService:Create(e.select, TWEEN_HOVER, { BackgroundTransparency = 0.5 })
			t:Play()
			table.insert(tweens, t)
		end

		if self._flashingFrame then
			local t = TweenService:Create(self._flashingFrame, TWEEN_HOVER_OUT, { ImageTransparency = self._buyOriginals.flashingTransparency })
			t:Play()
			table.insert(tweens, t)
		end

		if camera and self._originalCameraFOV then
			local t = TweenService:Create(camera, TWEEN_HOVER_OUT, { FieldOfView = self._originalCameraFOV })
			t:Play()
			table.insert(tweens, t)
		end

		currentTweens["buyHold"] = tweens
	end

	self._connections:track(e.button, "MouseButton1Down", startHold, "ui")
	self._connections:track(e.button, "MouseButton1Up", endHold, "ui")

	local inputBeganConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end

		local valid = input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
			or input.KeyCode == Enum.KeyCode.ButtonX

		if not valid then
			return
		end

		if input.UserInputType == Enum.UserInputType.Touch then
			local pos = input.Position
			local absPos = e.button.AbsolutePosition
			local absSize = e.button.AbsoluteSize

			if pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y then
				startHold()
			end
		else
			if GuiService.SelectedObject == e.button then
				startHold()
			end
		end
	end)

	local inputEndedConn = UserInputService.InputEnded:Connect(function(input)
		local valid = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
			or input.KeyCode == Enum.KeyCode.ButtonX

		if valid and self._isHoldingBuy then
			endHold()
		end
	end)

	local selectionConn = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		if self._isHoldingBuy and GuiService.SelectedObject ~= e.button then
			endHold()
		end
	end)

	self._connections:add(inputBeganConn, "ui")
	self._connections:add(inputEndedConn, "ui")
	self._connections:add(selectionConn, "ui")
end

function module:_onBuyComplete()
	self._isHoldingBuy = false

	local kitId = self._selectedKitId
	if not kitId then
		return
	end

	local kitData = KitsConfig.getKit(kitId)
	if not kitData then
		return
	end

	local cardData = self._kitCards[kitId]
	if not cardData then
		return
	end

	local price = kitData.Price or 0
	local currentGems = PlayerDataTable.getData("GEMS") or 0

	if currentGems < price then
		self:_resetBuyButton()
		return
	end

	cancelTweenGroup("buyHold")

	local tweens = {}
	local camera = workspace.CurrentCamera

	if self._flashingFrame then
		local t = TweenService:Create(self._flashingFrame, TWEEN_HIDE, { ImageTransparency = self._buyOriginals.flashingTransparency })
		t:Play()
		table.insert(tweens, t)
	end

	if camera and self._originalCameraFOV then
		local t = TweenService:Create(camera, TWEEN_HIDE, { FieldOfView = self._originalCameraFOV })
		t:Play()
		table.insert(tweens, t)
	end

	currentTweens["buyComplete"] = tweens

	PlayerDataTable.setData("GEMS", currentGems - price)
	PlayerDataTable.addOwned("OWNED_KITS", kitId)
	cardData.owned = true

	if cardData.card then
		self:_applyLockedState(cardData.card, false)
	end

	self:_playPurchaseFlash(kitId)
	self:_resetBuyButton()
	self:_hideBuyButton()
	self:_onKitPurchased(kitId)
end

function module:_onKitPurchased(kitId: string)
	print("[Kits] Purchased:", kitId)
end

function module:_resetBuyButton()
	local e = self._buyElements
	if not e then
		return
	end

	if e.holdingGradient then
		e.holdingGradient.Offset = Vector2.new(-0.1, 0)
	end

	if e.holding then
		e.holding.BackgroundColor3 = self._buyOriginals.holdingColor
	end

	if e.select then
		e.select.BackgroundTransparency = 1
	end

	if e.text then
		e.text.TextTransparency = 1
	end

	if e.text1 then
		e.text1.TextTransparency = 1
	end
end

function module:_showInsufficientFunds()
	if self._insufficientFunds then
		return
	end

	self._insufficientFunds = true

	local e = self._buyElements
	if not e then
		return
	end

	local kitData = self._selectedKitId and KitsConfig.getKit(self._selectedKitId)

	cancelTweenGroup("insufficientFunds")
	local tweens = {}

	if e.cost then
		e.cost.Text = "INSUFFICIENT FUNDS"
		e.cost.TextColor3 = Color3.fromRGB(255, 80, 80)
	end

	if e.costIcon then
		e.costIcon.Visible = false
	end

	if self._redFlashingFrame then
		local flashTween = TweenService:Create(self._redFlashingFrame, TWEEN_INSUFFICIENT_FLASH, {
			ImageTransparency = 0.5,
		})
		flashTween:Play()
		table.insert(tweens, flashTween)
	end

	currentTweens["insufficientFunds"] = tweens

	task.delay(1, function()
		if not self._insufficientFunds then
			return
		end

		self._insufficientFunds = false
		cancelTweenGroup("insufficientFunds")

		if e.cost and kitData then
			e.cost.Text = tostring(kitData.Price or 0)
			e.cost.TextColor3 = self._buyOriginals.costTextColor
		end

		if e.costIcon then
			e.costIcon.Visible = true
		end

		if self._redFlashingFrame then
			self._redFlashingFrame.ImageTransparency = self._buyOriginals.redFlashingTransparency
		end
	end)
end

function module:_resetInsufficientFunds(kitData)
	if not self._insufficientFunds then
		return
	end

	self._insufficientFunds = false

	cancelTweenGroup("insufficientFunds")

	local e = self._buyElements
	if not e then
		return
	end

	if e.cost and kitData then
		e.cost.Text = tostring(kitData.Price or 0)
		e.cost.TextColor3 = self._buyOriginals.costTextColor
	end

	if e.costIcon then
		e.costIcon.Visible = true
	end

	if self._redFlashingFrame then
		self._redFlashingFrame.ImageTransparency = self._buyOriginals.redFlashingTransparency
	end
end

function module:_showBuyButton(kitData)
	local e = self._buyElements
	if not e or not e.frame then
		return
	end

	cancelTweenGroup("buyShow")
	cancelTweenGroup("buyHover")
	cancelTweenGroup("buyHold")

	self._isHoldingBuy = false
	self:_resetBuyButton()

	if e.cost then
		e.cost.Text = tostring(kitData.Price or 0)
	end

	local originals = self._export:getOriginals("BuyButton")
	if not originals then
		return
	end

	local origPos = originals.Position
	e.frame.Position = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale + 0.03, origPos.Y.Offset)
	e.frame.GroupTransparency = 1
	e.frame.Visible = true

	local tweens = {}

	local posTween = TweenService:Create(e.frame, TWEEN_INFO_SHOW, { Position = origPos })
	local fadeTween = TweenService:Create(e.frame, TWEEN_INFO_SHOW, { GroupTransparency = originals.GroupTransparency or 0 })

	posTween:Play()
	fadeTween:Play()

	table.insert(tweens, posTween)
	table.insert(tweens, fadeTween)

	currentTweens["buyShow"] = tweens
end

function module:_hideBuyButton()
	local e = self._buyElements
	if not e or not e.frame then
		return
	end

	cancelTweenGroup("buyShow")
	cancelTweenGroup("buyHover")
	cancelTweenGroup("buyHold")

	self._isHoldingBuy = false

	local tween = TweenService:Create(e.frame, TWEEN_HIDE, { GroupTransparency = 1 })
	tween:Play()

	tween.Completed:Once(function()
		if e.frame.GroupTransparency >= 0.99 then
			e.frame.Visible = false
			self:_resetBuyButton()
		end
	end)

	currentTweens["buyShow"] = { tween }
end

function module:_populateKitCards()
	if not self._scrollingFrame then
		return
	end

	local kitIds = KitsConfig.getKitIds()

	for i, kitId in kitIds do
		task.delay((i - 1) * 0.15, function()
			if not self._export:isOpen() then
				return
			end
			self:_createKitCard(kitId, self._scrollingFrame)
		end)
	end
end

function module:_createKitCard(kitId: string, parent)
	local card = KitsConfig.createKitCard(kitId)
	if not card then
		return
	end

	card.Parent = parent
	card.LayoutOrder = #self._kitCards + 1

	local isOwned = self:_isKitOwned(kitId)

	self._kitCards[kitId] = {
		card = card,
		kitData = KitsConfig.getKit(kitId),
		owned = isOwned,
	}

	self:_applyLockedState(card, not isOwned)

	local holder = card:FindFirstChild("Holder")
	if holder then
		self:_playCardIntro(holder, kitId)
		local button = holder:FindFirstChild("Button")
		if button then
			self._connections:track(button, "Activated", function()
				self:_selectKit(kitId)
			end, "cards")
		end
	end

	self:_setupKitCardHover(card, kitId)
end

function module:_playCardIntro(holder, kitId: string)
	local origPosition = holder.Position
	local offsetPosition = UDim2.new(origPosition.X.Scale, origPosition.X.Offset, origPosition.Y.Scale - 0.35, origPosition.Y.Offset)

	holder.Position = offsetPosition

	local slideTween = TweenService:Create(holder, TWEEN_CARD_SLIDE, { Position = origPosition })
	slideTween:Play()

	local frame = holder:FindFirstChild("Frame")
	if frame then
		self:_playCardFlash(frame, kitId)
	end

	currentTweens["cardSlide_" .. kitId] = { slideTween }
end

function module:_playCardFlash(frame, kitId: string)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundTransparency = 0
	frame.Visible = true

	local fadeTween = TweenService:Create(frame, TWEEN_CARD_FLASH, { BackgroundTransparency = 1 })
	fadeTween:Play()

	fadeTween.Completed:Once(function()
		frame.Visible = false
	end)

	currentTweens["cardFlash_" .. kitId] = { fadeTween }
end

function module:_playPurchaseFlash(kitId: string)
	local cardData = self._kitCards[kitId]
	if not cardData or not cardData.card then
		return
	end

	local holder = cardData.card:FindFirstChild("Holder")
	if not holder then
		return
	end

	local frame = holder:FindFirstChild("Frame")
	if not frame then
		return
	end

	local uiScale = holder:FindFirstChild("UIScale")
	local origScale = uiScale and uiScale.Scale or 1

	cancelTweenGroup("cardFlash_" .. kitId)
	cancelTweenGroup("purchaseScale_" .. kitId)

	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundTransparency = 0
	frame.Visible = true

	local tweens = {}

	local fadeTween = TweenService:Create(frame, TWEEN_CARD_FLASH, { BackgroundTransparency = 1 })
	fadeTween:Play()
	table.insert(tweens, fadeTween)

	fadeTween.Completed:Once(function()
		frame.Visible = false
	end)

	if uiScale then
		local popTween = TweenService:Create(uiScale, TWEEN_PURCHASE_POP, { Scale = origScale * 1.1 })
		popTween:Play()
		table.insert(tweens, popTween)

		popTween.Completed:Once(function()
			local shrinkTween = TweenService:Create(uiScale, TWEEN_PURCHASE_SHRINK, { Scale = origScale })
			shrinkTween:Play()
		end)
	end

	currentTweens["cardFlash_" .. kitId] = tweens
end

function module:_setupKitCardHover(card, kitId: string)
	local isHovering = false

	local holder = card:FindFirstChild("Holder")
	if not holder then
		return
	end

	local itemFrame = holder:FindFirstChild("itemFrame")
	if not itemFrame then
		return
	end

	local selectFrame = itemFrame:FindFirstChild("Select")
	local selectGradient = selectFrame and selectFrame:FindFirstChild("UIGradient")
	local uiScale = card:FindFirstChild("UIScale")

	local origScale = uiScale and uiScale.Scale or 1
	local origOffset = selectGradient and selectGradient.Offset or Vector2.new(0, 1)

	self._connections:track(holder, "MouseEnter", function()
		if isHovering then
			return
		end
		isHovering = true

		cancelTweenGroup("kitHover_" .. kitId)
		local tweens = {}

		if uiScale then
			local t = TweenService:Create(uiScale, TWEEN_HOVER, { Scale = origScale * 1.03 })
			t:Play()
			table.insert(tweens, t)
		end

		if selectGradient and self._selectedKitId ~= kitId then
			local t = TweenService:Create(selectGradient, TWEEN_HOVER, { Offset = Vector2.new(origOffset.X, 0.35) })
			t:Play()
			table.insert(tweens, t)
		end

		currentTweens["kitHover_" .. kitId] = tweens
	end, "cards")

	self._connections:track(holder, "MouseLeave", function()
		if not isHovering then
			return
		end
		isHovering = false

		cancelTweenGroup("kitHover_" .. kitId)
		local tweens = {}

		if uiScale then
			local t = TweenService:Create(uiScale, TWEEN_HOVER_OUT, { Scale = origScale })
			t:Play()
			table.insert(tweens, t)
		end

		if selectGradient and self._selectedKitId ~= kitId then
			local t = TweenService:Create(selectGradient, TWEEN_HOVER_OUT, { Offset = origOffset })
			t:Play()
			table.insert(tweens, t)
		end

		currentTweens["kitHover_" .. kitId] = tweens
	end, "cards")
end

function module:_selectKit(kitId: string)
	if self._selectedKitId == kitId then
		return
	end

	local kitData = KitsConfig.getKit(kitId)
	if not kitData then
		return
	end

	self:_resetInsufficientFunds(kitData)

	if self._selectedKitId then
		self:_deselectKit(self._selectedKitId)
	end

	self._selectedKitId = kitId

	local cardData = self._kitCards[kitId]
	if cardData and cardData.card then
		local holder = cardData.card:FindFirstChild("Holder")
		if holder then
			local itemFrame = holder:FindFirstChild("itemFrame")
			if itemFrame then
				local selectFrame = itemFrame:FindFirstChild("Select")
				if selectFrame then
					local gradient = selectFrame:FindFirstChild("UIGradient")
					if gradient then
						TweenService:Create(gradient, TWEEN_SELECT, { Offset = Vector2.new(0, 0) }):Play()
					end
				end
			end
		end
	end

	self:_populateInfoPanel(kitId, kitData)

	if self:_isKitOwned(kitId) then
		self:_hideBuyButton()
	else
		self:_showBuyButton(kitData)
	end
end

function module:_deselectKit(kitId: string)
	local cardData = self._kitCards[kitId]
	if not cardData or not cardData.card then
		return
	end

	local holder = cardData.card:FindFirstChild("Holder")
	if not holder then
		return
	end

	local itemFrame = holder:FindFirstChild("itemFrame")
	if not itemFrame then
		return
	end

	local selectFrame = itemFrame:FindFirstChild("Select")
	if not selectFrame then
		return
	end

	local gradient = selectFrame:FindFirstChild("UIGradient")
	if gradient then
		TweenService:Create(gradient, TWEEN_SELECT, { Offset = Vector2.new(0, 1) }):Play()
	end
end

function module:_populateInfoPanel(kitId: string, kitData)
	if not self._info then
		return
	end

	local scrollingFrame = self._info:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then
		return
	end

	local mainHolder = scrollingFrame:FindFirstChild("MainHolder")
	local infoHolder = scrollingFrame:FindFirstChild("InfoHolder")
	local statsBar = scrollingFrame:FindFirstChild("StatsBar")

	if self._statsBarOpen then
		if self._activeActionHolder then
			self._activeActionHolder.Visible = true
			self._activeActionHolder = nil
		end

		if statsBar then
			statsBar.Visible = false
			local statsFrame = statsBar:FindFirstChild("StatsFrame")
			if statsFrame then
				statsFrame.GroupTransparency = 1
			end
		end

		self._statsBarOpen = false
		self._statsBarType = nil
	end

	cancelTweenGroup("infoPanel")

	if mainHolder then
		mainHolder.Visible = true
		self:_populateMainHolder(mainHolder, kitData)
	end

	if infoHolder then
		infoHolder.Visible = true
		self:_populateInfoHolder(infoHolder, kitData)
	end

	local originals = self._export:getOriginals("Info")
	if not originals then
		return
	end

	local origPos = originals.Position
	self._info.Position = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale - 0.03, origPos.Y.Offset)
	self._info.GroupTransparency = 1
	self._info.Visible = true

	local tweens = {}

	local posTween = TweenService:Create(self._info, TWEEN_INFO_SHOW, { Position = origPos })
	local fadeTween = TweenService:Create(self._info, TWEEN_INFO_SHOW, { GroupTransparency = originals.GroupTransparency or 0 })

	posTween:Play()
	fadeTween:Play()

	table.insert(tweens, posTween)
	table.insert(tweens, fadeTween)

	currentTweens["infoPanel"] = tweens
end

function module:_populateMainHolder(mainHolder, kitData)
	local mainFrame = mainHolder:FindFirstChild("Main")
	if mainFrame then
		local innerMain = mainFrame:FindFirstChild("Main")
		if innerMain then
			local kitIcon = innerMain:FindFirstChild("KitIcon")
			if kitIcon then
				kitIcon.Image = kitData.Icon or ""
			end

			local kitName = innerMain:FindFirstChild("KitName")
			if kitName then
				kitName.Text = kitData.Name or ""
			end
		end
	end

	local mapFrame = mainHolder:FindFirstChild("Map")
	if mapFrame then
		local rarityFrame = mapFrame:FindFirstChild("Rarity")
		if rarityFrame then
			local rarityInfo = KitsConfig.RarityInfo[kitData.Rarity]
			if rarityInfo then
				rarityFrame.BackgroundColor3 = rarityInfo.COLOR

				local rarityText = rarityFrame:FindFirstChild("RarityText")
				if rarityText then
					rarityText.Text = rarityInfo.TEXT
				end

				local stroke = rarityFrame:FindFirstChild("UIStroke")
				if stroke then
					stroke.Color = rarityInfo.COLOR
				end
			end
		end
	end

	local extraFrame = mainHolder:FindFirstChild("Extra")
	if extraFrame then
		local shortTextHolder = extraFrame:FindFirstChild("ShortTextHolder")
		if shortTextHolder then
			local shortText = shortTextHolder:FindFirstChild("ShortText1")
			if shortText then
				shortText.Text = "ㆍ" .. (kitData.Description or "")
			end
		end

		local extraRarity = extraFrame:FindFirstChild("Rarity")
		if extraRarity then
			local rarityInfo = KitsConfig.RarityInfo[kitData.Rarity]
			if rarityInfo then
				extraRarity.BackgroundColor3 = rarityInfo.COLOR
			end
		end
	end
end

function module:_populateInfoHolder(infoHolder, kitData)
	local infoFrame = infoHolder:FindFirstChild("InfoFrame")
	if not infoFrame then
		return
	end

	local actions = {
		{ key = "Ability", label = "ABILITY" },
		{ key = "Passive", label = "PASSIVE" },
		{ key = "Ultimate", label = "ULTIMATE" },
	}

	for _, action in actions do
		local holder = infoFrame:FindFirstChild(action.key .. "Holder")
		if not holder then
			continue
		end

		local actionData = kitData[action.key]

		if actionData then
			holder.Visible = true

			local mainText = holder:FindFirstChild("MainText")
			if mainText then
				mainText.Text = actionData.Name or "???"
			end

			local lowText = holder:FindFirstChild("LowText")
			if lowText then
				lowText.Text = action.label
			end
		else
			holder.Visible = false
		end
	end
end

-- Visual transition for showing (Category handles TallFade)
function module:transitionIn()
	-- Wrap in task.spawn to avoid yielding the caller
	task.spawn(function()
		-- Delay to sync with Category transition (wait for TallFade)
		task.wait(0.67)

		-- Now make visible and set initial state
		self._ui.Visible = true

		-- Animate in (use getOriginalsRaw since "Kits" is the root module path)
		local originals = self._export:getOriginalsRaw("Kits")
		if not originals then
			return
		end

		local origPos = originals.Position
		self._ui.Position = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale - 0.03, origPos.Y.Offset)
		self._ui.GroupTransparency = 1

		cancelTweenGroup("main")

		local tweens = {}

		local posTween = TweenService:Create(self._ui, TWEEN_SHOW, { Position = origPos })
		local fadeTween = TweenService:Create(self._ui, TWEEN_SHOW, { GroupTransparency = originals.GroupTransparency or 0 })

		posTween:Play()
		fadeTween:Play()

		table.insert(tweens, posTween)
		table.insert(tweens, fadeTween)

		currentTweens["main"] = tweens
	end)
end

-- Visual transition for hiding (Category handles TallFade)
function module:transitionOut()
	cancelTweenGroup("main")

	-- If UI isn't visible, nothing to transition out
	if not self._ui.Visible then
		return
	end

	local originals = self._export:getOriginalsRaw("Kits")
	if not originals then
		self._ui.Visible = false
		return
	end

	local origPos = originals.Position
	local targetPos = UDim2.new(origPos.X.Scale, origPos.X.Offset, origPos.Y.Scale - 0.03, origPos.Y.Offset)

	local tweens = {}

	local posTween = TweenService:Create(self._ui, TWEEN_HIDE, { Position = targetPos })
	local fadeTween = TweenService:Create(self._ui, TWEEN_HIDE, { GroupTransparency = 1 })

	posTween:Play()
	fadeTween:Play()

	table.insert(tweens, posTween)
	table.insert(tweens, fadeTween)

	-- Use posTween for completion since fadeTween completes instantly if already transparent
	posTween.Completed:Once(function()
		self._ui.Visible = false
	end)

	currentTweens["main"] = tweens
end

-- Called when CoreUI:show() is invoked
function module:show()
	-- Setup connections (they were cleaned up on hide)
	self:_setupConnections()

	-- Populate kit cards
	self:_populateKitCards()

	-- Play transition (visibility is set inside after delay)
	self:transitionIn()

	return true
end

-- Called when CoreUI:hide() is invoked
function module:hide()
	self:transitionOut()
	return true
end

-- Called by CoreUI after hide() completes - resets transient state
function module:_cleanup()
	-- Reset runtime state
	self._selectedKitId = nil
	self._statsBarOpen = false
	self._statsBarType = nil
	self._activeActionHolder = nil
	self._filterOpen = false
	self._filterRarity = false
	self._filterPrice = false
	self._filterAZ = false
	self._searchQuery = ""
	self._isHoldingBuy = false

	-- Reset camera effects
	local camera = workspace.CurrentCamera
	if camera and self._originalCameraFOV then
		camera.FieldOfView = self._originalCameraFOV
	end
	self._originalCameraFOV = nil

	-- Reset flashing frames
	if self._flashingFrame and self._buyOriginals then
		self._flashingFrame.ImageTransparency = self._buyOriginals.flashingTransparency
	end

	if self._redFlashingFrame and self._buyOriginals then
		self._redFlashingFrame.ImageTransparency = self._buyOriginals.redFlashingTransparency
	end

	self._insufficientFunds = false

	-- Reset filter checkboxes
	for _, data in self._filterCheckboxes do
		if data.checkOn then
			data.checkOn.Visible = false
			data.checkOn.Size = UDim2.fromScale(0, 0)
		end
	end

	-- Cancel all active tweens
	for key in currentTweens do
		cancelTweenGroup(key)
	end

	-- Destroy kit cards (they are dynamically created)
	for _, cardData in self._kitCards do
		if cardData.card then
			cardData.card:Destroy()
		end
	end
	table.clear(self._kitCards)

	-- Reset UI elements to initial hidden states
	self:_setInitialStates()

	-- Clear search text
	if self._searchHolder then
		for _, child in self._searchHolder:GetDescendants() do
			if child:IsA("TextBox") then
				child.Text = ""
				break
			end
		end
	end

	-- Reset info panel using CoreUI originals
	if self._info then
		local originals = self._export:getOriginals("Info")
		if originals then
			self._info.Position = originals.Position
			self._info.GroupTransparency = originals.GroupTransparency or 0
		end
		self._info.Visible = false
	end

	-- Reset filter dropdown
	if self._filterDropDown then
		local originals = self._export:getOriginals("SearchHolder.FilterDropDown")
		if originals then
			local origPos = originals.Position
			self._filterDropDown.Position = UDim2.new(origPos.X.Scale + 0.07, origPos.X.Offset, origPos.Y.Scale, origPos.Y.Offset)
		end
		self._filterDropDown.GroupTransparency = 1
		self._filterDropDown.Visible = false
	end

	-- Reset main UI using CoreUI originals
	local originals = self._export:getOriginalsRaw("Kits")
	if originals then
		self._ui.Position = originals.Position
		self._ui.GroupTransparency = originals.GroupTransparency or 0
	end
end

return module
