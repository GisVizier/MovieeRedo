local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)

local kitsFolder = script.Parent
local BaseAbility = require(kitsFolder.BaseAbility)

local PassiveAbility = {}
PassiveAbility.__index = PassiveAbility
setmetatable(PassiveAbility, { __index = BaseAbility })

function PassiveAbility.new(config)
	config.Type = "Passive"
	config.Cooldown = 0
	config.Duration = 0

	local self = setmetatable(BaseAbility.new(config), PassiveAbility)

	self._onKillHeal = config.OnKillHeal or 0
	self._tickInterval = config.TickInterval or 0
	self._onTick = config.OnTick

	self._tickConnection = nil

	return self
end

function PassiveAbility:Initialize(player, character)
	BaseAbility.Initialize(self, player, character)

	if self._tickInterval > 0 and self._onTick then
		self:StartTickLoop()
	end
end

function PassiveAbility:StartTickLoop()
	if self._tickConnection then
		return
	end

	self._tickConnection = task.spawn(function()
		while self.Owner and self.State ~= "Disabled" do
			if self._onTick then
				local success, err = pcall(function()
					self._onTick(self)
				end)
				if not success then
					warn("[PassiveAbility] OnTick error: " .. tostring(err))
				end
			end
			task.wait(self._tickInterval)
		end
	end)
end

function PassiveAbility:StopTickLoop()
	if self._tickConnection then
		task.cancel(self._tickConnection)
		self._tickConnection = nil
	end
end

function PassiveAbility:Activate()
	self:SetState(BaseAbility.AbilityState.Active)

	if self._onStart then
		local success, err = pcall(function()
			self._onStart(self)
		end)
		if not success then
			warn("[PassiveAbility] OnStart error: " .. tostring(err))
		end
	end

	self.Activated:Fire()
	return true
end

function PassiveAbility:OnKillTriggered(victim)
	BaseAbility.OnKillTriggered(self, victim)

	if self._onKillHeal > 0 then
		self:HealOwner(self._onKillHeal)
	end
end

function PassiveAbility:Cleanup()
	self:StopTickLoop()
	BaseAbility.Cleanup(self)
end

return PassiveAbility
