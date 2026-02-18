--[[
	QueueController
	
	Client-side controller for queue UI and pad visuals.
	
	Features:
	- Countdown GUI display
	- Pad visual updates (color changes)
	- Board display updates (player avatars, queue count)
	- Match transition handling
	
	API:
	- QueueController:IsInQueue() -> boolean
	- QueueController:GetCountdownRemaining() -> number or nil
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunService = game:GetService("RunService")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))

local QueueController = {}

-- DEBUG: Client-side position logging
local DEBUG_ENABLED = false
local DEBUG_INTERVAL = 3

local function debugPrint(...) end

function QueueController:Init(registry, net)
	self._registry = registry
	self._net = net

	-- State
	self._inQueue = false
	self._countdownActive = false
	self._countdownRemaining = nil
	self._myTeam = nil
	self._currentPadName = nil

	-- Pad cache for quick lookup
	self._pads = {}

	-- Board display cache: { [padName] = { leftSide, rightSide, counter, leftImage, rightImage } }
	self._boards = {}

	-- Track queue state per pad: { [padName] = { Team1 = playerId or nil, Team2 = playerId or nil } }
	self._queueState = {}

	-- GUI references (created dynamically)
	self._countdownGui = nil
	self._countdownLabel = nil

	-- Debug timing
	self._lastDebugPrint = 0

	self:_cachePads()
	self:_setupNetworkListeners()

	debugPrint("=== QueueController:Init() CALLED ===")
end

function QueueController:Start()
	self:_createCountdownGui()
	self:_startClientDebugLoop()
	debugPrint("=== QueueController:Start() COMPLETE ===")
end

function QueueController:_startClientDebugLoop()
	if not DEBUG_ENABLED then
		return
	end

	RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - self._lastDebugPrint >= DEBUG_INTERVAL then
			self._lastDebugPrint = now
			self:_printClientDebugSummary()
		end
	end)
end

function QueueController:_printClientDebugSummary()
	local player = Players.LocalPlayer
	local character = player.Character

	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
		if rootPart then
		else
			for _, child in character:GetChildren() do
			end
		end
	else
	end
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

	-- Match teleport (client-side teleportation for custom character system)
	self._net:ConnectClient("MatchTeleport", function(data)
		self:_onMatchTeleport(data)
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

	debugPrint("Caching pads with tag:", padTag)

	local taggedPads = CollectionService:GetTagged(padTag)
	debugPrint("CLIENT found", #taggedPads, "pads with tag '" .. padTag .. "'")

	for _, pad in taggedPads do
		debugPrint("  Caching pad:", pad.Name, "| Path:", pad:GetFullName())
		self._pads[pad.Name] = pad
		self:_cacheBoardForPad(pad)
		self:_initQueueState(pad.Name)

		-- Debug: print zone positions
		local team1 = pad:FindFirstChild("Team1")
		local team2 = pad:FindFirstChild("Team2")
		if team1 then
			local inner = team1:FindFirstChild("Inner")
			if inner and inner:IsA("BasePart") then
				debugPrint("    Team1 Inner position:", inner.Position)
			end
		end
		if team2 then
			local inner = team2:FindFirstChild("Inner")
			if inner and inner:IsA("BasePart") then
				debugPrint("    Team2 Inner position:", inner.Position)
			end
		end
	end

	CollectionService:GetInstanceAddedSignal(padTag):Connect(function(pad)
		debugPrint("NEW PAD ADDED (client):", pad.Name)
		self._pads[pad.Name] = pad
		self:_cacheBoardForPad(pad)
		self:_initQueueState(pad.Name)
	end)

	CollectionService:GetInstanceRemovedSignal(padTag):Connect(function(pad)
		self._pads[pad.Name] = nil
		self._boards[pad.Name] = nil
		self._queueState[pad.Name] = nil
	end)
end

function QueueController:_cacheBoardForPad(pad)
	debugPrint("Caching board for pad:", pad.Name)

	local board = pad:FindFirstChild("Board")
	if not board then
		debugPrint("  No Board found in pad")
		return
	end

	local surfaceGui = board:FindFirstChild("SurfaceGui")
	if not surfaceGui then
		debugPrint("  No SurfaceGui found in Board")
		return
	end

	local frame = surfaceGui:FindFirstChild("Frame")
	if not frame then
		debugPrint("  No Frame found in SurfaceGui")
		return
	end

	local leftSide = frame:FindFirstChild("LeftSide")
	local rightSide = frame:FindFirstChild("RightSide")
	local counter = frame:FindFirstChild("Counter")

	debugPrint("  LeftSide found:", leftSide ~= nil)
	debugPrint("  RightSide found:", rightSide ~= nil)
	debugPrint("  Counter found:", counter ~= nil)

	local leftImage = leftSide and self:_findImageLabel(leftSide)
	local rightImage = rightSide and self:_findImageLabel(rightSide)

	debugPrint("  LeftImage found:", leftImage ~= nil, leftImage and leftImage:GetFullName() or "N/A")
	debugPrint("  RightImage found:", rightImage ~= nil, rightImage and rightImage:GetFullName() or "N/A")

	-- Debug: print all children of LeftSide/RightSide if no image found
	if leftSide and not leftImage then
		debugPrint("  LeftSide children (no ImageLabel found):")
		for _, child in leftSide:GetDescendants() do
			debugPrint("    -", child.Name, "(" .. child.ClassName .. ")")
		end
	end
	if rightSide and not rightImage then
		debugPrint("  RightSide children (no ImageLabel found):")
		for _, child in rightSide:GetDescendants() do
			debugPrint("    -", child.Name, "(" .. child.ClassName .. ")")
		end
	end

	local counterText = nil
	if counter then
		counterText = counter:FindFirstChild("TextLabel") or counter:FindFirstChildOfClass("TextLabel")
		if not counterText then
			for _, desc in counter:GetDescendants() do
				if desc:IsA("TextLabel") then
					counterText = desc
					break
				end
			end
		end
	end
	debugPrint("  CounterText found:", counterText ~= nil)

	self._boards[pad.Name] = {
		leftSide = leftSide,
		rightSide = rightSide,
		counter = counter,
		counterText = counterText,
		leftImage = leftImage,
		rightImage = rightImage,
	}

	if leftSide then
		leftSide.Visible = false
	end
	if rightSide then
		rightSide.Visible = false
	end
	if counterText then
		counterText.Text = "0"
	end

	debugPrint("  Board cached successfully")
end

function QueueController:_findImageLabel(parent)
	local imageLabel = parent:FindFirstChild("ImageLabel")
	if imageLabel and imageLabel:IsA("ImageLabel") then
		return imageLabel
	end

	for _, desc in parent:GetDescendants() do
		if desc:IsA("ImageLabel") then
			return desc
		end
	end

	return nil
end

function QueueController:_initQueueState(padName)
	self._queueState[padName] = {
		Team1 = nil,
		Team2 = nil,
	}
end

function QueueController:_onPadUpdate(data)
	local padName = data.padName or data.padId
	local team = data.team
	local occupied = data.occupied
	local playerId = data.playerId

	-- Check if this is the local player
	local localPlayer = Players.LocalPlayer
	if playerId and playerId == localPlayer.UserId then
		self._inQueue = occupied
		self._myTeam = occupied and team or nil
		self._currentPadName = occupied and padName or nil
	end

	-- Update pad visual for the specific team zone
	self:_updateTeamZoneVisual(padName, team, occupied and "occupied" or "empty")

	-- Update queue state
	local queueState = self._queueState[padName]
	if queueState then
		queueState[team] = occupied and playerId or nil
	end

	-- Update board display
	self:_updateBoardDisplay(padName, team, occupied, playerId)
end

function QueueController:_updatePadVisual(padName, state)
	local pad = self._pads[padName]
	if not pad then
		return
	end

	local colors = MatchmakingConfig.PadVisuals
	local color = self:_getColorForState(state)

	-- Tween the color change
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Update all descendant parts
	for _, part in pad:GetDescendants() do
		if part:IsA("BasePart") then
			local tween = TweenService:Create(part, tweenInfo, { Color = color })
			tween:Play()
		end
	end
end

function QueueController:_updateTeamZoneVisual(padName, team, state)
	local pad = self._pads[padName]
	if not pad then
		return
	end

	local teamModel = pad:FindFirstChild(team)
	if not teamModel then
		-- Fallback to old behavior
		self:_updatePadVisual(padName, state)
		return
	end

	local color = self:_getColorForState(state)
	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Update all parts in the team model
	for _, part in teamModel:GetDescendants() do
		if part:IsA("BasePart") then
			local tween = TweenService:Create(part, tweenInfo, { Color = color })
			tween:Play()
		end
	end

	if teamModel:IsA("BasePart") then
		local tween = TweenService:Create(teamModel, tweenInfo, { Color = color })
		tween:Play()
	end
end

function QueueController:_getColorForState(state)
	local colors = MatchmakingConfig.PadVisuals

	if state == "empty" then
		return colors.EmptyColor
	elseif state == "occupied" then
		return colors.OccupiedColor
	elseif state == "countdown" then
		return colors.CountdownColor
	elseif state == "ready" then
		return colors.ReadyColor
	else
		return colors.EmptyColor
	end
end

--------------------------------------------------------------------------------
-- BOARD DISPLAY
--------------------------------------------------------------------------------

function QueueController:_updateBoardDisplay(padName, team, occupied, playerId)
	debugPrint("_updateBoardDisplay:", padName, team, "occupied:", occupied, "playerId:", playerId)

	local board = self._boards[padName]
	if not board then
		debugPrint("  No board cached for pad:", padName)
		return
	end

	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if team == "Team1" then
		debugPrint("  Team1 - leftSide:", board.leftSide ~= nil, "leftImage:", board.leftImage ~= nil)
		if board.leftSide then
			board.leftSide.Visible = occupied
			debugPrint("  Set leftSide.Visible =", occupied)
		end
		if occupied and playerId and board.leftImage then
			debugPrint("  Setting player avatar for Team1, playerId:", playerId)
			self:_setPlayerAvatar(board.leftImage, playerId)
		elseif occupied and playerId and not board.leftImage then
			debugPrint("  WARNING: No leftImage to set avatar!")
		end
	elseif team == "Team2" then
		debugPrint("  Team2 - rightSide:", board.rightSide ~= nil, "rightImage:", board.rightImage ~= nil)
		if board.rightSide then
			board.rightSide.Visible = occupied
			debugPrint("  Set rightSide.Visible =", occupied)
		end
		if occupied and playerId and board.rightImage then
			debugPrint("  Setting player avatar for Team2, playerId:", playerId)
			self:_setPlayerAvatar(board.rightImage, playerId)
		elseif occupied and playerId and not board.rightImage then
			debugPrint("  WARNING: No rightImage to set avatar!")
		end
	end

	self:_updateBoardCounter(padName)
end

function QueueController:_updateBoardCounter(padName)
	local board = self._boards[padName]
	local queueState = self._queueState[padName]

	if not board or not queueState then
		return
	end

	local count = 0
	if queueState.Team1 then
		count = count + 1
	end
	if queueState.Team2 then
		count = count + 1
	end

	if board.counterText then
		board.counterText.Text = tostring(count)

		local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		board.counterText.TextTransparency = 0.5
		local tween = TweenService:Create(board.counterText, tweenInfo, {
			TextTransparency = 0,
		})
		tween:Play()
	end
end

function QueueController:_setPlayerAvatar(imageLabel, userId)
	debugPrint("_setPlayerAvatar called, imageLabel:", imageLabel:GetFullName(), "userId:", userId)

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)

		debugPrint("  GetUserThumbnailAsync result - success:", success, "content:", content and "got content" or "nil")

		if success and content and imageLabel then
			imageLabel.Image = content
			debugPrint("  Set imageLabel.Image to:", content)
		else
			debugPrint(
				"  FAILED to set avatar - success:",
				success,
				"content:",
				content ~= nil,
				"imageLabel:",
				imageLabel ~= nil
			)
		end
	end)
end

function QueueController:_resetBoardDisplay(padName)
	local board = self._boards[padName]
	if not board then
		return
	end

	if board.leftSide then
		board.leftSide.Visible = false
	end
	if board.rightSide then
		board.rightSide.Visible = false
	end
	if board.counterText then
		board.counterText.Text = "0"
	end

	local queueState = self._queueState[padName]
	if queueState then
		queueState.Team1 = nil
		queueState.Team2 = nil
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
	local padName = data.padName

	-- Only show countdown if this is the pad we're on
	if self._currentPadName and self._currentPadName == padName then
		self._countdownActive = true
		self._countdownRemaining = data.duration

		-- Show countdown GUI
		self:_updateCountdownLabel(data.duration)
		self:_showCountdownGui()
	end

	-- Update the specific pad to countdown color
	local pad = self._pads[padName]
	if pad then
		self:_updatePadVisual(padName, "countdown")
	end
end

function QueueController:_onCountdownTick(data)
	local padName = data.padName

	-- Only update if this is our pad
	if self._currentPadName and self._currentPadName == padName then
		self._countdownRemaining = data.remaining
		self:_updateCountdownLabel(data.remaining)
	end
end

function QueueController:_onCountdownCancel(data)
	local padName = data.padName

	-- Only hide if this is our pad
	if self._currentPadName and self._currentPadName == padName then
		self._countdownActive = false
		self._countdownRemaining = nil
		self:_hideCountdownGui()
	end

	-- Reset the specific pad colors
	local pad = self._pads[padName]
	if pad then
		self:_updatePadVisual(padName, "empty")
	end
end

--------------------------------------------------------------------------------
-- MATCH EVENTS
--------------------------------------------------------------------------------

function QueueController:_onMatchReady(data)
	local padName = data.padName

	self._countdownActive = false
	self._countdownRemaining = nil
	self._inQueue = false
	self._currentPadName = nil

	-- Hide countdown GUI
	self:_hideCountdownGui()

	-- Update the specific pad to ready color briefly
	local pad = self._pads[padName]
	if pad then
		self:_updatePadVisual(padName, "ready")

		-- Reset after a short delay
		task.delay(1, function()
			if self._pads[padName] then
				self:_updatePadVisual(padName, "empty")
				self:_resetBoardDisplay(padName)
			end
		end)
	end

	-- The Map/Loadout UI will be triggered by the existing flow
end

function QueueController:_onMatchTeleport(data)
	debugPrint("=== MatchTeleport received ===")
	debugPrint("  matchId:", data.matchId)
	debugPrint("  team:", data.team)
	debugPrint("  spawnPosition:", data.spawnPosition)
	debugPrint("  spawnLookVector:", data.spawnLookVector)
	debugPrint("  isWaitingRoom:", data.isWaitingRoom)

	local spawnPos = data.spawnPosition
	local lookVector = data.spawnLookVector
	local matchId = data.matchId
	local isWaitingRoom = data.isWaitingRoom

	if not spawnPos then
		return
	end

	-- Stop any active emotes before teleporting
	self._net:FireServer("EmoteStop")

	local player = Players.LocalPlayer
	local UserInputService = game:GetService("UserInputService")

	-- Handle waiting room special setup
	if isWaitingRoom then
		debugPrint("  Waiting room teleport - setting up for map selection")
		
		-- Mark that we're in waiting room mode
		self._isInWaitingRoom = true
		player:SetAttribute("InWaitingRoom", true)
		
		-- Use MovementController.Teleport for clean teleport
		local movementController = self._registry:TryGet("Movement")
		if movementController and type(movementController.Teleport) == "function" then
			debugPrint("  Using MovementController:Teleport()")
			movementController:Teleport(spawnPos, lookVector)
			
			-- After teleport completes, keep character anchored for waiting room
			task.delay(0.15, function()
				local character = player.Character
				if character then
					local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
					if root then
						root.Anchored = true
						root.AssemblyLinearVelocity = Vector3.zero
						root.AssemblyAngularVelocity = Vector3.zero
						debugPrint("  Character re-anchored for waiting room")
					end
				end
			end)
		else
			-- Fallback: Direct teleport
			local character = player.Character
			if character then
				local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
				if root then
					root.Anchored = true
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					local targetCFrame = lookVector and CFrame.lookAt(spawnPos, spawnPos + lookVector) or CFrame.new(spawnPos)
					root.CFrame = targetCFrame
					debugPrint("  Fallback teleport executed")
				end
			end
		end
		
		-- Set camera to scriptable mode for map selection UI
		task.delay(0.2, function()
			local camera = workspace.CurrentCamera
			if camera then
				self._preWaitingRoomCameraType = camera.CameraType
				camera.CameraType = Enum.CameraType.Scriptable
				
				-- Position camera at spawn looking forward
				local cameraCFrame = CFrame.lookAt(spawnPos + Vector3.new(0, 5, 5), spawnPos + Vector3.new(0, 0, -10))
				camera.CFrame = cameraCFrame
				debugPrint("  Camera set to scriptable mode")
			end
			
			-- Unlock mouse for UI interaction
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			debugPrint("  Mouse unlocked for UI")
		end)
		
		return
	end

	-- Restore camera for normal gameplay (when leaving waiting room)
	if self._isInWaitingRoom then
		-- Unanchor character first
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
			if root then
				root.Anchored = false
				debugPrint("  Character unanchored from waiting room")
			end
		end
		
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			debugPrint("  Camera restored to Custom mode")
		end
		
		-- Re-lock mouse for gameplay
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
		debugPrint("  Mouse locked for gameplay")
		
		self._isInWaitingRoom = false
		player:SetAttribute("InWaitingRoom", nil)
	end

	-- Use MovementController to teleport (handles custom character system)
	local movementController = self._registry:TryGet("Movement")

	if movementController and type(movementController.Teleport) == "function" then
		debugPrint("  Calling MovementController:Teleport()")
		local success = movementController:Teleport(spawnPos, lookVector)
		debugPrint("  Teleport result:", success)
	else
		-- Fallback: Try to move character directly (may not work with anchored HumanoidRootPart)
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
			if root then
				local destCFrame
				if lookVector then
					destCFrame = CFrame.lookAt(spawnPos, spawnPos + lookVector)
				else
					destCFrame = CFrame.new(spawnPos)
				end
				character:PivotTo(destCFrame)
				debugPrint("  Fallback PivotTo executed")
			end
		end
	end

	-- Confirm teleport to server (so it knows to start the match)
	-- Skip for round reset or lobby return
	if matchId and matchId ~= "reset" and not data.roundReset then
		task.delay(0.1, function()
			self._net:FireServer("MatchTeleportReady", {
				matchId = matchId,
			})
			debugPrint("  Sent MatchTeleportReady confirmation")
		end)
	end
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

	-- Reset pad colors and board displays
	for padName, pad in self._pads do
		self:_updatePadVisual(padName, "empty")
		self:_resetBoardDisplay(padName)
	end
end

return QueueController
