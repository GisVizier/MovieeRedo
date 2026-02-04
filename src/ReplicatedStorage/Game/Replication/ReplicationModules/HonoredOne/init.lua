--[[
	HonoredOne VFX Module (Gojo)
	
	Handles visual effects for Gojo's Red and Blue abilities.
	
	RED ABILITY (Crouch + E):
	- redStart(originUserId, data) - Start charging VFX
	- redCharge(originUserId, data) - Charging loop VFX (intensity based on charge)
	- redShoot(originUserId, data) - Projectile fired VFX
	- redExplode(originUserId, data) - Explosion VFX at impact point
	
	BLUE ABILITY (E without crouch):
	- blueStart(originUserId, data) - Create blue sphere VFX
	- blueUpdate(originUserId, data) - Update position (called each tick)
	- blueEnd(originUserId, data) - End explosion VFX
	
	Data structures:
	- Red: { position, direction, chargePercent, speed, radius }
	- Blue: { position, radius }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Util = require(script.Parent.Util)
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local HonoredOne = {}

--------------------------------------------------------------------------------
-- Active VFX tracking
--------------------------------------------------------------------------------

HonoredOne._activeBlue = {}      -- { [userId] = { ... } }
HonoredOne._activeRed = {}       -- { [userId] = { ... } }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getEffectsFolder()
	local folder = Workspace:FindFirstChild("Effects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = Workspace
	end
	return folder
end

local function parseVector3(data)
	if typeof(data) == "Vector3" then
		return data
	elseif typeof(data) == "table" then
		return Vector3.new(data.X or 0, data.Y or 0, data.Z or 0)
	end
	return nil
end

local function getPlayerRoot(userId)
	local player = Players:GetPlayerByUserId(userId)
	if player and player.Character then
		return player.Character:FindFirstChild("HumanoidRootPart") 
			or player.Character:FindFirstChild("Root")
	end
	return nil
end

local function cleanupUserVFX(userId, vfxType)
	local storage = vfxType == "red" and HonoredOne._activeRed or HonoredOne._activeBlue
	local active = storage[userId]
	if active then
		for key, obj in pairs(active) do
			if typeof(obj) == "Instance" and obj.Parent then
				obj:Destroy()
			end
		end
		storage[userId] = nil
	end
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

function HonoredOne:Validate(_player, data)
	return typeof(data) == "table"
end

--------------------------------------------------------------------------------
-- RED ABILITY VFX
--------------------------------------------------------------------------------

--[[
	Called when Red ability starts charging
	data: { position }
]]
function HonoredOne:redStart(originUserId, data)
	cleanupUserVFX(originUserId, "red")
	
	local position = parseVector3(data.position)
	local root = getPlayerRoot(originUserId)
	
	-- TODO: Add your charging VFX here
	
	HonoredOne._activeRed[originUserId] = {
		startTime = tick(),
	}
end

--[[
	Called to update charge VFX intensity
	data: { chargePercent (0-1), position }
]]
function HonoredOne:redCharge(originUserId, data)
	local active = HonoredOne._activeRed[originUserId]
	if not active then return end
	
	local chargePercent = data.chargePercent or 0
	local position = parseVector3(data.position)
	
	-- TODO: Add your charge update VFX here
end

--[[
	Called when Red projectile is fired
	data: { startPosition, direction, speed }
]]
function HonoredOne:redShoot(originUserId, data)
	local active = HonoredOne._activeRed[originUserId]
	
	local startPosition = parseVector3(data.startPosition) or parseVector3(data.position)
	local direction = parseVector3(data.direction)
	local speed = data.speed or 400
	
	-- TODO: Add your projectile VFX here
	
	HonoredOne._activeRed[originUserId] = {
		startPosition = startPosition,
		direction = direction,
		speed = speed,
		startTime = tick(),
	}
end

--[[
	Update projectile position (call each frame if needed)
	data: { position }
]]
function HonoredOne:redUpdate(originUserId, data)
	local active = HonoredOne._activeRed[originUserId]
	if not active then return end
	
	local position = parseVector3(data.position)
	
	-- TODO: Add your projectile update VFX here
end

--[[
	Called when Red projectile explodes
	data: { position, radius }
]]
function HonoredOne:redExplode(originUserId, data)
	local position = parseVector3(data.position)
	local radius = data.radius or 20
	
	-- TODO: Add your explosion VFX here
	
	cleanupUserVFX(originUserId, "red")
end

--------------------------------------------------------------------------------
-- BLUE ABILITY VFX
--------------------------------------------------------------------------------

--[[
	Called when Blue ability starts (create hitbox visual)
	data: { position, radius }
]]
function HonoredOne:blueStart(originUserId, data)
	cleanupUserVFX(originUserId, "blue")
	
	local position = parseVector3(data.position)
	local radius = data.radius or 14
	
	-- TODO: Add your blue sphere VFX here
	
	HonoredOne._activeBlue[originUserId] = {
		radius = radius,
		startTime = tick(),
	}
end

--[[
	Update blue hitbox position (call each tick)
	data: { position }
]]
function HonoredOne:blueUpdate(originUserId, data)
	local active = HonoredOne._activeBlue[originUserId]
	if not active then return end
	
	local position = parseVector3(data.position)
	
	-- TODO: Add your blue update VFX here
end

--[[
	Called when Blue ability ends (explosion)
	data: { position, radius }
]]
function HonoredOne:blueEnd(originUserId, data)
	local position = parseVector3(data.position)
	local radius = data.radius or 14
	
	-- TODO: Add your blue end/explosion VFX here
	
	cleanupUserVFX(originUserId, "blue")
end

--------------------------------------------------------------------------------
-- Execute (fallback routing)
--------------------------------------------------------------------------------

function HonoredOne:Execute(originUserId, data)
	local action = data.action or data.forceAction
	if action then
		if self[action] then
			self[action](self, originUserId, data)
		else
			warn("[HonoredOne VFX] Unknown action:", action)
		end
	end
end

--------------------------------------------------------------------------------
-- Cleanup on player leave
--------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	cleanupUserVFX(player.UserId, "red")
	cleanupUserVFX(player.UserId, "blue")
end)

return HonoredOne
