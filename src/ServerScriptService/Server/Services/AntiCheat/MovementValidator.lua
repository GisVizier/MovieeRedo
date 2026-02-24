local MovementValidator = {}
MovementValidator.Players = {}

-- Thresholds
local MAX_SPEED = 120              -- studs/s; covers slide max (80) + ability buffer
local MAX_DISTANCE_PER_SEC = 150   -- studs/s; teleport detection ceiling
local MAX_AIRBORNE_TIME = 3.0      -- seconds; generous for slide-jump combos
local MAX_AIRBORNE_UPWARD_VEL = 20 -- studs/s upward after 1s airborne (fly-hack check)

-- Violation decay: 1 violation removed per this many seconds of clean play
local VIOLATION_DECAY_INTERVAL = 30
-- Kick threshold
local KICK_THRESHOLD = 6

function MovementValidator:Init()
	game.Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			-- Reset state on every character load (respawn, match transition, etc.)
			self:ResetPlayer(player)
			-- Give a grace window so the initial spawn position isn't flagged
			player:SetAttribute("AbilityBypassUntil", os.clock() + 5)
		end)
	end)
	game.Players.PlayerRemoving:Connect(function(player)
		self.Players[player] = nil
	end)
end

function MovementValidator:ResetPlayer(player)
	self.Players[player] = nil
end

function MovementValidator:Validate(player, state)
	local now = os.clock()
	local data = self.Players[player]

	-- First state: initialise and pass
	if not data then
		self.Players[player] = {
			LastPos = state.Position,
			LastValidateTime = now,
			AirborneTime = 0,
			Violations = 0,
			LastViolationDecayTime = now,
		}
		return true
	end

	-- Decay accumulated violations over time
	local decayElapsed = now - (data.LastViolationDecayTime or now)
	local decayAmount = math.floor(decayElapsed / VIOLATION_DECAY_INTERVAL)
	if decayAmount > 0 then
		data.Violations = math.max(0, data.Violations - decayAmount)
		data.LastViolationDecayTime = now
	end

	-- Ability bypass: set server-side via player attribute by KitService
	local bypassUntil = player:GetAttribute("AbilityBypassUntil") or 0
	if now < bypassUntil then
		-- Accept position during bypass but keep timestamps current
		data.LastPos = state.Position
		data.LastValidateTime = now
		data.AirborneTime = 0 -- don't accumulate airborne time during an ability
		return true
	end

	-- Use server-measured deltaTime so the client can't inflate it
	local deltaTime = math.clamp(now - (data.LastValidateTime or now), 0.016, 0.5)

	-- VALIDATION 1: Speed check
	local speed = state.Velocity.Magnitude
	if speed > MAX_SPEED then
		self:RecordViolation(player)
		data.LastValidateTime = now
		return false
	end

	-- VALIDATION 2: Position delta (teleport detection)
	local distance = (state.Position - data.LastPos).Magnitude
	local maxAllowedDistance = MAX_DISTANCE_PER_SEC * deltaTime
	if distance > maxAllowedDistance then
		self:RecordViolation(player)
		data.LastValidateTime = now
		return false
	end

	-- VALIDATION 3: Flight detection
	if state.IsGrounded then
		data.AirborneTime = 0
	else
		data.AirborneTime = data.AirborneTime + deltaTime
		if data.AirborneTime > MAX_AIRBORNE_TIME then
			self:RecordViolation(player)
			data.LastValidateTime = now
			return false
		end
		if data.AirborneTime > 1.0 and state.Velocity.Y > MAX_AIRBORNE_UPWARD_VEL then
			self:RecordViolation(player)
			data.LastValidateTime = now
			return false
		end
	end

	data.LastPos = state.Position
	data.LastValidateTime = now
	return true
end

function MovementValidator:RecordViolation(player)
	local data = self.Players[player]
	if not data then
		return
	end
	data.Violations = data.Violations + 1
	if data.Violations >= KICK_THRESHOLD then
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
