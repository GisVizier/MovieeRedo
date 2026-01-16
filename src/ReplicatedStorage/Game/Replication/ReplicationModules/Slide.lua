local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local Util = require(script.Parent.Util)

local ReturnService = require(game.ReplicatedStorage.Shared.Util.FXLibaray)
local Utils = ReturnService();

local Assets = script
local FxFolder = Assets._effect;

local EffectsFolder = workspace.Effects

--loc al PlayMeshes = Utils.Utils.PlayMeshes
--local PlayBeams = Utils.Utils.PlayBeams
--local setHighlight = Utils.Utils.setHighlight
--local stopHighlight = Utils.Utils.stopHighlight
--local CamShake = Utils.Utils.CamShake

local Slide = {}
local active = {
	welds = {},
}

function Slide:Validate(_player, data)
	if typeof(data) ~= "table" then
		return false
	end
	if data.state == "Start" or data.state == "End" then
		return data.direction == nil or typeof(data.direction) == "Vector3"
	end
	return typeof(data.direction) == "Vector3"
end

function Slide:StartFx(userId, data)
	if active[userId] then
		return
	end

	local fx = FxFolder.Slide
	local root = Util.getPlayerRoot(userId)
	if root and fx then
		fx = fx:Clone()		
		fx.Parent = EffectsFolder

		fx:PivotTo(root.CFrame)

		local weld = ReturnService(`Utils`):delta_weld(function()return root:GetPivot() end, fx, CFrame.new())
		active[userId] = {_instance = fx, _weldConnection = weld.Connection}
	end	
end

function Slide:StopFx(userId)
	local fxtable = active[userId]
	local fx = fxtable and fxtable._instance or nil
	local weld: RBXScriptConnection = fxtable and fxtable._weldConnection or nil

	if fx then
		Utils.PlayAttachment(fx, 5)	
		Utils.ToggleFX(fx, false)
		weld:Disconnect()

		active[userId] = nil
	end
end

function Slide:Execute(originUserId, data)
	if data.state == "Start" then
		self:StartFx(originUserId, data)


	elseif data.state == "End" then
		self:StopFx(originUserId, data)
	end

	if data.direction then

	end
end

function Slide:Update(originUserId, data)
	if not data or typeof(data.direction) ~= "Vector3" then
		return
	end
	if not active[originUserId] then
		return
	end

	--local key = "Slide_" .. tostring(originUserId)
	--VFXPlayer:UpdateYaw(key, data.direction)
end

return Slide
