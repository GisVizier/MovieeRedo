local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local Signal = require(Locations.Modules.Utils.Signal)

local BaseKit = {}
BaseKit.__index = BaseKit

function BaseKit.new(config)
	local self = setmetatable({}, BaseKit)

	self.Name = config.Name or "UnnamedKit"
	self.Description = config.Description or ""

	self.Passive = config.Passive
	self.Ability = config.Ability
	self.Ultimate = config.Ultimate

	self.Owner = nil
	self.Character = nil
	self.IsInitialized = false

	self.Initialized = Signal.new()
	self.Destroyed = Signal.new()

	self._connections = {}

	return self
end

function BaseKit:Initialize(player, character)
	if self.IsInitialized then
		Log:Warn("KITS", "Kit already initialized", { Kit = self.Name })
		return
	end

	self.Owner = player
	self.Character = character

	if self.Passive then
		self.Passive:Initialize(player, character)
		self.Passive:Activate()
	end

	if self.Ability then
		self.Ability:Initialize(player, character)
	end

	if self.Ultimate then
		self.Ultimate:Initialize(player, character)
	end

	self.IsInitialized = true

	Log:Info("KITS", "Kit initialized", {
		Kit = self.Name,
		Player = player.Name,
		HasPassive = self.Passive ~= nil,
		HasAbility = self.Ability ~= nil,
		HasUltimate = self.Ultimate ~= nil,
	})

	self.Initialized:fire()
end

function BaseKit:GetAbility(abilityType)
	if abilityType == "Passive" then
		return self.Passive
	elseif abilityType == "Ability" then
		return self.Ability
	elseif abilityType == "Ultimate" then
		return self.Ultimate
	end
	return nil
end

function BaseKit:ActivateAbility(data)
	if self.Ability and self.Ability:IsReady() then
		return self.Ability:Activate(data)
	end
	return false
end

function BaseKit:ActivateUltimate(data)
	if self.Ultimate and self.Ultimate:IsReady() then
		return self.Ultimate:Activate(data)
	end
	return false
end

function BaseKit:InterruptAll()
	if self.Ability and self.Ability.State == "Active" then
		self.Ability:Interrupt()
	end
	if self.Ultimate and self.Ultimate.State == "Active" then
		self.Ultimate:Interrupt()
	end
end

function BaseKit:OnKill(victim)
	if self.Passive then
		self.Passive:OnKillTriggered(victim)
	end
	if self.Ability then
		self.Ability:OnKillTriggered(victim)
	end
	if self.Ultimate then
		self.Ultimate:OnKillTriggered(victim)
	end
end

function BaseKit:ResetCooldowns()
	if self.Ability then
		self.Ability:ResetCooldown()
	end
	if self.Ultimate then
		self.Ultimate:ResetCooldown()
	end
end

function BaseKit:UpdateCharacter(newCharacter)
	self.Character = newCharacter

	if self.Passive then
		self.Passive.Character = newCharacter
	end
	if self.Ability then
		self.Ability.Character = newCharacter
	end
	if self.Ultimate then
		self.Ultimate.Character = newCharacter
	end
end

function BaseKit:Destroy()
	for _, conn in pairs(self._connections) do
		if conn and conn.Disconnect then
			conn:Disconnect()
		end
	end
	self._connections = {}

	if self.Passive then
		self.Passive:Cleanup()
		self.Passive = nil
	end

	if self.Ability then
		self.Ability:Cleanup()
		self.Ability = nil
	end

	if self.Ultimate then
		self.Ultimate:Cleanup()
		self.Ultimate = nil
	end

	self.IsInitialized = false

	Log:Debug("KITS", "Kit destroyed", { Kit = self.Name })

	self.Destroyed:fire()
	self.Initialized:destroy()
	self.Destroyed:destroy()
end

function BaseKit:GetState()
	return {
		Name = self.Name,
		Passive = self.Passive and {
			Name = self.Passive.Name,
			State = self.Passive.State,
		},
		Ability = self.Ability and {
			Name = self.Ability.Name,
			State = self.Ability.State,
			CooldownRemaining = self.Ability:GetCooldownRemaining(),
			Charges = self.Ability.Charges,
		},
		Ultimate = self.Ultimate and {
			Name = self.Ultimate.Name,
			State = self.Ultimate.State,
			CooldownRemaining = self.Ultimate:GetCooldownRemaining(),
			Charge = self.Ultimate.CurrentCharge,
			RequiredCharge = self.Ultimate.RequiredCharge,
		},
	}
end

return BaseKit
