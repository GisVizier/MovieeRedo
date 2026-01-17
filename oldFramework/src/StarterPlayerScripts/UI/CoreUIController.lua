--[[
	CoreUIController
	
	Manages the CoreUI declarative UI system.
	Handles initialization and provides access to CoreUI instance.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local LogService = require(Locations.Modules.Systems.Core.LogService)

local CoreUIController = {}
CoreUIController.__index = CoreUIController

function CoreUIController.new()
	local self = setmetatable({}, CoreUIController)
	
	self._coreUI = nil
	self._screenGui = nil
	self._initialized = false
	
	return self
end

function CoreUIController:Init()
	if self._initialized then
		LogService:Warn("COREUI", "Already initialized")
		return
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		LogService:Error("COREUI", "LocalPlayer not found")
		return
	end

	-- Wait for PlayerGui
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	
	-- Find or create the main ScreenGui for CoreUI
	local screenGui = playerGui:FindFirstChild("CoreUI")
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "CoreUI"
		screenGui.ResetOnSpawn = false
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.Parent = playerGui
		
		LogService:Info("COREUI", "Created CoreUI ScreenGui")
	else
		LogService:Info("COREUI", "Found existing CoreUI ScreenGui")
	end

	self._screenGui = screenGui

	-- Initialize CoreUI
	local coreUIPath = Locations.Modules.CoreUI
	if not coreUIPath or not coreUIPath.CoreUI then
		LogService:Error("COREUI", "CoreUI module not found in Locations", {
			CoreUIPath = coreUIPath,
			HasCoreUI = coreUIPath ~= nil,
			HasCoreUIModule = coreUIPath and coreUIPath.CoreUI ~= nil,
		})
		return
	end

	local success, CoreUI = pcall(require, coreUIPath.CoreUI)
	if not success then
		LogService:Error("COREUI", "Failed to require CoreUI module", {
			Error = CoreUI,
			Path = coreUIPath.CoreUI and coreUIPath.CoreUI:GetFullName() or "nil",
		})
		return
	end

	self._coreUI = CoreUI.new(screenGui)
	
	local initSuccess, initError = pcall(function()
		self._coreUI:init()
	end)
	
	if not initSuccess then
		LogService:Error("COREUI", "Failed to initialize CoreUI", {
			Error = initError,
		})
		return
	end

	self._initialized = true
	
	LogService:Info("COREUI", "CoreUI initialized successfully", {
		ModulesFound = self:GetModuleCount(),
	})
end

function CoreUIController:GetCoreUI()
	return self._coreUI
end

function CoreUIController:GetScreenGui()
	return self._screenGui
end

function CoreUIController:ShowModule(moduleName, force)
	if not self._coreUI then
		LogService:Warn("COREUI", "CoreUI not initialized")
		return
	end
	
	self._coreUI:show(moduleName, force)
end

function CoreUIController:HideModule(moduleName)
	if not self._coreUI then
		LogService:Warn("COREUI", "CoreUI not initialized")
		return
	end
	
	self._coreUI:hide(moduleName)
end

function CoreUIController:IsModuleOpen(moduleName)
	if not self._coreUI then
		return false
	end
	
	return self._coreUI:isOpen(moduleName)
end

function CoreUIController:GetModule(moduleName)
	if not self._coreUI then
		return nil
	end
	
	return self._coreUI:getModule(moduleName)
end

function CoreUIController:GetModuleCount()
	if not self._coreUI or not self._coreUI._modules then
		return 0
	end
	
	local count = 0
	for _ in pairs(self._coreUI._modules) do
		count = count + 1
	end
	return count
end

function CoreUIController:HideAll()
	if not self._coreUI then
		return
	end
	
	self._coreUI:hideAll()
end

return CoreUIController
