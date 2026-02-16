local CompressionUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ReplicationConfig = require(Locations.Global:WaitForChild("Replication"))
local Sera = require(Locations.Shared.Util:WaitForChild("Sera"))
local SeraSchemas = require(Locations.Shared.Util:WaitForChild("Sera"):WaitForChild("Schemas"))

local INT16_MIN = -32768
local INT16_MAX = 32767
local AIM_PITCH_MIN_DEGREES = -90
local AIM_PITCH_MAX_DEGREES = 90
local AIM_PITCH_SCALE = 100

function CompressionUtils:CompressPosition(position)
	return { position.X, position.Y, position.Z }
end

function CompressionUtils:DecompressPosition(values)
	return Vector3.new(values[1], values[2], values[3])
end

function CompressionUtils:CompressVelocity(velocity)
	return { velocity.X, velocity.Y, velocity.Z }
end

function CompressionUtils:DecompressVelocity(values)
	return Vector3.new(values[1], values[2], values[3])
end

function CompressionUtils:CompressRotation(cframe)
	local _, y, _ = cframe:ToEulerAnglesYXZ()
	local normalizedY = (y + math.pi) / (2 * math.pi)
	local compressedY = math.floor(normalizedY * (INT16_MAX - INT16_MIN) + INT16_MIN)
	return compressedY
end

function CompressionUtils:DecompressRotation(compressed)
	local normalizedY = (compressed - INT16_MIN) / (INT16_MAX - INT16_MIN)
	local y = normalizedY * (2 * math.pi) - math.pi
	return CFrame.Angles(0, y, 0)
end

function CompressionUtils:ShouldSendPositionUpdate(oldPosition, newPosition)
	if not oldPosition then
		return true
	end
	local delta = (newPosition - oldPosition).Magnitude
	return delta >= ReplicationConfig.Compression.MinPositionDelta
end

function CompressionUtils:ShouldSendRotationUpdate(oldRotation, newRotation)
	if not oldRotation then
		return true
	end
	local _, oldY, _ = oldRotation:ToEulerAnglesYXZ()
	local _, newY, _ = newRotation:ToEulerAnglesYXZ()
	local delta = math.abs(newY - oldY)
	return delta >= ReplicationConfig.Compression.MinRotationDelta
end

function CompressionUtils:ShouldSendVelocityUpdate(oldVelocity, newVelocity)
	if not oldVelocity then
		return true
	end
	local delta = (newVelocity - oldVelocity).Magnitude
	return delta >= ReplicationConfig.Compression.MinVelocityDelta
end

function CompressionUtils:ShouldSendAimPitchUpdate(oldAimPitch, newAimPitch)
	if oldAimPitch == nil then
		return true
	end
	local delta = math.abs((newAimPitch or 0) - oldAimPitch)
	local minDelta = ReplicationConfig.Compression.MinAimPitchDelta or 0.5
	return delta >= minDelta
end

local function quantizeAimPitch(aimPitch)
	local clamped = math.clamp(tonumber(aimPitch) or 0, AIM_PITCH_MIN_DEGREES, AIM_PITCH_MAX_DEGREES)
	if clamped >= 0 then
		return math.floor(clamped * AIM_PITCH_SCALE + 0.5)
	end
	return math.ceil(clamped * AIM_PITCH_SCALE - 0.5)
end

local function dequantizeAimPitch(quantizedPitch)
	return (tonumber(quantizedPitch) or 0) / AIM_PITCH_SCALE
end

function CompressionUtils:SerializeToBuffer(
	position,
	rotation,
	velocity,
	timestamp,
	isGrounded,
	animationId,
	rigTilt,
	sequenceNumber,
	aimPitch
)
	local _, rotationY, _ = rotation:ToEulerAnglesYXZ()

	local buf, err = Sera.Serialize(SeraSchemas.CharacterState, {
		Position = position,
		Rotation = rotationY,
		AimPitch = quantizeAimPitch(aimPitch),
		Velocity = velocity,
		Timestamp = timestamp,
		IsGrounded = isGrounded,
		AnimationId = animationId,
		RigTilt = rigTilt or 0,
		SequenceNumber = sequenceNumber or 0,
	})

	if not buf then
		return nil
	end

	return buf
end

function CompressionUtils:DeserializeFromBuffer(buf)
	local success, data = pcall(function()
		return Sera.Deserialize(SeraSchemas.CharacterState, buf)
	end)

	if not success then
		return nil
	end

	local rotation = CFrame.Angles(0, data.Rotation, 0)

	return {
		Position = data.Position,
		Rotation = rotation,
		AimPitch = dequantizeAimPitch(data.AimPitch),
		Velocity = data.Velocity,
		Timestamp = data.Timestamp,
		IsGrounded = data.IsGrounded,
		AnimationId = data.AnimationId,
		RigTilt = data.RigTilt or 0,
		SequenceNumber = data.SequenceNumber or 0,
	}
end

function CompressionUtils:CompressState(
	position,
	rotation,
	velocity,
	timestamp,
	isGrounded,
	animationId,
	rigTilt,
	sequenceNumber,
	aimPitch
)
	local buf = self:SerializeToBuffer(
		position,
		rotation,
		velocity,
		timestamp,
		isGrounded,
		animationId,
		rigTilt,
		sequenceNumber,
		aimPitch
	)

	return buf and buffer.tostring(buf) or nil
end

function CompressionUtils:DecompressState(compressed)
	if type(compressed) == "string" then
		compressed = buffer.fromstring(compressed)
	end
	return self:DeserializeFromBuffer(compressed)
end

function CompressionUtils:CompressDeltaState(
	position,
	rotation,
	aimPitch,
	velocity,
	timestamp,
	isGrounded,
	animationId,
	lastState
)
	local delta = {}
	local hasChanges = false

	delta.Timestamp = timestamp

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

	if self:ShouldSendAimPitchUpdate(lastState and lastState.AimPitch, aimPitch) then
		delta.AimPitch = quantizeAimPitch(aimPitch)
		hasChanges = true
	end

	if not lastState or lastState.IsGrounded ~= isGrounded then
		delta.IsGrounded = isGrounded
		hasChanges = true
	end

	if not lastState or lastState.AnimationId ~= animationId then
		delta.AnimationId = animationId
		hasChanges = true
	end

	if not hasChanges then
		return nil
	end

	local buf, err = Sera.DeltaSerialize(SeraSchemas.CharacterStateDelta, delta)
	if not buf then
		return nil
	end

	return buffer.tostring(buf)
end

function CompressionUtils:DecompressDeltaState(deltaString, lastState)
	local deltaBuf = buffer.fromstring(deltaString)

	local success, delta = pcall(function()
		return Sera.DeltaDeserialize(SeraSchemas.CharacterStateDelta, deltaBuf)
	end)

	if not success then
		return nil
	end

	local position = delta.Position or (lastState and lastState.Position) or Vector3.zero
	local rotation
	if delta.Rotation then
		rotation = CFrame.Angles(0, delta.Rotation, 0)
	else
		rotation = (lastState and lastState.Rotation) or CFrame.identity
	end
	local velocity = delta.Velocity or (lastState and lastState.Velocity) or Vector3.zero
	local aimPitch
	if delta.AimPitch ~= nil then
		aimPitch = dequantizeAimPitch(delta.AimPitch)
	else
		aimPitch = (lastState and lastState.AimPitch) or 0
	end
	local isGrounded = delta.IsGrounded or (lastState and lastState.IsGrounded) or false
	local animationId = delta.AnimationId or (lastState and lastState.AnimationId) or 1

	return {
		Position = position,
		Rotation = rotation,
		AimPitch = aimPitch,
		Velocity = velocity,
		Timestamp = delta.Timestamp,
		IsGrounded = isGrounded,
		AnimationId = animationId,
	}
end

function CompressionUtils:CompressViewmodelAction(playerUserId, weaponId, actionName, trackName, isActive, sequenceNumber, timestamp)
	local buf, err = Sera.Serialize(SeraSchemas.ViewmodelAction, {
		PlayerUserId = tonumber(playerUserId) or 0,
		WeaponId = tostring(weaponId or ""),
		ActionName = tostring(actionName or ""),
		TrackName = tostring(trackName or ""),
		IsActive = isActive == true,
		SequenceNumber = tonumber(sequenceNumber) or 0,
		Timestamp = tonumber(timestamp) or 0,
	})

	if not buf then
		return nil
	end

	return buffer.tostring(buf)
end

function CompressionUtils:DecompressViewmodelAction(compressed)
	if type(compressed) == "string" then
		compressed = buffer.fromstring(compressed)
	end

	if typeof(compressed) ~= "buffer" then
		return nil
	end

	local success, data = pcall(function()
		return Sera.Deserialize(SeraSchemas.ViewmodelAction, compressed)
	end)

	if not success then
		return nil
	end

	return data
end

return CompressionUtils
