local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitServiceImpl = require(ReplicatedStorage:WaitForChild("KitSystem"):WaitForChild("KitService"))

local KitService = {}

function KitService:Init(_registry, net)
	self._net = net
	self._impl = KitServiceImpl.new(net)
end

function KitService:Start()
	if self._impl then
		self._impl:start()
	end
end

return KitService

