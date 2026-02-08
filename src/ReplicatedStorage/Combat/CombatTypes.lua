--[[
	CombatTypes.lua
	Type definitions for the Combat Resource System
]]

local CombatTypes = {}

-- Damage application result
export type DamageResult = {
	healthDamage: number,
	shieldDamage: number,
	overshieldDamage: number,
	blocked: boolean,
	killed: boolean,
}

-- Damage options when applying damage
export type DamageOptions = {
	source: Player?,
	sourcePosition: Vector3?,
	hitPosition: Vector3?,
	isTrueDamage: boolean?,
	isHeadshot: boolean?,
	weaponId: string?,
	damageType: string?,
	skipIFrames: boolean?,
}

-- Heal options
export type HealOptions = {
	source: Player?,
	healType: string?,
}

-- Status effect settings passed to Apply
export type StatusEffectSettings = {
	duration: number,
	tickRate: number?,
	source: Player?,
	-- Effect-specific settings
	damagePerTick: number?,
	healPerTick: number?,
	slowPercent: number?,
	blockSprint: boolean?,
	friction: number?,
	breakOnDamage: boolean?,
	[string]: any,
}

-- Active status effect instance
export type ActiveStatusEffect = {
	effectId: string,
	settings: StatusEffectSettings,
	startTime: number,
	remainingDuration: number,
	lastTickTime: number,
}

-- Combat resource state
export type CombatState = {
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

-- Kill effect definition
export type KillEffectDefinition = {
	id: string,
	name: string,
	execute: (victim: Player, killer: Player?, weaponId: string?) -> (),
}

-- Status effect module definition
export type StatusEffectModule = {
	Id: string,
	DefaultTickRate: number?,
	OnApply: (self: StatusEffectModule, target: Player, settings: StatusEffectSettings) -> ()?,
	OnTick: (self: StatusEffectModule, target: Player, settings: StatusEffectSettings, deltaTime: number) -> boolean?,
	OnRemove: (self: StatusEffectModule, target: Player, settings: StatusEffectSettings, reason: string) -> ()?,
}

-- Combat state update payload for networking
export type CombatStatePayload = {
	health: number,
	maxHealth: number,
	shield: number,
	overshield: number,
	ultimate: number,
	maxUltimate: number,
	statusEffects: {[string]: number}, -- effectId -> remaining duration
}

-- Damage dealt payload for networking
export type DamageDealtPayload = {
	targetUserId: number,
	attackerUserId: number?,
	damage: number,
	isHeadshot: boolean,
	isCritical: boolean?,
	position: Vector3,
	sourcePosition: Vector3?,
	damageType: string?,
}

return CombatTypes
