local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local Util = require(script.Parent.Util)

local ReturnService = require(game.ReplicatedStorage.Shared.Util.FXLibaray)
local Utils = ReturnService();

local Assets = ReplicatedStorage.Assets.MovementFX
local FxFolder = Assets;

local EffectsFolder = workspace.Effects

local SlideCancel = {}

function SlideCancel:Validate(_player, data)
	return typeof(data) == "table" and typeof(data.position) == "Vector3"
end

function SlideCancel:Execute(_originUserId, data)
	local origin = data.position + Vector3.new(0, 2, 0)
	local dir = Vector3.new(0, -8, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {workspace.Rigs, workspace.Ragdolls, workspace.Entities  }
	rayParams.RespectCanCollide = true

	if not workspace:Raycast(origin, dir, rayParams) then
		return
	end

	--local template = Util.getMovementTemplate("SlideCancel")
	--if not template then
	--	return
	--end

	--local vfxCfg = Config.Gameplay.VFX and Config.Gameplay.VFX.SlideCancel
	--VFXPlayer:Play(template, data.position, vfxCfg and vfxCfg.Lifetime or nil)

	local fx = FxFolder:FindFirstChild(`SlideCancel`)
	local root = Util.getPlayerRoot(_originUserId)
	if root and fx then
		fx = fx:Clone()		
		fx.Parent = EffectsFolder

		fx:PivotTo(CFrame.new(data.position))
		Utils.PlayAttachment(fx, 5)	

		--active[userId] = {_instance = fx, _weldConnection = weld.Connection}
	end	
end

return SlideCancel
