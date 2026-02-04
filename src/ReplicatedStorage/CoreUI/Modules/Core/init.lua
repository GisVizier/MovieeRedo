local Players = game:GetService("Players")

local module = {}
module.__index = module

function module.start(export, _ui)
	local self = setmetatable({}, module)

	self._export = export
	self._connections = export.connections

	self._roundNumber = export:getInstance("HUD.Counter.Timer.RoundNumber")
	self._redScoreText = export:getInstance("HUD.Counter.RedScore.Text")
	self._blueScoreText = export:getInstance("HUD.Counter.BlueScore.Text")

	self._yourTeam = export:getInstance("HUD.Counter.YourTeam")
	self._enemyTeam = export:getInstance("HUD.Counter.EnemyTeam")

	self._yourTeamTemplate = self:_getPlayerTemplate(self._yourTeam)
	self._enemyTeamTemplate = self:_getPlayerTemplate(self._enemyTeam)

	self._yourTeamSlots = {}
	self._enemyTeamSlots = {}

	self._team1 = {}
	self._team2 = {}

	self:_setupListeners()

	return self
end

function module:_setupListeners()
	self._export:on("MatchStart", function(matchData)
		self:_onMatchStart(matchData)
	end)

	self._export:on("RoundStart", function(data)
		self:_onRoundStart(data)
	end)

	self._export:on("ScoreUpdate", function(data)
		self:_onScoreUpdate(data)
	end)

	self._export:on("ReturnToLobby", function()
		self:_clearTeams()
	end)
end

function module:_getPlayerTemplate(teamFrame)
	if not teamFrame then
		return nil
	end

	for _, child in ipairs(teamFrame:GetChildren()) do
		if child.Name == "PlayerHolder" and child:IsA("GuiObject") then
			child.Visible = false
			return child
		end
	end

	return nil
end

function module:_onMatchStart(matchData)
	if typeof(matchData) ~= "table" then
		return
	end

	self._team1 = matchData.team1 or {}
	self._team2 = matchData.team2 or {}

	self:_populateTeams()
end

function module:_populateTeams()
	local localPlayer = Players.LocalPlayer
	local localUserId = localPlayer and localPlayer.UserId or nil

	local localIsTeam1 = localUserId and table.find(self._team1, localUserId) ~= nil
	local localIsTeam2 = localUserId and table.find(self._team2, localUserId) ~= nil

	local yourTeamIds = self._team1
	local enemyTeamIds = self._team2

	if localIsTeam2 and not localIsTeam1 then
		yourTeamIds = self._team2
		enemyTeamIds = self._team1
	end

	self:_populateTeam(self._yourTeam, self._yourTeamTemplate, self._yourTeamSlots, yourTeamIds)
	self:_populateTeam(self._enemyTeam, self._enemyTeamTemplate, self._enemyTeamSlots, enemyTeamIds)
end

function module:_onRoundStart(data)
	if self._roundNumber and data and data.roundNumber then
		self._roundNumber.Text = tostring(data.roundNumber)
	end
end

function module:_onScoreUpdate(data)
	if not data then
		return
	end

	if self._redScoreText and data.team1Score ~= nil then
		self._redScoreText.Text = tostring(data.team1Score)
	end
	if self._blueScoreText and data.team2Score ~= nil then
		self._blueScoreText.Text = tostring(data.team2Score)
	end
end

function module:_populateTeam(teamFrame, template, slotCache, userIds)
	if not teamFrame or not template or type(userIds) ~= "table" then
		return
	end

	for i = #slotCache + 1, #userIds do
		local clone = template:Clone()
		clone.Visible = true
		clone.Parent = teamFrame
		table.insert(slotCache, clone)
	end

	for i = #slotCache, #userIds + 1, -1 do
		slotCache[i]:Destroy()
		table.remove(slotCache, i)
	end

	for i, userId in ipairs(userIds) do
		local holder = slotCache[i]
		if holder then
			self:_setPlayerThumbnail(holder, userId)
		end
	end
end

function module:_setPlayerThumbnail(holder, userId)
	if not holder or not userId then
		return
	end

	local image = holder:FindFirstChild("PlayerImage", true)
	if not image or not image:IsA("ImageLabel") then
		return
	end

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)
		if success and content then
			image.Image = content
		end
	end)
end

function module:_clearTeams()
	self:_clearSlots(self._yourTeamSlots)
	self:_clearSlots(self._enemyTeamSlots)
end

function module:_clearSlots(slotCache)
	for i = #slotCache, 1, -1 do
		slotCache[i]:Destroy()
		table.remove(slotCache, i)
	end
end

function module:_cleanup()
	self:_clearTeams()
	self._team1 = {}
	self._team2 = {}
end

return module
