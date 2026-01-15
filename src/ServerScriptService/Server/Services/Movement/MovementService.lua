local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))

local MovementService = {}

function MovementService:Init(_registry, net)
	print("[MovementService] Init")
	VFXRep:Init(net, true)
end

function MovementService:Start()
	print("[MovementService] Start")
end

return MovementService
