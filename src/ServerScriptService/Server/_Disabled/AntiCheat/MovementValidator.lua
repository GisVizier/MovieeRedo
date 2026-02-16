local MovementValidator = {}

MovementValidator.PlayerViolations = {} -- Track violations per player
MovementValidator.LastPositions = {} -- Store last validated positions

-- Anti-cheat thresholds
local MAX_SPEED_MULTIPLIER = 1.5 -- Allow 50% over max speed (for momentum, etc.)
local MAX_TELEPORT_DISTANCE = 50 -- Max studs moved in one frame (at 60fps)
local MAX_VERTICAL_VELOCITY = 200 -- Max studs/sec upward (prevents fly hacks)
local MAX_VIOLATIONS_BEFORE_KICK = 10 -- How many violations before kicking
local VIOLATION_DECAY_TIME = 30 -- Seconds before violations decay

function MovementValidator:Init()
	game.Players.PlayerRemoving:Connect(function(player)
		self.PlayerViolations[player] = nil
		self.LastPositions[player] = nil
	end)

end

function MovementValidator:Validate(player, state, deltaTime)
	if not state or not state.Position or not state.Velocity then
		return false
	end

	-- Initialize player data if needed
	if not self.PlayerViolations[player] then
		self.PlayerViolations[player] = {
			Count = 0,
			LastDecayTime = tick(),
		}
	end

	if not self.LastPositions[player] then
		self.LastPositions[player] = state.Position
		return true
	end

	local lastPos = self.LastPositions[player]
	local currentPos = state.Position

	-- Decay violations over time
	local now = tick()
	if now - self.PlayerViolations[player].LastDecayTime > VIOLATION_DECAY_TIME then
		self.PlayerViolations[player].Count = math.max(0, self.PlayerViolations[player].Count - 1)
		self.PlayerViolations[player].LastDecayTime = now
	end

	-- 1. Teleport detection
	local distance = (currentPos - lastPos).Magnitude
	local maxDistance = MAX_TELEPORT_DISTANCE * math.max(deltaTime, 0.016) -- Account for frame time
	
	if distance > maxDistance then
		self:RecordViolation(player, "Teleport", distance)
		return false
	end

	-- 2. Speed validation
	local velocity = state.Velocity
	local speed = velocity.Magnitude
	
	-- Get max expected speed (sprint speed + buffer)
	local maxSpeed = 24 * MAX_SPEED_MULTIPLIER -- Using sprint speed from Character config
	
	if speed > maxSpeed and deltaTime > 0 then
		self:RecordViolation(player, "SpeedHack", speed)
		return false
	end

	-- 3. Vertical velocity check (fly/noclip detection)
	local verticalVelocity = math.abs(velocity.Y)
	
	if verticalVelocity > MAX_VERTICAL_VELOCITY then
		self:RecordViolation(player, "FlyHack", verticalVelocity)
		return false
	end

	-- 4. Check if player is moving too far based on velocity
	if deltaTime > 0 then
		local expectedDistance = speed * deltaTime
		local actualDistance = distance
		local tolerance = 10 -- studs tolerance
		
		if actualDistance > expectedDistance + tolerance then
			self:RecordViolation(player, "PositionMismatch", actualDistance - expectedDistance)
			return false
		end
	end

	-- Valid state - update last position
	self.LastPositions[player] = currentPos
	return true
end

function MovementValidator:RecordViolation(player, violationType, value)
	local violations = self.PlayerViolations[player]
	violations.Count += 1


	-- Kick player if too many violations
	if violations.Count >= MAX_VIOLATIONS_BEFORE_KICK then
		player:Kick("Anti-cheat: Excessive movement violations detected")
	end
end

function MovementValidator:ResetPlayer(player)
	self.PlayerViolations[player] = {
		Count = 0,
		LastDecayTime = tick(),
	}
	self.LastPositions[player] = nil
end

return MovementValidator
