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

local APPEAR_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EXIT_TWEEN = TweenInfo.new(
	math.max(0.55, tonumber(CombatConfig.DamageNumbers.FadeDuration) or 0.3),
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)
local HOLD_TIME = math.max(2.5, tonumber(CombatConfig.DamageNumbers.FadeTime) or 1.0)
local FLOAT_OFFSET = Vector3.new(0, 3.4, 0)
local BURST_ACCUMULATION_WINDOW = 0.06

local function createFallbackTemplate(): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "dmgnmbr"

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumbers"
	billboard.Active = true
	billboard.ClipsDescendants = true
	billboard.Size = UDim2.new(3.5, 45, 3.5, 45)
	billboard.StudsOffsetWorldSpace = Vector3.zero
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
	sizeConstraint.MaxTextSize = 36
	sizeConstraint.Parent = mainText

	return attachment
end

local function getTemplate(): Attachment
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local template = assets:FindFirstChild("dmgnmbr")
		if template and template:IsA("Attachment") then
			return template
		end
	end

	return createFallbackTemplate()
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
	self._initialized = true
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

	if billboard and billboard:IsA("BillboardGui") then
		billboard.Adornee = attachment
		billboard.StudsOffsetWorldSpace = Vector3.zero
		billboard.Enabled = true
	end

	return {
		anchorPart = anchorPart,
		attachment = attachment,
		billboard = billboard,
		frame = frame,
		mainText = mainText,
		glow = glow,
		totalDamage = 0,
		serialRef = { value = 0 },
		appearTween = nil,
		moveTween = nil,
		fadeTween = nil,
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

	local state = self._activeByTarget[targetUserId]
	if not state then
		state = self:_createState(pending.position)
		self._activeByTarget[targetUserId] = state

		if state.frame and state.frame:IsA("CanvasGroup") then
			state.frame.GroupTransparency = 1
			state.appearTween = TweenService:Create(state.frame, APPEAR_TWEEN, {
				GroupTransparency = 0,
			})
			state.appearTween:Play()
		end
	else
		if state.anchorPart then
			state.anchorPart.CFrame = CFrame.new(pending.position)
		end
		if state.moveTween then
			state.moveTween:Cancel()
		end
		if state.fadeTween then
			state.fadeTween:Cancel()
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

	self:_scheduleExit(targetUserId, state)
end

function DamageNumbers:ShowForTarget(targetUserId: number, position: Vector3, damage: number, options)
	if not self._initialized then
		self:Init()
	end

	if not CombatConfig.DamageNumbers.Enabled then
		return
	end

	if typeof(position) ~= "Vector3" or type(targetUserId) ~= "number" then
		return
	end

	local addDamage = math.max(0, math.floor(tonumber(damage) or 0))
	if addDamage <= 0 then
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
	local state = self._activeByTarget[targetUserId]
	if not state then
		return
	end
	cleanupState(state)
	self._activeByTarget[targetUserId] = nil
end

function DamageNumbers:ClearAll()
	for targetUserId in self._pendingByTarget do
		self._pendingByTarget[targetUserId] = nil
	end

	for targetUserId, state in self._activeByTarget do
		cleanupState(state)
		self._activeByTarget[targetUserId] = nil
	end
end

return DamageNumbers
