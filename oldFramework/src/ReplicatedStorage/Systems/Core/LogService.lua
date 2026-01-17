local LogService = {}

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)

local TestMode = nil
local function getTestMode()
	if not TestMode then
		TestMode = require(Locations.Modules.TestMode)
	end
	return TestMode
end

LogService.LogLevel = {
	TRACE = 1,
	DEBUG = 2,
	INFO = 3,
	WARN = 4,
	ERROR = 5,
	FATAL = 6,
}

LogService.LogLevelNames = {
	[1] = "TRACE",
	[2] = "DEBUG",
	[3] = "INFO",
	[4] = "WARN",
	[5] = "ERROR",
	[6] = "FATAL",
}

LogService.LogLevelColors = {
	[1] = Color3.new(0.7, 0.7, 0.7),
	[2] = Color3.new(0.5, 0.8, 1),
	[3] = Color3.new(1, 1, 1),
	[4] = Color3.new(1, 0.8, 0.2),
	[5] = Color3.new(1, 0.4, 0.4),
	[6] = Color3.new(0.8, 0.2, 0.8),
}

LogService.Settings = {
	MinLogLevel = LogService.LogLevel.INFO,
	MaxLogEntries = 1000, -- Maximum entries to keep in memory
	IncludeTimestamp = true,
	IncludeLogLevel = true,
	IncludeSource = true,
	LogToRobloxOutput = true,
	LogToMemory = true,
	AutoFlushInterval = 60,
}

LogService.LogEntries = {}
LogService.LogCount = 0
LogService.StartTime = tick()
LogService.LastFlushTime = tick()

LogService.Categories = {}
LogService.FilteredCategories = {}
LogService.PerformanceMetrics = {
	TotalLogs = 0,
	LogsByLevel = {},
	LogsByCategory = {},
	ErrorCount = 0,
	WarnCount = 0,
}

function LogService:Init()
	for level = 1, 6 do
		self.PerformanceMetrics.LogsByLevel[level] = 0
	end

	if self.Settings.AutoFlushInterval > 0 then
		self:StartAutoFlush()
	end

	self:Info("LogService", "Logging system initialized", {
		MinLogLevel = self.LogLevelNames[self.Settings.MinLogLevel],
		MaxLogEntries = self.Settings.MaxLogEntries,
	})
end

function LogService:StartAutoFlush()
	RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - self.LastFlushTime > self.Settings.AutoFlushInterval then
			self:FlushOldEntries()
			self.LastFlushTime = currentTime
		end
	end)
end

function LogService:Log(level, category, message, data, source)
	-- CHECK TESTMODE
	local testMode = getTestMode()
	local isServer = RunService:IsServer()
	local isClient = RunService:IsClient()

	-- ALWAYS SHOW WARNINGS AND ERRORS
	if isClient and not testMode.CLIENT_LOGGING_ENABLED then
		if level < self.LogLevel.WARN then
			return
		end
	end
	if isServer and not testMode.SERVER_LOGGING_ENABLED then
		if level < self.LogLevel.WARN then
			return
		end
	end

	if level < self.Settings.MinLogLevel then
		return
	end

	if category and self.FilteredCategories[category] then
		return
	end

	if level <= self.LogLevel.DEBUG and not testMode:IsDebugLoggingEnabled() then
		return
	end

	local timestamp = tick() - self.StartTime
	local entry = {
		Level = level,
		LevelName = self.LogLevelNames[level],
		Category = category or "GENERAL",
		Message = message or "",
		Data = data,
		Source = source or self:GetCallerInfo(),
		Timestamp = timestamp,
		RealTime = os.date("%H:%M:%S"),
		ID = self.LogCount + 1,
	}

	self.LogCount = self.LogCount + 1
	self.PerformanceMetrics.TotalLogs = self.PerformanceMetrics.TotalLogs + 1
	self.PerformanceMetrics.LogsByLevel[level] = (self.PerformanceMetrics.LogsByLevel[level] or 0) + 1

	if category then
		self.PerformanceMetrics.LogsByCategory[category] = (self.PerformanceMetrics.LogsByCategory[category] or 0) + 1
	end

	if level == self.LogLevel.ERROR or level == self.LogLevel.FATAL then
		self.PerformanceMetrics.ErrorCount = self.PerformanceMetrics.ErrorCount + 1
	elseif level == self.LogLevel.WARN then
		self.PerformanceMetrics.WarnCount = self.PerformanceMetrics.WarnCount + 1
	end

	if self.Settings.LogToMemory then
		table.insert(self.LogEntries, entry)

		if #self.LogEntries > self.Settings.MaxLogEntries then
			table.remove(self.LogEntries, 1)
		end
	end

	if self.Settings.LogToRobloxOutput then
		self:OutputToConsole(entry)
	end

	return entry
end

function LogService:OutputToConsole(entry)
	-- Check TestMode for detailed data setting
	local testMode = getTestMode()
	local includeData = testMode and testMode.Logging and testMode.Logging.ShowDetailedData or false
	local output = self:FormatLogEntry(entry, includeData)

	if entry.Level >= self.LogLevel.ERROR then
		error(output)
	elseif entry.Level == self.LogLevel.WARN then
		warn(output)
	else
		print(output)
	end
end

function LogService:FormatLogEntry(entry, includeData)
	local parts = {}

	local isServer = RunService:IsServer()
	local environment = isServer and "Server" or "Client"
	table.insert(parts, string.format("[%s]", environment))

	if self.Settings.IncludeTimestamp then
		table.insert(parts, string.format("[%s]", entry.RealTime))
	end

	table.insert(parts, entry.Message)

	if self.Settings.IncludeSource and entry.Source and entry.Source ~= "" then
		table.insert(parts, string.format("- %s", entry.Source))
	end

	local output = table.concat(parts, " ")

	-- Include detailed data if enabled in TestMode
	if includeData and entry.Data then
		local dataStr = self:SerializeData(entry.Data)
		output = output .. "\n  Data: " .. dataStr
	end

	return output
end

function LogService:SerializeData(data)
	if type(data) == "table" then
		local success, result = pcall(function()
			return HttpService:JSONEncode(data)
		end)
		return success and result or tostring(data)
	else
		return tostring(data)
	end
end

function LogService:GetCallerInfo()
	-- FIND CALLER INFO
	local info = debug.traceback()
	local lines = string.split(info, "\n")

	local testMode = getTestMode()
	local showDebug = testMode and testMode.ENABLED and false

	if showDebug then
		print("=== DEBUG TRACEBACK ===")
		for i, line in ipairs(lines) do
			print(i, line)
		end
		print("=======================")
	end

	-- SKIP INTERNAL CALLS
	for _i, line in ipairs(lines) do
		if line and not string.find(line, "LogService") and not string.find(line, "TestMode") then
			local scriptMatch = string.match(line, "Script '([^']+)'")
			if scriptMatch then
				local lineMatch = string.match(line, "Line (%d+)")
				local shortName = string.match(scriptMatch, "([^%.]+)$") or scriptMatch
				if showDebug then
					print("Found script:", shortName, "line:", lineMatch)
				end
				return lineMatch and (shortName .. ":" .. lineMatch) or shortName
			end

			local moduleMatch = string.match(line, "ModuleScript '([^']+)'")
			if moduleMatch then
				local lineMatch = string.match(line, "Line (%d+)")
				local shortName = string.match(moduleMatch, "([^%.]+)$") or moduleMatch
				if showDebug then
					print("Found module:", shortName, "line:", lineMatch)
				end
				return lineMatch and (shortName .. ":" .. lineMatch) or shortName
			end

			local localScriptMatch = string.match(line, "LocalScript '([^']+)'")
			if localScriptMatch then
				local lineMatch = string.match(line, "Line (%d+)")
				local shortName = string.match(localScriptMatch, "([^%.]+)$") or localScriptMatch
				if showDebug then
					print("Found local script:", shortName, "line:", lineMatch)
				end
				return lineMatch and (shortName .. ":" .. lineMatch) or shortName
			end

			-- FALLBACK TO FOLDERS
			if
				string.find(line, "Services")
				or string.find(line, "Controllers")
				or string.find(line, "Utils")
				or string.find(line, "Modules")
			then
				if string.find(line, "Services") then
					return "Services"
				elseif string.find(line, "Controllers") then
					return "Controllers"
				elseif string.find(line, "Utils") then
					return "Utils"
				elseif string.find(line, "Modules") then
					return "Modules"
				end
			end
		end
	end

	return ""
end

function LogService:Trace(category, message, data)
	return self:Log(self.LogLevel.TRACE, category, message, data)
end

function LogService:Debug(category, message, data)
	return self:Log(self.LogLevel.DEBUG, category, message, data)
end

-- Conditional debug logging based on TestMode flags
-- Only logs if the specified TestMode.Logging flag is enabled
function LogService:ConditionalDebug(category, message, data, testModeFlag)
	local testMode = getTestMode()
	if testMode and testMode.Logging and testModeFlag then
		if not testMode.Logging[testModeFlag] then
			return -- Skip logging if flag is not enabled
		end
	end
	return self:Debug(category, message, data)
end

-- Conditional info logging based on TestMode flags
-- Only logs if the specified TestMode.Logging flag is enabled
function LogService:ConditionalInfo(category, message, data, testModeFlag)
	local testMode = getTestMode()
	if testMode and testMode.Logging and testModeFlag then
		if not testMode.Logging[testModeFlag] then
			return -- Skip logging if flag is not enabled
		end
	end
	return self:Info(category, message, data)
end

function LogService:Info(category, message, data)
	return self:Log(self.LogLevel.INFO, category, message, data)
end

function LogService:Warn(category, message, data)
	return self:Log(self.LogLevel.WARN, category, message, data)
end

function LogService:Error(category, message, data)
	return self:Log(self.LogLevel.ERROR, category, message, data)
end

function LogService:Fatal(category, message, data)
	return self:Log(self.LogLevel.FATAL, category, message, data)
end

function LogService:StartTimer(category, name)
	local startTime = tick()
	return {
		Category = category,
		Name = name,
		StartTime = startTime,
		Stop = function(timer)
			local duration = tick() - timer.StartTime
			LogService:Debug(timer.Category, string.format("Timer '%s' completed", timer.Name), {
				Duration = string.format("%.3fms", duration * 1000),
			})
			return duration
		end,
	}
end

function LogService:LogPerformance(category, operation, duration, details)
	self:Info(category, string.format("Performance: %s", operation), {
		Duration = string.format("%.3fms", duration * 1000),
		Details = details,
	})
end

function LogService:RegisterCategory(categoryName, description)
	self.Categories[categoryName] = {
		Name = categoryName,
		Description = description or "",
		RegisteredAt = tick(),
	}

	local testMode = getTestMode()
	if testMode and testMode.Logging.LogServiceInitialization then
		self:Debug("LogService", "Registered category: " .. categoryName, {
			Description = description,
		})
	end
end

function LogService:FilterCategory(categoryName, shouldFilter)
	if shouldFilter then
		self.FilteredCategories[categoryName] = true
		self:Debug("LogService", "Filtering out category: " .. categoryName)
	else
		self.FilteredCategories[categoryName] = nil
		self:Debug("LogService", "No longer filtering category: " .. categoryName)
	end
end

function LogService:FlushOldEntries()
	local before = #self.LogEntries
	local maxAge = 300
	local currentTime = tick() - self.StartTime

	local i = 1
	while i <= #self.LogEntries do
		local entry = self.LogEntries[i]
		if currentTime - entry.Timestamp > maxAge then
			table.remove(self.LogEntries, i)
		else
			i = i + 1
		end
	end

	local removed = before - #self.LogEntries
	if removed > 0 then
		self:Debug("LogService", string.format("Flushed %d old log entries", removed))
	end
end

function LogService:ClearLogs()
	local count = #self.LogEntries
	self.LogEntries = {}
	self:Info("LogService", string.format("Cleared %d log entries", count))
end

function LogService:GetLogs(filters)
	filters = filters or {}
	local results = {}

	for _, entry in ipairs(self.LogEntries) do
		local include = true

		if filters.MinLevel and entry.Level < filters.MinLevel then
			include = false
		end

		if filters.MaxLevel and entry.Level > filters.MaxLevel then
			include = false
		end

		if filters.Category and entry.Category ~= filters.Category then
			include = false
		end

		if filters.MessageContains and not string.find(entry.Message:lower(), filters.MessageContains:lower()) then
			include = false
		end

		if filters.Since and entry.Timestamp < filters.Since then
			include = false
		end

		if include then
			table.insert(results, entry)
		end
	end

	return results
end

function LogService:GetRecentErrors(count)
	count = count or 10
	local errors = self:GetLogs({
		MinLevel = self.LogLevel.ERROR,
	})

	local recent = {}
	local startIndex = math.max(1, #errors - count + 1)
	for i = startIndex, #errors do
		table.insert(recent, errors[i])
	end

	return recent
end

function LogService:GetStats()
	return {
		TotalLogs = self.PerformanceMetrics.TotalLogs,
		LogsByLevel = self.PerformanceMetrics.LogsByLevel,
		LogsByCategory = self.PerformanceMetrics.LogsByCategory,
		ErrorCount = self.PerformanceMetrics.ErrorCount,
		WarnCount = self.PerformanceMetrics.WarnCount,
		EntriesInMemory = #self.LogEntries,
		MaxLogEntries = self.Settings.MaxLogEntries,
		Categories = self.Categories,
		FilteredCategories = self.FilteredCategories,
		Uptime = tick() - self.StartTime,
	}
end

function LogService:PrintStats()
	local stats = self:GetStats()

	print("=== LOG SERVICE STATISTICS ===")
	print(string.format("Total Logs: %d", stats.TotalLogs))
	print(string.format("Errors: %d, Warnings: %d", stats.ErrorCount, stats.WarnCount))
	print(string.format("Memory Usage: %d/%d entries", stats.EntriesInMemory, stats.MaxLogEntries))
	print(string.format("Uptime: %.1f seconds", stats.Uptime))

	print("\nLogs by Level:")
	for level, count in pairs(stats.LogsByLevel) do
		if count > 0 then
			print(string.format("  %s: %d", self.LogLevelNames[level], count))
		end
	end

	print("\nTop Categories:")
	local sortedCategories = {}
	for category, count in pairs(stats.LogsByCategory) do
		table.insert(sortedCategories, { category, count })
	end
	table.sort(sortedCategories, function(a, b)
		return a[2] > b[2]
	end)

	for i = 1, math.min(5, #sortedCategories) do
		print(string.format("  %s: %d", sortedCategories[i][1], sortedCategories[i][2]))
	end
end

function LogService:SetLogLevel(level)
	local oldLevel = self.Settings.MinLogLevel
	self.Settings.MinLogLevel = level

	self:Info(
		"LogService",
		string.format("Log level changed from %s to %s", self.LogLevelNames[oldLevel], self.LogLevelNames[level])
	)
end

function LogService:SetMaxLogEntries(maxEntries)
	self.Settings.MaxLogEntries = maxEntries

	-- Trim current entries if needed
	while #self.LogEntries > maxEntries do
		table.remove(self.LogEntries, 1)
	end

	self:Info("LogService", "Max log entries set to: " .. maxEntries)
end

return LogService
