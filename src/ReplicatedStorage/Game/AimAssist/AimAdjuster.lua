--[[
	AimAdjuster.lua
	
	Applies aim assist adjustments using three methods:
	- Friction: Reduces input sensitivity near targets
	- Tracking: Follows moving targets
	- Centering: Pulls aim toward target center
]]

local TweenService = game:GetService("TweenService")

local TargetSelector = require(script.Parent.TargetSelector)
local AimAssistEnum = require(script.Parent.AimAssistEnum)
local AimAssistConfig = require(script.Parent.AimAssistConfig)

export type AimContext = {
	startingCFrame: CFrame,
	subjectCFrame: CFrame,
	adjustmentStrength: number,
	targetResult: TargetSelector.SelectTargetResult?,
	deltaTime: number?,
}

local AimAdjuster = {}
AimAdjuster.__index = AimAdjuster

-- =============================================================================
-- CONSTRUCTOR
-- =============================================================================

function AimAdjuster.new()
	local defaults = AimAssistConfig.Defaults
	
	local self = {
		type = AimAssistEnum.AimAssistType.Rotational,
		lastTargetInstance = nil :: PVInstance?,
		lastTargetPositions = {},
		subjectVelocity = Vector3.zero :: Vector3,
	}

	self.strengthTable = {
		[AimAssistEnum.AimAssistMethod.Friction] = defaults.Friction or 0,
		[AimAssistEnum.AimAssistMethod.Tracking] = defaults.Tracking or 0,
		[AimAssistEnum.AimAssistMethod.Centering] = defaults.Centering or 0,
	}

	setmetatable(self, AimAdjuster)

	return self
end

type AimAdjuster = typeof(AimAdjuster.new())

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

function AimAdjuster:setType(type: AimAssistEnum.AimAssistType)
	self.type = type
end

-- Strength is clamped between 0 and 1
function AimAdjuster:setMethodStrength(method: AimAssistEnum.AimAssistMethod, strength: number)
	-- Allow values above 1 for tuning headroom, but keep sane bounds for stability.
	strength = math.max(0, strength)
	strength = math.min(strength, 4)
	self.strengthTable[method] = strength
end

function AimAdjuster:getMethodStrength(method: AimAssistEnum.AimAssistMethod): number
	return self.strengthTable[method] or 0
end

-- =============================================================================
-- FRICTION (Slowdown)
-- Scales down previous subject CFrame transforms
-- =============================================================================

function AimAdjuster:adjustAimFriction(context: AimContext): CFrame
	local totalStrength =
		math.clamp(self.strengthTable[AimAssistEnum.AimAssistMethod.Friction] * context.adjustmentStrength, 0, 1)
	
	if not context.targetResult or totalStrength <= 0 then
		return context.subjectCFrame
	end

	local newCFrame = context.subjectCFrame

	if context.startingCFrame then
		local baseCFrame: CFrame
		if self.type == AimAssistEnum.AimAssistType.Rotational then
			-- CFrame without any rotation input
			baseCFrame = context.startingCFrame.Rotation + context.subjectCFrame.Position
		elseif self.type == AimAssistEnum.AimAssistType.Translational then
			-- CFrame without any translation input
			baseCFrame = context.subjectCFrame.Rotation + context.startingCFrame.Position
		end
		newCFrame = context.subjectCFrame:Lerp(baseCFrame, totalStrength)
	end

	return newCFrame
end

-- =============================================================================
-- TRACKING (Sticky Aim)
-- Keeps the target in the same relative position to the subject
-- =============================================================================

function AimAdjuster:adjustAimTracking(context: AimContext): CFrame
	local totalStrength =
		math.clamp(self.strengthTable[AimAssistEnum.AimAssistMethod.Tracking] * context.adjustmentStrength, 0, 1)
	
	if not context.targetResult or totalStrength <= 0 then
		return context.subjectCFrame
	end

	local targetPositions = context.targetResult.positions
	local targetWeights = context.targetResult.weights

	local newCFrame = context.subjectCFrame
	for i = 1, #targetPositions do
		local targetPosition: Vector3 = targetPositions[i]
		local weight: number = targetWeights[i]
		local lastTargetPosition: Vector3 = self.lastTargetPositions[i]

		if weight <= 0 or not lastTargetPosition then
			continue
		end

		if self.type == AimAssistEnum.AimAssistType.Rotational then
			-- Calculate the rotation that represents a perfectly tracked rotational input
			local baseCFrame: CFrame = context.startingCFrame.Rotation + context.subjectCFrame.Position
			local oldRelativeDir: Vector3 = context.startingCFrame:PointToObjectSpace(lastTargetPosition).Unit
			local newRelativeDir: Vector3 = baseCFrame:PointToObjectSpace(targetPosition).Unit
			local idealRotation: CFrame = CFrame.fromRotationBetweenVectors(oldRelativeDir, newRelativeDir)

			-- Adding the ideal rotation to input (no friction effect)
			local identityRotation = CFrame.identity
			local rotation = identityRotation:Lerp(idealRotation, totalStrength * weight)
			newCFrame = newCFrame * rotation
		elseif self.type == AimAssistEnum.AimAssistType.Translational then
			-- Calculate the translation that represents a perfectly tracked translation input
			local baseCFrame: CFrame = context.subjectCFrame.Rotation + context.startingCFrame.Position
			local oldRelativePos: Vector3 = lastTargetPosition - context.startingCFrame.Position
			local newRelativePos: Vector3 = targetPosition - baseCFrame.Position
			local idealTranslation: Vector3 = newRelativePos - oldRelativePos

			local translation: Vector3 = Vector3.new():Lerp(idealTranslation, totalStrength * weight)
			newCFrame = newCFrame + translation
		end
	end

	self.lastTargetPositions = targetPositions

	return newCFrame
end

-- =============================================================================
-- CENTERING (Magnetism)
-- Centers the subject onto the target
-- =============================================================================

function AimAdjuster:adjustAimCentering(context: AimContext): CFrame
	local responseScale = AimAssistConfig.Defaults.CenteringResponseScale or 1
	local totalStrength = math.clamp(
		self.strengthTable[AimAssistEnum.AimAssistMethod.Centering] * context.adjustmentStrength * responseScale,
		0,
		1
	)
	
	if not context.targetResult or totalStrength <= 0 then
		return context.subjectCFrame
	end

	local targetPosition = context.targetResult.bestPosition

	local idealCFrame = context.subjectCFrame
	if self.type == AimAssistEnum.AimAssistType.Rotational then
		idealCFrame = CFrame.lookAt(context.subjectCFrame.Position, targetPosition)
	elseif self.type == AimAssistEnum.AimAssistType.Translational then
		idealCFrame = context.subjectCFrame.Rotation + targetPosition
	end

	-- If deltaTime not provided, do a simple lerp
	if not context.deltaTime then
		local newCFrame = context.subjectCFrame:Lerp(idealCFrame, totalStrength)
		return newCFrame
	end

	-- Legacy response model: stronger feel at high strength.
	local smoothTime = 1 - totalStrength
	local maxSpeed = math.huge

	local newCFrame, newVelocity = TweenService:SmoothDamp(
		context.subjectCFrame,
		idealCFrame,
		self.subjectVelocity,
		smoothTime,
		maxSpeed,
		context.deltaTime
	)

	self.subjectVelocity = newVelocity

	return newCFrame
end

-- =============================================================================
-- MAIN ADJUSTMENT
-- Outputs a new CFrame with aim assist applied to subject
-- =============================================================================

function AimAdjuster:adjustAim(context: AimContext): CFrame
	local targetInstance = if context.targetResult then context.targetResult.instance else nil
	
	if targetInstance ~= self.lastTargetInstance then
		-- New target to track. Reset tracked variables
		self.lastTargetInstance = targetInstance
		self.lastTargetPositions = if context.targetResult then context.targetResult.positions else {}
		self.subjectVelocity = Vector3.zero
	end

	-- Execute methods in order: Friction -> Tracking -> Centering
	context.subjectCFrame = self:adjustAimFriction(context)
	context.subjectCFrame = self:adjustAimTracking(context)
	context.subjectCFrame = self:adjustAimCentering(context)

	return context.subjectCFrame
end

return AimAdjuster
