--[[
	Inspect.lua (Shotgun)

	Client-side inspect gating only.
	No viewmodel, VFX, or networking here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local Inspect = {}

function Inspect.Execute(weaponInstance)
	if not weaponInstance or not weaponInstance.State then
		return false, "InvalidInstance"
	end

	local state = weaponInstance.State
	if state.IsReloading or state.IsAttacking then
		return false, "Busy"
	end

	-- Set inspect offset on viewmodel (smoothly transitions)
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	local resetOffset = nil
	if viewmodelController then
		-- Bring weapon closer and tilt it for inspection
		resetOffset = viewmodelController:SetOffset(
			CFrame.new(0.15, -0.05, -0.2) * CFrame.Angles(math.rad(15), math.rad(-20), 0)
		)
	end

	if weaponInstance.PlayAnimation then
		local track = weaponInstance.PlayAnimation("Inspect", 0.1, true)

		-- Reset offset when animation ends
		if track and resetOffset then
			track.Stopped:Once(function()
				resetOffset()
			end)
		end
	end

	return true
end

return Inspect
