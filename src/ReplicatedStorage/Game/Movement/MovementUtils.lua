local MovementUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Raycast result caching for performance
local raycastCache = {}
local CACHE_LIFETIME = 0.1 -- Cache results for 100ms

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local ConfigCache = require(Locations.Shared.Util:WaitForChild("ConfigCache"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))

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

local function generateCacheKey(origin, direction)
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

	local alignOrientation = primaryPart:FindFirstChild("AlignOrientation")
	if not alignOrientation then
		alignOrientation = Instance.new("AlignOrientation")
		alignOrientation.Name = "AlignOrientation"
		alignOrientation.Attachment0 = movementAttachment1
		alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
		alignOrientation.Parent = primaryPart
	end

	alignOrientation.CFrame = primaryPart.CFrame
	alignOrientation.MaxTorque = 100000
	alignOrientation.Responsiveness = Config.Camera.Smoothing.AngleSmoothness or 25
	alignOrientation.RigidityEnabled = false

	return alignOrientation, vectorForce
end

function MovementUtils:CheckGrounded(character, primaryPart, raycastParams)
	if not character or not primaryPart then
		return false
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

	local offsetX = feetSize.X / 4
	local offsetZ = feetSize.Z / 4

	local rayOrigins = {
		baseRayOrigin,
		baseRayOrigin + Vector3.new(0, 0, offsetZ),
		baseRayOrigin + Vector3.new(0, 0, -offsetZ),
		baseRayOrigin + Vector3.new(offsetX, 0, 0),
		baseRayOrigin + Vector3.new(-offsetX, 0, 0),
	}

	-- Simple ground check: if ANY ray hits, we're grounded.
	-- (Matching Moviee-Proj - no normal filtering)
	for _, rayOrigin in ipairs(rayOrigins) do
		local result = workspace:Raycast(rayOrigin, rayDirection, params)
		if result then
			return true
		end
	end

	return false
end

function MovementUtils:GetGroundCheckDebugInfo(character, primaryPart, raycastParams, groundRayDistanceOverride)
	if not character or not primaryPart then
		return nil
	end

	local feetPart = CharacterLocations:GetFeet(character) or primaryPart
	if not feetPart then
		return nil
	end

	local feetPosition = feetPart.Position
	local feetSize = feetPart.Size
	local bottomOfFeet = feetPosition - Vector3.new(0, feetSize.Y / 2, 0)
	local baseRayOrigin = bottomOfFeet + Vector3.new(0, GROUND_RAY_OFFSET, 0)
	local rayDistance = groundRayDistanceOverride or GROUND_RAY_DISTANCE
	local rayDirection = Vector3.new(0, -rayDistance, 0)

	local params = raycastParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.RespectCanCollide = true
		params.CollisionGroup = "Players"
	end

	local offsetX = feetSize.X / 4
	local offsetZ = feetSize.Z / 4
	local rayOrigins = {
		baseRayOrigin,
		baseRayOrigin + Vector3.new(0, 0, offsetZ),
		baseRayOrigin + Vector3.new(0, 0, -offsetZ),
		baseRayOrigin + Vector3.new(offsetX, 0, 0),
		baseRayOrigin + Vector3.new(-offsetX, 0, 0),
	}

	local rays = {}
	local hitCount = 0
	for _, rayOrigin in ipairs(rayOrigins) do
		local result = workspace:Raycast(rayOrigin, rayDirection, params)
		local rayInfo = {
			origin = rayOrigin,
			hit = result ~= nil,
		}
		if result then
			hitCount += 1
			rayInfo.instance = result.Instance
			rayInfo.distance = result.Distance
			rayInfo.material = tostring(result.Material)
			rayInfo.normal = result.Normal
			rayInfo.position = result.Position
		end
		table.insert(rays, rayInfo)
	end

	local paramsInfo = {
		FilterType = params.FilterType,
		FilterCount = params.FilterDescendantsInstances and #params.FilterDescendantsInstances or 0,
		RespectCanCollide = params.RespectCanCollide,
		CollisionGroup = params.CollisionGroup,
	}

	local nonCollideHit = nil
	if hitCount == 0 and params.RespectCanCollide == true then
		local fallbackParams = RaycastParams.new()
		fallbackParams.FilterType = params.FilterType
		fallbackParams.FilterDescendantsInstances = params.FilterDescendantsInstances
		fallbackParams.CollisionGroup = params.CollisionGroup
		fallbackParams.RespectCanCollide = false
		for _, rayOrigin in ipairs(rayOrigins) do
			local result = workspace:Raycast(rayOrigin, rayDirection, fallbackParams)
			if result then
				nonCollideHit = {
					instance = result.Instance,
					distance = result.Distance,
					material = tostring(result.Material),
				}
				break
			end
		end
	end

	return {
		feetPart = feetPart,
		feetSize = feetSize,
		feetPosition = feetPosition,
		baseRayOrigin = baseRayOrigin,
		rayDirection = rayDirection,
		params = paramsInfo,
		rays = rays,
		nonCollideHit = nonCollideHit,
	}
end

function MovementUtils:CheckGroundedWithSlope(character, primaryPart, raycastParams, groundRayDistanceOverride)
	if not character or not primaryPart then
		return false, nil, 0
	end

	local feetPart = CharacterLocations:GetFeet(character) or primaryPart

	local feetPosition = feetPart.Position
	local feetSize = feetPart.Size
	local bottomOfFeet = feetPosition - Vector3.new(0, feetSize.Y / 2, 0)
	local baseRayOrigin = bottomOfFeet + Vector3.new(0, GROUND_RAY_OFFSET, 0)

	local rayDistance = groundRayDistanceOverride or GROUND_RAY_DISTANCE
	local rayDirection = Vector3.new(0, -rayDistance, 0)

	local params = raycastParams
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.RespectCanCollide = true
		params.CollisionGroup = "Players"
	end

	local offsetX = feetSize.X / 4
	local offsetZ = feetSize.Z / 4

	local rayOrigins = {
		baseRayOrigin,
		baseRayOrigin + Vector3.new(0, 0, offsetZ),
		baseRayOrigin + Vector3.new(0, 0, -offsetZ),
		baseRayOrigin + Vector3.new(offsetX, 0, 0),
		baseRayOrigin + Vector3.new(-offsetX, 0, 0),
	}

	-- Simple ground check with slope info (matching Moviee-Proj):
	-- Return first valid result with slope info - no normal filtering.
	local worldUp = Vector3.new(0, 1, 0)

	for _, rayOrigin in ipairs(rayOrigins) do
		local result = getCachedRaycast(rayOrigin, rayDirection, params)
		if result then
			local surfaceNormal = result.Normal
			local slopeAngle = math.acos(math.clamp(surfaceNormal:Dot(worldUp), -1, 1))
			local slopeDegrees = math.deg(slopeAngle)
			return true, surfaceNormal, slopeDegrees
		end
	end

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

	local offsetX = feetSize.X / 4
	local offsetZ = feetSize.Z / 4

	local rayOrigins = {
		baseRayOrigin,
		baseRayOrigin + Vector3.new(0, 0, offsetZ),
		baseRayOrigin + Vector3.new(0, 0, -offsetZ),
		baseRayOrigin + Vector3.new(offsetX, 0, 0),
		baseRayOrigin + Vector3.new(-offsetX, 0, 0),
	}

	for _, rayOrigin in ipairs(rayOrigins) do
		local result = workspace:Raycast(rayOrigin, rayDirection, params)
		if result then
			local materialName = tostring(result.Material)
			local materialParts = string.split(materialName, ".")
			local cleanMaterialName = materialParts[#materialParts] or "Plastic"
			return true, cleanMaterialName
		end
	end

	return false, nil
end

function MovementUtils:IsMovingIntoSteepSlope(character, primaryPart, raycastParams, movementDirection)
	if not character or not primaryPart or not raycastParams or not movementDirection then
		return false
	end

	local horizontalDirection = Vector3.new(movementDirection.X, 0, movementDirection.Z)
	if horizontalDirection.Magnitude < 0.01 then
		return false
	end
	horizontalDirection = horizontalDirection.Unit

	local maxWalkableAngle = Config.Gameplay.Character.MaxWalkableSlopeAngle
	-- Keep steep-slope logic simple (Moviee-style):
	-- Use the stabilized ground normal from CheckGroundedWithSlope (which already ignores near-vertical "ground" hits).
	local isGrounded, surfaceNormal, slopeDegrees = self:CheckGroundedWithSlope(character, primaryPart, raycastParams)
	if not isGrounded or not surfaceNormal then
		return false
	end

	-- Only block once slope is actually above the walkable limit.
	if slopeDegrees <= maxWalkableAngle then
		return false
	end

	local slopeDirection = Vector3.new(surfaceNormal.X, 0, surfaceNormal.Z)
	if slopeDirection.Magnitude < 0.01 then
		return false
	end
	slopeDirection = slopeDirection.Unit

	local movementDot = horizontalDirection:Dot(slopeDirection)
	-- Block if moving meaningfully uphill (against slope direction).
	return movementDot < -0.1
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

-- Simple wall stop (matching Moviee-Proj):
-- Single raycast from body position, simple angle check.
function MovementUtils:CheckWallStop(primaryPart, raycastParams, moveDirection)
	if not primaryPart then
		return false
	end

	local wallStopConfig = Config.Gameplay.Character.WallStop
	if not wallStopConfig or not wallStopConfig.Enabled then
		return false
	end

	if not moveDirection then
		return false
	end

	local horizontalMoveDir = Vector3.new(moveDirection.X, 0, moveDirection.Z)

	if horizontalMoveDir.Magnitude < 0.1 then
		return false
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
		return false -- Not steep enough, it's a slope (allow movement)
	end

	-- Check if we're actually moving TOWARD the wall (not parallel)
	local horizontalNormal = Vector3.new(wallNormal.X, 0, wallNormal.Z)
	if horizontalNormal.Magnitude > 0.01 then
		horizontalNormal = horizontalNormal.Unit
		local movingTowardWall = moveDirectionUnit:Dot(horizontalNormal) < -0.3
		if not movingTowardWall then
			return false, nil -- Moving parallel or away from wall
		end
	end

	return true, wallNormal
end

function MovementUtils:CheckWallStopWithNormal(primaryPart, raycastParams, moveDirection)
	return self:CheckWallStop(primaryPart, raycastParams, moveDirection)
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
			if not isGrounded then
				frictionMultiplier = frictionMultiplier * AIR_CONTROL_MULTIPLIER
			end
			return currentHorizontalVel * -frictionMultiplier
		end

		return VECTOR3_ZERO
	end

	if isGrounded and character and primaryPart and raycastParams then
		local isMovingIntoSteepSlope = self:IsMovingIntoSteepSlope(character, primaryPart, raycastParams, inputVector)
		if isMovingIntoSteepSlope then
			local currentHorizontalVel = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
			local currentSpeed = currentHorizontalVel.Magnitude

			if currentSpeed > MIN_SPEED_THRESHOLD then
				local frictionMultiplier = FRICTION_MULTIPLIER * 2
				return currentHorizontalVel * -frictionMultiplier
			end
			return VECTOR3_ZERO
		end
	end

	local currentHorizontalVel = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)

	local adjustedInput = inputVector
	if not isGrounded and primaryPart then
		adjustedInput = self:GetValidMovementDirection(primaryPart, inputVector, raycastParams, isGrounded)
	end

	local desiredVelocity
	local landingConfig = Config.Gameplay.Character.LandingMomentum

	local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
	local characterController = ServiceRegistry:GetController("CharacterController")
	local shouldPreserveMomentum = false

	if landingConfig and landingConfig.Enabled and characterController and characterController.JustLanded then
		local minSpeed = landingConfig.MinPreservationSpeed or 15
		local horizontalSpeed = currentHorizontalVel.Magnitude

		if horizontalSpeed > minSpeed then
			shouldPreserveMomentum = true
			local preservationMultiplier = landingConfig.PreservationMultiplier or 0.8
			desiredVelocity = currentHorizontalVel * preservationMultiplier
		end
	end

	if not shouldPreserveMomentum then
		desiredVelocity = adjustedInput.Unit * effectiveWalkSpeed
	end

	local velocityDifference = desiredVelocity - currentHorizontalVel

	local forceMultiplier = MOVEMENT_FORCE * weight

	if velocityDifference.Magnitude < DEADZONE_THRESHOLD then
		forceMultiplier = forceMultiplier * (velocityDifference.Magnitude / DEADZONE_THRESHOLD)
	end

	if not isGrounded then
		-- Rivals-like air control: extremely limited steering.
		-- We already have AirControlMultiplier, but also apply AirResistance (if present)
		-- to make direction changes much harder at speed.
		local airControl = AIR_CONTROL_MULTIPLIER

		-- AirResistance is tuned as "higher = less steering".
		-- Use a small scaling so values like 25 still allow some control.
		local airResistance = Config.Gameplay.Character.AirResistance or 0
		local resistanceFactor = 1 / (1 + (airResistance * 0.25)) -- airResistance=25 => ~0.138

		forceMultiplier = forceMultiplier * airControl * resistanceFactor
	end

	return velocityDifference * forceMultiplier
end

function MovementUtils:ApplySlopeJump(primaryPart, character, raycastParams, movementDirection, cameraYAngle)
	-- Slope jump: apply a controlled horizontal carry/boost when jumping on a downhill slope.
	-- Keep it raycast-based and stateless (no wall sticking / no fake states).
	if not character or not primaryPart or not raycastParams or not movementDirection then
		return false, 0
	end

	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local currentHorizontal = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local currentSpeed = currentHorizontal.Magnitude

	-- Prevent "free speed" from a near-standstill hop.
	-- (No new config surface area; keep as a small constant.)
	if currentSpeed < 10 then
		return false, 0
	end

	local isGrounded, groundNormal, slopeDegrees = self:CheckGroundedWithSlope(character, primaryPart, raycastParams)
	if not isGrounded or not groundNormal then
		return false, 0
	end

	-- Only apply slope jump on significant slopes
	local minSlopeAngle = Config.Gameplay.Character.SlopeJump and Config.Gameplay.Character.SlopeJump.MinSlopeAngle or 8
	local maxSlopeAngle = Config.Gameplay.Character.MaxWalkableSlopeAngle or 50

	if slopeDegrees < minSlopeAngle or slopeDegrees > maxSlopeAngle then
		return false, 0
	end

	-- Calculate downhill direction along the slope plane.
	local gravity = Vector3.new(0, -1, 0)
	local downhillDirection = gravity - gravity:Dot(groundNormal) * groundNormal
	if downhillDirection.Magnitude < 0.01 then
		return false, 0
	end
	downhillDirection = downhillDirection.Unit

	-- Determine intended direction: prefer input; fall back to current velocity direction.
	local intendedDir = nil
	local worldMovement = self:CalculateWorldMovementDirection(movementDirection, cameraYAngle, false)
	if worldMovement.Magnitude >= 0.1 then
		intendedDir = Vector3.new(worldMovement.X, 0, worldMovement.Z)
	end
	if not intendedDir or intendedDir.Magnitude < 0.1 then
		intendedDir = currentHorizontal
	end
	if intendedDir.Magnitude < 0.1 then
		return false, 0
	end
	intendedDir = intendedDir.Unit

	-- Only apply when actually moving meaningfully downhill.
	local movementAlignment = intendedDir:Dot(downhillDirection)
	if movementAlignment < 0.2 then
		return false, 0
	end

	-- Calculate slope jump boost
	local slopeJumpConfig = Config.Gameplay.Character.SlopeJump or {
		BaseBoost = 15,
		MaxBoost = 35,
		SlopeScaling = 1.5,
	}

	local slopeStrength = math.clamp((slopeDegrees - minSlopeAngle) / (maxSlopeAngle - minSlopeAngle), 0, 1)
	local alignmentBonus = math.clamp(movementAlignment, 0.2, 1)

	local horizontalBoost = slopeJumpConfig.BaseBoost
		+ (slopeJumpConfig.MaxBoost - slopeJumpConfig.BaseBoost) * slopeStrength * alignmentBonus
	horizontalBoost = horizontalBoost * (slopeJumpConfig.SlopeScaling or 1.5)

	-- Apply boost along slope-tangent movement (more reliable than pure input yaw).
	-- Project intended direction onto the slope plane to avoid injecting into-ground components.
	local boostDirection = intendedDir - intendedDir:Dot(groundNormal) * groundNormal
	if boostDirection.Magnitude > 0.01 then
		boostDirection = boostDirection.Unit
	else
		boostDirection = intendedDir
	end

	local newHorizontal = currentHorizontal + boostDirection * horizontalBoost
	return true, horizontalBoost, Vector3.new(newHorizontal.X, currentVelocity.Y, newHorizontal.Z)
end

function MovementUtils:ApplyJump(primaryPart, isGrounded, character, raycastParams, movementDirection, cameraYAngle)
	local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))
	local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
	local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
	local movementController = ServiceRegistry:GetController("MovementController")

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
			return false
		end
	end

	local jumpFatigueMultiplier = 1
	if movementController and movementController.GetJumpFatigueMultiplier then
		jumpFatigueMultiplier = movementController:GetJumpFatigueMultiplier()
	end
	local jumpPower = JUMP_POWER * jumpFatigueMultiplier
	if movementController and movementController.ApplyJumpFatigueToVertical then
		jumpPower = movementController:ApplyJumpFatigueToVertical(JUMP_POWER)
	end

	local currentVelocity = primaryPart.AssemblyLinearVelocity
	local jumpVelocity = Vector3.new(currentVelocity.X, jumpPower, currentVelocity.Z)

	-- Check for slope jump boost
	local appliedSlopeJump, boostAmount, slopeVelocity = self:ApplySlopeJump(
		primaryPart,
		character,
		raycastParams,
		movementDirection,
		cameraYAngle
	)

	if appliedSlopeJump and slopeVelocity then
		jumpVelocity = Vector3.new(slopeVelocity.X, jumpPower, slopeVelocity.Z)

		if TestMode.Logging.LogSlidingSystem then
			LogService:Info("MOVEMENT", "SLOPE JUMP BOOST APPLIED", {
				BoostAmount = boostAmount,
				PreviousHorizontal = Vector3.new(currentVelocity.X, 0, currentVelocity.Z).Magnitude,
				NewHorizontal = Vector3.new(jumpVelocity.X, 0, jumpVelocity.Z).Magnitude,
			})
		end
	end

	primaryPart.AssemblyLinearVelocity = jumpVelocity
	if movementController and movementController.ConsumeJumpFatigue then
		movementController:ConsumeJumpFatigue("Normal")
	end

	local animationController = ServiceRegistry:GetController("AnimationController")
	if animationController and animationController.TriggerJumpAnimation then
		animationController:TriggerJumpAnimation()
	end

	if TestMode.Logging.LogSlidingSystem then
		LogService:Info("MOVEMENT", "NORMAL JUMP EXECUTED SUCCESSFULLY", {
			PreviousVelocity = currentVelocity,
			NewVelocity = jumpVelocity,
			JumpPower = jumpPower,
			JumpFatigueMultiplier = jumpFatigueMultiplier,
			HorizontalVelocityPreserved = Vector3.new(currentVelocity.X, 0, currentVelocity.Z),
			PrimaryPartPosition = primaryPart.Position,
			Timestamp = tick(),
			SlopeJumpApplied = appliedSlopeJump,
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

	local inputVector = Vector3.new(movementInput.X, 0, -movementInput.Y)
	if inputVector.Magnitude > 0 then
		inputVector = inputVector.Unit
	end

	local cameraCFrame = CFrame.Angles(0, cameraYAngle, 0)
	local worldMovement = cameraCFrame:VectorToWorldSpace(inputVector)

	if includeSpeed then
		return worldMovement * WALK_SPEED
	end

	return worldMovement
end

function MovementUtils:UpdateStandingFriction(character, primaryPart, raycastParams, isMoving)
	if not character or not primaryPart or not raycastParams then
		return
	end

	if isMoving then
		for _, part in pairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				local props = part.CustomPhysicalProperties
				if props and props.Friction ~= 0 then
					part.CustomPhysicalProperties = PhysicalProperties.new(
						props.Density,
						0,
						props.Elasticity,
						props.FrictionWeight,
						props.ElasticityWeight
					)
				end
			end
		end
		return
	end

	local isGrounded, _, slopeDegrees = self:CheckGroundedWithSlope(character, primaryPart, raycastParams)

	if not isGrounded then
		return
	end

	local minSlopeAngle = Config.Gameplay.Character.StandingFriction.MinSlopeAngle
	local idleFriction = Config.Gameplay.Character.StandingFriction.IdleFriction
	local slopeFriction = Config.Gameplay.Character.StandingFriction.SlopeFriction
	local targetFriction = idleFriction

	if slopeDegrees >= minSlopeAngle then
		targetFriction = slopeFriction
	end

	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local props = part.CustomPhysicalProperties
			if props then
				if props.Friction ~= targetFriction then
					part.CustomPhysicalProperties = PhysicalProperties.new(
						props.Density,
						targetFriction,
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
