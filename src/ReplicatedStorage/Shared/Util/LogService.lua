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

function LogService:Info(_tag, _message, _data)
	-- Disabled: no-op
end

function LogService:Debug(_tag, _message, _data)
	-- Disabled: no-op
end

function LogService:Warn(_tag, _message, _data)
	-- Disabled: no-op
end

function LogService:Error(_tag, _message, _data)
	-- Disabled: no-op
end

return LogService
