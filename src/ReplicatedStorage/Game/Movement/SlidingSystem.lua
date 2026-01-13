local SlidingSystem = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local MovementUtils = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementUtils"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))
local SlideDirectionDetector = require(Locations.Shared.Util:WaitForChild("SlideDirectionDetector"))

local SlidingBuffer = require(Locations.Game:WaitForChild("Movement"):WaitForChild("SlidingBuffer"))
local SlidingPhysics = require(Locations.Game:WaitForChild("Movement"):WaitForChild("SlidingPhysics"))
local SlidingState = require(Locations.Game:WaitForChild("Movement"):WaitForChild("SlidingState"))
local RigRotationUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("RigRotationUtils"))
local FOVController = require(Locations.Shared.Util:WaitForChild("FOVController"))
local VFXPlayer = require(Locations.Shared.Util:WaitForChild("VFXPlayer"))

local function getMovementTemplate(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local vfx = assets:FindFirstChild("VFX")
	local movement = vfx and vfx:FindFirstChild("MovementFX")
	local fromNew = movement and movement:FindFirstChild(name)
	if fromNew then
		return fromNew
	end
	local legacy = assets:FindFirstChild("MovementFX")
	return legacy and legacy:FindFirstChild(name) or nil
end

SlidingSystem.IsSliding = false
SlidingSystem.SlideVelocity = 0
SlidingSystem.SlideDirection = Vector3.new(0, 0, 0)
SlidingSystem.OriginalSlideDirection = Vector3.new(0, 0, 0)
SlidingSystem.LastSlideEndTime = 0
SlidingSystem.CurrentSlideSkipsCooldown = false
SlidingSystem.PreviousY = 0

SlidingSystem.AirborneStartTime = 0
SlidingSystem.AirborneStartY = 0
SlidingSystem.AirbornePeakY = 0
SlidingSystem.IsAirborne = false
SlidingSystem.WasAirborneLastFrame = false

SlidingSystem.IsSlideBuffered = false
SlidingSystem.BufferedSlideDirection = Vector3.new(0, 0, 0)
SlidingSystem.SlideBufferStartTime = 0
SlidingSystem.IsSlideBufferFromJumpCancel = false

SlidingSystem.IsJumpCancelBuffered = false
SlidingSystem.BufferedJumpCancelDirection = Vector3.new(0, 0, 0)
SlidingSystem.JumpCancelBufferStartTime = 0

SlidingSystem.JumpCancelPerformed = false
SlidingSystem.HasLandedAfterJumpCancel = false

SlidingSystem.LastSlideStopTime = 0
SlidingSystem.SlideStopDirection = Vector3.new(0, 0, 0)
SlidingSystem.SlideStopVelocity = 0

SlidingSystem.Character = nil
SlidingSystem.PrimaryPart = nil
SlidingSystem.AlignOrientation = nil
SlidingSystem.RaycastParams = nil
SlidingSystem.CameraController = nil
SlidingSystem.CharacterController = nil
SlidingSystem.LastCameraAngle = 0

SlidingSystem.SlidingBuffer = SlidingBuffer
SlidingSystem.SlidingPhysics = SlidingPhysics
SlidingSystem.SlidingState = SlidingState

SlidingSystem.SlideUpdateConnection = nil

SlidingSystem.SlideTrail = nil
SlidingSystem.TrailAttachment0 = nil
SlidingSystem.TrailAttachment1 = nil

SlidingSystem.LastLandingBoostSoundTime = 0
SlidingSystem.LandingBoostSoundCooldown = 0.1

SlidingSystem.LastKnownDeltaTime = 1 / 60

function SlidingSystem:Init()
	SlidingBuffer:Init(self)
	SlidingPhysics:Init(self)
	SlidingState:Init(self)

	LogService:Info("SLIDING", "SlidingSystem initialized with modular architecture")
end

function SlidingSystem:CreateSlideTrail()
	return
end

function SlidingSystem:RemoveSlideTrail()
	if self.TrailSpawnConnection then
		self.TrailSpawnConnection:Disconnect()
		self.TrailSpawnConnection = nil
	end

	self.LastTrailSpawnTime = nil

	if self.TrailFolder then
		task.delay(12, function()
			if self.TrailFolder and self.TrailFolder.Parent then
				self.TrailFolder:Destroy()
			end
		end)
		self.TrailFolder = nil
	end
end

function SlidingSystem:PlayLandingBoostSound()
	local currentTime = tick()
	if currentTime - self.LastLandingBoostSoundTime >= self.LandingBoostSoundCooldown then
		self.LastLandingBoostSoundTime = currentTime

		SoundManager:PlaySound("Movement", "LandingBoost")

		local bodyPart = CharacterLocations:GetBody(self.Character) or self.PrimaryPart
		if bodyPart then
			SoundManager:RequestSoundReplication("Movement", "LandingBoost", bodyPart.Position)
		end

		return true
	end
	return false
end

function SlidingSystem:IsCrouchCooldownActive(characterController)
	return SlidingState:IsCrouchCooldownActive(characterController)
end

function SlidingSystem:ResetCooldownsFromJumpCancel(characterController)
	return SlidingState:ResetCooldownsFromJumpCancel(characterController)
end

function SlidingSystem:CanStartSlide(movementInput, isCrouching, isGrounded)
	return SlidingState:CanStartSlide(movementInput, isCrouching, isGrounded)
end

function SlidingSystem:IsInJumpCancelCoyoteTime()
	return SlidingState:IsInJumpCancelCoyoteTime()
end

function SlidingSystem:CanJumpCancel()
	return SlidingState:CanJumpCancel()
end

function SlidingSystem:ExecuteJumpCancel(slideDirection, characterController)
	return SlidingState:ExecuteJumpCancel(slideDirection, characterController)
end

function SlidingSystem:CanUncrouchAfterJumpSlide()
	return SlidingState:CanUncrouchAfterJumpSlide()
end

function SlidingSystem:CanBufferSlide(movementInput, isCrouching, isGrounded, characterController)
	return SlidingBuffer:CanBufferSlide(movementInput, isCrouching, isGrounded, characterController)
end

function SlidingSystem:StartSlideBuffer(movementDirection, fromJumpCancel)
	return SlidingBuffer:StartSlideBuffer(movementDirection, fromJumpCancel)
end

function SlidingSystem:CancelSlideBuffer(reason)
	return SlidingBuffer:CancelSlideBuffer(reason)
end

function SlidingSystem:TransferSlideCooldownToCrouch(characterController)
	return SlidingBuffer:TransferSlideCooldownToCrouch(characterController)
end

function SlidingSystem:CanBufferJumpCancel()
	return SlidingBuffer:CanBufferJumpCancel()
end

function SlidingSystem:StartJumpCancelBuffer()
	return SlidingBuffer:StartJumpCancelBuffer()
end

function SlidingSystem:CancelJumpCancelBuffer()
	return SlidingBuffer:CancelJumpCancelBuffer()
end

function SlidingSystem:GetInitialSlideDirection(originalDirection)
	return SlidingPhysics:GetInitialSlideDirection(originalDirection)
end

function SlidingSystem:GetInitialSlopeVelocityBoost()
	return SlidingPhysics:GetInitialSlopeVelocityBoost()
end

function SlidingSystem:CalculateSlopeMultiplierChange(deltaTime, slideConfig)
	return SlidingPhysics:CalculateSlopeMultiplierChange(deltaTime, slideConfig)
end

function SlidingSystem:ApplySlideVelocity(deltaTime)
	return SlidingPhysics:ApplySlideVelocity(deltaTime)
end

function SlidingSystem:UpdateSlideDirection()
	return SlidingPhysics:UpdateSlideDirection()
end

function SlidingSystem:CheckGroundedForSliding()
	return SlidingPhysics:CheckGroundedForSliding()
end

function SlidingSystem:UpdateSlideRotation()
	return SlidingPhysics:UpdateSlideRotation()
end

function SlidingSystem:SetupCharacter(character, primaryPart, _vectorForce, alignOrientation, raycastParams)
	self.Character = character
	self.PrimaryPart = primaryPart
	self.AlignOrientation = alignOrientation
	self.RaycastParams = raycastParams
end

function SlidingSystem:SetCameraController(cameraController)
	self.CameraController = cameraController
end

function SlidingSystem:SetCharacterController(characterController)
	self.CharacterController = characterController
end

function SlidingSystem:StartSlide(movementDirection, currentCameraAngle)
	if not self.PrimaryPart then
		LogService:Warn("SLIDING", "Cannot start slide - missing character components")
		return false
	end

	if self.AlignOrientation then
		self.AlignOrientation.Responsiveness = Config.Camera.Smoothing.AngleSmoothness or 25
	end

	local wasBuffered = self.IsSlideBuffered
	local airborneBonus = 0

	if wasBuffered then
		local landingBoostConfig = Config.Gameplay.Sliding.LandingBoost
		if landingBoostConfig.Enabled ~= false then
			local airTime = tick() - self.AirborneStartTime
			local fallDistance = self.AirbornePeakY - self.PrimaryPart.Position.Y

			if airTime > landingBoostConfig.MinAirTime and fallDistance > landingBoostConfig.MinFallDistance then
				local _, _, slopeDegrees =
					MovementUtils:CheckGroundedWithSlope(self.Character, self.PrimaryPart, self.RaycastParams)
				local slopeMultiplier
				if slopeDegrees >= landingBoostConfig.SlopeThreshold then
					slopeMultiplier = landingBoostConfig.SlopeBoostMultiplier
				else
					slopeMultiplier = landingBoostConfig.FlatBoostMultiplier
				end

				local baseBonus = fallDistance * landingBoostConfig.BoostMultiplier
				airborneBonus = math.min(baseBonus * slopeMultiplier, landingBoostConfig.MaxBoost)
				LogService:Info("SLIDING", "Buffered slide landing boost", {
					AirTime = airTime,
					FallDistance = fallDistance,
					PeakY = self.AirbornePeakY,
					CurrentY = self.PrimaryPart.Position.Y,
					Bonus = airborneBonus,
					SlopeDegrees = math.floor(slopeDegrees * 10) / 10,
					SlopeMultiplier = slopeMultiplier,
				})
			end
		end
	end

	if not MovementStateManager:TransitionTo(MovementStateManager.States.Sliding) then
		LogService:Warn("SLIDING", "Failed to transition to sliding state")
		return false
	end

	self.LastSlideEndTime = tick()

	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
	local currentHorizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local preservedMomentum = currentHorizontalVelocity.Magnitude * Config.Gameplay.Sliding.StartMomentumPreservation

	local slideDirection
	if movementDirection.Magnitude < 0.001 then
		local lookVector = self.PrimaryPart.CFrame.LookVector
		slideDirection = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
	else
		slideDirection = movementDirection.Unit
	end

	local isHittingWall = MovementUtils:CheckWallStop(self.PrimaryPart, self.RaycastParams, slideDirection)
	if isHittingWall then
		LogService:Debug("SLIDING", "Slide cancelled - sliding into wall")
		return false
	end

	self.IsSliding = true
	self.SlideVelocity = Config.Gameplay.Sliding.InitialVelocity + airborneBonus + preservedMomentum
	self.SlideDirection = slideDirection
	self.OriginalSlideDirection = slideDirection

	if currentHorizontalVelocity.Magnitude < 5 then
		local edgeCheckRay = workspace:Raycast(
			self.PrimaryPart.Position + slideDirection * 2,
			Vector3.new(0, -3, 0),
			self.RaycastParams
		)
		local isAtEdge = (edgeCheckRay == nil)

		local immediateVelocity = slideDirection * self.SlideVelocity

		local initVel = Instance.new("BodyVelocity")
		initVel.Name = "SlideInitVelocity"

		if isAtEdge then
			initVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			initVel.Velocity = Vector3.new(immediateVelocity.X, -10, immediateVelocity.Z)
		else
			initVel.MaxForce = Vector3.new(math.huge, 0, math.huge)
			initVel.Velocity = Vector3.new(immediateVelocity.X, 0, immediateVelocity.Z)
		end
		initVel.Parent = self.PrimaryPart

		if isAtEdge then
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
				immediateVelocity.X,
				math.min(self.PrimaryPart.AssemblyLinearVelocity.Y, -10),
				immediateVelocity.Z
			)
		else
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
				immediateVelocity.X,
				self.PrimaryPart.AssemblyLinearVelocity.Y,
				immediateVelocity.Z
			)
		end

		task.delay(0.1, function()
			if initVel and initVel.Parent then
				initVel:Destroy()
			end
		end)
	end

	local impulseConfig = Config.Gameplay.Sliding.ImpulseSlide
	local hasExistingMomentum = currentHorizontalVelocity.Magnitude > 5
	if impulseConfig and impulseConfig.Enabled and hasExistingMomentum then
		local mass = self.PrimaryPart.AssemblyMass
		local impulseMagnitude = mass * impulseConfig.ImpulsePower
		local impulseVector = slideDirection * impulseMagnitude

		self.PrimaryPart:ApplyImpulse(impulseVector)

		local glideProps = PhysicalProperties.new(0.01, impulseConfig.SlideFriction, 0, 100, 100)
		self.PrimaryPart.CustomPhysicalProperties = glideProps
	end

	if airborneBonus > 0 then
		self:PlayLandingBoostSound()
	end

	self:CreateSlideTrail()

	do
		local template = getMovementTemplate("Slide")
		if template then
			VFXPlayer:Start("Slide", template, self.PrimaryPart)
		end
	end
	FOVController:AddEffect("Slide")

	if wasBuffered then
		local wasFromJumpCancel = self.IsSlideBufferFromJumpCancel
		self.CurrentSlideSkipsCooldown = wasFromJumpCancel
		self.IsSlideBuffered = false

		if wasFromJumpCancel then
			self.SlideBypassCooldown = 0
		end
		self.BufferedSlideDirection = Vector3.new(0, 0, 0)
		self.SlideBufferStartTime = 0
		self.IsSlideBufferFromJumpCancel = false
	end

	if currentCameraAngle then
		self.LastCameraAngle = currentCameraAngle
	elseif self.CameraController then
		local cameraAngles = self.CameraController:GetCameraAngles()
		self.LastCameraAngle = cameraAngles.X
	end
	self.PreviousY = self.PrimaryPart.Position.Y

	local estimatedDeltaTime = 1 / 60
	if self.SlideUpdateConnection then
		estimatedDeltaTime = self.LastKnownDeltaTime or (1 / 60)
	end
	self:ApplySlideVelocity(estimatedDeltaTime)

	self:StartSlideUpdate()

	return true
end

function SlidingSystem:StopSlide(transitionToCrouch, _removeVisualCrouchImmediately, stopReason)
	-- Slope push tech (slide release):
	-- If the player manually cancels a slide while pushing into an uphill slope, give a clean,
	-- one-shot upward/forward pop. This is intentionally simple: no sticky wall states.
	if self.IsSliding and self.PrimaryPart and self.Character and self.RaycastParams then
		local isManualRelease = (stopReason == "ManualRelease" or stopReason == "ManualUncrouchRelease")
		if isManualRelease then
			local slideSpeed = self.SlideVelocity or 0
			if slideSpeed >= 10 then
				local config = Config.Gameplay.Sliding.JumpCancel
				local uphillConfig = config and config.UphillBoost

				if uphillConfig and uphillConfig.Enabled then
					local isGrounded, groundNormal =
						MovementUtils:CheckGroundedWithSlope(self.Character, self.PrimaryPart, self.RaycastParams)

					if isGrounded and groundNormal then
						local up = Vector3.new(0, 1, 0)
						local slopeAngle = math.acos(math.clamp(groundNormal:Dot(up), -1, 1))

						if slopeAngle > (uphillConfig.SlopeThreshold or 0) then
							local direction = self.SlideDirection
							if not direction or direction.Magnitude < 0.01 then
								local look = self.PrimaryPart.CFrame.LookVector
								direction = Vector3.new(look.X, 0, look.Z)
							end

							if direction and direction.Magnitude > 0.01 then
								direction = direction.Unit

								local gravity = Vector3.new(0, -1, 0)
								local downhill = gravity - gravity:Dot(groundNormal) * groundNormal
								if downhill.Magnitude > 0.01 then
									downhill = downhill.Unit

									local alignment = direction:Dot(downhill) -- < 0 means "uphill"
									if alignment <= (uphillConfig.MinUphillAlignment or -0.4) then
										local maxSlopeRadians = math.rad(uphillConfig.MaxSlopeAngle or 50)
										local slopeStrength = math.clamp(slopeAngle / maxSlopeRadians, 0, 1)
										slopeStrength = slopeStrength ^ (uphillConfig.ScalingExponent or 1)

										local slopeForward = direction - direction:Dot(groundNormal) * groundNormal
										if slopeForward.Magnitude > 0.01 then
											slopeForward = slopeForward.Unit
										else
											slopeForward = direction
										end

										local baseHorizontal = math.max(
											slideSpeed * (uphillConfig.HorizontalVelocityScale or 0.35),
											uphillConfig.MinHorizontalVelocity or 8
										)

										local jumpCancelVertical = (uphillConfig.MinVerticalBoost or 50)
											+ ((uphillConfig.MaxVerticalBoost or 70) - (uphillConfig.MinVerticalBoost or 50))
												* (1 - slopeStrength)

										-- Scale down from jump-cancel into a smaller "release pop".
										local releaseVertical = jumpCancelVertical * 0.45
										local releaseHorizontal = baseHorizontal * 0.55

										local v = self.PrimaryPart.AssemblyLinearVelocity
										self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(
											v.X + slopeForward.X * releaseHorizontal,
											math.max(v.Y, releaseVertical),
											v.Z + slopeForward.Z * releaseHorizontal
										)
									end
								end
							end
						end
					end
				end
			end
		end
	end

	self.LastSlideStopTime = tick()
	self.SlideStopDirection = self.SlideDirection
	self.SlideStopVelocity = self.SlideVelocity

	local slideBodyVel = self.PrimaryPart and self.PrimaryPart:FindFirstChild("SlideBodyVelocity")
	if slideBodyVel then
		slideBodyVel:Destroy()
	end

	self.IsSliding = false
	self.SlideVelocity = 0
	self.SlideDirection = Vector3.new(0, 0, 0)
	self.OriginalSlideDirection = Vector3.new(0, 0, 0)

	if self.PrimaryPart then
		self.PrimaryPart.CustomPhysicalProperties = nil
	end

	self.IsAirborne = false
	self.AirborneStartTime = 0
	self.AirborneStartY = 0
	self.AirbornePeakY = 0
	self.WasAirborneLastFrame = false

	RigRotationUtils:ResetRigRotation(self.Character, self.PrimaryPart, true)

	if self.SlideUpdateConnection then
		self.SlideUpdateConnection:Disconnect()
		self.SlideUpdateConnection = nil
	end

	self:RemoveSlideTrail()

	VFXPlayer:Stop("Slide")
	FOVController:RemoveEffect("Slide")

	if self.AlignOrientation then
		self.AlignOrientation.Responsiveness = Config.Camera.Smoothing.AngleSmoothness or 25
	end

	if self.CharacterController then
		self.CharacterController.LastCameraAngles = nil
		self.CharacterController.CameraRotationChanged = true
	end

	if transitionToCrouch then
		MovementStateManager:TransitionTo(MovementStateManager.States.Crouching)
	else
		local CrouchUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("CrouchUtils"))
		if self.Character then
			CrouchUtils:Uncrouch(self.Character)
			CrouchUtils:RemoveVisualCrouch(self.Character)
		end

		local shouldRestoreSprint = false
		if self.CharacterController then
			local autoSprint = Config.Gameplay.Character.AutoSprint
			shouldRestoreSprint = self.CharacterController.IsSprinting or autoSprint
		end

		if shouldRestoreSprint then
			MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
		else
			MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
		end
	end
end

function SlidingSystem:StartSlideUpdate()
	if self.SlideUpdateConnection then
		self.SlideUpdateConnection:Disconnect()
	end

	self.SlideUpdateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:UpdateSlide(deltaTime)
	end)
end

function SlidingSystem:UpdateSlide(deltaTime)
	self.LastKnownDeltaTime = deltaTime

	if self.IsSlideBuffered then
		if self.IsAirborne and self.PrimaryPart then
			self.AirbornePeakY = math.max(self.AirbornePeakY, self.PrimaryPart.Position.Y)
		end

		if self.PrimaryPart and not self:CheckGroundedForSliding() then
			local airborneTime = tick() - self.AirborneStartTime
			local baseDownforce = Config.Gameplay.Character.AirborneSlideDownforce or 600
			local floatDuration = Config.Gameplay.Sliding.FloatDuration or 0.7
			local effectiveDownforce

			if airborneTime < floatDuration then
				local floatMultiplier = Config.Gameplay.Sliding.FloatGravityMultiplier or 0.3
				effectiveDownforce = baseDownforce * floatMultiplier
			else
				local timeAfterFloat = airborneTime - floatDuration
				local progressiveMultiplier = 2 + (timeAfterFloat * 8)
				effectiveDownforce = baseDownforce * math.min(progressiveMultiplier, 10)
			end

			local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
			local newYVelocity = currentVelocity.Y - (effectiveDownforce * deltaTime)
			self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, newYVelocity, currentVelocity.Z)
		end

		return
	end

	if not self.IsSliding or not self.PrimaryPart then
		self:StopSlide(false, nil, "InvalidState")
		return
	end

	local isHittingWall = MovementUtils:CheckWallStop(self.PrimaryPart, self.RaycastParams, self.SlideDirection)
	if isHittingWall then
		LogService:Debug("SLIDING", "Slide stopped - hitting wall during slide")
		self:StopSlide(false, nil, "HitWall")
		return
	end

	local slideConfig = Config.Gameplay.Sliding

	if self.PrimaryPart and VFXPlayer:IsActive("Slide") then
		VFXPlayer:UpdateYaw(
			"Slide",
			self.SlideDirection and self.SlideDirection * 10 or self.PrimaryPart.CFrame.LookVector * 10
		)
	end

	local cappedDeltaTime = deltaTime

	local wasAirborneLastFrame = self.WasAirborneLastFrame
	local isGrounded = self:CheckGroundedForSliding()
	local isAirborne = not isGrounded

	if isAirborne and not wasAirborneLastFrame then
		self.IsAirborne = true
		self.AirborneStartTime = tick()
		self.AirborneStartY = self.PrimaryPart.Position.Y
		self.AirbornePeakY = self.PrimaryPart.Position.Y
	elseif isAirborne and wasAirborneLastFrame then
		self.AirbornePeakY = math.max(self.AirbornePeakY, self.PrimaryPart.Position.Y)
	elseif not isAirborne and wasAirborneLastFrame then
		local airTime = tick() - self.AirborneStartTime
		local fallDistance = self.AirbornePeakY - self.PrimaryPart.Position.Y

		self.HasLandedAfterJumpCancel = self.JumpCancelPerformed

		local landingBoostConfig = Config.Gameplay.Sliding.LandingBoost
		if landingBoostConfig.Enabled ~= false then
			if airTime > landingBoostConfig.MinAirTime and fallDistance > landingBoostConfig.MinFallDistance then
				local _, _, slopeDegrees =
					MovementUtils:CheckGroundedWithSlope(self.Character, self.PrimaryPart, self.RaycastParams)
				local slopeMultiplier
				if slopeDegrees >= landingBoostConfig.SlopeThreshold then
					slopeMultiplier = landingBoostConfig.SlopeBoostMultiplier
				else
					slopeMultiplier = landingBoostConfig.FlatBoostMultiplier
				end

				local baseLandingBoost = fallDistance * landingBoostConfig.BoostMultiplier
				local landingBoost =
					math.min(baseLandingBoost * slopeMultiplier, landingBoostConfig.MaxBoost)

				self.SlideVelocity = self.SlideVelocity + landingBoost

				self:PlayLandingBoostSound()
			end
		end

		local minLandingVelocity = Config.Gameplay.Sliding.MinLandingVelocity or 15
		if self.SlideVelocity < minLandingVelocity then
			self.SlideVelocity = minLandingVelocity
		end
	end

	self.WasAirborneLastFrame = isAirborne

	if isAirborne then
		self:UpdateSlideDirection()

		if self.SlideVelocity > 0 then
			local slideAirDrag = 0.12
			self.SlideVelocity = self.SlideVelocity * (1 - slideAirDrag * cappedDeltaTime)
		end

		local airborneTime = tick() - self.AirborneStartTime
		local baseDownforce = Config.Gameplay.Character.AirborneSlideDownforce or 600
		local floatDuration = Config.Gameplay.Sliding.FloatDuration or 0.7
		local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
		local effectiveDownforce

		if airborneTime < floatDuration then
			local floatMultiplier = Config.Gameplay.Sliding.FloatGravityMultiplier or 0.3
			effectiveDownforce = baseDownforce * floatMultiplier
		else
			local timeAfterFloat = airborneTime - floatDuration
			local progressiveMultiplier = 2 + (timeAfterFloat * 8)
			effectiveDownforce = baseDownforce * math.min(progressiveMultiplier, 10)
		end

		local slideTimeoutConfig = Config.Gameplay.Sliding.SlideTimeout
		if slideTimeoutConfig and slideTimeoutConfig.Enabled and airborneTime > floatDuration then
			if not self.LastDistanceCheckTime
				or (tick() - self.LastDistanceCheckTime) > slideTimeoutConfig.DistanceCheckInterval
			then
				self.LastDistanceCheckTime = tick()

				local currentPos = self.PrimaryPart.Position
				if self.LastCheckPosition then
					local distanceMoved = (currentPos - self.LastCheckPosition).Magnitude

					if distanceMoved < (slideTimeoutConfig.MinMovementDistance * slideTimeoutConfig.DistanceCheckInterval)
					then
						self:StopSlide(false, nil, "AirborneTimeoutStuck")
						return
					end
				end
				self.LastCheckPosition = currentPos
			end
		end

		local newYVelocity = currentVelocity.Y - (effectiveDownforce * cappedDeltaTime)

		self.PrimaryPart.AssemblyLinearVelocity = Vector3.new(currentVelocity.X, newYVelocity, currentVelocity.Z)

		self:UpdateSlideRotation()

		local cameraDirection
		if self.CameraController then
			local cameraAngles = self.CameraController:GetCameraAngles()
			local cameraDirAngle = math.rad(cameraAngles.X)
			cameraDirection = Vector3.new(math.sin(cameraDirAngle), 0, math.cos(cameraDirAngle))
		end

		RigRotationUtils:UpdateRigRotation(
			self.Character,
			self.PrimaryPart,
			self.SlideDirection,
			self.RaycastParams,
			cappedDeltaTime,
			cameraDirection
		)

		self:ApplySlideVelocity(cappedDeltaTime)

		return
	end

	local currentMultiplier = self.SlideVelocity / slideConfig.InitialVelocity
	local frictionAmount = slideConfig.FrictionRate * cappedDeltaTime
	currentMultiplier = math.max(0, currentMultiplier - frictionAmount)
	self.SlideVelocity = currentMultiplier * slideConfig.InitialVelocity

	local multiplierChange = self:CalculateSlopeMultiplierChange(cappedDeltaTime, slideConfig)

	if multiplierChange ~= 0 then
		currentMultiplier = self.SlideVelocity / slideConfig.InitialVelocity
		local newMultiplier =
			math.clamp(currentMultiplier + multiplierChange, 0, slideConfig.MaxVelocity / slideConfig.InitialVelocity)
		self.SlideVelocity = newMultiplier * slideConfig.InitialVelocity
	end

	self.SlideVelocity = math.clamp(self.SlideVelocity, 0, slideConfig.MaxVelocity)

	self:UpdateSlideDirection()

	self:UpdateSlideRotation()

	local cameraDirection
	if self.CameraController then
		local cameraAngles = self.CameraController:GetCameraAngles()
		local cameraDirAngle = math.rad(cameraAngles.X)
		cameraDirection = Vector3.new(math.sin(cameraDirAngle), 0, math.cos(cameraDirAngle))
	end

	RigRotationUtils:UpdateRigRotation(
		self.Character,
		self.PrimaryPart,
		self.SlideDirection,
		self.RaycastParams,
		cappedDeltaTime,
		cameraDirection
	)

	self:ApplySlideVelocity(cappedDeltaTime)

	if self.SlideVelocity <= slideConfig.MinVelocity then
		self:StopSlide(false, nil, "MinVelocity")
		return
	end
end

function SlidingSystem:GetSlideInfo()
	return {
		IsSliding = self.IsSliding,
		IsSlideBuffered = self.IsSlideBuffered,
		SlideVelocity = self.SlideVelocity,
		SlideDirection = self.SlideDirection,
		BufferedSlideDirection = self.BufferedSlideDirection,
		IsAirborne = self.IsAirborne,
		LastSlideEndTime = self.LastSlideEndTime,
		JumpCancelPerformed = self.JumpCancelPerformed,
	}
end

function SlidingSystem:GetCurrentSlideAnimationName()
	if not self.CameraController or not self.IsSliding then
		return "SlidingForward"
	end

	local cameraAngles = self.CameraController:GetCameraAngles()
	local cameraDirAngle = math.rad(cameraAngles.X)
	local cameraDirection = Vector3.new(math.sin(cameraDirAngle), 0, math.cos(cameraDirAngle))

	local animationName = SlideDirectionDetector:GetSlideAnimationName(cameraDirection, self.SlideDirection)

	return animationName
end

function SlidingSystem:Cleanup()
	if self.IsSliding then
		self:StopSlide(false, true, "Cleanup")
	end

	if self.IsSlideBuffered then
		self:CancelSlideBuffer("Character cleanup/despawn")
	end
	if self.IsJumpCancelBuffered then
		self:CancelJumpCancelBuffer()
	end

	self.JumpCancelPerformed = false
	self.HasLandedAfterJumpCancel = false

	self.LastSlideStopTime = 0
	self.SlideStopDirection = Vector3.new(0, 0, 0)
	self.SlideStopVelocity = 0

	if self.Character then
		RigRotationUtils:Cleanup(self.Character)
	end

	self.Character = nil
	self.PrimaryPart = nil
	self.VectorForce = nil
	self.AlignOrientation = nil
	self.RaycastParams = nil
	self.CharacterController = nil
end

return SlidingSystem
