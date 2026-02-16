local MovementValidator = {}
MovementValidator.Players = {}

-- Configuration
local MAX_SPEED = 120 -- Sliding max (80) + buffer for abilities/combos
local MAX_DISTANCE_PER_SEC = 150 -- Maximum studs per second (accounts for boosts)
local MAX_AIRBORNE_TIME = 3.0 -- Maximum time airborne (generous for slide jumps)
local MAX_AIRBORNE_UPWARD_VEL = 20 -- Maximum upward velocity while airborne >1s

function MovementValidator:Init()
	game.Players.PlayerRemoving:Connect(function(player)
		self.Players[player] = nil
	end)
	
end

function MovementValidator:Validate(player, state, deltaTime)
	local data = self.Players[player]
	
	-- Initialize on first state
	if not data then
		self.Players[player] = {
			LastPos = state.Position,
			AirborneTime = 0,
			Violations = 0,
		}
		return true
	end
	
	-- VALIDATION 1: Speed Check
	local speed = state.Velocity.Magnitude
	if speed > MAX_SPEED then
		self:RecordViolation(player, "Speed", speed)
		return false
	end
	
	-- VALIDATION 2: Position Delta (Teleport Detection)
	local distance = (state.Position - data.LastPos).Magnitude
	local maxAllowedDistance = MAX_DISTANCE_PER_SEC * math.max(deltaTime, 0.016)
	
	if distance > maxAllowedDistance then
		self:RecordViolation(player, "Teleport", distance)
		return false
	end
	
	-- VALIDATION 3: Flight Detection
	if state.IsGrounded then
		data.AirborneTime = 0
	else
		data.AirborneTime = data.AirborneTime + deltaTime
		
		-- Check if airborne too long
		if data.AirborneTime > MAX_AIRBORNE_TIME then
			self:RecordViolation(player, "Flight", data.AirborneTime)
			return false
		end
		
		-- Check if gaining height while airborne (fly hack)
		if data.AirborneTime > 1.0 and state.Velocity.Y > MAX_AIRBORNE_UPWARD_VEL then
			self:RecordViolation(player, "FlyUpward", state.Velocity.Y)
			return false
		end
	end
	
	-- Update last valid position
	data.LastPos = state.Position
	
	return true
end

function MovementValidator:RecordViolation(player, violationType, value)
	local data = self.Players[player]
	if not data then
		return
	end
	
	data.Violations = data.Violations + 1
	
	
	-- Kick after threshold
	if data.Violations >= 6 then
		player:Kick("Movement violations detected. Contact support if you believe this is an error.")
	end
end

function MovementValidator:GetPlayerStats(player)
	local data = self.Players[player]
	if not data then
		return nil
	end
	
	return {
		Violations = data.Violations,
		LastPosition = data.LastPos,
		AirborneTime = data.AirborneTime,
	}
end

return MovementValidator
