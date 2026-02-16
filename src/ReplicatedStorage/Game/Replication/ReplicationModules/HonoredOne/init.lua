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
local DEBUG_PROJECTILE_REPLICATION = true
local LOG_INTERVAL = 0.35
local _lastLogByKey = {}

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

local function debugLog(key, ...)
	if not DEBUG_PROJECTILE_REPLICATION then
		return
	end

	local now = os.clock()
	local last = _lastLogByKey[key]
	if last and (now - last) < LOG_INTERVAL then
		return
	end
	_lastLogByKey[key] = now
end

local function resolveReplicatedPlayer(originUserId, data)
	if typeof(data) == "table" then
		local candidate = data.Player
		if typeof(candidate) == "Instance" and candidate:IsA("Player") then
			return candidate
		end

		local playerId = tonumber(data.playerId)
		if playerId then
			local byId = Players:GetPlayerByUserId(playerId)
			if byId then
				return byId
			end
		end
	end

	local fallbackId = tonumber(originUserId)
	if fallbackId then
		return Players:GetPlayerByUserId(fallbackId)
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

local function ReplicateFX(module, action, fxData)
	local clientsFolder = script:FindFirstChild("Clients")
	if not clientsFolder then return end
	local nmodule = clientsFolder:FindFirstChild(module)
	if nmodule then
		local mod = require(nmodule)
		return mod[action](nil, fxData)
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

function HonoredOne:User(originUserId, data)
	local localPlayer = Players.LocalPlayer
	local originPlayer = Players:GetPlayerByUserId(originUserId)
	--if not localPlayer or localPlayer.UserId ~= originUserId then
	--	return -- Only run on caster's client
	--end

	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	local ViewModel = data.ViewModel or (viewmodelController and viewmodelController:GetActiveRig())

	local action = data.forceAction
	if action == "red_charge" and localPlayer.UserId == originUserId then

		local chargingFXcleanup = ReplicateFX("red", "chargeFX", { Character = localPlayer.Character, ViewModel = ViewModel})

		local connection; connection =localPlayer:GetAttributeChangedSignal(`red_charge`):Connect(function()
			if not localPlayer:GetAttribute(`red_charge`) then
				chargingFXcleanup()
				connection:Disconnect()

				--warn(`ran231`)
			end
		end)


	elseif action == "red_create" then
		ReplicateFX("red", "charge", { Character = localPlayer.Character, ViewModel = ViewModel, Part = `Right Arm`})
		ReplicateFX("red", "armFX", { Character = localPlayer.Character, ViewModel = ViewModel, Effect = `createred`})

		task.wait(.1)

		ReplicateFX("red", "createFire", { Character = localPlayer.Character, ViewModel = ViewModel, Effect = `createdmesh`})	

	elseif action == "red_fire" then
		ReplicateFX("red", "armFX", { Character = localPlayer.Character, ViewModel = ViewModel, Effect = `fire`})	
	end

	if action == "red_shootlolll" then
		ReplicateFX("red", "ReplicateProjectile", {
			Character = data.Character,
			Player = originPlayer,
			playerId = originUserId,
			ViewModel = ViewModel,
		})	
		
		
	elseif action == "red_explode" then
		ReplicateFX("red", "explodeplz", {
			Character = localPlayer.Character,
			Player = originPlayer,
			playerId = originUserId,
			pivot = data.pivot,
		})	


	elseif action == "blue_open" then

		ReplicateFX("blue", "open", { 
			Character = data.Character, 
			Player = originPlayer,
			playerId = originUserId,
			projectile = data.projectile, 
			lifetime = data.lifetime
		})	

	elseif action == "blue_loop" then
		--warn(data)
		ReplicateFX("blue", "loop", { 
			Character = data.Character, 
			Player = originPlayer,
			playerId = originUserId,
			projectile = data.projectile, 
			lifetime = data.lifetime
		})	

	elseif action == "blue_close" then

		--ReplicateFX("blue", "close", { 
		--	Character = localPlayer.Character, 
		--	Player = originPlayer,
		--	playerId = originUserId,
		--	projectile = data.projectile, 
		--	lifetime = data.lifetime
		--})	
	end

end

function HonoredOne:UpdateProj(originUserId, data)
	local plr = resolveReplicatedPlayer(originUserId, data)
	local char = data.Character
	local pivot = data.pivot

	if not plr then
		debugLog("red_missing_player_" .. tostring(originUserId), "UpdateProj missing player", "originUserId=", originUserId)
		return
	end
	
	if data.debris then
		plr:SetAttribute(`red_projectile_activeCFR`, nil )
		debugLog("red_debris_" .. tostring(plr.UserId), "UpdateProj clear", plr.Name)
		return
	end

	if typeof(pivot) ~= "CFrame" then
		debugLog("red_bad_pivot_" .. tostring(plr.UserId), "UpdateProj missing/invalid pivot", plr.Name)
		return
	end

	plr:SetAttribute(`red_projectile_activeCFR`, pivot )
	debugLog("red_update_" .. tostring(plr.UserId), "UpdateProj set", plr.Name, tostring(pivot.Position))
end

--------------------------------------------------------------------------------
-- BLUE ABILITY VFX
--------------------------------------------------------------------------------

function HonoredOne:UpdateBlue(originUserId, data)
	local plr = resolveReplicatedPlayer(originUserId, data)
	local char = data.Character
	local pivot = data.pivot

	if not plr then
		debugLog("blue_missing_player_" .. tostring(originUserId), "UpdateBlue missing player", "originUserId=", originUserId)
		return
	end

	if data.debris then
		plr:SetAttribute(`blue_projectile_activeCFR`, nil )
		debugLog("blue_debris_" .. tostring(plr.UserId), "UpdateBlue clear", plr.Name)
		return
	end

	if typeof(pivot) ~= "CFrame" then
		debugLog("blue_bad_pivot_" .. tostring(plr.UserId), "UpdateBlue missing/invalid pivot", plr.Name)
		return
	end

	plr:SetAttribute(`blue_projectile_activeCFR`, pivot )
	debugLog("blue_update_" .. tostring(plr.UserId), "UpdateBlue set", plr.Name, tostring(pivot.Position))
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
