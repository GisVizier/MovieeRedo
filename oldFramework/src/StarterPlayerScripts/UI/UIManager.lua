--[[
	UIManager
	Central manager for all UI systems in the game.
	Handles initialization, lifecycle, and coordination of UI elements.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local LogService = require(Locations.Modules.Systems.Core.LogService)

local UIManager = {}
UIManager.__index = UIManager

-- UI modules to load (add new UI systems here)
local UI_MODULES = {
	"MobileControls",
	"ChatMonitor",
	"CoreUIController",
}

function UIManager.new()
	local self = setmetatable({}, UIManager)

	self._uiModules = {}
	self._initialized = false

	return self
end

function UIManager:Init()
	if self._initialized then
		LogService:Warn("UI_MANAGER", "Already initialized")
		return
	end

	LogService:Info("UI_MANAGER", "Initializing UI systems")

	-- Load all UI modules
	local uiFolder = script.Parent
	for _, moduleName in ipairs(UI_MODULES) do
		local module = uiFolder:FindFirstChild(moduleName)
		if module then
			local success, result = pcall(require, module)
			if success then
				-- If module has a `new` function, instantiate it
				if result.new then
					self._uiModules[moduleName] = result.new()
				else
					self._uiModules[moduleName] = result
				end
				LogService:Debug("UI_MANAGER", "Loaded UI module", { Module = moduleName })
			else
				LogService:Error("UI_MANAGER", "Failed to load UI module", {
					Module = moduleName,
					Error = result,
				})
			end
		else
			LogService:Warn("UI_MANAGER", "UI module not found", { Module = moduleName })
		end
	end

	-- Initialize all UI modules
	for moduleName, uiModule in pairs(self._uiModules) do
		if uiModule.Init then
			local success, err = pcall(function()
				uiModule:Init()
			end)
			if not success then
				LogService:Error("UI_MANAGER", "Failed to initialize UI module", {
					Module = moduleName,
					Error = err,
				})
			end
		end
	end

	self._initialized = true
	LogService:Info("UI_MANAGER", "UI systems initialized", {
		LoadedModules = #self._uiModules,
	})
end

function UIManager:Show()
	for moduleName, uiModule in pairs(self._uiModules) do
		if uiModule.Show then
			local success, err = pcall(function()
				uiModule:Show()
			end)
			if not success then
				LogService:Error("UI_MANAGER", "Failed to show UI module", {
					Module = moduleName,
					Error = err,
				})
			end
		end
	end
end

function UIManager:Hide()
	for moduleName, uiModule in pairs(self._uiModules) do
		if uiModule.Hide then
			local success, err = pcall(function()
				uiModule:Hide()
			end)
			if not success then
				LogService:Error("UI_MANAGER", "Failed to hide UI module", {
					Module = moduleName,
					Error = err,
				})
			end
		end
	end
end

function UIManager:GetUIModule(moduleName)
	return self._uiModules[moduleName]
end

function UIManager:GetModule(moduleName)
	return self._uiModules[moduleName]
end

function UIManager:Cleanup()
	for moduleName, uiModule in pairs(self._uiModules) do
		if uiModule.Cleanup then
			local success, err = pcall(function()
				uiModule:Cleanup()
			end)
			if not success then
				LogService:Error("UI_MANAGER", "Failed to cleanup UI module", {
					Module = moduleName,
					Error = err,
				})
			end
		end
	end

	self._uiModules = {}
	self._initialized = false
end

return UIManager
