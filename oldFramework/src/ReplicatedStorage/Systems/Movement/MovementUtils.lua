local MovementUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Raycast result caching for performance
local raycastCache = {}
local CACHE_LIFETIME = 0.1 -- Cache results for 100ms
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local ConfigCache = require(Locations.Modules.Systems.Core.ConfigCache)
local Config = require(Locations.Modules.Config)

local GROUND_RAY_OFFSET = ConfigCache.GROUND_RAY_OFFSET
local GROUND_RAY_DISTANCE = ConfigCache.GROUND_RAY_DISTANCE
local MOVEMENT_FORCE = ConfigCache.MOVEMENT_FORCE
local WALK_SPEED = ConfigCache.WALK_SPEED
local JUMP_POWER = ConfigCache.JUMP_POWER
local AIR_CONTROL_MULTIPLIER = ConfigCache.AIR_CONTROL_MULTIPLIER

local FRICTION_MULTIPLIER = ConfigCache.FRICTION_MULTIPLIER
local DEADZONE_THRESHOLD = ConfigCache.DEADZONE_THRESHOLD
local MIN_SPEED_THRESHOLD = ConfigCache.MIN_SPEED_THRESHOLD
local VECTOR3_ZERO = ConfigCache.VECTOR3_ZERO

-- Raycast caching helper functions
local function generateCacheKey(origin, direction)
	-- Round positions to avoid tiny floating point differences
	local x = math.floor(origin.X * 100) / 100
	local y = math.floor(origin.Y * 100) / 100
	local z = math.floor(origin.Z * 100) / 100
	local dx = math.floor(direction.X * 100) / 100
	local dy = math.floor(direction.Y * 100) / 100
	local dz = math.floor(direction.Z * 100) / 100
	return string.format("%.2f,%.2f,%.2f:%.2f,%.2f,%.2f", x, y, z, dx, dy, dz)
end

local function getCachedRaycast(origin, direction, params)
	local key = generateCacheKey(origin, direction)
	local cached = raycastCache[key]
	local currentTime = tick()

	if cached and (currentTime - cached.timestamp) < CACHE_LIFETIME then
		return cached.result
	end

	-- Perform raycast and cache result
	local result = workspace:Raycast(origin, direction, params)
	raycastCache[key] = {
		result = result,
		timestamp = currentTime,
	}

	return result
end

local function cleanupCache()
	local currentTime = tick()
	for key, cached in pairs(raycastCache) do
		if (currentTime - cached.timestamp) >= CACHE_LIFETIME then
			raycastCache[key] = nil
		end
	end
end

function MovementUtils:SetupPhysicsConstraints(primaryPart)
	if not primaryPart then
		return nil, nil
	end

	local movementAttachment0 = primaryPart:FindFirstChild("MovementAttachment0")
	if not movementAttachment0 then
		movementAttachment0 = Instance.new("Attachment")
		movementAttachment0.Name = "MovementAttachment0"
		movementAttachment0.Parent = primaryPart
	end

	local movementAttachment1 = primaryPart:FindFirstChild("MovementAttachment1")
	if not movementAttachment1 then
		movementAttachment1 = Instance.new("Attachment")
		movementAttachment1.Name = "MovementAttachment1"
		movementAttachment1.Parent = primaryPart
	end

	-- NEW PHYSICS SYSTEM
	local vectorForce = primaryPart:FindFirstChild("VectorForce")
	if not vectorForce then
		vectorForce = Instance.new("VectorForce")
		vectorForce.Name = "VectorForce"
		vectorForce.Attachment0 = movementAttachment0
		vectorForce.Force = VECTOR3_ZERO
		vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
		vectorForce.ApplyAtCenterOfMass = true
		vectorForce.Parent = primaryPart
	end

	-- SMOOTH ROTATION - Always ensure correct settings to prevent flinging
	local alignOrientation = primaryPart:FindFirstChild("AlignOrientation")
	if not alignOrientation then
		alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "AlignOrientation"
		alignOrientation.Attachment0 = movementAttachment1
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.Parent = primaryPart
	end
	
	-- ALWAYS apply correct settings (fixes existing constraints with bad values)
	alignOrientation.CFrame = primaryPart.CFrame
	alignOrientation.MaxTorque = 100000 -- Reasonable torque to prevent flinging (NOT math.huge!)
	alignOrientation.Responsiveness = Config.Controls.Camera.Smoothness or 25 -- Lower for stability
	alignOrientation.RigidityEnabled = false -- Allow smooth interpolation via Responsiveness

	return alignOrientation, vectorForce
end

function MovementUtils:CheckGrounded(character, primaryPart, raycastParams)
	if not character or not primaryPart then
		return false
	end

	-- USE FEET FOR GROUND CHECK
	local feetPart = CharacterLocations:GetFeet(character) or primaryPart

	local feetPosition = feetPart.Position
	local feetSize = feetPart.Size
	local bottomOfFeet = feetPosition - Vector3.new(0, feetSize.Y / 2, 0)
	local baseRayOrigin = bottomOfFeet + Vector3.new(0, GROUND_RAY_OFFSET, 0)

	local rayDirection = Vector3.new(0, -GROUND_RAY_DISTANCE, 0)

	local params = raycastParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.RespectCanCollide = true -- Ignore nocollide objects
		params.CollisionGroup = "Players" -- Ignore other players
	end

	-- Calculate compact offsets for plus pattern (halfway to each edge)
	local offsetX = feetSize.X / 4 -- Quarter of width (halfway to edge)
	local offsetZ = feetSize.Z / 4 -- Quarter of depth (halfway to edge)

	-- Define 5 raycast origins in plus pattern
	local rayOrigins = {
		baseRayOrigin, -- Center (original)
		baseRayOrigin + Vector3.new(0, 0, offsetZ), -- North (forward)
		baseRayOrigin + Vector3.new(0, 0, -offsetZ), -- South (backward)
		baseRayOrigin + Vector3.new(offsetX, 0, 0), -- East (right)
		baseRayOrigin + Vector3.new(-offsetX, 0, 0), -- West (left)
	}

	-- Cast rays from all 5 positions - return true if ANY hit ground
	for _, rayOrigin in ipairs(rayOrigins) do
		local result = workspace:Raycast(rayOrigin, rayDirection, params)
		if result then
			return true
		end
	end

	return false
end

function MovementUtils:CheckGroundedWithSlope(character, primaryPart, raycastParams)
	if not character or not primaryPart then
		return false, nil, 0
	end

	-- USE FEET FOR GROUND CHECK
	local feetPart = CharacterLocations:GetFeet(character) or primaryPart

	local feetPosition = feetPart.Position
	local feetSize = feetPart.Size
	local bottomOfFeet = feetPosition - Vector3.new(0, feetSize.Y / 2, 0)
	local baseRayOrigin = bottomOfFeet + Vector3.new(0, GROUND_RAY_OFFSET, 0)

	local rayDirection = Vector3.new(0, -GROUND_RAY_DISTANCE, 0)

	local params = raycastParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.RespectCanCollide = true -- Ignore nocollide objects
		params.CollisionGroup = "Players" -- Ignore other players
	end

	-- Calculate compact offsets for plus pattern (halfway to each edge)
	local offsetX = feetSize.X / 4 -- Quarter of width (halfway to edge)
	local offsetZ = feetSize.Z / 4 -- Quarter of depth (halfway to edge)

	-- Define 5 raycast origins in plus pattern
	local rayOrigins = {
		baseRayOrigin, -- Center (original)
		baseRayOrigin + Vector3.new(0, 0, offsetZ), -- North (forward)
		baseRayOrigin + Vector3.new(0, 0, -offsetZ), -- South (backward)
		baseRayOrigin + Vector3.new(offsetX, 0, 0), -- East (right)
		baseRayOrigin + Vector3.new(-offsetX, 0, 0), -- West (left)
	}

	-- Cast rays from all 5 positions - return first valid result with slope info
	for _, rayOrigin in ipairs(rayOrigins) do
		local result = getCachedRaycast(rayOrigin, rayDirection, params)
		if result then
			-- Calculate slope angle
			local surfaceNormal = result.Normal
			local worldUp = Vector3.new(0, 1, 0)
			local slopeAngle = math.acos(math.clamp(surfaceNormal:Dot(worldUp), -1, 1))
			local slopeDegrees = math.deg(slopeAngle)

			return true, surfaceNormal, slopeDegrees
		end
	end

	-- Clean up old cache entries periodically
	cleanupCache()

	return false, nil, 0
end

function MovementUtils:IsSlopeWalkable(character, primaryPart, raycastParams)
	local isGrounded, _, slopeDegrees = self:CheckGroundedWithSlope(character, primaryPart, raycastParams)

	if not isGrounded then
		return false, 0
	end

	local maxWalkableAngle = Config.Gameplay.Character.MaxWalkableSlopeAngle
	local isWalkable = slopeDegrees <= maxWalkableAngle

	return isWalkable, slopeDegrees
end

function MovementUtils:CheckGroundedWithMaterial(character, primaryPart, raycastParams)
	if not character or not primaryPart then
		return false, nil
	end

	local feetPart = CharacterLocations:GetFeet(character) or primaryPart

	local feetPosition = feetPart.Position
	local feetSize = feetPart.Size
	local bottomOfFeet = feetPosition - Vector3.new(0, feetSize.Y / 2, 0)
	local baseRayOrigin = bottomOfFeet + Vector3.new(0, GROUND_RAY_OFFSET, 0)

	local rayDirection = Vector3.new(0, -GROUND_RAY_DISTANCE, 0)

	local params = raycastParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.RespectCanCollide = true
		params.CollisionGroup = "Players"
	end

	local result = workspace:Raycast(baseRayOrigin, rayDirection, params)
	if result then
		local materialName = tostring(result.Material)
		local materialParts = string.split(materialName, ".")
		local cleanMaterialName = materialParts[#materialParts] or "Plastic"
		return true, cleanMaterialName
	end

	return false, nil
end

-- NEW: Check if movement direction is going into a steep slope (returns true if blocked)
function MovementUtils:IsMovingIntoSteepSlope(character, primaryPart, raycastParams, movementDirection)
	if not character or not primaryPart or not raycastParams or not movementDirection then
		return false
	end

	-- Normalize movement direction (horizontal only)
	local horizontalDirection = Vector3.new(movementDirection.X, 0, movementDirection.Z)
	if horizontalDirection.Magnitude < 0.01 then
		return false -- No horizontal movement
	end
	horizontalDirection = horizontalDirection.Unit

	-- Get current ground normal
	local isGrounded, surfaceNormal, slopeDegrees = self:CheckGroundedWithSlope(character, primaryPart, raycastParams)
	if not isGrounded then
		return false -- Not grounded, allow movement
	end

	local maxWalkableAngle = Config.Gameplay.Character.MaxWalkableSlopeAngle
	if slopeDegrees <= maxWalkableAngle then
		return false -- Walkable slope, allow movement
	end

	-- We're on a steep slope - check if moving uphill
	-- Project surface normal onto horizontal plane to get slope direction
	local slopeDirection = Vector3.new(surfaceNormal.X, 0, surfaceNormal.Z)
	if slopeDirection.Magnitude < 0.01 then
		return false -- Vertical wall or flat, allow movement
	end
	slopeDirection = slopeDirection.Unit

	-- If moving opposite to slope direction (uphill), block movement
	-- Dot product: negative = moving uphill, positive = moving downhill
	local movementDot = horizontalDirection:Dot(slopeDirection)

	-- Block if moving uphill (against slope normal)
	return movementDot < -0.1 -- Small threshold to avoid edge cases
end

function MovementUtils:CheckWallCollision(primaryPart, movementDirection, raycastParams)
	if not primaryPart or not movementDirection then
		return false, nil
	end

	local jumpConfig = Config.Gameplay.Character.Jump
	if not jumpConfig or not jumpConfig.WallRaycast or not jumpConfig.WallRaycast.Enabled then
		return false, nil
	end

	local horizontalDirection = Vector3.new(movementDirection.X, 0, movementDirection.Z)
	if horizontalDirection.Magnitude < 0.01 then
		return false, nil
	end
	horizontalDirection = horizontalDirection.Unit

	local rayDistance = jumpConfig.WallRaycast.RayDistance
	local minWallAngle = jumpConfig.WallRaycast.MinWallAngle or 75

	local rayOrigin = primaryPart.Position
	local rayDirection = horizontalDirection * rayDistance

	local params = raycastParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { primaryPart.Parent }
		params.RespectCanCollide = true
	end

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if not result then
		return false, nil
	end

	local wallNormal = result.Normal
	local worldUp = Vector3.new(0, 1, 0)
	local wallAngle = math.deg(math.acos(math.clamp(math.abs(wallNormal:Dot(worldUp)), 0, 1)))

	if wallAngle < minWallAngle then
		return false, nil
	end

	return true, wallNormal
end

function MovementUtils:GetValidMovementDirection(primaryPart, desiredDirection, raycastParams, isGrounded)
	if not primaryPart or not desiredDirection then
		return desiredDirection
	end

	if isGrounded then
		return desiredDirection
	end

	local jumpConfig = Config.Gameplay.Character.Jump
	if not jumpConfig or not jumpConfig.WallRaycast or not jumpConfig.WallRaycast.Enabled then
		return desiredDirection
	end

	local isBlocked, wallNormal = self:CheckWallCollision(primaryPart, desiredDirection, raycastParams)
	if not isBlocked or not wallNormal then
		return desiredDirection
	end

	local horizontalNormal = Vector3.new(wallNormal.X, 0, wallNormal.Z)
	if horizontalNormal.Magnitude < 0.01 then
		return desiredDirection
	end
	horizontalNormal = horizontalNormal.Unit

	local horizontalDesired = Vector3.new(desiredDirection.X, 0, desiredDirection.Z)
	local desiredMagnitude = horizontalDesired.Magnitude
	if desiredMagnitude < 0.01 then
		return desiredDirection
	end

	local slideDirection = desiredDirection - (desiredDirection:Dot(horizontalNormal)) * horizontalNormal
	local slideMag = slideDirection.Magnitude
	if slideMag < 0.01 then
		return Vector3.new(0, desiredDirection.Y, 0)
	end

	local horizontalSlide = Vector3.new(slideDirection.X, 0, slideDirection.Z)
	if horizontalSlide.Magnitude > 0.01 then
		horizontalSlide = horizontalSlide.Unit * desiredMagnitude
	end

	return Vector3.new(horizontalSlide.X, desiredDirection.Y, horizontalSlide.Z)
end

-- WALL STOP: Check if trying to move into a wall using INPUT direction and stop completely
function MovementUtils:CheckWallStop(primaryPart, raycastParams, moveDirection)
	if not primaryPart then
		return false
	end

	local wallStopConfig = Config.Gameplay.Character.WallStop
	if not wallStopConfig or not wallStopConfig.Enabled then
		return false
	end

	-- Use INPUT direction (where player is TRYING to move), not velocity
	-- This ensures wall detection works even when velocity is 0 (already stopped)
	if not moveDirection then
		return false
	end
	
	local horizontalMoveDir = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	
	if horizontalMoveDir.Magnitude < 0.1 then
		return false -- Not trying to move
	end
	
	local moveDirectionUnit = horizontalMoveDir.Unit
	local rayOrigin = primaryPart.Position
	local rayDirection = moveDirectionUnit * wallStopConfig.RayDistance

	local params = raycastParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { primaryPart.Parent }
		params.RespectCanCollide = true
	end

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if not result then
		return false
	end

	-- Check if it's actually a wall (steep enough angle)
	local wallNormal = result.Normal
	local worldUp = Vector3.new(0, 1, 0)
	local wallAngle = math.deg(math.acos(math.clamp(math.abs(wallNormal:Dot(worldUp)), 0, 1)))
	
	local minWallAngle = wallStopConfig.MinWallAngle or 70
	if wallAngle < minWallAngle then
		return false -- Not steep enough, it's a slope
	end
	
	-- Check if we're actually moving TOWARD the wall (not parallel)
	-- Dot product: negative = moving toward wall, positive = moving away
	local horizontalNormal = Vector3.new(wallNormal.X, 0, wallNormal.Z)
	if horizontalNormal.Magnitude > 0.01 then
		horizontalNormal = horizontalNormal.Unit
		local movingTowardWall = moveDirectionUnit:Dot(horizontalNormal) < -0.3 -- More than 30% toward wall
		if not movingTowardWall then
			return false, nil -- Moving parallel or away from wall
		end
	end

	return true, wallNormal -- Wall detected in movement direction, trying to move into it
end

-- Explicit version that returns wall normal (for anti-stuck logic)
function MovementUtils:CheckWallStopWithNormal(primaryPart, raycastParams, moveDirection)
	return self:CheckWallStop(primaryPart, raycastParams, moveDirection)
end

-- STICKY GROUND: Apply downward force to keep player attached to surfaces when moving
-- Uses both straight-down and forward-down raycasts to catch upcoming slopes
function MovementUtils:ApplyStickyGround(primaryPart, raycastParams, lastJumpTime)
	if not primaryPart then
		return 0
	end

	local stickyConfig = Config.Gameplay.Character.StickyGround
	if not stickyConfig or not stickyConfig.Enabled then
		return 0
	end

	-- Don't apply sticky force shortly after jumping
	local currentTime = tick()
	local jumpBreakTime = stickyConfig.JumpBreakTime or 0.15
	if lastJumpTime and (currentTime - lastJumpTime) < jumpBreakTime then
		return 0
	end

	-- Check if moving fast enough horizontally
	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local horizontalSpeed = horizontalVelocity.Magnitude
	local minSpeed = stickyConfig.MinSpeed or 5
	local maxSpeed = stickyConfig.MaxSpeed or 9999 -- No max by default
	
	if horizontalSpeed < minSpeed then
		return 0, nil -- Not moving fast enough
	end
	
	-- Don't stick if moving TOO fast (high speed threshold)
	if horizontalSpeed > maxSpeed then
		return 0, nil -- Moving too fast, don't apply sticky
	end

	-- Don't apply if moving upward (jumping/launched)
	if currentVelocity.Y > 3 then
		return 0, nil
	end

	local params = raycastParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { primaryPart.Parent }
		params.RespectCanCollide = true
	end

	local rayOrigin = primaryPart.Position
	local rayDistance = stickyConfig.RayDistance or 8
	
	-- RAYCAST 1: Straight down
	local downRayDirection = Vector3.new(0, -rayDistance, 0)
	local downResult = workspace:Raycast(rayOrigin, downRayDirection, params)
	
	-- RAYCAST 2: Forward-down (predict upcoming surfaces)
	local forwardDownResult = nil
	if horizontalSpeed > 3 then
		local moveDir = horizontalVelocity.Unit
		local forwardDownDirection = (moveDir * rayDistance) + Vector3.new(0, -rayDistance, 0)
		forwardDownResult = workspace:Raycast(rayOrigin, forwardDownDirection, params)
	end
	
	-- If neither raycast hit, no ground nearby
	if not downResult and not forwardDownResult then
		return 0, nil
	end
	
	-- Get the best ground position (closer one)
	local groundY = nil
	if downResult then
		groundY = downResult.Position.Y
	end
	if forwardDownResult then
		local forwardGroundY = forwardDownResult.Position.Y
		if not groundY or forwardGroundY > groundY then
			groundY = forwardGroundY -- Use higher ground (upcoming slope)
		end
	end
	
	-- Calculate force based on speed (faster = stronger pull)
	local baseForce = stickyConfig.StickForce or 180
	local speedMultiplier = stickyConfig.SpeedMultiplier or 1.5
	local maxSpeedBonus = stickyConfig.MaxSpeedBonus or 80
	local speedBonus = math.min(horizontalSpeed * speedMultiplier, maxSpeedBonus)
	
	return baseForce + speedBonus, groundY
end

-- DEPRECATED: DeflectOffWall - replaced by WallStop
function MovementUtils:DeflectOffWall(primaryPart, moveDirection, raycastParams)
	if not primaryPart or not moveDirection then
		return moveDirection
	end

	local glanceConfig = Config.Gameplay.Character.WallGlancing
	if not glanceConfig or not glanceConfig.Enabled then
		return moveDirection
	end

	local horizontalMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if horizontalMove.Magnitude < 0.01 then
		return moveDirection
	end
	horizontalMove = horizontalMove.Unit

	local rayOrigin = primaryPart.Position
	local rayDirection = horizontalMove * glanceConfig.RayDistance

	local params = raycastParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { primaryPart.Parent }
		params.RespectCanCollide = true
	end

	local result = workspace:Raycast(rayOrigin, rayDirection, params)
	if not result then
		return moveDirection
	end

	local wallNormal = result.Normal
	local horizontalNormal = Vector3.new(wallNormal.X, 0, wallNormal.Z)
	if horizontalNormal.Magnitude < 0.01 then
		return moveDirection
	end
	horizontalNormal = horizontalNormal.Unit

	local moveMagnitude = moveDirection.Magnitude
	local projected = moveDirection - (moveDirection:Dot(horizontalNormal)) * horizontalNormal
	
	if projected.Magnitude < 0.01 then
		return Vector3.new(0, moveDirection.Y, 0)
	end

	local deflected = projected.Unit * moveMagnitude * glanceConfig.DeflectionStrength
	return Vector3.new(deflected.X, moveDirection.Y, deflected.Z)
end

function MovementUtils:CalculateMovementForce(
	inputVector,
	currentVelocity,
	isGrounded,
	character,
	primaryPart,
	raycastParams,
	targetSpeed,
	weightMultiplier
)
	local weight = weightMultiplier or 1.0
	local effectiveWalkSpeed = (targetSpeed or WALK_SPEED) * weight

	if not inputVector or inputVector.Magnitude == 0 then
		local currentHorizontalVel = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
		local currentSpeed = currentHorizontalVel.Magnitude

		if currentSpeed > MIN_SPEED_THRESHOLD then
			local frictionMultiplier = FRICTION_MULTIPLIER
			-- REDUCE AIR CONTROL
			if not isGrounded then
				frictionMultiplier = frictionMultiplier * AIR_CONTROL_MULTIPLIER
			end
			return currentHorizontalVel * -frictionMultiplier
		end

		return VECTOR3_ZERO
	end

	-- Check if we're trying to move INTO a steep slope (directional check)
	if isGrounded and character and primaryPart and raycastParams then
		local isMovingIntoSteepSlope = self:IsMovingIntoSteepSlope(character, primaryPart, raycastParams, inputVector)
		if isMovingIntoSteepSlope then
			-- Trying to move uphill on steep slope - only allow friction, no movement
			local currentHorizontalVel = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
			local currentSpeed = currentHorizontalVel.Magnitude

			if currentSpeed > MIN_SPEED_THRESHOLD then
				-- Apply stronger friction on steep slopes to make sliding feel more natural
				local frictionMultiplier = FRICTION_MULTIPLIER * 2 -- Double friction on steep slopes
				return currentHorizontalVel * -frictionMultiplier
			end
			return VECTOR3_ZERO
		end
	end

	local currentHorizontalVel = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)

	-- Apply wall raycast for airborne movement blocking
	local adjustedInput = inputVector
	if not isGrounded and primaryPart then
		adjustedInput = self:GetValidMovementDirection(primaryPart, inputVector, raycastParams, isGrounded)
	end

	-- RIVALS-STYLE MOMENTUM PRESERVATION (bouncy landings)
	local desiredVelocity
	local landingConfig = Config.Gameplay.Character.LandingMomentum

	-- Check if we should preserve landing momentum
	local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
	local characterController = ServiceRegistry:GetController("CharacterController")
	local shouldPreserveMomentum = false

	if landingConfig and landingConfig.Enabled and characterController and characterController.JustLanded then
		local minSpeed = landingConfig.MinPreservationSpeed or 15
		local horizontalSpeed = currentHorizontalVel.Magnitude

		-- Only preserve if landing faster than threshold
		if horizontalSpeed > minSpeed then
			shouldPreserveMomentum = true
			local preservationMultiplier = landingConfig.PreservationMultiplier or 0.8
			desiredVelocity = currentHorizontalVel * preservationMultiplier
		end
	end

	-- Fall back to normal walk speed targeting if not preserving momentum
	if not shouldPreserveMomentum then
		desiredVelocity = adjustedInput.Unit * effectiveWalkSpeed
	end

	local velocityDifference = desiredVelocity - currentHorizontalVel

	local forceMultiplier = MOVEMENT_FORCE * weight

	if velocityDifference.Magnitude < DEADZONE_THRESHOLD then
		forceMultiplier = forceMultiplier * (velocityDifference.Magnitude / DEADZONE_THRESHOLD)
	end

	if not isGrounded then
		forceMultiplier = forceMultiplier * AIR_CONTROL_MULTIPLIER
	end

	return velocityDifference * forceMultiplier
end

function MovementUtils:ApplyJump(primaryPart, isGrounded, character, raycastParams, movementDirection, cameraYAngle)
	local TestMode = require(ReplicatedStorage.TestMode)
	local LogService = require(Locations.Modules.Systems.Core.LogService)
	local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("MOVEMENT", "NORMAL JUMP ATTEMPT", {
			HasPrimaryPart = primaryPart ~= nil,
			IsGrounded = isGrounded,
			HasCharacter = character ~= nil,
			HasRaycastParams = raycastParams ~= nil,
			PrimaryPartPosition = primaryPart and primaryPart.Position or nil,
			CurrentVelocity = primaryPart and primaryPart.AssemblyLinearVelocity or nil,
			Timestamp = tick(),
		})
	end

	if not primaryPart or not isGrounded then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("MOVEMENT", "NORMAL JUMP FAILED - preconditions", {
				HasPrimaryPart = primaryPart ~= nil,
				IsGrounded = isGrounded,
				Reason = not primaryPart and "No PrimaryPart" or "Not grounded",
			})
		end
		return false
	end

	-- Check if jump pad was recently triggered to prevent overriding jump pad boost
	local interactableController = ServiceRegistry:GetController("InteractableController")
	if interactableController and interactableController:WasJumpPadRecentlyTriggered(0.1) then
		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("MOVEMENT", "NORMAL JUMP SKIPPED - recent jump pad", {
				TimeSinceJumpPad = interactableController:GetTimeSinceLastJumpPad(),
				CurrentVelocity = primaryPart.AssemblyLinearVelocity,
				Reason = "Jump pad recently triggered, skipping normal jump to preserve boost",
			})
		end
		return false
	end

	-- Check if we're trying to jump uphill on a steep slope
	-- Allow jumping if not moving, or if moving away from/parallel to the slope
	if character and raycastParams and movementDirection then
		local worldMovement = self:CalculateWorldMovementDirection(movementDirection, cameraYAngle, false)
		local isMovingIntoSteepSlope = self:IsMovingIntoSteepSlope(character, primaryPart, raycastParams, worldMovement)
		if isMovingIntoSteepSlope then
			if TestMode.Logging.LogSlidingSystem then
				LogService:Info("MOVEMENT", "NORMAL JUMP FAILED - trying to jump uphill on steep slope", {
					MovementDirection = movementDirection,
					PrimaryPartPosition = primaryPart.Position,
				})
			end
			-- Can't jump uphill on steep slopes
			return false
		end
	end

	-- INSTANT JUMP
	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local jumpVelocity = Vector3.new(currentVelocity.X, JUMP_POWER, currentVelocity.Z)

	primaryPart.AssemblyLinearVelocity = jumpVelocity

	-- Trigger jump animation
	local animationController = ServiceRegistry:GetController("AnimationController")
	if animationController and animationController.TriggerJumpAnimation then
		animationController:TriggerJumpAnimation()
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("MOVEMENT", "NORMAL JUMP EXECUTED SUCCESSFULLY", {
			PreviousVelocity = currentVelocity,
			NewVelocity = jumpVelocity,
			JumpPower = JUMP_POWER,
			HorizontalVelocityPreserved = Vector3.new(currentVelocity.X, 0, currentVelocity.Z),
			PrimaryPartPosition = primaryPart.Position,
			Timestamp = tick(),
		})
	end

	return true
end

function MovementUtils:SetCharacterRotation(alignOrientation, targetYAngle)
	if not alignOrientation then
		return
	end

	local targetCFrame = CFrame.Angles(0, targetYAngle, 0)
	alignOrientation.CFrame = targetCFrame
end

function MovementUtils:ClampForce(force, maxMagnitude)
	if force.Magnitude > maxMagnitude then
		return force.Unit * maxMagnitude
	end
	return force
end

function MovementUtils:CalculateWorldMovementDirection(movementInput, cameraYAngle, includeSpeed)
	if not movementInput or movementInput.Magnitude == 0 then
		return Vector3.new(0, 0, 0)
	end

	-- Transform input relative to camera direction
	local inputVector = Vector3.new(movementInput.X, 0, -movementInput.Y)
	if inputVector.Magnitude > 0 then
		inputVector = inputVector.Unit
	end

	local cameraCFrame = CFrame.Angles(0, cameraYAngle, 0)
	local worldMovement = cameraCFrame:VectorToWorldSpace(inputVector)

	-- Apply speed if requested (for movement calculation)
	if includeSpeed then
		return worldMovement * WALK_SPEED
	end

	-- Return just direction (for sliding calculation)
	return worldMovement
end

function MovementUtils:UpdateStandingFriction(character, primaryPart, raycastParams, isMoving)
	if not character or not primaryPart or not raycastParams then
		return
	end

	-- Only apply standing friction when not moving
	if isMoving then
		-- Reset friction to 0 when moving
		for _, part in pairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				local props = part.CustomPhysicalProperties
				if props and props.Friction ~= 0 then
					part.CustomPhysicalProperties = PhysicalProperties.new(
						props.Density,
						0, -- Reset friction to 0
						props.Elasticity,
						props.FrictionWeight,
						props.ElasticityWeight
					)
				end
			end
		end
		return
	end

	-- Check if standing on a slope
	local isGrounded, _, slopeDegrees = self:CheckGroundedWithSlope(character, primaryPart, raycastParams)

	if not isGrounded then
		return
	end

	local minSlopeAngle = Config.Gameplay.Character.StandingFriction.MinSlopeAngle
	local idleFriction = Config.Gameplay.Character.StandingFriction.IdleFriction
	local slopeFriction = Config.Gameplay.Character.StandingFriction.SlopeFriction
	local targetFriction = idleFriction -- Default to idle friction when standing still

	-- Apply slope friction if on a slope
	if slopeDegrees >= minSlopeAngle then
		targetFriction = slopeFriction
	end

	-- Update friction on all character parts
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local props = part.CustomPhysicalProperties
			if props then
				-- Only update if friction value has changed
				if props.Friction ~= targetFriction then
					part.CustomPhysicalProperties = PhysicalProperties.new(
						props.Density,
						targetFriction, -- Set friction
						props.Elasticity,
						props.FrictionWeight,
						props.ElasticityWeight
					)
				end
			end
		end
	end
end

return MovementUtils
