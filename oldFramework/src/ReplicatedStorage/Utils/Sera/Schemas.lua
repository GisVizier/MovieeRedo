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
}

-- Reverse lookup tables for deserialization
SeraSchemas.EnumNames = {
	Phase = {},
	PlayerState = {},
	WinningTeam = {},
}

-- Build reverse lookups
for enumName, enumTable in pairs(SeraSchemas.Enums) do
	for name, value in pairs(enumTable) do
		SeraSchemas.EnumNames[enumName][value] = name
	end
end

return SeraSchemas
