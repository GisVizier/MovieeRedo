--[[
	Aki Server Kit
	
	Ability: Kon - Summon devil that rushes to target location and bites
	
	Server responsibilities:
	1. Validate spawn location (range, LOS)
	2. Start cooldown
	3. Broadcast spawn to all clients
	4. Validate hits and apply damage
	
	DEBUG MODE: All logging enabled
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)

--------------------------------------------------------------------------------
-- Debug Logging
--------------------------------------------------------------------------------

local DEBUG = true

local function log(...)
	if DEBUG then
		print("[Aki Server]", ...)
	end
end

local function logTable(label, tbl)
	if not DEBUG then return end
	print("[Aki Server]", label, ":")
	if type(tbl) ~= "table" then
		print("  (not a table):", tbl)
		return
	end
	for k, v in pairs(tbl) do
		if typeof(v) == "Vector3" then
			print(string.format("  %s = Vector3(%.2f, %.2f, %.2f)", tostring(k), v.X, v.Y, v.Z))
		elseif typeof(v) == "CFrame" then
			print(string.format("  %s = CFrame at (%.2f, %.2f, %.2f)", tostring(k), v.Position.X, v.Position.Y, v.Position.Z))
		elseif typeof(v) == "Instance" then
			print(string.format("  %s = %s (%s)", tostring(k), v.Name, v.ClassName))
		else
			print(string.format("  %s = %s", tostring(k), tostring(v)))
		end
	end
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local MAX_RANGE = 150  -- Slightly more than client for validation tolerance
local BITE_DAMAGE = 35
local MAX_HITS_PER_BITE = 5  -- Anti-cheat: max targets per bite

--------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------

local Kit = {}
Kit.__index = Kit

function Kit.new(ctx)
	log("Kit.new() called")
	logTable("Context", {
		player = ctx.player,
		character = ctx.character,
		kitId = ctx.kitId,
	})
	
	local self = setmetatable({}, Kit)
	self._ctx = ctx
	self._pendingSpawn = nil  -- Track pending spawn validation
	return self
end

function Kit:SetCharacter(character)
	log("SetCharacter called:", character and character.Name or "nil")
	self._ctx.character = character
end

function Kit:Destroy()
	log("Destroy called")
	self._pendingSpawn = nil
end

function Kit:OnEquipped()
	log("OnEquipped called for player:", self._ctx.player.Name)
end

function Kit:OnUnequipped()
	log("OnUnequipped called for player:", self._ctx.player.Name)
	self._pendingSpawn = nil
end

--------------------------------------------------------------------------------
-- Validation Helpers
--------------------------------------------------------------------------------

local function validateTargetPosition(player, character, targetPos)
	if not character then
		warn("[Aki Server] Validation failed: No character")
		return false, "NoCharacter"
	end

	-- Use Root (physics body) first, then fallback to HumanoidRootPart/PrimaryPart
	local root = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not root then
		warn("[Aki Server] Validation failed: No root part")
		return false, "NoRootPart"
	end

	-- Check range
	local distance = (targetPos - root.Position).Magnitude
	warn(string.format("[Aki Server] Distance check: %.1f studs (max: %d) using %s", distance, MAX_RANGE, root.Name))
	
	if distance > MAX_RANGE then
		warn("[Aki Server] Validation failed: Out of range")
		return false, "OutOfRange"
	end

	-- TODO: Add line-of-sight check if needed
	
	log("Validation passed")
	return true, nil
end

local function validateHitList(hits)
	if type(hits) ~= "table" then
		log("Validation failed: hits is not a table")
		return false, "InvalidHits"
	end

	if #hits > MAX_HITS_PER_BITE then
		log(string.format("Validation failed: Too many hits (%d > %d)", #hits, MAX_HITS_PER_BITE))
		return false, "TooManyHits"
	end

	log(string.format("Hit list validated: %d hits", #hits))
	return true, nil
end

--------------------------------------------------------------------------------
-- Ability: Kon
--------------------------------------------------------------------------------

function Kit:OnAbility(inputState, clientData)
	warn("========== [Aki Server] OnAbility CALLED ==========")
	warn("[Aki Server] inputState:", tostring(inputState))
	warn("[Aki Server] clientData type:", type(clientData))
	warn("[Aki Server] self._ctx exists:", self._ctx ~= nil)
	warn("[Aki Server] self._ctx.service exists:", self._ctx and self._ctx.service ~= nil)
	warn("[Aki Server] self._ctx.player:", self._ctx and self._ctx.player and self._ctx.player.Name or "nil")
	
	if clientData then
		warn("[Aki Server] clientData.action:", clientData.action or "nil")
		logTable("clientData", clientData)
	else
		warn("[Aki Server] clientData is NIL!")
	end

	if inputState ~= Enum.UserInputState.Begin then
		warn("[Aki Server] Ignoring non-Begin input state")
		return false
	end

	local player = self._ctx.player
	local character = self._ctx.character or player.Character
	local service = self._ctx.service
	
	warn("[Aki Server] service check:", service ~= nil)

	if not character then
		warn("[Aki Server] No character for player:", player.Name)
		return false
	end

	clientData = clientData or {}
	local action = clientData.action

	warn("[Aki Server] Action:", action or "none")

	--------------------------------------------------------------------------------
	-- Action: Request Kon Spawn
	--------------------------------------------------------------------------------
	if action == "requestKonSpawn" then
		warn("[Aki Server] >>> Processing requestKonSpawn <<<")

		local targetPosData = clientData.targetPosition
		if not targetPosData then
			warn("[Aki Server] No target position in request")
			return false
		end

		local targetPos = Vector3.new(
			targetPosData.X or 0,
			targetPosData.Y or 0,
			targetPosData.Z or 0
		)

		warn("[Aki Server] Target position:", targetPos)

		-- Validate target position
		local valid, reason = validateTargetPosition(player, character, targetPos)
		if not valid then
			warn("[Aki Server] Spawn validation failed:", reason)
			-- TODO: Send rejection to client
			return false
		end

		-- Start cooldown
		warn("[Aki Server] About to start cooldown, service:", service ~= nil)
		if service then
			warn("[Aki Server] STARTING COOLDOWN NOW!")
			service:StartCooldown(player)
			warn("[Aki Server] Cooldown started successfully")
		else
			warn("[Aki Server] SERVICE IS NIL - CANNOT START COOLDOWN!")
		end

		-- Store pending spawn for bite validation
		self._pendingSpawn = {
			position = targetPos,
			time = os.clock(),
		}

		log("Spawn validated, pending spawn stored")
		logTable("Pending spawn", self._pendingSpawn)

		-- TODO: Broadcast spawn to all clients via KitService:BroadcastVFX or custom event
		-- For now, client handles this locally

		return false  -- Don't end ability yet, wait for bite
	end

	--------------------------------------------------------------------------------
	-- Action: Kon Bite (damage phase)
	--------------------------------------------------------------------------------
	if action == "konBite" then
		log("Processing konBite")

		local hits = clientData.hits
		local bitePosData = clientData.bitePosition

		if not hits or not bitePosData then
			warn("[Aki Server] Missing hits or bitePosition in konBite")
			return true  -- End ability anyway
		end

		local bitePos = Vector3.new(
			bitePosData.X or 0,
			bitePosData.Y or 0,
			bitePosData.Z or 0
		)

		log("Bite position:", bitePos)
		logTable("Hits received", hits)

		-- Validate hit list
		local valid, reason = validateHitList(hits)
		if not valid then
			warn("[Aki Server] Hit list validation failed:", reason)
			return true
		end

		-- Validate bite position matches pending spawn (with tolerance)
		if self._pendingSpawn then
			local spawnDist = (bitePos - self._pendingSpawn.position).Magnitude
			log(string.format("Bite/spawn position diff: %.1f studs", spawnDist))
			
			if spawnDist > 20 then  -- Tolerance for slight position differences
				warn("[Aki Server] Bite position too far from spawn position")
				-- Don't reject, just log for now
			end
		else
			log("Warning: No pending spawn found for bite validation")
		end

		-- Apply damage to each hit
		log("========== APPLYING DAMAGE ==========")
		
		for i, hitData in ipairs(hits) do
			log(string.format("Processing hit [%d]:", i))
			logTable("  Hit data", hitData)

			local targetPlayer = nil
			local targetCharacter = nil

			if hitData.playerId then
				-- Hit a player
				targetPlayer = Players:GetPlayerByUserId(hitData.playerId)
				if targetPlayer then
					targetCharacter = targetPlayer.Character
					log("  Found player:", targetPlayer.Name)
				else
					log("  Player not found for ID:", hitData.playerId)
				end
			elseif hitData.isDummy and hitData.characterName then
				-- Hit a dummy/NPC - find by name
				-- TODO: Use proper dummy lookup
				log("  Dummy hit:", hitData.characterName, "(damage not implemented for dummies yet)")
			end

			if targetCharacter then
				-- Apply damage via CombatService
				-- TODO: Get CombatService reference and apply damage
				log(string.format("  Would apply %d damage to %s", BITE_DAMAGE, targetCharacter.Name))
				
				-- For now, just damage the humanoid directly as fallback
				local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					log(string.format("  Dealing %d damage to %s (direct humanoid)", BITE_DAMAGE, targetCharacter.Name))
					humanoid:TakeDamage(BITE_DAMAGE)
				end
			end
		end

		log("========== DAMAGE COMPLETE ==========")

		-- Clear pending spawn
		self._pendingSpawn = nil

		-- End ability
		log("Ability complete, returning true")
		return true
	end

	--------------------------------------------------------------------------------
	-- Unknown action or no action
	--------------------------------------------------------------------------------
	log("Unknown or missing action, starting cooldown and ending")
	
	if service then
		service:StartCooldown(player)
	end

	return true
end

--------------------------------------------------------------------------------
-- Ultimate (placeholder)
--------------------------------------------------------------------------------

function Kit:OnUltimate(inputState, clientData)
	log("OnUltimate called")
	log("inputState:", tostring(inputState))
	
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end

	-- TODO: Implement ultimate
	log("Ultimate not implemented yet")
	return true
end

return Kit
