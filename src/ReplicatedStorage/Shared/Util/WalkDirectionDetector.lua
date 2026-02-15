local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))

local WalkDirectionDetector = {}

function WalkDirectionDetector:GetWalkAnimationType(cameraDirection, movementDirection)
	if not cameraDirection or not movementDirection then
		return "Forward"
	end

	local cameraDirXZ = Vector3.new(cameraDirection.X, 0, cameraDirection.Z).Unit
	local moveDirXZ = Vector3.new(movementDirection.X, 0, movementDirection.Z).Unit

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
		return "Backward"
	end

	return "Left"
end

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
	end

	return "WalkingForward"
end

function WalkDirectionDetector:GetRunAnimationName(cameraDirection, movementDirection)
	local animationType = WalkDirectionDetector:GetWalkAnimationType(cameraDirection, movementDirection)

	if animationType == "Forward" then
		return "RunningForward"
	elseif animationType == "Left" then
		return "RunningLeft"
	elseif animationType == "Right" then
		return "RunningRight"
	elseif animationType == "Backward" then
		return "RunningBackward"
	end

	return "RunningForward"
end

return WalkDirectionDetector
