local WallBoostDirectionDetector = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)

--[[
	Determines which directional wall boost animation to play based on the player's
	movement input direction relative to the camera (same as walking animations).

	Zones:
	- Forward: Moving forward or backward (0° to ~60° and 300° to 360°, or 120° to 240°)
	- Right: Moving right (60° to 120°)
	- Left: Moving left (240° to 300°)

	Returns: "Forward", "Left", or "Right"
]]
function WallBoostDirectionDetector:GetWallBoostAnimationType(cameraDirection, movementDirection)
	if not cameraDirection or not movementDirection then
		return "Forward" -- Default fallback
	end

	-- Normalize directions to XZ plane (ignore Y component)
	local cameraDirXZ = Vector3.new(cameraDirection.X, 0, cameraDirection.Z)
	local moveDirXZ = Vector3.new(movementDirection.X, 0, movementDirection.Z)

	-- Handle zero vectors
	if cameraDirXZ.Magnitude < 0.01 or moveDirXZ.Magnitude < 0.01 then
		return "Forward" -- Default fallback
	end

	cameraDirXZ = cameraDirXZ.Unit
	moveDirXZ = moveDirXZ.Unit

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

	-- Get angle thresholds from config (same as walking animations)
	local forwardAngle = Config.Gameplay.Character.DirectionalAnimations.ForwardAngle
	local lateralStart = Config.Gameplay.Character.DirectionalAnimations.LateralStartAngle
	local lateralEnd = Config.Gameplay.Character.DirectionalAnimations.LateralEndAngle
	local backwardStart = Config.Gameplay.Character.DirectionalAnimations.BackwardStartAngle
	local backwardEnd = Config.Gameplay.Character.DirectionalAnimations.BackwardEndAngle

	-- Determine zone based on angle from camera forward direction (same logic as walk animations)
	-- Forward/Backward both use "Forward" animation
	if angleDegrees <= forwardAngle or angleDegrees >= (360 - forwardAngle) then
		-- Moving with camera (forward)
		return "Forward"
	elseif angleDegrees >= lateralStart and angleDegrees <= lateralEnd then
		-- Right lateral zone (60° to 120°)
		return "Right"
	elseif angleDegrees >= backwardStart and angleDegrees <= backwardEnd then
		-- Moving away from camera (backward, but uses Forward animation)
		return "Forward"
	else
		-- Left lateral zone (240° to 300°)
		return "Left"
	end
end

--[[
	Gets the animation name for the current wall boost direction.

	Returns: "WallBoostForward", "WallBoostLeft", or "WallBoostRight"
]]
function WallBoostDirectionDetector:GetWallBoostAnimationName(cameraDirection, movementDirection)
	local animationType = self:GetWallBoostAnimationType(cameraDirection, movementDirection)

	if animationType == "Forward" then
		return "WallBoostForward"
	elseif animationType == "Left" then
		return "WallBoostLeft"
	elseif animationType == "Right" then
		return "WallBoostRight"
	else
		return "WallBoostForward" -- Fallback
	end
end

return WallBoostDirectionDetector
