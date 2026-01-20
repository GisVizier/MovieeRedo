--[[
	WeaponCooldown.lua
	
	Manages cooldowns for weapon actions (specials, melee attacks, etc.)
	Provides progress tracking for UI binding.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage:WaitForChild("CoreUI"):WaitForChild("Signal"))

local WeaponCooldown = {}
WeaponCooldown.__index = WeaponCooldown

function WeaponCooldown.new()
	local self = setmetatable({}, WeaponCooldown)
	self._cooldowns = {} -- { [name] = { endTime, duration } }
	self._onCooldownChanged = Signal.new()
	self._onCooldownComplete = Signal.new()
	return self
end

function WeaponCooldown:StartCooldown(name: string, duration: number)
	if type(name) ~= "string" or type(duration) ~= "number" then
		return
	end
	
	self._cooldowns[name] = {
		endTime = os.clock() + duration,
		duration = duration,
		startTime = os.clock(),
	}
	
	self._onCooldownChanged:fire(name, duration, 0)
	
	-- Schedule completion callback
	task.delay(duration, function()
		local cd = self._cooldowns[name]
		if cd and os.clock() >= cd.endTime then
			self._onCooldownComplete:fire(name)
		end
	end)
end

function WeaponCooldown:IsOnCooldown(name: string): boolean
	local cd = self._cooldowns[name]
	if not cd then
		return false
	end
	return os.clock() < cd.endTime
end

function WeaponCooldown:GetRemainingTime(name: string): number
	local cd = self._cooldowns[name]
	if not cd then
		return 0
	end
	return math.max(0, cd.endTime - os.clock())
end

function WeaponCooldown:GetProgress(name: string): number
	local cd = self._cooldowns[name]
	if not cd then
		return 1
	end
	
	local elapsed = os.clock() - cd.startTime
	return math.clamp(elapsed / cd.duration, 0, 1)
end

function WeaponCooldown:ClearCooldown(name: string)
	if self._cooldowns[name] then
		self._cooldowns[name] = nil
		self._onCooldownComplete:fire(name)
	end
end

function WeaponCooldown:ClearAllCooldowns()
	for name, _ in pairs(self._cooldowns) do
		self:ClearCooldown(name)
	end
end

function WeaponCooldown:OnCooldownChanged()
	return self._onCooldownChanged
end

function WeaponCooldown:OnCooldownComplete()
	return self._onCooldownComplete
end

function WeaponCooldown:Destroy()
	self._onCooldownChanged:destroy()
	self._onCooldownComplete:destroy()
	self._cooldowns = {}
end

return WeaponCooldown
