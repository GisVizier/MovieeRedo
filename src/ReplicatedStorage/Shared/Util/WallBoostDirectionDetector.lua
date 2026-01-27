local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))

local WallBoostDirectionDetector = {}

function WallBoostDirectionDetector:GetWallBoostAnimationType(cameraDirection, movementDirection)
	if not cameraDirection or not movementDirection then
		return "Forward"
	end

	local cameraDirXZ = Vector3.new(cameraDirection.X, 0, cameraDirection.Z)
	local moveDirXZ = Vector3.new(movementDirection.X, 0, movementDirection.Z)

	if cameraDirXZ.Magnitude < 0.01 or moveDirXZ.Magnitude < 0.01 then
		return "Forward"
	end

	cameraDirXZ = cameraDirXZ.Unit
	moveDirXZ = moveDirXZ.Unit

	local cameraAngle = math.atan2(cameraDirXZ.X, cameraDirXZ.Z)
	local moveAngle = math.atan2(moveDirXZ.X, moveDirXZ.Z)
	local relativeAngle = moveAngle - cameraAngle

	while relativeAngle > math.pi do
		relativeAngle = relativeAngle - 2 * math.pi
	end
	while relativeAngle < -math.pi do
		relativeAngle = relativeAngle + 2 * math.pi
	end

	local angleDegrees = math.deg(relativeAngle)
	if angleDegrees < 0 then
		angleDegrees = angleDegrees + 360
	end

	local forwardAngle = Config.Gameplay.Character.DirectionalAnimations.ForwardAngle
	local lateralStart = Config.Gameplay.Character.DirectionalAnimations.LateralStartAngle
	local lateralEnd = Config.Gameplay.Character.DirectionalAnimations.LateralEndAngle
	local backwardStart = Config.Gameplay.Character.DirectionalAnimations.BackwardStartAngle
	local backwardEnd = Config.Gameplay.Character.DirectionalAnimations.BackwardEndAngle

	if angleDegrees <= forwardAngle or angleDegrees >= (360 - forwardAngle) then
		return "Forward"
	elseif angleDegrees >= lateralStart and angleDegrees <= lateralEnd then
		return "Right"
	elseif angleDegrees >= backwardStart and angleDegrees <= backwardEnd then
		return "Back"
	end

	return "Left"
end

function WallBoostDirectionDetector:GetWallBoostAnimationName(cameraDirection, movementDirection)
	local animationType = self:GetWallBoostAnimationType(cameraDirection, movementDirection)

	if animationType == "Forward" then
		return "WallBoostForward"
	elseif animationType == "Left" then
		return "WallBoostLeft"
	elseif animationType == "Right" then
		return "WallBoostRight"
	elseif animationType == "Back" then
		return "WallBoostBackward"
	end

	return "WallBoostForward"
end

return WallBoostDirectionDetector
