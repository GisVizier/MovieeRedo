--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Blaster.Constants)

local AimAssistEnum = require(script.AimAssistEnum)
local TargetSelector = require(script.TargetSelector)
local AimAdjuster = require(script.AimAdjuster)
local DebugVisualizer = require(script.DebugVisualizer)

export type EasingFunction = (number) -> number

local AimAssist = {}
AimAssist.__index = AimAssist

function AimAssist:enable()
	self.enabled = true

	RunService:BindToRenderStep(Constants.AIM_ASSIST_BIND_NAME_START, Enum.RenderPriority.Camera.Value - 1, function()
		self:startAimAssist()
	end)

	RunService:BindToRenderStep(
		Constants.AIM_ASSIST_BIND_NAME_APPLY,
		Enum.RenderPriority.Camera.Value + 1,
		function(deltaTime: number)
			self:applyAimAssist(deltaTime)
		end
	)
end

function AimAssist:disable()
	self.enabled = false

	RunService:UnbindFromRenderStep(Constants.AIM_ASSIST_BIND_NAME_START)
	RunService:UnbindFromRenderStep(Constants.AIM_ASSIST_BIND_NAME_APPLY)
end

function AimAssist:getGamepadEligibility()
	if UserInputService.PreferredInput ~= Enum.PreferredInput.Gamepad or not self.thumbstickStates then
		return false
	end

	for _, magnitude in self.thumbstickStates do
		if magnitude > Constants.AIM_ASSIST_DEADZONE then
			return true
		end
	end

	return false
end

function AimAssist:updateGamepadEligibility(keyCode: Enum.KeyCode, position: Vector3)
	self.thumbstickStates[keyCode] = Vector2.new(position.X, position.Y).Magnitude
end

function AimAssist:getTouchEligibility(): boolean
	if UserInputService.PreferredInput ~= Enum.PreferredInput.Touch or not self.lastActiveTouch then
		return false
	end

	return self.lastActiveTouch :: number - os.clock() < Constants.AIM_ASSIST_INACTIVITY
end

function AimAssist:updateTouchEligibility()
	self.lastActiveTouch = os.clock()
end

-- Enables debug visualization
function AimAssist:setDebug(debugVisuals: boolean)
	if self.debug == debugVisuals then
		return
	end
	self.debug = debugVisuals

	if self.debug then
		self.debugVisualizer:createVisualElements()
	elseif self.debugVisualizer then
		self.debugVisualizer:destroy()
	end
end

-- Sets the aim-assisted instance
function AimAssist:setSubject(subject: PVInstance)
	self.subject = subject
	self:startAimAssist()
end

-- Sets how aim assist transforms the subject, either rotationally or translationally
function AimAssist:setType(type: AimAssistEnum.AimAssistType)
	self.aimAdjuster:setType(type)
end

function AimAssist:setRange(range: number)
	self.targetSelector:setRange(range)
end

function AimAssist:setFieldOfView(fov: number)
	self.targetSelector:setFieldOfView(fov)
end

-- Sets how aim assist chooses between multiple targets
function AimAssist:setSortingBehavior(behavior: AimAssistEnum.AimAssistSortingBehavior)
	self.targetSelector:setSortingBehavior(behavior)
end

function AimAssist:setIgnoreLineOfSight(ignore: boolean)
	self.targetSelector:setIgnoreLineOfSight(ignore)
end

-- Add a CollectionService tag as target candidates.
-- Optionally, bones are additional target points that can be added as children tags. If omitted, the bounding box center is used.
function AimAssist:addTargetTag(tag: string, bones: { string })
	self.targetSelector:addTargetTag(tag, bones)
end

function AimAssist:removeTargetTag(tag: string)
	self.targetSelector:removeTargetTag(tag)
end

-- Target players. Can optionally add bones in the same way as addTargetTag()
function AimAssist:addPlayerTargets(ignoreLocalPlayer: boolean?, ignoreTeammates: boolean?, bones)
	self.targetSelector:addPlayerTargets(ignoreLocalPlayer, ignoreTeammates, bones)
end

function AimAssist:removePlayerTargets()
	self.targetSelector:removePlayerTargets()
end

-- Sets the strength of an aim assist method
-- Strength is clamped between 0 and 1
function AimAssist:setMethodStrength(method: AimAssistEnum.AimAssistMethod, strength: number)
	self.aimAdjuster:setMethodStrength(method, strength)
end

-- Set a function to adjust aim assist strength based on target attributes
function AimAssist:setEasingFunc(attribute: AimAssistEnum.AimAssistEasingAttribute, func: EasingFunction)
	self.easingFuncs[attribute] = func
end

-- Marks the start of processing that aim assist will modify, recording the current state of the subject.
-- If not called, Aim Assist will affect ALL transformations on the subject CFrame
function AimAssist:startAimAssist()
	if not self.subject then
		return
	end

	self.startingSubjectCFrame = self.subject:GetPivot()
end

-- Applies aim assist to the subject, modifying its CFrame
function AimAssist:applyAimAssist(deltaTime: number?)
	if not self.subject then
		return
	end

	local currCFrame = self.subject:GetPivot()

	local targetResult: TargetSelector.SelectTargetResult? = nil
	if self:getGamepadEligibility() or self:getTouchEligibility() then
		targetResult = self.targetSelector:selectTarget(self.subject)
	end

	if self.debug then
		local allTargetPoints: { TargetSelector.TargetEntry } = self.targetSelector:getAllTargetPoints()
		self.debugVisualizer:update(targetResult, self.targetSelector.fieldOfView, allTargetPoints)
	end

	local adjustmentStrength = 1
	if targetResult then
		for attribute, ease in self.easingFuncs do
			adjustmentStrength *= ease(targetResult[attribute])
		end
	end

	local aimContext: AimAdjuster.AimContext = {
		subjectCFrame = currCFrame,
		startingCFrame = self.startingSubjectCFrame,
		adjustmentStrength = adjustmentStrength,
		targetResult = targetResult,
		deltaTime = deltaTime,
	}

	local newCFrame = self.aimAdjuster:adjustAim(aimContext)

	self.startingSubjectCFrame = newCFrame
	self.subject:PivotTo(newCFrame)
end

function AimAssist.new()
	local self = {
		enabled = false,
		subject = nil,
		debug = false,
		thumbstickStates = {},
	}

	self.targetSelector = TargetSelector.new()
	self.aimAdjuster = AimAdjuster.new()
	self.debugVisualizer = DebugVisualizer.new()
	self.easingFuncs = {}

	self.startingSubjectCFrame = nil

	setmetatable(self, AimAssist)

	return self
end

function AimAssist:destroy()
	if self.debugVisualizer then
		self.debugVisualizer:destroy()
	end
end

return AimAssist
