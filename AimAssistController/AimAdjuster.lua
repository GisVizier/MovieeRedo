--!strict
local TweenService = game:GetService("TweenService")

local TargetSelector = require(script.Parent.TargetSelector)
local AimAssistEnum = require(script.Parent.AimAssistEnum)

export type AimContext = {
	startingCFrame: CFrame,
	subjectCFrame: CFrame,
	adjustmentStrength: number,
	targetResult: TargetSelector.SelectTargetResult?,
	deltaTime: number?,
}

local AimAdjuster = {}
AimAdjuster.__index = AimAdjuster

function AimAdjuster.new()
	local self = {
		type = AimAssistEnum.AimAssistType.Rotational,
		lastTargetInstance = nil :: PVInstance?,
		lastTargetPositions = {},
		subjectVelocity = Vector3.zero :: Vector3,
	}

	self.strengthTable = {
		[AimAssistEnum.AimAssistMethod.Friction] = 0,
		[AimAssistEnum.AimAssistMethod.Tracking] = 0,
		[AimAssistEnum.AimAssistMethod.Centering] = 0,
	}

	setmetatable(self, AimAdjuster)

	return self
end

type AimAdjuster = typeof(AimAdjuster.new())

function AimAdjuster:setType(type: AimAssistEnum.AimAssistType)
	self.type = type
end

-- Strength is clamped between 0 and 1
function AimAdjuster:setMethodStrength(method: AimAssistEnum.AimAssistMethod, strength: number)
	strength = math.clamp(strength, 0, 1)
	self.strengthTable[method] = strength
end

-- Scales down previous subject CFrame transforms
function AimAdjuster:adjustAimFriction(context: AimContext): CFrame
	self = self :: AimAdjuster

	local totalStrength =
		math.clamp(self.strengthTable[AimAssistEnum.AimAssistMethod.Friction] * context.adjustmentStrength, 0, 1)
	if not context.targetResult or totalStrength <= 0 then
		return context.subjectCFrame
	end

	local newCFrame = context.subjectCFrame

	if context.startingCFrame then
		local baseCFrame: CFrame
		if self.type == AimAssistEnum.AimAssistType.Rotational then
			baseCFrame = context.startingCFrame.Rotation + context.subjectCFrame.Position -- CFrame without any rotation input
		elseif self.type == AimAssistEnum.AimAssistType.Translational then
			baseCFrame = context.subjectCFrame.Rotation + context.startingCFrame.Position -- CFrame without any translation input
		end
		newCFrame = context.subjectCFrame:Lerp(baseCFrame, totalStrength)
	end

	return newCFrame
end

-- Keeps the target in the same relative position to the subject
function AimAdjuster:adjustAimTracking(context: AimContext): CFrame
	self = self :: AimAdjuster

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

		if weight <= 0 then
			continue
		end

		if self.type == AimAssistEnum.AimAssistType.Rotational then
			-- Calculate the rotation that represents a perfectly tracked rotational input
			local baseCFrame: CFrame = context.startingCFrame.Rotation + context.subjectCFrame.Position -- CFrame without any rotation input
			local oldRelativeDir: Vector3 = context.startingCFrame:PointToObjectSpace(lastTargetPosition).Unit
			local newRelativeDir: Vector3 = baseCFrame:PointToObjectSpace(targetPosition).Unit
			local idealRotation: CFrame = CFrame.fromRotationBetweenVectors(oldRelativeDir, newRelativeDir)

			-- Adding the ideal rotation to input (no friction effect)
			local identityRotation = CFrame.identity
			local rotation = identityRotation:Lerp(idealRotation, totalStrength * weight)
			newCFrame = newCFrame * rotation
		elseif self.type == AimAssistEnum.AimAssistType.Translational then
			-- Calculate the translation that represent a perfectly tracked translation input
			local baseCFrame: CFrame = context.subjectCFrame.Rotation + context.startingCFrame.Position -- CFrame without any translation input
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

-- Centers the subject onto the target
function AimAdjuster:adjustAimCentering(context: AimContext): CFrame
	self = self :: AimAdjuster

	local totalStrength =
		math.clamp(self.strengthTable[AimAssistEnum.AimAssistMethod.Centering] * context.adjustmentStrength, 0, 1)
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

	-- if deltaTime not provided, do a simple lerp
	if not context.deltaTime then
		local newCFrame = context.subjectCFrame:Lerp(idealCFrame, totalStrength)
		return newCFrame
	end

	-- else, do a smoothDamp
	local smoothTime = 1 - totalStrength
	local maxSpeed = math.huge

	-- TODO: subjectVelocity is initialized as Vector3.zero,
	-- but should be changed to CFrame.identity once TweenService:SmoothDamp is fixed
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

-- Outputs a new CFrame with aim assist applied to subject
function AimAdjuster:adjustAim(context: AimContext): CFrame
	local targetInstance = if context.targetResult then context.targetResult.instance else nil
	if targetInstance ~= self.lastTargetInstance then
		-- New target to track. Reset tracked variables
		self.lastTargetInstance = targetInstance
		self.lastTargetPositions = if context.targetResult then context.targetResult.positions else {}
		self.subjectVelocity = Vector3.zero
	end

	-- Execute methods in order Friction -> Tracking -> Centering
	context.subjectCFrame = self:adjustAimFriction(context)
	context.subjectCFrame = self:adjustAimTracking(context)
	context.subjectCFrame = self:adjustAimCentering(context)

	return context.subjectCFrame
end

return AimAdjuster
