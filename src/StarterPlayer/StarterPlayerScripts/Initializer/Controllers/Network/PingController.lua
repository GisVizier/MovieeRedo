--[[
	PingController.lua
	
	Client-side handler for ping measurement.
	Responds to server ping requests immediately for accurate RTT calculation.
	
	The server sends PingRequest with a token, client echoes back PingResponse
	with the same token. Server measures round-trip time from this.
]]

local PingController = {}

PingController._net = nil
PingController._registry = nil

function PingController:Init(registry, net)
	self._registry = registry
	self._net = net
	
	-- Respond to ping requests immediately for accurate measurement
	net:ConnectClient("PingRequest", function(token)
		-- Echo back immediately - no processing delay
		net:FireServer("PingResponse", token)
	end)
end

function PingController:Start()
	-- No-op - all work done in Init
end

return PingController
