--[[
	MouseLockManager
	Centralized manager for controlling mouse lock state.
	Allows different systems (chat, settings, etc.) to request mouse unlock.
	The mouse is only locked when NO systems are requesting unlock.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local LogService = require(Locations.Modules.Systems.Core.LogService)

local MouseLockManager = {}
MouseLockManager.__index = MouseLockManager

-- Track which systems are requesting mouse unlock
MouseLockManager._unlockRequests = {}
MouseLockManager._isLocked = false

function MouseLockManager:Init()
	self._unlockRequests = {}
	self._isLocked = false
	LogService:Info("MOUSE_LOCK", "MouseLockManager initialized")
end

--[[
	Request the mouse to be unlocked
	@param requesterId string - Unique identifier for the requesting system (e.g., "Chat", "Settings")
]]
function MouseLockManager:RequestUnlock(requesterId)
	if not requesterId then
		LogService:Warn("MOUSE_LOCK", "RequestUnlock called without requesterId")
		return
	end

	if not self._unlockRequests[requesterId] then
		self._unlockRequests[requesterId] = true
		LogService:Debug("MOUSE_LOCK", "Unlock requested by: " .. requesterId)
		self:_UpdateLockState()
	end
end

--[[
	Release an unlock request, allowing the mouse to be locked again if no other requests exist
	@param requesterId string - Unique identifier for the requesting system
]]
function MouseLockManager:ReleaseUnlock(requesterId)
	if not requesterId then
		LogService:Warn("MOUSE_LOCK", "ReleaseUnlock called without requesterId")
		return
	end

	if self._unlockRequests[requesterId] then
		self._unlockRequests[requesterId] = nil
		LogService:Debug("MOUSE_LOCK", "Unlock released by: " .. requesterId)
		self:_UpdateLockState()
	end
end

--[[
	Check if the mouse is currently locked
	@return boolean - True if mouse is locked
]]
function MouseLockManager:IsLocked()
	return self._isLocked
end

--[[
	Internal: Update the mouse lock state based on active requests
]]
function MouseLockManager:_UpdateLockState()
	-- Count active unlock requests
	local hasUnlockRequests = false
	for _, _ in pairs(self._unlockRequests) do
		hasUnlockRequests = true
		break
	end

	-- Lock the mouse only if no unlock requests are active
	local shouldLock = not hasUnlockRequests

	if shouldLock ~= self._isLocked then
		self._isLocked = shouldLock

		if shouldLock then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			LogService:Debug("MOUSE_LOCK", "Mouse locked")
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			LogService:Debug("MOUSE_LOCK", "Mouse unlocked")
		end
	end
end

--[[
	Force the mouse to be locked regardless of requests
	Use this when initially setting up the camera system
]]
function MouseLockManager:ForceLock()
	self._unlockRequests = {}
	self._isLocked = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	LogService:Debug("MOUSE_LOCK", "Mouse force locked")
end

return MouseLockManager
