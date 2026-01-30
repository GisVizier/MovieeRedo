--[[
	QueueController
	
	Client-side controller for queue UI and pad visuals.
	
	Features:
	- Countdown GUI display
	- Pad visual updates (color changes)
	- Match transition handling
	
	API:
	- QueueController:IsInQueue() -> boolean
	- QueueController:GetCountdownRemaining() -> number or nil
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))

local QueueController = {}

function QueueController:Init(registry, net)
	self._registry = registry
	self._net = net

	-- State
	self._inQueue = false
	self._countdownActive = false
	self._countdownRemaining = nil
	self._myTeam = nil

	-- Pad cache for quick lookup
	self._pads = {}

	-- GUI references (created dynamically)
	self._countdownGui = nil
	self._countdownLabel = nil

	self:_cachePads()
	self:_setupNetworkListeners()
end

function QueueController:Start()
	self:_createCountdownGui()
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function QueueController:IsInQueue()
	return self._inQueue
end

function QueueController:GetCountdownRemaining()
	return self._countdownRemaining
end

--------------------------------------------------------------------------------
-- NETWORK LISTENERS
--------------------------------------------------------------------------------

function QueueController:_setupNetworkListeners()
	-- Pad updates
	self._net:ConnectClient("QueuePadUpdate", function(data)
		self:_onPadUpdate(data)
	end)

	-- Countdown events
	self._net:ConnectClient("QueueCountdownStart", function(data)
		self:_onCountdownStart(data)
	end)

	self._net:ConnectClient("QueueCountdownTick", function(data)
		self:_onCountdownTick(data)
	end)

	self._net:ConnectClient("QueueCountdownCancel", function(data)
		self:_onCountdownCancel(data)
	end)

	-- Match ready
	self._net:ConnectClient("QueueMatchReady", function(data)
		self:_onMatchReady(data)
	end)

	-- Round events
	self._net:ConnectClient("RoundStart", function(data)
		self:_onRoundStart(data)
	end)

	self._net:ConnectClient("ScoreUpdate", function(data)
		self:_onScoreUpdate(data)
	end)

	self._net:ConnectClient("ShowRoundLoadout", function(data)
		self:_onShowRoundLoadout(data)
	end)

	self._net:ConnectClient("MatchEnd", function(data)
		self:_onMatchEnd(data)
	end)

	self._net:ConnectClient("ReturnToLobby", function(data)
		self:_onReturnToLobby(data)
	end)
end

--------------------------------------------------------------------------------
-- PAD HANDLING
--------------------------------------------------------------------------------

function QueueController:_cachePads()
	local padTag = MatchmakingConfig.Queue.PadTag

	for _, pad in CollectionService:GetTagged(padTag) do
		self._pads[pad.Name] = pad
	end

	CollectionService:GetInstanceAddedSignal(padTag):Connect(function(pad)
		self._pads[pad.Name] = pad
	end)

	CollectionService:GetInstanceRemovedSignal(padTag):Connect(function(pad)
		self._pads[pad.Name] = nil
	end)
end

function QueueController:_onPadUpdate(data)
	local padId = data.padId
	local team = data.team
	local occupied = data.occupied
	local playerId = data.playerId

	-- Check if this is the local player
	local localPlayer = Players.LocalPlayer
	if playerId and playerId == localPlayer.UserId then
		self._inQueue = occupied
		self._myTeam = occupied and team or nil
	end

	-- Update pad visual
	self:_updatePadVisual(padId, occupied and "occupied" or "empty")
end

function QueueController:_updatePadVisual(padId, state)
	local pad = self._pads[padId]
	if not pad then
		return
	end

	local colors = MatchmakingConfig.PadVisuals
	local color

	if state == "empty" then
		color = colors.EmptyColor
	elseif state == "occupied" then
		color = colors.OccupiedColor
	elseif state == "countdown" then
		color = colors.CountdownColor
	elseif state == "ready" then
		color = colors.ReadyColor
	else
		color = colors.EmptyColor
	end

	-- Tween the color change
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if pad:IsA("BasePart") then
		local tween = TweenService:Create(pad, tweenInfo, { Color = color })
		tween:Play()
	end

	-- Also update child visual part if exists
	local visualPart = pad:FindFirstChild("Visual") or pad:FindFirstChild("Surface")
	if visualPart and visualPart:IsA("BasePart") then
		local tween = TweenService:Create(visualPart, tweenInfo, { Color = color })
		tween:Play()
	end
end

--------------------------------------------------------------------------------
-- COUNTDOWN GUI
--------------------------------------------------------------------------------

function QueueController:_createCountdownGui()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "QueueCountdownGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- Background frame (subtle dark overlay)
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.new(0, 0, 0)
	background.BackgroundTransparency = 0.7
	background.BorderSizePixel = 0
	background.Parent = screenGui

	-- Countdown container
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.fromOffset(300, 200)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	-- Title label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 40)
	titleLabel.Position = UDim2.fromScale(0.5, 0.2)
	titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "MATCH STARTING"
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextSize = 28
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = container

	-- Countdown number
	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "Countdown"
	countdownLabel.Size = UDim2.new(1, 0, 0, 120)
	countdownLabel.Position = UDim2.fromScale(0.5, 0.55)
	countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Text = "5"
	countdownLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
	countdownLabel.TextSize = 100
	countdownLabel.Font = Enum.Font.GothamBold
	countdownLabel.Parent = container

	-- Hint label
	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.Size = UDim2.new(1, 0, 0, 30)
	hintLabel.Position = UDim2.fromScale(0.5, 0.85)
	hintLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Text = "Step off the pad to cancel"
	hintLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	hintLabel.TextSize = 16
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.Parent = container

	self._countdownGui = screenGui
	self._countdownLabel = countdownLabel
end

function QueueController:_showCountdownGui()
	if self._countdownGui then
		self._countdownGui.Enabled = true

		-- Animate in
		local container = self._countdownGui:FindFirstChild("Container")
		if container then
			container.Position = UDim2.fromScale(0.5, 0.6)
			local tween =
				TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = UDim2.fromScale(0.5, 0.5),
				})
			tween:Play()
		end
	end
end

function QueueController:_hideCountdownGui()
	if self._countdownGui then
		local container = self._countdownGui:FindFirstChild("Container")
		if container then
			local tween =
				TweenService:Create(container, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromScale(0.5, 0.4),
				})
			tween:Play()
			tween.Completed:Once(function()
				self._countdownGui.Enabled = false
			end)
		else
			self._countdownGui.Enabled = false
		end
	end
end

function QueueController:_updateCountdownLabel(value)
	if self._countdownLabel then
		self._countdownLabel.Text = tostring(value)

		-- Pulse animation on each tick
		local originalSize = 100
		self._countdownLabel.TextSize = originalSize * 1.3

		local tween = TweenService:Create(
			self._countdownLabel,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				TextSize = originalSize,
			}
		)
		tween:Play()
	end
end

--------------------------------------------------------------------------------
-- COUNTDOWN EVENTS
--------------------------------------------------------------------------------

function QueueController:_onCountdownStart(data)
	self._countdownActive = true
	self._countdownRemaining = data.duration

	-- Update all occupied pads to countdown color
	for padId, pad in self._pads do
		-- Check if pad is occupied (we'd need to track this, for now just set all)
		self:_updatePadVisual(padId, "countdown")
	end

	-- Show countdown GUI
	self:_updateCountdownLabel(data.duration)
	self:_showCountdownGui()
end

function QueueController:_onCountdownTick(data)
	self._countdownRemaining = data.remaining
	self:_updateCountdownLabel(data.remaining)
end

function QueueController:_onCountdownCancel(data)
	self._countdownActive = false
	self._countdownRemaining = nil

	-- Reset pad colors
	for padId, pad in self._pads do
		self:_updatePadVisual(padId, "empty")
	end

	-- Hide countdown GUI
	self:_hideCountdownGui()
end

--------------------------------------------------------------------------------
-- MATCH EVENTS
--------------------------------------------------------------------------------

function QueueController:_onMatchReady(data)
	self._countdownActive = false
	self._countdownRemaining = nil
	self._inQueue = false

	-- Hide countdown GUI
	self:_hideCountdownGui()

	-- Update pads to ready color briefly
	for padId, pad in self._pads do
		self:_updatePadVisual(padId, "ready")
	end

	-- The Map/Loadout UI will be triggered by the existing flow
end

function QueueController:_onRoundStart(data)
	-- Round started - could show round indicator
	-- For now, just log it
end

function QueueController:_onScoreUpdate(data)
	-- Score updated - UI will handle this via its own listener
	-- This is here for future expansion
end

function QueueController:_onShowRoundLoadout(data)
	-- Show loadout UI - this will be handled by UIController
	-- The event is here for consistency
end

function QueueController:_onMatchEnd(data)
	-- Match ended - could show victory/defeat screen
	-- For now, the ReturnToLobby event handles the transition
end

function QueueController:_onReturnToLobby(data)
	-- Reset all state
	self._inQueue = false
	self._countdownActive = false
	self._countdownRemaining = nil
	self._myTeam = nil

	-- Reset pad colors
	for padId, pad in self._pads do
		self:_updatePadVisual(padId, "empty")
	end
end

return QueueController
