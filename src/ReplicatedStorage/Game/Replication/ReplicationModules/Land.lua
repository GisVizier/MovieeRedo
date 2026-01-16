local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local Util = require(script.Parent.Util)

local ReturnService = require(game.ReplicatedStorage.Shared.Util.FXLibaray)
local Utils = ReturnService();

local Assets = ReplicatedStorage.Assets.MovementFX
local FxFolder = Assets;

local EffectsFolder = workspace.Effects

local Land = {}

function Land:Validate(_player, data)
	return typeof(data) == "table" and typeof(data.position) == "Vector3"
end

function Land:Execute(_originUserId, data)
	--local template = Util.getMovementTemplate("Land")
	--if not template then
	--	return
	--end

	--local vfxCfg = Config.Gameplay.VFX and Config.Gameplay.VFX.Land
	--VFXPlayer:Play(template, data.position, vfxCfg and vfxCfg.Lifetime or nil)

	local fx = FxFolder:FindFirstChild(`Land`)
	local root = Util.getPlayerRoot(_originUserId)
	if root and fx then
		fx = fx:Clone()		
		fx.Parent = EffectsFolder

		fx:PivotTo(CFrame.new(data.position))
		Utils.PlayAttachment(fx, 5)	

		--active[userId] = {_instance = fx, _weldConnection = weld.Connection}
	end	
end

return Land
