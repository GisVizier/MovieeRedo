local DebugLogService = {}

local HttpService = game:GetService("HttpService")

local DEBUG_LOG_ENDPOINT = "http://127.0.0.1:7243/ingest/ac803ab1-738e-4091-b312-63d03fa04a69"

function DebugLogService:Init(_registry, net)
	self._net = net

	self._net:ConnectServer("DebugLog", function(player, payload)
		if type(payload) ~= "table" then
			return
		end

		payload.player = payload.player or {
			userId = player and player.UserId or nil,
			name = player and player.Name or nil,
		}

		local ok, body = pcall(function()
			return HttpService:JSONEncode(payload)
		end)
		if not ok then
			return
		end

		local okPost, err = pcall(function()
			HttpService:PostAsync(DEBUG_LOG_ENDPOINT, body, Enum.HttpContentType.ApplicationJson)
		end)
		if not okPost then
		end
	end)
end

return DebugLogService
