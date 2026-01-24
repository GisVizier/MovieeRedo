--[[
	CombatResource.lua
	Per-player resource container for health, shield, ultimate, and i-frames
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Signal = require(ReplicatedStorage:WaitForChild("CoreUI"):WaitForChild("Signal"))
local CombatConfig = require(script.Parent:WaitForChild("CombatConfig"))

local CombatResource = {}
CombatResource.__index = CombatResource

--[[
	Creates a new CombatResource for a player
	@param player Player - The player this resource belongs to
	@param options table? - Optional overrides for default values
	@return CombatResource
]]
function CombatResource.new(player: Player, options: {
	maxHealth: number?,
	maxShield: number?,
	maxOvershield: number?,
	maxUltimate: number?,
}?)
	local self = setmetatable({}, CombatResource)
	
	options = options or {}
	
	self._player = player
	
	-- Health
	self._health = options.maxHealth or CombatConfig.DefaultMaxHealth
	self._maxHealth = options.maxHealth or CombatConfig.DefaultMaxHealth
	
	-- Shield (stubbed, disabled by default)
	self._shield = 0
	self._maxShield = options.maxShield or CombatConfig.DefaultMaxShield
	self._overshield = 0
	self._maxOvershield = options.maxOvershield or CombatConfig.DefaultMaxOvershield
	self._lastDamageTime = 0
	
	-- Ultimate
	self._ultimate = 0
	self._maxUltimate = options.maxUltimate or CombatConfig.DefaultMaxUltimate
	
	-- I-Frames
	self._isInvulnerable = false
	self._iFrameEndTime = 0
	
	-- State
	self._isDead = false
	
	-- Events
	self.OnHealthChanged = Signal.new()
	self.OnMaxHealthChanged = Signal.new()
	self.OnShieldChanged = Signal.new()
	self.OnOvershieldChanged = Signal.new()
	self.OnUltimateChanged = Signal.new()
	self.OnUltimateFull = Signal.new()
	self.OnUltimateSpent = Signal.new()
	self.OnDamaged = Signal.new()
	self.OnHealed = Signal.new()
	self.OnDeath = Signal.new()
	self.OnInvulnerabilityChanged = Signal.new()
	
	-- Sync to player attributes for UI
	self:_syncAttributes()
	
	return self
end

--[[
	Syncs combat state to player attributes for UI display
]]
function CombatResource:_syncAttributes()
	if not self._player then return end
	
	self._player:SetAttribute("Health", self._health)
	self._player:SetAttribute("MaxHealth", self._maxHealth)
	self._player:SetAttribute("Shield", self._shield)
	self._player:SetAttribute("Overshield", self._overshield)
	self._player:SetAttribute("Ultimate", self._ultimate)
	self._player:SetAttribute("MaxUltimate", self._maxUltimate)
	
	-- Sync to Humanoid as well
	local character = self._player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.MaxHealth = self._maxHealth
			humanoid.Health = self._health
		end
	end
end

-- =============================================================================
-- HEALTH API
-- =============================================================================

function CombatResource:GetHealth(): number
	return self._health
end

function CombatResource:GetMaxHealth(): number
	return self._maxHealth
end

function CombatResource:SetHealth(value: number)
	local oldHealth = self._health
	self._health = math.clamp(value, 0, self._maxHealth)
	
	if self._health ~= oldHealth then
		self._player:SetAttribute("Health", self._health)
		self.OnHealthChanged:fire(self._health, oldHealth, nil)
	end
	
	if self._health <= 0 and not self._isDead then
		self._isDead = true
		self.OnDeath:fire(nil, nil)
	end
end

function CombatResource:SetMaxHealth(value: number)
	local oldMax = self._maxHealth
	self._maxHealth = math.max(1, value)
	
	if self._maxHealth ~= oldMax then
		self._player:SetAttribute("MaxHealth", self._maxHealth)
		self.OnMaxHealthChanged:fire(self._maxHealth, oldMax)
	end
	
	-- Clamp current health to new max
	if self._health > self._maxHealth then
		self:SetHealth(self._maxHealth)
	end
end

--[[
	Heals the player by the specified amount
	@param amount number - Amount to heal
	@param options HealOptions? - Optional heal context
	@return number - Actual amount healed
]]
function CombatResource:Heal(amount: number, options: {source: Player?, healType: string?}?): number
	if self._isDead then return 0 end
	
	local oldHealth = self._health
	local newHealth = math.min(self._health + amount, self._maxHealth)
	local actualHeal = newHealth - oldHealth
	
	if actualHeal > 0 then
		self._health = newHealth
		self._player:SetAttribute("Health", self._health)
		self.OnHealthChanged:fire(self._health, oldHealth, options and options.source)
		self.OnHealed:fire(actualHeal, options and options.source)
	end
	
	return actualHeal
end

--[[
	Applies damage to the player through shield/health pipeline
	@param amount number - Raw damage amount
	@param options DamageOptions? - Damage context
	@return DamageResult
]]
function CombatResource:TakeDamage(amount: number, options: {
	source: Player?,
	isTrueDamage: boolean?,
	isHeadshot: boolean?,
	weaponId: string?,
	damageType: string?,
	skipIFrames: boolean?,
}?): {healthDamage: number, shieldDamage: number, overshieldDamage: number, blocked: boolean, killed: boolean}
	options = options or {}
	
	-- Check if dead
	if self._isDead then
		return {
			healthDamage = 0,
			shieldDamage = 0,
			overshieldDamage = 0,
			blocked = true,
			killed = false,
		}
	end
	
	-- Check i-frames (true damage bypasses)
	if not options.skipIFrames and not options.isTrueDamage and self:IsInvulnerable() then
		return {
			healthDamage = 0,
			shieldDamage = 0,
			overshieldDamage = 0,
			blocked = true,
			killed = false,
		}
	end
	
	local remainingDamage = amount
	local overshieldDamage = 0
	local shieldDamage = 0
	local healthDamage = 0
	
	-- 1. Overshield absorbs first
	if self._overshield > 0 and remainingDamage > 0 then
		overshieldDamage = math.min(self._overshield, remainingDamage)
		self._overshield = self._overshield - overshieldDamage
		remainingDamage = remainingDamage - overshieldDamage
		self._player:SetAttribute("Overshield", self._overshield)
		self.OnOvershieldChanged:fire(self._overshield, self._overshield + overshieldDamage)
	end
	
	-- 2. Shield absorbs next (if enabled)
	if CombatConfig.Shield.Enabled and self._shield > 0 and remainingDamage > 0 then
		shieldDamage = math.min(self._shield, remainingDamage)
		self._shield = self._shield - shieldDamage
		remainingDamage = remainingDamage - shieldDamage
		self._player:SetAttribute("Shield", self._shield)
		self.OnShieldChanged:fire(self._shield, self._shield + shieldDamage)
	end
	
	-- 3. Health takes remaining
	if remainingDamage > 0 then
		local oldHealth = self._health
		healthDamage = math.min(self._health, remainingDamage)
		self._health = self._health - healthDamage
		self._player:SetAttribute("Health", self._health)
		self.OnHealthChanged:fire(self._health, oldHealth, options.source)
	end
	
	-- Track damage time for shield regen
	self._lastDamageTime = os.clock()
	
	-- Fire damaged event
	local totalDamage = overshieldDamage + shieldDamage + healthDamage
	if totalDamage > 0 then
		self.OnDamaged:fire(totalDamage, options.source, {
			isHeadshot = options.isHeadshot,
			weaponId = options.weaponId,
			damageType = options.damageType,
		})
	end
	
	-- Check for death
	local killed = false
	if self._health <= 0 and not self._isDead then
		self._isDead = true
		killed = true
		self.OnDeath:fire(options.source, options.weaponId)
	end
	
	return {
		healthDamage = healthDamage,
		shieldDamage = shieldDamage,
		overshieldDamage = overshieldDamage,
		blocked = false,
		killed = killed,
	}
end

--[[
	Kills the player instantly
	@param killer Player? - The player who caused the death
	@param killEffect string? - Kill effect to use
]]
function CombatResource:Kill(killer: Player?, killEffect: string?)
	if self._isDead then return end
	
	local oldHealth = self._health
	self._health = 0
	self._isDead = true
	self._player:SetAttribute("Health", 0)
	self.OnHealthChanged:fire(0, oldHealth, killer)
	self.OnDeath:fire(killer, killEffect)
end

function CombatResource:IsAlive(): boolean
	return not self._isDead and self._health > 0
end

function CombatResource:IsDead(): boolean
	return self._isDead
end

--[[
	Revives the player with specified health
	@param health number? - Health to revive with (defaults to max)
]]
function CombatResource:Revive(health: number?)
	if not self._isDead then return end
	
	self._isDead = false
	self._health = health or self._maxHealth
	self._player:SetAttribute("Health", self._health)
	self.OnHealthChanged:fire(self._health, 0, nil)
end

-- =============================================================================
-- SHIELD API (Stubbed - disabled by default)
-- =============================================================================

function CombatResource:GetShield(): number
	return self._shield
end

function CombatResource:GetMaxShield(): number
	return self._maxShield
end

function CombatResource:SetShield(value: number)
	local oldShield = self._shield
	self._shield = math.clamp(value, 0, self._maxShield)
	
	if self._shield ~= oldShield then
		self._player:SetAttribute("Shield", self._shield)
		self.OnShieldChanged:fire(self._shield, oldShield)
	end
end

function CombatResource:SetMaxShield(value: number)
	local oldMax = self._maxShield
	self._maxShield = math.max(0, value)
	
	if self._shield > self._maxShield then
		self:SetShield(self._maxShield)
	end
end

function CombatResource:GetOvershield(): number
	return self._overshield
end

function CombatResource:AddOvershield(amount: number)
	local oldOvershield = self._overshield
	self._overshield = math.clamp(self._overshield + amount, 0, self._maxOvershield)
	
	if self._overshield ~= oldOvershield then
		self._player:SetAttribute("Overshield", self._overshield)
		self.OnOvershieldChanged:fire(self._overshield, oldOvershield)
	end
end

function CombatResource:GetTotalShield(): number
	return self._shield + self._overshield
end

--[[
	Tick shield regeneration (call from update loop if shield enabled)
	@param deltaTime number
]]
function CombatResource:TickShieldRegen(deltaTime: number)
	if not CombatConfig.Shield.Enabled then return end
	if self._shield >= self._maxShield then return end
	
	local timeSinceDamage = os.clock() - self._lastDamageTime
	if timeSinceDamage < CombatConfig.Shield.RegenDelay then return end
	
	local regenAmount = CombatConfig.Shield.RegenRate * deltaTime
	self:SetShield(self._shield + regenAmount)
end

-- =============================================================================
-- ULTIMATE API
-- =============================================================================

function CombatResource:GetUltimate(): number
	return self._ultimate
end

function CombatResource:GetMaxUltimate(): number
	return self._maxUltimate
end

function CombatResource:SetUltimate(value: number)
	local oldUlt = self._ultimate
	local wasFull = self._ultimate >= self._maxUltimate
	
	self._ultimate = math.clamp(value, 0, self._maxUltimate)
	
	if self._ultimate ~= oldUlt then
		self._player:SetAttribute("Ultimate", self._ultimate)
		self.OnUltimateChanged:fire(self._ultimate, oldUlt)
		
		-- Fire full event if just became full
		if self._ultimate >= self._maxUltimate and not wasFull then
			self.OnUltimateFull:fire()
		end
	end
end

function CombatResource:SetMaxUltimate(value: number)
	self._maxUltimate = math.max(1, value)
	self._player:SetAttribute("MaxUltimate", self._maxUltimate)
	
	if self._ultimate > self._maxUltimate then
		self:SetUltimate(self._maxUltimate)
	end
end

function CombatResource:AddUltimate(amount: number)
	self:SetUltimate(self._ultimate + amount)
end

--[[
	Attempts to spend ultimate
	@param amount number - Amount to spend
	@return boolean - True if successfully spent
]]
function CombatResource:SpendUltimate(amount: number): boolean
	if self._ultimate < amount then
		return false
	end
	
	local oldUlt = self._ultimate
	self._ultimate = self._ultimate - amount
	self._player:SetAttribute("Ultimate", self._ultimate)
	self.OnUltimateChanged:fire(self._ultimate, oldUlt)
	self.OnUltimateSpent:fire(amount)
	
	return true
end

function CombatResource:IsUltFull(): boolean
	return self._ultimate >= self._maxUltimate
end

-- =============================================================================
-- I-FRAME API
-- =============================================================================

--[[
	Grants invulnerability frames for a duration
	@param duration number - Duration in seconds
]]
function CombatResource:GrantIFrames(duration: number)
	duration = duration or CombatConfig.IFrames.DefaultDuration
	
	local newEndTime = os.clock() + duration
	
	-- Extend if new duration is longer
	if newEndTime > self._iFrameEndTime then
		self._iFrameEndTime = newEndTime
	end
	
	if not self._isInvulnerable then
		self._isInvulnerable = true
		self.OnInvulnerabilityChanged:fire(true)
	end
end

--[[
	Manually sets invulnerability state
	@param invulnerable boolean
]]
function CombatResource:SetInvulnerable(invulnerable: boolean)
	if invulnerable then
		self._isInvulnerable = true
		self._iFrameEndTime = math.huge -- Infinite until manually disabled
	else
		self._isInvulnerable = false
		self._iFrameEndTime = 0
	end
	
	self.OnInvulnerabilityChanged:fire(self._isInvulnerable)
end

function CombatResource:IsInvulnerable(): boolean
	-- Check timed i-frames
	if self._iFrameEndTime > 0 and os.clock() >= self._iFrameEndTime then
		if self._isInvulnerable then
			self._isInvulnerable = false
			self._iFrameEndTime = 0
			self.OnInvulnerabilityChanged:fire(false)
		end
	end
	
	return self._isInvulnerable
end

-- =============================================================================
-- STATE
-- =============================================================================

--[[
	Gets the current combat state as a table
	@return CombatState
]]
function CombatResource:GetState(): {
	health: number,
	maxHealth: number,
	shield: number,
	maxShield: number,
	overshield: number,
	maxOvershield: number,
	ultimate: number,
	maxUltimate: number,
	isInvulnerable: boolean,
	iFrameEndTime: number,
	isDead: boolean,
}
	return {
		health = self._health,
		maxHealth = self._maxHealth,
		shield = self._shield,
		maxShield = self._maxShield,
		overshield = self._overshield,
		maxOvershield = self._maxOvershield,
		ultimate = self._ultimate,
		maxUltimate = self._maxUltimate,
		isInvulnerable = self:IsInvulnerable(),
		iFrameEndTime = self._iFrameEndTime,
		isDead = self._isDead,
	}
end

--[[
	Gets the player this resource belongs to
	@return Player
]]
function CombatResource:GetPlayer(): Player
	return self._player
end

--[[
	Destroys the combat resource and cleans up events
]]
function CombatResource:Destroy()
	self.OnHealthChanged:destroy()
	self.OnMaxHealthChanged:destroy()
	self.OnShieldChanged:destroy()
	self.OnOvershieldChanged:destroy()
	self.OnUltimateChanged:destroy()
	self.OnUltimateFull:destroy()
	self.OnUltimateSpent:destroy()
	self.OnDamaged:destroy()
	self.OnHealed:destroy()
	self.OnDeath:destroy()
	self.OnInvulnerabilityChanged:destroy()
end

return CombatResource
