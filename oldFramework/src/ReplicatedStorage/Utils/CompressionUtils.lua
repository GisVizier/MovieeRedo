local CompressionUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplicationConfig = require(ReplicatedStorage.Configs.ReplicationConfig)
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local Sera = require(Locations.Modules.Utils.Sera)
local SeraSchemas = require(Locations.Modules.Utils.Sera.Schemas)

-- int16 range: -32768 to 32767 (used for rotation compression only)
local INT16_MIN = -32768
local INT16_MAX = 32767

-- =============================================================================
-- VECTOR3 FULL PRECISION (12 bytes as float32 array - no compression)
-- =============================================================================

function CompressionUtils:CompressPosition(position)
	-- No compression - return raw float32 values for maximum precision
	return { position.X, position.Y, position.Z }
end

function CompressionUtils:DecompressPosition(values)
	-- No decompression needed - already full precision
	return Vector3.new(values[1], values[2], values[3])
end

-- =============================================================================
-- VELOCITY FULL PRECISION (12 bytes as float32 array - no compression)
-- =============================================================================

function CompressionUtils:CompressVelocity(velocity)
	-- No compression - return raw float32 values for maximum precision
	return { velocity.X, velocity.Y, velocity.Z }
end

function CompressionUtils:DecompressVelocity(values)
	-- No decompression needed - already full precision
	return Vector3.new(values[1], values[2], values[3])
end

-- =============================================================================
-- ROTATION COMPRESSION (CFrame → Euler angles → int16 array)
-- =============================================================================

function CompressionUtils:CompressRotation(cframe)
	-- Extract only Y rotation (yaw) since characters only rotate horizontally
	-- This reduces from 3 angles to 1 angle (2 bytes instead of 6)
	local _, y, _ = cframe:ToEulerAnglesYXZ()

	-- Normalize to 0-1 range (0 to 2π)
	local normalizedY = (y + math.pi) / (2 * math.pi)

	-- Scale to int16 range
	local compressedY = math.floor(normalizedY * (INT16_MAX - INT16_MIN) + INT16_MIN)

	return compressedY
end

function CompressionUtils:DecompressRotation(compressed)
	-- Scale back from int16 to 0-1 range
	local normalizedY = (compressed - INT16_MIN) / (INT16_MAX - INT16_MIN)

	-- Scale back to radians (-π to π)
	local y = normalizedY * (2 * math.pi) - math.pi

	-- Create CFrame with only Y rotation (looking direction)
	return CFrame.Angles(0, y, 0)
end

-- =============================================================================
-- DELTA COMPRESSION (only send if changed significantly)
-- =============================================================================

function CompressionUtils:ShouldSendPositionUpdate(oldPosition, newPosition)
	if not oldPosition then
		return true -- Always send first update
	end

	local delta = (newPosition - oldPosition).Magnitude
	return delta >= ReplicationConfig.Compression.MinPositionDelta
end

function CompressionUtils:ShouldSendRotationUpdate(oldRotation, newRotation)
	if not oldRotation then
		return true -- Always send first update
	end

	-- Compare Y angles only
	local _, oldY, _ = oldRotation:ToEulerAnglesYXZ()
	local _, newY, _ = newRotation:ToEulerAnglesYXZ()

	local delta = math.abs(newY - oldY)
	return delta >= ReplicationConfig.Compression.MinRotationDelta
end

function CompressionUtils:ShouldSendVelocityUpdate(oldVelocity, newVelocity)
	if not oldVelocity then
		return true -- Always send first update
	end

	local delta = (newVelocity - oldVelocity).Magnitude
	return delta >= ReplicationConfig.Compression.MinVelocityDelta
end

-- =============================================================================
-- BUFFER SERIALIZATION (Now using Sera for type-safe, efficient serialization)
-- =============================================================================

-- New buffer layout using Sera (40 bytes total):
-- [0-11]  Position (Vector3 - 3x float32 = 12 bytes)
-- [12-15] Rotation Y (float32 = 4 bytes, radians)
-- [16-27] Velocity (Vector3 - 3x float32 = 12 bytes)
-- [28-35] Timestamp (float64 = 8 bytes)
-- [36]    IsGrounded (boolean = 1 byte)
-- [37]    AnimationId (uint8 = 1 byte)
-- [38-39] SequenceNumber (uint16 = 2 bytes) - packet ordering/loss detection
-- Total: 40 bytes (unified physics + animation state + sequencing!)
-- Previous: 36 bytes physics + ~15 bytes animation event = ~51 bytes total
-- Savings: 22% reduction + eliminates race conditions + packet loss detection!

function CompressionUtils:SerializeToBuffer(
	position,
	rotation,
	velocity,
	timestamp,
	isGrounded,
	animationId,
	rigTilt,
	sequenceNumber
)
	-- Extract Y rotation in radians from CFrame
	local _, rotationY, _ = rotation:ToEulerAnglesYXZ()

	-- Use Sera schema for serialization
	local buf, err = Sera.Serialize(SeraSchemas.CharacterState, {
		Position = position,
		Rotation = rotationY,
		Velocity = velocity,
		Timestamp = timestamp,
		IsGrounded = isGrounded,
		AnimationId = animationId,
		RigTilt = rigTilt or 0, -- Default to 0 if not provided
		SequenceNumber = sequenceNumber or 0, -- Default to 0 if not provided
	})

	if not buf then
		Log:Warn("COMPRESSION", "Serialization failed", { Error = err })
		return nil
	end

	return buf
end

function CompressionUtils:DeserializeFromBuffer(buf)
	-- Use Sera schema for deserialization
	local success, data = pcall(function()
		return Sera.Deserialize(SeraSchemas.CharacterState, buf)
	end)

	if not success then
		Log:Warn("COMPRESSION", "Deserialization failed", {
			Error = data,
			BufferLength = buffer.len(buf),
		})
		return nil
	end

	-- Convert rotation Y back to CFrame
	local rotation = CFrame.Angles(0, data.Rotation, 0)

	return {
		Position = data.Position,
		Rotation = rotation,
		Velocity = data.Velocity,
		Timestamp = data.Timestamp,
		IsGrounded = data.IsGrounded,
		AnimationId = data.AnimationId,
		RigTilt = data.RigTilt or 0,
		SequenceNumber = data.SequenceNumber or 0,
	}
end

-- =============================================================================
-- FULL STATE COMPRESSION (Uses secure buffer serialization)
-- =============================================================================

function CompressionUtils:CompressState(
	position,
	rotation,
	velocity,
	timestamp,
	isGrounded,
	animationId,
	rigTilt,
	sequenceNumber
)
	-- Use buffer serialization for security and type enforcement
	local buf = self:SerializeToBuffer(
		position,
		rotation,
		velocity,
		timestamp,
		isGrounded,
		animationId,
		rigTilt,
		sequenceNumber
	)
	-- Convert buffer to string for RemoteEvent transmission
	return buffer.tostring(buf)
end

function CompressionUtils:DecompressState(compressed)
	-- Convert string back to buffer
	if type(compressed) == "string" then
		compressed = buffer.fromstring(compressed)
	end
	-- Buffer deserialization with integrity check
	return self:DeserializeFromBuffer(compressed)
end

-- =============================================================================
-- DELTA STATE COMPRESSION (only include changed fields using Sera DeltaSerialize)
-- =============================================================================

function CompressionUtils:CompressDeltaState(
	position,
	rotation,
	velocity,
	timestamp,
	isGrounded,
	animationId,
	lastState
)
	-- Build delta table with only changed fields
	local delta = {}
	local hasChanges = false

	-- Always include timestamp
	delta.Timestamp = timestamp

	-- Only include fields that changed significantly
	if self:ShouldSendPositionUpdate(lastState and lastState.Position, position) then
		delta.Position = position
		hasChanges = true
	end

	if self:ShouldSendRotationUpdate(lastState and lastState.Rotation, rotation) then
		local _, rotationY, _ = rotation:ToEulerAnglesYXZ()
		delta.Rotation = rotationY
		hasChanges = true
	end

	if self:ShouldSendVelocityUpdate(lastState and lastState.Velocity, velocity) then
		delta.Velocity = velocity
		hasChanges = true
	end

	-- Always include IsGrounded if it changed (critical for animation sync)
	if not lastState or lastState.IsGrounded ~= isGrounded then
		delta.IsGrounded = isGrounded
		hasChanges = true
	end

	-- Always include AnimationId if it changed
	if not lastState or lastState.AnimationId ~= animationId then
		delta.AnimationId = animationId
		hasChanges = true
	end

	-- If nothing changed, return nil (no update needed)
	if not hasChanges then
		return nil
	end

	-- Use Sera's DeltaSerialize to encode only present fields
	local buf, err = Sera.DeltaSerialize(SeraSchemas.CharacterStateDelta, delta)

	if not buf then
		Log:Warn("COMPRESSION", "Delta serialization failed", { Error = err })
		return nil
	end

	return buffer.tostring(buf)
end

function CompressionUtils:DecompressDeltaState(deltaString, lastState)
	-- Convert string to buffer
	local deltaBuf = buffer.fromstring(deltaString)

	-- Use Sera's DeltaDeserialize
	local success, delta = pcall(function()
		return Sera.DeltaDeserialize(SeraSchemas.CharacterStateDelta, deltaBuf)
	end)

	if not success then
		Log:Warn("COMPRESSION", "Delta deserialization failed", { Error = delta })
		return nil
	end

	-- Merge delta with last known state
	local position = delta.Position or (lastState and lastState.Position) or Vector3.zero
	local rotation
	if delta.Rotation then
		rotation = CFrame.Angles(0, delta.Rotation, 0)
	else
		rotation = (lastState and lastState.Rotation) or CFrame.identity
	end
	local velocity = delta.Velocity or (lastState and lastState.Velocity) or Vector3.zero
	local isGrounded = delta.IsGrounded or (lastState and lastState.IsGrounded) or false
	local animationId = delta.AnimationId or (lastState and lastState.AnimationId) or 1 -- Default to IdleStanding

	return {
		Position = position,
		Rotation = rotation,
		Velocity = velocity,
		Timestamp = delta.Timestamp,
		IsGrounded = isGrounded,
		AnimationId = animationId,
	}
end

return CompressionUtils
