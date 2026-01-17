--[[
	ChatMonitor
	Monitors when the chat window is opened/closed and manages mouse lock state accordingly.
	Uses the same reliable detection method as InputManager.
]]

local TextChatService = game:GetService("TextChatService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local MouseLockManager = require(Locations.Modules.Systems.Core.MouseLockManager)

local ChatMonitor = {}
ChatMonitor.__index = ChatMonitor

function ChatMonitor.new()
	local self = setmetatable({}, ChatMonitor)
	self._initialized = false
	self._chatConnection = nil
	self._menuOpenedConnection = nil
	self._menuClosedConnection = nil
	return self
end

function ChatMonitor:Init()
	if self._initialized then
		LogService:Warn("CHAT_MONITOR", "Already initialized")
		return
	end

	LogService:Info("CHAT_MONITOR", "Initializing chat and menu monitor")

	-- Setup chat detection (same method as InputManager)
	self:_setupChatDetection()

	-- Setup menu detection (Roblox menu, not settings)
	self:_setupMenuDetection()

	self._initialized = true
	LogService:Info("CHAT_MONITOR", "Chat and menu monitor initialized")
end

--[[
	Setup chat detection using TextChatService.ChatInputBarConfiguration.IsFocused
	This is the same reliable method used by InputManager
]]
function ChatMonitor:_setupChatDetection()
	-- Wait for ChatInputBarConfiguration to be available
	local chatInputBar = TextChatService:WaitForChild("ChatInputBarConfiguration", 5)

	if chatInputBar then
		LogService:Debug("CHAT_MONITOR", "Using ChatInputBarConfiguration.IsFocused for chat detection")

		-- Monitor IsFocused property changes
		self._chatConnection = chatInputBar:GetPropertyChangedSignal("IsFocused"):Connect(function()
			local isFocused = chatInputBar.IsFocused

			if isFocused then
				LogService:Debug("CHAT_MONITOR", "Chat focused - unlocking mouse")
				MouseLockManager:RequestUnlock("Chat")
			else
				LogService:Debug("CHAT_MONITOR", "Chat unfocused - locking mouse")
				MouseLockManager:ReleaseUnlock("Chat")
			end
		end)

		-- Set initial state if chat is already focused
		if chatInputBar.IsFocused then
			MouseLockManager:RequestUnlock("Chat")
		end
	else
		LogService:Warn("CHAT_MONITOR", "ChatInputBarConfiguration not found - chat detection disabled")
	end
end

--[[
	Setup Roblox menu detection (Escape menu, not settings menu)
	This unlocks the mouse when the player opens the Roblox menu
]]
function ChatMonitor:_setupMenuDetection()
	LogService:Debug("CHAT_MONITOR", "Setting up Roblox menu detection")

	self._menuOpenedConnection = GuiService.MenuOpened:Connect(function()
		LogService:Debug("CHAT_MONITOR", "Roblox menu opened - unlocking mouse")
		MouseLockManager:RequestUnlock("RobloxMenu")
	end)

	self._menuClosedConnection = GuiService.MenuClosed:Connect(function()
		LogService:Debug("CHAT_MONITOR", "Roblox menu closed - locking mouse")
		MouseLockManager:ReleaseUnlock("RobloxMenu")
	end)
end

function ChatMonitor:Cleanup()
	if self._chatWindowConnection then
		self._chatWindowConnection:Disconnect()
		self._chatWindowConnection = nil
	end

	-- Ensure chat unlock is released
	MouseLockManager:ReleaseUnlock("Chat")

	self._initialized = false
	LogService:Debug("CHAT_MONITOR", "Cleaned up")
end

return ChatMonitor
