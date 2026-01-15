local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local Util = require(script.Parent.Util)

local Speed = {}

function Speed:Validate(_player, data)
	return typeof(data) == "table"
		and typeof(data.direction) == "Vector3"
		and typeof(data.speed) == "number"
end

function Speed:Execute(originUserId, data)
	local key = "SpeedFX_" .. tostring(originUserId)
	local root = Util.getPlayerRoot(originUserId)
	if not root then
		return
	end

	local cfg = Config.Gameplay.VFX and Config.Gameplay.VFX.SpeedFX
	if not cfg or cfg.Enabled == false then
		return
	end

	if data.speed >= (cfg.Threshold or 80) then
		if not VFXPlayer:IsActive(key) then
			local template = Util.getMovementTemplate("SpeedFX")
			if template then
				VFXPlayer:Start(key, template, root)
			end
		end
		VFXPlayer:UpdateYaw(key, data.direction)
	else
		if VFXPlayer:IsActive(key) then
			VFXPlayer:Stop(key)
		end
	end
end

return Speed
