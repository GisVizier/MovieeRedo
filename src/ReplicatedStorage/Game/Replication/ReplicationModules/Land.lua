--[[
	Land VFX Module
	
	Plays landing VFX at a world position.
	Safely handles missing assets (MovementFX folder).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXPlayer = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("VFXPlayer"))

local Land = {}

local function getLandTemplate()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	local movementFx = assets:FindFirstChild("MovementFX")
	if not movementFx then
		return nil
	end

	-- Expect a Landing/Land effect in MovementFX (adjust name if needed)
	local template = movementFx:FindFirstChild("Land") or movementFx:FindFirstChild("Landing")
	return template
end

function Land:Validate(player, data)
	if not data or typeof(data) ~= "table" then
		return false
	end
	if not data.position or typeof(data.position) ~= "Vector3" then
		return false
	end
	return true
end

function Land:Execute(originUserId, data)
	if not data or not data.position then
		return
	end

	local template = getLandTemplate()
	if not template then
		return
	end

	VFXPlayer:Play(template, data.position)
end

return Land
