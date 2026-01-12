local ReplicationController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ClientReplicator = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ClientReplicator"))
local RemoteReplicator = require(Locations.Game:WaitForChild("Replication"):WaitForChild("RemoteReplicator"))

ReplicationController._registry = nil
ReplicationController._net = nil

function ReplicationController:Init(registry, net)
	self._registry = registry
	self._net = net

	ClientReplicator:Init(net)
	RemoteReplicator:Init(net)
end

function ReplicationController:Start()
	-- RemoteReplicator starts its loop during Init.
end

function ReplicationController:OnLocalCharacterReady(character)
	ClientReplicator:Start(character)
end

function ReplicationController:OnLocalCharacterRemoving()
	ClientReplicator:Stop()
end

function ReplicationController:SetPlayerRagdolled(player, isRagdolled)
	RemoteReplicator:SetPlayerRagdolled(player, isRagdolled)
end

return ReplicationController
