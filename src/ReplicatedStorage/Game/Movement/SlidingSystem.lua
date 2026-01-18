local SlidingSystem = {}

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

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
local VFXRep = require(Locations.Game:WaitForChild("Replication"):WaitForChild("ReplicationModules"))


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
SlidingSystem.SlideSound = nil

SlidingSystem.IsSlideBuffered = false
SlidingSystem.BufferedSlideDirection = Vector3.new(0, 0, 0)
SlidingSystem.SlideBufferStartTime = 0
SlidingSystem.IsSlideBufferFromJumpCancel = false

SlidingSystem.IsJumpCancelBuffered = false
SlidingSystem.BufferedJumpCancelDirection = Vector3.new(0, 0, 0)
SlidingSystem.JumpCancelBufferStartTime = 0

SlidingSystem.JumpCancelPerformed = false
SlidingSystem.HasLandedAfterJumpCancel = false
SlidingSystem.LastJumpCancelTime = 0

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

local function getSlideSoundDefinition()
	local audioConfig = Config.Audio
	return audioConfig and audioConfig.Sounds and audioConfig.Sounds.Movement
		and audioConfig.Sounds.Movement.Slide
end

local function getMovementSoundGroup()
	local existing = SoundService:FindFirstChild("Movement")
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	return nil
end

local function ensureSlideSound(self)
	if self.SlideSound and self.SlideSound.Parent then
		return self.SlideSound
	end

	if not self.PrimaryPart then
		return nil
	end

	local definition = getSlideSoundDefinition()
	if not definition or not definition.Id then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "SlideLoop"
	sound.SoundId = definition.Id
	sound.Volume = definition.Volume or 0.6
	sound.PlaybackSpeed = definition.Pitch or 1.0
	sound.RollOffMode = definition.RollOffMode or Enum.RollOffMode.Linear
	sound.EmitterSize = definition.EmitterSize or 10
	sound.MinDistance = definition.MinDistance or 5
	sound.MaxDistance = definition.MaxDistance or 30
	sound.Looped = true
	sound.SoundGroup = getMovementSoundGroup()
	sound.Parent = self.PrimaryPart

	self.SlideSound = sound
	return sound
end

local function updateSlideSound(self, isGrounded)
	local sound = ensureSlideSound(self)
	if not sound then
		return
	end

	if isGrounded then
		if not sound.IsPlaying then
			sound:Play()
		end
	else
		if sound.IsPlaying then
			sound:Stop()
		end
	end
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

	local currentVelocity = self.PrimaryPart.AssemblyLinearVelocity
	local currentHorizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local slideConfig = Config.Gameplay.Sliding
	local preservedMomentum = currentHorizontalVelocity.Magnitude * slideConfig.StartMomentumPreservation

	local slideDirection
	if movementDirection.Magnitude < 0.001 then
		local cameraDir = nil
		if self.CameraController then
			local cameraAngles = self.CameraController:GetCameraAngles()
			local cameraY = math.rad(cameraAngles.X)
			cameraDir = Vector3.new(math.sin(cameraY), 0, math.cos(cameraY))
		end
		if cameraDir and cameraDir.Magnitude > 0.1 then
			local isGrounded, groundNormal = MovementUtils:CheckGroundedWithSlope(
				self.Character,
				self.PrimaryPart,
				self.RaycastParams
			)
			if isGrounded and groundNormal then
				local projected = cameraDir - cameraDir:Dot(groundNormal) * groundNormal
				if projected.Magnitude > 0.05 then
					slideDirection = projected.Unit
				else
					slideDirection = cameraDir.Unit
				end
			else
				slideDirection = cameraDir.Unit
			end
		else
			local lookVector = self.PrimaryPart.CFrame.LookVector
			local horizontal = Vector3.new(lookVector.X, 0, lookVector.Z)
			if horizontal.Magnitude < 0.1 then
				local vel = self.PrimaryPart.AssemblyLinearVelocity
				horizontal = Vector3.new(vel.X, 0, vel.Z)
			end
			if horizontal.Magnitude < 0.1 then
				horizontal = Vector3.new(0, 0, -1)
			end
			slideDirection = horizontal.Unit
		end
	else
		slideDirection = movementDirection.Unit
	end

	-- Pre-slide ground validation: ensure there's actual surface to slide on.
	local feetPart = CharacterLocations:GetFeet(self.Character) or self.PrimaryPart
	local feetBottom = feetPart.Position - Vector3.new(0, feetPart.Size.Y / 2, 0)
	local groundOffset = slideConfig.GroundCheckOffset or 0.5
	local groundDistance = slideConfig.GroundCheckDistance or 10
	local baseRayOrigin = feetBottom + Vector3.new(0, groundOffset, 0)
	local downRay = workspace:Raycast(baseRayOrigin, Vector3.new(0, -groundDistance, 0), self.RaycastParams)

	local forwardDownRay = nil
	local horizontalDir = Vector3.new(slideDirection.X, 0, slideDirection.Z)
	if horizontalDir.Magnitude > 0.1 then
		horizontalDir = horizontalDir.Unit
		local forwardDownDirection = (horizontalDir * groundDistance) + Vector3.new(0, -groundDistance, 0)
		forwardDownRay = workspace:Raycast(baseRayOrigin, forwardDownDirection, self.RaycastParams)
	end

	if not downRay and not forwardDownRay then
		LogService:Debug("SLIDING", "Slide cancelled - no valid ground detected")
		return false
	end

	local isHittingWall = MovementUtils:CheckWallStop(self.PrimaryPart, self.RaycastParams, slideDirection)
	if isHittingWall then
		LogService:Debug("SLIDING", "Slide cancelled - sliding into wall")
		return false
	end

	if not MovementStateManager:TransitionTo(MovementStateManager.States.Sliding) then
		LogService:Warn("SLIDING", "Failed to transition to sliding state")
		return false
	end

	self.LastSlideEndTime = tick()

	self.IsSliding = true
	local rawSlideVelocity = slideConfig.InitialVelocity + airborneBonus + preservedMomentum
	self.SlideVelocity = math.min(rawSlideVelocity, slideConfig.MaxVelocity)
	self.SlideDirection = slideDirection
	self.OriginalSlideDirection = slideDirection

	updateSlideSound(self, self:CheckGroundedForSliding())

	local impulseConfig = Config.Gameplay.Sliding.ImpulseSlide

	-- Apply low-friction slide properties for ALL slides (prevents V-only "drag" on ramps).
	-- Keep the impulse ("pop") gated by existing momentum.
	if impulseConfig and impulseConfig.Enabled and self.PrimaryPart then
		local glideProps = PhysicalProperties.new(0.01, impulseConfig.SlideFriction, 0, 100, 100)
		self.PrimaryPart.CustomPhysicalProperties = glideProps
	end

	local hasExistingMomentum = currentHorizontalVelocity.Magnitude > 5
	if impulseConfig and impulseConfig.Enabled and hasExistingMomentum then
		local mass = self.PrimaryPart.AssemblyMass
		local impulseMagnitude = mass * impulseConfig.ImpulsePower
		local impulseVector = slideDirection * impulseMagnitude

		self.PrimaryPart:ApplyImpulse(impulseVector)
	end

	if airborneBonus > 0 then
		self:PlayLandingBoostSound()
	end

	self:CreateSlideTrail()

	VFXRep:Fire("All", { Module = "Slide" }, { state = "Start", direction = slideDirection })
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
	-- NOTE: Slide cancel should never inject forward momentum.
	-- Slope-jump tech belongs in jump logic (MovementUtils:ApplySlopeJump), not in StopSlide.

	self.LastSlideStopTime = tick()
	self.SlideStopDirection = self.SlideDirection
	self.SlideStopVelocity = self.SlideVelocity


	-- Clean up both old and new slide force systems
	if self.PrimaryPart then
		-- Legacy + init movers (migration safety)
		local initLinearVel = self.PrimaryPart:FindFirstChild("SlideInitLinearVelocity")
		if initLinearVel then
			initLinearVel:Destroy()
		end
		local slideBodyVel = self.PrimaryPart:FindFirstChild("SlideBodyVelocity")
		if slideBodyVel then
			slideBodyVel:Destroy()
		end
		local slideLinearVel = self.PrimaryPart:FindFirstChild("SlideLinearVelocity")
		if slideLinearVel then
			slideLinearVel:Destroy()
		end
		local slideForce = self.PrimaryPart:FindFirstChild("SlideForce")
		if slideForce then
			slideForce:Destroy()
		end
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

	if self.SlideSound then
		self.SlideSound:Stop()
		self.SlideSound:Destroy()
		self.SlideSound = nil
	end

	RigRotationUtils:ResetRigRotation(self.Character, self.PrimaryPart, true)

	if self.SlideUpdateConnection then
		self.SlideUpdateConnection:Disconnect()
		self.SlideUpdateConnection = nil
	end

	self:RemoveSlideTrail()

	VFXRep:Fire("All", { Module = "Slide" }, { state = "End" })
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

	if self.PrimaryPart then
		VFXRep:Fire("All", { Module = "Slide", Function = "Update" }, {
			direction = self.SlideDirection and self.SlideDirection * 10 or self.PrimaryPart.CFrame.LookVector * 10,
		})
	end

	local cappedDeltaTime = deltaTime

	local wasAirborneLastFrame = self.WasAirborneLastFrame
	local isGrounded = self:CheckGroundedForSliding()
	local isAirborne = not isGrounded

	updateSlideSound(self, isGrounded)

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

	-- Stop slide if too slow - ALWAYS stand up (Moviee behavior).
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
