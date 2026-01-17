local DebugPrint = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)

local TestMode = nil
local function getTestMode()
	if not TestMode then
		TestMode = require(Locations.Modules.TestMode)
	end
	return TestMode
end

function DebugPrint.print(...)
	local testMode = getTestMode()
	local isClient = RunService:IsClient()
	local isServer = RunService:IsServer()

	-- TESTMODE BLOCKS DEBUG PRINTS TO REDUCE SPAM IN PRODUCTION
	if isClient and not testMode.CLIENT_LOGGING_ENABLED then
		return
	end
	if isServer and not testMode.SERVER_LOGGING_ENABLED then
		return
	end

	print(...)
end

function DebugPrint.warn(...)
	warn(...)
end

function DebugPrint.error(...)
	error(...)
end

function DebugPrint.conditionalPrint(condition, ...)
	if not condition then
		return
	end

	DebugPrint.print(...)
end

return DebugPrint
