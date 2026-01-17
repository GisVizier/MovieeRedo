local SlideDirectionDetector = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)

--[[
	Determines which directional slide animation to play based on the angle
	between camera direction and slide direction.

	Zones:
	- Forward: 0° to ~60° from camera (and 300° to 360°)
	- Right: ~60° to ~120° from camera
	- Backward: ~120° to ~240° from camera (player faces opposite of slide)
	- Left: ~240° to ~300° from camera

	Returns: "Forward", "Left", "Right", or "Backward"
]]
function SlideDirectionDetector:GetSlideAnimationType(cameraDirection, slideDirection)
	if not cameraDirection or not slideDirection then
		return "Forward" -- Default fallback
	end

	-- Normalize directions to XZ plane (ignore Y component)
	local cameraDirXZ = Vector3.new(cameraDirection.X, 0, cameraDirection.Z).Unit
	local slideDirXZ = Vector3.new(slideDirection.X, 0, slideDirection.Z).Unit

	-- Calculate camera angle and slide angle
	local cameraAngle = math.atan2(cameraDirXZ.X, cameraDirXZ.Z)
	local slideAngle = math.atan2(slideDirXZ.X, slideDirXZ.Z)

	-- Calculate relative angle (how much the slide direction differs from camera direction)
	local relativeAngle = slideAngle - cameraAngle

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
	local forwardAngle = Config.Gameplay.Sliding.DirectionalAnimations.ForwardAngle
	local lateralStart = Config.Gameplay.Sliding.DirectionalAnimations.LateralStartAngle
	local lateralEnd = Config.Gameplay.Sliding.DirectionalAnimations.LateralEndAngle
	local backwardStart = Config.Gameplay.Sliding.DirectionalAnimations.BackwardStartAngle
	local backwardEnd = Config.Gameplay.Sliding.DirectionalAnimations.BackwardEndAngle

	-- Determine zone based on angle from camera forward direction
	-- 0° = sliding in camera direction, 180° = sliding backwards from camera
	-- INVERTED: what we think is forward is backward and vice versa
	if angleDegrees <= forwardAngle or angleDegrees >= (360 - forwardAngle) then
		-- This is actually backward - sliding with camera
		return "Backward"
	elseif angleDegrees >= lateralStart and angleDegrees <= lateralEnd then
		-- Right lateral zone (60° to 120°)
		return "Right"
	elseif angleDegrees >= backwardStart and angleDegrees <= backwardEnd then
		-- This is actually forward - sliding away from camera
		return "Forward"
	else
		-- Left lateral zone (240° to 300°)
		return "Left"
	end
end

--[[
	Determines if the slide should face the camera direction instead of slide direction.
	This is only true for backward slides.

	Returns: boolean
]]
function SlideDirectionDetector:ShouldFaceCamera(cameraDirection, slideDirection)
	local animationType = SlideDirectionDetector:GetSlideAnimationType(cameraDirection, slideDirection)
	return animationType == "Backward"
end

--[[
	Gets the appropriate rotation angle for the slide.
	- For forward/lateral slides: rotate to face slide direction
	- For backward slides: rotate to face OPPOSITE of slide direction (mirrors camera)

	Returns: angle in radians
]]
function SlideDirectionDetector:GetSlideRotationAngle(cameraDirection, slideDirection)
	if SlideDirectionDetector:ShouldFaceCamera(cameraDirection, slideDirection) then
		-- Face opposite of slide direction (backward slide)
		-- Negate WITHOUT the Roblox negation = face opposite direction
		return math.atan2(slideDirection.X, slideDirection.Z)
	else
		-- Face slide direction (forward/lateral slide)
		-- Use negative values to match Roblox's coordinate system (face direction of movement)
		return math.atan2(-slideDirection.X, -slideDirection.Z)
	end
end

--[[
	Gets the animation name for the current slide direction.

	Returns: "SlidingForward", "SlidingLeft", "SlidingRight", or "SlidingBackward"
]]
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
	else
		return "SlidingForward" -- Fallback
	end
end

return SlideDirectionDetector
