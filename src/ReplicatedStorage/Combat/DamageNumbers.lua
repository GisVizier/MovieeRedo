--[[
	DamageNumbers.lua
	Attachment-template based cumulative damage numbers.
	One active popup per target user id.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(script.Parent:WaitForChild("CombatConfig"))

local DamageNumbers = {}
DamageNumbers._initialized = false
DamageNumbers._template = nil
DamageNumbers._activeByTarget = {} -- [targetUserId] = state
DamageNumbers._pendingByTarget = {} -- [targetUserId] = { damage, position, options, scheduled }
DamageNumbers._stackedByTarget = {} -- [targetUserId] = { { state, basePosition } }
DamageNumbers._stackedPendingByTarget = {} -- [targetUserId] = { entries = { { damage, position, options } }, scheduled = boolean }
DamageNumbers._mode = "Add"

local APPEAR_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EXIT_TWEEN = TweenInfo.new(
	math.max(0.55, tonumber(CombatConfig.DamageNumbers.FadeDuration) or 0.3),
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)
local HOLD_TIME = math.max(2.5, tonumber(CombatConfig.DamageNumbers.FadeTime) or 1.0)
local FLOAT_OFFSET = Vector3.new(0, 3.4, 0)
local BURST_ACCUMULATION_WINDOW = 0.06
local POP_START_SCALE = 0.45
local POP_OVERSHOOT_SCALE = 1.1
local POP_SETTLE_SCALE = 1.0
local POP_ROTATION_MAX = 16
local POP_IN_TWEEN = TweenInfo.new(0.075, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_SETTLE_TWEEN = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PIVOT_RANDOM_OFFSET_BOUNDS = 1
local STACKED_VERTICAL_STEP = 0.85
local STACKED_ACCEPT_WINDOW = 0.07
local ADD_MAX_TEXT_SIZE = 30
local STACKED_TEXT_SIZE = 20

local DAMAGE_NUMBERS_MODE_ADD = "Add"
local DAMAGE_NUMBERS_MODE_DISABLED = "Disabled"
local DAMAGE_NUMBERS_MODE_STACKED = "Stacked"

local function isUsableTemplate(template: Instance): boolean
	if not template:IsA("Attachment") then
		return false
	end

	local billboard = template:FindFirstChild("DamageNumbers")
	if not billboard or not billboard:IsA("BillboardGui") then
		return false
	end

	local frame = billboard:FindFirstChild("Frame")
	if not frame or not frame:IsA("GuiObject") then
		return false
	end

	local mainText = frame:FindFirstChild("MainText")
	if not mainText or not mainText:IsA("TextLabel") then
		return false
	end

	return true
end

local function createFallbackTemplate(): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "dmgnmbr"

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumbers"
	billboard.Active = true
	billboard.ClipsDescendants = true
	billboard.Size = UDim2.new(3.5, 45, 3.5, 45)
	billboard.StudsOffset = Vector3.new(3, 0, 0)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Parent = attachment

	local frame = Instance.new("CanvasGroup")
	frame.Name = "Frame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = billboard

	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.BackgroundTransparency = 1
	glow.Image = "rbxassetid://5538771868"
	glow.ImageTransparency = 0.9
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1, 1)
	glow.Parent = frame

	local mainText = Instance.new("TextLabel")
	mainText.Name = "MainText"
	mainText.AnchorPoint = Vector2.new(0.5, 0.5)
	mainText.BackgroundTransparency = 1
	mainText.FontFace = Font.new(
		"rbxassetid://12187365977",
		Enum.FontWeight.ExtraBold,
		Enum.FontStyle.Normal
	)
	mainText.Position = UDim2.fromScale(0.5, 0.5)
	mainText.Size = UDim2.fromScale(1, 0.4)
	mainText.Text = "0"
	mainText.TextColor3 = Color3.fromRGB(233, 233, 233)
	mainText.TextScaled = true
	mainText.TextWrapped = true
	mainText.ZIndex = 3
	mainText.Parent = frame

	local sizeConstraint = Instance.new("UITextSizeConstraint")
	sizeConstraint.MaxTextSize = ADD_MAX_TEXT_SIZE
	sizeConstraint.Parent = mainText

	return attachment
end

local function getTemplate(): Attachment
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local template = assets:FindFirstChild("dmgnmbr")
		if template and isUsableTemplate(template) then
			return template
		elseif template then
		end
	end

	return createFallbackTemplate()
end

local function normalizeMode(mode)
	if type(mode) == "string" then
		local lowered = string.lower(mode)
		if lowered == "disabled" or lowered == "off" then
			return DAMAGE_NUMBERS_MODE_DISABLED
		end
		if lowered == "stacked" or lowered == "list" then
			return DAMAGE_NUMBERS_MODE_STACKED
		end
		return DAMAGE_NUMBERS_MODE_ADD
	end

	if type(mode) == "boolean" then
		return mode and DAMAGE_NUMBERS_MODE_ADD or DAMAGE_NUMBERS_MODE_DISABLED
	end

	if type(mode) == "number" then
		if mode == 1 then
			return DAMAGE_NUMBERS_MODE_DISABLED
		end
		if mode == 3 then
			return DAMAGE_NUMBERS_MODE_STACKED
		end
		return DAMAGE_NUMBERS_MODE_ADD
	end

	return DAMAGE_NUMBERS_MODE_ADD
end

local function cleanupState(state)
	if not state then
		return
	end

	if state.serialRef and state.serialRef.value then
		state.serialRef.value += 1
	end

	if state.appearTween then
		state.appearTween:Cancel()
	end
	if state.moveTween then
		state.moveTween:Cancel()
	end
	if state.fadeTween then
		state.fadeTween:Cancel()
	end
	if state.rotateTween then
		state.rotateTween:Cancel()
	end
	if state.popTween then
		state.popTween:Cancel()
	end
	if state.popSettleTween then
		state.popSettleTween:Cancel()
	end

	if state.anchorPart and state.anchorPart.Parent then
		state.anchorPart:Destroy()
	end
end

function DamageNumbers:Init()
	if self._initialized then
		return
	end

	self._template = getTemplate()
	self._pendingByTarget = {}
	self._stackedByTarget = {}
	self._stackedPendingByTarget = {}
	self._mode = DAMAGE_NUMBERS_MODE_ADD
	self._initialized = true
end

function DamageNumbers:SetMode(mode)
	local normalized = normalizeMode(mode)
	if self._mode == normalized then
		return
	end

	self._mode = normalized
	self:ClearAll()
end

function DamageNumbers:_createState(position: Vector3)
	local anchorPart = Instance.new("Part")
	anchorPart.Name = "DamageNumberAnchor"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
	anchorPart.CFrame = CFrame.new(position)
	anchorPart.Parent = workspace

	local attachment = self._template:Clone()
	attachment.Parent = anchorPart
	attachment.CFrame = CFrame.new()

	local billboard = attachment:FindFirstChild("DamageNumbers")
	local frame = billboard and billboard:FindFirstChild("Frame")
	local mainText = frame and frame:FindFirstChild("MainText")
	local glow = frame and frame:FindFirstChild("Glow")
	local popScale = nil

	if frame then
		popScale = frame:FindFirstChild("PopScale")
		if not popScale then
			popScale = Instance.new("UIScale")
			popScale.Name = "PopScale"
			popScale.Scale = 1
			popScale.Parent = frame
		end
	end

	if billboard and billboard:IsA("BillboardGui") then
		billboard.Adornee = attachment
		billboard.StudsOffset = Vector3.new(3, 0, 0)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
		billboard.Enabled = true
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
	end

	if frame and frame:IsA("GuiObject") then
		frame.Visible = true
	end

	if mainText and mainText:IsA("TextLabel") then
		mainText.Visible = true
		mainText.TextTransparency = 0
		mainText.TextScaled = true
		mainText.TextWrapped = true
		local sizeConstraint = mainText:FindFirstChildOfClass("UITextSizeConstraint")
		if not sizeConstraint then
			sizeConstraint = Instance.new("UITextSizeConstraint")
			sizeConstraint.Parent = mainText
		end
		sizeConstraint.MaxTextSize = ADD_MAX_TEXT_SIZE
	end

	return {
		anchorPart = anchorPart,
		attachment = attachment,
		billboard = billboard,
		frame = frame,
		mainText = mainText,
		glow = glow,
		popScale = popScale,
		totalDamage = 0,
		serialRef = { value = 0 },
		appearTween = nil,
		moveTween = nil,
		fadeTween = nil,
		rotateTween = nil,
		popTween = nil,
		popSettleTween = nil,
	}
end

function DamageNumbers:_applyStyle(state, options)
	options = options or {}

	local color = options.color
	if not color then
		if options.isCritical then
			color = CombatConfig.DamageNumbers.Colors.Critical
		elseif options.isHeadshot then
			color = CombatConfig.DamageNumbers.Colors.Headshot
		else
			color = CombatConfig.DamageNumbers.Colors.Normal
		end
	end

	if state.mainText then
		state.mainText.TextColor3 = color
	end

	if state.glow then
		state.glow.ImageColor3 = color
	end
end

function DamageNumbers:_getRandomPivotOffset(): Vector3
	return Vector3.new(
		(math.random() * 2 - 1) * PIVOT_RANDOM_OFFSET_BOUNDS,
		(math.random() * 2 - 1) * PIVOT_RANDOM_OFFSET_BOUNDS,
		(math.random() * 2 - 1) * PIVOT_RANDOM_OFFSET_BOUNDS
	)
end

function DamageNumbers:_playSpawnAnimation(state, isUpdate)
	if not state then
		return
	end

	if state.rotateTween then
		state.rotateTween:Cancel()
	end
	if state.popTween then
		state.popTween:Cancel()
	end
	if state.popSettleTween then
		state.popSettleTween:Cancel()
	end
	if state.appearTween then
		state.appearTween:Cancel()
	end

	if state.frame and state.frame:IsA("CanvasGroup") then
		state.frame.GroupTransparency = isUpdate and 0 or 1
		state.frame.Rotation = (math.random() * 2 - 1) * POP_ROTATION_MAX
	end

	if state.popScale then
		state.popScale.Scale = POP_START_SCALE
	end

	if not isUpdate and state.frame and state.frame:IsA("CanvasGroup") then
		state.appearTween = TweenService:Create(state.frame, APPEAR_TWEEN, {
			GroupTransparency = 0,
		})
		state.appearTween:Play()
	end

	if state.frame and state.frame:IsA("CanvasGroup") then
		state.rotateTween = TweenService:Create(state.frame, POP_IN_TWEEN, {
			Rotation = 0,
		})
		state.rotateTween:Play()
	end

	if state.popScale then
		state.popTween = TweenService:Create(state.popScale, POP_IN_TWEEN, {
			Scale = POP_OVERSHOOT_SCALE,
		})
		state.popTween:Play()
		state.popTween.Completed:Once(function()
			if not state.popScale then
				return
			end
			state.popSettleTween = TweenService:Create(state.popScale, POP_SETTLE_TWEEN, {
				Scale = POP_SETTLE_SCALE,
			})
			state.popSettleTween:Play()
		end)
	end
end

function DamageNumbers:_scheduleExit(targetUserId: number, state)
	local serialAtStart = state.serialRef.value
	task.delay(HOLD_TIME, function()
		local live = self._activeByTarget[targetUserId]
		if live ~= state then
			return
		end
		if state.serialRef.value ~= serialAtStart then
			return
		end

		state.moveTween = TweenService:Create(state.anchorPart, EXIT_TWEEN, {
			Position = state.anchorPart.Position + FLOAT_OFFSET,
		})
		state.moveTween:Play()

		if state.frame and state.frame:IsA("CanvasGroup") then
			state.fadeTween = TweenService:Create(state.frame, EXIT_TWEEN, {
				GroupTransparency = 1,
			})
			state.fadeTween:Play()
		end

		task.delay(EXIT_TWEEN.Time + 0.02, function()
			local current = self._activeByTarget[targetUserId]
			if current ~= state then
				return
			end
			cleanupState(state)
			self._activeByTarget[targetUserId] = nil
		end)
	end)
end

function DamageNumbers:_flushPendingTarget(targetUserId: number)
	local pending = self._pendingByTarget[targetUserId]
	if not pending then
		return
	end

	self._pendingByTarget[targetUserId] = nil

	local addDamage = math.max(0, math.floor(tonumber(pending.damage) or 0))
	if addDamage <= 0 then
		return
	end
	local anchoredPosition = pending.position + self:_getRandomPivotOffset()
	local isNewState = false

	local state = self._activeByTarget[targetUserId]
	if not state then
		state = self:_createState(anchoredPosition)
		self._activeByTarget[targetUserId] = state
		isNewState = true
	else
		if state.moveTween then
			state.moveTween:Cancel()
			state.moveTween = nil
		end
		if state.fadeTween then
			state.fadeTween:Cancel()
			state.fadeTween = nil
		end
		if state.anchorPart then
			state.anchorPart.CFrame = CFrame.new(anchoredPosition)
		end
		if state.frame and state.frame:IsA("CanvasGroup") then
			state.frame.GroupTransparency = 0
		end
		state.serialRef.value += 1
	end

	state.totalDamage = (state.totalDamage or 0) + addDamage
	self:_applyStyle(state, pending.options)

	if state.mainText then
		state.mainText.Text = tostring(state.totalDamage)
	end
	self:_playSpawnAnimation(state, not isNewState)

	self:_scheduleExit(targetUserId, state)
end

function DamageNumbers:_reflowStackedTarget(targetUserId)
	local bucket = self._stackedByTarget[targetUserId]
	if not bucket then
		return
	end

	local live = {}
	for _, entry in ipairs(bucket) do
		local state = entry and entry.state
		if state and state.anchorPart and state.anchorPart.Parent then
			table.insert(live, entry)
		end
	end

	if #live == 0 then
		self._stackedByTarget[targetUserId] = nil
		return
	end

	self._stackedByTarget[targetUserId] = live
	for index, entry in ipairs(live) do
		local state = entry.state
		if state and state.anchorPart then
			local desired = entry.basePosition + Vector3.new(0, (index - 1) * STACKED_VERTICAL_STEP, 0)
			state.anchorPart.CFrame = CFrame.new(desired)
		end
	end
end

function DamageNumbers:_removeStackedEntry(targetUserId, targetEntry)
	local bucket = self._stackedByTarget[targetUserId]
	if not bucket then
		return
	end

	for i = #bucket, 1, -1 do
		if bucket[i] == targetEntry then
			table.remove(bucket, i)
			break
		end
	end

	if #bucket == 0 then
		self._stackedByTarget[targetUserId] = nil
	else
		self:_reflowStackedTarget(targetUserId)
	end
end

function DamageNumbers:_scheduleStackedExit(targetUserId, entry)
	local state = entry and entry.state
	if not state then
		return
	end

	task.delay(HOLD_TIME, function()
		local bucket = self._stackedByTarget[targetUserId]
		if not bucket then
			return
		end

		local stillLive = false
		for _, liveEntry in ipairs(bucket) do
			if liveEntry == entry then
				stillLive = true
				break
			end
		end
		if not stillLive then
			return
		end

		if state.moveTween then
			state.moveTween:Cancel()
		end
		if state.fadeTween then
			state.fadeTween:Cancel()
		end

		state.moveTween = TweenService:Create(state.anchorPart, EXIT_TWEEN, {
			Position = state.anchorPart.Position + FLOAT_OFFSET,
		})
		state.moveTween:Play()

		if state.frame and state.frame:IsA("CanvasGroup") then
			state.fadeTween = TweenService:Create(state.frame, EXIT_TWEEN, {
				GroupTransparency = 1,
			})
			state.fadeTween:Play()
		end

		task.delay(EXIT_TWEEN.Time + 0.02, function()
			self:_removeStackedEntry(targetUserId, entry)
			cleanupState(state)
		end)
	end)
end

function DamageNumbers:_showStackedForTarget(targetUserId, position: Vector3, damage: number, options)
	local amount = math.max(0, math.floor(tonumber(damage) or 0))
	if amount <= 0 then
		return
	end

	local anchoredPosition = position + self:_getRandomPivotOffset()
	local state = self:_createState(anchoredPosition)
	state.totalDamage = amount

	self:_applyStyle(state, options)
	if state.mainText then
		state.mainText.Text = tostring(amount)
		state.mainText.TextScaled = false
		state.mainText.TextSize = STACKED_TEXT_SIZE
		state.mainText.TextXAlignment = Enum.TextXAlignment.Left
	end
	self:_playSpawnAnimation(state, false)

	local bucket = self._stackedByTarget[targetUserId]
	if not bucket then
		bucket = {}
		self._stackedByTarget[targetUserId] = bucket
	end

	local entry = {
		state = state,
		basePosition = position,
	}
	table.insert(bucket, 1, entry)
	self:_reflowStackedTarget(targetUserId)
	self:_scheduleStackedExit(targetUserId, entry)
end

function DamageNumbers:_flushStackedPendingTarget(targetUserId)
	local pending = self._stackedPendingByTarget[targetUserId]
	if not pending then
		return
	end

	self._stackedPendingByTarget[targetUserId] = nil
	for _, entry in ipairs(pending.entries) do
		self:_showStackedForTarget(targetUserId, entry.position, entry.damage, entry.options)
	end
end

function DamageNumbers:ShowForTarget(targetUserId, position: Vector3, damage: number, options)
	if not self._initialized then
		self:Init()
	end

	if not CombatConfig.DamageNumbers.Enabled then
		return
	end
	if self._mode == DAMAGE_NUMBERS_MODE_DISABLED then
		return
	end

	local keyType = type(targetUserId)
	if typeof(position) ~= "Vector3" or (keyType ~= "number" and keyType ~= "string") then
		return
	end

	local addDamage = math.max(0, math.floor(tonumber(damage) or 0))
	if addDamage <= 0 then
		return
	end

	if self._mode == DAMAGE_NUMBERS_MODE_STACKED then
		local pending = self._stackedPendingByTarget[targetUserId]
		if not pending then
			pending = {
				entries = {},
				scheduled = false,
			}
			self._stackedPendingByTarget[targetUserId] = pending
		end

		table.insert(pending.entries, {
			damage = addDamage,
			position = position,
			options = options or {},
		})

		if not pending.scheduled then
			pending.scheduled = true
			task.delay(STACKED_ACCEPT_WINDOW, function()
				self:_flushStackedPendingTarget(targetUserId)
			end)
		end
		return
	end

	local pending = self._pendingByTarget[targetUserId]
	if not pending then
		pending = {
			damage = 0,
			position = position,
			options = options or {},
			scheduled = false,
		}
		self._pendingByTarget[targetUserId] = pending
	end
	pending.damage += addDamage
	pending.position = position

	local mergedOptions = pending.options or {}
	local incomingOptions = options or {}
	mergedOptions.isCritical = mergedOptions.isCritical == true or incomingOptions.isCritical == true
	mergedOptions.isHeadshot = mergedOptions.isHeadshot == true or incomingOptions.isHeadshot == true
	mergedOptions.color = incomingOptions.color or mergedOptions.color
	pending.options = mergedOptions

	if not pending.scheduled then
		pending.scheduled = true
		task.delay(BURST_ACCUMULATION_WINDOW, function()
			self:_flushPendingTarget(targetUserId)
		end)
	end
end

function DamageNumbers:Show(position: Vector3, damage: number, options)
	local fallbackTarget = (options and options.targetUserId) or -1
	self:ShowForTarget(fallbackTarget, position, damage, options)
end

function DamageNumbers:ClearTarget(targetUserId: number)
	self._pendingByTarget[targetUserId] = nil
	self._stackedPendingByTarget[targetUserId] = nil
	local state = self._activeByTarget[targetUserId]
	if not state then
		local stacked = self._stackedByTarget[targetUserId]
		if stacked then
			for _, entry in ipairs(stacked) do
				if entry and entry.state then
					cleanupState(entry.state)
				end
			end
			self._stackedByTarget[targetUserId] = nil
		end
		return
	end
	cleanupState(state)
	self._activeByTarget[targetUserId] = nil

	local stacked = self._stackedByTarget[targetUserId]
	if stacked then
		for _, entry in ipairs(stacked) do
			if entry and entry.state then
				cleanupState(entry.state)
			end
		end
		self._stackedByTarget[targetUserId] = nil
	end
end

function DamageNumbers:ClearAll()
	for targetUserId in self._pendingByTarget do
		self._pendingByTarget[targetUserId] = nil
	end

	for targetUserId in self._stackedPendingByTarget do
		self._stackedPendingByTarget[targetUserId] = nil
	end

	for targetUserId, state in self._activeByTarget do
		cleanupState(state)
		self._activeByTarget[targetUserId] = nil
	end

	for targetUserId, bucket in self._stackedByTarget do
		for _, entry in ipairs(bucket) do
			if entry and entry.state then
				cleanupState(entry.state)
			end
		end
		self._stackedByTarget[targetUserId] = nil
	end
end

return DamageNumbers
