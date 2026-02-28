local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local MapConfig = require(Configs.MapConfig)
local SettingsConfig = require(Configs.SettingsConfig)
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)

local module = {}
module.__index = module

local RoundCreateData = {
	players = {},
	teams = { team1 = {}, team2 = {} },
	gamemodeId = "TwoVTwo",
	matchCreatedTime = os.time(),
}

local COLOR_MAP = {
	Blue = Color3.fromRGB(39, 53, 255),
	Orange = Color3.fromRGB(231, 155, 32),
	Green = Color3.fromRGB(20, 177, 46),
	Yellow = Color3.fromRGB(233, 219, 23),
	Red = Color3.fromRGB(255, 0, 4),
	Pink = Color3.fromRGB(201, 34, 223),
	Purple = Color3.fromRGB(121, 25, 255),
	Cyan = Color3.fromRGB(27, 177, 247),
}

local currentTweens = {}

-- Inline tween configs (no child TweenConfig module)
local TWEEN_FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_CARD = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_BLIP_SHOW = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_BLIP_HIDE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TWEEN_HEADER = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections
	self._initialized = false
	self._competitiveMode = false

	-- Cache top-level UI refs
	self._blur = ui:FindFirstChild("Blur")
	self._bgStuff = ui:FindFirstChild("BgStuff")
	self._canvasGroup = ui:FindFirstChild("CanvasGroup")
	self._frameContainer = ui:FindFirstChild("Frame")

	-- ScrollingFrame holds map cards
	self._scrollingFrame = self._canvasGroup and self._canvasGroup:FindFirstChild("Frame")

	-- RightSideHolder (header area with map name + mode label)
	self._rightSideHolder = self._frameContainer
		and self._frameContainer:FindFirstChild("RightSideHolder")

	-- Distinguish left / right team panels by Position.X.Scale
	-- Left (<0.5) = local player's team, Right (>0.5) = enemy team
	self._leftPanel = nil
	self._rightPanel = nil
	if self._frameContainer then
		for _, child in self._frameContainer:GetChildren() do
			if child:IsA("Frame") and child.Name == "Frame" then
				if child.Position.X.Scale < 0.5 then
					self._leftPanel = child
				else
					self._rightPanel = child
				end
			end
		end
	end

	-- Distinguish two MapName TextLabels in RightSideHolder by Position.Y.Scale
	-- Lower Y = map title, Higher Y = mode subtitle
	self._headerMapName = nil
	self._headerModeName = nil
	if self._rightSideHolder then
		local mapNames = {}
		for _, child in self._rightSideHolder:GetChildren() do
			if child.Name == "MapName" and child:IsA("TextLabel") then
				table.insert(mapNames, child)
			end
		end
		table.sort(mapNames, function(a, b)
			return a.Position.Y.Scale < b.Position.Y.Scale
		end)
		self._headerMapName = mapNames[1]
		self._headerModeName = mapNames[2]
	end

	-- Clone one of the 5 hardcoded card placeholders as reusable template,
	-- then destroy all 5 placeholders
	self._cardTemplate = nil
	if self._scrollingFrame then
		local firstCard = self._scrollingFrame:FindFirstChild("NewWorldTemp")
		if firstCard then
			self._cardTemplate = firstCard:Clone()
			self._cardTemplate.Name = "CardTemplate"
		end
		for _, name in { "NewWorldTemp", "ExpertTemp", "HardTemp", "MediumTemp", "EasyTemp" } do
			local card = self._scrollingFrame:FindFirstChild(name)
			if card then
				card:Destroy()
			end
		end
	end

	-- Templates from ReplicatedStorage.Assets.Gui
	local assets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Gui")
	self._voteTemplate = assets:FindFirstChild("MapVoteTemplate")
	self._teamTemplate = assets:FindFirstChild("MapTeamTemplate")

	-- State tables
	self._mapTemplates = {}
	self._mapVotersByMap = {}
	self._mapBlipsByMap = {}
	self._selectedMapId = nil
	self._teamEntries = {}
	self._timerRunning = false
	self._votingFinished = false
	self._allVoted = false

	return self
end

--------------------------------------------------------------------------------
-- Public interface (same as old Map module so UIController works unchanged)
--------------------------------------------------------------------------------

function module:setCompetitiveMode(enabled)
	self._competitiveMode = enabled == true
end

function module:setRoundData(data)
	if data.players then
		RoundCreateData.players = data.players
	end
	if data.teams then
		RoundCreateData.teams = data.teams
	end
	if data.gamemodeId then
		RoundCreateData.gamemodeId = data.gamemodeId
	end
	RoundCreateData.matchCreatedTime = data.matchCreatedTime or os.time()
	if data.mapSelectionDuration then
		RoundCreateData.mapSelectionDuration = data.mapSelectionDuration
	end
end

function module:onRemoteVote(userId, mapId)
	if not mapId then
		return
	end
	-- Remove old blip if player changed vote
	for existingMapId, blips in self._mapBlipsByMap do
		if blips[userId] and existingMapId ~= mapId then
			self:_removePlayerBlip(existingMapId, userId)
		end
	end
	self:_addPlayerBlip(mapId, userId)
	self:_recalculateVotes()
end

function module:fireMapVote(mapId)
	self._export:emit("MapVote", mapId)
	return mapId
end

function module:show()
	self._ui.Visible = true

	-- Reparent BlurEffect to camera so it actually blurs the 3D scene
	if self._blur then
		self._blur.Parent = workspace.CurrentCamera
		self._blur.Enabled = true
	end

	self._export:show("Black")
	self:_init()
	self:startTimer()
	return true
end

function module:hide()
	if self._blur then
		self._blur.Enabled = false
	end

	task.delay(0.5, function()
		self._ui.Visible = false
	end)

	self._export:hide("Black")
	return true
end

--------------------------------------------------------------------------------
-- Team color helpers (copied from old Map module)
--------------------------------------------------------------------------------

function module:_getTeamColor(isUserTeam)
	local settingKey = isUserTeam and "TeamColor" or "EnemyColor"
	local colorIndex = PlayerDataTable.get("Gameplay", settingKey)
	local settingConfig = SettingsConfig.getSetting("Gameplay", settingKey)

	if settingConfig and settingConfig.Options and colorIndex then
		local option = settingConfig.Options[colorIndex]
		if option and option.Value then
			return COLOR_MAP[option.Value] or option.Color
		end
	end

	if isUserTeam then
		return COLOR_MAP.Blue
	else
		return COLOR_MAP.Red
	end
end

function module:_getLocalPlayer()
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		return localPlayer.UserId
	end
	return RoundCreateData.players[1]
end

function module:_getPlayerTeam(userId)
	if RoundCreateData.teams.team1 then
		for _, id in RoundCreateData.teams.team1 do
			if id == userId then
				return "team1"
			end
		end
	end
	if RoundCreateData.teams.team2 then
		for _, id in RoundCreateData.teams.team2 do
			if id == userId then
				return "team2"
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function module:_init()
	if self._initialized then
		return
	end
	self._initialized = true
	self:_populateMapCards()
	self:_populateTeamPanels()
	self:_updateHeader(nil)
end

--------------------------------------------------------------------------------
-- Map Cards
--------------------------------------------------------------------------------

function module:_populateMapCards()
	if not self._scrollingFrame or not self._cardTemplate then
		return
	end

	local playerCount = #RoundCreateData.players
	local availableMaps = MapConfig.getMapsForPlayerCount(playerCount)
	if #availableMaps == 0 then
		availableMaps = MapConfig.getAllMaps()
	end

	for i, mapInfo in ipairs(availableMaps) do
		task.delay((i - 1) * 0.08, function()
			self:_createMapCard(mapInfo.id, mapInfo.data, i)
		end)
	end
end

function module:_createMapCard(mapId, mapData, index)
	if self._mapTemplates[mapId] then
		return
	end

	local card = self._cardTemplate:Clone()
	card.Name = "Map_" .. mapId
	card.Visible = true
	card.LayoutOrder = index

	local innerFrame = card:FindFirstChild("Frame")

	-- Start invisible for stagger fade-in (Frame is a CanvasGroup)
	if innerFrame and innerFrame:IsA("CanvasGroup") then
		innerFrame.GroupTransparency = 1
	end

	-- Populate card content
	if innerFrame then
		-- Map name + difficulty text
		local mapSection = innerFrame:FindFirstChild("MapSection")
		if mapSection then
			local holder = mapSection:FindFirstChild("Holder")
			if holder then
				local mapNameLabel = holder:FindFirstChild("MapName")
				if mapNameLabel then
					mapNameLabel.Text = string.upper(mapData.name)
				end
				local difficultyLabel = holder:FindFirstChild("MapDifficulty")
				if difficultyLabel then
					difficultyLabel.Text = "Map Difficulty : " .. string.upper(mapData.difficulty or "UNKNOWN")
				end
			end
		end

		-- Map preview image
		local mapImage = innerFrame:FindFirstChild("MapImage")
		if mapImage and mapData.imageId then
			mapImage.Image = mapData.imageId
		end

		-- Clear pre-filled vote blip placeholders in Vote frame
		local voteFrame = innerFrame:FindFirstChild("Vote")
		if voteFrame then
			for _, child in voteFrame:GetChildren() do
				if child:IsA("CanvasGroup") then
					child:Destroy()
				end
			end
		end
	end

	card.Parent = self._scrollingFrame

	self._mapTemplates[mapId] = {
		template = card,
		mapId = mapId,
		mapData = mapData,
		index = index,
		voteCount = 0,
		votePercent = 0,
	}

	-- Card click → vote
	self._connections:track(card, "Activated", function()
		self:_onMapSelected(mapId)
	end, "mapClick_" .. mapId)

	-- Fade-in animation
	if innerFrame and innerFrame:IsA("CanvasGroup") then
		local fadeTween = TweenService:Create(innerFrame, TWEEN_CARD, {
			GroupTransparency = 0,
		})
		fadeTween:Play()
	end
end

--------------------------------------------------------------------------------
-- Team Panels
--------------------------------------------------------------------------------

function module:_populateTeamPanels()
	if not self._teamTemplate then
		return
	end

	local localUserId = self:_getLocalPlayer()
	local localTeam = self:_getPlayerTeam(localUserId)
	local userTeamName = localTeam or "team1"
	local enemyTeamName = userTeamName == "team1" and "team2" or "team1"

	local userTeamPlayers = RoundCreateData.teams[userTeamName] or {}
	local enemyTeamPlayers = RoundCreateData.teams[enemyTeamName] or {}

	-- Clear existing placeholder ToggleHolders from both panels
	self:_clearTeamPanel(self._leftPanel)
	self:_clearTeamPanel(self._rightPanel)

	-- Left panel = local player's team
	for i, userId in ipairs(userTeamPlayers) do
		task.delay((i - 1) * 0.1, function()
			self:_createTeamEntry(self._leftPanel, userId, true, i)
		end)
	end

	-- Right panel = enemy team
	for i, userId in ipairs(enemyTeamPlayers) do
		task.delay((i - 1) * 0.1, function()
			self:_createTeamEntry(self._rightPanel, userId, false, i)
		end)
	end
end

function module:_clearTeamPanel(panel)
	if not panel then
		return
	end
	for _, child in panel:GetChildren() do
		if child.Name == "ToggleHolder" and child:IsA("Frame") then
			child:Destroy()
		end
	end
end

function module:_createTeamEntry(panel, userId, isUserTeam, index)
	if not panel or not self._teamTemplate then
		return
	end

	local entry = self._teamTemplate:Clone()
	entry.Name = "ToggleHolder"
	entry.LayoutOrder = index
	entry.Visible = true

	-- Apply team color to the color indicator
	local teamColor = self:_getTeamColor(isUserTeam)
	local innerFrame = entry:FindFirstChild("Frame")
	if innerFrame then
		local colorFrame = innerFrame:FindFirstChild("Frame")
		if colorFrame then
			local imgLabel = colorFrame:FindFirstChild("ImageLabel")
			if imgLabel then
				imgLabel.ImageColor3 = teamColor
			end
		end
	end

	entry.Parent = panel

	-- Fetch player info and avatar asynchronously
	task.spawn(function()
		local playerInstance = nil
		for _, p in Players:GetPlayers() do
			if p.UserId == userId then
				playerInstance = p
				break
			end
		end

		local displayName = playerInstance and playerInstance.DisplayName or "Player"
		local userName = playerInstance and playerInstance.Name or "unknown"

		if innerFrame then
			-- Set username labels (first = display name, second = @handle)
			local usernameLabels = {}
			for _, child in innerFrame:GetChildren() do
				if child.Name == "Username" and child:IsA("TextLabel") then
					table.insert(usernameLabels, child)
				end
			end
			if usernameLabels[1] then
				usernameLabels[1].Text = displayName
			end
			if usernameLabels[2] then
				usernameLabels[2].Text = "@" .. userName
			end
		end

		-- Set avatar headshot thumbnail
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420
			)
		end)
		if success and content and innerFrame then
			local playerImage = innerFrame:FindFirstChild("PlayerImage")
			if playerImage then
				playerImage.Image = content
			end
		end
	end)

	self._teamEntries[userId] = {
		entry = entry,
		userId = userId,
		isUserTeam = isUserTeam,
	}
end

--------------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------------

function module:_updateHeader(mapId)
	if not self._rightSideHolder then
		return
	end

	if mapId then
		local mapData = MapConfig[mapId]
		if mapData and self._headerMapName then
			self._headerMapName.Text = string.upper(mapData.name)
		end
	else
		if self._headerMapName then
			self._headerMapName.Text = ""
		end
	end

	if self._headerModeName then
		if self._competitiveMode then
			self._headerModeName.Text = "C O M P E T I T I V E"
		else
			self._headerModeName.Text = "U N R A T E D"
		end
	end
end

--------------------------------------------------------------------------------
-- Voting Flow
--------------------------------------------------------------------------------

function module:_onMapSelected(mapId)
	local localUserId = self:_getLocalPlayer()

	-- Remove old blip if switching vote
	if self._selectedMapId and self._selectedMapId ~= mapId then
		self:_removePlayerBlip(self._selectedMapId, localUserId)
	end

	self._selectedMapId = mapId

	self:_addPlayerBlip(mapId, localUserId)
	self:_updateHeader(mapId)
	self:_recalculateVotes()
	self:fireMapVote(mapId)
end

--------------------------------------------------------------------------------
-- Vote Blips
--------------------------------------------------------------------------------

function module:_getVoteFrame(mapId)
	local data = self._mapTemplates[mapId]
	if not data then
		return nil
	end
	local innerFrame = data.template:FindFirstChild("Frame")
	if not innerFrame then
		return nil
	end
	return innerFrame:FindFirstChild("Vote")
end

function module:_addPlayerBlip(mapId, userId)
	local voteFrame = self:_getVoteFrame(mapId)
	if not voteFrame then
		return nil
	end

	self._mapBlipsByMap[mapId] = self._mapBlipsByMap[mapId] or {}
	self._mapVotersByMap[mapId] = self._mapVotersByMap[mapId] or {}

	-- Already exists
	if self._mapBlipsByMap[mapId][userId] then
		return self._mapBlipsByMap[mapId][userId]
	end

	if not self._voteTemplate then
		return nil
	end

	local blip = self._voteTemplate:Clone()
	blip.Name = "Blip_" .. userId
	blip.Visible = true

	-- Add UIScale for scale-in/out animation
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0
	uiScale.Parent = blip

	blip.Parent = voteFrame

	self._mapBlipsByMap[mapId][userId] = blip
	self._mapVotersByMap[mapId][userId] = true

	-- Make Vote frame visible (it starts hidden)
	voteFrame.Visible = true

	-- Fetch avatar thumbnail
	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420
			)
		end)
		if success and content then
			local playerImage = blip:FindFirstChild("PlayerImage")
			if playerImage then
				playerImage.Image = content
			end
		end
	end)

	-- Scale-in animation
	local scaleTween = TweenService:Create(uiScale, TWEEN_BLIP_SHOW, {
		Scale = 1,
	})
	scaleTween:Play()

	return blip
end

function module:_removePlayerBlip(mapId, userId)
	if not self._mapBlipsByMap[mapId] or not self._mapBlipsByMap[mapId][userId] then
		return false
	end

	local blip = self._mapBlipsByMap[mapId][userId]
	local uiScale = blip:FindFirstChild("UIScale")

	if uiScale then
		local scaleTween = TweenService:Create(uiScale, TWEEN_BLIP_HIDE, {
			Scale = 0,
		})
		scaleTween:Play()
		scaleTween.Completed:Once(function()
			blip:Destroy()
		end)
	else
		blip:Destroy()
	end

	self._mapBlipsByMap[mapId][userId] = nil
	if self._mapVotersByMap[mapId] then
		self._mapVotersByMap[mapId][userId] = nil
	end

	return true
end

function module:_clearAllPlayerBlips()
	for mapId, blips in self._mapBlipsByMap do
		local toRemove = {}
		for userId in blips do
			table.insert(toRemove, userId)
		end
		for _, userId in ipairs(toRemove) do
			self:_removePlayerBlip(mapId, userId)
		end
	end
	table.clear(self._mapBlipsByMap)
	table.clear(self._mapVotersByMap)
end

--------------------------------------------------------------------------------
-- Vote Counting
--------------------------------------------------------------------------------

function module:_recalculateVotes()
	local totalVotesCast = 0
	for _, voters in self._mapVotersByMap do
		for _ in voters do
			totalVotesCast = totalVotesCast + 1
		end
	end

	for mapId, data in self._mapTemplates do
		local voteCount = 0
		if self._mapVotersByMap[mapId] then
			for _ in self._mapVotersByMap[mapId] do
				voteCount = voteCount + 1
			end
		end
		data.voteCount = voteCount
		data.votePercent = totalVotesCast > 0 and (voteCount / totalVotesCast * 100) or 0
	end

	self:_checkAllVoted()
end

function module:_checkAllVoted()
	local players = RoundCreateData.players or {}
	local totalPlayers = #players
	if totalPlayers == 0 then
		totalPlayers = #Players:GetPlayers()
	end
	if totalPlayers == 0 then
		totalPlayers = 1
	end

	local totalVotes = 0
	for _, voters in self._mapVotersByMap do
		for _ in voters do
			totalVotes = totalVotes + 1
		end
	end

	self._allVoted = (totalVotes >= totalPlayers)
end

--------------------------------------------------------------------------------
-- Timer
--------------------------------------------------------------------------------

function module:startTimer()
	if self._timerRunning then
		return
	end
	self._timerRunning = true

	task.spawn(function()
		local matchCreatedTime = RoundCreateData.matchCreatedTime or os.time()
		local duration = RoundCreateData.mapSelectionDuration or 20
		local endTime = matchCreatedTime + duration

		while self._initialized and self._timerRunning do
			local currentTime = os.time()
			local timeLeft = endTime - currentTime
			if timeLeft < 0 then
				timeLeft = 0
			end

			if timeLeft <= 0 then
				self:finishVoting()
				break
			end

			task.wait(0.2)
		end
		self._timerRunning = false
	end)
end

--------------------------------------------------------------------------------
-- Finish Voting
--------------------------------------------------------------------------------

function module:finishVoting()
	if self._votingFinished then
		return
	end
	self._votingFinished = true

	local votesData = {}
	for mapId, voters in self._mapVotersByMap do
		local userIds = {}
		for oduserId in voters do
			table.insert(userIds, oduserId)
		end
		votesData[mapId] = userIds
	end

	local mapPool = {}
	for mapId in self._mapTemplates do
		table.insert(mapPool, mapId)
	end

	local selectedMapId = self:_determineWinningMap(votesData, mapPool)

	self._export:emit("MapVoteComplete", selectedMapId)

	if self._competitiveMode then
		return
	end

	-- Non-competitive: transition to Loadout directly
	self._export:hide("MapVoteV2")

	local loadoutModule = self._export:getModule("Loadout")
	if loadoutModule then
		loadoutModule:setRoundData({
			players = RoundCreateData.players,
			mapId = selectedMapId,
			gamemodeId = RoundCreateData.gamemodeId,
			timeStarted = os.clock(),
		})
	end

	self._export:show("Loadout")
end

function module:_determineWinningMap(votesData, mapPool)
	local maxVotes = 0
	local winningMapId = self._selectedMapId

	for mapId, userIds in votesData do
		local count = #userIds
		if count > maxVotes then
			maxVotes = count
			winningMapId = mapId
		end
	end

	if not winningMapId and #mapPool > 0 then
		winningMapId = mapPool[math.random(1, #mapPool)]
	end

	return winningMapId or "ApexArena"
end

--------------------------------------------------------------------------------
-- Tween helpers
--------------------------------------------------------------------------------

function module:_cancelTweens(key)
	if currentTweens[key] then
		for _, tween in currentTweens[key] do
			tween:Cancel()
		end
		currentTweens[key] = nil
	end
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function module:_clearMapTemplates()
	for _, data in self._mapTemplates do
		if data and data.template then
			data.template:Destroy()
		end
	end
	table.clear(self._mapTemplates)
end

function module:_clearTeamEntries()
	for _, data in self._teamEntries do
		if data and data.entry then
			data.entry:Destroy()
		end
	end
	table.clear(self._teamEntries)
end

function module:_cleanup()
	self._timerRunning = false
	self._votingFinished = false
	self._allVoted = false
	self._competitiveMode = false

	-- Cancel tweens before clearing templates
	self:_cancelTweens("show")
	self:_cancelTweens("hide")
	for mapId in self._mapTemplates do
		self:_cancelTweens("mapClick_" .. mapId)
	end

	self:_clearAllPlayerBlips()
	self:_clearMapTemplates()
	self:_clearTeamEntries()

	self._selectedMapId = nil
	self._initialized = false

	-- Reparent blur back to UI frame
	if self._blur then
		self._blur.Enabled = false
		self._blur.Parent = self._ui
	end
end

return module
