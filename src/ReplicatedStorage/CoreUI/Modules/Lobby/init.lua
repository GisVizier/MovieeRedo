--[[
	Lobby CoreUI Module

	Drives the daily/beginner/bonus task panel visible in the lobby.
	Receives TasksUpdate events from UIController (which listens on the Net remote)
	and populates the Mission rows (Task1-3), progress bars, and the Callender header.

	UI hierarchy (from Studio):
	  Lobby > Frame > CanvasGroup
	    ├── Callender (header: title + character viewport)
	    │     └── Frame > Aim, Aim (title / subtitle)
	    └── Mission (task list + duels CTA)
	          ├── Task1, Task2, Task3
	          │     each: Frame(bg) + Frame(content)
	          │       content: Frame(icon) + Frame(text)
	          │         text: Aim(name) + Frame(progress row: Aim, Aim, Aim)
	          │         icon Frame contains: Bg + Frame{ Left(ImageLabel), Right(ImageLabel) } arc
	          ├── UIListLayout
	          └── Etc (CanvasGroup with Aim="TO DUELS :" + Frame/button)
]]

local TweenService    = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyTaskConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DailyTaskConfig"))

local TWEEN_ARC  = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_SHOW = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_HIDE = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local REWARD_DISPLAY = {
	GEMS   = "Gems",
	CROWNS = "Crowns",
}

-- Rotation mapping for a two-half circular arc:
--   Right UIGradient: -180° (empty) → 0°   (right half full) for 0–50%
--   Left  UIGradient:    0° (empty) → 180° (left  half full) for 50–100%
local function arcRotations(frac)
	local rightRot = math.clamp(frac * 2, 0, 1) * 180 - 180  -- -180 → 0
	local leftRot  = math.clamp(frac * 2 - 1, 0, 1) * 180    --    0 → 180
	return rightRot, leftRot
end

local module = {}
module.__index = module

local function getTextLabels(parent)
	local labels = {}
	for _, child in parent:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	table.sort(labels, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return labels
end

local function getFrames(parent)
	local frames = {}
	for _, child in parent:GetChildren() do
		if child:IsA("Frame") or child:IsA("CanvasGroup") then
			table.insert(frames, child)
		end
	end
	table.sort(frames, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return frames
end

local BAR_NAMES = { "Bar", "Fill", "Progress", "BarFill", "ProgressBar" }

local function findBarFill(root)
	local function search(parent)
		for _, child in parent:GetChildren() do
			-- Arc: a Frame containing ImageLabels named "Left" and "Right"
			if child:IsA("Frame") then
				local leftImg  = child:FindFirstChild("Left")
				local rightImg = child:FindFirstChild("Right")
				if leftImg and leftImg:IsA("ImageLabel") and rightImg and rightImg:IsA("ImageLabel") then
					return "arc", child
				end
			end

			local name = child.Name
			for _, barName in BAR_NAMES do
				if name == barName or name:find(barName) then
					if child:IsA("Frame") then
						local fill = child:FindFirstChild("Fill") or child:FindFirstChild("Bar")
						local uiScale = child:FindFirstChildOfClass("UIScale")
						local gradient = child:FindFirstChildOfClass("UIGradient")
						if fill and fill:IsA("Frame") then
							local fillScale = fill:FindFirstChildOfClass("UIScale")
							if fillScale then return "scale", fillScale end
							return "size", fill
						end
						if uiScale then return "scale", uiScale end
						if gradient then return "gradient", gradient end
					end
				end
			end
			local kind, obj = search(child)
			if kind then return kind, obj end
		end
		return nil, nil
	end
	return search(root)
end

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections

	self._taskState = nil
	self._taskSlots = {}

	self:_bindUi()
	self:_clearTemplateText()
	self:_bindEvents()

	return self
end

--------------------------------------------------------------------------------
-- UI BINDING
--------------------------------------------------------------------------------

function module:_bindUi()
	local frame = self._ui:FindFirstChild("Frame")
	if not frame then return end

	local canvasGroup = frame:FindFirstChild("CanvasGroup")
	if not canvasGroup then return end

	self._frame        = frame
	self._frameRestPos = frame.Position
	self._canvasGroup  = canvasGroup

	local callender = canvasGroup:FindFirstChild("Callender")
	if callender then
		self._callender = callender
		local headerFrame = callender:FindFirstChild("Frame")
		if headerFrame then
			local labels = getTextLabels(headerFrame)
			self._titleLabel    = labels[1]
			self._subtitleLabel = labels[2]
		end
	end

	local mission = canvasGroup:FindFirstChild("Mission")
	if not mission then return end
	self._mission = mission

	for _, slotName in { "Task1", "Task2", "Task3" } do
		local taskFrame = mission:FindFirstChild(slotName)
		if taskFrame then
			self._taskSlots[slotName] = self:_parseTaskRow(taskFrame)
		end
	end

	local etc = mission:FindFirstChild("Etc")
	if etc then
		self._duelsButton = etc
		self._connections:track(etc, "InputBegan", function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				self._export:emit("NavigateToDuels")
			end
		end, "lobby")
	end
end

function module:_parseTaskRow(taskFrame)
	local contentFrames = getFrames(taskFrame)
	if #contentFrames < 2 then return nil end

	local contentFrame = contentFrames[#contentFrames]
	local innerFrames = getFrames(contentFrame)

	local iconFrame = nil
	local textFrame = nil
	for _, f in innerFrames do
		local hasTextChild = false
		for _, c in f:GetChildren() do
			if c:IsA("TextLabel") then
				hasTextChild = true
				break
			end
		end
		if hasTextChild then
			textFrame = f
		elseif not iconFrame then
			iconFrame = f
		end
	end

	if not textFrame then return nil end

	local nameLabel = nil
	local progressFrame = nil
	for _, child in textFrame:GetChildren() do
		if child:IsA("TextLabel") then
			nameLabel = child
		elseif child:IsA("Frame") then
			progressFrame = child
		end
	end

	local progressLabel, separatorLabel, rewardLabel
	if progressFrame then
		local pLabels = getTextLabels(progressFrame)
		progressLabel  = pLabels[1]
		separatorLabel = pLabels[2]
		rewardLabel    = pLabels[3]
	end

	local barKind, barObj = findBarFill(taskFrame)

	return {
		root = taskFrame,
		nameLabel = nameLabel,
		progressLabel = progressLabel,
		separatorLabel = separatorLabel,
		rewardLabel = rewardLabel,
		iconFrame = iconFrame,
		bgFrame = contentFrames[1],
		barKind = barKind,
		barObj = barObj,
	}
end

function module:_clearTemplateText()
	if self._titleLabel then
		self._titleLabel.Text = "LOADING..."
	end
	if self._subtitleLabel then
		self._subtitleLabel.Text = ""
	end

	for _, slotName in { "Task1", "Task2", "Task3" } do
		local slot = self._taskSlots[slotName]
		if slot then
			if slot.bgFrame then
				slot.bgFrame.BackgroundColor3 = Color3.new(1, 1, 1)
				slot.bgFrame.BackgroundTransparency = 1
			end
			if slot.nameLabel then slot.nameLabel.Text = "" end
			if slot.progressLabel then slot.progressLabel.Text = "" end
			if slot.separatorLabel then slot.separatorLabel.Text = "" end
			if slot.rewardLabel then slot.rewardLabel.Text = "" end
			if slot.barKind and slot.barObj then
				if slot.barKind == "scale" then
					slot.barObj.Scale = 0
				elseif slot.barKind == "gradient" then
					slot.barObj.Offset = Vector2.new(0, 0.5)
				elseif slot.barKind == "size" and slot.barObj:IsA("GuiObject") then
					slot.barObj.Size = UDim2.new(0, 0, 1, 0)
				elseif slot.barKind == "arc" then
					local leftImg  = slot.barObj:FindFirstChild("Left")
					local rightImg = slot.barObj:FindFirstChild("Right")
					if leftImg then
						leftImg.Visible = false
						local g = leftImg:FindFirstChildOfClass("UIGradient")
						if g then g.Rotation = -1 end
					end
					if rightImg then
						rightImg.Visible = true
						local g = rightImg:FindFirstChildOfClass("UIGradient")
						if g then g.Rotation = -180 end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- EVENTS (routed through CoreUI emit from UIController)
--------------------------------------------------------------------------------

function module:_bindEvents()
	self._export:on("TasksUpdate", function(payload)
		self:_onTasksUpdate(payload)
	end)

	self._export:on("ReturnToLobby", function()
		self._export:emit("TasksRequestRefresh")
	end)
end

--------------------------------------------------------------------------------
-- UPDATE UI
--------------------------------------------------------------------------------

function module:_onTasksUpdate(payload)
	if type(payload) ~= "table" then return end
	self._taskState = payload
	self:_refreshDisplay()
end

function module:_refreshDisplay()
	local state = self._taskState
	if not state then return end

	local activeTier, pool = self:_getActiveTier(state)

	if self._titleLabel then
		if activeTier == "beginner" then
			self._titleLabel.Text = "BEGINNER TASKS"
		elseif activeTier == "bonus" then
			self._titleLabel.Text = "BONUS TASKS"
		else
			self._titleLabel.Text = "DAILY TASKS"
		end
	end

	if self._subtitleLabel then
		self._subtitleLabel.Text = ""
	end

	local progressMap, claimedMap
	if activeTier == "beginner" then
		progressMap = state.beginnerProgress or {}
		claimedMap  = state.beginnerClaimed  or {}
	elseif activeTier == "bonus" then
		progressMap = state.bonusProgress or {}
		claimedMap  = state.bonusClaimed  or {}
	else
		progressMap = state.dailyProgress or {}
		claimedMap  = state.dailyClaimed  or {}
	end

	local slotNames = { "Task1", "Task2", "Task3" }
	for i, slotName in slotNames do
		local slot = self._taskSlots[slotName]
		local taskDef = pool[i]
		if slot and taskDef then
			self:_updateSlot(slot, taskDef, progressMap, claimedMap)
			slot.root.Visible = true
		elseif slot then
			slot.root.Visible = false
		end
	end
end

function module:_getActiveTier(state)
	if not state.beginnerComplete then
		return "beginner", DailyTaskConfig.BeginnerTasks
	end

	if state.allDailiesClaimed then
		return "bonus", DailyTaskConfig.BonusTasks
	end

	return "daily", DailyTaskConfig.DailyTasks
end

function module:_updateSlot(slot, taskDef, progressMap, claimedMap)
	local current = progressMap[taskDef.id] or 0
	local target  = taskDef.target
	local claimed = claimedMap[taskDef.id] == true
	local fillFraction = target > 0 and (current / target) or 0

	if slot.bgFrame then
		if claimed then
			slot.bgFrame.BackgroundColor3 = Color3.fromRGB(59, 130, 246)
			slot.bgFrame.BackgroundTransparency = 0.6
		else
			slot.bgFrame.BackgroundColor3 = Color3.new(1, 1, 1)
			slot.bgFrame.BackgroundTransparency = 1
		end
	end

	if slot.nameLabel then
		slot.nameLabel.Text = taskDef.name
	end

	if slot.progressLabel then
		if claimed then
			slot.progressLabel.Text = "CLAIMED"
		else
			slot.progressLabel.Text = tostring(current) .. " / " .. tostring(target)
		end
	end

	if slot.separatorLabel then
		slot.separatorLabel.Text = claimed and "" or "|"
	end

	if slot.rewardLabel then
		if claimed then
			slot.rewardLabel.Text = ""
		else
			slot.rewardLabel.Text = "x" .. tostring(taskDef.reward) .. " " .. (REWARD_DISPLAY[taskDef.rewardType] or taskDef.rewardType)
		end
	end

	if slot.barKind and slot.barObj then
		local frac = claimed and 1 or math.clamp(fillFraction, 0, 1)
		if slot.barKind == "scale" then
			slot.barObj.Scale = frac
		elseif slot.barKind == "gradient" then
			slot.barObj.Offset = Vector2.new(frac, 0.5)
		elseif slot.barKind == "size" and slot.barObj:IsA("GuiObject") then
			slot.barObj.Size = UDim2.new(frac, 0, 1, 0)
		elseif slot.barKind == "arc" then
			local leftImg  = slot.barObj:FindFirstChild("Left")
			local rightImg = slot.barObj:FindFirstChild("Right")
			local rightRot, leftRot = arcRotations(frac)

			if leftImg  then leftImg.Visible  = frac > 0 end
			if rightImg then rightImg.Visible = true end

			local rightGrad = rightImg and rightImg:FindFirstChildOfClass("UIGradient")
			local leftGrad  = leftImg  and leftImg:FindFirstChildOfClass("UIGradient")

			if rightGrad then
				TweenService:Create(rightGrad, TWEEN_ARC, { Rotation = rightRot }):Play()
			end
			if leftGrad then
				TweenService:Create(leftGrad, TWEEN_ARC, { Rotation = leftRot }):Play()
			end
		end
	end

end

--------------------------------------------------------------------------------
-- SHOW / HIDE
--------------------------------------------------------------------------------

function module:show()
	self._ui.Visible = true

	if self._frame and self._frameRestPos then
		local rest = self._frameRestPos
		local offLeft = UDim2.new(rest.X.Scale - 0.5, rest.X.Offset, rest.Y.Scale, rest.Y.Offset)
		self._frame.Position = offLeft
		if self._canvasGroup then
			self._canvasGroup.GroupTransparency = 1
		end
		TweenService:Create(self._frame, TWEEN_SHOW, { Position = rest }):Play()
		if self._canvasGroup then
			TweenService:Create(self._canvasGroup, TWEEN_SHOW, { GroupTransparency = 0 }):Play()
		end
	end

	self._export:emit("TasksRequestRefresh")
end

function module:hide()
	if self._frame and self._frameRestPos then
		local rest = self._frameRestPos
		local offLeft = UDim2.new(rest.X.Scale - 0.5, rest.X.Offset, rest.Y.Scale, rest.Y.Offset)
		local t1 = TweenService:Create(self._frame, TWEEN_HIDE, { Position = offLeft })
		local t2 = self._canvasGroup and TweenService:Create(self._canvasGroup, TWEEN_HIDE, { GroupTransparency = 1 })
		t1:Play()
		if t2 then t2:Play() end
		task.spawn(function()
			t1.Completed:Wait()
			self._ui.Visible = false
		end)
	else
		self._ui.Visible = false
	end
	return true
end

function module:_cleanup()
	self._connections:cleanupAll()
end

return module
