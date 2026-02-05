--[[
	HonoredOne Server Kit (Gojo)
	
	Handles server-side validation and damage for HonoredOne's abilities.
	
	Blue (Pull): No damage, terrain destruction at explosion point
	Red (Push): Piercing projectile with body/headshot damage + explosion
	
	Uses standard kit interface (Kit.new, Kit:OnAbility, Kit:OnUltimate)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local VoxManager = require(ReplicatedStorage.Shared.Modules.VoxManager)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Red damage values (server authoritative)
local RED_BODY_DAMAGE = 35
local RED_HEADSHOT_DAMAGE = 90
local RED_EXPLOSION_DAMAGE = 10

local MAX_RANGE = 350            -- Max distance from player for validation
local MAX_TARGETS = 15           -- Max targets to accept per ability use

-- Destruction radius mapping
local DESTRUCTION_RADIUS = {
	Small = 6,
	Big = 10,
	Huge = 15,
	Mega = 22,
}

--------------------------------------------------------------------------------
-- Debug Helpers
--------------------------------------------------------------------------------

local function log(...)
	print("[HonoredOne Server]", ...)
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
	local self = setmetatable({}, Kit)
	self._ctx = ctx
	return self
end

function Kit:SetCharacter(character)
	self._ctx.character = character
end

function Kit:Destroy()
end

function Kit:OnEquipped()
end

function Kit:OnUnequipped()
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getPlayerRoot(player)
	local character = player.Character
	if character then
		return character:FindFirstChild("HumanoidRootPart")
			or character:FindFirstChild("Root")
			or character.PrimaryPart
	end
	return nil
end

local function findTargetCharacter(hit)
	-- Try player by userId
	if hit.playerId then
		local targetPlayer = Players:GetPlayerByUserId(hit.playerId)
		if targetPlayer and targetPlayer.Character then
			return targetPlayer.Character, targetPlayer
		end
	end

	-- Try dummy by name
	if hit.characterName then
		local world = workspace:FindFirstChild("World")
		if world then
			local dummySpawns = world:FindFirstChild("DummySpawns")
			if dummySpawns then
				local found = dummySpawns:FindFirstChild(hit.characterName)
				if found then return found, nil end
			end
		end
		local found = workspace:FindFirstChild(hit.characterName)
		if found then return found, nil end
	end

	return nil, nil
end

--------------------------------------------------------------------------------
-- Blue Ability Handler (Pull / Vacuum - knockback only + destruction)
--------------------------------------------------------------------------------

local function handleBlueHit(self, clientData)
	local player = self._ctx.player
	local service = self._ctx.service

	log("=== BLUE HIT ===", player.Name)

	-- Start cooldown
	if service then
		service:StartCooldown(player)
	end

	-- Terrain destruction at explosion position
	local posData = clientData.explosionPosition
	if not posData or type(posData) ~= "table" then
		log("No explosion position provided")
		return
	end

	local explosionPos = Vector3.new(posData.X or 0, posData.Y or 0, posData.Z or 0)

	-- Validate range
	local root = getPlayerRoot(player)
	if not root then
		log("Player has no root part")
		return
	end

	if (root.Position - explosionPos).Magnitude > MAX_RANGE then
		log("Explosion position out of range - skipping destruction")
		return
	end

	local kitData = KitConfig.getKit("HonoredOne")
	local destructionLevel = kitData and kitData.Ability and kitData.Ability.Destruction
	if not destructionLevel then
		return
	end

	local radius = DESTRUCTION_RADIUS[destructionLevel] or 10

	task.spawn(function()
		local success = VoxManager:explode(explosionPos, radius, {
			voxelSize = 2,
			debris = true,
			debrisAmount = 8,
		})
		if not success then
			warn("[HonoredOne] Blue destruction failed at:", explosionPos)
		end
	end)

	log("Terrain destruction at", explosionPos, "radius:", radius)
end

--------------------------------------------------------------------------------
-- Red Ability Handler (Piercing Projectile - damage + explosion)
--------------------------------------------------------------------------------

local function handleRedHit(self, clientData)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character

	log("=== RED HIT ===", player.Name)

	if not clientData.hits or type(clientData.hits) ~= "table" then
		log("Invalid hit list")
		return
	end

	local root = getPlayerRoot(player)
	local playerPosition = root and root.Position or nil

	-- Validate and process hits
	local validHits = {}

	for i, hit in ipairs(clientData.hits) do
		if i > MAX_TARGETS then break end
		if type(hit) ~= "table" then continue end

		local targetChar, targetPlayer = findTargetCharacter(hit)
		if not targetChar then continue end

		-- Range check
		if playerPosition then
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
				or targetChar:FindFirstChild("Root")
				or targetChar.PrimaryPart
			if targetRoot and (targetRoot.Position - playerPosition).Magnitude > MAX_RANGE then
				log("Target out of range:", hit.characterName)
				continue
			end
		end

		-- Server-authoritative damage
		local damage
		if hit.isExplosion then
			damage = RED_EXPLOSION_DAMAGE
		elseif hit.isHeadshot then
			damage = RED_HEADSHOT_DAMAGE
		else
			damage = RED_BODY_DAMAGE
		end

		table.insert(validHits, {
			character = targetChar,
			player = targetPlayer,
			isHeadshot = hit.isHeadshot,
			isExplosion = hit.isExplosion,
			damage = damage,
		})

		log("Validated:", targetChar.Name, hit.isHeadshot and "(HEADSHOT)" or (hit.isExplosion and "(explosion)" or "(body)"))
	end

	log("Valid hits:", #validHits)

	if #validHits == 0 then
		return
	end

	-- Apply damage
	for _, hit in ipairs(validHits) do
		local humanoid = hit.character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid:TakeDamage(hit.damage)
			log("Dealt", hit.damage, "to", hit.character.Name)
		end
	end

	log("=== RED HIT COMPLETE ===")
end

--------------------------------------------------------------------------------
-- Kit Interface (standard)
--------------------------------------------------------------------------------

function Kit:OnAbility(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end

	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	if not character then
		return false
	end

	clientData = clientData or {}
	local action = clientData.action

	if action == "blueHit" then
		handleBlueHit(self, clientData)
		return true
	elseif action == "redHit" then
		handleRedHit(self, clientData)
		return true
	else
		log("Unknown action:", tostring(action), "from", player.Name)
	end

	return false
end

function Kit:OnUltimate(inputState, clientData)
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	log("Ultimate from", self._ctx.player.Name, "- not implemented")
	return true
end

return Kit
