--[[
	ProjectilePhysics.lua
	
	Shared physics calculations for the projectile system.
	Used by both client (simulation) and server (validation).
	
	Provides CFrame-based trajectory calculation with:
	- Gravity
	- Drag (air resistance)
	- Velocity inheritance
	- Spread calculation
	
	Usage:
		local ProjectilePhysics = require(path.to.ProjectilePhysics)
		
		-- Create trajectory simulator
		local trajectory = ProjectilePhysics.new(config)
		
		-- Step simulation
		local newPos, newVel, hitResult = trajectory:Step(pos, vel, dt, rayParams)
		
		-- Get position at time
		local pos, vel = trajectory:GetStateAtTime(origin, direction, speed, time)
]]

local ProjectilePhysics = {}
ProjectilePhysics.__index = ProjectilePhysics

-- =============================================================================
-- CONSTANTS
-- =============================================================================

local DEFAULT_GRAVITY = 196.2 -- Roblox default workspace.Gravity
local DEFAULT_DRAG = 0
local DEFAULT_LIFETIME = 5
local MIN_VELOCITY = 1 -- Minimum velocity before projectile is considered stopped

-- Spread pattern presets
ProjectilePhysics.SpreadPatterns = {
	-- 8-pellet circle pattern
	Circle8 = {
		{0, 0},           -- Center
		{0.05, 0},        -- Right
		{-0.05, 0},       -- Left
		{0, 0.05},        -- Up
		{0, -0.05},       -- Down
		{0.035, 0.035},   -- Top-right
		{-0.035, 0.035},  -- Top-left
		{0.035, -0.035},  -- Bottom-right
	},
	
	-- 6-pellet hexagon pattern
	Hexagon6 = {
		{0.05, 0},
		{0.025, 0.043},
		{-0.025, 0.043},
		{-0.05, 0},
		{-0.025, -0.043},
		{0.025, -0.043},
	},
	
	-- 3-pellet triangle pattern
	Triangle3 = {
		{0, 0.04},
		{-0.035, -0.02},
		{0.035, -0.02},
	},
	
	-- 5-pellet cross pattern
	Cross5 = {
		{0, 0},
		{0.04, 0},
		{-0.04, 0},
		{0, 0.04},
		{0, -0.04},
	},
}

-- =============================================================================
-- CONSTRUCTOR
-- =============================================================================

--[[
	Create a new ProjectilePhysics instance
	
	@param config table - Projectile configuration:
		{
			speed = number,           -- Initial velocity (studs/sec)
			gravity = number?,        -- Gravity strength (default: 196.2)
			drag = number?,           -- Air resistance (default: 0)
			lifetime = number?,       -- Max flight time (default: 5)
			inheritVelocity = number?, -- Shooter velocity transfer (0-1)
		}
	@return ProjectilePhysics
]]
function ProjectilePhysics.new(config)
	local self = setmetatable({}, ProjectilePhysics)
	
	self.Config = {
		speed = config.speed or 100,
		gravity = config.gravity or DEFAULT_GRAVITY,
		drag = config.drag or DEFAULT_DRAG,
		lifetime = config.lifetime or DEFAULT_LIFETIME,
		inheritVelocity = config.inheritVelocity or 0,
	}
	
	return self
end

-- =============================================================================
-- PHYSICS SIMULATION
-- =============================================================================

--[[
	Step the physics simulation forward
	
	@param position Vector3 - Current position
	@param velocity Vector3 - Current velocity
	@param dt number - Delta time (seconds)
	@param raycastParams RaycastParams? - Optional raycast parameters for collision
	@return Vector3, Vector3, RaycastResult? - New position, new velocity, hit result (if any)
]]
function ProjectilePhysics:Step(position, velocity, dt, raycastParams)
	local config = self.Config
	
	-- Apply drag (air resistance)
	if config.drag > 0 then
		velocity = velocity * (1 - config.drag * dt)
	end
	
	-- Apply gravity
	local gravity = Vector3.new(0, -config.gravity, 0)
	velocity = velocity + gravity * dt
	
	-- Calculate movement
	local movement = velocity * dt
	local nextPosition = position + movement
	
	-- Check for collision if raycast params provided
	local hitResult = nil
	if raycastParams then
		hitResult = workspace:Raycast(position, movement, raycastParams)
		if hitResult then
			-- Stop at hit position
			nextPosition = hitResult.Position
		end
	end
	
	return nextPosition, velocity, hitResult
end

--[[
	Get the projectile state at a specific time
	
	@param origin Vector3 - Fire position
	@param direction Vector3 - Initial direction (normalized)
	@param speed number - Initial speed
	@param time number - Time since fire
	@return Vector3, Vector3 - Position and velocity at that time
]]
function ProjectilePhysics:GetStateAtTime(origin, direction, speed, time)
	local config = self.Config
	local gravity = config.gravity
	local drag = config.drag
	
	-- Initial velocity
	local v0 = direction.Unit * speed
	
	if drag == 0 then
		-- Simple kinematic equations (no drag)
		-- x(t) = x0 + v0*t + 0.5*a*t^2
		-- v(t) = v0 + a*t
		
		local gravityVec = Vector3.new(0, -gravity, 0)
		local position = origin + v0 * time + 0.5 * gravityVec * time * time
		local velocity = v0 + gravityVec * time
		
		return position, velocity
	else
		-- With drag, use iterative calculation
		-- This is less accurate but handles drag properly
		local position = origin
		local velocity = v0
		local dt = 1/60 -- 60 Hz simulation
		local elapsed = 0
		
		while elapsed < time do
			local stepDt = math.min(dt, time - elapsed)
			
			-- Apply drag
			velocity = velocity * (1 - drag * stepDt)
			
			-- Apply gravity
			velocity = velocity + Vector3.new(0, -gravity * stepDt, 0)
			
			-- Update position
			position = position + velocity * stepDt
			
			elapsed = elapsed + stepDt
		end
		
		return position, velocity
	end
end

--[[
	Simulate the full trajectory and return all points
	
	@param origin Vector3 - Fire position
	@param direction Vector3 - Initial direction (normalized)
	@param speed number - Initial speed
	@param maxTime number - Maximum simulation time
	@param raycastParams RaycastParams? - For collision detection
	@param stepSize number? - Time between points (default: 1/30)
	@return table, RaycastResult? - Array of positions, final hit result
]]
function ProjectilePhysics:Simulate(origin, direction, speed, maxTime, raycastParams, stepSize)
	stepSize = stepSize or (1/30)
	
	local points = {}
	local position = origin
	local velocity = direction.Unit * speed
	local time = 0
	local hitResult = nil
	
	table.insert(points, position)
	
	while time < maxTime do
		local dt = math.min(stepSize, maxTime - time)
		position, velocity, hitResult = self:Step(position, velocity, dt, raycastParams)
		
		table.insert(points, position)
		time = time + dt
		
		if hitResult then
			break
		end
		
		-- Check if projectile has effectively stopped
		if velocity.Magnitude < MIN_VELOCITY then
			break
		end
	end
	
	return points, hitResult
end

--[[
	Calculate expected flight time to reach a target position
	
	@param origin Vector3 - Fire position
	@param target Vector3 - Target position
	@param speed number - Projectile speed
	@return number - Estimated flight time in seconds
]]
function ProjectilePhysics:CalculateFlightTime(origin, target, speed)
	local config = self.Config
	local gravity = config.gravity
	
	-- Distance
	local delta = target - origin
	local horizontalDistance = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local verticalDelta = delta.Y
	
	-- Base time from horizontal distance
	local baseTime = horizontalDistance / speed
	
	-- Account for vertical component with gravity
	-- This is an approximation for ballistic trajectories
	if gravity > 0 and math.abs(verticalDelta) > 0.1 then
		-- More accurate calculation considering parabolic motion
		-- For shooting down: projectile arrives faster
		-- For shooting up: projectile takes longer
		local gravityEffect = 0
		if verticalDelta < 0 then
			-- Shooting down, gravity helps
			gravityEffect = -0.5 * math.sqrt(2 * math.abs(verticalDelta) / gravity)
		else
			-- Shooting up, gravity slows
			gravityEffect = 0.5 * math.sqrt(2 * verticalDelta / gravity)
		end
		
		baseTime = baseTime + gravityEffect
	end
	
	return math.max(baseTime, 0.01) -- Minimum 10ms
end

--[[
	Predict where a projectile will hit
	
	@param origin Vector3 - Fire position
	@param direction Vector3 - Initial direction
	@param speed number - Initial speed
	@param raycastParams RaycastParams - For collision detection
	@param maxTime number? - Max simulation time (default: lifetime)
	@return table? - Hit prediction { position, normal, distance, flightTime, instance }
]]
function ProjectilePhysics:PredictImpact(origin, direction, speed, raycastParams, maxTime)
	maxTime = maxTime or self.Config.lifetime
	
	local position = origin
	local velocity = direction.Unit * speed
	local time = 0
	local dt = 1/60
	
	while time < maxTime do
		local nextPos, nextVel, hitResult = self:Step(position, velocity, dt, raycastParams)
		time = time + dt
		
		if hitResult then
			return {
				position = hitResult.Position,
				normal = hitResult.Normal,
				distance = (hitResult.Position - origin).Magnitude,
				flightTime = time,
				instance = hitResult.Instance,
			}
		end
		
		position = nextPos
		velocity = nextVel
		
		-- Stop if velocity is too low
		if velocity.Magnitude < MIN_VELOCITY then
			break
		end
	end
	
	-- No hit, return final position
	return {
		position = position,
		normal = Vector3.yAxis,
		distance = (position - origin).Magnitude,
		flightTime = time,
		instance = nil,
	}
end

-- =============================================================================
-- SPREAD CALCULATION
-- =============================================================================

--[[
	Apply spread to a direction
	
	@param direction Vector3 - Base aim direction (normalized)
	@param spreadAngle number - Spread angle in radians
	@param seed number? - Optional random seed for deterministic spread
	@return Vector3 - Direction with spread applied
]]
function ProjectilePhysics:ApplySpread(direction, spreadAngle, seed)
	if spreadAngle <= 0 then
		return direction.Unit
	end
	
	-- Use seed for deterministic randomness if provided
	local random = seed and Random.new(seed) or Random.new()
	
	-- Random offset within cone
	local offsetX = (random:NextNumber() - 0.5) * 2 * spreadAngle
	local offsetY = (random:NextNumber() - 0.5) * 2 * spreadAngle
	
	-- Create rotation CFrame
	local spreadCFrame = CFrame.new(Vector3.zero, direction) * CFrame.Angles(offsetY, offsetX, 0)
	
	return spreadCFrame.LookVector
end

--[[
	Calculate spread angle based on weapon config and player state
	
	@param projectileConfig table - Projectile configuration
	@param spreadState table - Current spread state:
		{
			isMoving = boolean,
			isADS = boolean,
			inAir = boolean,
			isCrouching = boolean,
			isSliding = boolean,
			currentRecoil = number,
			velocitySpread = number,
		}
	@param crosshairConfig table? - Crosshair config for alignment
	@return number - Final spread angle in radians
]]
function ProjectilePhysics:CalculateSpreadAngle(projectileConfig, spreadState, crosshairConfig)
	local baseSpread = projectileConfig.baseSpread or 0
	
	-- Apply state modifiers
	local multiplier = 1.0
	
	if spreadState.isMoving then
		multiplier = multiplier * (projectileConfig.movementSpreadMult or 1.0)
	end
	
	if not spreadState.isADS then
		multiplier = multiplier * (projectileConfig.hipfireSpreadMult or 1.0)
	end
	
	if spreadState.inAir then
		multiplier = multiplier * (projectileConfig.airSpreadMult or 1.0)
	end
	
	if spreadState.isCrouching then
		multiplier = multiplier * (projectileConfig.crouchSpreadMult or 1.0)
	end
	
	if spreadState.isSliding then
		multiplier = multiplier * (projectileConfig.slideSpreadMult or 1.0)
	end
	
	-- Sprint penalty (stacks with movement)
	if spreadState.isSprinting then
		multiplier = multiplier * (projectileConfig.sprintSpreadMult or 1.3)
	end
	
	-- Base spread with multipliers
	local finalSpread = baseSpread * multiplier
	
	-- Add crosshair alignment if config provided
	if crosshairConfig and projectileConfig.crosshairSpreadScale then
		local crosshairSpread = (crosshairConfig.spreadX or 1) * 
			((spreadState.velocitySpread or 0) + (spreadState.currentRecoil or 0))
		finalSpread = finalSpread + (crosshairSpread * projectileConfig.crosshairSpreadScale)
	end
	
	return finalSpread
end

--[[
	Get pattern offsets for pattern spread mode
	
	@param patternName string|table - Pattern preset name or custom offsets
	@return table - Array of {x, y} offsets in radians
]]
function ProjectilePhysics:GetPatternOffsets(patternName)
	if type(patternName) == "table" then
		-- Custom pattern
		return patternName
	end
	
	-- Preset pattern
	return self.SpreadPatterns[patternName] or self.SpreadPatterns.Circle8
end

--[[
	Apply pattern spread to get multiple directions
	
	@param direction Vector3 - Base aim direction
	@param patternName string|table - Pattern name or custom offsets
	@param randomization number? - Random offset added to each pellet (radians)
	@return table - Array of directions for each pellet
]]
function ProjectilePhysics:ApplyPatternSpread(direction, patternName, randomization)
	local pattern = self:GetPatternOffsets(patternName)
	local directions = {}
	
	local baseCFrame = CFrame.new(Vector3.zero, direction)
	
	for i, offset in ipairs(pattern) do
		local offsetX = offset[1]
		local offsetY = offset[2]
		
		-- Add randomization if specified
		if randomization and randomization > 0 then
			offsetX = offsetX + (math.random() - 0.5) * 2 * randomization
			offsetY = offsetY + (math.random() - 0.5) * 2 * randomization
		end
		
		local spreadCFrame = baseCFrame * CFrame.Angles(offsetY, offsetX, 0)
		table.insert(directions, spreadCFrame.LookVector)
	end
	
	return directions
end

-- =============================================================================
-- CHARGE MECHANICS
-- =============================================================================

--[[
	Calculate charge multipliers based on hold time
	
	@param chargeConfig table - Charge configuration:
		{
			minTime = number,
			maxTime = number,
			minDamageMult = number,
			maxDamageMult = number,
			minSpeedMult = number,
			maxSpeedMult = number,
			minSpreadMult = number,
			maxSpreadMult = number,
		}
	@param holdTime number - How long the button was held
	@return table - { chargePercent, damageMult, speedMult, spreadMult }
]]
function ProjectilePhysics:CalculateChargeMultipliers(chargeConfig, holdTime)
	if not chargeConfig then
		return {
			chargePercent = 1,
			damageMult = 1,
			speedMult = 1,
			spreadMult = 1,
		}
	end
	
	local minTime = chargeConfig.minTime or 0
	local maxTime = chargeConfig.maxTime or 1
	
	-- Calculate charge percent (0-1)
	local chargePercent = math.clamp((holdTime - minTime) / (maxTime - minTime), 0, 1)
	
	-- Interpolate multipliers
	local function lerp(a, b, t)
		return a + (b - a) * t
	end
	
	return {
		chargePercent = chargePercent,
		damageMult = lerp(chargeConfig.minDamageMult or 1, chargeConfig.maxDamageMult or 1, chargePercent),
		speedMult = lerp(chargeConfig.minSpeedMult or 1, chargeConfig.maxSpeedMult or 1, chargePercent),
		spreadMult = lerp(chargeConfig.minSpreadMult or 1, chargeConfig.maxSpreadMult or 1, chargePercent),
	}
end

-- =============================================================================
-- REFLECTION (RICOCHET)
-- =============================================================================

--[[
	Calculate reflected velocity for ricochet
	
	@param velocity Vector3 - Incoming velocity
	@param normal Vector3 - Surface normal
	@param speedMultiplier number? - Speed retained after bounce (default: 0.9)
	@return Vector3 - Reflected velocity
]]
function ProjectilePhysics:CalculateReflection(velocity, normal, speedMultiplier)
	speedMultiplier = speedMultiplier or 0.9
	
	-- Reflection formula: v' = v - 2(v·n)n
	local reflected = velocity - 2 * velocity:Dot(normal) * normal
	
	-- Apply speed loss
	return reflected * speedMultiplier
end

-- =============================================================================
-- VALIDATION HELPERS
-- =============================================================================

--[[
	Validate that a claimed flight time is reasonable
	
	@param origin Vector3 - Fire position
	@param hitPosition Vector3 - Claimed hit position
	@param claimedTime number - Claimed flight time
	@param speed number - Projectile speed
	@param tolerance number? - Allowed variance (default: 0.15 = 15%)
	@return boolean, number - Is valid, expected time
]]
function ProjectilePhysics:ValidateFlightTime(origin, hitPosition, claimedTime, speed, tolerance)
	tolerance = tolerance or 0.15
	
	local expectedTime = self:CalculateFlightTime(origin, hitPosition, speed)
	local minTime = expectedTime * (1 - tolerance)
	local maxTime = expectedTime * (1 + tolerance)
	
	local isValid = claimedTime >= minTime and claimedTime <= maxTime
	return isValid, expectedTime
end

--[[
	Check if a trajectory is obstructed
	
	@param origin Vector3 - Fire position
	@param target Vector3 - Target position
	@param raycastParams RaycastParams - Collision parameters
	@param checkPoints number? - Number of points to check (default: 3)
	@return boolean, RaycastResult? - Is clear, obstruction hit (if any)
]]
function ProjectilePhysics:CheckTrajectoryObstruction(origin, target, raycastParams, checkPoints)
	checkPoints = checkPoints or 3
	
	-- Simple straight-line check for now
	-- For more accuracy, simulate the arc and check each segment
	
	local direction = target - origin
	local distance = direction.Magnitude
	
	-- Check along the path
	for i = 1, checkPoints do
		local t = i / (checkPoints + 1)
		local checkOrigin = origin + direction * ((i - 1) / checkPoints)
		local checkDirection = direction * (1 / checkPoints)
		
		local result = workspace:Raycast(checkOrigin, checkDirection, raycastParams)
		if result then
			-- Check if obstruction is before target
			local hitDistance = (result.Position - origin).Magnitude
			local targetDistance = (target - origin).Magnitude
			
			if hitDistance < targetDistance * 0.95 then -- 5% tolerance
				return false, result
			end
		end
	end
	
	return true, nil
end

return ProjectilePhysics
