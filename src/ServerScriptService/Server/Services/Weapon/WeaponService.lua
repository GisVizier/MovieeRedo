local WeaponService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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
