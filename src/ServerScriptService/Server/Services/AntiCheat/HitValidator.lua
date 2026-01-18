local HitValidator = {}

HitValidator.PlayerHistory = {} -- Stores position history for lag compensation
HitValidator.LastFireTimes = {} -- Rate limiting per player

local MAX_SHOT_DISTANCE_ERROR = 10 -- studs tolerance for hit validation
local POSITION_HISTORY_DURATION = 1.0 -- seconds to keep history

function HitValidator:Init()
	game.Players.PlayerRemoving:Connect(function(player)
		self.PlayerHistory[player] = nil
		self.LastFireTimes[player] = nil
	end)

	print("[HitValidator] Initialized")
end

function HitValidator:StorePosition(player, position, timestamp)
	if not self.PlayerHistory[player] then
		self.PlayerHistory[player] = {}
	end

	table.insert(self.PlayerHistory[player], {
		Position = position,
		Timestamp = timestamp,
	})

	-- Remove old history entries
	local cutoff = timestamp - POSITION_HISTORY_DURATION
	while #self.PlayerHistory[player] > 0 and self.PlayerHistory[player][1].Timestamp < cutoff do
		table.remove(self.PlayerHistory[player], 1)
	end
end

function HitValidator:ValidateHit(shooter, shotData, weaponConfig)
	-- 1. Rate limiting check
	local now = os.clock()
	local lastFire = self.LastFireTimes[shooter] or 0
	local fireInterval = 60 / (weaponConfig.fireRate or 600)

	if now - lastFire < fireInterval * 0.9 then -- 10% tolerance
		return false, "FireRateTooFast"
	end

	self.LastFireTimes[shooter] = now

	-- 2. Range check
	if not weaponConfig.range then
		return false, "NoWeaponRange"
	end

	local distance = (shotData.hitPosition - shotData.origin).Magnitude
	if distance > weaponConfig.range + 50 then -- +50 studs tolerance
		return false, "RangeTooFar"
	end

	-- 3. Bullet drop validation (if applicable)
	if weaponConfig.projectileSpeed and weaponConfig.bulletDrop then
		local travelTime = distance / weaponConfig.projectileSpeed
		local gravity = weaponConfig.gravity or workspace.Gravity
		local expectedDrop = 0.5 * gravity * (travelTime ^ 2)

		-- Verify drop amount is reasonable
		local verticalDiff = shotData.origin.Y - shotData.hitPosition.Y
		local dropTolerance = 20 -- studs

		if math.abs(verticalDiff - expectedDrop) > dropTolerance then
			return false, "BulletDropMismatch"
		end
	end

	-- 4. Target position validation (lag compensation)
	if shotData.hitPlayer then
		local targetHistory = self.PlayerHistory[shotData.hitPlayer]
		if not targetHistory or #targetHistory == 0 then
			-- No history yet, allow hit (player just spawned)
			return true
		end

		-- Find target position at shooter's timestamp (lag compensation)
		local targetPos = self:GetHistoricalPosition(shotData.hitPlayer, shotData.timestamp)

		if targetPos then
			local distanceToHit = (shotData.hitPosition - targetPos).Magnitude
			if distanceToHit > MAX_SHOT_DISTANCE_ERROR then
				return false, "TargetPositionMismatch"
			end
		end
	end

	return true
end

function HitValidator:GetHistoricalPosition(player, timestamp)
	local history = self.PlayerHistory[player]
	if not history or #history == 0 then
		return nil
	end

	-- Find closest position to timestamp
	local closest = history[1]
	for _, entry in ipairs(history) do
		if math.abs(entry.Timestamp - timestamp) < math.abs(closest.Timestamp - timestamp) then
			closest = entry
		end
	end

	return closest.Position
end

function HitValidator:RecordViolation(player, violationType, value)
	warn(string.format(
		"[HitValidator] %s (%d) - %s violation: %.1f",
		player.Name,
		player.UserId,
		violationType,
		value or 0
	))

	-- Future: Track violations and kick repeat offenders
end

return HitValidator
