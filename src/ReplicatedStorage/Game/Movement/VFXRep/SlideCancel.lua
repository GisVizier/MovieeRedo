local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local Util = require(script.Parent.Util)

local SlideCancel = {}

function SlideCancel:Validate(_player, data)
	return typeof(data) == "table" and typeof(data.position) == "Vector3"
end

function SlideCancel:Execute(_originUserId, data)
	local template = Util.getMovementTemplate("SlideCancel")
	if not template then
		return
	end
	local vfxCfg = Config.Gameplay.VFX and Config.Gameplay.VFX.SlideCancel
	VFXPlayer:Play(template, data.position, vfxCfg and vfxCfg.Lifetime or nil)
end

return SlideCancel
