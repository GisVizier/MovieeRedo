local WalkDirectionDetector = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)

--[[
	Determines which directional walk animation to play based on the angle
	between camera direction and movement direction.

	Zones:
	- Forward: 0° to ~60° from camera (and 300° to 360°)
	- Right: ~60° to ~120° from camera
	- Backward: ~120° to ~240° from camera (player walks backward)
	- Left: ~240° to ~300° from camera

	Returns: "Forward", "Left", "Right", or "Backward"
]]
function WalkDirectionDetector:GetWalkAnimationType(cameraDirection, movementDirection)
	if not cameraDirection or not movementDirection then
		return "Forward" -- Default fallback
	end

	-- Normalize directions to XZ plane (ignore Y component)
	local cameraDirXZ = Vector3.new(cameraDirection.X, 0, cameraDirection.Z).Unit
	local moveDirXZ = Vector3.new(movementDirection.X, 0, movementDirection.Z).Unit

	-- Calculate camera angle and movement angle
	local cameraAngle = math.atan2(cameraDirXZ.X, cameraDirXZ.Z)
	local moveAngle = math.atan2(moveDirXZ.X, moveDirXZ.Z)

	-- Calculate relative angle (how much the movement direction differs from camera direction)
	local relativeAngle = moveAngle - cameraAngle

	-- Normalize to -180 to 180 range
	while relativeAngle > math.pi do
		relativeAngle = relativeAngle - 2 * math.pi
	end
	while relativeAngle < -math.pi do
		relativeAngle = relativeAngle + 2 * math.pi
	end

	-- Convert to degrees and make positive (0-360 range)
	local angleDegrees = math.deg(relativeAngle)
	if angleDegrees < 0 then
		angleDegrees = angleDegrees + 360
	end

	-- Get angle thresholds from config
	local forwardAngle = Config.Gameplay.Character.DirectionalAnimations.ForwardAngle
	local lateralStart = Config.Gameplay.Character.DirectionalAnimations.LateralStartAngle
	local lateralEnd = Config.Gameplay.Character.DirectionalAnimations.LateralEndAngle
	local backwardStart = Config.Gameplay.Character.DirectionalAnimations.BackwardStartAngle
	local backwardEnd = Config.Gameplay.Character.DirectionalAnimations.BackwardEndAngle

	-- Determine zone based on angle from camera forward direction
	-- 0° = walking in camera direction, 180° = walking backwards from camera
	if angleDegrees <= forwardAngle or angleDegrees >= (360 - forwardAngle) then
		-- Walking with camera (forward)
		return "Forward"
	elseif angleDegrees >= lateralStart and angleDegrees <= lateralEnd then
		-- Right lateral zone (60° to 120°)
		return "Right"
	elseif angleDegrees >= backwardStart and angleDegrees <= backwardEnd then
		-- Walking away from camera (backward)
		return "Backward"
	else
		-- Left lateral zone (240° to 300°)
		return "Left"
	end
end

--[[
	Gets the animation name for the current walk direction.

	Returns: "WalkingForward", "WalkingLeft", "WalkingRight", or "WalkingBackward"
]]
function WalkDirectionDetector:GetWalkAnimationName(cameraDirection, movementDirection)
	local animationType = WalkDirectionDetector:GetWalkAnimationType(cameraDirection, movementDirection)

	if animationType == "Forward" then
		return "WalkingForward"
	elseif animationType == "Left" then
		return "WalkingLeft"
	elseif animationType == "Right" then
		return "WalkingRight"
	elseif animationType == "Backward" then
		return "WalkingBackward"
	else
		return "WalkingForward" -- Fallback
	end
end

return WalkDirectionDetector
