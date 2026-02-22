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
	self._localMirrorRow = nil

	self._searchQuery = ""
	self._statMode = "wins"
	self._matchStatus = "Lobby"
	self._defaultSection = DEFAULT_SECTION
	self._isPanelVisible = true

	self._playerShowFrame = nil
	self._partyState = nil
	self._userLeaveTemplate = nil
	self._userLeaveInstance = nil

	self._notifScreenGui = nil
	self._notifTemplates = {}
	self._activeNotif = nil
	self._notifTimerThread = nil

	self:_bindUi()
	self:_bindInput()
	self:_bindEvents()
	self:_bindPartyEvents()
	self:_bootstrapPlayers()
	self:_ensureCurrentUserCard()
	self:_ensureUserLeaveAction()
	self:_updateUserLeaveAction()

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

	if self._scrollingFrame and self._scrollingLayout then
		local sf = self._scrollingFrame
		local sl = self._scrollingLayout
		sf.AutomaticCanvasSize = Enum.AutomaticSize.None
		sf.CanvasSize = UDim2.new(0, 0, 0, sl.AbsoluteContentSize.Y + 8)
		sl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			sf.CanvasSize = UDim2.new(0, 0, 0, sl.AbsoluteContentSize.Y + 8)
		end)
	end

	local assetsGui = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Gui")
	self._rowTemplate = assetsGui and assetsGui:FindFirstChild("PlayerlistTemp")
	self._userLeaveTemplate = assetsGui and assetsGui:FindFirstChild("LeavePartyTemplate")

	for _, sectionId in ipairs(SECTION_IDS) do
		local sectionFrame = self._scrollingFrame and self._scrollingFrame:FindFirstChild(sectionId)
		local sectionHolder = sectionFrame and sectionFrame:FindFirstChild("Holder")
		local headerButton = sectionHolder and sectionHolder:FindFirstChild("InGame")
		local countLabel = headerButton and headerButton:FindFirstChild("Aim")

		if sectionFrame and sectionFrame:IsA("GuiObject") then
			sectionFrame.AutomaticSize = Enum.AutomaticSize.Y
			sectionFrame.Size = UDim2.new(sectionFrame.Size.X, UDim.new(0, 0))
		end
		if sectionHolder and sectionHolder:IsA("GuiObject") then
			sectionHolder.AutomaticSize = Enum.AutomaticSize.Y
			sectionHolder.Size = UDim2.new(sectionHolder.Size.X, UDim.new(0, 0))
		end

		self._sections[sectionId] = {
			frame = sectionFrame,
			holder = sectionHolder,
			template = self._rowTemplate,
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

	self._playerShowFrame = self._ui:FindFirstChild("PlayerShow")
	if self._playerShowFrame then
		self._playerShowFrame.Visible = false
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer then
		local playerGui = localPlayer:FindFirstChild("PlayerGui")
		if playerGui then
			local notifGui = playerGui:FindFirstChild("PartyNotification")
			if notifGui then
				self._notifScreenGui = notifGui
				local folder = notifGui:FindFirstChild("Folder")
				if folder then
					for _, child in folder:GetChildren() do
						if child:IsA("Frame") then
							self._notifTemplates[child.Name] = child
							child.Visible = false
						end
					end
				end
			end
		end
	end

	local oldInviteFrame = self._scrollingFrame and self._scrollingFrame:FindFirstChild("Invite")
	if oldInviteFrame then
		oldInviteFrame.Visible = false
	end
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
	if self._localMirrorRow and self._localMirrorRow.frame and self._localMirrorRow.frame.Parent then
		local mirrorSection = self._localMirrorRow.section
		if mirrorSection and counts[mirrorSection] ~= nil then
			counts[mirrorSection] = counts[mirrorSection] + 1
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

	-- Use replica-backed data if available so wins/streak are actual values
	local data = self._playersByUserId[localPlayer.UserId] or self:_buildPlayerData(localPlayer)
	if not data then
		return
	end

	for _, child in self._userFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child.Visible = false
		end
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
		hovered = false,
		selected = false,
		pulseToken = 0,
		glowTweens = {},
	}
	self:_applyRowData(row)
	self:_setGlowVisibility(row, false)
	self:_setGlowInstant(row, TweenConfig.Values.HiddenGlowTransparency)
	self:_connectRowInteractions(row)

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
	-- Prefer replica-backed data so wins/streak at top are actual values
	local data = self._playersByUserId[localPlayer.UserId]
	if not data then
		data = self:_buildPlayerData(localPlayer)
	end
	if not data then
		return
	end
	self._currentUserRow.data = data
	self:_applyRowData(self._currentUserRow)
	self:_updateUserLeaveAction()
end

function module:_ensureUserLeaveAction()
	if not self._scrollingFrame or not self._userFrame or self._userLeaveInstance or not self._userLeaveTemplate then
		return
	end

	self._userFrame.LayoutOrder = -2

	local instance = self._userLeaveTemplate:Clone()
	instance.Name = "UserLeaveAction"
	instance.Visible = false
	if instance:IsA("GuiObject") then
		instance.LayoutOrder = -1
	end
	instance.Parent = self._scrollingFrame
	self._userLeaveInstance = instance
end

function module:_updateUserLeaveAction()
	if not self._userLeaveInstance then
		return
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		self._userLeaveInstance.Visible = false
		return
	end

	local inParty = self._partyState ~= nil
	local isLeader = inParty and self._partyState.leaderId == localPlayer.UserId
	self._userLeaveInstance.Visible = inParty
	self:_refreshCanvasSize()

	local button = self._userLeaveInstance:FindFirstChild("InviteHolder", true)
	button = button and button:FindFirstChild("Holder")
	button = button and button:FindFirstChild("Accept")
	local label = button and button:FindFirstChild("Invited")
	if label and label:IsA("TextLabel") then
		label.Text = isLeader and "DISBAND" or "LEAVE"
	end

	self._connections:cleanupGroup("userLeaveAction")
	if button and button:IsA("GuiButton") and inParty then
		self._connections:track(button, "Activated", function()
			print("[PlayerList] USER ACTION clicked:", isLeader and "DISBAND" or "LEAVE")
			self._export:emit("PartyLeave")
			self:_eagerClearParty()
			self:_hidePlayerShow()
			self:_clearSelection()
		end, "userLeaveAction")
	end
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
		-- Don't allow player list toggle during match
		if self._matchStatus == "InGame" then
			return
		end
		self:toggleVisibility()
	end, "input")

	if self._searchBox then
		self._connections:add(self._searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			self._searchQuery = string.lower(self._searchBox.Text or "")
			self:_applySearchToSections()
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

	self._connections:add(self._export:on("TrainingStart", function()
		self:setMatchStatus("InGame")
	end), "events")

	self._connections:track(Players, "PlayerAdded", function(player)
		self:addPlayer(player)
	end, "players")

	self._connections:track(Players, "PlayerRemoving", function(player)
		self:removePlayer(player.UserId)
	end, "players")

	-- Refresh local player section when PlayerState/InLobby changes (e.g. return to lobby)
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		local function refreshLocalPlayerSection()
			self:updatePlayer(localPlayer)
		end
		self._connections:add(localPlayer:GetAttributeChangedSignal("PlayerState"):Connect(refreshLocalPlayerSection), "attributes")
		self._connections:add(localPlayer:GetAttributeChangedSignal("InLobby"):Connect(refreshLocalPlayerSection), "attributes")
	end
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

	local inParty
	if tableData.inParty ~= nil then
		inParty = toBoolean(tableData.inParty, false)
	elseif self._partyState then
		inParty = table.find(self._partyState.members, userId) ~= nil
	else
		inParty = false
	end

	local section = explicitSection
	if inParty then
		section = "InParty"
	elseif not section then
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
		inParty = inParty,
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
			local stillThisRow = self._rows[data.userId] == row or self._currentUserRow == row or self._localMirrorRow == row
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
	return self._rowTemplate
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
	if self._localMirrorRow and self._localMirrorRow.section == sectionId then
		table.insert(sorted, self._localMirrorRow)
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

function module:_applySearchToSections()
	if self._searchQuery == "" then
		for _, sectionId in ipairs(SECTION_IDS) do
			local sectionData = self._sections[sectionId]
			if sectionData then
				sectionData.open = true
			end
		end
		return
	end
	-- Close all, then open only sections that have at least one matching row
	for _, sectionId in ipairs(SECTION_IDS) do
		local sectionData = self._sections[sectionId]
		if sectionData then
			sectionData.open = false
		end
	end
	local sectionsWithMatches = {}
	for _, row in pairs(self._rows) do
		if row.section and self:_matchesSearch(row.data) then
			sectionsWithMatches[row.section] = true
		end
	end
	for sectionId, _ in pairs(sectionsWithMatches) do
		local sectionData = self._sections[sectionId]
		if sectionData then
			sectionData.open = true
		end
	end
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

	if self._localMirrorRow and self._localMirrorRow.frame then
		local sectionState = self._sections[self._localMirrorRow.section]
		local visible = (sectionState and sectionState.open == true) and self:_matchesSearch(self._localMirrorRow.data)
		self._localMirrorRow.frame.Visible = visible
	end

	self:_refreshCanvasSize()
end

function module:_refreshCanvasSize()
	if not self._scrollingFrame or not self._scrollingLayout then
		return
	end
	for _, sectionId in ipairs(SECTION_IDS) do
		local sec = self._sections[sectionId]
		if sec and sec.holder and sec.holder:IsA("GuiObject") then
			sec.holder.AutomaticSize = Enum.AutomaticSize.None
			sec.holder.AutomaticSize = Enum.AutomaticSize.Y
		end
		if sec and sec.frame and sec.frame:IsA("GuiObject") then
			sec.frame.AutomaticSize = Enum.AutomaticSize.None
			sec.frame.AutomaticSize = Enum.AutomaticSize.Y
		end
	end
	self._scrollingFrame.CanvasSize = UDim2.new(
		0, 0, 0, self._scrollingLayout.AbsoluteContentSize.Y + 8
	)
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
	if not selected then
		local localPlayer = Players.LocalPlayer
		if localPlayer and self._selectedUserId == localPlayer.UserId then
			selected = self._currentUserRow
		end
	end
	if selected then
		selected.selected = false
		self:_stopHoverPulse(selected)
	end
	self._selectedUserId = nil
	self:_hidePlayerShow()
end

function module:_selectUser(userId)
	local row = self._rows[userId]
	if not row then
		local localPlayer = Players.LocalPlayer
		if localPlayer and userId == localPlayer.UserId and self._currentUserRow then
			row = self._currentUserRow
		else
			return
		end
	end

	if self._selectedUserId == userId then
		self:_clearSelection()
		return
	end

	self:_clearSelection()

	self._selectedUserId = userId
	row.selected = true
	row.hovered = false
	row.pulseToken += 1

	self:_setGlowVisibility(row, true)
	self:_tweenGlow(row, TweenConfig.Values.SelectedGlowTransparency, TweenConfig.get("Glow", "selectIn"))

	self:_showPlayerShow(userId, row.data)

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

	local localPlayer = Players.LocalPlayer

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

	-- Keep User frame wins/streak in sync with actual profile data
	if localPlayer and data.userId == localPlayer.UserId then
		self:_updateCurrentUserCard()
	end
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
		elseif lower == "ingame" or lower == "match" or lower == "training" then
			self._defaultSection = "InGame"
			self._matchStatus = "InGame"
		end
	end

	-- Use proper hide/show methods for full visibility state (not halfway)
	if self._matchStatus == "InGame" then
		-- Properly hide: use _setPanelVisible for full hide flow (instant for match/training)
		self:_setPanelVisible(false, false)
		self._export:setModuleState("PlayerList", false)
	elseif self._matchStatus == "InLobby" then
		-- Properly show: use _setPanelVisible for full restore (panel open, animated)
		self:_setPanelVisible(true, true)
		self._export:setModuleState("PlayerList", true)
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

	if not self._panelGroup or not self._panelGroup:IsA("GuiObject") then
		if self._ui and self._ui:IsA("GuiObject") then
			self._ui.Visible = visible
		end
		return
	end

	local tweenInfo = visible and TweenConfig.get("Panel", "show") or TweenConfig.get("Panel", "hide")
	local targetTransparency = visible and 0 or 1

	if visible then
		self._ui.Visible = true
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
	else
		-- Hide: set panel transparent first, then hide root
		if animated then
			self._ui.Visible = true
			local tween = buildTween(self._panelGroup, tweenInfo, { GroupTransparency = targetTransparency })
			if tween then
				tween:Play()
			else
				self._panelGroup.GroupTransparency = targetTransparency
			end
			task.delay(tweenInfo.Time, function()
				if not self._isPanelVisible and self._ui and self._ui:IsA("GuiObject") then
					self._ui.Visible = false
				end
			end)
		else
			-- Instant hide: no animation, no delay
			self._panelGroup.GroupTransparency = targetTransparency
			if self._ui and self._ui:IsA("GuiObject") then
				self._ui.Visible = false
			end
		end
	end
end

function module:setPanelVisible(visible)
	-- During match, only allow hiding (never showing)
	if self._matchStatus == "InGame" and visible then
		return
	end
	self:_setPanelVisible(visible == true, true)
end

function module:toggleVisibility()
	-- Don't show player list during match
	if self._matchStatus == "InGame" then
		self:_setPanelVisible(false, true)
		return
	end
	self:_setPanelVisible(not self._isPanelVisible, true)
end

function module:show()
	-- Don't show player list during match
	if self._matchStatus == "InGame" then
		return false
	end
	self:_setPanelVisible(true, true)
	self._export:setModuleState("PlayerList", true)
	return true
end

function module:hide()
	self:_setPanelVisible(false, true)
	self._export:setModuleState("PlayerList", false)
	return true
end

--------------------------------------------------------------------------------
-- PLAYER SHOW CARD
--------------------------------------------------------------------------------

function module:_showPlayerShow(userId, data)
	local frame = self._playerShowFrame
	if not frame then
		return
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		frame.Visible = false
		return
	end

	local isSelf = userId == localPlayer.UserId

	self._connections:cleanupGroup("playerShow")

	local contentFrame = frame:FindFirstChild("Frame")
	if not contentFrame then
		return
	end

	local userHolder = contentFrame:FindFirstChild("userHolder")
	if userHolder then
		local nameHolder = userHolder:FindFirstChild("NameHolder")
		if nameHolder then
			local username = nameHolder:FindFirstChild("Username")
			if username and username:IsA("TextLabel") then
				username.Text = data.displayName or ("Player " .. tostring(userId))
			end
		end
		local status = userHolder:FindFirstChild("Status")
		if status and status:IsA("TextLabel") then
			status.Text = "@" .. tostring(data.username or data.displayName or "unknown")
		end
		local playerImage = userHolder:FindFirstChild("PlayerImage")
		if playerImage and playerImage:IsA("ImageLabel") then
			task.spawn(function()
				local ok, content = pcall(function()
					return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
				end)
				if ok and content and self._selectedUserId == userId then
					playerImage.Image = content
				end
			end)
		end
	end

	local statusGroup = contentFrame:FindFirstChild("Status")
	if statusGroup then
		local aim = statusGroup:FindFirstChild("Aim")
		if aim and aim:IsA("TextLabel") then
			if data.section == "InGame" then
				aim.Text = "IN GAME"
			elseif data.section == "InParty" then
				aim.Text = "IN PARTY"
			else
				aim.Text = "IN LOBBY"
			end
		end
	end

	local inviteButton = contentFrame:FindFirstChild("PartyInvite")
	local leaveButton = contentFrame:FindFirstChild("bar")
	local inPartyDisplay = contentFrame:FindFirstChild("InPartyDisplay")

	local kickButton, disbandButton
	for _, child in contentFrame:GetChildren() do
		if child.Name == "LeaveParty" and child:IsA("GuiButton") then
			local label = child:FindFirstChild("Status")
			if label and label:IsA("TextLabel") then
				if string.find(label.Text, "KICK") then
					kickButton = child
				elseif string.find(label.Text, "DISBAND") then
					disbandButton = child
				end
			end
		end
	end

	local inParty = self._partyState ~= nil
	local isLeader = inParty and self._partyState.leaderId == localPlayer.UserId
	local targetInMyParty = inParty and table.find(self._partyState.members, userId) ~= nil

	local targetInAnyParty = false
	if not isSelf then
		if targetInMyParty then
			targetInAnyParty = true
		else
			local trackedData = self._playersByUserId[userId]
			if trackedData and trackedData.inParty == false then
				targetInAnyParty = false
			else
				local targetPlayer = Players:GetPlayerByUserId(userId)
				if targetPlayer then
					targetInAnyParty = targetPlayer:GetAttribute("InParty") == true
				end
			end
		end
	end

	print("[PlayerList] _showPlayerShow: userId", userId, "isSelf:", isSelf, "inParty:", inParty, "isLeader:", isLeader, "targetInMyParty:", targetInMyParty, "targetInAnyParty:", targetInAnyParty)

	if isSelf then
		if inviteButton then inviteButton.Visible = false end
		if kickButton then kickButton.Visible = false end

		if leaveButton then
			-- Fallback behavior: if no dedicated disband button exists, this button handles both.
			leaveButton.Visible = inParty and (not isLeader or disbandButton == nil)
			local leaveLabel = leaveButton:FindFirstChild("Status")
			if leaveLabel and leaveLabel:IsA("TextLabel") then
				leaveLabel.Text = isLeader and "DISBAND PARTY" or "LEAVE PARTY"
			end
			self._connections:track(leaveButton, "Activated", function()
				print("[PlayerList] LEAVE PARTY clicked by local player")
				self._export:emit("PartyLeave")
				self:_eagerClearParty()
				self:_hidePlayerShow()
				self:_clearSelection()
			end, "playerShow")
		end

		if disbandButton then
			disbandButton.Visible = inParty and isLeader
			local disbandLabel = disbandButton:FindFirstChild("Status")
			if disbandLabel and disbandLabel:IsA("TextLabel") then
				disbandLabel.Text = "DISBAND PARTY"
			end
			self._connections:track(disbandButton, "Activated", function()
				print("[PlayerList] DISBAND PARTY clicked by local player (leader)")
				self._export:emit("PartyLeave")
				self:_eagerClearParty()
				self:_hidePlayerShow()
				self:_clearSelection()
			end, "playerShow")
		end

		if inPartyDisplay then
			inPartyDisplay.Visible = inParty
			if inParty then
				local nameHolder = inPartyDisplay:FindFirstChild("NameHolder")
				if nameHolder then
					local username = nameHolder:FindFirstChild("Username")
					if username and username:IsA("TextLabel") then
						username.Text = isLeader and "PARTY LEADER" or "IN PARTY"
					end
					local icon = nameHolder:FindFirstChild("Icon")
					if icon and icon:IsA("TextLabel") then
						icon.Visible = true
						icon.Text = tostring(#self._partyState.members) .. "/" .. tostring(self._partyState.maxSize or 5)
					end
				end
			end
		end
	else
		if leaveButton then leaveButton.Visible = false end
		if disbandButton then disbandButton.Visible = false end

		local canInvite = not targetInMyParty
			and not targetInAnyParty
			and data.section ~= "InGame"
			and (not inParty or isLeader)

		if inviteButton then
			inviteButton.Visible = canInvite
			inviteButton.Active = true
			local statusLabel = inviteButton:FindFirstChild("Status")
			if statusLabel and statusLabel:IsA("TextLabel") then
				statusLabel.Text = "PARTY INVITE"
			end
			self._connections:track(inviteButton, "Activated", function()
				self:_sendPartyInvite(userId)
			end, "playerShow")
		end

		if kickButton then
			kickButton.Visible = targetInMyParty and isLeader
			self._connections:track(kickButton, "Activated", function()
				print("[PlayerList] KICK clicked: kicking userId", userId)
				self._export:emit("PartyKick", { targetUserId = userId })

				local kickedTracked = self._playersByUserId[userId]
				if kickedTracked then
					kickedTracked.inParty = false
				end
				self:_movePlayerToSection(userId, self._defaultSection, true)

				if self._partyState then
					local members = self._partyState.members
					local idx = table.find(members, userId)
					if idx then
						table.remove(members, idx)
					end
					if #members <= 1 then
						self:_eagerClearParty()
					end
				end

				self:_hidePlayerShow()
				self:_clearSelection()
			end, "playerShow")
		end

		if inPartyDisplay then
			inPartyDisplay.Visible = targetInAnyParty and not targetInMyParty
			if targetInAnyParty and not targetInMyParty then
				local nameHolder = inPartyDisplay:FindFirstChild("NameHolder")
				if nameHolder then
					local username = nameHolder:FindFirstChild("Username")
					if username and username:IsA("TextLabel") then
						username.Text = "CLOSED PARTY"
					end
					local icon = nameHolder:FindFirstChild("Icon")
					if icon and icon:IsA("TextLabel") then
						icon.Visible = false
					end
				end
			end
		end
	end

	self:_positionPlayerShow(userId)
	frame.Visible = true
end

function module:_positionPlayerShow(userId)
	local frame = self._playerShowFrame
	if not frame then
		return
	end

	local row = self._rows[userId]
	if not row then
		local lp = Players.LocalPlayer
		if lp and userId == lp.UserId then
			row = self._currentUserRow
		end
	end
	if not row or not row.frame then
		return
	end

	local uiAbsSize = self._ui.AbsoluteSize
	if uiAbsSize.Y == 0 then
		return
	end

	local uiScaleObj = self._ui:FindFirstChildWhichIsA("UIScale")
	local scaleFactor = uiScaleObj and uiScaleObj.Scale or 1

	local rowAbsY = row.frame.AbsolutePosition.Y
	local uiAbsY = self._ui.AbsolutePosition.Y

	local nudgeUp = 0.05
	local yScale = (rowAbsY - uiAbsY) / (uiAbsSize.Y * scaleFactor) - nudgeUp
	yScale = math.clamp(yScale, 0, 0.75)

	frame.Position = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, yScale, 0)
end

function module:_hidePlayerShow()
	if self._playerShowFrame then
		self._playerShowFrame.Visible = false
	end
	self._connections:cleanupGroup("playerShow")
end

function module:_sendPartyInvite(targetUserId)
	print("[PlayerList] _sendPartyInvite: inviting userId", targetUserId)
	self._export:emit("PartyInviteSend", { targetUserId = targetUserId })

	self:_hidePlayerShow()
	self:_clearSelection()
end

--------------------------------------------------------------------------------
-- PARTY NOTIFICATIONS  (uses PartyNotification.Folder templates)
--------------------------------------------------------------------------------

function module:_showPartyNotification(templateName, opts)
	opts = opts or {}
	self:_hidePartyNotification()

	local template = self._notifTemplates[templateName]
	if not template or not self._notifScreenGui then
		return
	end

	local clone = template:Clone()
	clone.Name = templateName .. "_Active"
	clone.Visible = true
	clone.Parent = self._notifScreenGui

	self._activeNotif = clone
	self._connections:cleanupGroup("partyNotif")

	local function findDescendantByNameAndClass(parent, name, class)
		for _, desc in parent:GetDescendants() do
			if desc.Name == name and desc:IsA(class) then
				return desc
			end
		end
		return nil
	end

	if opts.headerText then
		local headers = {}
		for _, desc in clone:GetDescendants() do
			if desc.Name == "Username" and desc:IsA("TextLabel") then
				table.insert(headers, desc)
			end
		end
		if headers[1] then
			headers[1].Text = opts.headerText
		end
	end

	if opts.bodyText then
		local bodies = {}
		for _, desc in clone:GetDescendants() do
			if desc.Name == "Username" and desc:IsA("TextLabel") then
				table.insert(bodies, desc)
			end
		end
		if bodies[2] then
			bodies[2].Text = opts.bodyText
		end
	end

	if opts.userId and opts.userId ~= 0 then
		local capturedClone = clone
		task.spawn(function()
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(
					opts.userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size420x420
				)
			end)
			if ok and content and self._activeNotif == capturedClone then
				local directImage = capturedClone:FindFirstChild("ImageLabel")
				if directImage and directImage:IsA("ImageLabel") then
					directImage.Image = content
				end
				for _, desc in capturedClone:GetDescendants() do
					if desc.Name == "PlayerImage" and desc:IsA("ImageLabel") then
						desc.Image = content
					end
				end
			end
		end)
	end

	if opts.onAccept or opts.onDecline then
		local acceptBtn = findDescendantByNameAndClass(clone, "Accept", "ImageButton")
		local declineBtn = findDescendantByNameAndClass(clone, "Decline", "ImageButton")
		local loadingHolder = findDescendantByNameAndClass(clone, "LoadingHolder", "Frame")

		if loadingHolder then
			loadingHolder.Visible = true
		end

		if acceptBtn and opts.onAccept then
			self._connections:track(acceptBtn, "Activated", function()
				opts.onAccept()
				self:_hidePartyNotification()
			end, "partyNotif")
		end
		if declineBtn and opts.onDecline then
			self._connections:track(declineBtn, "Activated", function()
				opts.onDecline()
				self:_hidePartyNotification()
			end, "partyNotif")
		end
	else
		local loadingHolder = findDescendantByNameAndClass(clone, "LoadingHolder", "Frame")
		if loadingHolder then
			loadingHolder.Visible = false
		end
	end

	local timeout = opts.timeout or 5
	self._notifTimerThread = task.delay(timeout, function()
		if self._activeNotif == clone then
			if opts.onTimeout then
				opts.onTimeout()
			end
			self:_hidePartyNotification()
		end
	end)
end

function module:_hidePartyNotification()
	if self._notifTimerThread then
		pcall(task.cancel, self._notifTimerThread)
		self._notifTimerThread = nil
	end
	self._connections:cleanupGroup("partyNotif")
	if self._activeNotif then
		self._activeNotif:Destroy()
		self._activeNotif = nil
	end
end

--------------------------------------------------------------------------------
-- PARTY EVENTS
--------------------------------------------------------------------------------

function module:_bindPartyEvents()
	self._connections:add(self._export:on("PartyInviteReceived", function(data)
		if not data or type(data) ~= "table" then
			return
		end
		local fromName = data.fromDisplayName or data.fromUsername or "Unknown"
		self:_showPartyNotification("PartyInvite", {
			headerText = "PARTY INVITE",
			bodyText = "party invite from " .. fromName,
			userId = data.fromUserId,
			timeout = data.timeout or 15,
			onAccept = function()
				self._export:emit("PartyInviteResponse", { accept = true })
			end,
			onDecline = function()
				self._export:emit("PartyInviteResponse", { accept = false })
			end,
			onTimeout = function()
				self._export:emit("PartyInviteResponse", { accept = false })
			end,
		})
	end), "partyEvents")

	self._connections:add(self._export:on("PartyUpdate", function(data)
		if data and type(data) == "table" then
			self:_onPartyUpdate(data)
		end
	end), "partyEvents")

	self._connections:add(self._export:on("PartyDisbanded", function(data)
		self:_onPartyDisbanded(data)
	end), "partyEvents")

	self._connections:add(self._export:on("PartyKicked", function(data)
		self:_onPartyKicked(data)
	end), "partyEvents")

	self._connections:add(self._export:on("PartyInviteBusy", function(data)
		self:_hidePartyNotification()
	end), "partyEvents")

	self._connections:add(self._export:on("PartyInviteDeclined", function(data)
		self:_hidePartyNotification()
	end), "partyEvents")

end

function module:_reconcilePartySections()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end

	local members = (self._partyState and self._partyState.members) or {}
	local memberSet = {}
	for _, uid in ipairs(members) do
		memberSet[uid] = true
	end

	for uid, tracked in pairs(self._playersByUserId) do
		local shouldBeInParty = memberSet[uid] == true
		tracked.inParty = shouldBeInParty
		local nextSection = shouldBeInParty and "InParty" or self._defaultSection
		if tracked.section ~= nextSection then
			self:_movePlayerToSection(uid, nextSection, true)
		else
			self:addPlayer(tracked)
		end
	end

	local localInParty = memberSet[localPlayer.UserId] == true
	if localInParty then
		self:_ensureLocalMirrorRow()
	else
		self:_destroyLocalMirrorRow()
	end

	self:_updateCurrentUserCard()

	if self._selectedUserId then
		local row = self._rows[self._selectedUserId]
		if row then
			self:_showPlayerShow(self._selectedUserId, row.data)
		end
	end

	self:_updateUserLeaveAction()
end

function module:_onPartyUpdate(data)
	local members = data.members or {}
	print("[PlayerList] _onPartyUpdate: partyId", data.partyId, "leader", data.leaderId, "members:", table.concat(members, ","))

	local oldMembers = self._partyState and self._partyState.members or {}
	local localPlayer = Players.LocalPlayer

	self._partyState = {
		partyId = data.partyId,
		leaderId = data.leaderId,
		members = members,
		maxSize = data.maxSize or 5,
	}
	self:_reconcilePartySections()

	if #oldMembers > 0 and localPlayer then
		local newSet = {}
		for _, uid in ipairs(members) do
			newSet[uid] = true
		end
		for _, uid in ipairs(oldMembers) do
			if not newSet[uid] and uid ~= localPlayer.UserId then
				local leftPlayer = Players:GetPlayerByUserId(uid)
				local displayName = leftPlayer and leftPlayer.DisplayName or ("Player " .. tostring(uid))
				self:_showPartyNotification("Left", {
					headerText = "PLAYER LEFT PARTY",
					bodyText = displayName .. " has left the party",
					userId = uid,
					timeout = 3,
				})
				break
			end
		end
	end
end

function module:_onPartyDisbanded(data)
	local leaderId = self._partyState and self._partyState.leaderId
	local oldMembers = self._partyState and self._partyState.members or {}
	print("[PlayerList] _onPartyDisbanded: clearing party, old members:", table.concat(oldMembers, ","))
	self._partyState = nil
	self:_reconcilePartySections()

	if self._selectedUserId then
		local row = self._rows[self._selectedUserId]
		if row then
			self:_showPlayerShow(self._selectedUserId, row.data)
		else
			self:_hidePlayerShow()
			self:_clearSelection()
		end
	end

	local leaderName = "The leader"
	if leaderId then
		local leaderPlayer = Players:GetPlayerByUserId(leaderId)
		if leaderPlayer then
			leaderName = leaderPlayer.DisplayName
		end
	end
	self:_showPartyNotification("Disband", {
		headerText = "PARTY DISBAND",
		bodyText = leaderName .. " has disbanded the party",
		userId = leaderId or 0,
		timeout = 3,
	})
end

function module:_onPartyKicked(data)
	local leaderId = self._partyState and self._partyState.leaderId
	local oldMembers = self._partyState and self._partyState.members or {}
	print("[PlayerList] _onPartyKicked: YOU WERE KICKED, clearing party, old members:", table.concat(oldMembers, ","))
	self._partyState = nil
	self:_reconcilePartySections()

	self:_hidePlayerShow()
	self:_clearSelection()

	local leaderName = "The leader"
	if leaderId then
		local leaderPlayer = Players:GetPlayerByUserId(leaderId)
		if leaderPlayer then
			leaderName = leaderPlayer.DisplayName
		end
	end
	self:_showPartyNotification("Kicked", {
		headerText = "KICKED FROM PARTY",
		bodyText = "kicked from party by " .. leaderName,
		userId = leaderId or 0,
		timeout = 3,
	})
end

function module:_eagerClearParty()
	if not self._partyState then
		return
	end

	local oldMembers = self._partyState.members or {}
	print("[PlayerList] _eagerClearParty: clearing party eagerly, old members:", table.concat(oldMembers, ","))
	self._partyState = nil
	self:_reconcilePartySections()
end

function module:_movePlayerToSection(userId, sectionId, force)
	local data = self._playersByUserId[userId]
	if not data then
		return
	end

	if data.sectionLocked and not force then
		return
	end

	data.section = sectionId
	data.inParty = sectionId == "InParty"
	self:addPlayer(data)
end

--------------------------------------------------------------------------------
-- LOCAL PLAYER MIRROR ROW  (keeps them visible in InLobby while also in InParty)
--------------------------------------------------------------------------------

function module:_ensureLocalMirrorRow()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end

	local data = self._playersByUserId[localPlayer.UserId]
	if not data then
		return
	end

	local sectionData = self._sections[self._defaultSection] or self._sections[DEFAULT_SECTION]
	if not sectionData or not sectionData.holder then
		return
	end

	if self._localMirrorRow and self._localMirrorRow.frame and self._localMirrorRow.frame.Parent then
		self._localMirrorRow.data = data
		self:_applyRowData(self._localMirrorRow)
		return
	end

	local template = self:_getRowTemplate(self._defaultSection)
	if not template then
		return
	end

	local frame = template:Clone()
	frame.Name = "User_Mirror_" .. tostring(localPlayer.UserId)
	frame.Visible = true
	frame.Parent = sectionData.holder
	frame.LayoutOrder = TweenConfig.Values.RowLayoutBaseOrder

	local mirrorData = {}
	for k, v in pairs(data) do
		mirrorData[k] = v
	end
	mirrorData.section = self._defaultSection

	local row = {
		userId = localPlayer.UserId,
		section = self._defaultSection,
		frame = frame,
		refs = self:_captureRowRefs(frame),
		data = mirrorData,
		hovered = false,
		selected = false,
		pulseToken = 0,
		glowTweens = {},
		isMirror = true,
	}

	self:_setGlowVisibility(row, false)
	self:_setGlowInstant(row, TweenConfig.Values.HiddenGlowTransparency)

	local groupName = "row_mirror_" .. tostring(localPlayer.UserId)
	if frame:IsA("GuiButton") then
		self._connections:track(frame, "Activated", function()
			self:_selectUser(localPlayer.UserId)
		end, groupName)
	else
		self._connections:track(frame, "InputBegan", function(input)
			local inputType = input.UserInputType
			if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
				self:_selectUser(localPlayer.UserId)
			end
		end, groupName)
	end

	self:_applyRowData(row)
	self._localMirrorRow = row

	self:_sortSection(self._defaultSection)
	self:_updateSectionCounts()
	self:_refreshCanvasSize()
end

function module:_destroyLocalMirrorRow()
	if not self._localMirrorRow then
		return
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer then
		self._connections:cleanupGroup("row_mirror_" .. tostring(localPlayer.UserId))
	end

	if self._localMirrorRow.frame and self._localMirrorRow.frame.Parent then
		self._localMirrorRow.frame:Destroy()
	end
	self._localMirrorRow = nil

	self:_updateSectionCounts()
	self:_refreshCanvasSize()
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

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
	self:_destroyLocalMirrorRow()
	self:_hidePlayerShow()
	self:_hidePartyNotification()
	self._partyState = nil
	self._connections:cleanupGroup("partyEvents")
	self._connections:cleanupGroup("userLeaveAction")
	if self._userLeaveInstance and self._userLeaveInstance.Parent then
		self._userLeaveInstance:Destroy()
	end
	self._userLeaveInstance = nil
end

return module
