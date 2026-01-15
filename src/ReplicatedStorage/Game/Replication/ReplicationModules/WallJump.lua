local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local Util = require(script.Parent.Util)

local WallJump = {}

function WallJump:Validate(_player, data)
	return typeof(data) == "table" and typeof(data.position) == "Vector3"
end

function WallJump:Execute(_originUserId, data)
	local template = Util.getMovementTemplate("WallJump")
	if not template then
		return
	end
	local vfxCfg = Config.Gameplay.VFX and Config.Gameplay.VFX.WallJump
	VFXPlayer:Play(template, data.position, vfxCfg and vfxCfg.Lifetime or nil)
end

return WallJump
