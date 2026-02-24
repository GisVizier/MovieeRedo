--[[
	DailyTaskService

	Server-authoritative task system with three tiers:
	  Beginner  – one-time onboarding tasks (persist forever)
	  Daily     – reset every UTC day
	  Bonus     – repeatable after all dailies claimed; progress persists across daily resets

	Public API used by other services:
	  DailyTaskService:RecordEvent(player, eventType)
	    eventType: "ELIMINATION" | "DUEL_PLAYED" | "DUEL_WON"

	Integration points:
	  MatchManager  – DUEL_PLAYED (match created), DUEL_WON (match won), ELIMINATION (kill)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyTaskConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DailyTaskConfig"))

local DailyTaskService = {}

DailyTaskService._registry = nil
DailyTaskService._net = nil

function DailyTaskService:Init(registry, net)
	self._registry = registry
	self._net = net

	self._net:ConnectServer("TasksRequest", function(player)
		self:_sendTaskState(player)
	end)

	self._net:ConnectServer("TaskClaimReward", function(player, taskId)
		self:_claimReward(player, taskId)
	end)
end

function DailyTaskService:Start()
	local function onPlayerReady(player)
		if player:GetAttribute("Data_Loaded") then
			self:_sendTaskState(player)
			return
		end
		local conn
		conn = player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
			if player:GetAttribute("Data_Loaded") then
				conn:Disconnect()
				self:_sendTaskState(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerReady)
	for _, player in Players:GetPlayers() do
		task.defer(onPlayerReady, player)
	end
end

--------------------------------------------------------------------------------
-- DATA HELPERS
--------------------------------------------------------------------------------

local function getData(player)
	local ProfileHandler = require(game:GetService("ServerScriptService")
		:WaitForChild("Data"):WaitForChild("ProfileHandler"))
	local replica = ProfileHandler.GetReplica(player)
	if not replica then return nil end
	return replica.Data
end

local function setPath(player, path, value)
	local ProfileHandler = require(game:GetService("ServerScriptService")
		:WaitForChild("Data"):WaitForChild("ProfileHandler"))
	ProfileHandler.SetData(player, path, value)
end

local function ensureTasksTable(data)
	if not data.TASKS then
		data.TASKS = {
			beginnerProgress = {},
			beginnerClaimed  = {},
			beginnerComplete = false,
			dailyDayId       = "",
			dailyProgress    = {},
			dailyClaimed     = {},
			bonusProgress    = {},
			bonusClaimed     = {},
		}
	end
	return data.TASKS
end

--------------------------------------------------------------------------------
-- DAILY RESET
--------------------------------------------------------------------------------

function DailyTaskService:_ensureDailyFresh(player, tasks)
	local today = DailyTaskConfig.getUTCDayId()
	if tasks.dailyDayId == today then return end

	setPath(player, { "TASKS", "dailyDayId" },    today)
	setPath(player, { "TASKS", "dailyProgress" }, {})
	setPath(player, { "TASKS", "dailyClaimed" },  {})

	tasks.dailyDayId    = today
	tasks.dailyProgress = {}
	tasks.dailyClaimed  = {}
end

--------------------------------------------------------------------------------
-- RECORD EVENT (called by MatchManager / CombatService)
--------------------------------------------------------------------------------

function DailyTaskService:RecordEvent(player, eventType)
	if not player or not player:IsA("Player") then return end

	local data = getData(player)
	if not data then return end

	local tasks = ensureTasksTable(data)
	self:_ensureDailyFresh(player, tasks)

	local changed = false

	if not tasks.beginnerComplete then
		changed = self:_incrementTier(player, tasks, "beginner", eventType) or changed
	end

	changed = self:_incrementTier(player, tasks, "daily", eventType) or changed
	changed = self:_incrementTier(player, tasks, "bonus", eventType) or changed

	if changed then
		self:_sendTaskState(player)
	end
end

function DailyTaskService:_incrementTier(player, tasks, tier, eventType)
	local pool
	if tier == "beginner" then
		pool = DailyTaskConfig.BeginnerTasks
	elseif tier == "daily" then
		pool = DailyTaskConfig.DailyTasks
	elseif tier == "bonus" then
		pool = DailyTaskConfig.BonusTasks
	end
	if not pool then return false end

	local progressKey = tier .. "Progress"
	local claimedKey  = tier .. "Claimed"
	local progress = tasks[progressKey] or {}
	local claimed  = tasks[claimedKey]  or {}
	local anyChanged = false

	for _, taskDef in pool do
		if taskDef.eventType == eventType and not claimed[taskDef.id] then
			local current = progress[taskDef.id] or 0
			if current < taskDef.target then
				local newVal = math.min(current + 1, taskDef.target)
				progress[taskDef.id] = newVal
				setPath(player, { "TASKS", progressKey, taskDef.id }, newVal)
				anyChanged = true
			end
		end
	end

	return anyChanged
end

--------------------------------------------------------------------------------
-- CLAIM REWARD
--------------------------------------------------------------------------------

function DailyTaskService:_claimReward(player, taskId)
	if type(taskId) ~= "string" then return end

	local data = getData(player)
	if not data then return end

	local tasks = ensureTasksTable(data)
	self:_ensureDailyFresh(player, tasks)

	local taskDef, tier = self:_findTask(taskId)
	if not taskDef then return end

	local progressKey = tier .. "Progress"
	local claimedKey  = tier .. "Claimed"
	local progress = tasks[progressKey] or {}
	local claimed  = tasks[claimedKey]  or {}

	if claimed[taskId] then return end

	local current = progress[taskId] or 0
	if current < taskDef.target then return end

	claimed[taskId] = true
	setPath(player, { "TASKS", claimedKey, taskId }, true)

	local ProfileHandler = require(game:GetService("ServerScriptService")
		:WaitForChild("Data"):WaitForChild("ProfileHandler"))
	ProfileHandler.IncrementData(player, "GEMS", taskDef.reward)

	if tier == "beginner" then
		self:_checkBeginnerComplete(player, tasks)
	end

	if tier == "bonus" then
		self:_checkBonusReset(player, tasks)
	end

	self:_sendTaskState(player)
end

function DailyTaskService:_findTask(taskId)
	for _, def in DailyTaskConfig.BeginnerTasks do
		if def.id == taskId then return def, "beginner" end
	end
	for _, def in DailyTaskConfig.DailyTasks do
		if def.id == taskId then return def, "daily" end
	end
	for _, def in DailyTaskConfig.BonusTasks do
		if def.id == taskId then return def, "bonus" end
	end
	return nil, nil
end

function DailyTaskService:_checkBeginnerComplete(player, tasks)
	for _, def in DailyTaskConfig.BeginnerTasks do
		if not tasks.beginnerClaimed[def.id] then
			return
		end
	end
	tasks.beginnerComplete = true
	setPath(player, { "TASKS", "beginnerComplete" }, true)
end

function DailyTaskService:_checkBonusReset(player, tasks)
	local allClaimed = true
	for _, def in DailyTaskConfig.BonusTasks do
		if not tasks.bonusClaimed[def.id] then
			allClaimed = false
			break
		end
	end
	if allClaimed then
		setPath(player, { "TASKS", "bonusProgress" }, {})
		setPath(player, { "TASKS", "bonusClaimed" },  {})
		tasks.bonusProgress = {}
		tasks.bonusClaimed  = {}
	end
end

--------------------------------------------------------------------------------
-- SEND STATE TO CLIENT
--------------------------------------------------------------------------------

function DailyTaskService:_sendTaskState(player)
	local data = getData(player)
	if not data then return end

	local tasks = ensureTasksTable(data)
	self:_ensureDailyFresh(player, tasks)

	local allDailiesClaimed = true
	for _, def in DailyTaskConfig.DailyTasks do
		if not tasks.dailyClaimed[def.id] then
			allDailiesClaimed = false
			break
		end
	end

	local payload = {
		beginnerComplete = tasks.beginnerComplete,
		beginnerProgress = tasks.beginnerProgress,
		beginnerClaimed  = tasks.beginnerClaimed,
		dailyProgress    = tasks.dailyProgress,
		dailyClaimed     = tasks.dailyClaimed,
		bonusProgress    = tasks.bonusProgress,
		bonusClaimed     = tasks.bonusClaimed,
		allDailiesClaimed = allDailiesClaimed,
	}

	self._net:FireClient("TasksUpdate", player, payload)
end

return DailyTaskService
