local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))

local Util = require(script.Parent.Util)

local Speed = {}
local active = {} -- [userId] = fxInstance

function Speed:Validate(_player, data)
	return typeof(data) == "table"
		and typeof(data.direction) == "Vector3"
		and typeof(data.speed) == "number"
end

local function createFx(): Instance?
	local template = Util.getMovementTemplate("SpeedFX")
	return template and template:Clone() or nil
end

function Speed:Execute(originUserId, data)
	local root = Util.getPlayerRoot(originUserId)
	if not root then
		return
	end

	local cfg = Config.Gameplay.VFX and Config.Gameplay.VFX.SpeedFX
	if not cfg or cfg.Enabled == false then
		return
	end

	if data.speed >= (cfg.Threshold or 80) then
		local fx = active[originUserId]
		if not fx then
			fx = createFx()
			if not fx then
				return
			end
			fx.Parent = workspace:FindFirstChild("Effects") or workspace
			active[originUserId] = fx
		end

		local dir = data.direction
		if dir.Magnitude > 0.001 then
			local pos = root.Position
			local cf = CFrame.lookAt(pos, pos + dir.Unit)
			fx:PivotTo(cf)
		end
	else
		local fx = active[originUserId]
		if fx then
			fx:Destroy()
			active[originUserId] = nil
		end
	end
end

return Speed