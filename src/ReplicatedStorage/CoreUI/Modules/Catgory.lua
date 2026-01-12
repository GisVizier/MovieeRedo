local TweenService = game:GetService("TweenService")

local module = {}
module.__index = module

local TWEEN_SHOW = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_HIDE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TWEEN_HOVER = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_HOVER_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SWAP = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local CATEGORY_ORDER = { "Leave", "Ability", "Primary", "Secondary", "Melee" }
local STAGGER_DELAY = 0.2

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

	self._categories = {}
	self._selectedCategory = nil
	self._lastSelectedCategory = "Ability"
	self._currentScreen = nil
	self._buttonsActive = false

	self._originals = {}
	self._initialized = false

	return self
end

function module:_init()
	if self._initialized then
		-- Re-setup hover/button connections if they were cleaned up
		self:_reconnectCategories()
		return
	end

	self._initialized = true
	self:_cacheOriginals()
	self:_setupCategories()
end

function module:_reconnectCategories()
	for _, categoryName in CATEGORY_ORDER do
		local data = self._categories[categoryName]
		if not data or not data.button then
			continue
		end

		-- Re-setup hover and button connections
		self:_setupCategoryHover(categoryName)
		self:_setupCategoryButton(categoryName)
	end
end

function module:_cacheOriginals()
	self._originals.ui = {
		position = self._ui.Position,
		transparency = self._ui.GroupTransparency or 0,
	}

	--local holder = self._ui:FindFirstChild("Holder")
	--if holder then
	--	self._originals.holder = {
	--		position = holder.Position,
	--		transparency = holder.GroupTransparency or 0,
	--	}
	--end
end

function module:_setupCategories()
	local holder = self._ui:FindFirstChild("Holder")
	if not holder then
		return
	end

	local categoryHolder = holder:FindFirstChild("CatgoryHolder")
	if not categoryHolder then
		return
	end

	for i, categoryName in CATEGORY_ORDER do
		local categoryFrame = categoryHolder:FindFirstChild(categoryName)
		if not categoryFrame then
			continue
		end

		local frameHolder = categoryFrame:FindFirstChild("Holder")
		if not frameHolder then
			continue
		end

		local defaultFrame = frameHolder.Frame:FindFirstChild("Default")
		local selectFrame = frameHolder.Frame:FindFirstChild("Select")

		local textHolder = categoryFrame:FindFirstChild("TextHolder")
		local textLabel = textHolder and textHolder:FindFirstChild("TextLabel")
		local iconHolder = frameHolder and frameHolder:FindFirstChild("Icon")
		local iconScale = frameHolder.Frame:FindFirstChild("Icon"):FindFirstChild("UIScale")
		local button = frameHolder:FindFirstChild("Button")

		local selectBottomBar = selectFrame and selectFrame:FindFirstChild("BottomBar")
		local selectGlow = selectFrame and selectFrame:FindFirstChild("Glow")
		local defaultBottomBar = defaultFrame and defaultFrame:FindFirstChild("BottomBar")
		
		--warn(`ran`, frameHolder)
		
		self._categories[categoryName] = {
			frame = categoryFrame,
			holder = frameHolder,
			default = defaultFrame,
			select = selectFrame,
			selectBottomBar = selectBottomBar,
			selectGlow = selectGlow,
			defaultBottomBar = defaultBottomBar,
			textHolder = textHolder,
			textLabel = textLabel,
			iconHolder = iconHolder,
			iconScale = iconScale,
			button = button,
			order = i,
			originals = {
				holderPosition = frameHolder and frameHolder.Position,
				holderTransparency = 0, -- Force to 0 since we want fully visible when shown
				textPosition = textLabel and textLabel.Position,
				textTransparency = textLabel and (textLabel.TextTransparency or 0),
				iconScale = iconScale and iconScale.Scale or 1,
			},
		}

		categoryFrame.Visible = false

		-- All categories (including Leave) start with default visible, select hidden
		if defaultFrame then
			defaultFrame.Visible = true
		end
		if selectFrame then
			selectFrame.Visible = false
		end

		if defaultBottomBar then
			defaultBottomBar.BackgroundTransparency = 1
		end
		if textLabel then
			textLabel.TextTransparency = 1
		end

		if button then
			self:_setupCategoryHover(categoryName)
			self:_setupCategoryButton(categoryName)
		end
	end
end

function module:_setupCategoryHover(categoryName: string)
	local data = self._categories[categoryName]
	if not data or not data.holder then
		return
	end

	local isHovering = false

	self._connections:track(data.holder, "MouseEnter", function()
		if isHovering then
			return
		end
		-- Skip if this category is currently selected (Leave is never "selected" so it will always hover)
		if self._selectedCategory == categoryName then
			return
		end
		isHovering = true

		cancelTweenGroup("hover_" .. categoryName)
		local tweens = {}

		-- Show Select frame on hover
		if data.default then
			data.default.Visible = false
		end

		if data.select then
			data.select.Visible = true
			data.select.GroupTransparency = 1
			local t = TweenService:Create(data.select, TWEEN_HOVER, { GroupTransparency = 0 })
			t:Play()
			table.insert(tweens, t)
		end

		if data.iconScale then
			local t = TweenService:Create(data.iconScale, TWEEN_HOVER, { Scale = data.originals.iconScale * 1.25 })
			t:Play()
			table.insert(tweens, t)
		end

		if data.textLabel then
			local origPos = data.originals.textPosition
			if origPos then
				local targetPos = UDim2.new(
					origPos.X.Scale,
					origPos.X.Offset,
					origPos.Y.Scale + 0.05,
					origPos.Y.Offset
				)
				local t1 = TweenService:Create(data.textLabel, TWEEN_HOVER, { Position = targetPos, TextTransparency = data.originals.textTransparency })
				t1:Play()
				table.insert(tweens, t1)
			end
		end

		currentTweens["hover_" .. categoryName] = tweens
	end, "category_" .. categoryName)

	self._connections:track(data.holder, "MouseLeave", function()
		if not isHovering then
			return
		end
		isHovering = false

		-- Skip if this category is currently selected
		if self._selectedCategory == categoryName then
			return
		end

		cancelTweenGroup("hover_" .. categoryName)
		local tweens = {}

		-- Hide Select frame, show Default on hover out
		if data.select then
			local t = TweenService:Create(data.select, TWEEN_HOVER_OUT, { GroupTransparency = 1 })
			t:Play()
			table.insert(tweens, t)

			t.Completed:Once(function()
				if self._selectedCategory ~= categoryName then
					data.select.Visible = false
					if data.default then
						data.default.Visible = true
					end
				end
			end)
		end

		if data.iconScale then
			local t = TweenService:Create(data.iconScale, TWEEN_HOVER_OUT, { Scale = data.originals.iconScale })
			t:Play()
			table.insert(tweens, t)
		end

		if data.textLabel then
			local origPos = data.originals.textPosition
			if origPos then
				local t1 = TweenService:Create(data.textLabel, TWEEN_HOVER_OUT, { Position = origPos, TextTransparency = 1 })
				t1:Play()
				table.insert(tweens, t1)
			end
		end

		currentTweens["hover_" .. categoryName] = tweens
	end, "category_" .. categoryName)
end

function module:_setupCategoryButton(categoryName: string)
	local data = self._categories[categoryName]
	if not data or not data.button then
		return
	end

	self._connections:track(data.button, "Activated", function()
		if not self._buttonsActive then
			return
		end

		if categoryName == "Leave" then
			self:_onLeaveClicked()
		else
			self:_selectCategory(categoryName)
		end
	end, "category_" .. categoryName)
end

function module:_setButtonsActive(active: boolean)
	self._buttonsActive = active

	for _, categoryName in CATEGORY_ORDER do
		local data = self._categories[categoryName]
		if data and data.button then
			data.button.Active = active
			data.button.Interactable = active
		end
	end
end

function module:_onLeaveClicked()
	if self._currentScreen then
		self._export:hide(self._currentScreen)
		self._currentScreen = nil
	end

	task.spawn(function()
		self._export:hide("Catgory")
	end)

	local startModule = self._export:getModule("Start")
	if startModule and startModule.showAll then
		task.wait(.25)
		startModule:showAll()
	end
end

function module:_selectCategory(categoryName: string)
	if self._selectedCategory == categoryName then
		return
	end

	if self._selectedCategory then
		self:_deselectCategory(self._selectedCategory)
	end

	self._selectedCategory = categoryName
	self._lastSelectedCategory = categoryName

	local data = self._categories[categoryName]
	if not data then
		return
	end

	cancelTweenGroup("select_" .. categoryName)
	local tweens = {}

	if data.default then
		data.default.Visible = false
	end

	if data.select then
		data.select.Visible = true
		data.select.GroupTransparency = 1

		local t = TweenService:Create(data.select, TWEEN_SWAP, { GroupTransparency = 0 })
		t:Play()
		table.insert(tweens, t)
	end

	if data.selectGlow then
		data.selectGlow.BackgroundTransparency = 1
		local t = TweenService:Create(data.selectGlow, TWEEN_SWAP, { BackgroundTransparency = 0 })
		t:Play()
		table.insert(tweens, t)
	end

	if data.defaultBottomBar then
		data.defaultBottomBar.BackgroundTransparency = 1
	end

	if data.iconScale then
		local t = TweenService:Create(data.iconScale, TWEEN_HOVER, { Scale = data.originals.iconScale })
		t:Play()
		table.insert(tweens, t)
	end

	if data.textLabel then
		local origPos = data.originals.textPosition
		if origPos then
			local targetPos = UDim2.new(
				origPos.X.Scale,
				origPos.X.Offset,
				origPos.Y.Scale + 0.05,
				origPos.Y.Offset
			)
			data.textLabel.Position = targetPos
			data.textLabel.TextTransparency = data.originals.textTransparency
		end
	end

	currentTweens["select_" .. categoryName] = tweens

	self:_onCategorySelected(categoryName)
end

function module:_deselectCategory(categoryName: string)
	local data = self._categories[categoryName]
	if not data then
		return
	end

	cancelTweenGroup("select_" .. categoryName)
	cancelTweenGroup("hover_" .. categoryName)

	if data.select then
		data.select.Visible = false
	end

	if data.default then
		data.default.Visible = true
	end

	if data.defaultBottomBar then
		data.defaultBottomBar.BackgroundTransparency = 1
	end

	if data.iconScale then
		data.iconScale.Scale = data.originals.iconScale
	end

	if data.textLabel then
		local origPos = data.originals.textPosition
		if origPos then
			data.textLabel.Position = origPos
			data.textLabel.TextTransparency = 1
		end
	end
end

function module:_onCategorySelected(categoryName: string)
	self._export:emit("CategorySelected", categoryName)
end

function module:_showCategories()
	for i, categoryName in CATEGORY_ORDER do
		local data = self._categories[categoryName]
		if not data then
			continue
		end

		data.frame.Visible = false

		task.delay((i - 1) * STAGGER_DELAY, function()
			self:_tweenCategoryIn(categoryName)
		end)
	end
end

function module:_tweenCategoryIn(categoryName: string)
	local data = self._categories[categoryName]
	if not data then
		return
	end

	data.frame.Visible = true

	local holder = data.holder
	if not holder then
		return
	end

	local origPos = data.originals.holderPosition
	if not origPos then
		return
	end

	local offsetPos = UDim2.new(
		origPos.X.Scale,
		origPos.X.Offset,
		origPos.Y.Scale - 0.15,
		origPos.Y.Offset
	)

	holder.Position = offsetPos
	holder.GroupTransparency = 1

	cancelTweenGroup("categoryIn_" .. categoryName)
	local tweens = {}

	local posTween = TweenService:Create(holder, TWEEN_SHOW, { Position = origPos })
	local fadeTween = TweenService:Create(holder, TWEEN_SHOW, { GroupTransparency = data.originals.holderTransparency })

	posTween:Play()
	fadeTween:Play()

	table.insert(tweens, posTween)
	table.insert(tweens, fadeTween)

	currentTweens["categoryIn_" .. categoryName] = tweens
end

function module:_hideCategories()
	for _, categoryName in CATEGORY_ORDER do
		local data = self._categories[categoryName]
		if not data then
			continue
		end

		cancelTweenGroup("categoryIn_" .. categoryName)
		cancelTweenGroup("categoryOut_" .. categoryName)
		cancelTweenGroup("hover_" .. categoryName)
		cancelTweenGroup("select_" .. categoryName)

		data.frame.Visible = false
	end
end

function module:_resetCategories()
	for _, categoryName in CATEGORY_ORDER do
		local data = self._categories[categoryName]
		if not data then
			continue
		end

		-- All categories (including Leave) reset to default visible, select hidden
		if data.default then
			data.default.Visible = true
		end
		if data.select then
			data.select.Visible = false
		end

		if data.defaultBottomBar then
			data.defaultBottomBar.BackgroundTransparency = 1
		end
		if data.iconScale then
			data.iconScale.Scale = data.originals.iconScale
		end
		if data.textLabel and data.originals.textPosition then
			data.textLabel.Position = data.originals.textPosition
			data.textLabel.TextTransparency = 1
		end
		if data.holder and data.originals.holderPosition then
			data.holder.Position = data.originals.holderPosition
			data.holder.GroupTransparency = data.originals.holderTransparency
		end
	end

	self._selectedCategory = nil
end

function module:setCurrentScreen(screenName: string)
	self._currentScreen = screenName
end

function module:getLastSelectedCategory(): string
	return self._lastSelectedCategory or "Ability"
end

-- Visual transition for showing (fade in with TallFade)
function module:transitionIn()
	self._export:show("TallFade")

	self:_setButtonsActive(false)

	task.spawn(function()
		task.wait(0.35)

		self._ui.Visible = true

		cancelTweenGroup("mainOut")
		cancelTweenGroup("mainIn")
		for _, categoryName in CATEGORY_ORDER do
			cancelTweenGroup("categoryIn_" .. categoryName)
			cancelTweenGroup("categoryOut_" .. categoryName)
			cancelTweenGroup("hover_" .. categoryName)
			cancelTweenGroup("select_" .. categoryName)
		end

		local originals = self._originals.ui
		if originals then
			local startPos = UDim2.new(
				originals.position.X.Scale,
				originals.position.X.Offset,
				originals.position.Y.Scale - 0.05,
				originals.position.Y.Offset
			)

			self._ui.Position = startPos
			self._ui.GroupTransparency = originals.transparency

			local posTween = TweenService:Create(self._ui, TWEEN_SHOW, { Position = originals.position })
			posTween:Play()

			currentTweens["mainIn"] = { posTween }
		end

		self:_resetCategories()
		self:_showCategories()

		local categoryToSelect = self._lastSelectedCategory or "Ability"
		task.delay(#CATEGORY_ORDER * STAGGER_DELAY + 0.1, function()
			self:_selectCategory(categoryToSelect)
			self:_setButtonsActive(true)
		end)
	end)
end

-- Visual transition for hiding (fade out with TallFade)
function module:transitionOut()
	self:_setButtonsActive(false)
	cancelTweenGroup("mainOut")

	-- Fade out all categories in parallel (no stagger)
	local lastTween = nil

	for _, categoryName in CATEGORY_ORDER do
		local data = self._categories[categoryName]
		if not data then
			continue
		end

		lastTween = self:_tweenCategoryOut(categoryName)
	end

	-- Move the main UI up (categories handle their own fade)
	local originals = self._originals.ui
	if originals then
		local targetPos = UDim2.new(
			originals.position.X.Scale,
			originals.position.X.Offset,
			originals.position.Y.Scale - 0.05,
			originals.position.Y.Offset
		)

		local posTween = TweenService:Create(self._ui, TWEEN_HIDE, { Position = targetPos })
		posTween:Play()

		currentTweens["mainOut"] = { posTween }
	end
	
	if lastTween then
		lastTween.Completed:Once(function()
			self._ui.Visible = false
		end)
	else
		self._ui.Visible = false
	end
	
	self._export:hide("TallFade")

	-- Set visibility false when animation completes

end

function module:show()
	--self._ui.Visible = true
	self:_init()
	self:transitionIn()
	return true
end

function module:hide()
	self:transitionOut()
	return true
end

function module:_tweenCategoryOut(categoryName: string)
	local data = self._categories[categoryName]
	if not data then
		return nil
	end

	local holder = data.holder
	if not holder then
		return nil
	end

	local origPos = data.originals.holderPosition
	if not origPos then
		return nil
	end

	local offsetPos = UDim2.new(
		origPos.X.Scale,
		origPos.X.Offset,
		origPos.Y.Scale - 0.15,
		origPos.Y.Offset
	)

	cancelTweenGroup("categoryOut_" .. categoryName)
	local tweens = {}

	local posTween = TweenService:Create(holder, TWEEN_HIDE, { Position = offsetPos })
	local fadeTween = TweenService:Create(holder, TWEEN_HIDE, { GroupTransparency = 1 })

	posTween:Play()
	fadeTween:Play()

	table.insert(tweens, posTween)
	table.insert(tweens, fadeTween)

	fadeTween.Completed:Once(function()
		data.frame.Visible = false
	end)

	currentTweens["categoryOut_" .. categoryName] = tweens

	return fadeTween
end

function module:_cleanup()
	-- Cleanup connections and tweens
	cancelTweenGroup("mainOut")
	cancelTweenGroup("mainIn")
	for _, categoryName in CATEGORY_ORDER do
		self._connections:cleanupGroup("category_" .. categoryName)
		cancelTweenGroup("categoryIn_" .. categoryName)
		cancelTweenGroup("categoryOut_" .. categoryName)
		cancelTweenGroup("hover_" .. categoryName)
		cancelTweenGroup("select_" .. categoryName)
	end

	-- Reset main UI position and transparency
	local originals = self._originals.ui
	if originals then
		self._ui.Position = originals.position
		self._ui.GroupTransparency = originals.transparency
	end

	-- Force reset all holder states to originals after cancelling tweens
	for _, categoryName in CATEGORY_ORDER do
		local data = self._categories[categoryName]
		if data and data.holder and data.originals.holderPosition then
			data.holder.Position = data.originals.holderPosition
			data.holder.GroupTransparency = data.originals.holderTransparency
		end
		if data and data.frame then
			data.frame.Visible = false
		end
	end

	self:_resetCategories()
	self._currentScreen = nil
end

return module
