local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))

local SlideDirectionDetector = {}

function SlideDirectionDetector:GetSlideAnimationType(cameraDirection, slideDirection)
	if not cameraDirection or not slideDirection then
		return "Forward"
	end

	local cameraDirXZ = Vector3.new(cameraDirection.X, 0, cameraDirection.Z).Unit
	local slideDirXZ = Vector3.new(slideDirection.X, 0, slideDirection.Z).Unit

	local cameraAngle = math.atan2(cameraDirXZ.X, cameraDirXZ.Z)
	local slideAngle = math.atan2(slideDirXZ.X, slideDirXZ.Z)
	local relativeAngle = slideAngle - cameraAngle

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

	local forwardAngle = Config.Gameplay.Sliding.DirectionalAnimations.ForwardAngle
	local lateralStart = Config.Gameplay.Sliding.DirectionalAnimations.LateralStartAngle
	local lateralEnd = Config.Gameplay.Sliding.DirectionalAnimations.LateralEndAngle
	local backwardStart = Config.Gameplay.Sliding.DirectionalAnimations.BackwardStartAngle
	local backwardEnd = Config.Gameplay.Sliding.DirectionalAnimations.BackwardEndAngle

	if angleDegrees <= forwardAngle or angleDegrees >= (360 - forwardAngle) then
		return "Backward"
	elseif angleDegrees >= lateralStart and angleDegrees <= lateralEnd then
		return "Right"
	elseif angleDegrees >= backwardStart and angleDegrees <= backwardEnd then
		return "Forward"
	else
		return "Left"
	end
end

function SlideDirectionDetector:ShouldFaceCamera(cameraDirection, slideDirection)
	local animationType = SlideDirectionDetector:GetSlideAnimationType(cameraDirection, slideDirection)
	return animationType == "Backward"
end

function SlideDirectionDetector:GetSlideRotationAngle(cameraDirection, slideDirection)
	if SlideDirectionDetector:ShouldFaceCamera(cameraDirection, slideDirection) then
		return math.atan2(slideDirection.X, slideDirection.Z)
	end

	return math.atan2(-slideDirection.X, -slideDirection.Z)
end

function SlideDirectionDetector:GetSlideAnimationName(cameraDirection, slideDirection)
	local animationType = SlideDirectionDetector:GetSlideAnimationType(cameraDirection, slideDirection)

	if animationType == "Forward" then
		return "SlidingForward"
	elseif animationType == "Left" then
		return "SlidingLeft"
	elseif animationType == "Right" then
		return "SlidingRight"
	elseif animationType == "Backward" then
		return "SlidingBackward"
	end

	return "SlidingForward"
end

return SlideDirectionDetector
