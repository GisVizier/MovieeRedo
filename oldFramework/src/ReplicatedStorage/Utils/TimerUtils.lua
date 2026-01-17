local TimerUtils = {}

function TimerUtils.FormatTime(seconds)
	local totalSeconds = math.round(seconds)
	local days = math.floor(totalSeconds / 86400)
	local remainingAfterDays = totalSeconds % 86400
	local hours = math.floor(remainingAfterDays / 3600)
	local remainingAfterHours = remainingAfterDays % 3600
	local minutes = math.floor(remainingAfterHours / 60)
	local secs = remainingAfterHours % 60

	local result = ""
	if days >= 1 then
		result = result .. string.format("%dd ", days)
	end
	if days >= 1 or hours >= 1 then
		result = result .. string.format("%dh ", hours)
	end
	if hours >= 1 or minutes >= 1 then
		result = result .. string.format("%dm ", minutes)
	end
	if hours <= 0 and minutes <= 0 and days <= 0 then
		result = result .. string.format("%ds", secs)
	end
	return result:gsub("%s+$", "")
end

function TimerUtils.FormatClock(seconds)
	local totalSeconds = math.round(seconds)
	local days = math.floor(totalSeconds / 86400)
	local remainingAfterDays = totalSeconds % 86400
	local hours = math.floor(remainingAfterDays / 3600)
	local remainingAfterHours = remainingAfterDays % 3600
	local minutes = math.floor(remainingAfterHours / 60)
	local secs = remainingAfterHours % 60

	local result = ""
	if days >= 1 then
		result = result .. string.format("%d:", days)
	end
	if days >= 1 or hours >= 1 then
		result = result .. string.format("%02d:", hours)
	end
	if hours >= 1 or minutes >= 1 or days >= 1 then
		result = result .. string.format("%02d:", minutes)
	end
	return result .. string.format("%02d", secs)
end

function TimerUtils.FormatSeconds(seconds)
	local totalSeconds = math.max(0, math.floor(math.round(seconds)))
	return string.format("%ds", totalSeconds)
end

function TimerUtils.FormatCompact(seconds)
	local totalSeconds = math.max(0, math.floor(math.round(seconds)))
	local days = math.floor(totalSeconds / 86400)
	local remainingAfterDays = totalSeconds % 86400
	local hours = math.floor(remainingAfterDays / 3600)
	local remainingAfterHours = remainingAfterDays % 3600
	local minutes = math.floor(remainingAfterHours / 60)
	local secs = remainingAfterHours % 60

	if days > 0 then
		return string.format("%dd %dh %dm", days, hours, minutes)
	elseif hours > 0 then
		return string.format("%dh %dm %ds", hours, minutes, secs)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	else
		return string.format("%ds", secs)
	end
end

return TimerUtils
