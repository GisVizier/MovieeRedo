local WeaponService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local HitValidator = require(script.Parent.Parent.AntiCheat.HitValidator)

function WeaponService:Init(registry, net)
	self._registry = registry
	self._net = net

	HitValidator:Init()

	-- Listen for weapon fire events
	net:ConnectServer("WeaponFired", function(player, shotData)
		self:OnWeaponFired(player, shotData)
	end)

	print("[WeaponService] Initialized")
end

function WeaponService:Start()
	-- No-op for now
end

function WeaponService:OnWeaponFired(player, shotData)
	print(string.format("[WeaponService] Received shot from %s", player and player.Name or "unknown"))
	
	if not player or not shotData or not shotData.weaponId then
		warn("[WeaponService] Invalid shot data from", player and player.Name or "unknown")
		return
	end

	-- Validate weapon config exists
	local weaponConfig = LoadoutConfig.getWeapon(shotData.weaponId)
	if not weaponConfig then
		warn("[WeaponService] Invalid weapon:", shotData.weaponId, "from", player.Name)
		return
	end

	-- Shotgun pellet handling (server-authoritative)
	if weaponConfig.pelletsPerShot and weaponConfig.pelletsPerShot > 1 and shotData.pelletDirections then
		local valid, reason = self:_validatePellets(shotData, weaponConfig)
		if not valid then
			warn("[WeaponService] Invalid pellet data from", player.Name, "Reason:", reason)
			return
		end

		local pelletResult = self:_processPellets(player, shotData, weaponConfig)
		if not pelletResult then
			warn("[WeaponService] Pellet processing failed for", player.Name)
			return
		end

		local victimPlayer = pelletResult.hitCharacter and Players:GetPlayerFromCharacter(pelletResult.hitCharacter) or nil

		-- Broadcast validated hit to all clients for VFX
		self._net:FireAllClients("HitConfirmed", {
			shooter = player.UserId,
			weaponId = shotData.weaponId,
			origin = shotData.origin,
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

	-- Validate the hit with anti-cheat
	local isValid, reason = HitValidator:ValidateHit(player, shotData, weaponConfig)
	if not isValid then
		warn("[WeaponService] Invalid shot from", player.Name, "Reason:", reason)
		HitValidator:RecordViolation(player, reason, 1)
		return
	end

	print(string.format("[WeaponService] Shot validated from %s with %s", player.Name, shotData.weaponId))

	-- Calculate damage
	local damage = self:CalculateDamage(shotData, weaponConfig)

	-- Apply damage if hit a character (player OR dummy)
	local victimPlayer = nil
	local hitCharacterName = nil
	
	if shotData.hitCharacter and shotData.hitCharacter:FindFirstChildOfClass("Humanoid") then
		-- Hit a character with Humanoid (could be player or dummy)
		self:ApplyDamageToCharacter(shotData.hitCharacter, damage, player, shotData.isHeadshot)
		hitCharacterName = shotData.hitCharacter.Name
		
		-- Check if it's a player
		if shotData.hitPlayer and shotData.hitPlayer:IsA("Player") then
			victimPlayer = shotData.hitPlayer
		end
	end

	-- Broadcast validated hit to all clients for VFX
	self._net:FireAllClients("HitConfirmed", {
		shooter = player.UserId,
		weaponId = shotData.weaponId,
		origin = shotData.origin,
		hitPosition = shotData.hitPosition,
		hitPlayer = victimPlayer and victimPlayer.UserId or nil,
		hitCharacterName = hitCharacterName,
		damage = damage,
		isHeadshot = shotData.isHeadshot,
	})

	-- Log successful hit
	if victimPlayer then
		print(string.format(
			"[WeaponService] %s hit player %s for %d damage (headshot: %s)",
			player.Name,
			victimPlayer.Name,
			damage,
			tostring(shotData.isHeadshot)
		))
	elseif hitCharacterName then
		print(string.format(
			"[WeaponService] %s hit dummy/rig '%s' for %d damage (headshot: %s)",
			player.Name,
			hitCharacterName,
			damage,
			tostring(shotData.isHeadshot)
		))
	else
		print(string.format(
			"[WeaponService] %s shot at position %s (no target hit)",
			player.Name,
			tostring(shotData.hitPosition)
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

			local character = result.Instance and result.Instance.Parent
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
		self:ApplyDamageToCharacter(character, damage, player, (headshotByCharacter[character] or 0) > 0)
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

function WeaponService:ApplyDamageToCharacter(character, damage, shooter, isHeadshot)
	if not character or not character.Parent then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Apply damage
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

		-- TODO: Fire kill event for kill feed
	end
end

return WeaponService
