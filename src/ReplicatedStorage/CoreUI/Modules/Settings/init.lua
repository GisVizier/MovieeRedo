local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = require(ReplicatedStorage.Configs)
local SettingsConfig = Configs.SettingsConfig
local ActionsIcon = Configs.ActionsIcon
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
local TweenConfig = require(script.TweenConfig)

local module = {}
module.__index = module

local currentTweens = {}

local function cancelTweenGroup(key)
	if currentTweens[key] then
		for _, tween in currentTweens[key] do
			tween:Cancel()
		end
		currentTweens[key] = nil
	end
end

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections

	self._currentCategory = "Gameplay"
	self._selectedSetting = nil
	self._settingRows = {}

	self._overlayOpen = nil
	self._awaitingKeybind = nil
	self._resetCategory = nil

	self._imageCarouselConnection = nil
	self._currentImageIndex = 1
	self._videoPlaying = false

	self._searchQuery = ""
	self._deviceType = "PC"

	self._conflictingSettings = {}

	self._originals = {
		uiPosition = nil,
		uiTransparency = nil,
	}

	self._initialized = false
	self._buttonsActive = false

	self:_cacheUIReferences()
	self:_cacheOriginals()
	self:_detectDeviceType()

	return self
end

function module:_cacheUIReferences()
	self._canvasGroup = self._ui:FindFirstChild("CanvasGroup")
	self._options = self._ui:FindFirstChild("Options")
	self._keybindUI = self._ui:FindFirstChild("Keybind")
	self._actionUI = self._ui:FindFirstChild("Action")
	self._videoUI = self._ui:FindFirstChild("Video")
	self._blurUI = self._ui:FindFirstChild("Blur")

	if self._options then
		local important = self._options:FindFirstChild("Important")
		if important then
			local interaction = important:FindFirstChild("Interaction")
			if interaction then
				self._actionsBar = interaction:FindFirstChild("Actions")
				self._searchBar = interaction:FindFirstChild("SearchBar")
			end

			self._gameplayScroll = important:FindFirstChild("Gameplay")
			self._controlsScroll = important:FindFirstChild("Control")
			self._crosshairScroll = important:FindFirstChild("Crosshair")
		end

		self._infoPanel = self._options:FindFirstChild("Info")
	end
end

function module:_cacheOriginals()
	local canvas = self._canvasGroup or self._ui
	self._originals.uiPosition = canvas.Position
	self._originals.uiTransparency = canvas.GroupTransparency or 0
end

function module:_detectDeviceType()
	local gamepadConnected = UserInputService.GamepadEnabled
	local touchEnabled = UserInputService.TouchEnabled
	local keyboardEnabled = UserInputService.KeyboardEnabled

	if gamepadConnected and not keyboardEnabled then
		self._deviceType = "Console"
	elseif touchEnabled and not keyboardEnabled then
		self._deviceType = "Mobile"
	else
		self._deviceType = "PC"
	end
end

function module:_init()
	if self._initialized then
		self:_reconnect()
		self:_selectCategory(self._currentCategory)
		return
	end

	self._initialized = true

	SettingsConfig.init()
	PlayerDataTable.init()

	self:_setupCategories()
	self:_setupCategoryNavigation()
	self:_setupSearch()
	self:_setupCloseButton()
	self:_setupOverlays()

	self:_selectCategory("Gameplay")
end

function module:_reconnect()
	self:_setupCategories()
	self:_setupCategoryNavigation()
	self:_setupSearch()
	self:_setupCloseButton()
	self:_setupOverlays()
end

function module:_setupCategories()
	if not self._actionsBar then
		return
	end

	local gameplayBtn = self._actionsBar:FindFirstChild("Gameplay")
	local crosshairBtn = self._actionsBar:FindFirstChild("Crosshair")
	local controlBtn = self._actionsBar:FindFirstChild("Control")

	if gameplayBtn then
		self:_setupCategoryButton(gameplayBtn, "Gameplay")
	end

	if crosshairBtn then
		self:_setupCategoryButton(crosshairBtn, "Crosshair")
	end

	if controlBtn then
		self:_setupCategoryButton(controlBtn, "Controls")
	end
end

function module:_setupCategoryButton(btn, categoryKey: string)
	self._connections:track(btn, "Activated", function()
		if not self._buttonsActive or self._overlayOpen then
			return
		end
		self:_selectCategory(categoryKey)
	end, "categories")

	local select = btn:FindFirstChild("Select")
	if not select then
		return
	end

	local isHovering = false

	self._connections:track(btn, "MouseEnter", function()
		if isHovering or self._currentCategory == categoryKey then
			return
		end
		isHovering = true

		cancelTweenGroup("categoryHover_" .. categoryKey)
		local tween = TweenService:Create(select, TweenConfig.create("SettingHover"), {
			BackgroundTransparency = 0,
		})
		tween:Play()
		currentTweens["categoryHover_" .. categoryKey] = {tween}
	end, "categories")

	self._connections:track(btn, "MouseLeave", function()
		if not isHovering then
			return
		end
		isHovering = false

		if self._currentCategory == categoryKey then
			return
		end

		cancelTweenGroup("categoryHover_" .. categoryKey)
		local tween = TweenService:Create(select, TweenConfig.create("SettingHoverOut"), {
			BackgroundTransparency = 1,
		})
		tween:Play()
		currentTweens["categoryHover_" .. categoryKey] = {tween}
	end, "categories")
end

function module:_setupCategoryNavigation()
	self._connections:track(UserInputService, "InputBegan", function(input, gameProcessed)
		if gameProcessed or not self._buttonsActive or self._overlayOpen then
			return
		end

		if input.KeyCode == Enum.KeyCode.Tab then
			self:_cycleCategoryForward()
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			self:_cycleCategoryBackward()
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			self:_cycleCategoryForward()
		end
	end, "navigation")
end

function module:_cycleCategoryForward()
	local order = SettingsConfig.CategoryOrder
	local currentIndex = table.find(order, self._currentCategory) or 1
	local nextIndex = currentIndex % #order + 1
	self:_selectCategory(order[nextIndex])
end

function module:_cycleCategoryBackward()
	local order = SettingsConfig.CategoryOrder
	local currentIndex = table.find(order, self._currentCategory) or 1
	local prevIndex = (currentIndex - 2) % #order + 1
	self:_selectCategory(order[prevIndex])
end

function module:_selectCategory(categoryKey: string)
	if self._currentCategory == categoryKey and #self._settingRows > 0 then
		return
	end

	self:_deselectSetting()
	self._currentCategory = categoryKey

	self:_updateCategorySelection()
	self:_clearSettings()
	self:_populateSettings(categoryKey)
	self:_hideInfoPanel()
end

function module:_updateCategorySelection()
	if not self._actionsBar then
		return
	end

	local gameplayBtn = self._actionsBar:FindFirstChild("Gameplay")
	local crosshairBtn = self._actionsBar:FindFirstChild("Crosshair")
	local controlBtn = self._actionsBar:FindFirstChild("Control")

	local function updateButtonVisual(btn, isSelected, categoryKey)
		if not btn then return end

		local select = btn:FindFirstChild("Select")
		if select then
			cancelTweenGroup("categorySelect_" .. categoryKey)
			local targetTransparency = isSelected and 0 or 1
			local tween = TweenService:Create(select, TweenConfig.create("SettingSelect"), {
				BackgroundTransparency = targetTransparency,
			})
			tween:Play()
			currentTweens["categorySelect_" .. categoryKey] = {tween}
		end
	end

	updateButtonVisual(gameplayBtn, self._currentCategory == "Gameplay", "Gameplay")
	updateButtonVisual(crosshairBtn, self._currentCategory == "Crosshair", "Crosshair")
	updateButtonVisual(controlBtn, self._currentCategory == "Controls", "Controls")
end

function module:_getScrollingFrameForCategory(categoryKey: string): ScrollingFrame?
	if categoryKey == "Gameplay" then
		return self._gameplayScroll
	elseif categoryKey == "Controls" then
		return self._controlsScroll
	elseif categoryKey == "Crosshair" then
		return self._crosshairScroll
	end
	return nil
end

function module:_clearSettings()
	for _, rowData in self._settingRows do
		if rowData.row and rowData.row.Parent then
			rowData.row:Destroy()
		end
	end
	table.clear(self._settingRows)

	local scrollFrames = {self._gameplayScroll, self._controlsScroll, self._crosshairScroll}
	for _, scrollFrame in scrollFrames do
		if scrollFrame then
			local resetBtn = scrollFrame:FindFirstChild("ResetButton")
			if resetBtn then
				resetBtn:Destroy()
			end

			local keybindHeader = scrollFrame:FindFirstChild("KeybindHeader")
			if keybindHeader then
				keybindHeader:Destroy()
			end
		end
	end

	self._connections:cleanupGroup("settingRows")
	self._connections:cleanupGroup("sliders")
end

function module:_populateSettings(categoryKey: string)
	local scrollFrame = self:_getScrollingFrameForCategory(categoryKey)
	if not scrollFrame then
		return
	end

	if self._gameplayScroll then
		self._gameplayScroll.Visible = categoryKey == "Gameplay"
	end
	if self._controlsScroll then
		self._controlsScroll.Visible = categoryKey == "Controls"
	end
	if self._crosshairScroll then
		self._crosshairScroll.Visible = categoryKey == "Crosshair"
	end

	local settingsList = SettingsConfig.getSettingsList(categoryKey)

	if categoryKey == "Controls" then
		self:_createKeybindDisplayHeader(scrollFrame)
	end

	for i, settingData in settingsList do
		local row = self:_createSettingRow(settingData.key, settingData.config, scrollFrame, i)
		if row then
			table.insert(self._settingRows, {
				key = settingData.key,
				config = settingData.config,
				row = row,
				category = categoryKey,
			})
		end
	end

	self:_createResetButton(scrollFrame, categoryKey)
	self:_updateConflicts()
end

function module:_createKeybindDisplayHeader(parent: ScrollingFrame)
	local template = SettingsConfig.Templates.KeybindDisplay
	if not template then
		return
	end

	local header = template:Clone()
	header.Name = "KeybindHeader"
	header.LayoutOrder = 0
	header.Visible = true
	header.Parent = parent

	local infoFrame = header:FindFirstChild("Info")
	if infoFrame then
		local textLabel = infoFrame:FindFirstChild("TextLabel")
		if textLabel then
			textLabel.Text = "ACTION"
		end
	end
end

function module:_createSettingRow(settingKey: string, config, parent: ScrollingFrame, order: number): Frame?
	local template = SettingsConfig.cloneTemplate(config.SettingType)
	if not template then
		return nil
	end

	local row = template
	row.Name = "Setting_" .. settingKey
	row.LayoutOrder = order
	row.Visible = true
	row.Parent = parent

	local infoFrame = row:FindFirstChild("Info")
	if infoFrame then
		local textLabel = infoFrame:FindFirstChild("TextLabel")
		if textLabel then
			textLabel.Text = config.Name
		end
	end

	if config.SettingType == "toggle" then
		self:_setupToggleRow(row, settingKey, config)
	elseif config.SettingType == "slider" then
		self:_setupSliderRow(row, settingKey, config)
	elseif config.SettingType == "keybind" then
		self:_setupKeybindRow(row, settingKey, config)
	elseif config.SettingType == "divider" then
		return row
	end

	self:_setupSettingHover(row, settingKey)
	self:_setupSettingClick(row, settingKey)

	return row
end

function module:_createResetButton(parent: ScrollingFrame, categoryKey: string)
	local template = SettingsConfig.Templates.Reset
	if not template then
		return
	end

	local reset = template:Clone()
	reset.Name = "ResetButton"
	reset.LayoutOrder = 999
	reset.Visible = true
	reset.Parent = parent

	local action = reset:FindFirstChild("Action")
	if action then
		local holder = action:FindFirstChild("HOLDER")
		if holder then
			local textLabel = holder:FindFirstChild("TextLabel")
			if textLabel then
				textLabel.Text = "RESET TO DEFAULT"
			end
		end

		local button = action:FindFirstChildWhichIsA("TextButton") or action:FindFirstChildWhichIsA("ImageButton")
		if button then
			button.Active = true
			self._connections:track(button, "Activated", function()
				if not self._buttonsActive or self._overlayOpen then
					return
				end
				self:_openActionUI(categoryKey)
			end, "settingRows")
		else
			self._connections:track(action, "InputBegan", function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					if not self._buttonsActive or self._overlayOpen then
						return
					end
					self:_openActionUI(categoryKey)
				end
			end, "settingRows")
		end
	end
end

function module:_setupToggleRow(row: Frame, settingKey: string, config)
	local action = row:FindFirstChild("Action")
	if not action then
		return
	end

	local actionFrame = action:FindFirstChild("Action")
	if not actionFrame then
		return
	end

	local buttons = actionFrame:FindFirstChild("BUTTONS")
	local holder = actionFrame:FindFirstChild("HOLDER")

	if not buttons or not holder then
		return
	end

	local leftBtn = buttons:FindFirstChild("Left")
	local rightBtn = buttons:FindFirstChild("Right")
	local textLabel = holder:FindFirstChild("TextLabel")
	local selctedContainer = holder:FindFirstChild("Selcted")

	local actionUIScale = actionFrame:FindFirstChild("UIScale")

	local currentValue = PlayerDataTable.get(self._currentCategory, settingKey)
	if currentValue == nil then
		currentValue = config.Default or 1
	end

	local templateOptions = {}
	local optionCount = SettingsConfig.getOptionCount(config)

	if selctedContainer then
		local templateSource = selctedContainer:FindFirstChild("Template")
		if templateSource then
			for i = 1, optionCount do
				local option = SettingsConfig.getOptionByIndex(config, i)
				if option then
					local template
					if i == 1 then
						template = templateSource
					else
						template = templateSource:Clone()
						template.Parent = selctedContainer
					end

					template.Name = "Option_" .. i
					template.LayoutOrder = i
					template.Visible = true

					if option.Color then
						template.BackgroundColor3 = option.Color
					end

					templateOptions[i] = template
				end
			end
		end
	end

	local function updateTemplateVisuals(selectedIndex)
		for idx, template in templateOptions do
			local isSelected = (idx == selectedIndex)
			local targetScaleY = isSelected and TweenConfig.Values.TemplateSelectedScaleY or TweenConfig.Values.TemplateDeselectedScaleY
			local targetTransparency = isSelected and TweenConfig.Values.TemplateSelectedTransparency or TweenConfig.Values.TemplateDeselectedTransparency

			cancelTweenGroup("template_" .. settingKey .. "_" .. idx)

			local tween = TweenService:Create(template, TweenConfig.createCustom(
				isSelected and TweenConfig.Durations.TemplateSelect or TweenConfig.Durations.TemplateDeselect,
				isSelected and "Select" or "HoverOut"
			), {
				Size = UDim2.new(template.Size.X.Scale, template.Size.X.Offset, targetScaleY, 0),
				BackgroundTransparency = targetTransparency,
			})
			tween:Play()
			currentTweens["template_" .. settingKey .. "_" .. idx] = {tween}
		end
	end

	local function selectValue(index)
		if index == currentValue then
			return
		end
		currentValue = index
		PlayerDataTable.set(self._currentCategory, settingKey, currentValue)
		local option = SettingsConfig.getOptionByIndex(config, index)
		if option and textLabel then
			textLabel.Text = option.Display:upper()
		end
		updateTemplateVisuals(index)
	end

	for i, template in templateOptions do
		self._connections:track(template, "InputBegan", function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if not self._buttonsActive or self._overlayOpen then
					return
				end
				self:_selectSetting(settingKey)
				selectValue(i)
			end
		end, "settingRows")
	end

	local function updateDisplay(index)
		local option = SettingsConfig.getOptionByIndex(config, index)
		if option and textLabel then
			textLabel.Text = option.Display:upper()
		end
		updateTemplateVisuals(index)
	end

	updateDisplay(currentValue)

	local function changeValue(delta)
		local newIndex = currentValue + delta

		if newIndex < 1 then
			self:_flashArrowRed(leftBtn)
			return
		elseif newIndex > optionCount then
			self:_flashArrowRed(rightBtn)
			return
		end

		currentValue = newIndex
		PlayerDataTable.set(self._currentCategory, settingKey, currentValue)
		updateDisplay(currentValue)
	end

	if leftBtn then
		self._connections:track(leftBtn, "Activated", function()
			if not self._buttonsActive or self._overlayOpen then
				return
			end
			self:_selectSetting(settingKey)
			changeValue(-1)
		end, "settingRows")
	end

	if rightBtn then
		self._connections:track(rightBtn, "Activated", function()
			if not self._buttonsActive or self._overlayOpen then
				return
			end
			self:_selectSetting(settingKey)
			changeValue(1)
		end, "settingRows")
	end

	row:SetAttribute("ToggleActionFrame", true)
	row:SetAttribute("ToggleSettingKey", settingKey)

	self._toggleRowData = self._toggleRowData or {}
	self._toggleRowData[settingKey] = {
		actionFrame = actionFrame,
		actionUIScale = actionUIScale,
		updateDisplay = updateDisplay,
		getCurrentValue = function() return currentValue end,
		setCurrentValue = function(v) currentValue = v end,
	}
end

function module:_setupSliderRow(row: Frame, settingKey: string, config)
	local action = row:FindFirstChild("Action")
	if not action then
		return
	end

	local actionFrame = action:FindFirstChild("Action")
	if not actionFrame then
		return
	end

	local buttons = actionFrame:FindFirstChild("BUTTONS")
	local holder = actionFrame:FindFirstChild("HOLDER")

	if not buttons or not holder then
		return
	end

	local leftBtn = buttons:FindFirstChild("Left")
	local rightBtn = buttons:FindFirstChild("Right")
	local drag = holder:FindFirstChild("Drag")
	local fillFrame = holder:FindFirstChild("Frame")

	local sliderConfig = config.Slider
	if not sliderConfig then
		return
	end

	local currentValue = PlayerDataTable.get(self._currentCategory, settingKey)
	if currentValue == nil then
		currentValue = sliderConfig.Default
	end

	local handleWidthScale = 0
	local minPadding = TweenConfig.Values.SliderMinPadding
	local maxPadding = TweenConfig.Values.SliderMaxPadding
	local gradientOffset = TweenConfig.Values.SliderGradientOffset

	local function getMinPos()
		return handleWidthScale + minPadding
	end

	local function getMaxPos()
		return 1 - maxPadding
	end

	local function valueToPosition(value)
		local percentage = (value - sliderConfig.Min) / (sliderConfig.Max - sliderConfig.Min)
		percentage = math.clamp(percentage, 0, 1)
		local minPos = getMinPos()
		local maxPos = getMaxPos()
		return minPos + percentage * (maxPos - minPos)
	end

	local function positionToValue(position)
		local minPos = getMinPos()
		local maxPos = getMaxPos()
		local normalizedPos = (position - minPos) / (maxPos - minPos)
		normalizedPos = math.clamp(normalizedPos, 0, 1)
		return sliderConfig.Min + normalizedPos * (sliderConfig.Max - sliderConfig.Min)
	end

	local function updateDisplay(value)
		if drag then
			local textLabel = drag:FindFirstChild("TextLabel")
			if textLabel then
				textLabel.Text = tostring(math.floor(value))
			end
		end

		local position = valueToPosition(value)

		if drag then
			drag.Position = UDim2.new(position, 0, 0.5, 0)
		end

		if fillFrame then
			local gradient = fillFrame:FindFirstChild("UIGradient")
			if gradient then
				local percentage = (value - sliderConfig.Min) / (sliderConfig.Max - sliderConfig.Min)
				percentage = math.clamp(percentage, 0, 1)
				gradient.Offset = Vector2.new((percentage - 1) + gradientOffset, 0)
			end
		end
	end

	if drag and holder then
		task.defer(function()
			if drag.AbsoluteSize.X > 0 and holder.AbsoluteSize.X > 0 then
				handleWidthScale = drag.AbsoluteSize.X / holder.AbsoluteSize.X
			end
			updateDisplay(currentValue)
		end)
	else
		updateDisplay(currentValue)
	end

	local function changeValue(delta)
		local newValue = currentValue + delta * sliderConfig.Step
		newValue = math.clamp(newValue, sliderConfig.Min, sliderConfig.Max)

		if newValue == currentValue then
			if delta < 0 then
				self:_flashArrowRed(leftBtn)
			else
				self:_flashArrowRed(rightBtn)
			end
			return
		end

		currentValue = newValue
		PlayerDataTable.set(self._currentCategory, settingKey, currentValue)
		updateDisplay(currentValue)
	end

	if leftBtn then
		self._connections:track(leftBtn, "Activated", function()
			if not self._buttonsActive or self._overlayOpen then
				return
			end
			self:_selectSetting(settingKey)
			changeValue(-1)
		end, "settingRows")
	end

	if rightBtn then
		self._connections:track(rightBtn, "Activated", function()
			if not self._buttonsActive or self._overlayOpen then
				return
			end
			self:_selectSetting(settingKey)
			changeValue(1)
		end, "settingRows")
	end

	if drag then
		local dragDetector = drag:FindFirstChild("UIDragDetector")
		if dragDetector then
			self._connections:track(dragDetector, "DragStart", function()
				if not self._buttonsActive or self._overlayOpen then
					return
				end
				self:_selectSetting(settingKey)
			end, "sliders")

			self._connections:track(dragDetector, "DragContinue", function()
				if not self._buttonsActive or self._overlayOpen then
					return
				end

				local holderAbsSize = holder.AbsoluteSize.X
				local dragAbsPos = drag.AbsolutePosition.X
				local holderAbsPos = holder.AbsolutePosition.X
				local dragWidth = drag.AbsoluteSize.X

				if handleWidthScale == 0 and holderAbsSize > 0 then
					handleWidthScale = dragWidth / holderAbsSize
				end

				local dragRightEdge = dragAbsPos + dragWidth
				local relativeX = (dragRightEdge - holderAbsPos) / holderAbsSize
				relativeX = math.clamp(relativeX, getMinPos(), getMaxPos())

				local rawValue = positionToValue(relativeX)

				local snappedValue = math.floor(rawValue / sliderConfig.Step + 0.5) * sliderConfig.Step
				snappedValue = math.clamp(snappedValue, sliderConfig.Min, sliderConfig.Max)

				currentValue = snappedValue
				updateDisplay(currentValue)
			end, "sliders")

			self._connections:track(dragDetector, "DragEnd", function()
				PlayerDataTable.set(self._currentCategory, settingKey, currentValue)
			end, "sliders")
		end
	end
end

function module:_setupKeybindRow(row: Frame, settingKey: string, config)
	local action = row:FindFirstChild("Action")
	if not action then
		return
	end

	local actionFrame = action:FindFirstChild("Action")
	if not actionFrame then
		return
	end

	local pcBtn = actionFrame:FindFirstChild("PC")
	local pc2Btn = actionFrame:FindFirstChild("PC2")
	local consoleBtn = actionFrame:FindFirstChild("CONSOLE")

	local binds = PlayerDataTable.get("Controls", settingKey)
	if not binds then
		binds = config.DefaultBind or {}
	end

	local function updateBindDisplay()
		binds = PlayerDataTable.get("Controls", settingKey) or {}

		if pcBtn then
			pcBtn.Image = ActionsIcon.getBindIcon(binds.PC, "PC")
		end
		if pc2Btn then
			pc2Btn.Image = ActionsIcon.getBindIcon(binds.PC2, "PC")
		end
		if consoleBtn then
			consoleBtn.Image = ActionsIcon.getBindIcon(binds.Console, "Console")
		end
	end

	updateBindDisplay()

	row:SetAttribute("UpdateBindDisplay", true)
	row.AttributeChanged:Connect(function(attr)
		if attr == "UpdateBindDisplay" then
			updateBindDisplay()
		end
	end)

	if pcBtn then
		pcBtn.Active = true
		self._connections:track(pcBtn, "Activated", function()
			if not self._buttonsActive or self._overlayOpen then
				return
			end
			self:_openKeybindUI(settingKey, "PC", config)
		end, "settingRows")
	end

	if pc2Btn then
		pc2Btn.Active = true
		self._connections:track(pc2Btn, "Activated", function()
			if not self._buttonsActive or self._overlayOpen then
				return
			end
			self:_openKeybindUI(settingKey, "PC2", config)
		end, "settingRows")
	end

	if consoleBtn then
		consoleBtn.Active = true
		self._connections:track(consoleBtn, "Activated", function()
			if not self._buttonsActive or self._overlayOpen then
				return
			end
			self:_openKeybindUI(settingKey, "Console", config)
		end, "settingRows")
	end
end

function module:_setupSettingHover(row: Frame, settingKey: string)
	local action = row:FindFirstChild("Action")
	if not action then
		return
	end

	local uiScale = action:FindFirstChild("UIScale")
	local isHovering = false

	self._connections:track(row, "MouseEnter", function()
		if isHovering or self._overlayOpen then
			return
		end
		isHovering = true

		if self._selectedSetting == settingKey then
			return
		end

		cancelTweenGroup("hover_" .. settingKey)

		if uiScale then
			local tween = TweenService:Create(uiScale, TweenConfig.create("SettingHover"), {
				Scale = TweenConfig.Values.SettingRowHoverScale,
			})
			tween:Play()
			currentTweens["hover_" .. settingKey] = {tween}
		end

		self:_showToggleAction(settingKey)
	end, "settingRows")

	self._connections:track(row, "MouseLeave", function()
		if not isHovering then
			return
		end
		isHovering = false

		if self._selectedSetting == settingKey then
			return
		end

		cancelTweenGroup("hover_" .. settingKey)

		if uiScale then
			local tween = TweenService:Create(uiScale, TweenConfig.create("SettingHoverOut"), {
				Scale = 1,
			})
			tween:Play()
			currentTweens["hover_" .. settingKey] = {tween}
		end

		self:_hideToggleAction(settingKey)
	end, "settingRows")
end

function module:_showToggleAction(settingKey: string)
	if not self._toggleRowData or not self._toggleRowData[settingKey] then
		return
	end

	local data = self._toggleRowData[settingKey]
	if not data.actionUIScale then
		return
	end

	cancelTweenGroup("toggleAction_" .. settingKey)

	local tween = TweenService:Create(data.actionUIScale, TweenConfig.createCustom(TweenConfig.Durations.ActionShow, "Select"), {
		Scale = TweenConfig.Values.ActionShowScale,
	})
	tween:Play()
	currentTweens["toggleAction_" .. settingKey] = {tween}
end

function module:_hideToggleAction(settingKey: string)
	if not self._toggleRowData or not self._toggleRowData[settingKey] then
		return
	end

	local data = self._toggleRowData[settingKey]
	if not data.actionUIScale then
		return
	end

	cancelTweenGroup("toggleAction_" .. settingKey)

	local tween = TweenService:Create(data.actionUIScale, TweenConfig.createCustom(TweenConfig.Durations.ActionHide, "HoverOut"), {
		Scale = TweenConfig.Values.ActionHideScale,
	})
	tween:Play()
	currentTweens["toggleAction_" .. settingKey] = {tween}
end

function module:_setupSettingClick(row: Frame, settingKey: string)
	local action = row:FindFirstChild("Action")
	if not action then
		return
	end

	local actionInner = action:FindFirstChild("Action")

	if actionInner then
		self._connections:track(actionInner, "InputBegan", function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if not self._buttonsActive or self._overlayOpen then
					return
				end
				self:_selectSetting(settingKey)
			end
		end, "settingRows")
	end
end

function module:_selectSetting(settingKey: string)
	if self._selectedSetting == settingKey then
		return
	end

	self:_deselectSetting()
	self._selectedSetting = settingKey

	local rowData = nil
	for _, data in self._settingRows do
		if data.key == settingKey then
			rowData = data
			break
		end
	end

	if rowData then
		self:_animateSettingSelect(rowData.row)
		self:_updateInfoPanel(settingKey, rowData.config)
	end
end

function module:_deselectSetting()
	if not self._selectedSetting then
		return
	end

	local prevKey = self._selectedSetting
	self._selectedSetting = nil

	for _, data in self._settingRows do
		if data.key == prevKey then
			self:_animateSettingDeselect(data.row)
			break
		end
	end
end

function module:_animateSettingSelect(row: Frame)
	local action = row:FindFirstChild("Action")
	if not action then
		return
	end

	local actionInner = action:FindFirstChild("Action")

	local uiScale = action:FindFirstChild("UIScale")
	local selectFrame = actionInner and actionInner:FindFirstChild("Select") or action:FindFirstChild("Select")

	local settingKey = row.Name:gsub("Setting_", "")
	cancelTweenGroup("select_" .. settingKey)

	local tweens = {}

	if uiScale then
		local tween = TweenService:Create(uiScale, TweenConfig.create("SettingSelect"), {
			Scale = TweenConfig.Values.SettingRowHoverScale,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	if selectFrame then
		local glow = selectFrame:FindFirstChild("Glow")
		local bottomBar = selectFrame:FindFirstChild("BottomBar")

		if glow then
			local gradient = glow:FindFirstChild("UIGradient")
			if gradient then
				local tween = TweenService:Create(gradient, TweenConfig.create("SettingSelect"), {
					Offset = Vector2.new(0, 0),
				})
				tween:Play()
				table.insert(tweens, tween)
			end
		end

		if bottomBar then
			local tween = TweenService:Create(bottomBar, TweenConfig.create("SettingSelect"), {
				BackgroundTransparency = 0,
			})
			tween:Play()
			table.insert(tweens, tween)
		end
	end

	currentTweens["select_" .. settingKey] = tweens

	self:_showToggleAction(settingKey)
end

function module:_animateSettingDeselect(row: Frame)
	local action = row:FindFirstChild("Action")
	if not action then
		return
	end

	local actionInner = action:FindFirstChild("Action")

	local uiScale = action:FindFirstChild("UIScale")
	local selectFrame = actionInner and actionInner:FindFirstChild("Select") or action:FindFirstChild("Select")

	local settingKey = row.Name:gsub("Setting_", "")
	cancelTweenGroup("select_" .. settingKey)

	local tweens = {}

	if uiScale then
		local tween = TweenService:Create(uiScale, TweenConfig.create("SettingDeselect"), {
			Scale = 1,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	if selectFrame then
		local glow = selectFrame:FindFirstChild("Glow")
		local bottomBar = selectFrame:FindFirstChild("BottomBar")

		if glow then
			local gradient = glow:FindFirstChild("UIGradient")
			if gradient then
				local tween = TweenService:Create(gradient, TweenConfig.create("SettingDeselect"), {
					Offset = Vector2.new(0, 1),
				})
				tween:Play()
				table.insert(tweens, tween)
			end
		end

		if bottomBar then
			local tween = TweenService:Create(bottomBar, TweenConfig.create("SettingDeselect"), {
				BackgroundTransparency = 1,
			})
			tween:Play()
			table.insert(tweens, tween)
		end
	end

	currentTweens["select_" .. settingKey] = tweens

	self:_hideToggleAction(settingKey)
end

function module:_updateInfoPanel(settingKey: string, config)
	if not self._infoPanel then
		return
	end

	local title = self._infoPanel:FindFirstChild("Title")
	local header = self._infoPanel:FindFirstChild("Header")
	local textFrame = self._infoPanel:FindFirstChild("Text")
	local imageFrame = self._infoPanel:FindFirstChild("ImageFrame")
	local videoFrame = self._infoPanel:FindFirstChild("VideoFrame")

	if title then
		title.Text = config.Name
		title.TextTransparency = 0
		title.Visible = true
	end

	if header then
		if config.Header then
			header.Text = config.Header:upper()
			header.TextTransparency = 0
			header.Visible = true
		else
			header.Visible = false
		end
	end

	if textFrame then
		textFrame.Visible = true
		local descriptionLabel = textFrame:FindFirstChild("Text")
		if descriptionLabel then
			descriptionLabel.Text = config.Description
			descriptionLabel.TextTransparency = 0
			descriptionLabel.Visible = true
		end
	end

	self:_stopImageCarousel()
	self:_stopVideo()

	self._currentInfoImages = nil

	if config.Video then
		if imageFrame then
			imageFrame.Visible = false
		end
		if videoFrame then
			videoFrame.Visible = true
			self:_playVideo(config.Video)
		end
	elseif config.Image and #config.Image > 0 then
		if videoFrame then
			videoFrame.Visible = false
		end
		if imageFrame then
			imageFrame.Visible = true
			self._currentInfoImages = config.Image
			self:_startImageCarousel(config.Image, imageFrame)
		end
	else
		if imageFrame then
			imageFrame.Visible = false
		end
		if videoFrame then
			videoFrame.Visible = false
		end
	end

	self:_showInfoPanel()
end

function module:_showInfoPanel()
	if not self._infoPanel then
		return
	end

	self._infoPanel.Visible = true
end

function module:_hideInfoPanel()
	if not self._infoPanel then
		return
	end

	self:_stopImageCarousel()
	self:_stopVideo()
end

function module:_startImageCarousel(images: {string}, imageFrame: Frame)
	if #images == 0 then
		return
	end

	local holder = imageFrame:FindFirstChild("Holder")
	if not holder then
		return
	end

	local canvas = holder:FindFirstChild("CanvasGroup")
	if not canvas then
		return
	end

	local currentImg = canvas:FindFirstChild("Current")
	local nextTemplate = canvas:FindFirstChild("Next")

	if not currentImg or not nextTemplate then
		return
	end

	local originalPosition = currentImg.Position

	self._currentImageIndex = 1
	currentImg.Image = images[1]
	currentImg.Position = originalPosition
	nextTemplate.Visible = false

	local maximizeBtn = holder:FindFirstChild("maximize")
	if maximizeBtn then
		self._connections:track(maximizeBtn, "InputBegan", function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if not self._buttonsActive or self._overlayOpen then
					return
				end
				self:_openImageUI(images[self._currentImageIndex])
			end
		end, "settingRows")
	end

	if #images <= 1 then
		return
	end

	self._imageCarouselConnection = task.spawn(function()
		while true do
			task.wait(TweenConfig.Durations.ImageCarouselInterval)

			if not self._infoPanel or not self._infoPanel.Visible then
				break
			end

			self._currentImageIndex = self._currentImageIndex % #images + 1

			local startPosition = UDim2.new(
				originalPosition.X.Scale,
				originalPosition.X.Offset,
				originalPosition.Y.Scale - 1,
				originalPosition.Y.Offset
			)

			local nextClone = nextTemplate:Clone()
			nextClone.Name = "NextClone"
			nextClone.Image = images[self._currentImageIndex]
			nextClone.Position = startPosition
			nextClone.Visible = true
			nextClone.Parent = canvas

			local slideInTween = TweenService:Create(nextClone, TweenConfig.createCustom(TweenConfig.Durations.ImageCarouselSwap, "Show"), {
				Position = originalPosition,
			})

			slideInTween:Play()
			slideInTween.Completed:Wait()

			currentImg.Image = images[self._currentImageIndex]
			currentImg.Position = originalPosition
			nextClone:Destroy()

			if self._overlayOpen == "Image" then
				self:_updateFullscreenImage(images[self._currentImageIndex])
			end
		end
	end)
end

function module:_updateFullscreenImage(imageId: string)
	if not self._videoUI then
		return
	end

	local imageFrame = self._videoUI:FindFirstChild("ImageFrame")
	if imageFrame then
		local holder = imageFrame:FindFirstChild("Holder")
		if holder then
			local canvas = holder:FindFirstChild("CanvasGroup")
			if canvas then
				local image = canvas:FindFirstChild("ImageLabel")
				if image then
					image.Image = imageId
				end
			end
		end
	end
end

function module:_stopImageCarousel()
	if self._imageCarouselConnection then
		task.cancel(self._imageCarouselConnection)
		self._imageCarouselConnection = nil
	end
end

function module:_playVideo(videoId: string)
	if not self._infoPanel then
		return
	end

	local videoFrame = self._infoPanel:FindFirstChild("VideoFrame")
	if not videoFrame then
		return
	end

	local videoHolder = videoFrame:FindFirstChild("VideoHolder")
	if not videoHolder then
		return
	end

	local video = videoHolder:FindFirstChild("VideoFrame")
	if not video then
		return
	end

	video.Video = videoId
	video.Playing = true
	video.Looped = true
	self._videoPlaying = true

	local maximizeBtn = videoHolder:FindFirstChild("maximize")
	if maximizeBtn then
		self._connections:track(maximizeBtn, "Activated", function()
			if not self._buttonsActive or self._overlayOpen then
				return
			end
			self:_openVideoUI(videoId)
		end, "settingRows")
	end
end

function module:_stopVideo()
	if not self._infoPanel then
		return
	end

	local videoFrame = self._infoPanel:FindFirstChild("VideoFrame")
	if not videoFrame then
		return
	end

	local videoHolder = videoFrame:FindFirstChild("VideoHolder")
	if not videoHolder then
		return
	end

	local video = videoHolder:FindFirstChild("VideoFrame")
	if video then
		video.Playing = false
	end

	self._videoPlaying = false
end

function module:_flashArrowRed(arrow: ImageButton?)
	if not arrow then
		return
	end

	self._arrowOriginalColors = self._arrowOriginalColors or {}
	local arrowKey = arrow:GetFullName()

	if not self._arrowOriginalColors[arrowKey] then
		self._arrowOriginalColors[arrowKey] = arrow.ImageColor3
	end

	local originalColor = self._arrowOriginalColors[arrowKey]
	local uiScale = arrow:FindFirstChild("UIScale")

	cancelTweenGroup("arrow_" .. arrowKey)

	local tweens = {}

	local colorTween = TweenService:Create(arrow, TweenConfig.create("Flash"), {
		ImageColor3 = TweenConfig.Values.FlashRedColor,
	})
	colorTween:Play()
	table.insert(tweens, colorTween)

	if uiScale then
		local scaleTween = TweenService:Create(uiScale, TweenConfig.createCustom(TweenConfig.Durations.ArrowPress, "Flash"), {
			Scale = TweenConfig.Values.ArrowPressScale,
		})
		scaleTween:Play()
		table.insert(tweens, scaleTween)
	end

	colorTween.Completed:Once(function()
		local revertTween = TweenService:Create(arrow, TweenConfig.create("Flash"), {
			ImageColor3 = originalColor,
		})
		revertTween:Play()

		if uiScale then
			local scaleRevert = TweenService:Create(uiScale, TweenConfig.createCustom(TweenConfig.Durations.ArrowPress, "Flash"), {
				Scale = 1,
			})
			scaleRevert:Play()
		end
	end)

	currentTweens["arrow_" .. arrowKey] = tweens
end

function module:_setupOverlays()
	self:_setupKeybindOverlay()
	self:_setupActionOverlay()
	self:_setupVideoOverlay()
end

function module:_dimSettings()
	if not self._options then
		return
	end

	cancelTweenGroup("dim")

	local tween = TweenService:Create(self._options, TweenConfig.create("OverlayFadeIn"), {
		GroupTransparency = TweenConfig.Values.SettingsUIOverlayTransparency,
	})
	tween:Play()
	currentTweens["dim"] = {tween}

	if self._blurUI then
		self._blurUI.Visible = true
		local blurTween = TweenService:Create(self._blurUI, TweenConfig.create("BlurFadeIn"), {
			GroupTransparency = TweenConfig.Values.BlurOverlayTransparency,
		})
		blurTween:Play()
	end
end

function module:_undimSettings()
	if not self._options then
		return
	end

	cancelTweenGroup("dim")

	local tween = TweenService:Create(self._options, TweenConfig.create("OverlayFadeOut"), {
		GroupTransparency = 0,
	})
	tween:Play()
	currentTweens["dim"] = {tween}

	if self._blurUI then
		local blurTween = TweenService:Create(self._blurUI, TweenConfig.create("BlurFadeOut"), {
			GroupTransparency = 1,
		})
		blurTween:Play()
		blurTween.Completed:Once(function()
			self._blurUI.Visible = false
		end)
	end
end

function module:_setupKeybindOverlay()
	if not self._keybindUI then
		return
	end

	self._keybindUI.Visible = false
	self._keybindUI.GroupTransparency = 1

	local actions = self._keybindUI:FindFirstChild("Actions")
	if actions then
		local returnFrame = actions:FindFirstChild("Return")
		if returnFrame then
			local action = returnFrame:FindFirstChild("Action")
			if action then
				self._connections:track(action, "Activated", function()
					self:_closeKeybindUI(true)
				end, "keybindOverlay")
			end
		end
	end
end

function module:_openKeybindUI(settingKey: string, slot: string, config)
	if self._overlayOpen then
		return
	end

	self._overlayOpen = "Keybind"
	self._awaitingKeybind = {
		settingKey = settingKey,
		slot = slot,
		config = config,
	}

	if self._keybindUI then
		local header = self._keybindUI:FindFirstChild("Header")
		if header then
			local textLabel = header:FindFirstChild("TextLabel")
			if textLabel then
				textLabel.Text = "REBIND " .. config.Name:upper()
			end
		end

		local info = self._keybindUI:FindFirstChild("Info")
		if info then
			local description = info:FindFirstChild("Description")
			if description then
				description.Text = "PRESS ANY KEY TO REBIND " .. config.Name:upper()
			end
		end

		local actions = self._keybindUI:FindFirstChild("Actions")
		if actions then
			local returnFrame = actions:FindFirstChild("Return")
			if returnFrame then
				local action = returnFrame:FindFirstChild("Action")
				if action then
					local holder = action:FindFirstChild("HOLDER")
					if holder then
						local textLabel = holder:FindFirstChild("TextLabel")
						if textLabel then
							textLabel.Text = "AWAITING INPUT..."
						end
					end
				end
			end
		end

		self._keybindUI.Visible = true
		local tween = TweenService:Create(self._keybindUI, TweenConfig.create("OverlayFadeIn"), {
			GroupTransparency = 0,
		})
		tween:Play()
	end

	self:_dimSettings()
	self:_awaitKeybindInput()
end

function module:_awaitKeybindInput()
	if not self._awaitingKeybind then
		return
	end

	self._keybindInputConnection = self._connections:track(UserInputService, "InputBegan", function(input, _gameProcessed)
		if not self._awaitingKeybind then
			return
		end

		local keyCode = input.KeyCode
		if keyCode == Enum.KeyCode.Unknown then
			return
		end

		if keyCode == Enum.KeyCode.Escape then
			self:_closeKeybindUI(true)
			return
		end

		if keyCode == Enum.KeyCode.Delete or keyCode == Enum.KeyCode.Backspace then
			self:_applyKeybind(nil)
			self:_closeKeybindUI(false)
			return
		end

		if SettingsConfig.isKeyBlocked(keyCode) then
			return
		end

		self:_applyKeybind(keyCode)
		self:_closeKeybindUI(false)
	end, "keybindInput")
end

function module:_applyKeybind(keyCode: Enum.KeyCode?)
	if not self._awaitingKeybind then
		return
	end

	local settingKey = self._awaitingKeybind.settingKey
	local slot = self._awaitingKeybind.slot

	if keyCode then
		local conflicts = PlayerDataTable.getConflicts(keyCode, settingKey, slot)
		for _, conflict in conflicts do
			PlayerDataTable.setBind(conflict.settingKey, conflict.slot, nil)
		end
	end

	PlayerDataTable.setBind(settingKey, slot, keyCode)

	for _, rowData in self._settingRows do
		if rowData.row:GetAttribute("UpdateBindDisplay") ~= nil then
			rowData.row:SetAttribute("UpdateBindDisplay", not rowData.row:GetAttribute("UpdateBindDisplay"))
		end
	end

	self:_updateConflicts()
end

function module:_closeKeybindUI(_cancelled: boolean)
	self._connections:cleanupGroup("keybindInput")
	self._awaitingKeybind = nil
	self._overlayOpen = nil

	if self._keybindUI then
		local tween = TweenService:Create(self._keybindUI, TweenConfig.create("OverlayFadeOut"), {
			GroupTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			self._keybindUI.Visible = false
		end)
	end

	self:_undimSettings()
end

function module:_updateConflicts()
	table.clear(self._conflictingSettings)

	local allBinds = {}
	for _, rowData in self._settingRows do
		if rowData.config.SettingType ~= "keybind" then
			continue
		end

		local binds = PlayerDataTable.get("Controls", rowData.key)
		if not binds then
			continue
		end

		for slot, keyCode in binds do
			if keyCode then
				if not allBinds[keyCode] then
					allBinds[keyCode] = {}
				end
				table.insert(allBinds[keyCode], {key = rowData.key, slot = slot})
			end
		end
	end

	for _, usages in allBinds do
		if #usages > 1 then
			for _, usage in usages do
				self._conflictingSettings[usage.key .. "_" .. usage.slot] = true
			end
		end
	end

	for _, rowData in self._settingRows do
		if rowData.config.SettingType ~= "keybind" then
			continue
		end

		local infoFrame = rowData.row:FindFirstChild("Info")
		if infoFrame then
			local hasConflict = false
			for slot in {"PC", "PC2", "Console"} do
				if self._conflictingSettings[rowData.key .. "_" .. slot] then
					hasConflict = true
					break
				end
			end

			if hasConflict then
				infoFrame.BackgroundColor3 = TweenConfig.Values.ConflictBgColor
				local textLabel = infoFrame:FindFirstChild("TextLabel")
				if textLabel then
					textLabel.TextColor3 = TweenConfig.Values.ConflictRedColor
				end
			else
				local gradient = infoFrame:FindFirstChild("UIGradient")
				if gradient then
					infoFrame.BackgroundColor3 = Color3.new(1, 1, 1)
				end
				local textLabel = infoFrame:FindFirstChild("TextLabel")
				if textLabel then
					textLabel.TextColor3 = Color3.new(1, 1, 1)
				end
			end
		end
	end
end

function module:_setupActionOverlay()
	if not self._actionUI then
		return
	end

	self._actionUI.Visible = false
	self._actionUI.GroupTransparency = 1

	local actions = self._actionUI:FindFirstChild("Actions")
	if actions then
		local resetFrame = actions:FindFirstChild("Reset")
		if resetFrame then
			local action = resetFrame:FindFirstChild("Action")
			if action then
				self._connections:track(action, "Activated", function()
					self:_confirmReset()
				end, "actionOverlay")
			end
		end

		local returnFrame = actions:FindFirstChild("Return")
		if returnFrame then
			local action = returnFrame:FindFirstChild("Action")
			if action then
				self._connections:track(action, "Activated", function()
					self:_closeActionUI()
				end, "actionOverlay")
			end
		end
	end
end

function module:_openActionUI(categoryKey: string)
	if self._overlayOpen then
		return
	end

	self._overlayOpen = "Action"
	self._resetCategory = categoryKey

	local categoryConfig = SettingsConfig.getCategory(categoryKey)
	local displayName = categoryConfig and categoryConfig.DisplayName or categoryKey

	if self._actionUI then
		local header = self._actionUI:FindFirstChild("Header")
		if header then
			local textLabel = header:FindFirstChild("TextLabel")
			if textLabel then
				textLabel.Text = "ARE YOU SURE?"
			end
		end

		local info = self._actionUI:FindFirstChild("Info")
		if info then
			local textLabel = info:FindFirstChild("TextLabel")
			if textLabel then
				textLabel.Text = "ARE YOU SURE YOU WOULD LIKE TO RESET " .. displayName:upper() .. " SETTINGS TO DEFAULT?"
			end
		end

		local actions = self._actionUI:FindFirstChild("Actions")
		if actions then
			local resetFrame = actions:FindFirstChild("Reset")
			if resetFrame then
				local action = resetFrame:FindFirstChild("Action")
				if action then
					local holder = action:FindFirstChild("HOLDER")
					if holder then
						local textLabel = holder:FindFirstChild("TextLabel")
						if textLabel then
							textLabel.Text = "RESET TO DEFAULT"
						end
					end
				end
			end

			local returnFrame = actions:FindFirstChild("Return")
			if returnFrame then
				local action = returnFrame:FindFirstChild("Action")
				if action then
					local holder = action:FindFirstChild("HOLDER")
					if holder then
						local textLabel = holder:FindFirstChild("TextLabel")
						if textLabel then
							textLabel.Text = "RETURN"
						end
					end
				end
			end
		end

		self._actionUI.Visible = true
		local tween = TweenService:Create(self._actionUI, TweenConfig.create("OverlayFadeIn"), {
			GroupTransparency = 0,
		})
		tween:Play()
	end

	self:_dimSettings()
end

function module:_confirmReset()
	if not self._resetCategory then
		return
	end

	local categoryToReset = self._resetCategory
	PlayerDataTable.resetCategory(categoryToReset)
	self:_closeActionUI()

	self:_clearSettings()
	self:_populateSettings(self._currentCategory)
end

function module:_closeActionUI()
	self._overlayOpen = nil
	self._resetCategory = nil

	if self._actionUI then
		local tween = TweenService:Create(self._actionUI, TweenConfig.create("OverlayFadeOut"), {
			GroupTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			self._actionUI.Visible = false
		end)
	end

	self:_undimSettings()
end

function module:_setupVideoOverlay()
	if not self._videoUI then
		return
	end

	self._videoUI.Visible = false
	self._videoUI.GroupTransparency = 1

	local videoFrame = self._videoUI:FindFirstChild("VideoFrame")
	if videoFrame then
		local videoHolder = videoFrame:FindFirstChild("VideoHolder")
		if videoHolder then
			local minimizeBtn = videoHolder:FindFirstChild("minimize")
			if minimizeBtn then
				self._connections:track(minimizeBtn, "Activated", function()
					self:_closeVideoUI()
				end, "videoOverlay")
			end
		end
	end

	local imageFrame = self._videoUI:FindFirstChild("ImageFrame")
	if imageFrame then
		local holder = imageFrame:FindFirstChild("Holder")
		if holder then
			local minimizeBtn = holder:FindFirstChild("minimize")
			if minimizeBtn then
				self._connections:track(minimizeBtn, "Activated", function()
					self:_closeImageUI()
				end, "imageOverlay")

				self._connections:track(minimizeBtn, "InputBegan", function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						self:_closeImageUI()
					end
				end, "imageOverlay")
			end
		end
	end
end

function module:_openVideoUI(videoId: string)
	if self._overlayOpen then
		return
	end

	self._overlayOpen = "Video"

	if self._videoUI then
		local imageFrame = self._videoUI:FindFirstChild("ImageFrame")
		if imageFrame then
			imageFrame.Visible = false
		end

		local videoFrame = self._videoUI:FindFirstChild("VideoFrame")
		if videoFrame then
			videoFrame.Visible = true
			local videoHolder = videoFrame:FindFirstChild("VideoHolder")
			if videoHolder then
				local video = videoHolder:FindFirstChild("VideoFrame")
				if video then
					video.Video = videoId
					video.Playing = true
					video.Looped = true
				end
			end
		end

		self._videoUI.Visible = true
		local tween = TweenService:Create(self._videoUI, TweenConfig.create("OverlayFadeIn"), {
			GroupTransparency = 0,
		})
		tween:Play()
	end

	self:_dimSettings()
end

function module:_closeVideoUI()
	self._overlayOpen = nil

	if self._videoUI then
		local videoFrame = self._videoUI:FindFirstChild("VideoFrame")
		if videoFrame then
			videoFrame.Visible = false
			local videoHolder = videoFrame:FindFirstChild("VideoHolder")
			if videoHolder then
				local video = videoHolder:FindFirstChild("VideoFrame")
				if video then
					video.Playing = false
				end
			end
		end

		local tween = TweenService:Create(self._videoUI, TweenConfig.create("OverlayFadeOut"), {
			GroupTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			self._videoUI.Visible = false
		end)
	end

	self:_undimSettings()
end

function module:_openImageUI(imageId: string)
	if self._overlayOpen then
		return
	end

	self._overlayOpen = "Image"

	if self._videoUI then
		local videoFrame = self._videoUI:FindFirstChild("VideoFrame")
		if videoFrame then
			videoFrame.Visible = false
		end

		local imageFrame = self._videoUI:FindFirstChild("ImageFrame")
		if imageFrame then
			imageFrame.Visible = true
			local holder = imageFrame:FindFirstChild("Holder")
			if holder then
				local canvas = holder:FindFirstChild("CanvasGroup")
				if canvas then
					local image = canvas:FindFirstChild("ImageLabel")
					if image then
						image.Image = imageId
					end
				end
			end
		end

		self._videoUI.Visible = true
		local tween = TweenService:Create(self._videoUI, TweenConfig.create("OverlayFadeIn"), {
			GroupTransparency = 0,
		})
		tween:Play()
	end

	self:_dimSettings()
end

function module:_closeImageUI()
	self._overlayOpen = nil

	if self._videoUI then
		local imageFrame = self._videoUI:FindFirstChild("ImageFrame")
		if imageFrame then
			imageFrame.Visible = false
		end

		local tween = TweenService:Create(self._videoUI, TweenConfig.create("OverlayFadeOut"), {
			GroupTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function()
			self._videoUI.Visible = false
		end)
	end

	self:_undimSettings()
end

function module:_setupSearch()
	if not self._searchBar then
		return
	end

	local frame = self._searchBar:FindFirstChild("Frame")
	if not frame then
		return
	end

	local textBox = frame:FindFirstChild("TextBox")
	if not textBox then
		return
	end

	self._connections:track(textBox, "FocusLost", function()
		self._searchQuery = textBox.Text
		self:_filterSettings(self._searchQuery)
	end, "search")

	local textChangedConnection = textBox:GetPropertyChangedSignal("Text"):Connect(function()
		self._searchQuery = textBox.Text
		self:_filterSettings(self._searchQuery)
	end)
	self._connections:add(textChangedConnection, "search")
end

function module:_filterSettings(query: string)
	local lowerQuery = query:lower()

	for _, rowData in self._settingRows do
		if lowerQuery == "" then
			rowData.row.Visible = true
		else
			local settingName = rowData.config.Name:lower()
			rowData.row.Visible = settingName:find(lowerQuery, 1, true) ~= nil
		end
	end
end

function module:_setupCloseButton()
	if not self._actionsBar then
		return
	end

	local closeButton = self._actionsBar:FindFirstChild("CloseButton")
	if not closeButton then
		return
	end

	self._connections:track(closeButton, "Activated", function()
		if not self._buttonsActive then
			return
		end
		if self._overlayOpen then
			return
		end
		self:_close()
	end, "close")
end

function module:_close()
	local startModule = self._export:getModule("Start")
	if startModule and startModule.showAll then
		 task.delay(0.25, function()
			startModule:showAll()
		end)
	end

	self._export:hide()
end

function module:_setButtonsActive(active: boolean)
	self._buttonsActive = active
end

function module:transitionIn()
	self._export:show("Black")

	self:_setButtonsActive(false)

	task.spawn(function()
		task.wait(0.35)

		self._ui.Visible = true

		local canvas = self._canvasGroup or self._ui
		local startPos = UDim2.new(
			self._originals.uiPosition.X.Scale,
			self._originals.uiPosition.X.Offset,
			self._originals.uiPosition.Y.Scale - TweenConfig.Values.SettingsUIFadeOffset,
			self._originals.uiPosition.Y.Offset
		)

		canvas.Position = startPos
		canvas.GroupTransparency = 1

		cancelTweenGroup("show")
		cancelTweenGroup("hide")

		local posTween = TweenService:Create(canvas, TweenConfig.create("Show"), {
			Position = self._originals.uiPosition,
		})
		local fadeTween = TweenService:Create(canvas, TweenConfig.create("Show"), {
			GroupTransparency = self._originals.uiTransparency,
		})

		posTween:Play()
		fadeTween:Play()

		currentTweens["show"] = {posTween, fadeTween}

		fadeTween.Completed:Once(function()
			self:_setButtonsActive(true)
		end)

		self:_init()
	end)
end

function module:transitionOut()
	self:_setButtonsActive(false)
	self._export:setModuleState(nil, false)

	if self._overlayOpen then
		if self._overlayOpen == "Keybind" then
			self:_closeKeybindUI(true)
		elseif self._overlayOpen == "Action" then
			self:_closeActionUI()
		elseif self._overlayOpen == "Video" then
			self:_closeVideoUI()
		elseif self._overlayOpen == "Image" then
			self:_closeImageUI()
		end
	end

	self:_stopImageCarousel()
	self:_stopVideo()
	self:_clearSettings()

	local canvas = self._canvasGroup or self._ui

	cancelTweenGroup("show")
	cancelTweenGroup("hide")

	local targetPos = UDim2.new(
		self._originals.uiPosition.X.Scale,
		self._originals.uiPosition.X.Offset,
		self._originals.uiPosition.Y.Scale - TweenConfig.Values.SettingsUIFadeOffset,
		self._originals.uiPosition.Y.Offset
	)

	local posTween = TweenService:Create(canvas, TweenConfig.create("Hide"), {
		Position = targetPos,
	})
	local fadeTween = TweenService:Create(canvas, TweenConfig.create("Hide"), {
		GroupTransparency = 1,
	})

	posTween:Play()
	fadeTween:Play()

	currentTweens["hide"] = {posTween, fadeTween}

	self._export:hide("Black")

	fadeTween.Completed:Once(function()
		self._ui.Visible = false

		self._selectedSetting = nil
		self._overlayOpen = nil
		self._awaitingKeybind = nil
		self._resetCategory = nil
		self._searchQuery = ""
		table.clear(self._conflictingSettings)

		if self._toggleRowData then
			table.clear(self._toggleRowData)
		end

		if self._arrowOriginalColors then
			table.clear(self._arrowOriginalColors)
		end
	end)
end

function module:show()
	self:transitionIn()
end

function module:hide()
	self:transitionOut()
end

function module:_cleanup()
	self:_stopImageCarousel()
	self:_stopVideo()

	self._connections:cleanupGroup("categories")
	self._connections:cleanupGroup("navigation")
	self._connections:cleanupGroup("search")
	self._connections:cleanupGroup("close")
	self._connections:cleanupGroup("settingRows")
	self._connections:cleanupGroup("sliders")
	self._connections:cleanupGroup("keybindInput")
	self._connections:cleanupGroup("keybindOverlay")
	self._connections:cleanupGroup("actionOverlay")
	self._connections:cleanupGroup("videoOverlay")
	self._connections:cleanupGroup("imageOverlay")

	for _, tweens in currentTweens do
		for _, tween in tweens do
			tween:Cancel()
		end
	end
	table.clear(currentTweens)

	self._initialized = false
	self._selectedSetting = nil
	self._overlayOpen = nil
	self._awaitingKeybind = nil
	self._resetCategory = nil
	self._searchQuery = ""
	table.clear(self._conflictingSettings)

	if self._toggleRowData then
		table.clear(self._toggleRowData)
	end

	if self._arrowOriginalColors then
		table.clear(self._arrowOriginalColors)
	end

	local canvas = self._canvasGroup or self._ui
	canvas.Position = self._originals.uiPosition
	canvas.GroupTransparency = self._originals.uiTransparency
end

return module
