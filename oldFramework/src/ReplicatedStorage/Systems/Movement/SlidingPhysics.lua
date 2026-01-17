local SlidingPhysics = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local TestMode = require(ReplicatedStorage.TestMode)
local SlideDirectionDetector = require(Locations.Modules.Utils.SlideDirectionDetector)
local UserSettings = require(Locations.Modules.Systems.Core.UserSettings)

-- Reference to main SlidingSystem (will be set by SlidingSystem:Init)
SlidingPhysics.SlidingSystem = nil

-- Rotation tracking for smooth updates
SlidingPhysics.LastSlideRotationAngle = nil

function SlidingPhysics:Init(slidingSystem)
	self.SlidingSystem = slidingSystem
	self.LastSlideRotationAngle = nil
	LogService:Info("SLIDING", "SlidingPhysics initialized")
end

function SlidingPhysics:GetInitialSlideDirection(originalDirection)
	if
		not self.SlidingSystem.Character
		or not self.SlidingSystem.PrimaryPart
		or not self.SlidingSystem.RaycastParams
	then
		return nil
	end

	-- Get slope from raycast at slide start
	local feetPart = CharacterLocations:GetFeet(self.SlidingSystem.Character) or self.SlidingSystem.PrimaryPart
	local feetPosition = feetPart.Position
	local feetSize = feetPart.Size
	local bottomOfFeet = feetPosition - Vector3.new(0, feetSize.Y / 2, 0)
	local rayOrigin = bottomOfFeet + Vector3.new(0, Config.Gameplay.Sliding.GroundCheckOffset, 0)
	local rayDirection = Vector3.new(0, -Config.Gameplay.Sliding.GroundCheckDistance, 0)

	local result = workspace:Raycast(rayOrigin, rayDirection, self.SlidingSystem.RaycastParams)
	if not result then
		return nil
	end

	-- Calculate slope angle
	local surfaceNormal = result.Normal
	local worldUp = Vector3.new(0, 1, 0)
	local slopeAngle = math.acos(math.clamp(surfaceNormal:Dot(worldUp), -1, 1))
	local slopeDegrees = math.deg(slopeAngle)

	-- Only adjust direction on significant slopes
	if slopeDegrees < Config.Gameplay.Sliding.SlopeThreshold then
		return nil
	end

	-- Calculate true downhill direction
	local slopeGradient = Vector3.new(surfaceNormal.X, 0, surfaceNormal.Z)
	if slopeGradient.Magnitude == 0 then
		return nil
	end

	local downhillDirection = slopeGradient.Unit -- Gradient points downhill when normalized

	-- Check if original direction is reasonably aligned with downhill
	local alignment = downhillDirection:Dot(originalDirection.Unit)

	-- If sliding reasonably downhill (>30% aligned), use pure downhill direction
	-- This prevents the "forward then down" issue
	if alignment > 0.3 then
		return downhillDirection
	end

	-- Otherwise, keep original direction
	return nil
end

function SlidingPhysics:GetInitialSlopeVelocityBoost()
	if
		not self.SlidingSystem.Character
		or not self.SlidingSystem.PrimaryPart
		or not self.SlidingSystem.RaycastParams
	then
		return 0
	end

	-- Get slope angle for initial boost calculation
	local feetPart = CharacterLocations:GetFeet(self.SlidingSystem.Character) or self.SlidingSystem.PrimaryPart
	local feetPosition = feetPart.Position
	local feetSize = feetPart.Size
	local bottomOfFeet = feetPosition - Vector3.new(0, feetSize.Y / 2, 0)
	local rayOrigin = bottomOfFeet + Vector3.new(0, Config.Gameplay.Sliding.GroundCheckOffset, 0)
	local rayDirection = Vector3.new(0, -Config.Gameplay.Sliding.GroundCheckDistance, 0)

	local result = workspace:Raycast(rayOrigin, rayDirection, self.SlidingSystem.RaycastParams)
	if not result then
		return 0
	end

	-- Calculate slope angle
	local surfaceNormal = result.Normal
	local worldUp = Vector3.new(0, 1, 0)
	local slopeAngle = math.acos(math.clamp(surfaceNormal:Dot(worldUp), -1, 1))
	local slopeDegrees = math.deg(slopeAngle)

	-- Only boost on steeper slopes for immediate downhill feeling
	if slopeDegrees > Config.Gameplay.Sliding.SlopeThreshold * 2 then -- Double threshold for initial boost
		local slopeStrength = (slopeDegrees - Config.Gameplay.Sliding.SlopeThreshold * 2)
			/ (90 - Config.Gameplay.Sliding.SlopeThreshold * 2)
		slopeStrength = math.clamp(slopeStrength, 0, 1)
		return slopeStrength * 15 -- Up to 15 extra velocity for steep slopes
	end

	return 0
end

function SlidingPhysics:CalculateSlopeMultiplierChange(deltaTime, slideConfig)
	if
		not self.SlidingSystem.Character
		or not self.SlidingSystem.PrimaryPart
		or not self.SlidingSystem.RaycastParams
	then
		return 0
	end

	-- Update previous Y position tracking
	local currentY = self.SlidingSystem.PrimaryPart.Position.Y
	self.SlidingSystem.PreviousY = currentY

	-- Get slope angle from raycast for steepness calculation (always use main Sliding config)
	local groundRay = workspace:Raycast(
		self.SlidingSystem.PrimaryPart.Position,
		-self.SlidingSystem.PrimaryPart.CFrame.UpVector * Config.Gameplay.Sliding.GroundCheckDistance,
		self.SlidingSystem.RaycastParams
	)

	if not groundRay then
		return 0
	end

	-- Calculate slope information
	local surfaceNormal = groundRay.Normal
	local worldUp = Vector3.new(0, 1, 0)
	local slopeAngle = math.acos(math.clamp(surfaceNormal:Dot(worldUp), -1, 1))
	local slopeSteepness = math.deg(slopeAngle)

	-- Use slope angle to determine terrain type (not position change)
	if slopeSteepness <= slideConfig.SlopeThreshold then
		-- On flat ground - apply forward deceleration
		return -slideConfig.SpeedChangeRates.Forward * deltaTime
	else
		-- On a slope - use graduated alignment system to prevent zigzag exploitation
		-- Calculate slope's downhill direction
		local gravity = Vector3.new(0, -1, 0)
		local slopeDownhillDirection = (gravity - gravity:Dot(surfaceNormal) * surfaceNormal).Unit

		-- Get alignment with downhill direction (-1 = uphill, 0 = across, +1 = downhill)
		local movementAlignment = self.SlidingSystem.SlideDirection:Dot(slopeDownhillDirection)

		-- Calculate alignment strength (how directly aligned we are)
		local alignmentStrength = math.abs(movementAlignment)

		if movementAlignment > 0 then
			-- Moving downhill - blend between cross-slope resistance and downhill acceleration
			-- The more aligned with downhill, the more acceleration we get
			local downhillFactor = slopeSteepness / slideConfig.SlopeSteepnessScaling.Downhill
			downhillFactor = math.clamp(downhillFactor, 1, 3)

			-- Give meaningful downhill acceleration even when not perfectly aligned
			-- Use a minimum base acceleration for steep downhill movement
			local minimumDownhillStrength = math.max(0.4, alignmentStrength) -- At least 40% acceleration
			local accelerationAmount = slideConfig.SpeedChangeRates.Downward * downhillFactor * minimumDownhillStrength
			-- Cross-slope resistance when not aligned
			local resistanceAmount = -slideConfig.SpeedChangeRates.CrossSlope * (1 - alignmentStrength)

			return (accelerationAmount + resistanceAmount) * deltaTime
		else
			-- Moving uphill - blend between cross-slope resistance and uphill deceleration
			-- The more aligned with uphill, the more deceleration we get
			-- Scale deceleration by slope steepness - steeper slopes = much more deceleration
			local uphillFactor = slopeSteepness / slideConfig.SlopeSteepnessScaling.Uphill
			uphillFactor = math.clamp(uphillFactor, 1, 3)

			local decelerationAmount = -slideConfig.SpeedChangeRates.Upward * alignmentStrength * uphillFactor
			-- Cross-slope resistance when not aligned
			local resistanceAmount = -slideConfig.SpeedChangeRates.CrossSlope * (1 - alignmentStrength)

			-- Take the stronger of the two forces (both are negative)
			return math.min(decelerationAmount, resistanceAmount) * deltaTime
		end
	end
end

function SlidingPhysics:ApplySlideVelocity(deltaTime)
	if not self.SlidingSystem.PrimaryPart then
		return
	end

	-- Apply velocity directly like the original system
	local slideVelocityVector = self.SlidingSystem.SlideDirection * self.SlidingSystem.SlideVelocity

	-- Get current Y velocity to preserve gravity/jumping
	local currentVelocity = self.SlidingSystem.PrimaryPart.AssemblyLinearVelocity

	-- SIMPLIFIED SURFACE STICKINESS: Always stick to ground when detected
	local yVelocity = currentVelocity.Y
	local primaryPart = self.SlidingSystem.PrimaryPart
	local raycastParams = self.SlidingSystem.RaycastParams
	
	-- Raycast straight down
	local downRayDistance = Config.Gameplay.Sliding.GroundCheckDistance or 10
	local downRay = workspace:Raycast(
		primaryPart.Position,
		Vector3.new(0, -downRayDistance, 0),
		raycastParams
	)
	
	-- Raycast forward-down to catch upcoming slopes
	local forwardDownRay = nil
	local slideSpeed = self.SlidingSystem.SlideVelocity or 0
	if slideSpeed > 5 then
		local moveDir = slideVelocityVector.Unit
		if moveDir.Magnitude > 0.1 then
			local horizontalDir = Vector3.new(moveDir.X, 0, moveDir.Z)
			if horizontalDir.Magnitude > 0.1 then
				horizontalDir = horizontalDir.Unit
				local forwardDownDirection = (horizontalDir * downRayDistance) + Vector3.new(0, -downRayDistance, 0)
				forwardDownRay = workspace:Raycast(primaryPart.Position, forwardDownDirection, raycastParams)
			end
		end
	end
	
	-- If ANY ground is detected, apply strong stickiness
	local groundDetected = downRay or forwardDownRay
	if groundDetected then
		-- Get the best ground hit (prefer the higher/closer one)
		local bestHit = downRay
		if forwardDownRay then
			if not downRay then
				bestHit = forwardDownRay
			else
				if forwardDownRay.Position.Y > downRay.Position.Y then
					bestHit = forwardDownRay
				end
			end
		end
		
		local distanceToGround = (primaryPart.Position - bestHit.Position).Magnitude
		
		-- VELOCITY-SCALED SURFACE STICKINESS
		-- Higher velocity = stronger stickiness (prevents floating at speed)
		-- Lower velocity = gentler stickiness (prevents ground pushing on slow slides)
		local slideSpeed = self.SlidingSystem.SlideVelocity or 0
		if slideSpeed > 5 then
			-- IMMEDIATE STICKINESS for standstill slides on ramps
			local speedFactor = math.clamp((slideSpeed - 5) / 45, 0, 1)
			local baseStrength = 220 -- High base for standstill slides on ramps
			local maxStrength = 300 -- Max for fast slides
			local stickStrength = baseStrength + (maxStrength - baseStrength) * speedFactor
			
			local distanceMultiplier = math.clamp(distanceToGround / 3, 0.5, 2.0)
			local stickForce = stickStrength * distanceMultiplier
			
			-- Apply stick force (pull toward ground)
			yVelocity = -stickForce
			
			-- If already moving downward faster, keep that
			if currentVelocity.Y < yVelocity then
				yVelocity = currentVelocity.Y
			end
		end
	end
	
	-- CLAMP Y VELOCITY: Prevent extreme values
	yVelocity = math.clamp(yVelocity, -250, 30)

	-- Use BodyVelocity WITH Y CONTROL to stick to surfaces
	local bodyVel = self.SlidingSystem.PrimaryPart:FindFirstChild("SlideBodyVelocity")
	if not bodyVel then
		bodyVel = Instance.new("BodyVelocity")
		bodyVel.Name = "SlideBodyVelocity"
		bodyVel.Parent = self.SlidingSystem.PrimaryPart
	end

	-- ENABLE Y CONTROL: Was (40000, 0, 40000) - Y was 0 meaning no vertical control!
	-- Now Y has force to actually stick to surfaces
	bodyVel.MaxForce = Vector3.new(40000, 30000, 40000)
	bodyVel.Velocity = Vector3.new(slideVelocityVector.X, yVelocity, slideVelocityVector.Z)
end

function SlidingPhysics:UpdateSlideDirection()
	-- RIVALS-STYLE OMNI-DIRECTIONAL SLIDING (momentum-based steering)
	local steeringConfig = Config.Gameplay.Sliding.Steering
	if not steeringConfig or not steeringConfig.Enabled then
		return
	end

	-- Check if we have valid references
	if not self.SlidingSystem.CharacterController or not self.SlidingSystem.CameraController then
		return
	end

	-- Get current movement input
	local movementInput = self.SlidingSystem.CharacterController.MovementInput
	if not movementInput or movementInput.Magnitude < 0.1 then
		return
	end

	-- Calculate world-space target direction from input
	local cameraAngles = self.SlidingSystem.CameraController:GetCameraAngles()
	local cameraYAngle = math.rad(cameraAngles.X)

	local targetDirection = MovementUtils:CalculateWorldMovementDirection(
		movementInput,
		cameraYAngle,
		false
	)

	if targetDirection.Magnitude < 0.01 then
		return
	end

	targetDirection = targetDirection.Unit

	-- Calculate alignment between current and target direction
	local currentDirection = self.SlidingSystem.SlideDirection
	local alignment = currentDirection:Dot(targetDirection)

	-- Apply velocity penalty for sharp turns (momentum-based)
	local minAlignment = steeringConfig.MinAlignment or 0.7
	if alignment < minAlignment then
		local velocityPenalty = steeringConfig.VelocityPenalty or 0.75
		local penaltyFactor = math.max(velocityPenalty, alignment)
		self.SlidingSystem.SlideVelocity = self.SlidingSystem.SlideVelocity * penaltyFactor
	end

	-- Blend current direction toward target with responsiveness
	local responsiveness = steeringConfig.Responsiveness or 0.12
	self.SlidingSystem.SlideDirection = currentDirection:Lerp(targetDirection, responsiveness).Unit
end

function SlidingPhysics:CheckGroundedForSliding()
	if
		not self.SlidingSystem.Character
		or not self.SlidingSystem.PrimaryPart
		or not self.SlidingSystem.RaycastParams
	then
		return false
	end

	-- Use the same grounded check as normal movement for consistency and efficiency
	return MovementUtils:CheckGrounded(
		self.SlidingSystem.Character,
		self.SlidingSystem.PrimaryPart,
		self.SlidingSystem.RaycastParams
	)
end

function SlidingPhysics:UpdateSlideRotation()
	if not self.SlidingSystem.AlignOrientation or not self.SlidingSystem.CameraController then
		return
	end

	-- Get camera direction
	local cameraAngles = self.SlidingSystem.CameraController:GetCameraAngles()
	local cameraDirAngle = math.rad(cameraAngles.X)
	local cameraDirection = Vector3.new(math.sin(cameraDirAngle), 0, math.cos(cameraDirAngle))

	-- Determine rotation based on slide type (backward slides face camera)
	local targetYAngle =
		SlideDirectionDetector:GetSlideRotationAngle(cameraDirection, self.SlidingSystem.SlideDirection)

	-- Update rotation and track for next frame (removed threshold - always update for responsive feel)
	self.LastSlideRotationAngle = targetYAngle
	MovementUtils:SetCharacterRotation(self.SlidingSystem.AlignOrientation, targetYAngle)
end



return SlidingPhysics
