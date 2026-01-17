local ServiceLoader = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)

local LogService = nil
local TestMode = nil

local function getLogService()
	if not LogService then
		LogService = require(Locations.Modules.Systems.Core.LogService)
	end
	return LogService
end

local function getTestMode()
	if not TestMode then
		TestMode = require(ReplicatedStorage:WaitForChild("TestMode"))
	end
	return TestMode
end

-- Helper function to find module in container (supports subfolders)
local function findModule(container, moduleName)
	-- Try direct child first
	local directChild = container:FindFirstChild(moduleName)
	if directChild and directChild:IsA("ModuleScript") then
		return directChild
	end
	
	-- Search in subfolders
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Folder") then
			local module = child:FindFirstChild(moduleName)
			if module and module:IsA("ModuleScript") then
				return module
			end
		end
	end
	
	return nil
end

function ServiceLoader:LoadModules(container, moduleNames, moduleType)
	local loaded = {}
	local log = getLogService()
	local testMode = getTestMode()
	local shouldLog = testMode.Logging.LogServiceInitialization

	for _, moduleName in pairs(moduleNames) do
		local success, module = pcall(function()
			-- Try to find module (supports subfolders)
			local moduleScript = findModule(container, moduleName)
			if moduleScript then
				return require(moduleScript)
			else
				-- Fallback to WaitForChild for backwards compatibility
				return require(container:WaitForChild(moduleName))
			end
		end)

		if success then
			loaded[moduleName] = module
			if shouldLog then
				log:Debug("SYSTEM", `{moduleType} loaded: {moduleName}`)
			end

			if module.Init then
				module:Init()
				if shouldLog then
					log:Debug("SYSTEM", `{moduleType} initialized: {moduleName}`)
				end
			end
		else
			log:Error("SYSTEM", `Failed to load {moduleType} {moduleName}`, { Error = module })
		end
	end

	return loaded
end

function ServiceLoader:GetServices()
	return game:GetService("Players"),
		game:GetService("RunService"),
		game:GetService("ReplicatedStorage"),
		game:GetService("ServerScriptService"),
		game:GetService("ServerStorage"),
		game:GetService("UserInputService"),
		game:GetService("TweenService")
end

function ServiceLoader:GetLocalPlayer()
	return game:GetService("Players").LocalPlayer
end

return ServiceLoader
