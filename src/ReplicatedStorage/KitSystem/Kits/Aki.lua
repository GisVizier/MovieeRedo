--[[
	Aki Server Kit
	
	Ability: Kon - Summon devil that rushes to target location and bites
	
	Server responsibilities:
	1. Validate spawn location
	2. Start cooldown
	3. Validate hits and apply damage
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local VoxManager = require(ReplicatedStorage.Shared.Modules.VoxManager)
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Hitbox = require(Locations.Shared.Util:WaitForChild("Hitbox"))

-- HitDetectionAPI for authoritative position data
local HitDetectionAPI = nil
local function getHitDetectionAPI()
	if HitDetectionAPI then
		return HitDetectionAPI
	end
	
	local antiCheat = ServerScriptService:FindFirstChild("Server")
		and ServerScriptService.Server:FindFirstChild("Services")
		and ServerScriptService.Server.Services:FindFirstChild("AntiCheat")
	
	if antiCheat then
		local apiModule = antiCheat:FindFirstChild("HitDetectionAPI")
		if apiModule then
			local ok, api = pcall(require, apiModule)
			if ok then
				HitDetectionAPI = api
				return HitDetectionAPI
			end
		end
	end
	
	return nil
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_RANGE = 150
local BITE_DAMAGE = 35
local MAX_HITS_PER_BITE = 5

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
	local self = setmetatable({}, Kit)
	self._ctx = ctx
	self._pendingSpawn = nil
	return self
end

function Kit:SetCharacter(character)
	self._ctx.character = character
end

function Kit:Destroy()
	self._pendingSpawn = nil
end

function Kit:OnEquipped()
end

function Kit:OnUnequipped()
	self._pendingSpawn = nil
end

--------------------------------------------------------------------------------
-- Validation
--------------------------------------------------------------------------------

local function validateTargetPosition(player, character, targetPos)
	if not character then
		return false, "NoCharacter"
	end

	local playerPos = nil
	
	local api = getHitDetectionAPI()
	if api then
		local currentTime = workspace:GetServerTimeNow()
		playerPos = api:GetPositionAtTime(player, currentTime)
	end
	
	if not playerPos then
		local root = character.PrimaryPart 
			or character:FindFirstChild("Root") 
			or character:FindFirstChild("HumanoidRootPart")
		if root then
			playerPos = root.Position
		end
	end
	
	if not playerPos then
		return false, "NoPosition"
	end

	local distance = (targetPos - playerPos).Magnitude
	if distance > MAX_RANGE then
		return false, "OutOfRange"
	end

	return true, nil
end

local function validateHitList(hits)
	if type(hits) ~= "table" then
		return false, "InvalidHits"
	end

	if #hits > MAX_HITS_PER_BITE then
		return false, "TooManyHits"
	end

	return true, nil
end

--------------------------------------------------------------------------------
-- Ability: Kon
--------------------------------------------------------------------------------

function Kit:OnAbility(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end

	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	local service = self._ctx.service

	if not character then
		return false
	end

	clientData = clientData or {}
	local action = clientData.action

	-- Request Kon Spawn
	if action == "requestKonSpawn" then
		local targetPosData = clientData.targetPosition
		if not targetPosData then
			return false
		end

		local targetPos = Vector3.new(
			targetPosData.X or 0,
			targetPosData.Y or 0,
			targetPosData.Z or 0
		)

		local valid, reason = validateTargetPosition(player, character, targetPos)
		if not valid then
			return false
		end

		-- Start cooldown
		if service then
			service:StartCooldown(player)
		end

		-- Store for bite validation
		self._pendingSpawn = {
			position = targetPos,
			time = os.clock(),
		}

		return false
	end

	-- Kon Bite
	if action == "konBite" then
		local hits = clientData.hits
		local bitePosData = clientData.bitePosition

		if not bitePosData then
			return true
		end

		local bitePos = Vector3.new(
			bitePosData.X or 0,
			bitePosData.Y or 0,
			bitePosData.Z or 0
		)

		if hits ~= nil then
			local valid = validateHitList(hits)
			if not valid then
				return true
			end
		end

		-- Validate bite position
		if self._pendingSpawn then
			local spawnDist = (bitePos - self._pendingSpawn.position).Magnitude
			if spawnDist > 20 then
				-- Position mismatch, but don't reject
			end
		end

		-- Server-authoritative damage check at bite position.
		local targets = Hitbox.GetCharactersInRadius(bitePos, BITE_RADIUS, player)
		local appliedHits = 0
		for _, targetCharacter in ipairs(targets) do
			if appliedHits >= MAX_HITS_PER_BITE then
				break
			end

			if targetCharacter and targetCharacter ~= character then
				local humanoid = targetCharacter:FindFirstChildWhichIsA("Humanoid", true)
				if humanoid and humanoid.Health > 0 then
					humanoid:TakeDamage(BITE_DAMAGE)
					appliedHits += 1
				end
			end
		end

		-- Terrain destruction at bite location
		local kitData = KitConfig.getKit("Aki")
		local destructionLevel = kitData and kitData.Ability and kitData.Ability.Destruction
		
		if destructionLevel then
			-- Scale radius based on destruction level
			local radiusMap = {
				Small = 6,
				Big = 10,
				Huge = 15,
				Mega = 22,
			}
			local radius = radiusMap[destructionLevel] or 10
			
			task.spawn(function()
				local success = VoxManager:explode(bitePos, radius, {
					voxelSize = 2,
					debris = true,
					debrisAmount = 8,
				})
				if not success then
					warn("[Aki] Kon destruction failed at position:", bitePos)
				end
			end)
		end

		self._pendingSpawn = nil
		return true
	end

	-- Unknown action
	if service then
		service:StartCooldown(player)
	end

	return true
end

--------------------------------------------------------------------------------
-- Ultimate
--------------------------------------------------------------------------------

function Kit:OnUltimate(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	return true
end

return Kit
