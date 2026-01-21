--[[
	Hurricane VFX Module
	
	Handles visual effects for Airborne's Hurricane ultimate.
	
	Functions:
	- User(originUserId, data) - Called for the caster (first-person effects)
	- Observer(originUserId, data) - Called for other players (third-person effects)
	- Execute(originUserId, data) - Fallback for both (if Function not specified)
	- Stop(originUserId) - Stops the hurricane effect
	
	data:
	- position: Vector3 (center of the hurricane)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Util = require(script.Parent.Util)

local ReturnService = require(ReplicatedStorage.Shared.Util.FXLibaray)
local Utils = ReturnService()

local Hurricane = {}

-- Track active hurricane effects per player
local activeEffects = {}

function Hurricane:Validate(_player, data)
	return typeof(data) == "table"
		and typeof(data.position) == "Vector3"
end

--[[
	Called for the CASTER (the player who used the ability)
	Use this for first-person specific effects
]]
function Hurricane:User(originUserId, data)
	-- Stop any existing hurricane for this player
	self:Stop(originUserId)
	
	local root = Util.getPlayerRoot(originUserId)
	
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	local MovementFX = Assets and Assets:FindFirstChild("MovementFX")
	local fxTemplate = MovementFX and MovementFX:FindFirstChild("Hurricane")
	
	if fxTemplate then
		local fx = fxTemplate:Clone()
		fx.Parent = workspace:FindFirstChild("Effects") or workspace
		fx:PivotTo(CFrame.new(data.position))
		
		activeEffects[originUserId] = fx
		
		Utils.PlayAttachment(fx, 5)
		
		task.delay(5, function()
			if activeEffects[originUserId] == fx then
				activeEffects[originUserId] = nil
			end
		end)
	end
	
	-- TODO: Add first-person specific effects here
	-- - Camera shake
	-- - Wind sounds
	-- - Screen effects
end

--[[
	Called for OTHER PLAYERS (observers/spectators)
	Use this for third-person effects visible to others
]]
function Hurricane:Observer(originUserId, data)
	-- Stop any existing hurricane for this player
	self:Stop(originUserId)
	
	local root = Util.getPlayerRoot(originUserId)
	
	local Assets = ReplicatedStorage:FindFirstChild("Assets")
	local MovementFX = Assets and Assets:FindFirstChild("MovementFX")
	local fxTemplate = MovementFX and MovementFX:FindFirstChild("Hurricane")
	
	if fxTemplate then
		local fx = fxTemplate:Clone()
		fx.Parent = workspace:FindFirstChild("Effects") or workspace
		fx:PivotTo(CFrame.new(data.position))
		
		activeEffects[originUserId] = fx
		
		Utils.PlayAttachment(fx, 5)
		
		task.delay(5, function()
			if activeEffects[originUserId] == fx then
				activeEffects[originUserId] = nil
			end
		end)
	end
end

--[[
	Fallback if no specific function is specified
	Automatically determines if caller is User or Observer
]]
function Hurricane:Execute(originUserId, data)
	local localPlayer = Players.LocalPlayer
	if localPlayer and localPlayer.UserId == originUserId then
		self:User(originUserId, data)
	else
		self:Observer(originUserId, data)
	end
end

function Hurricane:Stop(originUserId)
	local fx = activeEffects[originUserId]
	if fx then
		Utils.ToggleFX(fx, false)
		task.delay(1, function()
			if fx and fx.Parent then
				fx:Destroy()
			end
		end)
		activeEffects[originUserId] = nil
	end
end

return Hurricane
