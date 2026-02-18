local WeaponService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

-- Debug logging toggle
local DEBUG_LOGGING = true

local function dbg(...)
	if DEBUG_LOGGING then
		warn("[WeaponService]", ...)
	end
end

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local HitPacketUtils = require(Locations.Shared.Util:WaitForChild("HitPacketUtils"))
local HitValidator = require(script.Parent.Parent.AntiCheat.HitValidator)

-- Projectile system modules
local ProjectileAPI = require(script.Parent.Parent.Combat.ProjectileAPI)
local ProjectilePacketUtils = require(Locations.Shared.Util:WaitForChild("ProjectilePacketUtils"))

local normalizeCharacterModel

-- Traverse up from a hit part to find the character model (has Humanoid)
local function getCharacterFromPart(part)
	if not part then
		return nil
	end

	local current = part.Parent

	-- Handle Root folder (dummies): Dummy/Root/Part
	-- The dummy structure has hitbox parts inside a "Root" BasePart
	if current and current.Name == "Root" and current:IsA("BasePart") then
		current = current.Parent
	end

	-- Search up for a character model (has Humanoid)
	while current and current ~= workspace do
		if current:IsA("Model") then
			-- Use recursive search for nested Humanoids (e.g., dummies with Rig subfolder)
			local humanoid = current:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid then
				return normalizeCharacterModel(current)
			end
		end
		current = current.Parent
	end

	return nil
end

-- Normalize nested/cosmetic rig models to canonical character models.
-- This keeps damage/state writes on the actual gameplay character.
normalizeCharacterModel = function(character)
	if not character or not character:IsA("Model") then
		return character
	end

	-- Dummy structure: DummyModel/Rig -> use DummyModel.
	local parentModel = character.Parent
	if
		character.Name == "Rig"
		and parentModel
		and parentModel:IsA("Model")
		and parentModel:FindFirstChild("Root")
		and parentModel:FindFirstChild("Collider")
	then
		return parentModel
	end

	-- Cosmetic player rig in workspace.Rigs -> resolve back to live player character.
	local parent = character.Parent
	if parent and parent:IsA("Folder") and parent.Name == "Rigs" then
		local ownerUserId = character:GetAttribute("OwnerUserId")
		if type(ownerUserId) == "number" then
			local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
			if ownerPlayer and ownerPlayer.Character then
				return ownerPlayer.Character
			end
		end
	end

	return character
end

function WeaponService:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Initialize HitValidator with network for ping tracking
	HitValidator:Init(net)

	-- Initialize ProjectileAPI with HitDetectionAPI reference
	local HitDetectionAPI = require(script.Parent.Parent.AntiCheat.HitDetectionAPI)
	ProjectileAPI:Init(net, HitDetectionAPI)

	-- Listen for weapon fire events (hitscan)
	net:ConnectServer("WeaponFired", function(player, shotData)
		self:OnWeaponFired(player, shotData)
	end)

	-- Listen for projectile events
	net:ConnectServer("ProjectileSpawned", function(player, data)
		self:OnProjectileSpawned(player, data)
	end)

	net:ConnectServer("ProjectileHit", function(player, data)
		self:OnProjectileHit(player, data)
	end)

	net:ConnectServer("ProjectileHitBatch", function(player, data)
		self:OnProjectileHitBatch(player, data)
	end)
end

--[[
	Fires an event to all players in the same match context as the source player.
	Falls back to FireAllClients if no match context is found.
]]
function WeaponService:_fireMatchScoped(sourcePlayer, eventName, data)
	if not self._net then return end
	
	local matchManager = self._registry:TryGet("MatchManager")
	if matchManager and sourcePlayer then
		local recipients = matchManager:GetPlayersInMatch(sourcePlayer)
		if recipients and #recipients > 0 then
			for _, player in recipients do
				self._net:FireClient(eventName, player, data)
			end
			return
		end
	end
	
	-- Fallback: fire to all clients (lobby/unknown context)
	self._net:FireAllClients(eventName, data)
end

--[[
	Fires an event to all players in the same match context, excluding one player.
]]
function WeaponService:_fireMatchScopedExcept(sourcePlayer, excludePlayer, eventName, data)
	if not self._net then return end
	
	local matchManager = self._registry:TryGet("MatchManager")
	if matchManager and sourcePlayer then
		local recipients = matchManager:GetPlayersInMatch(sourcePlayer)
		if recipients and #recipients > 0 then
			for _, player in recipients do
				if player ~= excludePlayer then
					self._net:FireClient(eventName, player, data)
				end
			end
			return
		end
	end
	
	-- Fallback: fire to all clients except excluded
	self._net:FireAllClientsExcept(excludePlayer, eventName, data)
end

function WeaponService:Start()
	-- No-op for now
end

function WeaponService:OnWeaponFired(player, shotData)
	if not player or not shotData then
		return
	end

	-- Block weapon fire while frozen (loadout / between rounds)
	if player:GetAttribute("MatchFrozen") then
		dbg(player.Name, "blocked: MatchFrozen =", player:GetAttribute("MatchFrozen"))
		return
	end

	-- Parse the hit packet (new buffer format) or use legacy table format
	local hitData
	local weaponId = shotData.weaponId

	if shotData.packet then
		-- New buffer-based packet format
		hitData = HitPacketUtils:ParsePacket(shotData.packet)
		if not hitData then
			dbg(player.Name, "BLOCKED: packet parse failed")
			return
		end
		weaponId = hitData.weaponName
		
		-- DEBUG: Log parsed packet details
		warn(string.format("[WeaponService PACKET] Shooter: %s | targetUserId: %s | hitPlayer resolved: %s | weapon: %s",
			player.Name,
			tostring(hitData.targetUserId),
			hitData.hitPlayer and hitData.hitPlayer.Name or "NIL",
			tostring(weaponId)))
		-- END DEBUG
	else
		-- Legacy table format (backward compatibility)
		hitData = {
			timestamp = shotData.timestamp or workspace:GetServerTimeNow(),
			origin = shotData.origin,
			hitPosition = shotData.hitPosition,
			targetUserId = shotData.hitPlayer and shotData.hitPlayer.UserId or 0,
			hitPlayer = shotData.hitPlayer,
			isHeadshot = shotData.isHeadshot,
			hitPart = shotData.hitPart,
			weaponName = weaponId,
		}
	end

	-- Server-authoritative receive time used by HitValidator rollback.
	hitData.serverReceiveTime = workspace:GetServerTimeNow()

	if not weaponId then
		dbg(player.Name, "BLOCKED: weaponId is nil (weaponName from packet =", hitData and hitData.weaponName, ")")
		return
	end

	-- Validate weapon config exists
	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		dbg(player.Name, "BLOCKED: no weaponConfig for weaponId=", weaponId)
		return
	end

	dbg(player.Name, "fire: weapon=", weaponId, "targetUserId=", hitData.targetUserId,
		"hitPlayer=", hitData.hitPlayer and hitData.hitPlayer.Name or "nil",
		"hitPos=", hitData.hitPosition, "origin=", hitData.origin)

	hitData.adsShot = (weaponId == "DualPistols") and (shotData.adsShot == true) or false

	-- Shotgun pellet handling (server-authoritative)
	if weaponConfig.pelletsPerShot and weaponConfig.pelletsPerShot > 1 and shotData.pelletDirections then
		local valid, reason = self:_validatePellets(shotData, weaponConfig)
		if not valid then
			dbg(player.Name, "BLOCKED: pellet validation failed:", reason)
			return
		end

		-- Use parsed hitData origin if available
		local pelletOrigin = hitData.origin or shotData.origin
		local pelletShotData = {
			origin = pelletOrigin,
			pelletDirections = shotData.pelletDirections,
			weaponId = weaponId,
		}

		local pelletResult = self:_processPellets(player, pelletShotData, weaponConfig)
		if not pelletResult then
			return
		end

		local victimPlayer = pelletResult.hitCharacter and Players:GetPlayerFromCharacter(pelletResult.hitCharacter)
			or nil

		-- Broadcast validated hit to match players for VFX
		self:_fireMatchScoped(player, "HitConfirmed", {
			shooter = player.UserId,
			weaponId = weaponId,
			origin = pelletOrigin,
			hitPosition = pelletResult.hitPosition,
			hitPlayer = victimPlayer and victimPlayer.UserId or nil,
			hitCharacterName = pelletResult.hitCharacter and pelletResult.hitCharacter.Name or nil,
			damage = pelletResult.damageTotal,
			isHeadshot = pelletResult.headshotCount > 0,
		})

		return
	end

	-- Validate the hit with anti-cheat (using new HitValidator)
	local isValid, reason = HitValidator:ValidateHit(player, hitData, weaponConfig)
	if not isValid then
		dbg(player.Name, "BLOCKED by HitValidator:", reason, "| target=", hitData.hitPlayer and hitData.hitPlayer.Name or "nil")
		HitValidator:RecordViolation(player, reason, 1)
		return
	end

	-- Calculate damage
	local damage = self:CalculateDamage(hitData, weaponConfig)
	dbg(player.Name, "HitValidator PASSED | damage=", damage, "| target=", hitData.hitPlayer and hitData.hitPlayer.Name or "nil")

	-- Apply damage if hit a player
	local victimPlayer = hitData.hitPlayer
	local hitCharacter = nil
	local hitCharacterName = nil

	if victimPlayer then
		hitCharacter = victimPlayer.Character
		if not hitCharacter then
			dbg(player.Name, "BLOCKED: victimPlayer", victimPlayer.Name, "has no character")
		elseif not hitCharacter:FindFirstChildWhichIsA("Humanoid", true) then
			dbg(player.Name, "BLOCKED: victimPlayer", victimPlayer.Name, "character has no Humanoid")
		else
			self:ApplyDamageToCharacter(hitCharacter, damage, player, hitData.isHeadshot, weaponId, hitData.origin, hitData.hitPosition)
			hitCharacterName = hitCharacter.Name
		end
	else
		-- No real player hit - do server-side raycast to check for dummy/NPC hits
		-- This handles the case where client detected a hit on a non-player target
		if hitData.origin and hitData.hitPosition then
			local direction = (hitData.hitPosition - hitData.origin)
			local distance = direction.Magnitude

			if distance > 0 and distance <= (weaponConfig.range or 1000) then
				local raycastParams = RaycastParams.new()
				raycastParams.FilterType = Enum.RaycastFilterType.Exclude
				local ignoreList = {}
				if player.Character then
					table.insert(ignoreList, player.Character)
				end
				raycastParams.FilterDescendantsInstances = ignoreList

				-- Raycast to verify hit
				local result = workspace:Raycast(hitData.origin, direction.Unit * (distance + 5), raycastParams)
				if result then
					local character = getCharacterFromPart(result.Instance)
					if character then
						local humanoid = character:FindFirstChildWhichIsA("Humanoid", true)
						if humanoid then
							-- Verify it's not a real player (handled above)
							local isRealPlayer = Players:GetPlayerFromCharacter(character)
							if not isRealPlayer then
								-- It's a dummy/NPC - apply damage
								hitCharacter = character
								hitCharacterName = character.Name
								local isHeadshot = result.Instance.Name == "Head"
									or result.Instance.Name == "CrouchHead"
									or result.Instance.Name == "HitboxHead"
								self:ApplyDamageToCharacter(character, damage, player, isHeadshot, weaponId, hitData.origin, result.Position)
							end
						end
					end
				end
			end
		end
	end

	-- Broadcast validated hit to match players for VFX
	self:_fireMatchScoped(player, "HitConfirmed", {
		shooter = player.UserId,
		weaponId = weaponId,
		origin = hitData.origin,
		hitPosition = hitData.hitPosition,
		hitPlayer = victimPlayer and victimPlayer.UserId or nil,
		hitCharacterName = hitCharacterName,
		damage = damage,
		isHeadshot = hitData.isHeadshot,
	})

end

function WeaponService:_validatePellets(shotData, weaponConfig)
	if type(shotData.pelletDirections) ~= "table" then
		return false, "PelletDirectionsMissing"
	end

	if #shotData.pelletDirections == 0 then
		return false, "NoPellets"
	end

	if #shotData.pelletDirections > weaponConfig.pelletsPerShot then
		return false, "TooManyPellets"
	end

	for _, dir in ipairs(shotData.pelletDirections) do
		if typeof(dir) ~= "Vector3" then
			return false, "PelletDirNotVector"
		end
		if math.abs(dir.Magnitude - 1) > 0.2 then
			return false, "PelletDirNotUnit"
		end
	end

	return true
end

local function applyDistanceFalloff(baseDamage, distance, config)
	local minR = config.minRange
	local maxR = config.maxRange
	if not minR or not maxR or distance <= minR then
		return baseDamage
	end
	local minD = config.minDamage or (baseDamage * 0.3)
	if distance >= maxR then
		return minD
	end
	local t = (distance - minR) / (maxR - minR)
	return baseDamage - (baseDamage - minD) * t
end

function WeaponService:_processPellets(player, shotData, weaponConfig)
	local origin = shotData.origin
	if typeof(origin) ~= "Vector3" then
		return nil
	end

	local range = weaponConfig.range or 50
	local damagePerPellet = weaponConfig.damage or 10
	local headshotMultiplier = weaponConfig.headshotMultiplier or 1.5

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList = {}
	if player.Character then
		table.insert(ignoreList, player.Character)
	end
	raycastParams.FilterDescendantsInstances = ignoreList

	local damageByCharacter = {}
	local headshotByCharacter = {}
	local hitPositionByCharacter = {}
	local firstHitPosition = nil
	local firstHitCharacter = nil

	for i, dir in ipairs(shotData.pelletDirections) do
		local result = workspace:Raycast(origin, dir * range, raycastParams)
		if result then
			if not firstHitPosition then
				firstHitPosition = result.Position
			end

			-- Traverse up to find character (handles nested colliders like Dummy/Root/Head)
			local character = getCharacterFromPart(result.Instance)
			-- Use recursive search for nested Humanoids (e.g., dummies with Rig subfolder)
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid", true)

			if humanoid then
				if not firstHitCharacter then
					firstHitCharacter = character
				end

				local isHeadshot = result.Instance.Name == "Head"
				local distance = (result.Position - origin).Magnitude
				local falloffDamage = applyDistanceFalloff(damagePerPellet, distance, weaponConfig)
				local pelletDamage = isHeadshot and (falloffDamage * headshotMultiplier) or falloffDamage
				damageByCharacter[character] = (damageByCharacter[character] or 0) + pelletDamage
				headshotByCharacter[character] = (headshotByCharacter[character] or 0) + (isHeadshot and 1 or 0)
				hitPositionByCharacter[character] = result.Position
			end
		end
	end

	local totalDamage = 0
	local totalHeadshots = 0
	local damageCount = 0
	for character, damage in pairs(damageByCharacter) do
		damageCount = damageCount + 1
		totalDamage = totalDamage + damage
		totalHeadshots = totalHeadshots + (headshotByCharacter[character] or 0)

		self:ApplyDamageToCharacter(
			character,
			damage,
			player,
			(headshotByCharacter[character] or 0) > 0,
			shotData.weaponId,
			shotData.origin,
			hitPositionByCharacter[character]
		)
	end

	-- If no hits, pick a fallback position for VFX
	if not firstHitPosition then
		local firstDir = shotData.pelletDirections[1]
		firstHitPosition = origin + firstDir * range
	end

	return {
		hitPosition = firstHitPosition,
		hitCharacter = firstHitCharacter,
		damageTotal = math.floor(totalDamage + 0.5),
		headshotCount = totalHeadshots,
	}
end

function WeaponService:CalculateDamage(shotData, weaponConfig)
	local baseDamage = weaponConfig.damage or 10
	local dropoffScale = 1
	if weaponConfig.id == "DualPistols" and shotData.adsShot == true then
		dropoffScale = 0.5
	end

	-- Headshot multiplier
	if shotData.isHeadshot then
		baseDamage = baseDamage * (weaponConfig.headshotMultiplier or 1.5)
	end

	-- Distance falloff
	if weaponConfig.minRange and weaponConfig.maxRange then
		local distance = (shotData.hitPosition - shotData.origin).Magnitude

		if distance > weaponConfig.minRange then
			local falloffRange = weaponConfig.maxRange - weaponConfig.minRange
			local distanceBeyondMin = distance - weaponConfig.minRange
			local falloffPercent = math.clamp(distanceBeyondMin / falloffRange, 0, 1)

			local minDamage = weaponConfig.minDamage or (baseDamage * 0.3)
			baseDamage = baseDamage - ((baseDamage - minDamage) * (falloffPercent * dropoffScale))
		end
	end

	-- Handle shotgun pellets
	if weaponConfig.pelletsPerShot and weaponConfig.pelletsPerShot > 1 then
		-- For simplicity, assume all pellets hit (shotgun spread is client-side)
		-- In production, you'd validate each pellet individually
		baseDamage = baseDamage * weaponConfig.pelletsPerShot
	end

	return math.floor(baseDamage + 0.5) -- Round to nearest integer
end

function WeaponService:ApplyDamageToCharacter(character, damage, shooter, isHeadshot, weaponId, damageSourcePosition, damageHitPosition)
	character = normalizeCharacterModel(character)

	if not character or not character.Parent then
		dbg("ApplyDamage: character nil or no parent")
		return
	end

	-- Use recursive search to find Humanoid (may be nested in Rig subfolder for dummies)
	local humanoid = character:FindFirstChildWhichIsA("Humanoid", true)
	if not humanoid or humanoid.Health <= 0 then
		dbg("ApplyDamage: no humanoid or already dead. char=", character.Name)
		return
	end

	local combatService = self._registry:TryGet("CombatService")

	-- Check if victim is a real player
	local victimPlayer = Players:GetPlayerFromCharacter(character)

	-- If not a real player, check for pseudo-player (dummies)
	if not victimPlayer and combatService then
		victimPlayer = combatService:GetPlayerByCharacter(character)
	end

	dbg("ApplyDamage: char=", character.Name, "victimPlayer=", victimPlayer and victimPlayer.Name or "nil",
		"combatService=", combatService ~= nil, "damage=", damage)

	-- Route through CombatService for players and dummies
	if victimPlayer and combatService then
		local impactDirection = nil
		if typeof(damageSourcePosition) == "Vector3" and typeof(damageHitPosition) == "Vector3" then
			local delta = damageHitPosition - damageSourcePosition
			if delta.Magnitude > 0.001 then
				impactDirection = delta.Unit
			end
		end

		local result = combatService:ApplyDamage(victimPlayer, damage, {
			source = shooter,
			isHeadshot = isHeadshot,
			weaponId = weaponId or self._currentWeaponId,
			sourcePosition = damageSourcePosition,
			hitPosition = damageHitPosition,
			impactDirection = impactDirection,
		})

		return
	end

	-- Fallback for unregistered NPCs - direct humanoid damage
	humanoid:TakeDamage(damage)

	-- Set last damage dealer (useful for kill attribution)
	character:SetAttribute("LastDamageDealer", shooter.UserId)
	character:SetAttribute("WasHeadshot", isHeadshot)

end

-- =============================================================================
-- PROJECTILE SYSTEM HANDLERS
-- =============================================================================

--[[
	Handle projectile spawn event (Client -> Server)
	Validates spawn and replicates to other clients
]]
function WeaponService:OnProjectileSpawned(player, data)
	if not player or not data then
		return
	end

	-- Block projectile spawn while frozen (loadout / between rounds) - same as hitscan
	if player:GetAttribute("MatchFrozen") then
		dbg(player.Name, "ProjectileSpawned BLOCKED: MatchFrozen")
		return
	end

	-- Parse spawn packet
	local spawnData = ProjectilePacketUtils:ParseSpawnPacket(data.packet)
	if not spawnData then
		dbg(player.Name, "ProjectileSpawned BLOCKED: packet parse failed")
		return
	end

	-- Get weapon config
	local weaponId = data.weaponId or spawnData.weaponName
	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		dbg(player.Name, "ProjectileSpawned BLOCKED: no weaponConfig for weaponId=", weaponId)
		return
	end

	-- Validate spawn
	local isValid, reason = ProjectileAPI:ValidateSpawn(player, spawnData, weaponConfig)
	if not isValid then
		dbg(player.Name, "ProjectileSpawned BLOCKED by validation:", reason)
		return
	end

	-- Create replicate packet for other clients
	local replicatePacket = ProjectilePacketUtils:CreateReplicatePacket({
		shooterUserId = player.UserId,
		origin = spawnData.origin,
		direction = spawnData.direction,
		speed = spawnData.speed,
		projectileId = spawnData.projectileId,
		chargePercent = spawnData.chargePercent,
	}, weaponId)

	if replicatePacket then
		-- Broadcast to match players except shooter
		self:_fireMatchScopedExcept(player, player, "ProjectileReplicate", {
			packet = replicatePacket,
		})
	end
end

--[[
	Handle projectile hit event (Client -> Server)
	Validates hit and applies damage
]]
function WeaponService:OnProjectileHit(player, data)
	if not player or not data then
		return
	end

	-- Block projectile hit while frozen (loadout / between rounds) - same as hitscan
	if player:GetAttribute("MatchFrozen") then
		dbg(player.Name, "ProjectileHit BLOCKED: MatchFrozen")
		return
	end

	-- Parse hit packet
	local hitData = ProjectilePacketUtils:ParseHitPacket(data.packet)
	if not hitData then
		dbg(player.Name, "ProjectileHit BLOCKED: packet parse failed")
		return
	end

	-- Get weapon config
	local weaponId = data.weaponId or hitData.weaponName
	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		dbg(player.Name, "ProjectileHit BLOCKED: no weaponConfig for weaponId=", weaponId)
		return
	end

	-- Validate hit (skip validation for rigs - they don't have position history)
	local victimPlayer = hitData.hitPlayer
	local isRig = data.rigName and not victimPlayer

	if not isRig then
		local isValid, reason = ProjectileAPI:ValidateHit(player, hitData, weaponConfig)
		if not isValid then
			dbg(player.Name, "ProjectileHit BLOCKED by validation:", reason, "| weapon=", weaponId, "target=", victimPlayer and victimPlayer.Name or "nil")
			return
		end
	end

	-- Calculate damage
	local damage = self:CalculateProjectileDamage(hitData, weaponConfig, data)

	-- Apply damage
	local hitCharacter = nil
	local hitCharacterName = nil

	if victimPlayer then
		-- Hit a player
		hitCharacter = victimPlayer.Character
		-- Use recursive search for nested Humanoids (e.g., dummies with Rig subfolder)
		if hitCharacter and hitCharacter:FindFirstChildWhichIsA("Humanoid", true) then
			self:ApplyDamageToCharacter(hitCharacter, damage, player, hitData.isHeadshot, weaponId, hitData.origin, hitData.hitPosition)
			hitCharacterName = hitCharacter.Name
		end
	elseif isRig then
		-- Hit a rig/dummy - find it in workspace
		hitCharacter = self:_findRigByName(data.rigName, hitData.hitPosition)
		if hitCharacter then
			hitCharacter = normalizeCharacterModel(hitCharacter)
			self:ApplyDamageToCharacter(hitCharacter, damage, player, hitData.isHeadshot, weaponId, hitData.origin, hitData.hitPosition)
			hitCharacterName = hitCharacter.Name
		end
	end

	-- Remove projectile from tracking
	ProjectileAPI:RemoveProjectile(player, hitData.projectileId)

	-- Broadcast validated hit to match players for VFX
	self:_fireMatchScoped(player, "ProjectileHitConfirmed", {
		shooter = player.UserId,
		weaponId = weaponId,
		projectileId = hitData.projectileId,
		origin = hitData.origin,
		hitPosition = hitData.hitPosition,
		hitPlayer = victimPlayer and victimPlayer.UserId or nil,
		hitCharacterName = hitCharacterName,
		damage = damage,
		isHeadshot = hitData.isHeadshot,
		pierceCount = hitData.pierceCount,
		bounceCount = hitData.bounceCount,
	})

end

function WeaponService:OnProjectileHitBatch(player, data)
	if not player or type(data) ~= "table" then
		return
	end

	local hits = data.hits
	if type(hits) ~= "table" then
		return
	end

	for _, hitData in ipairs(hits) do
		self:OnProjectileHit(player, hitData)
	end
end

--[[
	Find a rig/dummy in workspace by name and proximity to hit position
]]
function WeaponService:_findRigByName(rigName, hitPosition)
	-- First, try to find by proximity to hit position (most reliable)
	if hitPosition then
		local closest = nil
		local closestDist = 15 -- Max distance to consider (studs)
		local closestMap = {}

		-- Search all descendants with humanoids (use recursive search for nested Humanoids)
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("Model") and descendant:FindFirstChildWhichIsA("Humanoid", true) then
				local candidate = normalizeCharacterModel(descendant)
				if candidate then
					-- Skip player characters/cosmetic rigs owned by players
					local isPlayerChar = false
					for _, player in ipairs(Players:GetPlayers()) do
						if player.Character == candidate then
							isPlayerChar = true
							break
						end
					end

					if not isPlayerChar and not closestMap[candidate] then
						closestMap[candidate] = true
						local hrp = candidate:FindFirstChild("HumanoidRootPart")
							or candidate:FindFirstChild("Torso")
							or candidate.PrimaryPart

						if hrp then
							local dist = (hrp.Position - hitPosition).Magnitude
							if dist < closestDist then
								closest = candidate
								closestDist = dist
							end
						end
					end
				end
			end
		end

		if closest then
			return closest
		end
	end

	-- Fallback: search by name
	local candidates = {}
	local candidateMap = {}

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant.Name == rigName then
			-- Use recursive search for nested Humanoids (e.g., inside Rig subfolder)
			local humanoid = descendant:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid then
				local candidate = normalizeCharacterModel(descendant)
				if candidate then
					-- Skip player characters
					local isPlayerChar = false
					for _, player in ipairs(Players:GetPlayers()) do
						if player.Character == candidate then
							isPlayerChar = true
							break
						end
					end

					if not isPlayerChar and not candidateMap[candidate] then
						candidateMap[candidate] = true
						table.insert(candidates, candidate)
					end
				end
			end
		end
	end

	-- If only one candidate, return it
	if #candidates == 1 then
		return candidates[1]
	end

	-- If multiple, return first (or could do proximity again)
	if #candidates > 0 then
		return candidates[1]
	end

	return nil
end

--[[
	Calculate damage for projectile hits
	Handles pierce damage reduction, bounce damage reduction, AoE falloff, and charge scaling
]]
function WeaponService:CalculateProjectileDamage(hitData, weaponConfig, extraData)
	local baseDamage = weaponConfig.damage or 10
	local projectileConfig = weaponConfig.projectile or {}
	local isRocketSpecial = extraData and extraData.isRocketSpecial == true

	-- Headshot multiplier
	if hitData.isHeadshot then
		baseDamage = baseDamage * (weaponConfig.headshotMultiplier or 1.5)
	end

	-- Pierce damage reduction
	local pierceCount = hitData.pierceCount or 0
	if pierceCount > 0 then
		local pierceDamageMult = projectileConfig.pierceDamageMult or 0.8
		baseDamage = baseDamage * math.pow(pierceDamageMult, pierceCount)
	end

	-- Bounce damage reduction
	local bounceCount = hitData.bounceCount or 0
	if bounceCount > 0 then
		local bounceDamageMult = projectileConfig.ricochetDamageMult or 0.7
		baseDamage = baseDamage * math.pow(bounceDamageMult, bounceCount)
	end

	-- AoE falloff (if applicable)
	if extraData and extraData.isAoE and projectileConfig.aoe then
		local aoeConfig = projectileConfig.aoe
		local distance = extraData.aoeDistance or 0
		local radius = extraData.aoeRadius or aoeConfig.radius or 15

		if aoeConfig.falloff then
			local falloffMin = aoeConfig.falloffMin or 0.25
			local falloffFactor = 1 - (distance / radius) * (1 - falloffMin)
			baseDamage = baseDamage * math.max(falloffFactor, falloffMin)
		end
	end

	if (not isRocketSpecial) and hitData.origin and hitData.hitPosition then
		local distance = (hitData.hitPosition - hitData.origin).Magnitude
		local falloffConfig = projectileConfig.minRange and projectileConfig or weaponConfig
		baseDamage = applyDistanceFalloff(baseDamage, distance, falloffConfig)
	end

	-- Charge scaling (based on chargePercent stored in projectile tracking)
	-- Note: This would need to be passed from client or stored during spawn
	-- For now, we trust the damage is already scaled client-side

	return math.floor(baseDamage + 0.5) -- Round to nearest integer
end

return WeaponService
