--[[
	CombatService.lua
	Server-authoritative combat resource management
	
	Handles:
	- Player combat resource initialization
	- Damage application with i-frame and shield checks
	- Ultimate gain from damage dealt/taken/kills/assists
	- Status effect ticking
	- Death and kill effect execution
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CombatResource = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatResource"))
local StatusEffectManager = require(ReplicatedStorage.Combat:WaitForChild("StatusEffectManager"))
local CombatConfig = require(ReplicatedStorage.Combat:WaitForChild("CombatConfig"))
local KillEffects = require(ReplicatedStorage.Combat:WaitForChild("KillEffects"))

local CombatService = {}

CombatService._registry = nil
CombatService._net = nil
CombatService._playerResources = {} -- [Player] = CombatResource
CombatService._statusEffects = {} -- [Player] = StatusEffectManager
CombatService._assistTracking = {} -- [Player] = { [attackerUserId] = lastDamageTime }

local ASSIST_WINDOW = 10 -- Seconds to qualify for assist
local DEATH_RAGDOLL_DURATION = CombatConfig.Death.RagdollDuration or 3

function CombatService:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Tick status effects on heartbeat
	RunService.Heartbeat:Connect(function(deltaTime)
		self:_tickStatusEffects(deltaTime)
	end)
end

function CombatService:Start()
	-- Clean up on player leave
	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)
end

-- =============================================================================
-- PLAYER INITIALIZATION
-- =============================================================================

--[[
	Initializes combat resources for a player
	Call this when a player's character spawns
	@param player Player
	@param options table? - Optional overrides
]]
function CombatService:InitializePlayer(
	player: Player,
	options: {
		maxHealth: number?,
		maxShield: number?,
		maxUltimate: number?,
	}?
)
	-- Clean up existing resources
	self:_cleanupPlayer(player)

	-- Create combat resource
	local resource = CombatResource.new(player, options)
	self._playerResources[player] = resource

	-- Debug: Log registration
	local charName = player.Character and player.Character.Name or "no character"
	print(string.format("[CombatService] InitializePlayer: Registered '%s' (Character: %s)", player.Name, charName))

	-- Create status effect manager
	local effectManager = StatusEffectManager.new(player, resource)
	self._statusEffects[player] = effectManager

	-- Initialize assist tracking
	self._assistTracking[player] = {}

	-- Connect death event
	resource.OnDeath:connect(function(killer, weaponId)
		self:_handleDeath(player, killer, weaponId)
	end)

	-- Sync initial state to client
	self:_syncCombatState(player)
end

--[[
	Cleans up combat resources for a player
	@param player Player
]]
function CombatService:_cleanupPlayer(player: Player)
	local resource = self._playerResources[player]
	if resource then
		resource:Destroy()
		self._playerResources[player] = nil
	end

	local effectManager = self._statusEffects[player]
	if effectManager then
		effectManager:Destroy()
		self._statusEffects[player] = nil
	end

	self._assistTracking[player] = nil
end

--[[
	Public method to clean up combat resources for a player or pseudo-player (dummies)
	@param player Player|table - The player or pseudo-player to clean up
]]
function CombatService:CleanupPlayer(player)
	self:_cleanupPlayer(player)
end

-- =============================================================================
-- RESOURCE ACCESS
-- =============================================================================

--[[
	Gets the combat resource for a player
	@param player Player
	@return CombatResource?
]]
function CombatService:GetResource(player: Player)
	return self._playerResources[player]
end

--[[
	Gets the status effect manager for a player
	@param player Player
	@return StatusEffectManager?
]]
function CombatService:GetStatusEffects(player: Player)
	return self._statusEffects[player]
end

--[[
	Gets the player/pseudo-player by their character model
	Works for both real players and dummies (pseudo-players)
	@param character Model
	@return Player|table?
]]
function CombatService:GetPlayerByCharacter(character)
	if not character then
		return nil
	end

	-- Check all registered players/pseudo-players
	local count = 0
	for player, _ in self._playerResources do
		count = count + 1
		local playerChar = player.Character
		if playerChar == character then
			print(string.format("[CombatService] GetPlayerByCharacter: Found '%s' for character '%s'", 
				player.Name, character.Name))
			return player
		end
	end

	-- Debug: print registered characters if not found
	print(string.format("[CombatService] GetPlayerByCharacter: Looking for '%s' (%s), checked %d registered players, not found",
		character.Name, tostring(character), count))
	
	-- List all registered characters for debugging
	print("[CombatService] Registered characters:")
	for player, _ in self._playerResources do
		local charName = player.Character and player.Character.Name or "nil"
		local charRef = player.Character and tostring(player.Character) or "nil"
		print(string.format("  - %s: Character=%s (%s)", player.Name, charName, charRef))
	end

	return nil
end

-- =============================================================================
-- DAMAGE API
-- =============================================================================

--[[
	Applies damage to a player through the combat system
	@param targetPlayer Player - The player receiving damage
	@param damage number - Raw damage amount
	@param options DamageOptions? - Damage context
	@return DamageResult?
]]
function CombatService:ApplyDamage(
	targetPlayer: Player,
	damage: number,
	options: {
		source: Player?,
		isTrueDamage: boolean?,
		isHeadshot: boolean?,
		weaponId: string?,
		damageType: string?,
		skipIFrames: boolean?,
	}?
)
	options = options or {}

	local resource = self._playerResources[targetPlayer]
	if not resource or not resource:IsAlive() then
		return nil
	end

	-- Apply damage through resource
	local result = resource:TakeDamage(damage, options)

	if result.blocked then
		return result
	end

	-- Notify status effects of damage (for effects like Frozen that break on damage)
	local effectManager = self._statusEffects[targetPlayer]
	if effectManager then
		effectManager:NotifyDamage(result.healthDamage, options.source)
	end

	-- Track assist
	if options.source and options.source ~= targetPlayer then
		self:_trackAssist(targetPlayer, options.source)
	end

	-- Grant ultimate to attacker for damage dealt
	if options.source and result.healthDamage > 0 then
		local attackerResource = self._playerResources[options.source]
		if attackerResource then
			local ultGain = result.healthDamage * CombatConfig.UltGain.DamageDealt
			attackerResource:AddUltimate(ultGain)
			self:_syncCombatState(options.source)
		end
	end

	-- Grant ultimate to victim for damage taken
	if result.healthDamage > 0 then
		local ultGain = result.healthDamage * CombatConfig.UltGain.DamageTaken
		resource:AddUltimate(ultGain)
	end

	-- Sync state to client
	self:_syncCombatState(targetPlayer)

	-- Broadcast damage for damage numbers
	self:_broadcastDamage(targetPlayer, damage, options)

	return result
end

--[[
	Heals a player
	@param player Player
	@param amount number
	@param options HealOptions?
	@return number - Actual amount healed
]]
function CombatService:Heal(player: Player, amount: number, options: { source: Player?, healType: string? }?): number
	local resource = self._playerResources[player]
	if not resource then
		return 0
	end

	local healed = resource:Heal(amount, options)

	if healed > 0 then
		self:_syncCombatState(player)

		-- Broadcast heal for damage numbers
		self:_broadcastHeal(player, healed, options)
	end

	return healed
end

--[[
	Kills a player instantly
	@param player Player
	@param killer Player?
	@param killEffect string?
]]
function CombatService:Kill(player: Player, killer: Player?, killEffect: string?)
	local resource = self._playerResources[player]
	if not resource then
		return
	end

	resource:Kill(killer, killEffect)
end

-- =============================================================================
-- ULTIMATE API
-- =============================================================================

--[[
	Adds ultimate to a player
	@param player Player
	@param amount number
]]
function CombatService:AddUltimate(player: Player, amount: number)
	local resource = self._playerResources[player]
	if not resource then
		return
	end

	resource:AddUltimate(amount)
	self:_syncCombatState(player)
end

--[[
	Spends ultimate from a player
	@param player Player
	@param amount number
	@return boolean - True if successfully spent
]]
function CombatService:SpendUltimate(player: Player, amount: number): boolean
	local resource = self._playerResources[player]
	if not resource then
		return false
	end

	local success = resource:SpendUltimate(amount)
	if success then
		self:_syncCombatState(player)
	end

	return success
end

-- =============================================================================
-- I-FRAME API
-- =============================================================================

--[[
	Grants invulnerability frames to a player
	@param player Player
	@param duration number
]]
function CombatService:GrantIFrames(player: Player, duration: number)
	local resource = self._playerResources[player]
	if not resource then
		return
	end

	resource:GrantIFrames(duration)
end

--[[
	Sets invulnerability state for a player
	@param player Player
	@param invulnerable boolean
]]
function CombatService:SetInvulnerable(player: Player, invulnerable: boolean)
	local resource = self._playerResources[player]
	if not resource then
		return
	end

	resource:SetInvulnerable(invulnerable)
end

--[[
	Checks if a player is invulnerable
	@param player Player
	@return boolean
]]
function CombatService:IsInvulnerable(player: Player): boolean
	local resource = self._playerResources[player]
	if not resource then
		return false
	end

	return resource:IsInvulnerable()
end

-- =============================================================================
-- STATUS EFFECTS API
-- =============================================================================

--[[
	Applies a status effect to a player
	@param player Player
	@param effectId string
	@param settings StatusEffectSettings
]]
function CombatService:ApplyStatusEffect(
	player: Player,
	effectId: string,
	settings: {
		duration: number,
		tickRate: number?,
		source: Player?,
		[string]: any,
	}
)
	local effectManager = self._statusEffects[player]
	if not effectManager then
		return
	end

	effectManager:Apply(effectId, settings)
	self:_syncStatusEffects(player)
end

--[[
	Removes a status effect from a player
	@param player Player
	@param effectId string
	@param reason string?
]]
function CombatService:RemoveStatusEffect(player: Player, effectId: string, reason: string?)
	local effectManager = self._statusEffects[player]
	if not effectManager then
		return
	end

	effectManager:Remove(effectId, reason)
	self:_syncStatusEffects(player)
end

--[[
	Removes all status effects from a player
	@param player Player
	@param reason string?
]]
function CombatService:RemoveAllStatusEffects(player: Player, reason: string?)
	local effectManager = self._statusEffects[player]
	if not effectManager then
		return
	end

	effectManager:RemoveAll(reason)
	self:_syncStatusEffects(player)
end

-- =============================================================================
-- INTERNAL - STATUS EFFECT TICKING
-- =============================================================================

function CombatService:_tickStatusEffects(deltaTime: number)
	for player, effectManager in pairs(self._statusEffects) do
		effectManager:Tick(deltaTime)
	end
end

-- =============================================================================
-- INTERNAL - DEATH HANDLING
-- =============================================================================

function CombatService:_handleDeath(victim: Player, killer: Player?, weaponId: string?)
	-- Grant ult to killer
	if killer and killer ~= victim then
		local killerResource = self._playerResources[killer]
		if killerResource then
			killerResource:AddUltimate(CombatConfig.UltGain.Kill)
			self:_syncCombatState(killer)
		end
	end

	-- Grant ult to assists
	local assists = self:_getAssists(victim, killer)
	for _, assister in ipairs(assists) do
		local assisterResource = self._playerResources[assister]
		if assisterResource then
			assisterResource:AddUltimate(CombatConfig.UltGain.Assist)
			self:_syncCombatState(assister)
		end
	end

	-- Determine kill effect
	local effectId = self:_getKillEffect(killer, weaponId)

	-- Trigger ragdoll through CharacterService for ragdoll-type kill effects
	local characterService = self._registry:TryGet("CharacterService")
	if characterService and effectId == "Ragdoll" then
		-- Build knockback direction from killer toward victim
		local ragdollOptions = {}
		local victimChar = victim.Character
		local killerChar = killer and killer.Character

		if victimChar and killerChar then
			local victimRoot = victimChar:FindFirstChild("Root") or victimChar.PrimaryPart
			local killerRoot = killerChar:FindFirstChild("Root") or killerChar.PrimaryPart
			if victimRoot and killerRoot then
				local direction = (victimRoot.Position - killerRoot.Position).Unit
				ragdollOptions.Velocity = direction * 40 + Vector3.new(0, 30, 0)
			end
		end

		-- If no directional knockback, apply a default upward fling
		if not ragdollOptions.Velocity then
			ragdollOptions.Velocity = Vector3.new(0, 30, 0)
		end

		-- Ragdoll with no auto-recovery (server controls respawn timing)
		characterService:Ragdoll(victim, nil, ragdollOptions)
	else
		-- Non-ragdoll kill effects: execute as before
		KillEffects:Execute(effectId, victim, killer, weaponId)
	end

	-- Clear status effects
	local effectManager = self._statusEffects[victim]
	if effectManager then
		effectManager:RemoveAll("death")
	end

	-- Clear assist tracking
	self._assistTracking[victim] = {}

	-- Broadcast kill event
	if self._net then
		self._net:FireAllClients("PlayerKilled", {
			victimUserId = victim.UserId,
			killerUserId = killer and killer.UserId or nil,
			weaponId = weaponId,
			killEffect = effectId,
		})
	end

	-- Notify MatchManager for scoring/round reset (only for real players)
	if typeof(victim) == "Instance" and victim:IsA("Player") then
		local matchManager = self._registry:TryGet("MatchManager")
		if matchManager then
			matchManager:OnPlayerKilled(killer, victim)
		end
	end

	print("[CombatService]", killer and killer.Name or "Unknown", "killed", victim.Name)

	-- Server-controlled respawn after ragdoll plays out (only for real players)
	if typeof(victim) == "Instance" and victim:IsA("Player") and characterService then
		-- Use training respawn delay if in training, otherwise default ragdoll duration
		local roundService = self._registry:TryGet("RoundService")
		local isTraining = roundService and roundService:IsPlayerInTraining(victim)
		local respawnDelay = isTraining and 2 or DEATH_RAGDOLL_DURATION

		task.delay(respawnDelay, function()
			if not victim or not victim.Parent then
				return
			end

			-- Clean up ragdoll before respawning
			characterService:Unragdoll(victim)
			characterService:SpawnCharacter(victim)

			-- If in training, teleport back to training spawn instead of lobby
			if isTraining and roundService:IsPlayerInTraining(victim) then
				roundService:RespawnInTraining(victim)
			end
		end)
	end
end

function CombatService:_getKillEffect(killer: Player?, weaponId: string?): string
	if not killer or not weaponId then
		return CombatConfig.Death.DefaultKillEffect
	end

	-- Try to get player's custom kill effect for this weapon
	-- This would come from PlayerDataTable.WEAPON_DATA
	local PlayerDataTable = require(ReplicatedStorage:WaitForChild("PlayerDataTable"))
	local weaponData = PlayerDataTable.getWeaponData and PlayerDataTable.getWeaponData(weaponId)

	if weaponData and weaponData.killEffect then
		return weaponData.killEffect
	end

	return CombatConfig.Death.DefaultKillEffect
end

-- =============================================================================
-- INTERNAL - ASSIST TRACKING
-- =============================================================================

function CombatService:_trackAssist(victim: Player, attacker: Player)
	local tracking = self._assistTracking[victim]
	if not tracking then
		return
	end

	tracking[attacker.UserId] = os.clock()
end

function CombatService:_getAssists(victim: Player, killer: Player?): { Player }
	local tracking = self._assistTracking[victim]
	if not tracking then
		return {}
	end

	local now = os.clock()
	local assists = {}

	for userId, lastTime in pairs(tracking) do
		if now - lastTime <= ASSIST_WINDOW then
			local player = Players:GetPlayerByUserId(userId)
			if player and player ~= killer and player ~= victim then
				table.insert(assists, player)
			end
		end
	end

	return assists
end

-- =============================================================================
-- INTERNAL - NETWORKING
-- =============================================================================

function CombatService:_syncCombatState(player: Player)
	if not self._net then
		return
	end

	-- Skip firing to non-Player entities (like dummies)
	if not (typeof(player) == "Instance" and player:IsA("Player")) then
		return
	end

	local resource = self._playerResources[player]
	if not resource then
		return
	end

	local effectManager = self._statusEffects[player]
	local statusEffects = effectManager and effectManager:GetActiveEffects() or {}

	local state = resource:GetState()

	self._net:FireClient("CombatStateUpdate", player, {
		health = state.health,
		maxHealth = state.maxHealth,
		shield = state.shield,
		overshield = state.overshield,
		ultimate = state.ultimate,
		maxUltimate = state.maxUltimate,
		statusEffects = statusEffects,
	})
end

function CombatService:_syncStatusEffects(player: Player)
	if not self._net then
		return
	end

	-- Skip firing to non-Player entities (like dummies)
	if not (typeof(player) == "Instance" and player:IsA("Player")) then
		return
	end

	local effectManager = self._statusEffects[player]
	if not effectManager then
		return
	end

	self._net:FireClient("StatusEffectUpdate", player, effectManager:GetActiveEffects())
end

function CombatService:_broadcastDamage(
	target: Player,
	damage: number,
	options: {
		source: Player?,
		isHeadshot: boolean?,
		isCritical: boolean?,
		weaponId: string?,
	}?
)
	if not self._net then
		return
	end

	options = options or {}

	local character = target.Character
	local position = character and character.PrimaryPart and character.PrimaryPart.Position
	if not position then
		return
	end

	-- Offset position upward for head
	local head = character:FindFirstChild("Head")
	if head then
		position = head.Position + Vector3.new(0, 1, 0)
	end

	self._net:FireAllClients("DamageDealt", {
		targetUserId = target.UserId,
		attackerUserId = options.source and options.source.UserId or nil,
		damage = damage,
		isHeadshot = options.isHeadshot or false,
		isCritical = options.isCritical or false,
		position = position,
	})
end

function CombatService:_broadcastHeal(target: Player, amount: number, options: { source: Player?, healType: string? }?)
	if not self._net then
		return
	end

	options = options or {}

	local character = target.Character
	local position = character and character.PrimaryPart and character.PrimaryPart.Position
	if not position then
		return
	end

	self._net:FireAllClients("DamageDealt", {
		targetUserId = target.UserId,
		attackerUserId = options.source and options.source.UserId or nil,
		damage = amount,
		isHeadshot = false,
		isCritical = false,
		isHeal = true,
		position = position,
	})
end

return CombatService
