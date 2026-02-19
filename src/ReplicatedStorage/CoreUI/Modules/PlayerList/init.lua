local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TweenConfig = require(script.TweenConfig)

local PlayerDataTable = require(ReplicatedStorage:WaitForChild("PlayerDataTable"))
local LobbyData = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LobbyData"))

local module = {}
module.__index = module

-- Match Overhead name-tag verified display (utf8 verified badge)
local VERIFIED_CHAR = utf8.char(0xE000)

local SECTION_IDS = { "InLobby", "InGame", "InParty" }
local SECTION_DISPLAY_NAMES = {
	InLobby = "IN LOBBY",
	InGame = "IN GAME",
	InParty = "IN PARTY",
}
local DEFAULT_SECTION = "InLobby"
local TOGGLE_KEY = Enum.KeyCode.Tab

local EVENT_ALIASES = {
	setPlayers = { "PlayerList_SetPlayers", "PlayerListSetPlayers", "PlayerList:SetPlayers" },
	joined = { "PlayerList_PlayerJoined", "PlayerListJoined", "PlayerList:Joined", "PlayerJoined" },
	left = { "PlayerList_PlayerLeft", "PlayerListLeft", "PlayerList:Left", "PlayerLeft" },
	updated = { "PlayerList_PlayerUpdated", "PlayerListUpdated", "PlayerList:Updated", "PlayerDataUpdated" },
	setMatchStatus = { "PlayerList_SetMatchStatus", "PlayerListMatchStatus", "PlayerList:SetMatchStatus" },
	toggleVisible = { "PlayerList_ToggleVisibility", "PlayerListToggle", "PlayerList:Toggle" },
	setVisible = { "PlayerList_SetVisibility", "PlayerListSetVisibility", "PlayerList:SetVisibility" },
}

local function toUserId(value)
	local valueType = typeof(value)
	if valueType == "Instance" and value:IsA("Player") then
		return value.UserId
	end
	if type(value) == "number" then
		return value
	end
	if type(value) == "string" then
		return tonumber(value)
	end
	if type(value) == "table" then
		return toUserId(value.userId or value.UserId or value.id or value.Id)
	end
	return nil
end

local function toBoolean(value, fallback)
	if type(value) == "boolean" then
		return value
	end
	return fallback == true
end

local function normalizeSection(section)
	if type(section) ~= "string" then
		return nil
	end
	for _, sectionId in ipairs(SECTION_IDS) do
		if string.lower(sectionId) == string.lower(section) then
			return sectionId
		end
	end
	return nil
end

local function setGuiVisible(gui, visible)
	if not gui or not gui:IsA("GuiObject") then
		return
	end
	gui.Visible = visible
	if gui:IsA("CanvasGroup") then
		gui.GroupTransparency = visible and 0 or 1
	end
end

local function buildTween(target, tweenInfo, goals)
	local success, tween = pcall(function()
		return TweenService:Create(target, tweenInfo, goals)
	end)
	if not success then
		return nil
	end
	return tween
end

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections

	self._rootHolder = nil
	self._panelGroup = nil
	self._scrollingFrame = nil
	self._scrollingLayout = nil
	self._searchBox = nil
	self._tabs = {}

	self._sections = {}
	self._rows = {}
	self._playersByUserId = {}
	self._selectedUserId = nil
	self._currentUserRow = nil

	self._searchQuery = ""
	self._statMode = "wins"
	self._matchStatus = "Lobby"
	self._defaultSection = DEFAULT_SECTION
	self._isPanelVisible = true

	self:_bindUi()
	self:_bindInput()
	self:_bindEvents()
	self:_bootstrapPlayers()
	self:_ensureCurrentUserCard()

	self._ui.Visible = true
	self:_setPanelVisible(true, false)

	return self
end

function module:_bindUi()
	local holder = self._ui:FindFirstChild("Holder")
	self._rootHolder = holder

	local frame = holder and holder:FindFirstChild("Frame")
	local panel = frame and frame:FindFirstChild("Frame")
	local panelGroup = panel and panel:FindFirstChild("Holder")
	self._panelGroup = panelGroup

	self._searchBox = panelGroup
		and panelGroup:FindFirstChild("Search")
		and panelGroup.Search:FindFirstChild("Search")
		and panelGroup.Search.Search:FindFirstChild("TextBox")

	local tabs = panelGroup and panelGroup:FindFirstChild("Tabs")
	if tabs then
		self._tabs.Crowns = tabs:FindFirstChild("Crowns")
		self._tabs.Streaks = tabs:FindFirstChild("Streaks")
	end

	self._scrollingFrame = panelGroup and panelGroup:FindFirstChild("ScrollingFrame")
	self._scrollingLayout = self._scrollingFrame and self._scrollingFrame:FindFirstChild("UIListLayout")
	self._userFrame = self._scrollingFrame and self._scrollingFrame:FindFirstChild("User")

	for _, sectionId in ipairs(SECTION_IDS) do
		local sectionFrame = self._scrollingFrame and self._scrollingFrame:FindFirstChild(sectionId)
		local sectionHolder = sectionFrame and sectionFrame:FindFirstChild("Holder")
		local template = sectionHolder and (sectionHolder:FindFirstChild("Template") or sectionHolder:FindFirstChild("User"))
		local headerButton = sectionHolder and sectionHolder:FindFirstChild("InGame")
		local countLabel = headerButton and headerButton:FindFirstChild("Aim")

		if template and template:IsA("GuiObject") then
			template.Visible = false
		end

		self._sections[sectionId] = {
			frame = sectionFrame,
			holder = sectionHolder,
			template = template,
			headerButton = headerButton,
			countLabel = countLabel,
			open = true,
		}

		if headerButton and headerButton:IsA("GuiButton") then
			self._connections:track(headerButton, "Activated", function()
				self:_toggleSection(sectionId)
			end, "sectionHeaders")
		end
	end

	self:_syncTabVisuals(false)
	self:_updateSectionCounts()
	self:_refreshCanvasSize()
end

function module:_updateSectionCounts()
	local counts = {}
	for _, sid in ipairs(SECTION_IDS) do
		counts[sid] = 0
	end
	for _, row in pairs(self._rows) do
		if row.section and counts[row.section] ~= nil then
			counts[row.section] = counts[row.section] + 1
		end
	end
	for _, sectionId in ipairs(SECTION_IDS) do
		local sectionData = self._sections[sectionId]
		local label = sectionData and sectionData.countLabel
		if label and label:IsA("TextLabel") then
			local displayName = SECTION_DISPLAY_NAMES[sectionId] or sectionId:upper()
			label.Text = displayName .. " (" .. tostring(counts[sectionId] or 0) .. ")"
		end
	end
end

function module:_ensureCurrentUserCard()
	if not self._userFrame or self._currentUserRow then
		return
	end

	local template = self:_getRowTemplate(DEFAULT_SECTION)
	if not template then
		return
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end

	local data = self:_buildPlayerData(localPlayer)
	if not data then
		return
	end

	local frame = template:Clone()
	frame.Name = "CurrentUser"
	frame.Visible = true
	frame.Parent = self._userFrame

	local row = {
		userId = data.userId,
		section = data.section,
		frame = frame,
		refs = self:_captureRowRefs(frame),
		data = data,
	}
	self:_applyRowData(row)
	self:_setGlowVisibility(row, false)
	self:_setGlowInstant(row, TweenConfig.Values.HiddenGlowTransparency)

	self._currentUserRow = row
end

function module:_updateCurrentUserCard()
	if not self._currentUserRow then
		return
	end
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	local data = self:_buildPlayerData(localPlayer)
	if not data then
		return
	end
	self._currentUserRow.data = data
	self:_applyRowData(self._currentUserRow)
end

function module:_bindInput()
	self._connections:track(UserInputService, "InputBegan", function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode ~= TOGGLE_KEY then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		self:toggleVisibility()
	end, "input")

	if self._searchBox then
		self._connections:add(self._searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			self._searchQuery = string.lower(self._searchBox.Text or "")
			self:_applyFilters()
			self._export:emit("PlayerList_SearchChanged", self._searchBox.Text)
		end), "search")
	end

	if self._tabs.Crowns and self._tabs.Crowns:IsA("GuiButton") then
		self._connections:track(self._tabs.Crowns, "Activated", function()
			self:setStatMode("wins")
		end, "tabs")
	end

	if self._tabs.Streaks and self._tabs.Streaks:IsA("GuiButton") then
		self._connections:track(self._tabs.Streaks, "Activated", function()
			self:setStatMode("streak")
		end, "tabs")
	end

	if self._scrollingLayout then
		self._connections:add(self._scrollingLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			self:_refreshCanvasSize()
		end), "layout")
	end
end

function module:_bindEvents()
	for _, eventName in ipairs(EVENT_ALIASES.setPlayers) do
		self._connections:add(self._export:on(eventName, function(payload)
			self:setPlayers(payload)
		end), "events")
	end

	for _, eventName in ipairs(EVENT_ALIASES.joined) do
		self._connections:add(self._export:on(eventName, function(payload)
			self:addPlayer(payload)
		end), "events")
	end

	for _, eventName in ipairs(EVENT_ALIASES.left) do
		self._connections:add(self._export:on(eventName, function(payload)
			self:removePlayer(payload)
		end), "events")
	end

	for _, eventName in ipairs(EVENT_ALIASES.updated) do
		self._connections:add(self._export:on(eventName, function(payload)
			self:updatePlayer(payload)
		end), "events")
	end

	for _, eventName in ipairs(EVENT_ALIASES.setMatchStatus) do
		self._connections:add(self._export:on(eventName, function(status)
			self:setMatchStatus(status)
		end), "events")
	end

	for _, eventName in ipairs(EVENT_ALIASES.toggleVisible) do
		self._connections:add(self._export:on(eventName, function()
			self:toggleVisibility()
		end), "events")
	end

	for _, eventName in ipairs(EVENT_ALIASES.setVisible) do
		self._connections:add(self._export:on(eventName, function(visible)
			self:setPanelVisible(visible)
		end), "events")
	end

	self._connections:add(self._export:on("MatchStart", function()
		self:setMatchStatus("InGame")
	end), "events")

	self._connections:add(self._export:on("RoundStart", function()
		self:setMatchStatus("InGame")
	end), "events")

	self._connections:add(self._export:on("ReturnToLobby", function()
		self:setMatchStatus("InLobby")
	end), "events")

	self._connections:track(Players, "PlayerAdded", function(player)
		self:addPlayer(player)
	end, "players")

	self._connections:track(Players, "PlayerRemoving", function(player)
		self:removePlayer(player.UserId)
	end, "players")
end

function module:_bootstrapPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		self:addPlayer(player)
	end
end

function module:_buildPlayerData(inputData)
	local player = nil
	if typeof(inputData) == "Instance" and inputData:IsA("Player") then
		player = inputData
	end

	local userId = toUserId(inputData)
	if not userId then
		return nil
	end

	local tableData = type(inputData) == "table" and inputData or {}
	local localPlayer = Players.LocalPlayer
	local livePlayer = player or Players:GetPlayerByUserId(userId)

	local displayName = tableData.displayName or tableData.DisplayName
	if type(displayName) ~= "string" or displayName == "" then
		displayName = livePlayer and livePlayer.DisplayName or nil
	end
	if type(displayName) ~= "string" or displayName == "" then
		displayName = tableData.username or tableData.userName or tableData.Name or ("Player " .. tostring(userId))
	end

	local username = tableData.username or tableData.userName or tableData.Name
	if type(username) ~= "string" or username == "" then
		username = livePlayer and livePlayer.Name or displayName
	end

	local wins = tonumber(tableData.wins or tableData.WINS)
	local streak = tonumber(tableData.streak or tableData.STREAK)

	if not wins or not streak then
		if localPlayer and userId == localPlayer.UserId then
			wins = wins or tonumber(PlayerDataTable.getData("WINS")) or 0
			streak = streak or tonumber(PlayerDataTable.getData("STREAK")) or 0
		else
			local lobbyPlayer = LobbyData.getPlayer(userId)
			if lobbyPlayer then
				wins = wins or tonumber(lobbyPlayer.wins) or 0
				streak = streak or tonumber(lobbyPlayer.streak) or 0
			end
		end
	end

	local explicitSection = normalizeSection(tableData.section or tableData.statusSection)
	local inParty = toBoolean(tableData.inParty, false)
	if not inParty and livePlayer then
		inParty = toBoolean(livePlayer:GetAttribute("InParty"), false)
	end

	local section = explicitSection
	if not section then
		if inParty then
			section = "InParty"
		else
			local state = livePlayer and livePlayer:GetAttribute("PlayerState")
			local inLobby = livePlayer and toBoolean(livePlayer:GetAttribute("InLobby"), false)
			if inLobby or state == "Lobby" then
				section = "InLobby"
			elseif self._defaultSection == "InGame" or state == "InMatch" or state == "Training" then
				section = "InGame"
			else
				section = DEFAULT_SECTION
			end
		end
	end

	local isFriend = toBoolean(tableData.isFriend, false)
	if not isFriend and localPlayer and userId ~= localPlayer.UserId then
		local ok, friendResult = pcall(function()
			return localPlayer:IsFriendsWith(userId)
		end)
		isFriend = ok and friendResult == true
	end

	local isDev = toBoolean(tableData.isDev, false)
	if not isDev and livePlayer then
		isDev = toBoolean(livePlayer:GetAttribute("IsDeveloper"), false)
	end

	local isPremium = toBoolean(tableData.isPremium, false)
	if not isPremium and livePlayer then
		isPremium = livePlayer.MembershipType == Enum.MembershipType.Premium
	end

	local isVerified = toBoolean(tableData.isVerified, false)
	if not isVerified and livePlayer then
		local ok, verifiedResult = pcall(function()
			return livePlayer.HasVerifiedBadge
		end)
		isVerified = ok and verifiedResult == true
	end

	return {
		userId = userId,
		displayName = displayName,
		username = username,
		wins = wins or 0,
		streak = streak or 0,
		section = section,
		isFriend = isFriend,
		isDev = isDev,
		isPremium = isPremium,
		isVerified = isVerified,
		sectionLocked = explicitSection ~= nil,
	}
end

function module:_captureRowRefs(frame)
	local nameHolder = frame:FindFirstChild("NameHolder")
	local glow = frame:FindFirstChild("Glow")

	return {
		frame = frame,
		nameLabel = nameHolder and nameHolder:FindFirstChild("Username"),
		statusLabel = frame:FindFirstChild("Status"),
		numberLabel = frame:FindFirstChild("NumberText"),
		playerImage = frame:FindFirstChild("PlayerImage"),
		friendBadge = nameHolder and nameHolder:FindFirstChild("Friend"),
		devBadge = nameHolder and nameHolder:FindFirstChild("Dev"),
		premiumBadge = nameHolder and nameHolder:FindFirstChild("Premuim"),
		verifiedIcon = nameHolder and nameHolder:FindFirstChild("Icon"),
		glowRoot = glow,
		glowBar = glow and glow:FindFirstChild("Bar"),
		glowFill = glow and glow:FindFirstChild("Glow"),
	}
end

function module:_setGlowVisibility(row, visible)
	local refs = row.refs
	if not refs or not refs.glowRoot then
		return
	end
	refs.glowRoot.Visible = visible
end

function module:_cancelGlowTweens(row)
	if not row.glowTweens then
		return
	end
	for _, tween in ipairs(row.glowTweens) do
		tween:Cancel()
	end
	table.clear(row.glowTweens)
end

function module:_tweenGlow(row, transparency, tweenInfo)
	local refs = row.refs
	if not refs then
		return
	end

	self:_cancelGlowTweens(row)
	row.glowTweens = {}

	local targets = { refs.glowBar, refs.glowFill }
	for _, target in ipairs(targets) do
		if target and target:IsA("GuiObject") then
			local tween = buildTween(target, tweenInfo, { BackgroundTransparency = transparency })
			if tween then
				table.insert(row.glowTweens, tween)
				tween:Play()
			end
		end
	end
end

function module:_setGlowInstant(row, transparency)
	local refs = row.refs
	if not refs then
		return
	end

	for _, target in ipairs({ refs.glowBar, refs.glowFill }) do
		if target and target:IsA("GuiObject") then
			target.BackgroundTransparency = transparency
		end
	end
end

function module:_startHoverPulse(row)
	row.pulseToken += 1
	local currentToken = row.pulseToken

	self:_setGlowVisibility(row, true)

	task.spawn(function()
		while row.pulseToken == currentToken and row.hovered and not row.selected do
			self:_tweenGlow(
				row,
				TweenConfig.Values.HoverGlowMinTransparency,
				TweenConfig.get("Glow", "hoverPulse")
			)
			task.wait(TweenConfig.get("Glow", "hoverPulse").Time)
			if row.pulseToken ~= currentToken or row.selected or not row.hovered then
				break
			end

			self:_tweenGlow(
				row,
				TweenConfig.Values.HoverGlowMaxTransparency,
				TweenConfig.get("Glow", "hoverPulse")
			)
			task.wait(TweenConfig.get("Glow", "hoverPulse").Time)
		end
	end)
end

function module:_stopHoverPulse(row)
	row.pulseToken += 1
	if row.selected then
		self:_setGlowVisibility(row, true)
		self:_tweenGlow(row, TweenConfig.Values.SelectedGlowTransparency, TweenConfig.get("Glow", "selectIn"))
		return
	end

	self:_tweenGlow(row, TweenConfig.Values.HiddenGlowTransparency, TweenConfig.get("Glow", "selectOut"))
	task.delay(TweenConfig.get("Glow", "selectOut").Time, function()
		if row and row.refs and row.pulseToken and not row.selected and not row.hovered then
			self:_setGlowVisibility(row, false)
		end
	end)
end

function module:_applyBadgePriority(refs, data)
	if not refs then
		return
	end

	setGuiVisible(refs.friendBadge, false)
	setGuiVisible(refs.devBadge, false)
	setGuiVisible(refs.premiumBadge, false)

	if data.isFriend then
		setGuiVisible(refs.friendBadge, true)
	elseif data.isDev then
		setGuiVisible(refs.devBadge, true)
	elseif data.isPremium then
		setGuiVisible(refs.premiumBadge, true)
	end
end

function module:_applyVerified(refs, data)
	if not refs then
		return
	end

	-- Match Overhead: displayName + " " + VERIFIED_CHAR when verified (no RichText)
	local baseDisplayName = data.displayName or ("Player " .. tostring(data.userId))
	local suffix = data.isVerified and (" " .. VERIFIED_CHAR) or ""

	if refs.verifiedIcon and refs.verifiedIcon:IsA("TextLabel") then
		refs.verifiedIcon.Text = data.isVerified and VERIFIED_CHAR or ""
		refs.verifiedIcon.Visible = data.isVerified
	end

	if refs.nameLabel and refs.nameLabel:IsA("TextLabel") then
		refs.nameLabel.Text = baseDisplayName .. suffix
		refs.nameLabel.RichText = false
	end
end

function module:_applyRowData(row)
	local data = row.data
	local refs = row.refs
	if not data or not refs then
		return
	end

	self:_applyVerified(refs, data)
	self:_applyBadgePriority(refs, data)

	if refs.statusLabel and refs.statusLabel:IsA("TextLabel") then
		refs.statusLabel.Text = "@" .. tostring(data.username or data.displayName or "unknown")
	end

	if refs.numberLabel and refs.numberLabel:IsA("TextLabel") then
		local value = self._statMode == "streak" and data.streak or data.wins
		refs.numberLabel.Text = tostring(value or 0)
	end

	if refs.playerImage and refs.playerImage:IsA("ImageLabel") then
		task.spawn(function()
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(
					data.userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size420x420
				)
			end)
			local stillThisRow = self._rows[data.userId] == row or self._currentUserRow == row
			if ok and content and stillThisRow and refs.playerImage then
				refs.playerImage.Image = content
			end
		end)
	end
end

function module:_connectRowInteractions(row)
	local frame = row.frame
	local groupName = "row_" .. tostring(row.userId)

	if frame:IsA("GuiButton") then
		self._connections:track(frame, "Activated", function()
			self:_selectUser(row.userId)
		end, groupName)
	else
		self._connections:track(frame, "InputBegan", function(input)
			local inputType = input.UserInputType
			if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
				self:_selectUser(row.userId)
			end
		end, groupName)
	end

	local function onHoverStart()
		row.hovered = true
		if not row.selected then
			self:_startHoverPulse(row)
		end
	end

	local function onHoverEnd()
		row.hovered = false
		self:_stopHoverPulse(row)
	end

	self._connections:track(frame, "MouseEnter", onHoverStart, groupName)
	self._connections:track(frame, "MouseLeave", onHoverEnd, groupName)
	self._connections:track(frame, "SelectionGained", onHoverStart, groupName)
	self._connections:track(frame, "SelectionLost", onHoverEnd, groupName)
end

function module:_getRowTemplate(sectionId)
	local sectionData = self._sections[sectionId]
	if sectionData and sectionData.template then
		return sectionData.template
	end
	-- Fallback: use first section that has a template (e.g. InGame may have no Template in UI)
	for _, sid in ipairs(SECTION_IDS) do
		local sd = self._sections[sid]
		if sd and sd.template then
			return sd.template
		end
	end
	return nil
end

function module:_createRow(data)
	local sectionData = self._sections[data.section] or self._sections[DEFAULT_SECTION]
	if not sectionData or not sectionData.holder then
		return nil
	end

	local template = self:_getRowTemplate(data.section)
	if not template then
		return nil
	end

	local frame = template:Clone()
	frame.Name = "User_" .. tostring(data.userId)
	frame.Visible = true
	frame.Parent = sectionData.holder
	frame.LayoutOrder = TweenConfig.Values.RowLayoutBaseOrder

	local row = {
		userId = data.userId,
		section = data.section,
		frame = frame,
		refs = self:_captureRowRefs(frame),
		data = data,
		hovered = false,
		selected = false,
		pulseToken = 0,
		glowTweens = {},
	}

	self:_setGlowVisibility(row, false)
	self:_setGlowInstant(row, TweenConfig.Values.HiddenGlowTransparency)
	self:_connectRowInteractions(row)

	local rowScale = frame:FindFirstChild("UIScale")
	if rowScale and rowScale:IsA("UIScale") then
		rowScale.Scale = 0.9
		local tween = buildTween(rowScale, TweenConfig.get("Row", "enter"), { Scale = 1 })
		if tween then
			tween:Play()
		end
	end

	self:_applyRowData(row)

	return row
end

function module:_destroyRow(row)
	if not row then
		return
	end

	local groupName = "row_" .. tostring(row.userId)
	self._connections:cleanupGroup(groupName)

	self:_cancelGlowTweens(row)
	row.pulseToken += 1

	if row.frame and row.frame.Parent then
		local rowScale = row.frame:FindFirstChild("UIScale")
		if rowScale and rowScale:IsA("UIScale") then
			local tween = buildTween(rowScale, TweenConfig.get("Row", "exit"), { Scale = 0.92 })
			if tween then
				tween:Play()
			end
		end
		row.frame:Destroy()
	end
end

function module:_sortSection(sectionId)
	local sorted = {}
	for _, row in pairs(self._rows) do
		if row.section == sectionId then
			table.insert(sorted, row)
		end
	end

	table.sort(sorted, function(a, b)
		local ad = string.lower(tostring(a.data.displayName or a.data.username or ""))
		local bd = string.lower(tostring(b.data.displayName or b.data.username or ""))
		if ad == bd then
			return a.userId < b.userId
		end
		return ad < bd
	end)

	for index, row in ipairs(sorted) do
		row.frame.LayoutOrder = TweenConfig.Values.RowLayoutBaseOrder + index
	end
end

function module:_matchesSearch(data)
	if self._searchQuery == "" then
		return true
	end
	local displayName = string.lower(tostring(data.displayName or ""))
	local username = string.lower(tostring(data.username or ""))
	return string.find(displayName, self._searchQuery, 1, true) ~= nil
		or string.find(username, self._searchQuery, 1, true) ~= nil
end

function module:_applyFilters()
	for _, row in pairs(self._rows) do
		local sectionState = self._sections[row.section]
		local visible = (sectionState and sectionState.open == true) and self:_matchesSearch(row.data)
		row.frame.Visible = visible

		if not visible and self._selectedUserId == row.userId then
			self:_clearSelection()
		end
	end

	self:_refreshCanvasSize()
end

function module:_refreshCanvasSize()
	if not self._scrollingFrame or not self._scrollingLayout then
		return
	end
	local sizeY = self._scrollingLayout.AbsoluteContentSize.Y + 8
	self._scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, sizeY)
end

function module:_toggleSection(sectionId)
	local sectionData = self._sections[sectionId]
	if not sectionData then
		return
	end

	sectionData.open = not sectionData.open
	self:_applyFilters()

	self._export:emit("PlayerList_DropdownChanged", {
		section = sectionId,
		open = sectionData.open,
	})
end

function module:_syncTabVisuals(emitChanged)
	local crownsActive = self._statMode == "wins"
	local streaksActive = self._statMode == "streak"

	local function setTab(tabButton, active)
		if not tabButton then
			return
		end
		local glow = tabButton:FindFirstChild("Glow")
		if glow and glow:IsA("GuiObject") then
			glow.Visible = true
			local target = active and 0 or 1
			local tween = buildTween(glow, TweenConfig.get("Tab", "switch"), { BackgroundTransparency = target })
			if tween then
				tween:Play()
			else
				glow.BackgroundTransparency = target
			end
		end
	end

	setTab(self._tabs.Crowns, crownsActive)
	setTab(self._tabs.Streaks, streaksActive)

	for _, row in pairs(self._rows) do
		self:_applyRowData(row)
	end

	self:_updateCurrentUserCard()

	if emitChanged then
		self._export:emit("PlayerList_ViewChanged", self._statMode)
	end
end

function module:_clearSelection()
	local selected = self._selectedUserId and self._rows[self._selectedUserId]
	if selected then
		selected.selected = false
		self:_stopHoverPulse(selected)
	end
	self._selectedUserId = nil
end

function module:_selectUser(userId)
	local row = self._rows[userId]
	if not row then
		return
	end

	if self._selectedUserId == userId then
		return
	end

	self:_clearSelection()

	self._selectedUserId = userId
	row.selected = true
	row.hovered = false
	row.pulseToken += 1

	self:_setGlowVisibility(row, true)
	self:_tweenGlow(row, TweenConfig.Values.SelectedGlowTransparency, TweenConfig.get("Glow", "selectIn"))

	self._export:emit("PlayerList_PlayerSelected", {
		userId = row.data.userId,
		displayName = row.data.displayName,
		username = row.data.username,
		section = row.data.section,
		wins = row.data.wins,
		streak = row.data.streak,
	})
end

function module:addPlayer(payload)
	local data = self:_buildPlayerData(payload)
	if not data then
		return
	end

	local existing = self._playersByUserId[data.userId]
	if existing then
		data.sectionLocked = data.sectionLocked or existing.sectionLocked
		for key, value in pairs(existing) do
			if data[key] == nil then
				data[key] = value
			end
		end
	end

	self._playersByUserId[data.userId] = data

	local existingRow = self._rows[data.userId]
	if existingRow and existingRow.section ~= data.section then
		self:_destroyRow(existingRow)
		self._rows[data.userId] = nil
		existingRow = nil
	end

	if not existingRow then
		local row = self:_createRow(data)
		if row then
			self._rows[data.userId] = row
		end
	else
		existingRow.data = data
		self:_applyRowData(existingRow)
	end

	self:_sortSection(data.section)
	self:_applyFilters()
	self:_updateSectionCounts()
	self:_refreshCanvasSize()
end

function module:removePlayer(payload)
	local userId = toUserId(payload)
	if not userId then
		return
	end

	self._playersByUserId[userId] = nil

	local row = self._rows[userId]
	if row then
		if self._selectedUserId == userId then
			self._selectedUserId = nil
		end
		self:_destroyRow(row)
		self._rows[userId] = nil
	end

	self:_updateSectionCounts()
	self:_refreshCanvasSize()
end

function module:updatePlayer(payload)
	local data = self:_buildPlayerData(payload)
	if not data then
		return
	end
	self:addPlayer(data)
end

function module:setPlayers(payload)
	for userId, row in pairs(self._rows) do
		self:_destroyRow(row)
		self._rows[userId] = nil
	end
	table.clear(self._playersByUserId)
	self._selectedUserId = nil

	if type(payload) == "table" then
		if #payload > 0 then
			for _, entry in ipairs(payload) do
				self:addPlayer(entry)
			end
		else
			for key, entry in pairs(payload) do
				if type(entry) ~= "table" then
					entry = { userId = key }
				elseif entry.userId == nil and entry.UserId == nil then
					entry.userId = key
				end
				self:addPlayer(entry)
			end
		end
	end

	self:_updateSectionCounts()
	self:_refreshCanvasSize()
end

function module:setMatchStatus(status)
	local section = normalizeSection(status)
	if section then
		self._defaultSection = section
		self._matchStatus = section
	elseif type(status) == "string" then
		local lower = string.lower(status)
		if lower == "lobby" or lower == "inlobby" then
			self._defaultSection = "InLobby"
			self._matchStatus = "InLobby"
		elseif lower == "ingame" or lower == "match" then
			self._defaultSection = "InGame"
			self._matchStatus = "InGame"
		end
	end

	for userId, data in pairs(self._playersByUserId) do
		if not data.sectionLocked and data.section ~= "InParty" then
			local nextSection = self._defaultSection
			data.section = nextSection
			self:addPlayer(data)
			if self._rows[userId] then
				self._rows[userId].section = nextSection
			end
		end
	end

	self:_applyFilters()
end

function module:setStatMode(mode)
	local normalized = string.lower(tostring(mode or "wins"))
	if normalized == "crowns" then
		normalized = "wins"
	end
	if normalized ~= "wins" and normalized ~= "streak" then
		return
	end
	if self._statMode == normalized then
		return
	end

	self._statMode = normalized
	self:_syncTabVisuals(true)
end

function module:_setPanelVisible(visible, animated)
	self._isPanelVisible = visible
	self._ui.Visible = true

	if not self._panelGroup or not self._panelGroup:IsA("GuiObject") then
		if not visible then
			self._ui.Visible = false
		end
		return
	end

	local tweenInfo = visible and TweenConfig.get("Panel", "show") or TweenConfig.get("Panel", "hide")
	local targetTransparency = visible and 0 or 1

	if animated then
		local tween = buildTween(self._panelGroup, tweenInfo, { GroupTransparency = targetTransparency })
		if tween then
			tween:Play()
		else
			self._panelGroup.GroupTransparency = targetTransparency
		end
	else
		self._panelGroup.GroupTransparency = targetTransparency
	end

	if not visible then
		task.delay(tweenInfo.Time, function()
			if not self._isPanelVisible then
				self._ui.Visible = false
			end
		end)
	end
end

function module:setPanelVisible(visible)
	self:_setPanelVisible(visible == true, true)
end

function module:toggleVisibility()
	self:_setPanelVisible(not self._isPanelVisible, true)
end

function module:show()
	self:_setPanelVisible(true, true)
	self._export:setModuleState("PlayerList", true)
	return true
end

function module:hide()
	self:_setPanelVisible(false, true)
	self._export:setModuleState("PlayerList", false)
	return true
end

function module:_cleanup()
	for _, row in pairs(self._rows) do
		self:_destroyRow(row)
	end
	table.clear(self._rows)
	table.clear(self._playersByUserId)
	self._selectedUserId = nil
	if self._currentUserRow and self._currentUserRow.frame and self._currentUserRow.frame.Parent then
		self._currentUserRow.frame:Destroy()
	end
	self._currentUserRow = nil
end

return module
