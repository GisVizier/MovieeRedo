local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local Util = require(script.Parent.Util)

local WallJump = {}

function WallJump:Validate(_player, data)
	return typeof(data) == "table"
		and typeof(data.position) == "Vector3"
		and (data.pivot == nil or typeof(data.pivot) == "CFrame")
end

function WallJump:Execute(_originUserId, data)
	local Assets = ReplicatedStorage.Assets.MovementFX
	local fxFolder = Assets;
	
	local root = Util.getPlayerRoot(_originUserId)
	local fx = fxFolder and fxFolder:FindFirstChild("WallJump")
	if root and fx then
		fx = fx:Clone()
		fx.Parent = effectsFolder

		local pivot = data.pivot or CFrame.new(data.position)
		fx:PivotTo(pivot)
	end
end

return WallJump
