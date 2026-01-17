local LogServiceInitializer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)

function LogServiceInitializer:Init()
	Log:Init()

	Log:SetLogLevel(Log.LogLevel.DEBUG)

	-- MAKE LOGSERVICE GLOBALLY ACCESSIBLE FOR OTHER SCRIPTS
	_G.Log = Log

	Log:Info("SYSTEM", "LogService initialized and made globally available")
end

return LogServiceInitializer
