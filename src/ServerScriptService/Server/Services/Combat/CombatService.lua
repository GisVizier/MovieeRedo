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
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CombatResource = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatResource"))
local StatusEffectManager = require(ReplicatedStorage.Combat:WaitForChild("StatusEffectManager"))
local CombatConfig = require(ReplicatedStorage.Combat:WaitForChild("CombatConfig"))
local KillEffects = require(ReplicatedStorage.Combat:WaitForChild("KillEffects"))
local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))

local CombatService = {}
local DEBUG_LOGGING = false

CombatService._registry = nil
CombatService._net = nil
CombatService._playerResources = {} -- [Player] = CombatResource
CombatService._statusEffects = {} -- [Player] = StatusEffectManager
CombatService._assistTracking = {} -- [Player] = { [attackerUserId] = lastDamageTime }
CombatService._deathHandled = {} -- [Player|PseudoPlayer] = boolean

local ASSIST_WINDOW = 10 -- Seconds to qualify for assist
local DEATH_RAGDOLL_DURATION = CombatConfig.Death.RagdollDuration or 3

local function isRealPlayer(entity)
	return typeof(entity) == "Instance" and entity:IsA("Player")
end

local function resolveVictimCharacter(entity)
	if isRealPlayer(entity) then
		return entity.Character
	end

	if typeof(entity) == "Instance" and entity:IsA("Model") then
		return entity
	end

	if type(entity) == "table" then
		local character = rawget(entity, "Character")
		if typeof(character) == "Instance" and character:IsA("Model") then
			return character
		end
	end

	return nil
end

local function safeAddUltimate(resource, amount, context)
	if not resource then
		return false
	end

	local ok, err = pcall(function()
		resource:AddUltimate(amount)
	end)

	if not ok then
		warn(string.format("[CombatService] Failed to add ultimate (%s): %s", tostring(context), tostring(err)))
		return false
	end

	return true
end

function CombatService:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Give KillEffects access to the service registry so effects
	-- (e.g. Ragdoll) can reach CharacterService and other services.
	KillEffects:Init(registry)

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

	-- Debug: test death keybind (H) – kills self through the full combat pipeline
	self._net:ConnectServer("RequestTestDeath", function(player)
		local resource = self._playerResources[player]
		if not resource or not resource:IsAlive() then
			return
		end
		self:Kill(player, nil, "Ragdoll")
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
	if DEBUG_LOGGING then
		print(string.format("[CombatService] InitializePlayer: Registered '%s' (Character: %s)", player.Name, charName))
	end

	-- Create status effect manager
	local effectManager = StatusEffectManager.new(player, resource)
	self._statusEffects[player] = effectManager

	-- Initialize assist tracking
	self._assistTracking[player] = {}

	-- Connect death event
	resource.OnDeath:connect(function(killer, weaponId)
		self:_handleDeath(player, killer, weaponId, nil)
	end)

	self._deathHandled[player] = false

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
	self._deathHandled[player] = nil
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
	for player, _ in self._playerResources do
		local playerChar = player.Character
		if playerChar == character then
			return player
		end
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
		sourcePosition: Vector3?,
		hitPosition: Vector3?,
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

	if self._deathHandled[targetPlayer] then
		self._deathHandled[targetPlayer] = false
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
			if safeAddUltimate(attackerResource, ultGain, "damage_dealt") then
				self:_syncCombatState(options.source)
			end
		end
	end

	-- Grant ultimate to victim for damage taken (skip killing blow to avoid cleanup races)
	if result.healthDamage > 0 and not result.killed then
		local ultGain = result.healthDamage * CombatConfig.UltGain.DamageTaken
		-- Re-read in case the original resource got cleaned up by death handlers.
		local victimResource = self._playerResources[targetPlayer]
		if victimResource then
			safeAddUltimate(victimResource, ultGain, "damage_taken")
		end
	end

	-- Sync state to client
	self:_syncCombatState(targetPlayer)

	-- Broadcast damage for client combat UI
	local dealtDamage = (result.healthDamage or 0) + (result.shieldDamage or 0) + (result.overshieldDamage or 0)
	self:_broadcastDamage(targetPlayer, dealtDamage, options)

	-- Handle death synchronously to avoid races with async OnDeath listeners.
	if result.killed then
		self:_handleDeath(targetPlayer, options.source, options.weaponId, {
			sourcePosition = options.sourcePosition,
			hitPosition = options.hitPosition,
		})
	end

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

		-- Broadcast heal for client combat UI
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
	self:_handleDeath(player, killer, killEffect, nil)
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

function CombatService:_handleDeath(victim, killer, weaponId, deathContext)
	if self._deathHandled[victim] then
		return
	end
	self._deathHandled[victim] = true
	deathContext = deathContext or {}

	-- Grant ult to killer
	if killer and killer ~= victim then
		local killerResource = self._playerResources[killer]
		if killerResource then
			if safeAddUltimate(killerResource, CombatConfig.UltGain.Kill, "kill_bonus") then
				self:_syncCombatState(killer)
			end
		end
	end

	-- Grant ult to assists
	local assists = self:_getAssists(victim, killer)
	for _, assister in ipairs(assists) do
		local assisterResource = self._playerResources[assister]
		if assisterResource then
			if safeAddUltimate(assisterResource, CombatConfig.UltGain.Assist, "assist_bonus") then
				self:_syncCombatState(assister)
			end
		end
	end

	local effectId = self:_getKillEffect(killer, weaponId)
	local victimIsRealPlayer = isRealPlayer(victim)
	local victimCharacter = resolveVictimCharacter(victim)
	if not victimIsRealPlayer then
		print(string.format(
			"[CombatService] Executing kill effect '%s' for non-player victim %s (character=%s)",
			tostring(effectId),
			tostring(victim and victim.Name),
			tostring(victimCharacter and victimCharacter:GetFullName() or "nil")
		))
	end
	KillEffects:Execute(effectId, victim, killer, weaponId, {
		victimCharacter = victimCharacter,
		victimIsPlayer = victimIsRealPlayer,
		sourcePosition = deathContext.sourcePosition,
		hitPosition = deathContext.hitPosition,
	})

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
	if victimIsRealPlayer then
		local matchManager = self._registry:TryGet("MatchManager")
		if matchManager then
			matchManager:OnPlayerKilled(killer, victim)
		end
	end

	print("[CombatService]", killer and killer.Name or "Unknown", "killed", victim.Name)

	-- Server-controlled respawn after ragdoll plays out (only for real players)
	local characterService = self._registry:TryGet("CharacterService")
	if victimIsRealPlayer and characterService then
		local roundService = self._registry:TryGet("Round")
		local matchManager = self._registry:TryGet("MatchManager")

		local isTraining = roundService and roundService:IsPlayerInTraining(victim)
		local match = matchManager and matchManager:GetMatchForPlayer(victim)
		local isCompetitive = match and (match.state == "playing" or match.state == "resetting")

		-- Pick ragdoll/respawn delay based on context
		local respawnDelay
		if isTraining then
			respawnDelay = MatchmakingConfig.Modes.Training.respawnDelay or 2
		elseif isCompetitive then
			respawnDelay = match.modeConfig.roundResetDelay or DEATH_RAGDOLL_DURATION
		else
			respawnDelay = DEATH_RAGDOLL_DURATION
		end

		task.delay(respawnDelay, function()
			if not victim or not victim.Parent then
				return
			end

			-- Always clean up ragdoll
			characterService:Unragdoll(victim)

			-- Competitive round-based modes: MatchManager._resetRound handles
			-- respawning BOTH players, loadout UI, round counter, etc.
			-- Just clean up the ragdoll and let MatchManager take it from here.
			if isCompetitive and match.modeConfig.hasScoring then
				return
			end

			-- Training: revive + teleport to a random Exit gadget Spawn
			-- (same approach as Exit gadget — no character recreation, just teleport)
			if isTraining and roundService:IsPlayerInTraining(victim) then
				-- Find a random Exit gadget spawn in the player's area
				local spawnPos = nil
				local spawnLookVector = nil
				local areaId = victim:GetAttribute("CurrentArea")
				local gadgetService = self._registry:TryGet("GadgetService")

				if gadgetService and areaId then
					local exitGadgets = gadgetService:GetExitGadgetsForArea(areaId)
					local spawns = {}
					for _, gadget in ipairs(exitGadgets) do
						local model = gadget.model or (gadget.getModel and gadget:getModel())
						if model then
							local spawnPart = model:FindFirstChild("Spawn")
							if spawnPart and spawnPart:IsA("BasePart") then
								table.insert(spawns, spawnPart)
							end
						end
					end

					if #spawns > 0 then
						local chosen = spawns[math.random(1, #spawns)]
						local size = chosen.Size
						local offset = Vector3.new(
							(math.random() - 0.5) * size.X,
							0,
							(math.random() - 0.5) * size.Z
						)
						local spawnCFrame = chosen.CFrame * CFrame.new(offset)
						spawnPos = spawnCFrame.Position + Vector3.new(0, 3, 0)
						spawnLookVector = spawnCFrame.LookVector
					end
				end

				-- Revive combat resource (reset health and dead state)
				local resource = self._playerResources[victim]
				if resource then
					resource:Revive()
					self._deathHandled[victim] = false
					self:_syncCombatState(victim)
				end

				-- Reset humanoid health
				local character = victim.Character
				if character then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid.Health = humanoid.MaxHealth
					end
				end

				-- Tell client to teleport (same pattern as Exit gadget)
				if self._net and spawnPos then
					self._net:FireClient("PlayerRespawned", victim, {
						spawnPosition = spawnPos,
						spawnLookVector = spawnLookVector,
					})
				end
			else
				-- Lobby/no match: spawn new character normally (resets to "Lobby")
				characterService:SpawnCharacter(victim)
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
		hitPosition: Vector3?,
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
	local targetPivotPosition = nil
	if character then
		local root = character:FindFirstChild("Root")
			or character.PrimaryPart
			or character:FindFirstChild("HumanoidRootPart")
			or character:FindFirstChildWhichIsA("BasePart", true)
		targetPivotPosition = root and root.Position or nil
	end

	local position = options.hitPosition
	if not position then
		position = targetPivotPosition
	end
	if not position then
		return
	end

	local sourcePosition = options.sourcePosition
	if not sourcePosition and options.source and options.source.Character then
		local sourceCharacter = options.source.Character
		local sourceRoot = sourceCharacter:FindFirstChild("Root")
			or sourceCharacter.PrimaryPart
			or sourceCharacter:FindFirstChild("HumanoidRootPart")
		if sourceRoot then
			sourcePosition = sourceRoot.Position
		end
	end

	local targetEntityKey = nil
	if not target.UserId then
		targetEntityKey = tostring(target.Name or "entity")
		if character and character.GetDebugId then
			targetEntityKey = character:GetDebugId(0)
		end
	end

	self._net:FireAllClients("DamageDealt", {
		targetUserId = target.UserId,
		targetEntityKey = targetEntityKey,
		attackerUserId = options.source and options.source.UserId or nil,
		damage = damage,
		isHeadshot = options.isHeadshot or false,
		isCritical = options.isCritical or false,
		position = position,
		targetPivotPosition = targetPivotPosition,
		sourcePosition = sourcePosition,
	})
end

function CombatService:_broadcastHeal(target: Player, amount: number, options: { source: Player?, healType: string? }?)
	if not self._net then
		return
	end

	options = options or {}

	local character = target.Character
	local position = nil
	if character then
		local root = character:FindFirstChild("Root")
			or character.PrimaryPart
			or character:FindFirstChild("HumanoidRootPart")
			or character:FindFirstChildWhichIsA("BasePart", true)
		position = root and root.Position or nil
	end
	if not position then
		return
	end

	self._net:FireAllClients("DamageDealt", {
		targetUserId = target.UserId,
		targetEntityKey = target.UserId and nil or tostring(target.Name or "entity"),
		attackerUserId = options.source and options.source.UserId or nil,
		damage = amount,
		isHeadshot = false,
		isCritical = false,
		isHeal = true,
		position = position,
	})
end

return CombatService
