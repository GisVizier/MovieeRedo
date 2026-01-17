local WhiteBeardVFX = {}
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

--[[
	Effect: QuakeBall
	Description: Creates a growing sphere representing the quake bubble
	Params:
		- Position (Vector3): Where to spawn
		- Radius (Number): Final size (default 12)
		- Duration (Number): How long to expand (default 0.5)
]]
function WhiteBeardVFX.QuakeBall(data)
	local position = data.Position
	if not position then return end
	
	local radius = data.Params and data.Params.Radius or 12
	local duration = data.Params and data.Params.Duration or 0.3
	
	-- "HERES WHERE YOU PUT YOUR STUFF"
end

return WhiteBeardVFX
