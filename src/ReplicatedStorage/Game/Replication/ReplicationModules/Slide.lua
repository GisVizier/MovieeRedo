--[[
	Slide VFX Module
	
	Plays sliding VFX at a world position.
	Safely handles missing assets (MovementFX folder).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXPlayer = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("VFXPlayer"))

local Slide = {}

local function getSlideTemplate()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	local movementFx = assets:FindFirstChild("MovementFX")
	if not movementFx then
		return nil
	end

	-- Expect a Slide/Sliding effect in MovementFX (adjust name if needed)
	local template = movementFx:FindFirstChild("Slide") or movementFx:FindFirstChild("Sliding")
	return template
end

function Slide:Validate(player, data)
	if not data or typeof(data) ~= "table" then
		return false
	end
	if not data.position or typeof(data.position) ~= "Vector3" then
		return false
	end
	return true
end

function Slide:Execute(originUserId, data)
	if not data or not data.position then
		return
	end

	local template = getSlideTemplate()
	if not template then
		return
	end

	VFXPlayer:Play(template, data.position)
end

return Slide
