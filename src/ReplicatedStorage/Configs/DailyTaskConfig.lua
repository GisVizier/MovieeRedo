--[[
	DailyTaskConfig

	Defines all task pools for the task system:
	  - Beginner: one-time onboarding tasks
	  - Daily: reset every 24 hours (UTC midnight)
	  - Bonus: repeatable after dailies are complete, progress persists across resets
]]

local DailyTaskConfig = {}

DailyTaskConfig.EVENT_TYPES = {
	ELIMINATION = "ELIMINATION",
	DUEL_PLAYED = "DUEL_PLAYED",
	DUEL_WON    = "DUEL_WON",
}

DailyTaskConfig.BeginnerTasks = {
	{
		id = "beginner_play_duel",
		name = "Play a Duel",
		eventType = "DUEL_PLAYED",
		target = 1,
		reward = 50,
	},
	{
		id = "beginner_eliminate_5",
		name = "Eliminate 5 Players",
		eventType = "ELIMINATION",
		target = 5,
		reward = 75,
	},
	{
		id = "beginner_win_duel",
		name = "Win a Duel",
		eventType = "DUEL_WON",
		target = 1,
		reward = 100,
	},
}

DailyTaskConfig.DailyTasks = {
	{
		id = "daily_play_5",
		name = "Play 5 Duels",
		eventType = "DUEL_PLAYED",
		target = 5,
		reward = 50,
	},
	{
		id = "daily_eliminate_15",
		name = "Eliminate 15 Players",
		eventType = "ELIMINATION",
		target = 15,
		reward = 75,
	},
	{
		id = "daily_win_2",
		name = "Win 2 Duels",
		eventType = "DUEL_WON",
		target = 2,
		reward = 100,
	},
}

DailyTaskConfig.BonusTasks = {
	{
		id = "bonus_play_12",
		name = "Play 12 Duels",
		eventType = "DUEL_PLAYED",
		target = 12,
		reward = 25,
	},
	{
		id = "bonus_eliminate_40",
		name = "Eliminate 40 Players",
		eventType = "ELIMINATION",
		target = 40,
		reward = 50,
	},
	{
		id = "bonus_win_12",
		name = "Win 12 Duels",
		eventType = "DUEL_WON",
		target = 12,
		reward = 75,
	},
}

function DailyTaskConfig.getUTCDayId(): string
	return os.date("!%Y-%m-%d", os.time())
end

return DailyTaskConfig
