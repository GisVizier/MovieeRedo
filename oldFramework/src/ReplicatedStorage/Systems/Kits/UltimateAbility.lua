local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Signal = require(Locations.Modules.Utils.Signal)

local kitsFolder = script.Parent
local BaseAbility = require(kitsFolder.BaseAbility)

local UltimateAbility = {}
UltimateAbility.__index = UltimateAbility
setmetatable(UltimateAbility, { __index = BaseAbility })

function UltimateAbility.new(config)
	config.Type = "Ultimate"

	local self = setmetatable(BaseAbility.new(config), UltimateAbility)

	self.RequiredCharge = config.RequiredCharge or 100
	self.CurrentCharge = 0
	self.ChargeRate = config.ChargeRate or 1
	self.ChargeOnKill = config.ChargeOnKill or 0
	self.ChargeOnDamage = config.ChargeOnDamage or 0
	self.ChargeOnAssist = config.ChargeOnAssist or 0
	self.RefundOnInterrupt = config.RefundOnInterrupt or 0

	self.ChargeChanged = Signal.new()

	return self
end

function UltimateAbility:Initialize(player, character)
	BaseAbility.Initialize(self, player, character)
end

function UltimateAbility:IsReady()
	if self.CurrentCharge < self.RequiredCharge then
		return false
	end
	return BaseAbility.IsReady(self)
end

function UltimateAbility:GetChargePercent()
	return math.clamp(self.CurrentCharge / self.RequiredCharge, 0, 1)
end

function UltimateAbility:AddCharge(amount)
	local oldCharge = self.CurrentCharge
	self.CurrentCharge = math.clamp(self.CurrentCharge + amount, 0, self.RequiredCharge)

	if self.CurrentCharge ~= oldCharge then
		self.ChargeChanged:fire(self.CurrentCharge, self.RequiredCharge)
	end
end

function UltimateAbility:SetCharge(amount)
	local oldCharge = self.CurrentCharge
	self.CurrentCharge = math.clamp(amount, 0, self.RequiredCharge)

	if self.CurrentCharge ~= oldCharge then
		self.ChargeChanged:fire(self.CurrentCharge, self.RequiredCharge)
	end
end

function UltimateAbility:ResetCharge()
	self:SetCharge(0)
end

function UltimateAbility:Activate()
	if not self:IsReady() then
		return false
	end

	self.CurrentCharge = 0
	self.ChargeChanged:fire(0, self.RequiredCharge)

	return BaseAbility.Activate(self)
end

function UltimateAbility:Interrupt()
	local wasActive = self.State == BaseAbility.AbilityState.Active

	local result = BaseAbility.Interrupt(self)

	if wasActive and self.RefundOnInterrupt > 0 then
		local refundAmount = self.RequiredCharge * self.RefundOnInterrupt
		self:AddCharge(refundAmount)
	end

	return result
end

function UltimateAbility:OnKillTriggered(victim)
	BaseAbility.OnKillTriggered(self, victim)

	if self.ChargeOnKill > 0 then
		self:AddCharge(self.ChargeOnKill)
	end
end

function UltimateAbility:OnDamageDealt(amount)
	if self.ChargeOnDamage > 0 then
		local chargeGain = amount * self.ChargeOnDamage
		self:AddCharge(chargeGain)
	end
end

function UltimateAbility:OnAssist()
	if self.ChargeOnAssist > 0 then
		self:AddCharge(self.ChargeOnAssist)
	end
end

function UltimateAbility:Cleanup()
	self.ChargeChanged:destroy()
	BaseAbility.Cleanup(self)
end

return UltimateAbility
