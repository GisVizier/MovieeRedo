local SlidingPhysics = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local MovementUtils = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementUtils"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))
local SlideDirectionDetector = require(Locations.Shared.Util:WaitForChild("SlideDirectionDetector"))

SlidingPhysics.SlidingSystem = nil
SlidingPhysics.LastSlideRotationAngle = nil

function SlidingPhysics:Init(slidingSystem)
	self.SlidingSystem = slidingSystem
	self.LastSlideRotationAngle = nil
	LogService:Info("SLIDING", "SlidingPhysics initialized")
end

function SlidingPhysics:GetInitialSlideDirection(originalDirection)
	if not self.SlidingSystem.Character or not self.SlidingSystem.PrimaryPart or not self.SlidingSystem.RaycastParams then
		return nil
	end

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

	local surfaceNormal = result.Normal
	local worldUp = Vector3.new(0, 1, 0)
	local slopeAngle = math.acos(math.clamp(surfaceNormal:Dot(worldUp), -1, 1))
	local slopeDegrees = math.deg(slopeAngle)

	if slopeDegrees < Config.Gameplay.Sliding.SlopeThreshold then
		return nil
	end

	local slopeGradient = Vector3.new(surfaceNormal.X, 0, surfaceNormal.Z)
	if slopeGradient.Magnitude == 0 then
		return nil
	end

	local downhillDirection = slopeGradient.Unit
	local alignment = downhillDirection:Dot(originalDirection.Unit)

	if alignment > 0.3 then
		return downhillDirection
	end

	return nil
end

function SlidingPhysics:GetInitialSlopeVelocityBoost()
	if not self.SlidingSystem.Character or not self.SlidingSystem.PrimaryPart or not self.SlidingSystem.RaycastParams then
		return 0
	end

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

	local surfaceNormal = result.Normal
	local worldUp = Vector3.new(0, 1, 0)
	local slopeAngle = math.acos(math.clamp(surfaceNormal:Dot(worldUp), -1, 1))
	local slopeDegrees = math.deg(slopeAngle)

	if slopeDegrees > Config.Gameplay.Sliding.SlopeThreshold * 2 then
		local slopeStrength = (slopeDegrees - Config.Gameplay.Sliding.SlopeThreshold * 2)
			/ (90 - Config.Gameplay.Sliding.SlopeThreshold * 2)
		slopeStrength = math.clamp(slopeStrength, 0, 1)
		return slopeStrength * 15
	end

	return 0
end

function SlidingPhysics:CalculateSlopeMultiplierChange(deltaTime, slideConfig)
	if not self.SlidingSystem.Character or not self.SlidingSystem.PrimaryPart or not self.SlidingSystem.RaycastParams then
		return 0
	end

	local currentY = self.SlidingSystem.PrimaryPart.Position.Y
	self.SlidingSystem.PreviousY = currentY

	local groundRay = workspace:Raycast(
		self.SlidingSystem.PrimaryPart.Position,
		-self.SlidingSystem.PrimaryPart.CFrame.UpVector * Config.Gameplay.Sliding.GroundCheckDistance,
		self.SlidingSystem.RaycastParams
	)

	if not groundRay then
		return 0
	end

	local surfaceNormal = groundRay.Normal
	local worldUp = Vector3.new(0, 1, 0)
	local slopeAngle = math.acos(math.clamp(surfaceNormal:Dot(worldUp), -1, 1))
	local slopeSteepness = math.deg(slopeAngle)

	if slopeSteepness <= slideConfig.SlopeThreshold then
		return -slideConfig.SpeedChangeRates.Forward * deltaTime
	end

	local gravity = Vector3.new(0, -1, 0)
	local slopeDownhillDirection = (gravity - gravity:Dot(surfaceNormal) * surfaceNormal).Unit

	local movementAlignment = self.SlidingSystem.SlideDirection:Dot(slopeDownhillDirection)
	local alignmentStrength = math.abs(movementAlignment)

	if movementAlignment > 0 then
		local downhillFactor = slopeSteepness / slideConfig.SlopeSteepnessScaling.Downhill
		downhillFactor = math.clamp(downhillFactor, 1, 3)

		local minimumDownhillStrength = math.max(0.4, alignmentStrength)
		local accelerationAmount = slideConfig.SpeedChangeRates.Downward * downhillFactor * minimumDownhillStrength
		local resistanceAmount = -slideConfig.SpeedChangeRates.CrossSlope * (1 - alignmentStrength)

		return (accelerationAmount + resistanceAmount) * deltaTime
	end

	local uphillFactor = slopeSteepness / slideConfig.SlopeSteepnessScaling.Uphill
	uphillFactor = math.clamp(uphillFactor, 1, 3)

	local decelerationAmount = -slideConfig.SpeedChangeRates.Upward * alignmentStrength * uphillFactor
	local resistanceAmount = -slideConfig.SpeedChangeRates.CrossSlope * (1 - alignmentStrength)

	return math.min(decelerationAmount, resistanceAmount) * deltaTime
end

function SlidingPhysics:ApplySlideVelocity(deltaTime)
	if not self.SlidingSystem.PrimaryPart then
		return
	end

	-- Moviee-Proj style (old feel): drive slide with a velocity target (not force).
	-- We use LinearVelocity (constraint-based replacement for BodyVelocity) for modern parity.
	local primaryPart = self.SlidingSystem.PrimaryPart
	local raycastParams = self.SlidingSystem.RaycastParams

	-- Ensure any prior force-based slide driver is removed.
	local slideForce = primaryPart:FindFirstChild("SlideForce")
	if slideForce then
		slideForce:Destroy()
	end
	-- Ensure any legacy BodyVelocity slide driver is removed (migration safety).
	local legacyBodyVel = primaryPart:FindFirstChild("SlideBodyVelocity")
	if legacyBodyVel then
		legacyBodyVel:Destroy()
	end

	local slideVelocityVector = self.SlidingSystem.SlideDirection * self.SlidingSystem.SlideVelocity
	local currentVelocity = primaryPart.AssemblyLinearVelocity

	-- Preserve gravity/jumping unless we detect ground and want stickiness.
	local adhesionYVelocity = nil
	local targetVelocity = slideVelocityVector

	-- Raycast straight down
	local downRayDistance = Config.Gameplay.Sliding.GroundCheckDistance or 10
	local downRay = workspace:Raycast(primaryPart.Position, Vector3.new(0, -downRayDistance, 0), raycastParams)

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
		-- Prefer the higher/closer ground hit
		local bestHit = downRay
		if forwardDownRay then
			if not downRay then
				bestHit = forwardDownRay
			elseif forwardDownRay.Position.Y > downRay.Position.Y then
				bestHit = forwardDownRay
			end
		end

		if bestHit and bestHit.Normal then
			local tangentDirection = self.SlidingSystem.SlideDirection
				- self.SlidingSystem.SlideDirection:Dot(bestHit.Normal) * bestHit.Normal
			if tangentDirection.Magnitude > 0.05 then
				targetVelocity = tangentDirection.Unit * slideSpeed
			end
		end

		-- NOTE: Use vertical gap from the *bottom of the rig* (not root center, not 3D distance).
		-- Using the root center causes constant "digging" because the center is always ~half a part-height above the ground.
		-- Also add a small deadzone + damping (PD-style) so we don't "dig" into ground at any speed.
		local feetPart = CharacterLocations:GetFeet(self.SlidingSystem.Character) or primaryPart
		local feetBottomY = feetPart.Position.Y - (feetPart.Size.Y * 0.5)

		local verticalGap = feetBottomY - bestHit.Position.Y
		verticalGap = math.max(0, verticalGap)

		-- Deadzone: if we're already close enough to the surface, don't force extra downward velocity.
		local targetGap = 0.2
		local gapError = verticalGap - targetGap

		if gapError > 0 then
			-- Pull down proportional to gap, with damping against current vertical velocity.
			-- Scale slightly with slide speed so faster slides re-attach more aggressively.
			local speedFactor = math.clamp(slideSpeed / 60, 0, 1)
			local kP = 120 + 80 * speedFactor
			local kD = 10 + 6 * speedFactor

			adhesionYVelocity = -(kP * gapError) - (kD * currentVelocity.Y)

			-- If already moving downward faster, keep that.
			if currentVelocity.Y < adhesionYVelocity then
				adhesionYVelocity = currentVelocity.Y
			end
		end
	end

	local finalYVelocity
	if groundDetected then
		finalYVelocity = targetVelocity.Y
		if adhesionYVelocity and adhesionYVelocity < finalYVelocity then
			finalYVelocity = adhesionYVelocity
		end
	else
		finalYVelocity = currentVelocity.Y
	end

	-- Clamp Y velocity (prevents extreme values)
	finalYVelocity = math.clamp(finalYVelocity, -250, 30)

	-- Use LinearVelocity with per-axis force limits to match old BodyVelocity behavior.
	local attachment = primaryPart:FindFirstChild("SlideAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "SlideAttachment"
		attachment.Parent = primaryPart
	end

	local linearVel = primaryPart:FindFirstChild("SlideLinearVelocity")
	if not linearVel then
		linearVel = Instance.new("LinearVelocity")
		linearVel.Name = "SlideLinearVelocity"
		linearVel.Attachment0 = attachment
		linearVel.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		linearVel.ForceLimitsEnabled = true
		linearVel.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		linearVel.Parent = primaryPart
	end

	-- Match prior per-axis MaxForce used by SlideBodyVelocity.
	linearVel.MaxAxesForce = Vector3.new(40000, 30000, 40000)
	linearVel.VectorVelocity = Vector3.new(targetVelocity.X, finalYVelocity, targetVelocity.Z)
end

function SlidingPhysics:UpdateSlideDirection()
	local steeringConfig = Config.Gameplay.Sliding.Steering
	if not steeringConfig or not steeringConfig.Enabled then
		return
	end

	if not self.SlidingSystem.CharacterController or not self.SlidingSystem.CameraController then
		return
	end

	local movementInput = self.SlidingSystem.CharacterController.MovementInput
	if not movementInput or movementInput.Magnitude < 0.1 then
		return
	end

	local cameraAngles = self.SlidingSystem.CameraController:GetCameraAngles()
	local cameraYAngle = math.rad(cameraAngles.X)

	local targetDirection = MovementUtils:CalculateWorldMovementDirection(movementInput, cameraYAngle, false)

	if targetDirection.Magnitude < 0.01 then
		return
	end

	targetDirection = targetDirection.Unit

	local currentDirection = self.SlidingSystem.SlideDirection
	local alignment = currentDirection:Dot(targetDirection)

	local minAlignment = steeringConfig.MinAlignment or 0.7
	if alignment < minAlignment then
		local velocityPenalty = steeringConfig.VelocityPenalty or 0.75
		local penaltyFactor = math.max(velocityPenalty, alignment)
		self.SlidingSystem.SlideVelocity = self.SlidingSystem.SlideVelocity * penaltyFactor
	end

	local responsiveness = steeringConfig.Responsiveness or 0.12
	self.SlidingSystem.SlideDirection = currentDirection:Lerp(targetDirection, responsiveness).Unit
end

function SlidingPhysics:CheckGroundedForSliding()
	if not self.SlidingSystem.Character or not self.SlidingSystem.PrimaryPart or not self.SlidingSystem.RaycastParams then
		return false
	end

	return MovementUtils:CheckGrounded(self.SlidingSystem.Character, self.SlidingSystem.PrimaryPart, self.SlidingSystem.RaycastParams)
end

function SlidingPhysics:UpdateSlideRotation()
	if not self.SlidingSystem.AlignOrientation or not self.SlidingSystem.CameraController then
		return
	end

	local cameraAngles = self.SlidingSystem.CameraController:GetCameraAngles()
	local cameraDirAngle = math.rad(cameraAngles.X)
	local cameraDirection = Vector3.new(math.sin(cameraDirAngle), 0, math.cos(cameraDirAngle))

	local targetYAngle = SlideDirectionDetector:GetSlideRotationAngle(cameraDirection, self.SlidingSystem.SlideDirection)

	self.LastSlideRotationAngle = targetYAngle
	MovementUtils:SetCharacterRotation(self.SlidingSystem.AlignOrientation, targetYAngle)
end

return SlidingPhysics
