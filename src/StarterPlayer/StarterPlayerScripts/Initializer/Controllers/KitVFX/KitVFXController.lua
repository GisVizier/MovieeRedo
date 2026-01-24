local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local VFXController = require(Locations.Shared.Util:WaitForChild("VFXController"))

local KitVFXController = {}

KitVFXController._registry = nil
KitVFXController._net = nil
KitVFXController._conn = nil

function KitVFXController:Init(registry, net)
	self._registry = registry
	self._net = net

	ServiceRegistry:SetRegistry(registry)
	ServiceRegistry:RegisterController("KitVFX", self)

	if self._net and self._net.ConnectClient then
		self._conn = self._net:ConnectClient("KitState", function(message)
			self:_onKitMessage(message)
		end)
	end
end

function KitVFXController:Start() end

function KitVFXController:_onKitMessage(message)
	if type(message) ~= "table" then
		return
	end
	if message.kind ~= "Event" then
		return
	end

	VFXController:Dispatch(message)
end

function KitVFXController:Destroy()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

return KitVFXController

