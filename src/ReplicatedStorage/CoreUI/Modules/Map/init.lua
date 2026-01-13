local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Net = require(Locations.Shared.Net.Net)

local Configs = ReplicatedStorage:WaitForChild("Configs")
local MapConfig = require(Configs.MapConfig)
local GamemodeConfig = require(Configs.GamemodeConfig)
local SettingsConfig = require(Configs.SettingsConfig)
local LobbyData = require(Configs.LobbyData)
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
local TweenConfig = require(script.TweenConfig)

local module = {}
module.__index = module

local RoundCreateData = {
	players = {949024059, 9124290782, 1565898941, 204471960},
	teams = {
		team1 = {949024059, 9124290782},
		team2 = {1565898941, 204471960},
	},
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

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections
	self._initialized = false

	self._playerTemplates = {}
	self._userTeamTemplates = {}
	self._enemyTeamTemplates = {}

	self._bottomBar = ui:FindFirstChild("BottomBar")
	self._topBar = ui:FindFirstChild("TopBar")
	self._currentLineUp = ui:FindFirstChild("CurrentLineUp")
	self._lineBg = ui:FindFirstChild("LineBg")
	self._mapHolder = ui:FindFirstChild("MapHolder")
	self._rightSideHolder = ui:FindFirstChild("RightSideHolder")
	self._rewards = ui:FindFirstChild("Rewards")

	self._barHolder = self._currentLineUp and self._currentLineUp:FindFirstChild("BarHolder")

	self._rewardTemplates = {}
	self._mapTemplates = {}
	-- Votes are tracked as:
	-- - _mapVotersByMap[mapId][userId] = true
	-- - _mapBlipsByMap[mapId][userId] = blipInstance
	self._mapVotersByMap = {}
	self._mapBlipsByMap = {}
	self._selectedMapId = nil
	self._rightSideHolderVisible = false

	return self
end

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

function module:_init()
	if self._initialized then
		self:_refreshTeamDisplay()
		return
	end

	self._initialized = true
	self:_populateTeams()
	self:_populateRewards()
	self:_populateMaps()
	self:_setupNetworkListeners()
end

function module:_setupNetworkListeners()
	-- Server broadcasts a full snapshot: { [mapId] = { userId1, userId2, ... }, ... }
	self._connections:add(Net:ConnectClient("MapVoteUpdate", function(votesByMap)
		self:onVotesSnapshot(votesByMap)
	end), "mapVoteNet")
end

function module:fireMapVote(mapId)
	Net:FireServer("MapVoteCast", mapId)
end

function module:_getLocalPlayer()
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		return localPlayer.UserId
	end

	for _, player in Players:GetPlayers() do
		return player.UserId
	end

	return RoundCreateData.players[1]
end

function module:_getPlayerTeam(userId)
	for _, id in RoundCreateData.teams.team1 do
		if id == userId then
			return "team1"
		end
	end

	for _, id in RoundCreateData.teams.team2 do
		if id == userId then
			return "team2"
		end
	end

	return nil
end

function module:_isUserTeam(teamName)
	local localUserId = self:_getLocalPlayer()
	local localTeam = self:_getPlayerTeam(localUserId)
	return teamName == localTeam
end

function module:_populateTeams()
	task.spawn(function()
		local localUserId = self:_getLocalPlayer()
		local localTeam = self:_getPlayerTeam(localUserId)

		local userTeamName = localTeam or "team1"
		local enemyTeamName = userTeamName == "team1" and "team2" or "team1"

		local userTeamHolder = self._currentLineUp and self._currentLineUp:FindFirstChild("UsersTeamHolder")
		local enemyTeamHolder = self._currentLineUp and self._currentLineUp:FindFirstChild("EnemyTeamHolder")

		local userTeamPlayers = RoundCreateData.teams[userTeamName] or {}
		local enemyTeamPlayers = RoundCreateData.teams[enemyTeamName] or {}

		local userTemplateSource = self:_getTemplateSource(userTeamHolder)
		local enemyTemplateSource = self:_getTemplateSource(enemyTeamHolder)

		if self._barHolder then
			self._barHolder.GroupTransparency = 1
		end

		local allPlayers = {}

		for i, oduserId in ipairs(userTeamPlayers) do
			table.insert(allPlayers, {
				userId = oduserId,
				holder = userTeamHolder,
				templateSource = userTemplateSource,
				isUserTeam = true,
				index = i,
			})
		end

		for i, oduserId in ipairs(enemyTeamPlayers) do
			table.insert(allPlayers, {
				userId = oduserId,
				holder = enemyTeamHolder,
				templateSource = enemyTemplateSource,
				isUserTeam = false,
				index = i,
			})
		end

		for globalIndex, playerInfo in ipairs(allPlayers) do
			if playerInfo.holder and playerInfo.templateSource then
				self:_createPlayerTemplate(
					playerInfo.holder,
					playerInfo.templateSource,
					playerInfo.userId,
					playerInfo.isUserTeam,
					playerInfo.index
				)
			end

			if globalIndex < #allPlayers then
				task.wait(TweenConfig.getDelay("PlayerTemplateStagger"))
			end
		end

		if self._barHolder then
			local barFadeTween = TweenService:Create(self._barHolder, TweenConfig.get("PlayerTemplate", "show"), {
				GroupTransparency = 0,
			})
			barFadeTween:Play()
		end
	end)
end

function module:_getTemplateSource(holder)
	if not holder then
		return nil
	end

	local templateFolder = holder:FindFirstChild("Template")
	if not templateFolder then
		return nil
	end

	return templateFolder:FindFirstChild("TeamTemp1") or templateFolder:FindFirstChild("Template")
end

function module:_createPlayerTemplate(holder, templateSource, userId, isUserTeam, index)
	if self._playerTemplates[userId] then
		return self._playerTemplates[userId].template
	end

	local template = templateSource:Clone()
	template.Name = "Player_" .. userId
	template.Visible = true
	template.LayoutOrder = index

	local canvasGroup = template:FindFirstChild("CanvasGroup")
	if canvasGroup then
		canvasGroup.Position = UDim2.fromScale(-1, 0.5)
	end

	template.Parent = holder

	local teamColor = self:_getTeamColor(isUserTeam)
	self:_applyTeamColors(template, teamColor)

	self._playerTemplates[userId] = {
		template = template,
		userId = userId,
		teamIndex = index,
		mapPicked = nil,
		isUserTeam = isUserTeam,
	}

	if isUserTeam then
		self._userTeamTemplates[userId] = self._playerTemplates[userId]
	else
		self._enemyTeamTemplates[userId] = self._playerTemplates[userId]
	end

	local playerData = LobbyData.getPlayer(userId)
	local wins = playerData and playerData.wins or 0
	local streak = playerData and playerData.streak or 0

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)

		if success and content and canvasGroup then
			local playerImage = canvasGroup:FindFirstChild("PlayerImage", true)
				or canvasGroup:FindFirstChild("Image", true)
				or canvasGroup:FindFirstChildWhichIsA("ImageLabel", true)
			if playerImage then
				playerImage.Image = content
			end
		end
	end)

	local mapNameLabel = canvasGroup and canvasGroup:FindFirstChild("MapName")
	if mapNameLabel then
		mapNameLabel.Visible = false
		mapNameLabel.Text = ""
	end

	if canvasGroup then
		local dataTemplate = canvasGroup:FindFirstChild("Template")
		if dataTemplate then
			local dataHolder = dataTemplate:FindFirstChild("Data")
			if dataHolder then
				local children = dataHolder:GetChildren()
				for _, child in ipairs(children) do
					if child:IsA("Frame") then
						local textLabel = child:FindFirstChild("TextLabel")
						if textLabel then
							local imageLabel = child:FindFirstChild("ImageLabel")
							if imageLabel and imageLabel.Image:find("105873826321471") then
								textLabel.Text = tostring(wins)
							elseif imageLabel and imageLabel.Image:find("82840964166861") then
								textLabel.Text = tostring(streak)
							end
						end
					end
				end
			end
		end
	end

	if canvasGroup then
		local posTween = TweenService:Create(canvasGroup, TweenConfig.get("PlayerTemplate", "show"), {
			Position = UDim2.fromScale(0, 0.5),
		})
		posTween:Play()
	end

	return template
end

function module:_applyTeamColors(template, color)
	local canvasGroup = template:FindFirstChild("CanvasGroup")
	if not canvasGroup then
		return
	end

	local glowDisplay = canvasGroup:FindFirstChild("GlowDisplay")
	if glowDisplay then
		glowDisplay.GroupColor3 = color

		local bottomBar = glowDisplay:FindFirstChild("BottomBar")
		if bottomBar then
			bottomBar.BackgroundColor3 = color
		end

		local glow = glowDisplay:FindFirstChild("Glow")
		if glow then
			glow.BackgroundColor3 = color
		end
	end
end

function module:setMapPicked(userId, mapId)
	local data = self._playerTemplates[userId]
	if not data then
		return false
	end

	data.mapPicked = mapId

	local canvasGroup = data.template:FindFirstChild("CanvasGroup")
	if not canvasGroup then
		return false
	end

	local mapNameLabel = canvasGroup:FindFirstChild("MapName")
	if not mapNameLabel then
		return false
	end

	if mapId and mapId ~= "" then
		local mapData = MapConfig[mapId]
		local displayName = mapData and mapData.name or mapId

		mapNameLabel.Text = string.upper(displayName)
		mapNameLabel.Visible = true
	else
		mapNameLabel.Text = ""
		mapNameLabel.Visible = false
	end

	return true
end

function module:getMapPicked(userId)
	local data = self._playerTemplates[userId]
	if not data then
		return nil
	end

	return data.mapPicked
end

function module:_refreshTeamDisplay()
	for userId, data in self._playerTemplates do
		local teamColor = self:_getTeamColor(data.isUserTeam)
		self:_applyTeamColors(data.template, teamColor)

		if data.mapPicked then
			self:setMapPicked(userId, data.mapPicked)
		end
	end
end

function module:_populateRewards()
	if not self._rewards then
		return
	end

	local gamemodeData = self:getGamemodeData()
	if not gamemodeData or not gamemodeData.rewards then
		return
	end

	local rewardsPreview = self._rewards:FindFirstChild("RewardsPreview")
	if not rewardsPreview then
		return
	end

	local rewardHolder = rewardsPreview:FindFirstChild("RewardHolder")
	if not rewardHolder then
		return
	end

	local templateSource = rewardHolder:FindFirstChild("RewardTemp")
	if not templateSource then
		return
	end

	local rewardCount = self._rewards:FindFirstChild("RewardCount")
	if rewardCount then
		local holder = rewardCount:FindFirstChild("Holder")
		if holder then
			local countLabel = holder:FindFirstChild("Count")
			if countLabel then
				countLabel.Text = "0/" .. #gamemodeData.rewards
			end
		end
	end

	for i, rewardData in ipairs(gamemodeData.rewards) do
		task.delay((i - 1) * TweenConfig.getDelay("RewardTemplateStagger"), function()
			self:_createRewardTemplate(rewardHolder, templateSource, rewardData, i)
		end)
	end
end

function module:_createRewardTemplate(holder, templateSource, rewardData, index)
	local template = templateSource:Clone()
	template.Name = "Reward_" .. index
	template.Visible = true
	template.LayoutOrder = index

	local holderFrame = template:FindFirstChild("Holder")
	if holderFrame then
		holderFrame.GroupTransparency = 1

		local textLabel = holderFrame:FindFirstChild("Text")
		if textLabel then
			textLabel.Text = string.upper(rewardData.name)
		end

		local imageLabel = holderFrame:FindFirstChild("Image")
		if imageLabel then
			imageLabel.Image = rewardData.imageId or ""
		end
	end

	template.Parent = holder

	self._rewardTemplates[index] = {
		template = template,
		rewardData = rewardData,
		index = index,
	}

	if holderFrame then
		local originalPos = UDim2.fromScale(0.5, 0.5)
		holderFrame.Position = UDim2.new(0.5, 0, 0.5, 40)

		local fadeTween = TweenService:Create(holderFrame, TweenConfig.get("RewardTemplate", "show"), {
			GroupTransparency = 0,
		})
		local slideTween = TweenService:Create(holderFrame, TweenConfig.get("RewardTemplate", "show"), {
			Position = originalPos,
		})

		fadeTween:Play()
		slideTween:Play()
	end

	return template
end

function module:_clearRewardTemplates()
	for _, data in self._rewardTemplates do
		if data and data.template then
			data.template:Destroy()
		end
	end
	table.clear(self._rewardTemplates)
end

function module:_populateMaps()
	if not self._mapHolder then
		return
	end

	local scrollingFrame = self._mapHolder:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then
		return
	end

	local mapTemplateFolder = scrollingFrame:FindFirstChild("MapTemplate")
	if not mapTemplateFolder then
		return
	end

	local templateSource = mapTemplateFolder:FindFirstChild("MapTemp1")
	if not templateSource then
		return
	end

	local playerCount = #RoundCreateData.players
	local availableMaps = MapConfig.getMapsForPlayerCount(playerCount)

	if #availableMaps == 0 then
		availableMaps = MapConfig.getAllMaps()
	end

	task.delay(TweenConfig.getDelay("MapTemplateStart"), function()
		for i, mapInfo in ipairs(availableMaps) do
			self:_createMapTemplate(scrollingFrame, templateSource, mapInfo.id, mapInfo.data, i)

			if i < #availableMaps then
				task.wait(TweenConfig.getDelay("MapTemplateStagger"))
			end
		end
	end)
end

function module:_createMapTemplate(holder, templateSource, mapId, mapData, index)
	if self._mapTemplates[mapId] then
		return self._mapTemplates[mapId].template
	end

	local template = templateSource:Clone()
	template.Name = "Map_" .. mapId
	template.Visible = true
	template.LayoutOrder = index

	local uiScale = template:FindFirstChild("UIScale")
	if uiScale then
		uiScale.Scale = 0
	end

	template.Parent = holder

	self._mapTemplates[mapId] = {
		template = template,
		mapId = mapId,
		mapData = mapData,
		index = index,
		voteCount = 0,
		votePercent = 0,
	}

	local frame = template:FindFirstChild("Frame")
	if frame then
		local frameHolder = frame:FindFirstChild("FrameHolder")
		if frameHolder then
			local holderCanvas = frameHolder:FindFirstChild("Holder")
			if holderCanvas then
				local mapNameLabel = holderCanvas:FindFirstChild("MapName")
				if mapNameLabel then
					mapNameLabel.Text = string.upper(mapData.name)
				end

				local mapHolder = holderCanvas:FindFirstChild("MapHolder")
				if mapHolder then
					local mapImage = mapHolder:FindFirstChild("MapImage")
					if mapImage and mapData.imageId then
						mapImage.Image = mapData.imageId
					end
				end
			end
		end
	end

	if uiScale then
		local scaleTween = TweenService:Create(uiScale, TweenConfig.get("MapTemplate", "show"), {
			Scale = 1.0,
		})
		scaleTween:Play()
	end

	self:_setupMapHover(template, mapId)
	self:_setupMapClick(template, mapId)

	return template
end

function module:_setupMapHover(template, mapId)
	local groupName = "mapHover_" .. mapId
	local isHovering = false

	local uiScale = template:FindFirstChild("UIScale")
	if not uiScale then
		return
	end

	local function onHoverStart()
		if isHovering then
			return
		end
		if self._selectedMapId == mapId then
			return
		end
		isHovering = true

		self:_cancelTweens("mapHover_" .. mapId)

		local hoverTween = TweenService:Create(uiScale, TweenConfig.get("MapTemplate", "hover"), {
			Scale = 1.2,
		})
		hoverTween:Play()

		currentTweens["mapHover_" .. mapId] = {hoverTween}
	end

	local function onHoverEnd()
		if not isHovering then
			return
		end
		isHovering = false

		self:_cancelTweens("mapHover_" .. mapId)

		local targetScale = (self._selectedMapId == mapId) and 1.35 or 1.0
		local unhoverTween = TweenService:Create(uiScale, TweenConfig.get("MapTemplate", "unhover"), {
			Scale = targetScale,
		})
		unhoverTween:Play()

		currentTweens["mapHover_" .. mapId] = {unhoverTween}
	end

	self._connections:track(template, "MouseEnter", onHoverStart, groupName)
	self._connections:track(template, "MouseLeave", onHoverEnd, groupName)
	self._connections:track(template, "SelectionGained", onHoverStart, groupName)
	self._connections:track(template, "SelectionLost", onHoverEnd, groupName)
end

function module:_setupMapClick(template, mapId)
	local groupName = "mapClick_" .. mapId

	local frame = template:FindFirstChild("Frame")
	if not frame then
		return
	end

	local frameHolder = frame:FindFirstChild("FrameHolder")
	if not frameHolder then
		return
	end

	local button = frameHolder:FindFirstChild("Button")
	if not button then
		local holder = frameHolder:FindFirstChild("Holder")
		if holder then
			button = holder:FindFirstChild("Button")
		end
	end

	if not button then
		return
	end

	self._connections:track(button, "Activated", function()
		self:_onMapSelected(mapId)
	end, groupName)
end

function module:_onMapSelected(mapId)
	local localUserId = self:_getLocalPlayer()

	if self._selectedMapId and self._selectedMapId ~= mapId then
		self:_removePlayerBlip(self._selectedMapId, localUserId)
	end

	self._selectedMapId = mapId

	self:selectMap(mapId)
	self:_addPlayerBlip(mapId, localUserId)
	self:_showRightSideHolder(mapId)
	self:_recalculateVotes()

	self:fireMapVote(mapId)
end

function module:_getVoteHolder(mapId)
	local data = self._mapTemplates[mapId]
	if not data then
		return nil
	end

	local frame = data.template:FindFirstChild("Frame")
	if not frame then
		return nil
	end

	return frame:FindFirstChild("VoteHolder")
end

function module:_getPlayerBlipTemplate(voteHolder)
	if not voteHolder then
		return nil
	end

	-- Try finding template directly in VoteHolder
	local direct = voteHolder:FindFirstChild("PlayerTemplate") 
		or voteHolder:FindFirstChild("Template")
		or voteHolder:FindFirstChild("PlayerTemp1")

	if direct and direct:IsA("GuiObject") then
		return direct
	end

	-- Try finding in a container folder
	local templateFolder = voteHolder:FindFirstChild("PlayerTemplate") or voteHolder:FindFirstChild("Templates")
	if templateFolder then
		return templateFolder:FindFirstChild("PlayerTemp1") 
			or templateFolder:FindFirstChild("Template") 
			or templateFolder:FindFirstChild("PlayerTemplate")
	end

	-- Fallback: Create a default template if none found
	local fallback = Instance.new("Frame")
	fallback.Name = "Template"
	fallback.Size = UDim2.fromOffset(40, 40)
	fallback.BackgroundTransparency = 1
	
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "UIScale"
	uiScale.Parent = fallback
	
	local img = Instance.new("ImageLabel")
	img.Name = "PlayerImage"
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Parent = fallback
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = img
	
	return fallback
end

function module:_addPlayerBlip(mapId, userId)
	local voteHolder = self:_getVoteHolder(mapId)
	if not voteHolder then
		return nil
	end

	self._mapBlipsByMap[mapId] = self._mapBlipsByMap[mapId] or {}
	self._mapVotersByMap[mapId] = self._mapVotersByMap[mapId] or {}

	local existingBlip = voteHolder:FindFirstChild("Blip_" .. userId)
	if existingBlip then
		self._mapBlipsByMap[mapId][userId] = existingBlip
		self._mapVotersByMap[mapId][userId] = true
		return existingBlip
	end

	local templateSource = self:_getPlayerBlipTemplate(voteHolder)
	if not templateSource then
		return nil
	end

	local blip = templateSource:Clone()
	blip.Name = "Blip_" .. userId
	blip.Visible = true

	local uiScale = blip:FindFirstChild("UIScale")
	if uiScale then
		uiScale.Scale = 0
	end

	blip.Parent = voteHolder

	self._mapBlipsByMap[mapId][userId] = blip
	self._mapVotersByMap[mapId][userId] = true

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)

		if success and content then
			local playerImage = blip:FindFirstChild("PlayerImage")
			if playerImage then
				playerImage.Image = content
			end
		end
	end)

	if uiScale then
		local scaleTween = TweenService:Create(uiScale, TweenConfig.get("PlayerBlip", "show"), {
			Scale = 1,
		})
		scaleTween:Play()
	end

	return blip
end

function module:_removePlayerBlip(mapId, userId)
	if not self._mapBlipsByMap[mapId] or not self._mapBlipsByMap[mapId][userId] then
		return false
	end

	local blip = self._mapBlipsByMap[mapId][userId]
	local uiScale = blip:FindFirstChild("UIScale")

	if uiScale then
		local scaleTween = TweenService:Create(uiScale, TweenConfig.get("PlayerBlip", "hide"), {
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

function module:_showRightSideHolder(mapId)
	if not self._rightSideHolder then
		return
	end

	local mapData = MapConfig[mapId]
	if not mapData then
		return
	end

	local mapNameLabel = self._rightSideHolder:FindFirstChild("MapName")
	if mapNameLabel then
		mapNameLabel.Text = string.upper(mapData.name)
	end

	local description = self._rightSideHolder:FindFirstChild("Description")
	if description then
		local descText = description:FindFirstChild("TextLabel") or description:FindFirstChildOfClass("TextLabel")
		if descText then
			descText.Text = mapData.description or ""
		end
	end

	local madeByHolder = self._rightSideHolder:FindFirstChild("MadeByHolder")
	if madeByHolder then
		local holder = madeByHolder:FindFirstChild("Holder")
		if holder then
			local textLabel = holder:FindFirstChild("Text") or holder:FindFirstChild("TextLabel")
			if textLabel then
				textLabel.Text = "Made By " .. (mapData.creator or "Unknown")
			end
		end
	end

	self:_cancelTweens("rightSideHolder")

	local hiddenPos = TweenConfig.getPosition("RightSideHolder", "hidden")
	local shownPos = TweenConfig.getPosition("RightSideHolder", "shown")

	self._rightSideHolder.Position = hiddenPos
	self._rightSideHolder.GroupTransparency = 1

	local posTween = TweenService:Create(self._rightSideHolder, TweenConfig.get("RightSideHolder", "show"), {
		Position = shownPos,
	})
	local fadeTween = TweenService:Create(self._rightSideHolder, TweenConfig.get("RightSideHolder", "fade"), {
		GroupTransparency = 0,
	})

	posTween:Play()
	fadeTween:Play()

	self._rightSideHolderVisible = true
	currentTweens["rightSideHolder"] = {posTween, fadeTween}
end

function module:_hideRightSideHolder()
	if not self._rightSideHolder or not self._rightSideHolderVisible then
		return
	end

	self._rightSideHolderVisible = false

	self:_cancelTweens("rightSideHolder")

	local hiddenPos = TweenConfig.getPosition("RightSideHolder", "hidden")

	local posTween = TweenService:Create(self._rightSideHolder, TweenConfig.get("RightSideHolder", "hide"), {
		Position = hiddenPos,
	})
	local fadeTween = TweenService:Create(self._rightSideHolder, TweenConfig.get("RightSideHolder", "hide"), {
		GroupTransparency = 1,
	})

	posTween:Play()
	fadeTween:Play()

	currentTweens["rightSideHolder"] = {posTween, fadeTween}
end

function module:_recalculateVotes()
	local totalVotesCast = 0
	
	-- First pass: count total votes
	for _, voters in self._mapVotersByMap do
		for _ in voters do
			totalVotesCast = totalVotesCast + 1
		end
	end

	-- Second pass: update percentages
	for mapId in self._mapTemplates do
		local voteCount = 0
		if self._mapVotersByMap[mapId] then
			for _ in self._mapVotersByMap[mapId] do
				voteCount = voteCount + 1
			end
		end

		local votePercent = 0
		if totalVotesCast > 0 then
			votePercent = (voteCount / totalVotesCast) * 100
		end
		
		self:updateMapVote(mapId, voteCount, votePercent, totalVotesCast)
	end
	
	self:_checkAllVoted()
end

function module:onVotesSnapshot(votesByMap)
	if typeof(votesByMap) ~= "table" then
		return
	end

	-- Apply per-map updates; also clear maps not present in snapshot.
	for mapId in self._mapTemplates do
		local votes = votesByMap[mapId]
		if typeof(votes) ~= "table" then
			votes = {}
		end
		self:onVoteUpdate(mapId, votes)
	end

	-- If server sent votes for a map not in our UI, ignore.
end

function module:onVoteUpdate(mapId, votes)
	if typeof(mapId) ~= "string" or mapId == "" then
		return
	end
	if typeof(votes) ~= "table" then
		votes = {}
	end

	self._mapVotersByMap[mapId] = self._mapVotersByMap[mapId] or {}
	self._mapBlipsByMap[mapId] = self._mapBlipsByMap[mapId] or {}

	local desired = {}
	for _, userId in ipairs(votes) do
		if typeof(userId) == "number" then
			desired[userId] = true
		end
	end

	-- Add new voters
	for userId in desired do
		if not self._mapVotersByMap[mapId][userId] then
			self:_addPlayerBlip(mapId, userId)
		end
	end

	-- Remove voters who are no longer on this map
	local toRemove = {}
	for userId in self._mapVotersByMap[mapId] do
		if not desired[userId] then
			table.insert(toRemove, userId)
		end
	end
	for _, userId in ipairs(toRemove) do
		self:_removePlayerBlip(mapId, userId)
	end

	self._mapVotersByMap[mapId] = desired
	self:_recalculateVotes()
end

function module:updateMapVote(mapId, voteCount, votePercent, totalVotesCast)
	local data = self._mapTemplates[mapId]
	if not data then
		return false
	end

	data.voteCount = voteCount
	data.votePercent = votePercent

	local frame = data.template:FindFirstChild("Frame")
	if frame then
		local frameHolder = frame:FindFirstChild("FrameHolder")
		if frameHolder then
			local holderCanvas = frameHolder:FindFirstChild("Holder")
			if holderCanvas then
				local mapNameLabel = holderCanvas:FindFirstChild("MapName")
				if mapNameLabel then
					local displayName = data.mapData.name
					if (totalVotesCast or 0) > 0 then
						mapNameLabel.Text = string.upper(displayName) .. " - " .. math.floor(votePercent) .. "%"
					else
						mapNameLabel.Text = string.upper(displayName)
					end
				end
			end
		end
	end

	return true
end

function module:selectMap(mapId)
	for id, data in self._mapTemplates do
		local uiScale = data.template:FindFirstChild("UIScale")
		if uiScale then
			local targetScale = (id == mapId) and 1.35 or 1.0
			local scaleTween = TweenService:Create(uiScale, TweenConfig.get("MapTemplate", "select"), {
				Scale = targetScale,
			})
			scaleTween:Play()
		end

		local frame = data.template:FindFirstChild("Frame")
		if frame then
			local frameHolder = frame:FindFirstChild("FrameHolder")
			if frameHolder then
				local button = frameHolder:FindFirstChild("Button") or frameHolder:FindFirstChild("ImageButton")
				if not button then
					local holder = frameHolder:FindFirstChild("Holder")
					if holder then
						button = holder:FindFirstChild("Button") or holder:FindFirstChild("ImageButton")
					end
				end

				if button then
					button.Active = (id ~= mapId)
				end
			end
		end
	end
end

function module:_clearMapTemplates()
	for _, data in self._mapTemplates do
		if data and data.template then
			data.template:Destroy()
		end
	end
	table.clear(self._mapTemplates)
end

function module:_cancelTweens(key)
	if currentTweens[key] then
		for _, tween in currentTweens[key] do
			tween:Cancel()
		end
		currentTweens[key] = nil
	end
end

function module:_animateShow()
	self._export:show("Black")

	self:_cancelTweens("show")
	self:_cancelTweens("hide")

	local tweens = {}

	if self._topBar then
		local hiddenPos = TweenConfig.getPosition("TopBar", "hidden")
		local shownPos = TweenConfig.getPosition("TopBar", "shown")

		self._topBar.Position = hiddenPos
		self._topBar.GroupTransparency = 1

		local topPosTween = TweenService:Create(self._topBar, TweenConfig.get("TopBar", "show"), {
			Position = shownPos,
		})
		local topFadeTween = TweenService:Create(self._topBar, TweenConfig.get("TopBar", "fade"), {
			GroupTransparency = 0,
		})

		topPosTween:Play()
		topFadeTween:Play()
		table.insert(tweens, topPosTween)
		table.insert(tweens, topFadeTween)
	end

	task.delay(TweenConfig.getDelay("BottomBar"), function()
		if self._bottomBar then
			local hiddenPos = TweenConfig.getPosition("BottomBar", "hidden")
			local shownPos = TweenConfig.getPosition("BottomBar", "shown")

			self._bottomBar.Position = hiddenPos
			self._bottomBar.GroupTransparency = 1

			local bottomPosTween = TweenService:Create(self._bottomBar, TweenConfig.get("BottomBar", "show"), {
				Position = shownPos,
			})
			local bottomFadeTween = TweenService:Create(self._bottomBar, TweenConfig.get("BottomBar", "fade"), {
				GroupTransparency = 0,
			})

			bottomPosTween:Play()
			bottomFadeTween:Play()
			table.insert(tweens, bottomPosTween)
			table.insert(tweens, bottomFadeTween)
		end
	end)

	task.delay(TweenConfig.getDelay("CurrentLineUp"), function()
		if self._currentLineUp then
			local hiddenPos = TweenConfig.getPosition("CurrentLineUp", "hidden")
			local shownPos = TweenConfig.getPosition("CurrentLineUp", "shown")

			self._currentLineUp.Position = hiddenPos
			self._currentLineUp.GroupTransparency = 1

			local lineUpPosTween = TweenService:Create(self._currentLineUp, TweenConfig.get("CurrentLineUp", "show"), {
				Position = shownPos,
			})
			local lineUpFadeTween = TweenService:Create(self._currentLineUp, TweenConfig.get("CurrentLineUp", "fade"), {
				GroupTransparency = 0,
			})

			lineUpPosTween:Play()
			lineUpFadeTween:Play()
			table.insert(tweens, lineUpPosTween)
			table.insert(tweens, lineUpFadeTween)

			lineUpFadeTween.Completed:Once(function()
				if self._lineBg then
					local lineBgOriginals = self._export:getOriginals("LineBg")
					local originalSize = lineBgOriginals and lineBgOriginals.Size or self._lineBg.Size

					self._lineBg.Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset, 0, 0)
					self._lineBg.GroupTransparency = 0

					local lineBgTween = TweenService:Create(self._lineBg, TweenConfig.get("LineBg", "show"), {
						Size = originalSize,
					})
					lineBgTween:Play()
					table.insert(tweens, lineBgTween)
				end
			end)
		end
	end)

	task.delay(TweenConfig.getDelay("Rewards"), function()
		if self._rewards then
			local hiddenPos = TweenConfig.getPosition("Rewards", "hidden")
			local shownPos = TweenConfig.getPosition("Rewards", "shown")

			self._rewards.Position = hiddenPos
			self._rewards.GroupTransparency = 1

			local rewardsPosTween = TweenService:Create(self._rewards, TweenConfig.get("Rewards", "show"), {
				Position = shownPos,
			})
			local rewardsFadeTween = TweenService:Create(self._rewards, TweenConfig.get("Rewards", "fade"), {
				GroupTransparency = 0,
			})

			rewardsPosTween:Play()
			rewardsFadeTween:Play()
			table.insert(tweens, rewardsPosTween)
			table.insert(tweens, rewardsFadeTween)
		end
	end)

	task.delay(TweenConfig.getDelay("MapHolder"), function()
		if self._mapHolder then
			local hiddenPos = TweenConfig.getPosition("MapHolder", "hidden")
			local shownPos = TweenConfig.getPosition("MapHolder", "shown")

			self._mapHolder.Position = hiddenPos
			self._mapHolder.GroupTransparency = 1

			local mapHolderPosTween = TweenService:Create(self._mapHolder, TweenConfig.get("MapHolder", "show"), {
				Position = shownPos,
			})
			local mapHolderFadeTween = TweenService:Create(self._mapHolder, TweenConfig.get("MapHolder", "fade"), {
				GroupTransparency = 0,
			})

			mapHolderPosTween:Play()
			mapHolderFadeTween:Play()
			table.insert(tweens, mapHolderPosTween)
			table.insert(tweens, mapHolderFadeTween)
		end
	end)

	currentTweens["show"] = tweens
end

function module:_animateHide()
	self:_cancelTweens("show")
	self:_cancelTweens("hide")

	local tweens = {}

	self:_hideRightSideHolder()

	if self._mapHolder then
		local hiddenPos = TweenConfig.getPosition("MapHolder", "hidden")

		local mapHolderPosTween = TweenService:Create(self._mapHolder, TweenConfig.get("MapHolder", "hide"), {
			Position = hiddenPos,
		})
		local mapHolderFadeTween = TweenService:Create(self._mapHolder, TweenConfig.get("MapHolder", "hide"), {
			GroupTransparency = 1,
		})

		mapHolderPosTween:Play()
		mapHolderFadeTween:Play()
		table.insert(tweens, mapHolderPosTween)
		table.insert(tweens, mapHolderFadeTween)
	end

	if self._rewards then
		local hiddenPos = TweenConfig.getPosition("Rewards", "hidden")

		local rewardsPosTween = TweenService:Create(self._rewards, TweenConfig.get("Rewards", "hide"), {
			Position = hiddenPos,
		})
		local rewardsFadeTween = TweenService:Create(self._rewards, TweenConfig.get("Rewards", "hide"), {
			GroupTransparency = 1,
		})

		rewardsPosTween:Play()
		rewardsFadeTween:Play()
		table.insert(tweens, rewardsPosTween)
		table.insert(tweens, rewardsFadeTween)
	end

	if self._lineBg then
		local lineBgTween = TweenService:Create(self._lineBg, TweenConfig.get("LineBg", "hide"), {
			GroupTransparency = 1,
		})
		lineBgTween:Play()
		table.insert(tweens, lineBgTween)
	end

	if self._currentLineUp then
		local hiddenPos = TweenConfig.getPosition("CurrentLineUp", "hidden")

		local lineUpPosTween = TweenService:Create(self._currentLineUp, TweenConfig.get("CurrentLineUp", "hide"), {
			Position = hiddenPos,
		})
		local lineUpFadeTween = TweenService:Create(self._currentLineUp, TweenConfig.get("CurrentLineUp", "hide"), {
			GroupTransparency = 1,
		})

		lineUpPosTween:Play()
		lineUpFadeTween:Play()
		table.insert(tweens, lineUpPosTween)
		table.insert(tweens, lineUpFadeTween)
	end

	task.delay(TweenConfig.getDelay("HideBottomBar"), function()
		if self._bottomBar then
			local hiddenPos = TweenConfig.getPosition("BottomBar", "hidden")

			local bottomPosTween = TweenService:Create(self._bottomBar, TweenConfig.get("BottomBar", "hide"), {
				Position = hiddenPos,
			})
			local bottomFadeTween = TweenService:Create(self._bottomBar, TweenConfig.get("BottomBar", "hide"), {
				GroupTransparency = 1,
			})

			bottomPosTween:Play()
			bottomFadeTween:Play()
			table.insert(tweens, bottomPosTween)
			table.insert(tweens, bottomFadeTween)
		end
	end)

	task.delay(TweenConfig.getDelay("HideTopBar"), function()
		if self._topBar then
			local hiddenPos = TweenConfig.getPosition("TopBar", "hidden")

			local topPosTween = TweenService:Create(self._topBar, TweenConfig.get("TopBar", "hide"), {
				Position = hiddenPos,
			})
			local topFadeTween = TweenService:Create(self._topBar, TweenConfig.get("TopBar", "hide"), {
				GroupTransparency = 1,
			})

			topPosTween:Play()
			topFadeTween:Play()
			table.insert(tweens, topPosTween)
			table.insert(tweens, topFadeTween)
		end
	end)

	currentTweens["hide"] = tweens

	self._export:hide("Black")
end

function module:_resetToOriginals()
	self._export:resetToOriginals("TopBar")
	self._export:resetToOriginals("BottomBar")
	self._export:resetToOriginals("CurrentLineUp")
	self._export:resetToOriginals("LineBg")
	self._export:resetToOriginals("Rewards")
	self._export:resetToOriginals("MapHolder")
	self._export:resetToOriginals("RightSideHolder")
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
end

function module:getRoundData()
	return RoundCreateData
end

function module:getGamemodeData()
	return GamemodeConfig[RoundCreateData.gamemodeId]
end

function module:show()
	self._ui.Visible = true
	self:_animateShow()
	self:_init()
	self:startTimer()
	return true
end

function module:hide()
	self:_animateHide()

	task.delay(0.6, function()
		self._ui.Visible = false
	end)

	return true
end

function module:_checkAllVoted()
	local players = RoundCreateData.players or {}
	local totalPlayers = #players
	if totalPlayers == 0 then
		totalPlayers = #game:GetService("Players"):GetPlayers()
	end
	if totalPlayers == 0 then totalPlayers = 1 end

	local totalVotes = 0
	for _, voters in self._mapVotersByMap do
		for _ in voters do
			totalVotes = totalVotes + 1
		end
	end

	self._allVoted = (totalVotes >= totalPlayers)
end

function module:startTimer()
	if self._timerRunning then return end
	self._timerRunning = true

	task.spawn(function()
		local timeTextLabel = nil
		-- Look for TimeRemaining in Rewards holder
		if self._rewards then
			local timeRemaining = self._rewards:FindFirstChild("TimeRemaining")
			if timeRemaining then
				local holder = timeRemaining:FindFirstChild("Holder")
				if holder then
					timeTextLabel = holder:FindFirstChild("TimeText")
				end
			end
		end

		local matchCreatedTime = RoundCreateData.matchCreatedTime or os.time()
		local duration = 5
		local endTime = matchCreatedTime + duration

		while self._initialized and self._timerRunning do
			local currentTime = os.time()
			local timeLeft = endTime - currentTime

			-- For now: keep voting timer fixed at 30s (no early shorten).

			if timeLeft < 0 then timeLeft = 0 end

			if timeTextLabel then
				if timeLeft >= 60 then
					local mins = math.floor(timeLeft / 60)
					local secs = timeLeft % 60
					timeTextLabel.Text = string.format("Remaining: %dm %ds", mins, secs)
				else
					timeTextLabel.Text = string.format("Remaining: %ds", timeLeft)
				end
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

function module:finishVoting()
	if self._votingFinished then return end
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

	self:fireVotingFinished(votesData, mapPool)

	self._export:hide("Map")

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
	self._export:emit("MapVoteComplete", selectedMapId)
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

function module:fireVotingFinished(_votesData, _mapPool)
	-- TODO: Fire remote event to server with voting results
	-- Example: RemoteEvent:FireServer("MapVoteFinished", _votesData, _mapPool)
end

function module:_cleanup()
	self._initialized = false
	self._timerRunning = false
	self._votingFinished = false
	self._allVoted = false

	for userId in self._playerTemplates do
		local data = self._playerTemplates[userId]
		if data and data.template then
			data.template:Destroy()
		end
	end

	table.clear(self._playerTemplates)
	table.clear(self._userTeamTemplates)
	table.clear(self._enemyTeamTemplates)

	self:_clearRewardTemplates()
	self:_clearMapTemplates()
	self:_clearAllPlayerBlips()

	self._selectedMapId = nil
	self._rightSideHolderVisible = false

	self:_cancelTweens("show")
	self:_cancelTweens("hide")
	self:_cancelTweens("rightSideHolder")

	for mapId in self._mapTemplates do
		self:_cancelTweens("mapHover_" .. mapId)
	end

	self:_resetToOriginals()
end

return module
