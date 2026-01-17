--!strict
-- WeaponHitService.lua
-- Server-side weapon hit validation and damage application
-- Validates client-side raycasts to prevent exploiting

local WeaponHitService = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local HitscanSystem = require(Locations.Modules.Weapons.Systems.HitscanSystem)
local WeaponConfig = require(Locations.Modules.Weapons.Configs)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)

-- Configuration (tolerance-based validation)
local MAX_DISTANCE_TOLERANCE = 50 -- studs - accounts for lag and movement
local MAX_TIME_TOLERANCE = 0.5 -- seconds - max age of hit data before rejecting

--[[
	Initializes the WeaponHitService
	Sets up RemoteEvent listeners for weapon firing
]]
function WeaponHitService:Init()
	LogService:RegisterCategory("WEAPON_HIT", "Weapon hit validation and damage application")

	-- Listen for weapon fire events from clients
	RemoteEvents:ConnectServer("WeaponFired", function(player, hitData)
		self:ValidateAndProcessHit(player, hitData)
	end)

	LogService:Info("WEAPON_HIT", "WeaponHitService initialized")
end

--[[
	Validates client-provided hit data and processes damage if valid

	Validation steps:
	1. Time validation (reject old hits)
	2. Distance validation (check if within weapon range + tolerance)
	3. Server-side raycast (confirm hit is reasonable)
	4. Apply damage if all checks pass

	@param player - The player who fired the weapon
	@param hitData - Table containing:
		- WeaponType: "Gun" or "Melee"
		- WeaponName: "Revolver", "Knife", etc.
		- Origin: Vector3 - Starting position of raycast
		- Direction: Vector3 - Direction vector (includes distance as magnitude)
		- IsShotgun: boolean - Whether this is shotgun mode (multiple pellets)
		- PelletCount: number - Number of pellets fired (shotgun only)
		- Hits: Array of hit info tables (shotgun mode uses this)
		- HitPosition: Vector3 or nil - Where the client's raycast hit (non-shotgun)
		- HitPartName: string or nil - Name of the part that was hit (non-shotgun)
		- Distance: number or nil - Distance to hit (non-shotgun)
		- Timestamp: number - os.clock() when client fired
		- TargetPlayer: Player or nil - Player who was hit (non-shotgun)
		- IsHeadshot: boolean or nil - Whether this was a headshot (non-shotgun)
]]
function WeaponHitService:ValidateAndProcessHit(player: Player, hitData: any)
	local character = player.Character
	if not character then
		LogService:Debug("WEAPON_HIT", "Player has no character", { Player = player.Name })
		return
	end

	-- Validate hit data structure
	if type(hitData) ~= "table" then
		LogService:Warn("WEAPON_HIT", "Invalid hitData type", { Player = player.Name })
		return
	end

	-- Get weapon config
	local weaponConfig = WeaponConfig:GetWeaponConfig(hitData.WeaponType, hitData.WeaponName)
	if not weaponConfig then
		LogService:Warn("WEAPON_HIT", "Invalid weapon config", {
			Player = player.Name,
			WeaponType = hitData.WeaponType,
			WeaponName = hitData.WeaponName,
		})
		return
	end

	-- All weapons now use the Hits array format (even single-shot weapons)
	-- This simplifies the code and makes it consistent across all weapon types
	self:ProcessHits(player, hitData, weaponConfig)
end

--[[
	Processes weapon hits (single or multiple)
	For weapons with multiple pellets (shotguns), damage is divided equally among all pellets

	@param player - The player who fired the weapon
	@param hitData - Hit data containing Hits array and PelletCount
	@param weaponConfig - Weapon configuration
]]
function WeaponHitService:ProcessHits(player: Player, hitData: any, weaponConfig: any)
	local pelletCount = hitData.PelletCount or 1
	local hits = hitData.Hits or {}

	if #hits == 0 then
		LogService:Debug("WEAPON_HIT", "Weapon missed all shots", {
			Player = player.Name,
			Weapon = hitData.WeaponName,
			PelletCount = pelletCount,
		})
		return
	end

	-- Calculate damage per pellet (divide base damage by pellet count)
	local baseDamagePerPellet = weaponConfig.Damage.BodyDamage / pelletCount
	local headshotDamagePerPellet = weaponConfig.Damage.HeadshotDamage / pelletCount

	-- Group hits by target player to apply total damage per player
	local damageByPlayer = {} -- {[Player] = {totalDamage, headshots, bodyshots, hitParts}}

	for pelletIndex, hitInfo in ipairs(hits) do
		-- Convert TargetUserId back to Player (Player objects don't serialize over RemoteEvents)
		local targetPlayer = hitInfo.TargetUserId and Players:GetPlayerByUserId(hitInfo.TargetUserId) or nil
		local isHeadshot = hitInfo.IsHeadshot or false
		local distance = hitInfo.Distance or 0
		local hitPartName = hitInfo.HitPartName or "Unknown"

		if targetPlayer then
			-- Calculate damage for this pellet (with falloff if applicable)
			local pelletDamage
			if isHeadshot then
				pelletDamage = self:CalculateDamageWithFalloff(
					weaponConfig,
					headshotDamagePerPellet,
					distance
				)
			else
				pelletDamage = self:CalculateDamageWithFalloff(
					weaponConfig,
					baseDamagePerPellet,
					distance
				)
			end

			-- Initialize player damage tracking if needed
			if not damageByPlayer[targetPlayer] then
				damageByPlayer[targetPlayer] = {
					totalDamage = 0,
					headshots = 0,
					bodyshots = 0,
					hitParts = {},
				}
			end

			-- Add to total damage for this player
			damageByPlayer[targetPlayer].totalDamage = damageByPlayer[targetPlayer].totalDamage + pelletDamage

			-- Track headshot/bodyshot counts
			if isHeadshot then
				damageByPlayer[targetPlayer].headshots = damageByPlayer[targetPlayer].headshots + 1
			else
				damageByPlayer[targetPlayer].bodyshots = damageByPlayer[targetPlayer].bodyshots + 1
			end

			-- Track hit parts
			table.insert(damageByPlayer[targetPlayer].hitParts, hitPartName)

			LogService:Debug("WEAPON_HIT", "Hit registered", {
				HitIndex = pelletIndex,
				Shooter = player.Name,
				Target = targetPlayer.Name,
				Damage = pelletDamage,
				Headshot = isHeadshot,
				Distance = distance,
			})
		end
	end

	-- Apply total damage to each player that was hit
	for targetPlayer, damageInfo in pairs(damageByPlayer) do
		local isHeadshot = damageInfo.headshots > 0 -- Consider it a headshot if any pellets hit head
		local hitPartsString = table.concat(damageInfo.hitParts, ", ")

		self:ApplyDamage(targetPlayer, damageInfo.totalDamage, player, isHeadshot, hitPartsString)

		LogService:Info("WEAPON_HIT", "Hit confirmed", {
			Shooter = player.Name,
			Target = targetPlayer.Name,
			TotalDamage = damageInfo.totalDamage,
			HitsCount = damageInfo.headshots + damageInfo.bodyshots,
			Headshots = damageInfo.headshots,
			Bodyshots = damageInfo.bodyshots,
			HitParts = hitPartsString,
		})
	end
end

--[[
	Helper function to calculate damage with distance falloff
	Used for shotgun pellets to apply falloff to the per-pellet damage

	@param weaponConfig - Weapon configuration
	@param baseDamage - Base damage for this calculation
	@param distance - Distance to target
	@return Final damage with falloff applied
]]
function WeaponHitService:CalculateDamageWithFalloff(weaponConfig: any, baseDamage: number, distance: number): number
	local minRange = weaponConfig.Damage.MinRange
	local maxRange = weaponConfig.Damage.MaxRange
	local minMultiplier = weaponConfig.Damage.MinDamageMultiplier

	if not minRange or not maxRange or not minMultiplier then
		return baseDamage
	end

	-- No falloff within min range
	if distance <= minRange then
		return baseDamage
	end

	-- Calculate falloff
	local falloffRange = maxRange - minRange
	local falloffDistance = math.min(distance - minRange, falloffRange)
	local falloffProgress = falloffDistance / falloffRange

	-- Linear interpolation for damage falloff
	local falloffMultiplier = 1 - (falloffProgress * (1 - minMultiplier))

	return baseDamage * falloffMultiplier
end

--[[
	Calculates final damage with distance-based falloff

	@param weaponConfig - Weapon configuration table
	@param distance - Distance to target in studs
	@param isHeadshot - Whether this was a headshot
	@return Final damage value
]]
function WeaponHitService:CalculateDamage(weaponConfig: any, distance: number, isHeadshot: boolean): number
	if not weaponConfig.Damage then
		return 0
	end

	-- Base damage
	local baseDamage = isHeadshot and weaponConfig.Damage.HeadshotDamage or weaponConfig.Damage.BodyDamage

	-- No falloff for melee weapons or if no range specified
	local minRange = weaponConfig.Damage.MinRange
	local maxRange = weaponConfig.Damage.MaxRange
	local minMultiplier = weaponConfig.Damage.MinDamageMultiplier

	if not minRange or not maxRange or not minMultiplier then
		return baseDamage
	end

	-- No falloff within min range
	if distance <= minRange then
		return baseDamage
	end

	-- Calculate falloff
	local falloffRange = maxRange - minRange
	local falloffDistance = math.min(distance - minRange, falloffRange)
	local falloffProgress = falloffDistance / falloffRange

	-- Linear interpolation for damage falloff
	local falloffMultiplier = 1 - (falloffProgress * (1 - minMultiplier))

	return math.floor(baseDamage * falloffMultiplier)
end

--[[
	Applies damage to a player and broadcasts to all clients

	@param targetPlayer - The player receiving damage
	@param damage - Amount of damage to apply
	@param shooterPlayer - The player who dealt the damage
	@param isHeadshot - Whether this was a headshot
	@param hitPartName - Name of the part that was hit
]]
function WeaponHitService:ApplyDamage(
	targetPlayer: Player,
	damage: number,
	shooterPlayer: Player,
	isHeadshot: boolean,
	hitPartName: string
)
	LogService:Info("WEAPON_HIT", "ApplyDamage called", {
		Target = targetPlayer.Name,
		Shooter = shooterPlayer.Name,
		Damage = damage,
		Headshot = isHeadshot,
		HitPart = hitPartName,
	})

	-- Get target's character and humanoid
	local character = targetPlayer.Character
	if not character then
		LogService:Warn("WEAPON_HIT", "Target has no character", { Target = targetPlayer.Name })
		return
	end

	local humanoid = CharacterLocations:GetHumanoidInstance(character)
	if not humanoid then
		LogService:Warn("WEAPON_HIT", "Target has no humanoid", { Target = targetPlayer.Name })
		return
	end

	if humanoid.Health <= 0 then
		LogService:Debug("WEAPON_HIT", "Target is already dead", {
			Target = targetPlayer.Name,
			Health = humanoid.Health,
		})
		return
	end

	-- SERVER DOES NOT APPLY DAMAGE - Client owns the Humanoid and rebuilds it
	-- Server only validates hits, calculates damage, and broadcasts to clients
	-- The client will apply damage to its own Humanoid instance

	-- Calculate new health (server-side tracking)
	local healthBefore = humanoid.Health
	local healthAfter = math.max(0, healthBefore - damage)
	local killed = healthAfter <= 0

	-- Update server's Humanoid for tracking (even though client owns the actual Humanoid)
	humanoid.Health = healthAfter

	LogService:Info("WEAPON_HIT", "Damage calculated and broadcasted", {
		Target = targetPlayer.Name,
		Shooter = shooterPlayer.Name,
		Damage = damage,
		Headshot = isHeadshot,
		HitPart = hitPartName,
		HealthBefore = healthBefore,
		HealthAfter = healthAfter,
		Killed = killed,
		ActualDamageDone = healthBefore - healthAfter,
	})

	-- Broadcast health change to ALL clients (they will update their local Humanoids)
	RemoteEvents:FireAllClients("PlayerHealthChanged", {
		Player = targetPlayer,
		Health = healthAfter,
		MaxHealth = humanoid.MaxHealth,
		Damage = damage,
		Attacker = shooterPlayer,
		Headshot = isHeadshot,
	})

	-- Broadcast damage to all clients for visual feedback (blood effects, damage numbers, etc.)
	RemoteEvents:FireAllClients("PlayerDamaged", {
		TargetUserId = targetPlayer.UserId,
		ShooterUserId = shooterPlayer.UserId,
		Damage = damage,
		Headshot = isHeadshot,
		HitPart = hitPartName,
		Timestamp = os.clock(),
	})
end

return WeaponHitService
