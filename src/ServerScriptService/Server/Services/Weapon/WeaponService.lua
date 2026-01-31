local WeaponService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

-- Debug logging toggle
local DEBUG_LOGGING = true

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local HitPacketUtils = require(Locations.Shared.Util:WaitForChild("HitPacketUtils"))
local HitValidator = require(script.Parent.Parent.AntiCheat.HitValidator)

-- Projectile system modules
local ProjectileAPI = require(script.Parent.Parent.Combat.ProjectileAPI)
local ProjectilePacketUtils = require(Locations.Shared.Util:WaitForChild("ProjectilePacketUtils"))

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
				if DEBUG_LOGGING then
					print(
						string.format(
							"[WeaponService] getCharacterFromPart: Found character '%s' from part '%s'",
							current.Name,
							part.Name
						)
					)
				end
				return current
			end
		end
		current = current.Parent
	end

	if DEBUG_LOGGING then
		print(
			string.format(
				"[WeaponService] getCharacterFromPart: No character found from part '%s' (parent: %s)",
				part.Name,
				part.Parent and part.Parent.Name or "nil"
			)
		)
	end
	return nil
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
end

function WeaponService:Start()
	-- No-op for now
end

function WeaponService:OnWeaponFired(player, shotData)
	if not player or not shotData then
		warn("[WeaponService] Invalid shot data from", player and player.Name or "unknown")
		return
	end

	-- Parse the hit packet (new buffer format) or use legacy table format
	local hitData
	local weaponId = shotData.weaponId

	if shotData.packet then
		-- New buffer-based packet format
		hitData = HitPacketUtils:ParsePacket(shotData.packet)
		if not hitData then
			warn("[WeaponService] Failed to parse hit packet from", player.Name)
			return
		end
		weaponId = hitData.weaponName
	else
		-- Legacy table format (backward compatibility)
		hitData = {
			timestamp = shotData.timestamp or os.clock(),
			origin = shotData.origin,
			hitPosition = shotData.hitPosition,
			targetUserId = shotData.hitPlayer and shotData.hitPlayer.UserId or 0,
			hitPlayer = shotData.hitPlayer,
			isHeadshot = shotData.isHeadshot,
			hitPart = shotData.hitPart,
			weaponName = weaponId,
		}
	end

	if not weaponId then
		warn("[WeaponService] No weapon ID from", player.Name)
		return
	end

	-- Validate weapon config exists
	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		warn("[WeaponService] Invalid weapon:", weaponId, "from", player.Name)
		return
	end

	-- Shotgun pellet handling (server-authoritative)
	if weaponConfig.pelletsPerShot and weaponConfig.pelletsPerShot > 1 and shotData.pelletDirections then
		local valid, reason = self:_validatePellets(shotData, weaponConfig)
		if not valid then
			warn("[WeaponService] Invalid pellet data from", player.Name, "Reason:", reason)
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
			warn("[WeaponService] Pellet processing failed for", player.Name)
			return
		end

		local victimPlayer = pelletResult.hitCharacter and Players:GetPlayerFromCharacter(pelletResult.hitCharacter)
			or nil

		-- Broadcast validated hit to all clients for VFX
		self._net:FireAllClients("HitConfirmed", {
			shooter = player.UserId,
			weaponId = weaponId,
			origin = pelletOrigin,
			hitPosition = pelletResult.hitPosition,
			hitPlayer = victimPlayer and victimPlayer.UserId or nil,
			hitCharacterName = pelletResult.hitCharacter and pelletResult.hitCharacter.Name or nil,
			damage = pelletResult.damageTotal,
			isHeadshot = pelletResult.headshotCount > 0,
		})

		if DEBUG_LOGGING then
			if victimPlayer then
				print(
					string.format(
						"[WeaponService] %s hit player %s with pellets for %d damage (headshots: %d)",
						player.Name,
						victimPlayer.Name,
						pelletResult.damageTotal,
						pelletResult.headshotCount
					)
				)
			elseif pelletResult.hitCharacter then
				print(
					string.format(
						"[WeaponService] %s hit dummy/rig '%s' with pellets for %d damage (headshots: %d)",
						player.Name,
						pelletResult.hitCharacter.Name,
						pelletResult.damageTotal,
						pelletResult.headshotCount
					)
				)
			else
				print(string.format("[WeaponService] %s fired pellets (no target hit)", player.Name))
			end
		end

		return
	end

	-- Validate the hit with anti-cheat (using new HitValidator)
	local isValid, reason = HitValidator:ValidateHit(player, hitData, weaponConfig)
	if not isValid then
		warn("[WeaponService] Invalid shot from", player.Name, "Reason:", reason)
		HitValidator:RecordViolation(player, reason, 1)
		return
	end

	-- Calculate damage
	local damage = self:CalculateDamage(hitData, weaponConfig)

	-- Apply damage if hit a player
	local victimPlayer = hitData.hitPlayer
	local hitCharacter = nil
	local hitCharacterName = nil

	if victimPlayer then
		hitCharacter = victimPlayer.Character
		-- Use recursive search for nested Humanoids (e.g., dummies with Rig subfolder)
		if hitCharacter and hitCharacter:FindFirstChildWhichIsA("Humanoid", true) then
			self:ApplyDamageToCharacter(hitCharacter, damage, player, hitData.isHeadshot, weaponId)
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
								self:ApplyDamageToCharacter(character, damage, player, isHeadshot, weaponId)

								if DEBUG_LOGGING then
									print(
										string.format(
											"[WeaponService] Server-verified dummy hit: %s on %s (part: %s, damage: %d)",
											player.Name,
											character.Name,
											result.Instance.Name,
											damage
										)
									)
								end
							end
						end
					end
				elseif DEBUG_LOGGING then
					print(string.format("[WeaponService] Server raycast found no target at client hit position"))
				end
			end
		end
	end

	-- Broadcast validated hit to all clients for VFX
	self._net:FireAllClients("HitConfirmed", {
		shooter = player.UserId,
		weaponId = weaponId,
		origin = hitData.origin,
		hitPosition = hitData.hitPosition,
		hitPlayer = victimPlayer and victimPlayer.UserId or nil,
		hitCharacterName = hitCharacterName,
		damage = damage,
		isHeadshot = hitData.isHeadshot,
	})

	-- Log successful hit
	if DEBUG_LOGGING then
		if victimPlayer then
			print(
				string.format(
					"[WeaponService] %s hit player %s for %d damage (headshot: %s)",
					player.Name,
					victimPlayer.Name,
					damage,
					tostring(hitData.isHeadshot)
				)
			)
		elseif hitCharacterName then
			print(
				string.format(
					"[WeaponService] %s hit dummy/rig '%s' for %d damage (headshot: %s)",
					player.Name,
					hitCharacterName,
					damage,
					tostring(hitData.isHeadshot)
				)
			)
		else
			print(
				string.format(
					"[WeaponService] %s shot at position %s (no target hit)",
					player.Name,
					tostring(hitData.hitPosition)
				)
			)
		end
	end
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
	local firstHitPosition = nil
	local firstHitCharacter = nil

	if DEBUG_LOGGING then
		print(
			string.format(
				"[WeaponService] _processPellets: %s firing %d pellets from %s",
				player.Name,
				#shotData.pelletDirections,
				tostring(origin)
			)
		)
	end

	for i, dir in ipairs(shotData.pelletDirections) do
		local result = workspace:Raycast(origin, dir * range, raycastParams)
		if result then
			if not firstHitPosition then
				firstHitPosition = result.Position
			end

			if DEBUG_LOGGING then
				print(
					string.format(
						"[WeaponService] Pellet %d hit: %s (parent: %s, fullname: %s)",
						i,
						result.Instance.Name,
						result.Instance.Parent and result.Instance.Parent.Name or "nil",
						result.Instance:GetFullName()
					)
				)
			end

			-- Traverse up to find character (handles nested colliders like Dummy/Root/Head)
			local character = getCharacterFromPart(result.Instance)
			-- Use recursive search for nested Humanoids (e.g., dummies with Rig subfolder)
			local humanoid = character and character:FindFirstChildWhichIsA("Humanoid", true)

			if DEBUG_LOGGING then
				print(
					string.format(
						"[WeaponService] Pellet %d: character=%s, humanoid=%s",
						i,
						character and character.Name or "nil",
						humanoid and "found" or "nil"
					)
				)
			end

			if humanoid then
				if not firstHitCharacter then
					firstHitCharacter = character
				end

				local isHeadshot = result.Instance.Name == "Head"
				local pelletDamage = isHeadshot and (damagePerPellet * headshotMultiplier) or damagePerPellet
				damageByCharacter[character] = (damageByCharacter[character] or 0) + pelletDamage
				headshotByCharacter[character] = (headshotByCharacter[character] or 0) + (isHeadshot and 1 or 0)
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

		if DEBUG_LOGGING then
			print(
				string.format(
					"[WeaponService] _processPellets: Applying %d damage to '%s' (headshots: %d)",
					damage,
					character.Name,
					headshotByCharacter[character] or 0
				)
			)
		end

		self:ApplyDamageToCharacter(
			character,
			damage,
			player,
			(headshotByCharacter[character] or 0) > 0,
			shotData.weaponId
		)
	end

	if DEBUG_LOGGING then
		print(
			string.format(
				"[WeaponService] _processPellets: Total %d characters damaged, %d total damage",
				damageCount,
				totalDamage
			)
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
			baseDamage = baseDamage - ((baseDamage - minDamage) * falloffPercent)
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

function WeaponService:ApplyDamageToCharacter(character, damage, shooter, isHeadshot, weaponId)
	if not character or not character.Parent then
		if DEBUG_LOGGING then
			print("[WeaponService] ApplyDamageToCharacter: character is nil or has no parent")
		end
		return
	end

	-- Use recursive search to find Humanoid (may be nested in Rig subfolder for dummies)
	local humanoid = character:FindFirstChildWhichIsA("Humanoid", true)
	if not humanoid or humanoid.Health <= 0 then
		if DEBUG_LOGGING then
			print(
				string.format(
					"[WeaponService] ApplyDamageToCharacter: %s - humanoid=%s, health=%s",
					character.Name,
					humanoid and "found" or "nil",
					humanoid and tostring(humanoid.Health) or "N/A"
				)
			)
		end
		return
	end

	local combatService = self._registry:TryGet("CombatService")

	-- Check if victim is a real player
	local victimPlayer = Players:GetPlayerFromCharacter(character)

	-- If not a real player, check for pseudo-player (dummies)
	if not victimPlayer and combatService then
		victimPlayer = combatService:GetPlayerByCharacter(character)
		if DEBUG_LOGGING then
			print(
				string.format(
					"[WeaponService] ApplyDamageToCharacter: %s - checked CombatService, victimPlayer=%s",
					character.Name,
					victimPlayer and victimPlayer.Name or "nil"
				)
			)
		end
	end

	if DEBUG_LOGGING then
		print(
			string.format(
				"[WeaponService] ApplyDamageToCharacter: %s - damage=%d, victimPlayer=%s, combatService=%s",
				character.Name,
				damage,
				victimPlayer and victimPlayer.Name or "nil",
				combatService and "found" or "nil"
			)
		)
	end

	-- Route through CombatService for players and dummies
	if victimPlayer and combatService then
		local result = combatService:ApplyDamage(victimPlayer, damage, {
			source = shooter,
			isHeadshot = isHeadshot,
			weaponId = weaponId or self._currentWeaponId,
		})

		if DEBUG_LOGGING then
			print(
				string.format(
					"[WeaponService] CombatService:ApplyDamage result for %s: %s",
					character.Name,
					result and "success" or "nil"
				)
			)
			if result then
				print(
					string.format(
						"  - blocked=%s, healthDamage=%s, killed=%s",
						tostring(result.blocked),
						tostring(result.healthDamage),
						tostring(result.killed)
					)
				)
			end
		end

		if result and result.killed and DEBUG_LOGGING then
			print(
				string.format(
					"[WeaponService] %s killed %s (headshot: %s)",
					shooter.Name,
					character.Name,
					tostring(isHeadshot)
				)
			)
		end
		return
	end

	-- Fallback for unregistered NPCs - direct humanoid damage
	if DEBUG_LOGGING then
		print(string.format("[WeaponService] Fallback: humanoid:TakeDamage(%d) for %s", damage, character.Name))
	end
	humanoid:TakeDamage(damage)

	-- Set last damage dealer (useful for kill attribution)
	character:SetAttribute("LastDamageDealer", shooter.UserId)
	character:SetAttribute("WasHeadshot", isHeadshot)

	-- Check if killed
	if humanoid.Health <= 0 and DEBUG_LOGGING then
		print(
			string.format(
				"[WeaponService] %s killed %s (headshot: %s)",
				shooter.Name,
				character.Name,
				tostring(isHeadshot)
			)
		)
	end
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
		warn("[WeaponService] Invalid projectile spawn data from", player and player.Name or "unknown")
		return
	end

	-- Parse spawn packet
	local spawnData = ProjectilePacketUtils:ParseSpawnPacket(data.packet)
	if not spawnData then
		warn("[WeaponService] Failed to parse projectile spawn packet from", player.Name)
		return
	end

	-- Get weapon config
	local weaponId = data.weaponId or spawnData.weaponName
	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		warn("[WeaponService] Invalid weapon for projectile:", weaponId, "from", player.Name)
		return
	end

	-- Validate spawn
	local isValid, reason = ProjectileAPI:ValidateSpawn(player, spawnData, weaponConfig)
	if not isValid then
		warn("[WeaponService] Invalid projectile spawn from", player.Name, "Reason:", reason)
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
		-- Broadcast to all clients except shooter
		self._net:FireAllClientsExcept(player, "ProjectileReplicate", {
			packet = replicatePacket,
		})
	end

	if DEBUG_LOGGING then
		print(
			string.format(
				"[WeaponService] %s spawned projectile %d (%s) at %.0f studs/sec",
				player.Name,
				spawnData.projectileId,
				weaponId,
				spawnData.speed
			)
		)
	end
end

--[[
	Handle projectile hit event (Client -> Server)
	Validates hit and applies damage
]]
function WeaponService:OnProjectileHit(player, data)
	if not player or not data then
		warn("[WeaponService] Invalid projectile hit data from", player and player.Name or "unknown")
		return
	end

	-- Parse hit packet
	local hitData = ProjectilePacketUtils:ParseHitPacket(data.packet)
	if not hitData then
		warn("[WeaponService] Failed to parse projectile hit packet from", player.Name)
		return
	end

	-- Get weapon config
	local weaponId = data.weaponId or hitData.weaponName
	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if not weaponConfig then
		warn("[WeaponService] Invalid weapon for projectile hit:", weaponId, "from", player.Name)
		return
	end

	-- Validate hit (skip validation for rigs - they don't have position history)
	local victimPlayer = hitData.hitPlayer
	local isRig = data.rigName and not victimPlayer

	if DEBUG_LOGGING then
		print(
			string.format(
				"[WeaponService] OnProjectileHit: rigName=%s, victimPlayer=%s, isRig=%s",
				tostring(data.rigName),
				victimPlayer and victimPlayer.Name or "nil",
				tostring(isRig)
			)
		)
	end

	if not isRig then
		local isValid, reason = ProjectileAPI:ValidateHit(player, hitData, weaponConfig)
		if not isValid then
			warn("[WeaponService] Invalid projectile hit from", player.Name, "Reason:", reason)
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
			self:ApplyDamageToCharacter(hitCharacter, damage, player, hitData.isHeadshot, weaponId)
			hitCharacterName = hitCharacter.Name
		end
	elseif isRig then
		-- Hit a rig/dummy - find it in workspace
		if DEBUG_LOGGING then
			print(
				string.format(
					"[WeaponService] OnProjectileHit: Looking for rig '%s' near position %s",
					data.rigName,
					tostring(hitData.hitPosition)
				)
			)
		end
		hitCharacter = self:_findRigByName(data.rigName, hitData.hitPosition)
		if hitCharacter then
			if DEBUG_LOGGING then
				print(
					string.format(
						"[WeaponService] OnProjectileHit: Found rig '%s', applying %d damage",
						hitCharacter.Name,
						damage
					)
				)
			end
			self:ApplyDamageToCharacter(hitCharacter, damage, player, hitData.isHeadshot, weaponId)
			hitCharacterName = hitCharacter.Name
		else
			warn("[WeaponService] Could not find rig:", data.rigName)
		end
	else
		if DEBUG_LOGGING then
			print("[WeaponService] OnProjectileHit: No target (neither player nor rig)")
		end
	end

	-- Remove projectile from tracking
	ProjectileAPI:RemoveProjectile(player, hitData.projectileId)

	-- Broadcast validated hit to all clients for VFX
	self._net:FireAllClients("ProjectileHitConfirmed", {
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

	-- Log successful hit
	if DEBUG_LOGGING then
		if victimPlayer then
			print(
				string.format(
					"[WeaponService] %s projectile hit player %s for %d damage (headshot: %s, pierce: %d, bounce: %d)",
					player.Name,
					victimPlayer.Name,
					damage,
					tostring(hitData.isHeadshot),
					hitData.pierceCount or 0,
					hitData.bounceCount or 0
				)
			)
		elseif hitCharacterName then
			print(
				string.format(
					"[WeaponService] %s projectile hit rig '%s' for %d damage (headshot: %s)",
					player.Name,
					hitCharacterName,
					damage,
					tostring(hitData.isHeadshot)
				)
			)
		else
			print(
				string.format(
					"[WeaponService] %s projectile hit environment at %s",
					player.Name,
					tostring(hitData.hitPosition)
				)
			)
		end
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

		-- Search all descendants with humanoids (use recursive search for nested Humanoids)
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("Model") and descendant:FindFirstChildWhichIsA("Humanoid", true) then
				-- Skip player characters
				local isPlayerChar = false
				for _, player in ipairs(Players:GetPlayers()) do
					if player.Character == descendant then
						isPlayerChar = true
						break
					end
				end

				if not isPlayerChar then
					local hrp = descendant:FindFirstChild("HumanoidRootPart")
						or descendant:FindFirstChild("Torso")
						or descendant.PrimaryPart

					if hrp then
						local dist = (hrp.Position - hitPosition).Magnitude
						if dist < closestDist then
							closest = descendant
							closestDist = dist
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

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant.Name == rigName then
			-- Use recursive search for nested Humanoids (e.g., inside Rig subfolder)
			local humanoid = descendant:FindFirstChildWhichIsA("Humanoid", true)
			if humanoid then
				-- Skip player characters
				local isPlayerChar = false
				for _, player in ipairs(Players:GetPlayers()) do
					if player.Character == descendant then
						isPlayerChar = true
						break
					end
				end

				if not isPlayerChar then
					table.insert(candidates, descendant)
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

	-- Charge scaling (based on chargePercent stored in projectile tracking)
	-- Note: This would need to be passed from client or stored during spawn
	-- For now, we trust the damage is already scaled client-side

	return math.floor(baseDamage + 0.5) -- Round to nearest integer
end

return WeaponService
