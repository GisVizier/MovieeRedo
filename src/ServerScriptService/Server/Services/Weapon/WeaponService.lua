local WeaponService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local HitPacketUtils = require(Locations.Shared.Util:WaitForChild("HitPacketUtils"))
local HitValidator = require(script.Parent.Parent.AntiCheat.HitValidator)

-- Traverse up from a hit part to find the character model (has Humanoid)
local function getCharacterFromPart(part)
	local current = part
	while current and current ~= workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

function WeaponService:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Initialize HitValidator with network for ping tracking
	HitValidator:Init(net)

	-- Listen for weapon fire events
	net:ConnectServer("WeaponFired", function(player, shotData)
		self:OnWeaponFired(player, shotData)
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

		local victimPlayer = pelletResult.hitCharacter and Players:GetPlayerFromCharacter(pelletResult.hitCharacter) or nil

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

		if victimPlayer then
			print(string.format(
				"[WeaponService] %s hit player %s with pellets for %d damage (headshots: %d)",
				player.Name,
				victimPlayer.Name,
				pelletResult.damageTotal,
				pelletResult.headshotCount
			))
		elseif pelletResult.hitCharacter then
			print(string.format(
				"[WeaponService] %s hit dummy/rig '%s' with pellets for %d damage (headshots: %d)",
				player.Name,
				pelletResult.hitCharacter.Name,
				pelletResult.damageTotal,
				pelletResult.headshotCount
			))
		else
			print(string.format(
				"[WeaponService] %s fired pellets (no target hit)",
				player.Name
			))
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
		if hitCharacter and hitCharacter:FindFirstChildOfClass("Humanoid") then
			self:ApplyDamageToCharacter(hitCharacter, damage, player, hitData.isHeadshot, weaponId)
			hitCharacterName = hitCharacter.Name
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
	if victimPlayer then
		print(string.format(
			"[WeaponService] %s hit player %s for %d damage (headshot: %s)",
			player.Name,
			victimPlayer.Name,
			damage,
			tostring(hitData.isHeadshot)
		))
	elseif hitCharacterName then
		print(string.format(
			"[WeaponService] %s hit dummy/rig '%s' for %d damage (headshot: %s)",
			player.Name,
			hitCharacterName,
			damage,
			tostring(hitData.isHeadshot)
		))
	else
		print(string.format(
			"[WeaponService] %s shot at position %s (no target hit)",
			player.Name,
			tostring(hitData.hitPosition)
		))
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

	for _, dir in ipairs(shotData.pelletDirections) do
		local result = workspace:Raycast(origin, dir * range, raycastParams)
		if result then
			if not firstHitPosition then
				firstHitPosition = result.Position
			end

			-- Traverse up to find character (handles nested colliders like Dummy/Root/Head)
			local character = getCharacterFromPart(result.Instance)
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
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
	for character, damage in pairs(damageByCharacter) do
		totalDamage = totalDamage + damage
		totalHeadshots = totalHeadshots + (headshotByCharacter[character] or 0)
		self:ApplyDamageToCharacter(character, damage, player, (headshotByCharacter[character] or 0) > 0, shotData.weaponId)
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
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local combatService = self._registry:TryGet("CombatService")

	-- Check if victim is a real player
	local victimPlayer = Players:GetPlayerFromCharacter(character)

	-- If not a real player, check for pseudo-player (dummies)
	if not victimPlayer and combatService then
		victimPlayer = combatService:GetPlayerByCharacter(character)
	end

	-- Route through CombatService for players and dummies
	if victimPlayer and combatService then
		local result = combatService:ApplyDamage(victimPlayer, damage, {
			source = shooter,
			isHeadshot = isHeadshot,
			weaponId = weaponId or self._currentWeaponId,
		})

		if result and result.killed then
			print(string.format(
				"[WeaponService] %s killed %s (headshot: %s)",
				shooter.Name,
				character.Name,
				tostring(isHeadshot)
			))
		end
		return
	end

	-- Fallback for unregistered NPCs - direct humanoid damage
	humanoid:TakeDamage(damage)

	-- Set last damage dealer (useful for kill attribution)
	character:SetAttribute("LastDamageDealer", shooter.UserId)
	character:SetAttribute("WasHeadshot", isHeadshot)

	-- Check if killed
	if humanoid.Health <= 0 then
		print(string.format(
			"[WeaponService] %s killed %s (headshot: %s)",
			shooter.Name,
			character.Name,
			tostring(isHeadshot)
		))
	end
end

return WeaponService
