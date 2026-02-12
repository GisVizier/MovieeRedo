--[[
	HonoredOne Server Kit (Gojo)
	
	Handles server-side validation and damage for HonoredOne's abilities.
	
	Blue (Pull): No damage, terrain destruction at explosion point
	Red (Push): Piercing projectile with body/headshot damage + explosion
	
	Uses standard kit interface (Kit.new, Kit:OnAbility, Kit:OnUltimate)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local VoxelDestruction = require(ReplicatedStorage.Shared.Modules.VoxelDestruction)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Red damage values (server authoritative)
local RED_BODY_DAMAGE = 35
local RED_HEADSHOT_DAMAGE = 90
local RED_EXPLOSION_DAMAGE = 10

local MAX_RANGE = 3000 -- Max distance from player for validation
local MAX_TARGETS = 15 -- Max targets to accept per ability use
local RED_MAX_HIT_DISTANCE = 700 -- Plausible distance from attacker to victim/hit
local RED_EXPLOSION_RADIUS = 20
local RED_EXPLOSION_HIT_BUFFER = 6

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

local function log(...) end
local DEBUG_PROJECTILE_RELAY = true
local RELAY_LOG_INTERVAL = 0.25
local _lastRelayLogByKey = {}

local function relayDebugLog(key, ...)
	if not DEBUG_PROJECTILE_RELAY then
		return
	end

	local now = os.clock()
	local last = _lastRelayLogByKey[key]
	if last and (now - last) < RELAY_LOG_INTERVAL then
		return
	end
	_lastRelayLogByKey[key] = now
	warn("[HonoredOneKitRelay]", ...)
end

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
	local self = setmetatable({}, Kit)
	self._ctx = ctx
	self._blueActive = false -- Track if Blue ability is active (for damage interrupt)
	return self
end

function Kit:SetCharacter(character)
	self._ctx.character = character
end

function Kit:Destroy()
	self._blueActive = false
end

function Kit:OnEquipped() end

function Kit:OnUnequipped()
	self._blueActive = false
end

--[[
	Called by KitService when this player takes damage.
	If Blue is active, interrupt it immediately.
]]
function Kit:OnDamageTaken(damage, source)
	if not self._blueActive then
		return
	end
	
	-- Blue should cancel on damage
	self._blueActive = false
	
	local service = self._ctx and self._ctx.service
	if service and service.InterruptAbility then
		service:InterruptAbility(self._ctx.player, "Ability", "damage_taken")
	end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getPlayerRoot(player)
	local character = player.Character
	if character then
		return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root") or character.PrimaryPart
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
				if found then
					return found, nil
				end
			end
		end

		-- Recursive fallback for dummies nested under maps/folders.
		local found = workspace:FindFirstChild(hit.characterName, true)
		if found then
			return found, nil
		end

		-- Tagged dummy fallback used elsewhere in the framework.
		for _, tagged in CollectionService:GetTagged("AimAssistTarget") do
			if tagged:IsA("Model") and tagged.Name == hit.characterName then
				return tagged, nil
			end
		end
	end

	return nil, nil
end

local function getKitRegistry(self)
	local service = self._ctx and self._ctx.service
	return service and service._registry or nil
end

local function getCombatService(self)
	local registry = getKitRegistry(self)
	return registry and registry:TryGet("CombatService") or nil
end

local function getMatchManager(self)
	local registry = getKitRegistry(self)
	return registry and registry:TryGet("MatchManager") or nil
end

local function getCharacterRoot(character)
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root") or character.PrimaryPart
end

local function toVector3(data)
	if type(data) ~= "table" then
		return nil
	end
	if type(data.X) ~= "number" or type(data.Y) ~= "number" or type(data.Z) ~= "number" then
		return nil
	end
	return Vector3.new(data.X, data.Y, data.Z)
end

local function resolveBlueUpdatePivot(clientData)
	local pivot = clientData and clientData.pivot
	if typeof(pivot) == "CFrame" then
		return pivot, "cframe"
	end

	local position = toVector3(clientData and clientData.position)
	if position then
		return CFrame.new(position), "position"
	end

	return nil, "missing"
end

local function resolveRedUpdatePivot(clientData)
	local pivot = clientData and clientData.pivot
	if typeof(pivot) == "CFrame" then
		return pivot, "cframe"
	end

	local position = toVector3(clientData and clientData.position)
	local direction = toVector3(clientData and clientData.direction)
	if position and direction and direction.Magnitude > 0.01 then
		return CFrame.lookAt(position, position + direction.Unit), "position+direction"
	end
	if position then
		return CFrame.new(position), "position"
	end

	return nil, "missing"
end

local function isSameMatchContext(self, attacker, targetPlayer)
	local matchManager = getMatchManager(self)
	if not matchManager then
		return true
	end

	local attackerMatch = matchManager:GetMatchForPlayer(attacker)
	local targetMatch = matchManager:GetMatchForPlayer(targetPlayer)
	if attackerMatch or targetMatch then
		return attackerMatch ~= nil and attackerMatch == targetMatch
	end

	-- Fallback for training context (non-competitive)
	local attackerArea = attacker:GetAttribute("CurrentArea")
	local targetArea = targetPlayer:GetAttribute("CurrentArea")
	if attackerArea and targetArea then
		return attackerArea == targetArea
	end

	return false
end

local function applyValidatedDamage(
	self,
	attacker,
	targetCharacter,
	targetPlayer,
	damage,
	isHeadshot,
	sourcePos,
	hitPos
)
	local humanoid = targetCharacter and targetCharacter:FindFirstChildWhichIsA("Humanoid", true)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local combatService = getCombatService(self)
	local victimHandle = targetPlayer
	if not victimHandle and combatService then
		victimHandle = combatService:GetPlayerByCharacter(targetCharacter)
	end

	if victimHandle and combatService then
		local impactDirection = nil
		if typeof(sourcePos) == "Vector3" and typeof(hitPos) == "Vector3" then
			local delta = hitPos - sourcePos
			if delta.Magnitude > 0.001 then
				impactDirection = delta.Unit
			end
		end

		combatService:ApplyDamage(victimHandle, damage, {
			source = attacker,
			isHeadshot = isHeadshot == true,
			weaponId = "HonoredOne_Red",
			damageType = "KitAbility",
			sourcePosition = sourcePos,
			hitPosition = hitPos,
			impactDirection = impactDirection,
		})
		return
	end

	humanoid:TakeDamage(damage)
	if targetCharacter then
		targetCharacter:SetAttribute("LastDamageDealer", attacker.UserId)
		targetCharacter:SetAttribute("WasHeadshot", isHeadshot == true)
	end
end

local ALLOWED_RELAY_FORCE_ACTION = {
	blue_open = true,
	blue_loop = true,
	blue_close = true,
	red_shootlolll = true,
	red_explode = true,
}

local function relayHonoredOneVfx(self, player, functionName, payload)
	local service = self._ctx and self._ctx.service
	if not service or not service.BroadcastVFXMatchScoped then
		return
	end
	service:BroadcastVFXMatchScoped(player, "HonoredOne", payload, functionName, false)
end

local function handleBlueProjectileUpdate(self, clientData)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	if not character then
		return
	end

	if clientData and clientData.debris == true then
		-- Blue ended (debris = cleanup)
		self._blueActive = false
		player:SetAttribute("blue_projectile_activeCFR", nil)
		relayDebugLog("blue_debris_" .. tostring(player.UserId), "blueProjectileUpdate clear", player.Name)
		relayHonoredOneVfx(self, player, "UpdateBlue", {
			Player = player,
			playerId = player.UserId,
			Character = character,
			debris = true,
		})
		return
	end
	
	-- Blue is active (receiving position updates)
	self._blueActive = true

	local pivot, pivotSource = resolveBlueUpdatePivot(clientData)
	if typeof(pivot) ~= "CFrame" then
		relayDebugLog(
			"blue_bad_pivot_" .. tostring(player.UserId),
			"blueProjectileUpdate reject bad pivot",
			player.Name,
			"source=",
			pivotSource
		)
		return
	end

	local root = getPlayerRoot(player)
	if not root then
		relayDebugLog("blue_no_root_" .. tostring(player.UserId), "blueProjectileUpdate reject no root", player.Name)
		return
	end

	-- VFX replication state should not hard-reject by distance; apply directly.
	player:SetAttribute("blue_projectile_activeCFR", pivot)

	relayDebugLog(
		"blue_ok_" .. tostring(player.UserId),
		"blueProjectileUpdate relay",
		player.Name,
		"source=",
		pivotSource,
		tostring(pivot.Position)
	)
	relayHonoredOneVfx(self, player, "UpdateBlue", {
		Player = player,
		playerId = player.UserId,
		Character = character,
		pivot = pivot,
		radius = tonumber(clientData and clientData.radius),
	})
end

local function handleRedProjectileUpdate(self, clientData)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	if not character then
		return
	end

	if clientData and clientData.debris == true then
		player:SetAttribute("red_projectile_activeCFR", nil)
		relayDebugLog("red_debris_" .. tostring(player.UserId), "redProjectileUpdate clear", player.Name)
		relayHonoredOneVfx(self, player, "UpdateProj", {
			Player = player,
			playerId = player.UserId,
			Character = character,
			debris = true,
		})
		return
	end

	local pivot, pivotSource = resolveRedUpdatePivot(clientData)
	if typeof(pivot) ~= "CFrame" then
		relayDebugLog(
			"red_bad_pivot_" .. tostring(player.UserId),
			"redProjectileUpdate reject bad pivot",
			player.Name,
			"source=",
			pivotSource
		)
		return
	end

	local root = getPlayerRoot(player)
	if not root then
		relayDebugLog("red_no_root_" .. tostring(player.UserId), "redProjectileUpdate reject no root", player.Name)
		return
	end

	-- VFX replication state should not hard-reject by distance; apply directly.
	player:SetAttribute("red_projectile_activeCFR", pivot)

	relayDebugLog(
		"red_ok_" .. tostring(player.UserId),
		"redProjectileUpdate relay",
		player.Name,
		"source=",
		pivotSource,
		tostring(pivot.Position)
	)
	relayHonoredOneVfx(self, player, "UpdateProj", {
		Player = player,
		playerId = player.UserId,
		Character = character,
		pivot = pivot,
	})
end

local function handleUserVfxRelay(self, clientData)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	if not character then
		return
	end

	local forceAction = clientData and clientData.forceAction
	if type(forceAction) ~= "string" or not ALLOWED_RELAY_FORCE_ACTION[forceAction] then
		relayDebugLog(
			"user_bad_action_" .. tostring(player.UserId),
			"relayUserVfx reject action",
			player.Name,
			tostring(forceAction)
		)
		return
	end

	local payload = {
		Character = character,
		forceAction = forceAction,
	}

	if typeof(clientData.pivot) == "CFrame" then
		payload.pivot = clientData.pivot
	end
	if type(clientData.lifetime) == "number" then
		payload.lifetime = clientData.lifetime
	end
	if type(clientData.radius) == "number" then
		payload.radius = clientData.radius
	end

	relayDebugLog(
		"user_ok_" .. tostring(player.UserId) .. "_" .. forceAction,
		"relayUserVfx relay",
		player.Name,
		forceAction
	)
	relayHonoredOneVfx(self, player, "User", payload)
end

--------------------------------------------------------------------------------
-- Blue Ability Handler (Pull / Vacuum - knockback only + destruction)
--------------------------------------------------------------------------------

local function handleBlueHit(self, clientData)
	local player = self._ctx.player
	local service = self._ctx.service
	
	-- Blue completed - mark as inactive
	self._blueActive = false

	log("=== BLUE HIT ===", player.Name)
	log(
		"Blue hit payload:",
		clientData and clientData.explosionPosition and "has explosionPosition" or "missing explosionPosition"
	)

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

	local distance = (root.Position - explosionPos).Magnitude
	if distance > MAX_RANGE then
		log("Explosion position out of range - skipping destruction", "distance:", math.floor(distance + 0.5))
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
		hitbox.CanQuery = false
		hitbox.Transparency = 1
		hitbox.Parent = workspace

		-- excludePlayer = player: the originating client already did local destruction
		-- for instant feedback, so only replicate to other clients
		VoxelDestruction.Destroy(
			hitbox,
			nil, -- OverlapParams
			2, -- voxelSize
			8, -- debrisCount
			nil -- reset (uses default)
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

	local distance = (root.Position - position).Magnitude
	if distance > MAX_RANGE then
		log("Blue destruction out of range", "distance:", math.floor(distance + 0.5))
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
		hitbox.CanQuery = false
		hitbox.Transparency = 1
		hitbox.Parent = workspace

		-- excludePlayer = player: the originating client already did local destruction
		-- for instant feedback, so only replicate to other clients
		VoxelDestruction.Destroy(
			hitbox,
			nil, -- OverlapParams
			2, -- voxelSize
			5, -- debrisCount
			nil -- reset (uses default)
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
-- Red Destruction Handler (server-side voxel destruction on red impact)
--------------------------------------------------------------------------------

local function handleRedDestruction(self, clientData)
	local player = self._ctx.player
	local root = getPlayerRoot(player)
	if not root then
		return
	end

	local position = toVector3(clientData and clientData.position)
	if not position then
		return
	end

	local distance = (root.Position - position).Magnitude
	if distance > RED_MAX_HIT_DISTANCE then
		log("Red destruction out of range", "distance:", math.floor(distance + 0.5))
		return
	end

	local kitData = KitConfig.getKit("HonoredOne")
	local destructionLevel = kitData and kitData.Ability and kitData.Ability.Destruction
	local configRadius = destructionLevel and DESTRUCTION_RADIUS[destructionLevel] or 10

	local clientRadius = tonumber(clientData and clientData.radius) or RED_EXPLOSION_RADIUS
	clientRadius = math.clamp(clientRadius, 4, 30)

	local radius = math.max(configRadius, clientRadius)

	task.spawn(function()
		local hitbox = Instance.new("Part")
		hitbox.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		hitbox.Position = position
		hitbox.Shape = Enum.PartType.Ball
		hitbox.Anchored = true
		hitbox.CanCollide = false
		hitbox.CanQuery = false
		hitbox.Transparency = 1
		hitbox.Parent = workspace

		VoxelDestruction.Destroy(
			hitbox,
			nil,
			2,
			10,
			nil
		)

		task.delay(2, function()
			if hitbox and hitbox.Parent then
				hitbox:Destroy()
			end
		end)
	end)

	log("Red destruction at", position, "radius:", radius)
end

--------------------------------------------------------------------------------
-- Red Ability Handler (Piercing Projectile - damage + explosion)
--------------------------------------------------------------------------------

local function handleRedHit(self, clientData)
	local player = self._ctx.player
	local character = self._ctx.character or player.Character

	log("=== RED HIT ===", player.Name)
	log(
		"Red hit payload:",
		clientData and clientData.explosionPosition and "has explosionPosition" or "missing explosionPosition"
	)

	if not clientData.hits or type(clientData.hits) ~= "table" then
		log("Invalid hit list")
		return
	end

	-- Ownership / identity validation
	if not character or character ~= player.Character then
		log("Rejected redHit: attacker character mismatch")
		return
	end

	local root = getPlayerRoot(player)
	local playerPosition = root and root.Position or nil
	if not playerPosition then
		log("Rejected redHit: attacker has no root")
		return
	end

	local explosionPos = toVector3(clientData.explosionPosition)
	if not explosionPos then
		log("Rejected redHit: missing explosionPosition")
		return
	end
	if (explosionPos - playerPosition).Magnitude > RED_MAX_HIT_DISTANCE then
		log("Rejected redHit: explosion out of plausible range")
		return
	end

	-- Validate and process hits
	local validHits = {}
	local seenTargets = {}

	for i, hit in ipairs(clientData.hits) do
		if i > MAX_TARGETS then
			break
		end
		if type(hit) ~= "table" then
			continue
		end

		local targetChar, targetPlayer = findTargetCharacter(hit)
		if not targetChar then
			continue
		end
		if targetPlayer == player then
			continue
		end

		-- Dedup by target identity
		local targetKey = targetPlayer and `plr:{targetPlayer.UserId}` or `char:{targetChar:GetFullName()}`
		if seenTargets[targetKey] then
			continue
		end

		-- Range check
		local targetRoot = getCharacterRoot(targetChar)
		if targetRoot then
			local attackerToTarget = (targetRoot.Position - playerPosition).Magnitude
			if attackerToTarget > RED_MAX_HIT_DISTANCE then
				log("Target out of plausible range:", targetChar.Name)
				continue
			end
		end

		-- Match-scoped player validation
		if targetPlayer and not isSameMatchContext(self, player, targetPlayer) then
			log("Rejected redHit target outside match context:", targetPlayer.Name)
			continue
		end

		-- Validate hit entry geometry
		local hitPos = toVector3(hit.hitPosition)
		local isExplosion = hit.isExplosion == true
		if isExplosion then
			if targetRoot then
				local distFromExplosion = (targetRoot.Position - explosionPos).Magnitude
				if distFromExplosion > (RED_EXPLOSION_RADIUS + RED_EXPLOSION_HIT_BUFFER) then
					continue
				end
			end
		elseif hitPos then
			if (hitPos - playerPosition).Magnitude > RED_MAX_HIT_DISTANCE then
				continue
			end
		end

		-- Server-authoritative damage
		local damage
		if isExplosion then
			damage = RED_EXPLOSION_DAMAGE
		elseif hit.isHeadshot then
			damage = RED_HEADSHOT_DAMAGE
		else
			damage = RED_BODY_DAMAGE
		end

		table.insert(validHits, {
			character = targetChar,
			player = targetPlayer,
			isHeadshot = hit.isHeadshot == true,
			isExplosion = isExplosion,
			damage = damage,
			hitPosition = hitPos,
		})
		seenTargets[targetKey] = true

		log(
			"Validated:",
			targetChar.Name,
			hit.isHeadshot and "(HEADSHOT)" or (hit.isExplosion and "(explosion)" or "(body)")
		)
	end

	log("Valid hits:", #validHits)

	if #validHits == 0 then
		return
	end

	-- Apply damage
	for _, hit in ipairs(validHits) do
		applyValidatedDamage(
			self,
			player,
			hit.character,
			hit.player,
			hit.damage,
			hit.isHeadshot and not hit.isExplosion,
			playerPosition,
			hit.hitPosition or explosionPos
		)
		log("Dealt", hit.damage, "to", hit.character.Name)
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
	elseif action == "blueProjectileUpdate" then
		handleBlueProjectileUpdate(self, clientData)
		return false
	elseif action == "redProjectileUpdate" then
		handleRedProjectileUpdate(self, clientData)
		return false
	elseif action == "relayUserVfx" then
		handleUserVfxRelay(self, clientData)
		return false
	elseif action == "blueHit" then
		log("Blue hit received")
		handleBlueHit(self, clientData)
		return true
	elseif action == "redHit" then
		log("Red hit received")
		handleRedHit(self, clientData)
		return true
	elseif action == "redDestruction" then
		handleRedDestruction(self, clientData)
		return false -- doesn't end ability; pure destruction request
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
