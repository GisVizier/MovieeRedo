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

local APPEAR_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EXIT_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOLD_TIME = 0.36
local FLOAT_OFFSET = Vector3.new(0, 2.5, 0)

local function createFallbackTemplate(): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "dmgnmbr"

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumbers"
	billboard.Active = true
	billboard.ClipsDescendants = true
	billboard.Size = UDim2.new(3.5, 45, 3.5, 45)
	billboard.StudsOffsetWorldSpace = Vector3.new(-3, 3, 0)
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

	local billboard = attachment:FindFirstChild("DamageNumbers")
	local frame = billboard and billboard:FindFirstChild("Frame")
	local mainText = frame and frame:FindFirstChild("MainText")
	local glow = frame and frame:FindFirstChild("Glow")

	if billboard and billboard:IsA("BillboardGui") then
		billboard.Adornee = attachment
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

	local previous = self._activeByTarget[targetUserId]
	local runningTotal = addDamage
	if previous then
		runningTotal += previous.totalDamage or 0
		cleanupState(previous)
	end

	local state = self:_createState(position)
	state.totalDamage = runningTotal
	self:_applyStyle(state, options)
	self._activeByTarget[targetUserId] = state

	if state.mainText then
		state.mainText.Text = tostring(runningTotal)
	end

	if state.frame and state.frame:IsA("CanvasGroup") then
		state.frame.GroupTransparency = 1
		state.appearTween = TweenService:Create(state.frame, APPEAR_TWEEN, {
			GroupTransparency = 0,
		})
		state.appearTween:Play()
	end

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

function DamageNumbers:Show(position: Vector3, damage: number, options)
	local fallbackTarget = (options and options.targetUserId) or -1
	self:ShowForTarget(fallbackTarget, position, damage, options)
end

function DamageNumbers:ClearTarget(targetUserId: number)
	local state = self._activeByTarget[targetUserId]
	if not state then
		return
	end
	cleanupState(state)
	self._activeByTarget[targetUserId] = nil
end

function DamageNumbers:ClearAll()
	for targetUserId, state in self._activeByTarget do
		cleanupState(state)
		self._activeByTarget[targetUserId] = nil
	end
end

return DamageNumbers
