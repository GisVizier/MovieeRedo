--!strict

--[[
	SeraSchemas.lua

	Centralized schema definitions for all network data in StickTag.
	Each schema defines the exact structure and types for data sent over RemoteEvents.

	Usage:
		local Sera = require(Locations.Modules.Utils.Sera)
		local SeraSchemas = require(Locations.Modules.Utils.SeraSchemas)

		-- Serialize
		local buffer = Sera.Serialize(SeraSchemas.CharacterState, {
			Position = Vector3.new(0, 5, 0),
			Rotation = 1.57,
			Velocity = Vector3.new(10, 0, 5),
			Timestamp = os.clock()
		})

		-- Deserialize
		local data = Sera.Deserialize(SeraSchemas.CharacterState, buffer)
--]]

local Sera = require(script.Parent)

local SeraSchemas = {}

-- Character State Replication (60 Hz - Most frequent)
-- Replaces the current 48-byte buffer format in CompressionUtils
SeraSchemas.CharacterState = Sera.Schema({
	Position = Sera.Vector3, -- 12 bytes (3x float32)
	Rotation = Sera.Float32, -- 4 bytes (Y rotation in radians)
	Velocity = Sera.Vector3, -- 12 bytes (3x float32)
	Timestamp = Sera.Float64, -- 8 bytes
	IsGrounded = Sera.Boolean, -- 1 byte (prevents falling animation bug)
	AnimationId = Sera.Uint8, -- 1 byte (animation enum, replaces string events)
	RigTilt = Sera.Int8, -- 1 byte (rig tilt angle in degrees, -128 to 127)
	SequenceNumber = Sera.Uint16, -- 2 bytes (packet ordering/loss detection, wraps at 65535)
	-- Total: 41 bytes (unified physics + animation + rig rotation + sequencing!)
	-- Previous: 36 bytes physics + ~15 bytes animation event = ~51 bytes total
	-- Savings: 20% reduction + eliminates race conditions + packet loss detection!
})

-- Delta Character State (for stationary players)
-- Only sends fields that changed beyond threshold
SeraSchemas.CharacterStateDelta = Sera.Schema({
	Position = Sera.Vector3,
	Rotation = Sera.Float32,
	Velocity = Sera.Vector3,
	Timestamp = Sera.Float64,
	IsGrounded = Sera.Boolean,
	AnimationId = Sera.Uint8,
	RigTilt = Sera.Int8,
	SequenceNumber = Sera.Uint16,
})

-- Animation State Change
-- Currently sent as: (player, animationName: string, category: string, variantIndex: number)
SeraSchemas.AnimationState = Sera.Schema({
	PlayerUserId = Sera.Uint32, -- 4 bytes (player ID)
	AnimationName = Sera.String8, -- 1 + length bytes (max 255 char)
	Category = Sera.String8, -- 1 + length bytes
	VariantIndex = Sera.Uint8, -- 1 byte
	-- Typical: ~20 bytes (vs ~60+ bytes for raw strings)
})

-- Round Phase Change
-- Currently sent as: (phase: string, timerSeconds: number, mapName?: string)
SeraSchemas.RoundPhase = Sera.Schema({
	Phase = Sera.Uint8, -- 1 byte (enum: 0=Intermission, 1=RoundStart, 2=Round, 3=RoundEnd)
	TimerSeconds = Sera.Uint16, -- 2 bytes (max 65535 seconds = ~18 hours)
	MapId = Sera.Uint8, -- 1 byte (0 = no map)
	-- Total: 4 bytes (vs ~20+ bytes for strings)
})

-- Player State Change
-- Currently sent as: (player: Player, state: string)
SeraSchemas.PlayerState = Sera.Schema({
	PlayerUserId = Sera.Uint32, -- 4 bytes
	State = Sera.Uint8, -- 1 byte (enum: 0=Lobby, 1=AFK, 2=Runner, 3=Tagger, 4=Ghost, 5=Spectator)
	-- Total: 5 bytes
})

-- NPC State Change
SeraSchemas.NPCState = Sera.Schema({
	NPCName = Sera.String8, -- 1 + length bytes
	State = Sera.Uint8, -- 1 byte
})

-- Crouch State
-- Currently sent as: (isCrouching: boolean)
SeraSchemas.CrouchState = Sera.Schema({
	PlayerUserId = Sera.Uint32, -- 4 bytes
	IsCrouching = Sera.Boolean, -- 1 byte
	-- Total: 5 bytes
})

-- Sound Request
-- Currently sent as: (soundName: string, position?: Vector3, volume?: number)
SeraSchemas.SoundRequest = Sera.Schema({
	SoundName = Sera.String8, -- 1 + length bytes
	Position = Sera.Vector3, -- 12 bytes (optional in practice)
	Volume = Sera.Float32, -- 4 bytes
	-- Total: ~20 bytes
})

-- Tagger Selection
SeraSchemas.TaggerSelected = Sera.Schema({
	PlayerUserId = Sera.Uint32, -- 4 bytes
})

-- Player Tagged Event
SeraSchemas.PlayerTagged = Sera.Schema({
	TaggerUserId = Sera.Uint32, -- 4 bytes
	RunnerUserId = Sera.Uint32, -- 4 bytes
	Timestamp = Sera.Float64, -- 8 bytes
	-- Total: 16 bytes
})

-- Round Results
-- More complex - uses arrays
SeraSchemas.RoundResult = Sera.Schema({
	WinningTeam = Sera.Uint8, -- 1 byte (0=Runners, 1=Taggers, 2=Draw)
	RoundDuration = Sera.Uint16, -- 2 bytes (seconds)
	-- Note: Winner/Tagged player lists sent separately to avoid dynamic array complexity
})

-- Batch State Update Entry (for server broadcast)
SeraSchemas.StateBatchEntry = Sera.Schema({
	PlayerUserId = Sera.Uint32, -- 4 bytes
	StateBuffer = Sera.Buffer8, -- 1 + 36 bytes (contains CharacterState)
	-- Total: 41 bytes per player
})

-- Server Correction (for anti-cheat reconciliation)
SeraSchemas.ServerCorrection = Sera.Schema({
	Position = Sera.Vector3, -- 12 bytes
	Velocity = Sera.Vector3, -- 12 bytes
	Timestamp = Sera.Float64, -- 8 bytes
	-- Total: 32 bytes
})

-- AFK Toggle
SeraSchemas.AFKToggle = Sera.Schema({
	PlayerUserId = Sera.Uint32, -- 4 bytes
	IsAFK = Sera.Boolean, -- 1 byte
	-- Total: 5 bytes
})

-- =============================================================================
-- HIT DETECTION SYSTEM
-- =============================================================================

-- Hit Packet (Client -> Server)
-- Efficient buffer-based hit registration (~39 bytes vs ~200+ for tables)
SeraSchemas.HitPacket = Sera.Schema({
	Timestamp = Sera.Float64,      -- 8 bytes (needs precision for GetServerTimeNow)
	Origin = Sera.Vector3,         -- 12 bytes (shooter position)
	HitPosition = Sera.Vector3,    -- 12 bytes (world position of hit)
	TargetUserId = Sera.Uint32,    -- 4 bytes (0 = no player target / dummy)
	HitPart = Sera.Uint8,          -- 1 byte (enum: None/Body/Head/Limb)
	WeaponId = Sera.Uint8,         -- 1 byte (weapon enum)
	TargetStance = Sera.Uint8,     -- 1 byte (stance client observed: Standing/Crouched/Sliding)
	-- Total: 35 bytes
})

-- Shotgun Hit Packet (Client -> Server)
-- For multi-pellet weapons, includes pellet count
SeraSchemas.ShotgunHitPacket = Sera.Schema({
	Timestamp = Sera.Float64,      -- 8 bytes (needs precision for GetServerTimeNow)
	Origin = Sera.Vector3,         -- 12 bytes
	HitPosition = Sera.Vector3,    -- 12 bytes (primary/first hit position)
	TargetUserId = Sera.Uint32,    -- 4 bytes
	HitPart = Sera.Uint8,          -- 1 byte
	WeaponId = Sera.Uint8,         -- 1 byte
	TargetStance = Sera.Uint8,     -- 1 byte
	PelletHits = Sera.Uint8,       -- 1 byte (how many pellets hit this target)
	HeadshotPellets = Sera.Uint8,  -- 1 byte (how many were headshots)
	-- Total: 37 bytes
})

-- =============================================================================
-- PROJECTILE SYSTEM
-- =============================================================================

-- Projectile Spawned Packet (Client -> Server -> Others)
-- Sent when a projectile is fired, used for visual replication
SeraSchemas.ProjectileSpawnPacket = Sera.Schema({
	FireTimestamp = Sera.Float64,  -- 8 bytes (when projectile was fired)
	Origin = Sera.Vector3,         -- 12 bytes (fire position)
	DirectionX = Sera.Float32,     -- 4 bytes (direction X component)
	DirectionY = Sera.Float32,     -- 4 bytes (direction Y component)
	DirectionZ = Sera.Float32,     -- 4 bytes (direction Z component)
	Speed = Sera.Float32,          -- 4 bytes (initial speed)
	ChargePercent = Sera.Uint8,    -- 1 byte (0-255 = 0-100% charge)
	WeaponId = Sera.Uint8,         -- 1 byte (weapon enum)
	ProjectileId = Sera.Uint32,    -- 4 bytes (unique ID for this projectile)
	SpreadSeed = Sera.Uint16,      -- 2 bytes (random seed for server verification)
	-- Total: 44 bytes
})

-- Projectile Hit Packet (Client -> Server)
-- Sent when a projectile hits something
SeraSchemas.ProjectileHitPacket = Sera.Schema({
	FireTimestamp = Sera.Float64,   -- 8 bytes (original fire time)
	ImpactTimestamp = Sera.Float64, -- 8 bytes (when projectile hit)
	Origin = Sera.Vector3,          -- 12 bytes (fire position)
	HitPosition = Sera.Vector3,     -- 12 bytes (impact position)
	TargetUserId = Sera.Uint32,     -- 4 bytes (target player, 0 = environment)
	HitPart = Sera.Uint8,           -- 1 byte (enum: None/Body/Head/Limb)
	WeaponId = Sera.Uint8,          -- 1 byte (weapon enum)
	ProjectileId = Sera.Uint32,     -- 4 bytes (matching spawn ID)
	TargetStance = Sera.Uint8,      -- 1 byte (stance at impact)
	PierceCount = Sera.Uint8,       -- 1 byte (how many targets already hit)
	BounceCount = Sera.Uint8,       -- 1 byte (how many times bounced)
	-- Total: 53 bytes
})

-- Projectile Replicate Packet (Server -> Clients)
-- Sent to other clients to spawn visual projectile
SeraSchemas.ProjectileReplicatePacket = Sera.Schema({
	ShooterUserId = Sera.Uint32,   -- 4 bytes (who fired)
	Origin = Sera.Vector3,         -- 12 bytes (fire position)
	DirectionX = Sera.Float32,     -- 4 bytes
	DirectionY = Sera.Float32,     -- 4 bytes
	DirectionZ = Sera.Float32,     -- 4 bytes
	Speed = Sera.Float32,          -- 4 bytes
	ProjectileId = Sera.Uint32,    -- 4 bytes
	WeaponId = Sera.Uint8,         -- 1 byte
	ChargePercent = Sera.Uint8,    -- 1 byte
	-- Total: 38 bytes
})

-- Projectile Destroyed Packet (Server -> Clients)
-- Sent when projectile should be removed
SeraSchemas.ProjectileDestroyedPacket = Sera.Schema({
	ProjectileId = Sera.Uint32,    -- 4 bytes
	HitPosition = Sera.Vector3,    -- 12 bytes (for impact VFX)
	DestroyReason = Sera.Uint8,    -- 1 byte (enum: Timeout/Hit/OutOfRange)
	-- Total: 17 bytes
})

--[[
	Enum mappings for efficient serialization
	These replace string-based enums with uint8 values
--]]

SeraSchemas.Enums = {
	-- Round Phases
	Phase = {
		Intermission = 0,
		RoundStart = 1,
		Round = 2,
		RoundEnd = 3,
	},

	-- Player States
	PlayerState = {
		Lobby = 0,
		AFK = 1,
		Runner = 2,
		Tagger = 3,
		Ghost = 4,
		Spectator = 5,
	},

	-- Winning Teams
	WinningTeam = {
		Runners = 0,
		Taggers = 1,
		Draw = 2,
	},

	-- Hit Part (for hit detection)
	HitPart = {
		None = 0,
		Body = 1,
		Head = 2,
		Limb = 3,
	},

	-- Character Stance (for hitbox selection)
	Stance = {
		Standing = 0,
		Crouched = 1,
		Sliding = 2,
	},

	-- Weapon IDs (map weapon names to bytes)
	WeaponId = {
		Unknown = 0,
		Sniper = 1,
		Shotgun = 2,
		AssaultRifle = 3,
		Revolver = 4,
		Knife = 5,
		ExecutionerBlade = 6,
		Bow = 7,
		RocketLauncher = 8,
		Crossbow = 9,
	},

	-- Projectile Destroy Reasons
	ProjectileDestroyReason = {
		Timeout = 0,        -- Exceeded lifetime
		HitTarget = 1,      -- Hit a player
		HitEnvironment = 2, -- Hit world geometry
		OutOfRange = 3,     -- Exceeded max range
		Cancelled = 4,      -- Manually cancelled
	},

	-- Spread Modes
	SpreadMode = {
		None = 0,    -- Perfect accuracy
		Cone = 1,    -- Random within cone
		Pattern = 2, -- Fixed pattern (shotgun)
	},
}

-- Reverse lookup tables for deserialization
SeraSchemas.EnumNames = {
	Phase = {},
	PlayerState = {},
	WinningTeam = {},
	HitPart = {},
	Stance = {},
	WeaponId = {},
	ProjectileDestroyReason = {},
	SpreadMode = {},
}

-- Build reverse lookups
for enumName, enumTable in pairs(SeraSchemas.Enums) do
	for name, value in pairs(enumTable) do
		SeraSchemas.EnumNames[enumName][value] = name
	end
end

return SeraSchemas
