local RigRotationUtils = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local MovementUtils = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementUtils"))
local SlideDirectionDetector = require(Locations.Shared.Util:WaitForChild("SlideDirectionDetector"))
local function getClientReplicator()
	local ok, module = pcall(function()
		return require(Locations.Game:WaitForChild("Replication"):WaitForChild("ClientReplicator"))
	end)
	if ok then
		return module
	end
	return nil
end

local RigRotationState = {}

function RigRotationUtils:CalculateTargetTilt(character, primaryPart, slideDirection, raycastParams, cameraDirection)
	if not Config.Gameplay.Character.RigRotation.Enabled then
		return 0
	end

	local isGrounded, groundNormal, slopeDegrees = MovementUtils:CheckGroundedWithSlope(character, primaryPart, raycastParams)

	if not isGrounded then
		return self:CalculateAirborneTilt(primaryPart, slideDirection, cameraDirection)
	end

	if slopeDegrees < Config.Gameplay.Character.RigRotation.MinSlopeForRotation then
		return 0
	end

	local slopeDirection = Vector3.new(groundNormal.X, 0, groundNormal.Z).Unit
	if slopeDirection.Magnitude < 0.01 then
		return 0
	end

	local slideDirectionFlat = Vector3.new(slideDirection.X, 0, slideDirection.Z).Unit
	local directionDot = slideDirectionFlat:Dot(slopeDirection)

	local alignmentFactor = math.abs(directionDot)
	if alignmentFactor < 0.3 then
		alignmentFactor = alignmentFactor * 0.2
	end

	local maxTiltAngle = Config.Gameplay.Character.RigRotation.MaxTiltAngle
	local tiltAmount = (slopeDegrees / 45) * maxTiltAngle * alignmentFactor
	tiltAmount = math.clamp(tiltAmount, 0, maxTiltAngle)

	local targetTilt = -tiltAmount * math.sign(directionDot)

	if cameraDirection then
		local isBackwardSlide = SlideDirectionDetector:ShouldFaceCamera(cameraDirection, slideDirection)
		if isBackwardSlide then
			targetTilt = -targetTilt
		end
	end

	return targetTilt
end

function RigRotationUtils:CalculateAirborneTilt(primaryPart, slideDirection, cameraDirection)
	local airborneConfig = Config.Gameplay.Character.RigRotation.Airborne
	if not airborneConfig.Enabled then
		return 0
	end

	local velocity = primaryPart.AssemblyLinearVelocity
	local verticalVelocity = velocity.Y

	if math.abs(verticalVelocity) < airborneConfig.MinVerticalVelocity then
		return 0
	end

	local maxTiltAngle = airborneConfig.MaxTiltAngle
	local normalizedVelocity = math.clamp(verticalVelocity / 80, -1, 1)
	local targetTilt = normalizedVelocity * maxTiltAngle

	if cameraDirection and slideDirection then
		local isBackwardSlide = SlideDirectionDetector:ShouldFaceCamera(cameraDirection, slideDirection)
		if isBackwardSlide then
			targetTilt = -targetTilt
		end
	end

	return targetTilt
end

function RigRotationUtils:UpdateRigRotation(character, primaryPart, slideDirection, raycastParams, deltaTime, cameraDirection)
	if not Config.Gameplay.Character.RigRotation.Enabled then
		return
	end

	local rigHRP = CharacterLocations:GetRigHumanoidRootPart(character)
	if not rigHRP then
		return
	end

	local state = RigRotationState[character]
	if not state then
		state = { CurrentTilt = 0, TargetTilt = 0 }
		RigRotationState[character] = state
	end

	if state.ResetConnection then
		state.ResetConnection:Disconnect()
		state.ResetConnection = nil
	end

	local targetTilt = self:CalculateTargetTilt(character, primaryPart, slideDirection, raycastParams, cameraDirection)
	state.TargetTilt = targetTilt

	local isGrounded = MovementUtils:CheckGroundedWithSlope(character, primaryPart, raycastParams)
	local smoothness
	if not isGrounded and Config.Gameplay.Character.RigRotation.Airborne.Enabled then
		smoothness = Config.Gameplay.Character.RigRotation.Airborne.Smoothness
	else
		smoothness = Config.Gameplay.Character.RigRotation.Smoothness
	end

	local alpha = math.clamp(deltaTime * smoothness, 0, 1)
	state.CurrentTilt = state.CurrentTilt + (targetTilt - state.CurrentTilt) * alpha

	self:ApplyRigTilt(character, primaryPart, rigHRP, state.CurrentTilt)
end

function RigRotationUtils:ApplyRigTilt(character, primaryPart, rigHRP, tiltDegrees)
	local RunService = game:GetService("RunService")
	if not RunService:IsClient() then
		return
	end

	local Players = game:GetService("Players")
	local localPlayer = Players.LocalPlayer
	local isLocalPlayer = localPlayer and character.Name == localPlayer.Name

	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not characterTemplate then
		return
	end

	local templateRoot = characterTemplate:FindFirstChild("Root")
	local templateRig = characterTemplate:FindFirstChild("Rig")
	local templateRigHRP = templateRig and templateRig:FindFirstChild("HumanoidRootPart")

	local baseOffset = CFrame.new()
	if templateRoot and templateRigHRP then
		baseOffset = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
	end

	local tiltRotation = CFrame.Angles(math.rad(tiltDegrees), 0, 0)
	local finalOffset = baseOffset * tiltRotation

	if isLocalPlayer then
		local clientReplicator = getClientReplicator()
		if clientReplicator and clientReplicator.IsActive then
			clientReplicator.RigOffset = finalOffset
		end
	else
		if rigHRP then
			rigHRP.CFrame = primaryPart.CFrame * finalOffset
		end
	end
end

function RigRotationUtils:ResetRigRotation(character, primaryPart, smooth)
	local rigHRP = CharacterLocations:GetRigHumanoidRootPart(character)
	if not rigHRP then
		return
	end

	local state = RigRotationState[character]
	if not state then
		return
	end

	if smooth then
		state.TargetTilt = 0

		if not state.ResetConnection then
			local RunService = game:GetService("RunService")
			state.ResetConnection = RunService.Heartbeat:Connect(function(dt)
				local smoothness = Config.Gameplay.Character.RigRotation.Smoothness
				local alpha = math.clamp(dt * smoothness, 0, 1)
				state.CurrentTilt = state.CurrentTilt + (0 - state.CurrentTilt) * alpha

				self:ApplyRigTilt(character, primaryPart, rigHRP, state.CurrentTilt)

				if math.abs(state.CurrentTilt) < 0.1 then
					state.CurrentTilt = 0
					state.TargetTilt = 0
					self:ApplyRigTilt(character, primaryPart, rigHRP, 0)

					if state.ResetConnection then
						state.ResetConnection:Disconnect()
						state.ResetConnection = nil
					end
				end
			end)
		end
	else
		state.CurrentTilt = 0
		state.TargetTilt = 0
		self:ApplyRigTilt(character, primaryPart, rigHRP, 0)

		if state.ResetConnection then
			state.ResetConnection:Disconnect()
			state.ResetConnection = nil
		end
	end
end

function RigRotationUtils:GetCurrentTilt(character)
	local state = RigRotationState[character]
	if not state then
		return 0
	end
	return math.floor(state.CurrentTilt + 0.5)
end

function RigRotationUtils:Cleanup(character)
	local state = RigRotationState[character]
	if state and state.ResetConnection then
		state.ResetConnection:Disconnect()
		state.ResetConnection = nil
	end
	RigRotationState[character] = nil
end

return RigRotationUtils
