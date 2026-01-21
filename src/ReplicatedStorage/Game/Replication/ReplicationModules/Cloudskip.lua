--[[
	Cloudskip VFX Module
	
	Handles visual effects for Airborne's Cloudskip ability.
	
	Functions:
	- User(originUserId, data) - Called for the caster (first-person effects)
	- Observer(originUserId, data) - Called for other players (third-person effects)
	- Execute(originUserId, data) - Fallback for both (if Function not specified)
	
	data:
	- position: Vector3 (where the dash started)
	- direction: Vector3 (dash direction)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Util = require(script.Parent.Util)

local ReturnService = require(ReplicatedStorage.Shared.Util.FXLibaray)
local Utils = ReturnService()

local Cloudskip = {}

function Cloudskip:Validate(_player, data)
	return typeof(data) == "table"
		and typeof(data.position) == "Vector3"
		and (data.direction == nil or typeof(data.direction) == "Vector3")
end

--[[
	Called for the CASTER (the player who used the ability)
	Use this for first-person specific effects, screen shake, etc.
]]
function Cloudskip:User(originUserId, data)
	local root = Util.getPlayerRoot(originUserId)
	if not root then return end
	
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	local MovementFX = Assets and Assets:FindFirstChild("MovementFX")
	local fxTemplate = MovementFX and MovementFX:FindFirstChild("Cloudskip")
	
	if fxTemplate then
		local fx = fxTemplate:Clone()
		fx.Parent = workspace:FindFirstChild("Effects") or workspace
		
		local direction = data.direction or Vector3.new(0, 0, -1)
		local pivot = CFrame.lookAt(data.position, data.position + direction)
		fx:PivotTo(pivot)
		
		Utils.PlayAttachment(fx, 3)
	end
	
	-- TODO: Add first-person specific effects here
	-- - Screen shake
	-- - Wind particles on camera
	-- - Sound effects
end

--[[
	Called for OTHER PLAYERS (observers/spectators)
	Use this for third-person effects visible to others
]]
function Cloudskip:Observer(originUserId, data)
	local root = Util.getPlayerRoot(originUserId)
	if not root then return end
	
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	local MovementFX = Assets and Assets:FindFirstChild("MovementFX")
	local fxTemplate = MovementFX and MovementFX:FindFirstChild("Cloudskip")
	
	if fxTemplate then
		local fx = fxTemplate:Clone()
		fx.Parent = workspace:FindFirstChild("Effects") or workspace
		
		local direction = data.direction or Vector3.new(0, 0, -1)
		local pivot = CFrame.lookAt(data.position, data.position + direction)
		fx:PivotTo(pivot)
		
		Utils.PlayAttachment(fx, 3)
	end
end

--[[
	Fallback if no specific function is specified
	Automatically determines if caller is User or Observer
]]
function Cloudskip:Execute(originUserId, data)
	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer.UserId == originUserId then
		self:User(originUserId, data)
	else
		self:Observer(originUserId, data)
	end
end

return Cloudskip
