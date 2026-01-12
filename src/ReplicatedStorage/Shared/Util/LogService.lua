local LogService = {}

function LogService:RegisterCategory(_name, _description)
	-- No-op for v2
end

local function formatMessage(level, tag, message, data)
	local suffix = ""
	if data ~= nil then
		suffix = " " .. tostring(data)
	end
	return string.format("[%s][%s] %s%s", level, tag, tostring(message), suffix)
end

function LogService:Info(tag, message, data)
	print(formatMessage("INFO", tag, message, data))
end

function LogService:Debug(tag, message, data)
	print(formatMessage("DEBUG", tag, message, data))
end

function LogService:Warn(tag, message, data)
	warn(formatMessage("WARN", tag, message, data))
end

function LogService:Error(tag, message, data)
	warn(formatMessage("ERROR", tag, message, data))
end

return LogService
