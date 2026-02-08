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
local VoxelDestruction = require(ReplicatedStorage.Shared.Modules.VoxelDestruction)

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
	log("Blue hit payload:", clientData and clientData.explosionPosition and "has explosionPosition" or "missing explosionPosition")

	-- Cooldown already started at "open" event via startCooldown action

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
		-- Create hitbox for destruction
		local hitbox = Instance.new("Part")
		hitbox.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		hitbox.Position = explosionPos
		hitbox.Shape = Enum.PartType.Ball
		hitbox.Anchored = true
		hitbox.CanCollide = false
		hitbox.CanQuery = true
		hitbox.Transparency = 1
		hitbox.Parent = workspace
		
		-- excludePlayer = player: the originating client already did local destruction
		-- for instant feedback, so only replicate to other clients
		VoxelDestruction.Destroy(
			hitbox,
			nil, -- OverlapParams
			2, -- voxelSize
			8, -- debrisCount
			nil, -- reset (uses default)
			player -- excludePlayer: skip originator (they already did local destruction)
		)
		
		-- Delay cleanup so clients have time to receive and process the replicated hitbox
		task.delay(2, function()
			if hitbox and hitbox.Parent then
				hitbox:Destroy()
			end
		end)
	end)

	log("Terrain destruction at", explosionPos, "radius:", radius)
end

--------------------------------------------------------------------------------
-- Blue Destruction Tick Handler (continuous destruction during blue movement)
--------------------------------------------------------------------------------

local function handleBlueDestruction(self, clientData)
	local player = self._ctx.player

	log("Blue destruction payload:", clientData and clientData.position and "has position" or "missing position")
	local posData = clientData.position
	if not posData or type(posData) ~= "table" then
		return
	end

	local position = Vector3.new(posData.X or 0, posData.Y or 0, posData.Z or 0)
	local radius = clientData.radius or 8

	-- Validate range
	local root = getPlayerRoot(player)
	if not root then
		return
	end

	if (root.Position - position).Magnitude > MAX_RANGE then
		return
	end

	-- Clamp radius to prevent abuse
	radius = math.clamp(radius, 1, 25)

	task.spawn(function()
		local hitbox = Instance.new("Part")
		hitbox.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		hitbox.Position = position
		hitbox.Shape = Enum.PartType.Ball
		hitbox.Anchored = true
		hitbox.CanCollide = false
		hitbox.CanQuery = true
		hitbox.Transparency = 1
		hitbox.Parent = workspace

		-- excludePlayer = player: the originating client already did local destruction
		-- for instant feedback, so only replicate to other clients
		VoxelDestruction.Destroy(
			hitbox,
			nil, -- OverlapParams
			2, -- voxelSize
			5, -- debrisCount
			nil, -- reset (uses default)
			player -- excludePlayer: skip originator (they already did local destruction)
		)

		-- Delay cleanup so clients have time to receive and process the replicated hitbox
		task.delay(2, function()
			if hitbox and hitbox.Parent then
				hitbox:Destroy()
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Red Ability Handler (Piercing Projectile - damage + explosion)
--------------------------------------------------------------------------------

local function handleRedHit(self, clientData)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character

	log("=== RED HIT ===", player.Name)
	log("Red hit payload:", clientData and clientData.explosionPosition and "has explosionPosition" or "missing explosionPosition")

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

	-- Red explosion terrain destruction (replicate to all clients except originator)
	local posData = clientData.explosionPosition
	if posData and type(posData) == "table" then
		local explosionPos = Vector3.new(posData.X or 0, posData.Y or 0, posData.Z or 0)

		-- Validate range
		if root and (root.Position - explosionPos).Magnitude <= MAX_RANGE then
			task.spawn(function()
				local hitbox = Instance.new("Part")
				hitbox.Size = Vector3.new(20 * 2, 20 * 2, 20 * 2) -- RED_CONFIG.EXPLOSION_RADIUS = 20
				hitbox.Position = explosionPos
				hitbox.Shape = Enum.PartType.Ball
				hitbox.Anchored = true
				hitbox.CanCollide = false
				hitbox.CanQuery = true
				hitbox.Transparency = 1
				hitbox.Parent = workspace

				VoxelDestruction.Destroy(
					hitbox,
					nil, -- OverlapParams
					2, -- voxelSize
					5, -- debrisCount
					nil, -- reset (uses default)
					player -- excludePlayer: skip originator (they already did local destruction)
				)

				task.delay(2, function()
					if hitbox and hitbox.Parent then
						hitbox:Destroy()
					end
				end)
			end)

			log("Red explosion destruction at", explosionPos)
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
	log("OnAbility action:", action or "nil", "player:", player.Name)

	if action == "startCooldown" then
		-- Start cooldown when ability commits (open for Blue, shoot for Red)
		local service = self._ctx.service
		if service then
			service:StartCooldown(player)
		end
		return false -- Don't end ability, just started cooldown
	elseif action == "blueDestruction" then
		-- Periodic destruction tick during blue movement (replicate to all clients)
		log("Blue destruction tick received")
		handleBlueDestruction(self, clientData)
		return false -- Don't end ability, just a destruction tick
	elseif action == "blueHit" then
		log("Blue hit received")
		handleBlueHit(self, clientData)
		return true
	elseif action == "redHit" then
		log("Red hit received")
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
