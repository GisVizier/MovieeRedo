local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local Util = require(script.Parent.Util)

local Slide = {}
local active = {}

function Slide:Validate(_player, data)
	if typeof(data) ~= "table" then
		return false
	end
	if data.state == "Start" or data.state == "End" then
		return data.direction == nil or typeof(data.direction) == "Vector3"
	end
	return typeof(data.direction) == "Vector3"
end

function Slide:Execute(originUserId, data)
	local key = "Slide_" .. tostring(originUserId)

	if data.state == "Start" then
		if active[originUserId] then
			return
		end

		local root = Util.getPlayerRoot(originUserId)
		if not root then
			return
		end

		local template = Util.getMovementTemplate("Slide")
		if template then
			VFXPlayer:Start(key, template, root)
			active[originUserId] = true
		end

		if data.direction then
			VFXPlayer:UpdateYaw(key, data.direction)
		end
	else
		VFXPlayer:Stop(key)
		active[originUserId] = nil
	end
end

function Slide:Update(originUserId, data)
	if not data or typeof(data.direction) ~= "Vector3" then
		return
	end
	if not active[originUserId] then
		return
	end
	local key = "Slide_" .. tostring(originUserId)
	VFXPlayer:UpdateYaw(key, data.direction)
end

return Slide
