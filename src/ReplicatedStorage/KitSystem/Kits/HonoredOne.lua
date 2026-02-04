--[[
	HonoredOne Server Kit (Gojo)
	
	Handles server-side validation and damage for HonoredOne's abilities.
	
	Blue (Pull): No damage, just knockback/CC
	Red (Push): Piercing projectile with body/headshot damage + explosion
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))

local HonoredOne = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

-- Blue does NO damage (just knockback)
local BLUE_DAMAGE = 0

-- Red damage values (validated against client)
local RED_BODY_DAMAGE = 35
local RED_HEADSHOT_DAMAGE = 90
local RED_EXPLOSION_DAMAGE = 10

local MAX_RANGE = 350            -- Max distance from player for validation (Red has long range)
local MAX_TARGETS = 15           -- Max targets to accept per ability use

--------------------------------------------------------------------------------
-- Debug Helpers
--------------------------------------------------------------------------------

local function log(...)
	print("[HonoredOne Server]", ...)
end

--------------------------------------------------------------------------------
-- Validation Helpers
--------------------------------------------------------------------------------

local function validateHitList(player, hits, maxRange)
	if not hits or type(hits) ~= "table" then
		log("Invalid hit list: not a table")
		return {}
	end
	
	if #hits > MAX_TARGETS then
		log("Hit list too large:", #hits, "- truncating to", MAX_TARGETS)
		local truncated = {}
		for i = 1, MAX_TARGETS do
			truncated[i] = hits[i]
		end
		hits = truncated
	end
	
	local validHits = {}
	local playerPosition = nil
	
	-- Get player position for range check
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
		if root then
			playerPosition = root.Position
		end
	end
	
	for i, hit in ipairs(hits) do
		if type(hit) ~= "table" then
			log("Invalid hit entry at index", i)
			continue
		end
		
		local targetChar = nil
		
		-- Try to find target by player ID
		if hit.playerId then
			local targetPlayer = Players:GetPlayerByUserId(hit.playerId)
			if targetPlayer and targetPlayer.Character then
				targetChar = targetPlayer.Character
			end
		end
		
		-- Try to find target by name (for dummies)
		if not targetChar and hit.characterName then
			-- Check in World/DummySpawns
			local world = workspace:FindFirstChild("World")
			if world then
				local dummySpawns = world:FindFirstChild("DummySpawns")
				if dummySpawns then
					targetChar = dummySpawns:FindFirstChild(hit.characterName)
				end
			end
			
			-- Fallback to workspace
			if not targetChar then
				targetChar = workspace:FindFirstChild(hit.characterName)
			end
		end
		
		if not targetChar then
			log("Could not find target:", hit.characterName or "unknown")
			continue
		end
		
		-- Range check
		if playerPosition then
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Root") or targetChar.PrimaryPart
			if targetRoot then
				local distance = (targetRoot.Position - playerPosition).Magnitude
				if distance > maxRange then
					log("Target out of range:", hit.characterName, "- distance:", distance)
					continue
				end
			end
		end
		
		table.insert(validHits, {
			character = targetChar,
			playerId = hit.playerId,
			isDummy = hit.isDummy,
		})
		log("Validated hit:", targetChar.Name)
	end
	
	return validHits
end

--------------------------------------------------------------------------------
-- Action Handlers
--------------------------------------------------------------------------------

local function handleBlueHit(player, data, context)
	log("=== BLUE HIT RECEIVED ===")
	log("Player:", player.Name)
	-- Blue does NO damage, just knockback (handled client-side)
	log("Blue ability does no damage - knockback only")
	log("=== BLUE HIT COMPLETE ===")
end

local function handleRedHit(player, data, context)
	log("=== RED HIT RECEIVED ===")
	log("Player:", player.Name)
	log("Hits:", data.hits and #data.hits or 0)
	
	-- Validate hits
	local validHits = {}
	local playerPosition = nil
	
	-- Get player position for range check
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
		if root then
			playerPosition = root.Position
		end
	end
	
	if not data.hits or type(data.hits) ~= "table" then
		log("Invalid hit list")
		return
	end
	
	-- Validate each hit
	for i, hit in ipairs(data.hits) do
		if i > MAX_TARGETS then break end
		if type(hit) ~= "table" then continue end
		
		local targetChar = nil
		
		-- Find target
		if hit.playerId then
			local targetPlayer = Players:GetPlayerByUserId(hit.playerId)
			if targetPlayer and targetPlayer.Character then
				targetChar = targetPlayer.Character
			end
		elseif hit.characterName then
			-- Check dummies
			local world = workspace:FindFirstChild("World")
			if world then
				local dummySpawns = world:FindFirstChild("DummySpawns")
				if dummySpawns then
					targetChar = dummySpawns:FindFirstChild(hit.characterName)
				end
			end
			if not targetChar then
				targetChar = workspace:FindFirstChild(hit.characterName)
			end
		end
		
		if not targetChar then continue end
		
		-- Range check
		if playerPosition then
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart") or targetChar:FindFirstChild("Root") or targetChar.PrimaryPart
			if targetRoot and (targetRoot.Position - playerPosition).Magnitude > MAX_RANGE then
				log("Target out of range:", hit.characterName)
				continue
			end
		end
		
		-- Validate damage amount (server authoritative)
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
			playerId = hit.playerId,
			isHeadshot = hit.isHeadshot,
			isExplosion = hit.isExplosion,
			damage = damage,
		})
		
		log("Validated:", targetChar.Name, hit.isHeadshot and "(HEADSHOT)" or (hit.isExplosion and "(explosion)" or "(body)"))
	end
	
	log("Valid hits:", #validHits)
	
	if #validHits == 0 then
		log("No valid hits to process")
		return
	end
	
	-- Get CombatService for damage
	local registry = context.registry
	local combatService = registry and registry:TryGet("CombatService")
	
	if not combatService then
		log("WARNING: CombatService not found, cannot apply damage")
		return
	end
	
	-- Apply damage to each valid target
	for _, hit in ipairs(validHits) do
		local targetPlayer = hit.playerId and Players:GetPlayerByUserId(hit.playerId)
		
		if targetPlayer then
			-- Player target
			local result = combatService:TakeDamage(targetPlayer, hit.damage, {
				source = player,
				damageType = "ability",
				weaponId = "HonoredOne_Red",
				isHeadshot = hit.isHeadshot,
			})
			log("Dealt", hit.damage, "to player:", targetPlayer.Name)
		else
			-- Dummy target
			local humanoid = hit.character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:TakeDamage(hit.damage)
				log("Dealt", hit.damage, "to dummy:", hit.character.Name)
			end
		end
	end
	
	log("=== RED HIT COMPLETE ===")
end

--------------------------------------------------------------------------------
-- Kit Interface
--------------------------------------------------------------------------------

function HonoredOne.OnAbilityRequest(player, data, context)
	local action = data.action
	
	log("Ability request:", action, "from", player.Name)
	
	if action == "blueHit" then
		handleBlueHit(player, data, context)
	elseif action == "redHit" then
		handleRedHit(player, data, context)
	else
		log("Unknown action:", action)
	end
end

function HonoredOne.OnUltimateRequest(player, data, context)
	log("Ultimate request from", player.Name, "- not implemented")
end

return HonoredOne
