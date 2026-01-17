local RigRotationUtils = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)

-- Track rig rotation state per character
local RigRotationState = {} -- [character] = { CurrentTilt = 0, TargetTilt = 0, UpdateConnection = nil }

-- Calculate target tilt angle based on slope and slide direction
function RigRotationUtils:CalculateTargetTilt(character, primaryPart, slideDirection, raycastParams, cameraDirection)
	if not Config.Gameplay.Character.RigRotation.Enabled then
		return 0
	end

	-- Get slope information
	local isGrounded, groundNormal, slopeDegrees =
		MovementUtils:CheckGroundedWithSlope(character, primaryPart, raycastParams)

	-- Handle airborne rotation differently
	if not isGrounded then
		return self:CalculateAirborneTilt(primaryPart, slideDirection, cameraDirection)
	end

	-- Check if slope is steep enough to warrant rotation
	if slopeDegrees < Config.Gameplay.Character.RigRotation.MinSlopeForRotation then
		return 0
	end

	-- Calculate slope direction (upward direction of the slope)
	local slopeDirection = Vector3.new(groundNormal.X, 0, groundNormal.Z).Unit
	if slopeDirection.Magnitude < 0.01 then
		return 0 -- Flat ground or near-vertical surface
	end

	-- Determine if we're going uphill or downhill
	-- Dot product > 0 = going uphill (slide direction aligns with slope up direction)
	-- Dot product < 0 = going downhill (slide direction opposite to slope up direction)
	local slideDirectionFlat = Vector3.new(slideDirection.X, 0, slideDirection.Z).Unit
	local directionDot = slideDirectionFlat:Dot(slopeDirection)

	-- Calculate alignment factor (how directly we're moving up/down the slope)
	-- abs(directionDot) = 0 means perpendicular (cross-slope), 1 means directly up/down
	local alignmentFactor = math.abs(directionDot)

	-- Apply falloff for cross-slope movement to prevent awkward transitions
	-- When sliding perpendicular to slope, reduce tilt to near zero
	if alignmentFactor < 0.3 then
		-- Very cross-slope movement - minimal tilt
		alignmentFactor = alignmentFactor * 0.2 -- Reduce by 80%
	end

	-- Calculate tilt amount based on slope steepness AND alignment
	-- Map slope angle to tilt angle (0 to MaxTiltAngle)
	local maxTiltAngle = Config.Gameplay.Character.RigRotation.MaxTiltAngle
	local tiltAmount = (slopeDegrees / 45) * maxTiltAngle * alignmentFactor -- Scale by alignment
	tiltAmount = math.clamp(tiltAmount, 0, maxTiltAngle)

	-- Apply sign based on uphill/downhill
	-- Negative tilt = lean forward (downhill), Positive tilt = lean backward (uphill)
	local targetTilt = -tiltAmount * math.sign(directionDot)

	-- FIX: Invert tilt for backward slides (when character faces opposite of slide direction)
	if cameraDirection then
		local SlideDirectionDetector = require(Locations.Modules.Utils.SlideDirectionDetector)
		local isBackwardSlide = SlideDirectionDetector:ShouldFaceCamera(cameraDirection, slideDirection)
		if isBackwardSlide then
			-- Invert the tilt so downhill looks correct when facing backward
			targetTilt = -targetTilt
		end
	end

	return targetTilt
end

-- Calculate airborne tilt based on vertical velocity
function RigRotationUtils:CalculateAirborneTilt(primaryPart, slideDirection, cameraDirection)
	local airborneConfig = Config.Gameplay.Character.RigRotation.Airborne
	if not airborneConfig.Enabled then
		return 0
	end

	-- Get vertical velocity
	local velocity = primaryPart.AssemblyLinearVelocity
	local verticalVelocity = velocity.Y

	-- Check if velocity is significant enough to warrant rotation
	if math.abs(verticalVelocity) < airborneConfig.MinVerticalVelocity then
		return 0
	end

	-- Calculate tilt based on vertical velocity
	-- Positive Y velocity (going up) = tilt backwards (positive angle)
	-- Negative Y velocity (going down) = tilt forwards (negative angle)
	local maxTiltAngle = airborneConfig.MaxTiltAngle

	-- Normalize vertical velocity to a 0-1 range
	-- Use 80 studs/s as reference for max tilt (terminal velocity is ~200, but we cap at reasonable jump heights)
	local normalizedVelocity = math.clamp(verticalVelocity / 80, -1, 1)

	-- Apply tilt: positive velocity = backward tilt, negative velocity = forward tilt
	local targetTilt = normalizedVelocity * maxTiltAngle

	-- FIX: Invert tilt for backward slides (when character faces opposite of slide direction)
	if cameraDirection and slideDirection then
		local SlideDirectionDetector = require(Locations.Modules.Utils.SlideDirectionDetector)
		local isBackwardSlide = SlideDirectionDetector:ShouldFaceCamera(cameraDirection, slideDirection)
		if isBackwardSlide then
			-- Invert the tilt so airborne tilt looks correct when facing backward
			targetTilt = -targetTilt
		end
	end

	return targetTilt
end

-- Update rig rotation for a character (called each frame during slides)
function RigRotationUtils:UpdateRigRotation(character, primaryPart, slideDirection, raycastParams, deltaTime, cameraDirection)
	if not Config.Gameplay.Character.RigRotation.Enabled then
		return
	end

	local rigHRP = CharacterLocations:GetRigHumanoidRootPart(character)
	if not rigHRP then
		return
	end

	-- Get or create state for this character
	local state = RigRotationState[character]
	if not state then
		state = { CurrentTilt = 0, TargetTilt = 0 }
		RigRotationState[character] = state
	end

	-- If there's an active reset connection, disconnect it (sliding has resumed)
	if state.ResetConnection then
		state.ResetConnection:Disconnect()
		state.ResetConnection = nil
	end

	-- Calculate target tilt (pass camera direction for backward slide detection)
	local targetTilt = self:CalculateTargetTilt(character, primaryPart, slideDirection, raycastParams, cameraDirection)
	state.TargetTilt = targetTilt

	-- Determine if we're airborne to use appropriate smoothness
	local isGrounded = MovementUtils:CheckGroundedWithSlope(character, primaryPart, raycastParams)
	local smoothness
	if not isGrounded and Config.Gameplay.Character.RigRotation.Airborne.Enabled then
		-- Use airborne smoothness (slightly snappier for responsive feel)
		smoothness = Config.Gameplay.Character.RigRotation.Airborne.Smoothness
	else
		-- Use grounded smoothness
		smoothness = Config.Gameplay.Character.RigRotation.Smoothness
	end

	-- Smoothly interpolate current tilt towards target
	local alpha = math.clamp(deltaTime * smoothness, 0, 1)
	state.CurrentTilt = state.CurrentTilt + (targetTilt - state.CurrentTilt) * alpha

	-- Apply rotation to rig
	self:ApplyRigTilt(character, primaryPart, rigHRP, state.CurrentTilt)
end

-- Apply tilt rotation to the rig
function RigRotationUtils:ApplyRigTilt(character, primaryPart, rigHRP, tiltDegrees)
	local RunService = game:GetService("RunService")
	if not RunService:IsClient() then
		return -- Only run on client
	end

	local Players = game:GetService("Players")
	local localPlayer = Players.LocalPlayer
	local isLocalPlayer = localPlayer and character.Name == localPlayer.Name

	-- Slide tilting is now always enabled (can be customized via future UI settings)

	-- Get the character template to calculate base offset
	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not characterTemplate then
		return
	end

	local templateRoot = characterTemplate:FindFirstChild("Root")
	local templateRig = characterTemplate:FindFirstChild("Rig")
	local templateRigHRP = templateRig and templateRig:FindFirstChild("HumanoidRootPart")

	-- Calculate base offset from template
	local baseOffset = CFrame.new()
	if templateRoot and templateRigHRP then
		baseOffset = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
	end

	-- Apply tilt rotation around the X-axis (pitch)
	local tiltRotation = CFrame.Angles(math.rad(tiltDegrees), 0, 0)
	local finalOffset = baseOffset * tiltRotation

	if isLocalPlayer then
		-- LOCAL PLAYER: Update ClientReplicator's RigOffset (BulkMoveTo system)
		local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
		local clientReplicator = ServiceRegistry:GetSystem("ClientReplicator")
		if clientReplicator and clientReplicator.IsActive then
			clientReplicator.RigOffset = finalOffset
		end
	else
		-- OTHER PLAYERS: Directly update welded rig CFrame
		-- Other players' rigs are welded (not using BulkMoveTo), so we set CFrame directly
		if rigHRP then
			rigHRP.CFrame = primaryPart.CFrame * finalOffset
		end
	end
end

-- Reset rig rotation to neutral (called when slide ends)
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
		-- Smoothly return to neutral over multiple frames
		state.TargetTilt = 0

		-- CRITICAL FIX: Start a smooth lerp to 0 instead of relying on UpdateRigRotation
		-- UpdateRigRotation is only called during slides, so we need our own update loop
		if not state.ResetConnection then
			local RunService = game:GetService("RunService")
			state.ResetConnection = RunService.Heartbeat:Connect(function(dt)
				-- Smoothly interpolate towards 0
				local smoothness = Config.Gameplay.Character.RigRotation.Smoothness
				local alpha = math.clamp(dt * smoothness, 0, 1)
				state.CurrentTilt = state.CurrentTilt + (0 - state.CurrentTilt) * alpha

				-- Apply the tilt
				self:ApplyRigTilt(character, primaryPart, rigHRP, state.CurrentTilt)

				-- Once we're close enough to 0, snap and disconnect
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
		-- Immediately snap to neutral
		state.CurrentTilt = 0
		state.TargetTilt = 0
		self:ApplyRigTilt(character, primaryPart, rigHRP, 0)

		-- Disconnect any active reset connection
		if state.ResetConnection then
			state.ResetConnection:Disconnect()
			state.ResetConnection = nil
		end
	end
end

-- Get current tilt angle for a character (for replication)
function RigRotationUtils:GetCurrentTilt(character)
	local state = RigRotationState[character]
	if not state then
		return 0
	end
	-- Return as integer degrees for network efficiency (Int8 = -128 to 127)
	return math.floor(state.CurrentTilt + 0.5) -- Round to nearest integer
end

-- Cleanup rotation state for a character
function RigRotationUtils:Cleanup(character)
	local state = RigRotationState[character]
	if state then
		-- Disconnect any active reset connection
		if state.ResetConnection then
			state.ResetConnection:Disconnect()
			state.ResetConnection = nil
		end
	end
	RigRotationState[character] = nil
end

return RigRotationUtils
