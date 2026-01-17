local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)

local kitsFolder = script.Parent
local BaseAbility = require(kitsFolder.BaseAbility)

local ActiveAbility = {}
ActiveAbility.__index = ActiveAbility
setmetatable(ActiveAbility, { __index = BaseAbility })

function ActiveAbility.new(config)
	config.Type = "Active"

	local self = setmetatable(BaseAbility.new(config), ActiveAbility)

	self.CanMoveWhileActive = config.CanMoveWhileActive ~= false
	self.CanBeInterrupted = config.CanBeInterrupted ~= false
	self.CancelOnDamage = config.CancelOnDamage or false
	self.CancelOnStun = config.CancelOnStun ~= false

	self._damageConnection = nil

	return self
end

function ActiveAbility:Initialize(player, character)
	BaseAbility.Initialize(self, player, character)

	if self.CancelOnDamage then
		self:SetupDamageInterrupt()
	end
end

function ActiveAbility:SetupDamageInterrupt()
	if not self.Character then
		return
	end

	local humanoid = self.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self._damageConnection = humanoid.HealthChanged:Connect(function(newHealth)
			if self.State == BaseAbility.AbilityState.Active then
				local changed = humanoid:GetAttribute("LastHealth") or humanoid.MaxHealth
				if newHealth < changed then
					self:Interrupt()
				end
			end
			humanoid:SetAttribute("LastHealth", newHealth)
		end)
		table.insert(self._connections, self._damageConnection)
	end
end

function ActiveAbility:Activate()
	if not self:IsReady() then
		return false
	end

	return BaseAbility.Activate(self)
end

function ActiveAbility:End()
	return BaseAbility.End(self)
end

function ActiveAbility:Interrupt()
	if not self.CanBeInterrupted then
		return false
	end

	return BaseAbility.Interrupt(self)
end

return ActiveAbility
