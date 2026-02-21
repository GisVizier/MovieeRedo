--[[
	Leaderboard CoreUI Module
	
	Shows during match when Tab is pressed. Displays:
	- YOUR TEAM vs ENEMY TEAM
	- Per-player: Kills, Assists, Deaths (EAD), Damage (DMG)
	- Dead / Disconnected state
	
	Data sources:
	- MatchStart: team1, team2
	- RoundKill: killerId, victimId (kills/deaths)
	- RoundStart: clear dead state for new round
	- PlayerLeftMatch: mark disconnected
	- ReturnToLobby: clear all
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local module = {}
module.__index = module

local TOGGLE_KEY = Enum.KeyCode.Tab

local function resolveUserId(entry)
	if type(entry) == "number" then
		return entry
	end
	if type(entry) == "string" then
		return tonumber(entry)
	end
	if type(entry) == "table" then
		local raw = entry.userId or entry.UserId or entry.id or entry.Id or entry.playerId
		if type(raw) == "number" then return raw end
		if type(raw) == "string" then return tonumber(raw) end
	end
	return nil
end

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections

	self._holder = nil
	self._playerStatsFrame = nil
	self._yourTeamHolder = nil
	self._enemyTeamHolder = nil
	self._yourTeamTemplate = nil
	self._enemyTeamTemplate = nil

	self._yourTeam = {}
	self._enemyTeam = {}
	self._statsByUserId = {}
	self._deadThisRound = {}
	self._disconnectedByUserId = {}
	self._inMatch = false
	self._currentMatchId = nil
	self._yourTeamSlots = {}
	self._enemyTeamSlots = {}
	self._rowByUserId = {}

	self:_bindUi()
	self:_bindInput()
	self:_bindEvents()

	-- Start hidden
	self._ui.Visible = false

	return self
end

function module:_bindUi()
	local holder = self._ui:FindFirstChild("Holder")
	if not holder then return end

	self._holder = holder

	local frame = holder:FindFirstChild("Frame")
	if frame then
		local playerStats = frame:FindFirstChild("PlayerStats")
		if playerStats then
			self._playerStatsFrame = playerStats:FindFirstChild("PlayerStats")
		end

		local teamHolder = frame:FindFirstChild("TeamHolder")
		if teamHolder then
			local playerLbHolder = teamHolder:FindFirstChild("PlayerLeaderboredHolder")
			local enemyLbHolder = teamHolder:FindFirstChild("EnemyHolder")

			if playerLbHolder then
				self._yourTeamHolder = playerLbHolder
				self._yourTeamTemplate = playerLbHolder:FindFirstChild("TeamLeaderboredTemp")
			end

			if enemyLbHolder then
				self._enemyTeamHolder = enemyLbHolder
				self._enemyTeamTemplate = enemyLbHolder:FindFirstChild("EnemyLeaderboredTemp")
			end
		end
	end

	-- Hide templates (we clone them)
	if self._yourTeamTemplate then
		self._yourTeamTemplate.Visible = false
	end
	if self._enemyTeamTemplate then
		self._enemyTeamTemplate.Visible = false
	end
end

function module:_bindInput()
	self._connections:track(UserInputService, "InputBegan", function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode ~= TOGGLE_KEY then return end
		if UserInputService:GetFocusedTextBox() then return end

		-- Only show leaderboard during match
		if not self._inMatch then return end

		self:toggleVisibility()
	end, "input")

	self._connections:track(UserInputService, "InputEnded", function(input)
		if input.KeyCode ~= TOGGLE_KEY then return end
		-- Optionally hide on key release (toggle behavior - user presses again to hide)
		-- For hold-to-view: uncomment below
		-- if self._inMatch and self._ui.Visible then
		--     self:hide()
		-- end
	end, "input")
end

function module:_bindEvents()
	self._export:on("MatchStart", function(data)
		self:_onMatchStart(data)
	end)

	self._export:on("RoundStart", function(data)
		self:_onRoundStart(data)
	end)

	self._export:on("RoundKill", function(data)
		self:_onRoundKill(data)
	end)

	self._export:on("MatchStatsUpdate", function(data)
		self:_onMatchStatsUpdate(data)
	end)

	self._export:on("ScoreUpdate", function(data)
		self:_onScoreUpdate(data)
	end)

	self._export:on("PlayerLeftMatch", function(data)
		self:_onPlayerLeftMatch(data)
	end)

	self._export:on("ReturnToLobby", function()
		self:_onReturnToLobby()
	end)
end

function module:_teamHasUserId(teamEntries, userId)
	if type(teamEntries) ~= "table" or type(userId) ~= "number" then
		return false
	end
	for _, entry in ipairs(teamEntries) do
		local uid = resolveUserId(entry)
		if uid == userId then return true end
	end
	return false
end

function module:_onMatchStart(data)
	if type(data) ~= "table" then return end

	local matchId = data.matchId
	local isNewMatch = (matchId ~= nil and matchId ~= self._currentMatchId)

	if isNewMatch then
		-- New match: reset all stats so we don't carry over from previous match
		self._currentMatchId = matchId
		table.clear(self._statsByUserId)
		table.clear(self._deadThisRound)
		table.clear(self._disconnectedByUserId)
	end

	-- Apply server stats if included (kills, deaths, damage)
	if type(data.stats) == "table" then
		for rawUserId, s in pairs(data.stats) do
			local userId = tonumber(rawUserId) or rawUserId
			self._statsByUserId[userId] = {
				kills = s.kills or 0,
				deaths = s.deaths or 0,
				assists = 0,
				damage = s.damage or 0,
			}
		end
	end

	local team1 = data.team1 or {}
	local team2 = data.team2 or {}

	if type(team1) ~= "table" then team1 = {} end
	if type(team2) ~= "table" then team2 = {} end

	local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId or nil
	local yourTeam = team1
	local enemyTeam = team2

	if localUserId and self:_teamHasUserId(team2, localUserId) and not self:_teamHasUserId(team1, localUserId) then
		yourTeam = team2
		enemyTeam = team1
	end

	self._inMatch = true
	self._yourTeam = yourTeam
	self._enemyTeam = enemyTeam

	-- Same match, new round: keep stats, clear dead state (RoundStart handles that)
	self:_populateTeams()
end

function module:_onRoundStart(data)
	-- Clear dead state - everyone is revived for new round
	table.clear(self._deadThisRound)
	self:_refreshAllRows()
end

function module:_onRoundKill(data)
	if type(data) ~= "table" then return end

	-- Mark victim as dead this round (for death indicator)
	local victimId = data.victimId
	if victimId then
		self._deadThisRound[victimId] = true
	end

	-- Stats (kills/deaths) come from MatchStatsUpdate - server is source of truth
	self:_updateRowStats(data.killerId)
	self:_updateRowStats(victimId)
end

function module:_onMatchStatsUpdate(data)
	if type(data) ~= "table" or type(data.stats) ~= "table" then return end
	if data.matchId ~= self._currentMatchId then return end

	for rawUserId, s in pairs(data.stats) do
		-- Normalize to number (Roblox may serialize numeric keys as strings over RemoteEvent)
		local userId = tonumber(rawUserId) or rawUserId
		self._statsByUserId[userId] = {
			kills = s.kills or 0,
			deaths = s.deaths or 0,
			assists = 0,
			damage = s.damage or 0,
		}
		self:_updateRowStats(userId)
	end
	-- Refresh all rows to catch any key mismatches and ensure UI is in sync
	self:_refreshAllRows()
end

function module:_onScoreUpdate(data)
	-- Team scores could be shown in header if desired
end

function module:_onPlayerLeftMatch(data)
	if type(data) ~= "table" then return end

	local userId = data.playerId or data.userId
	if not userId then return end

	self._disconnectedByUserId[userId] = true
	self:_updateRowStats(userId)
end

function module:_onReturnToLobby()
	self._inMatch = false
	self._currentMatchId = nil
	table.clear(self._yourTeam)
	table.clear(self._enemyTeam)
	table.clear(self._statsByUserId)
	table.clear(self._deadThisRound)
	table.clear(self._disconnectedByUserId)

	self:_clearAllRows()
	self:hide()
end

function module:_getRowHolder(template, parentHolder)
	if not template or not parentHolder then return nil end

	-- Find the Holder inside the template that contains the row structure
	local canvasGroup = template:FindFirstChild("CanvasGroup")
	local holder = canvasGroup and canvasGroup:FindFirstChild("Holder")
	if not holder then return nil end

	-- The parent for rows is PlayerHolder or similar
	local rowParent = holder:FindFirstChild("PlayerHolder")
	if not rowParent then
		rowParent = holder
	end

	return rowParent
end

function module:_getOrCreateSlot(template, parentHolder, slots, index)
	if not template or not parentHolder then return nil end

	local rowParent = self:_getRowHolder(template, parentHolder)
	if not rowParent then return nil end

	-- Ensure we have enough slots
	while #slots < index do
		local clone = template:Clone()
		clone.Name = "Row_" .. (#slots + 1)
		clone.Visible = true
		clone.Parent = parentHolder
		table.insert(slots, clone)
	end

	return slots[index]
end

function module:_populateTeams()
	-- Clear existing rows
	self:_clearAllRows()

	local yourTemplate = self._yourTeamTemplate
	local enemyTemplate = self._enemyTeamTemplate
	local yourParent = self._yourTeamHolder
	local enemyParent = self._enemyTeamHolder

	if not yourTemplate or not yourParent or not enemyTemplate or not enemyParent then
		return
	end

	local yourRowParent = self:_getRowHolder(yourTemplate, yourParent)
	local enemyRowParent = self:_getRowHolder(enemyTemplate, enemyParent)

	if not yourRowParent or not enemyRowParent then return end

	-- Clear existing children (except template)
	for _, child in yourParent:GetChildren() do
		if child ~= yourTemplate and child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, child in enemyParent:GetChildren() do
		if child ~= enemyTemplate and child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	table.clear(self._yourTeamSlots)
	table.clear(self._enemyTeamSlots)
	table.clear(self._rowByUserId)

	-- Create rows for your team
	for i, entry in ipairs(self._yourTeam) do
		local userId = resolveUserId(entry)
		if userId then
			local clone = yourTemplate:Clone()
			clone.Name = "YourTeam_" .. userId
			clone.Visible = true
			clone.Parent = yourParent
			clone.LayoutOrder = i
			table.insert(self._yourTeamSlots, clone)
			self._rowByUserId[userId] = { slot = clone, team = "yours" }
			self:_applyRowData(clone, userId, i)
		end
	end

	-- Create rows for enemy team
	for i, entry in ipairs(self._enemyTeam) do
		local userId = resolveUserId(entry)
		if userId then
			local clone = enemyTemplate:Clone()
			clone.Name = "EnemyTeam_" .. userId
			clone.Visible = true
			clone.Parent = enemyParent
			clone.LayoutOrder = i
			table.insert(self._enemyTeamSlots, clone)
			self._rowByUserId[userId] = { slot = clone, team = "enemy" }
			self:_applyRowData(clone, userId, i)
		end
	end

	-- Update current player card in PlayerStats if present
	self:_updateCurrentPlayerCard()
end

function module:_findRowElements(slot)
	-- Structure: slot -> CanvasGroup -> Holder -> PlayerHolder (main row)
	--   PlayerHolder has: usernameHolder, EAD, DmgHolder, PlayerHolder (inner: PlayerImage, Died, Disconnected)
	--   Holder has: Placement
	local cg = slot:FindFirstChild("CanvasGroup")
	local holder = cg and cg:FindFirstChild("Holder")
	local mainRow = holder and holder:FindFirstChild("PlayerHolder")
	if not mainRow then return {} end

	local innerPlayerHolder = mainRow:FindFirstChild("PlayerHolder")
	local usernameHolder = mainRow:FindFirstChild("usernameHolder")
	local ead = mainRow:FindFirstChild("EAD")
	local dmgHolder = mainRow:FindFirstChild("DmgHolder")
	local placement = holder:FindFirstChild("Placement")

	return {
		displayName = usernameHolder and usernameHolder:FindFirstChild("DisplayName"),
		username = usernameHolder and usernameHolder:FindFirstChild("Username"),
		kills = ead and ead:FindFirstChild("Kills"),
		assist = ead and ead:FindFirstChild("Assist"),
		death = ead and ead:FindFirstChild("Death"),
		dmg = dmgHolder and dmgHolder:FindFirstChild("Dmg"),
		playerImage = innerPlayerHolder and innerPlayerHolder:FindFirstChild("PlayerImage"),
		died = innerPlayerHolder and innerPlayerHolder:FindFirstChild("Died"),
		disconnected = innerPlayerHolder and innerPlayerHolder:FindFirstChild("Disconnected"),
		placement = placement and placement:FindFirstChild("Text"),
	}
end

function module:_applyRowData(slot, userId, placementIndex)
	local player = Players:GetPlayerByUserId(userId)
	local displayName = player and player.DisplayName or ("Player " .. tostring(userId))
	local username = player and player.Name or ""

	local stats = self._statsByUserId[userId] or { kills = 0, deaths = 0, assists = 0, damage = 0 }
	local kills = stats.kills or 0
	local deaths = stats.deaths or 0
	local assists = stats.assists or 0
	local damage = stats.damage or 0
	local isDead = self._deadThisRound[userId] == true
	local isDisconnected = self._disconnectedByUserId[userId] == true

	local refs = self:_findRowElements(slot)
	if refs.displayName and refs.displayName:IsA("TextLabel") then
		refs.displayName.Text = displayName
	end
	if refs.username and refs.username:IsA("TextLabel") then
		refs.username.Text = "@" .. username
	end
	if refs.kills and refs.kills:IsA("TextLabel") then
		refs.kills.Text = tostring(kills)
	end
	if refs.assist and refs.assist:IsA("TextLabel") then
		refs.assist.Text = tostring(assists)
	end
	if refs.death and refs.death:IsA("TextLabel") then
		refs.death.Text = tostring(deaths)
	end
	if refs.dmg and refs.dmg:IsA("TextLabel") then
		refs.dmg.Text = tostring(damage)
	end
	if placementIndex and refs.placement and refs.placement:IsA("TextLabel") then
		refs.placement.Text = tostring(placementIndex)
	end

	if refs.died and refs.died:IsA("GuiObject") then
		refs.died.Visible = isDead
	end
	if refs.disconnected and refs.disconnected:IsA("GuiObject") then
		refs.disconnected.Visible = isDisconnected
	end

	-- Thumbnail
	if refs.playerImage and refs.playerImage:IsA("ImageLabel") then
		task.spawn(function()
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
			end)
			if ok and content and self._rowByUserId[userId] then
				refs.playerImage.Image = content
			end
		end)
	end
end

function module:_updateRowStats(userId)
	local rowData = self._rowByUserId[userId]
	if not rowData then return end

	self:_applyRowData(rowData.slot, userId, nil)
end

function module:_refreshAllRows()
	for userId, rowData in pairs(self._rowByUserId) do
		local placement = 0
		for i, entry in ipairs(self._yourTeam) do
			if resolveUserId(entry) == userId then placement = i break end
		end
		if placement == 0 then
			for i, entry in ipairs(self._enemyTeam) do
				if resolveUserId(entry) == userId then placement = i break end
			end
		end
		self:_applyRowData(rowData.slot, userId, placement)
	end
end

function module:_updateCurrentPlayerCard()
	if not self._playerStatsFrame then return end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then return end

	local userId = localPlayer.UserId
	local stats = self._statsByUserId[userId] or { kills = 0, deaths = 0, assists = 0, damage = 0 }

	local displayName = self._playerStatsFrame:FindFirstChild("DisplayName")
	local username = self._playerStatsFrame:FindFirstChild("Username")

	if displayName and displayName:IsA("TextLabel") then
		displayName.Text = localPlayer.DisplayName or localPlayer.Name
	end
	if username and username:IsA("TextLabel") then
		username.Text = "@" .. localPlayer.Name
	end

	-- Current player thumbnail
	local playerImage = self._playerStatsFrame:FindFirstChild("PlayerImage", true)
	if playerImage and playerImage:IsA("ImageLabel") then
		task.spawn(function()
			local ok, content = pcall(function()
				return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
			end)
			if ok and content then
				playerImage.Image = content
			end
		end)
	end
end

function module:_clearAllRows()
	for _, slot in ipairs(self._yourTeamSlots) do
		if slot and slot.Parent then
			slot:Destroy()
		end
	end
	for _, slot in ipairs(self._enemyTeamSlots) do
		if slot and slot.Parent then
			slot:Destroy()
		end
	end
	table.clear(self._yourTeamSlots)
	table.clear(self._enemyTeamSlots)
	table.clear(self._rowByUserId)
end

function module:toggleVisibility()
	if self._ui.Visible then
		self:hide()
	else
		self:show()
	end
end

function module:show()
	if not self._inMatch then return false end
	self._ui.Visible = true
	self._export:setModuleState("Leaderboard", true)
	return true
end

function module:hide()
	self._ui.Visible = false
	self._export:setModuleState("Leaderboard", false)
	return true
end

function module:_cleanup()
	self:_onReturnToLobby()
end

return module
