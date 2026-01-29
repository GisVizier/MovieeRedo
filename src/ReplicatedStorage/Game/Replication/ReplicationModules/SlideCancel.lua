--[[
	SlideCancel VFX Module
	
	Spawns visual effects when a player performs a slide cancel (jump cancel from slide).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SlideCancel = {}

-- Configuration
local VFX_ENABLED = true
local VFX_LIFETIME = 0.3

--[[
	Validates the incoming data
]]
function SlideCancel:Validate(player, data)
	if not data or typeof(data) ~= "table" then
		return false
	end
	if not data.position or typeof(data.position) ~= "Vector3" then
		return false
	end
	return true
end

--[[
	Executes the slide cancel VFX
	
	@param originUserId number - The user ID of the player who triggered the effect
	@param data table - Effect data containing:
		- position: Vector3 - Position to spawn the effect at
]]
function SlideCancel:Execute(originUserId, data)
	if not VFX_ENABLED then
		return
	end
	
	if not data or not data.position then
		return
	end
	
	-- Find the player who triggered this
	local player = Players:GetPlayerByUserId(originUserId)
	if not player then
		return
	end
	
	-- Get the rig for this player (if any)
	local rigsFolder = workspace:FindFirstChild("Rigs")
	if not rigsFolder then
		return
	end
	
	local rigName = player.Name .. "_Rig"
	local rig = rigsFolder:FindFirstChild(rigName)
	if not rig then
		return
	end
	
	-- Simple dust/smoke effect at the position
	-- This could be expanded to spawn actual particle emitters or models
	local position = data.position
	
	-- For now, this is a stub that can be expanded with actual VFX
	-- Example: spawn a quick dust puff particle at the position
	
	-- If you have a VFX assets folder, you could do something like:
	-- local dustEffect = ReplicatedStorage.Assets.VFX.SlideCancelDust:Clone()
	-- dustEffect.Position = position
	-- dustEffect.Parent = workspace
	-- Debris:AddItem(dustEffect, VFX_LIFETIME)
end

return SlideCancel
