local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitServiceImpl = require(ReplicatedStorage:WaitForChild("KitSystem"):WaitForChild("KitService"))

local KitService = {}

function KitService:Init(registry, net)
	self._net = net
	self._impl = KitServiceImpl.new(net, registry)
end

function KitService:Start()
	if self._impl then
		self._impl:start()
	end
end

function KitService:NotifyDamage(player, damage, source)
	if self._impl and self._impl.NotifyDamage then
		self._impl:NotifyDamage(player, damage, source)
	end
end

function KitService:InterruptAbility(player, abilityType, reason)
	if self._impl and self._impl.InterruptAbility then
		self._impl:InterruptAbility(player, abilityType, reason)
	end
end

function KitService:OnPlayerDeath(player)
	if self._impl and self._impl.OnPlayerDeath then
		self._impl:OnPlayerDeath(player)
	end
end

return KitService

