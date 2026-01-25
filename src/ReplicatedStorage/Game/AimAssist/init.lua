--[[
	AimAssistController (init.lua)
	
	Main controller for the Aim Assist system.
	Manages target selection, aim adjustment, and debug visualization.
	
	Features:
	- Three aim assist methods: Friction, Tracking, Centering
	- Per-weapon configuration
	- Player preference multiplier
	- Gamepad/Touch/Mouse input support
	- Debug visualization mode
	- Cursor lock detection
	
	Usage:
		local AimAssist = require(path.to.AimAssist)
		local aimAssist = AimAssist.new()
		
		aimAssist:setSubject(workspace.CurrentCamera)
		aimAssist:addPlayerTargets(true, true)
		aimAssist:setMethodStrength("friction", 0.3)
		aimAssist:enable()
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AimAssistConfig = require(script.AimAssistConfig)
local AimAssistEnum = require(script.AimAssistEnum)
local TargetSelector = require(script.TargetSelector)
local AimAdjuster = require(script.AimAdjuster)
local DebugVisualizer = require(script.DebugVisualizer)

export type EasingFunction = (number) -> number

local AimAssist = {}
AimAssist.__index = AimAssist

-- =============================================================================
-- ENABLE / DISABLE
-- =============================================================================

function AimAssist:enable()
	if self.enabled then
		return
	end
	self.enabled = true

	local bindNames = AimAssistConfig.BindNames

	-- Bind BEFORE camera (record starting CFrame)
	RunService:BindToRenderStep(bindNames.Start, Enum.RenderPriority.Camera.Value - 1, function()
		self:startAimAssist()
	end)

	-- Bind AFTER camera (apply aim assist adjustments)
	RunService:BindToRenderStep(bindNames.Apply, Enum.RenderPriority.Camera.Value + 1, function(deltaTime: number)
		self:applyAimAssist(deltaTime)
	end)
end

function AimAssist:disable()
	if not self.enabled then
		return
	end
	self.enabled = false

	local bindNames = AimAssistConfig.BindNames

	pcall(function()
		RunService:UnbindFromRenderStep(bindNames.Start)
	end)
	pcall(function()
		RunService:UnbindFromRenderStep(bindNames.Apply)
	end)
end

-- =============================================================================
-- INPUT ELIGIBILITY
-- =============================================================================

function AimAssist:getGamepadEligibility(): boolean
	if UserInputService.PreferredInput ~= Enum.PreferredInput.Gamepad or not self.thumbstickStates then
		return false
	end

	local deadzone = AimAssistConfig.Input.GamepadDeadzone

	for _, magnitude in self.thumbstickStates do
		if magnitude > deadzone then
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

	local timeout = AimAssistConfig.Input.TouchInactivityTimeout
	return (os.clock() - self.lastActiveTouch) < timeout
end

function AimAssist:updateTouchEligibility()
	self.lastActiveTouch = os.clock()
end

function AimAssist:getMouseEligibility(): boolean
	-- For testing: allow mouse input if configured
	return self.allowMouseInput or AimAssistConfig.AllowMouseInput
end

-- Check if cursor is locked (indicates combat/aiming mode)
function AimAssist:isCursorLocked(): boolean
	return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

-- Combined eligibility check
function AimAssist:isEligible(): boolean
	-- Must have cursor locked (combat mode)
	if not self:isCursorLocked() then
		return false
	end
	
	-- Check input type eligibility
	return self:getMouseEligibility() or self:getGamepadEligibility() or self:getTouchEligibility()
end

-- =============================================================================
-- DEBUG
-- =============================================================================

function AimAssist:setDebug(debugEnabled: boolean)
	if self.debug == debugEnabled then
		return
	end
	self.debug = debugEnabled

	if self.debug then
		self.debugVisualizer:createVisualElements()
	elseif self.debugVisualizer then
		self.debugVisualizer:destroy()
	end
end

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

-- Sets the aim-assisted instance (usually the camera)
function AimAssist:setSubject(subject: PVInstance)
	self.subject = subject
	self:startAimAssist()
end

-- Sets how aim assist transforms the subject
function AimAssist:setType(type: AimAssistEnum.AimAssistType)
	self.aimAdjuster:setType(type)
end

function AimAssist:setRange(range: number)
	self.targetSelector:setRange(range)
end

function AimAssist:setMinRange(minRange: number)
	self.targetSelector:setMinRange(minRange)
end

function AimAssist:setFieldOfView(fov: number)
	self.targetSelector:setFieldOfView(fov)
	self.fieldOfView = fov
end

-- Sets how aim assist chooses between multiple targets
function AimAssist:setSortingBehavior(behavior: AimAssistEnum.AimAssistSortingBehavior)
	self.targetSelector:setSortingBehavior(behavior)
end

function AimAssist:setIgnoreLineOfSight(ignore: boolean)
	self.targetSelector:setIgnoreLineOfSight(ignore)
end

-- Allow mouse input for testing
function AimAssist:setAllowMouseInput(allow: boolean)
	self.allowMouseInput = allow
end

-- =============================================================================
-- TARGET MANAGEMENT
-- =============================================================================

-- Add a CollectionService tag as target candidates
function AimAssist:addTargetTag(tag: string, bones: { string }?)
	self.targetSelector:addTargetTag(tag, bones)
end

function AimAssist:removeTargetTag(tag: string)
	self.targetSelector:removeTargetTag(tag)
end

-- Target players
function AimAssist:addPlayerTargets(ignoreLocalPlayer: boolean?, ignoreTeammates: boolean?, bones: { string }?)
	self.targetSelector:addPlayerTargets(ignoreLocalPlayer, ignoreTeammates, bones)
end

function AimAssist:removePlayerTargets()
	self.targetSelector:removePlayerTargets()
end

-- =============================================================================
-- STRENGTH MANAGEMENT
-- =============================================================================

-- Sets the strength of an aim assist method (0-1)
function AimAssist:setMethodStrength(method: AimAssistEnum.AimAssistMethod, strength: number)
	self.aimAdjuster:setMethodStrength(method, strength)
end

function AimAssist:getMethodStrength(method: AimAssistEnum.AimAssistMethod): number
	return self.aimAdjuster:getMethodStrength(method)
end

-- Store base strengths for later restoration (used for ADS boost)
function AimAssist:storeBaseStrengths()
	self.baseStrengths = {
		friction = self.aimAdjuster:getMethodStrength(AimAssistEnum.AimAssistMethod.Friction),
		tracking = self.aimAdjuster:getMethodStrength(AimAssistEnum.AimAssistMethod.Tracking),
		centering = self.aimAdjuster:getMethodStrength(AimAssistEnum.AimAssistMethod.Centering),
	}
end

-- Restore base strengths (after ADS)
function AimAssist:restoreBaseStrengths()
	if self.baseStrengths then
		self.aimAdjuster:setMethodStrength(AimAssistEnum.AimAssistMethod.Friction, self.baseStrengths.friction)
		self.aimAdjuster:setMethodStrength(AimAssistEnum.AimAssistMethod.Tracking, self.baseStrengths.tracking)
		self.aimAdjuster:setMethodStrength(AimAssistEnum.AimAssistMethod.Centering, self.baseStrengths.centering)
	end
end

-- Apply ADS boost multipliers
function AimAssist:applyADSBoost(boostConfig: { Friction: number?, Tracking: number?, Centering: number? }?)
	local boost = boostConfig or AimAssistConfig.Defaults.ADSBoost
	
	if self.baseStrengths then
		self.aimAdjuster:setMethodStrength(
			AimAssistEnum.AimAssistMethod.Friction,
			self.baseStrengths.friction * (boost.Friction or 1)
		)
		self.aimAdjuster:setMethodStrength(
			AimAssistEnum.AimAssistMethod.Tracking,
			self.baseStrengths.tracking * (boost.Tracking or 1)
		)
		self.aimAdjuster:setMethodStrength(
			AimAssistEnum.AimAssistMethod.Centering,
			self.baseStrengths.centering * (boost.Centering or 1)
		)
	end
end

-- =============================================================================
-- EASING FUNCTIONS
-- =============================================================================

-- Set a function to adjust aim assist strength based on target attributes
function AimAssist:setEasingFunc(attribute: AimAssistEnum.AimAssistEasingAttribute, func: EasingFunction)
	self.easingFuncs[attribute] = func
end

-- Set default easing (smooth falloff at FOV edges and distance cutoff)
function AimAssist:applyDefaultEasing()
	local minRange = AimAssistConfig.Defaults.MinRange
	
	-- Distance easing: no aim assist at very close range
	self:setEasingFunc(AimAssistEnum.AimAssistEasingAttribute.Distance, function(distance: number): number
		if distance < minRange then
			return 0
		end
		return 1
	end)
	
	-- Angle easing: reduce strength at edge of FOV
	self:setEasingFunc(AimAssistEnum.AimAssistEasingAttribute.NormalizedAngle, function(normalizedAngle: number): number
		-- normalizedAngle is 0 at center, 1 at edge of FOV
		-- Smooth falloff: full strength at center, 50% at edge
		return 1 - (normalizedAngle * 0.5)
	end)
end

-- =============================================================================
-- CORE LOGIC
-- =============================================================================

-- Marks the start of processing, recording the current state of the subject
function AimAssist:startAimAssist()
	if not self.subject then
		return
	end

	self.startingSubjectCFrame = self.subject:GetPivot()
end

-- Applies aim assist to the subject
function AimAssist:applyAimAssist(deltaTime: number?)
	if not self.subject then
		return
	end

	local currCFrame = self.subject:GetPivot()

	-- Check eligibility
	local targetResult: TargetSelector.SelectTargetResult? = nil
	if self:isEligible() then
		targetResult = self.targetSelector:selectTarget(self.subject)
	end

	-- Debug visualization
	if self.debug then
		local allTargetPoints: { TargetSelector.TargetEntry } = self.targetSelector:getAllTargetPoints()
		self.debugVisualizer:update(targetResult, self.fieldOfView, allTargetPoints)
	end

	-- Calculate adjustment strength from easing functions
	local adjustmentStrength = self:getPlayerStrengthMultiplier()
	if targetResult then
		for attribute, ease in self.easingFuncs do
			local value = targetResult[attribute]
			if value then
				adjustmentStrength *= ease(value)
			end
		end
	end

	-- Build aim context
	local aimContext: AimAdjuster.AimContext = {
		subjectCFrame = currCFrame,
		startingCFrame = self.startingSubjectCFrame,
		adjustmentStrength = adjustmentStrength,
		targetResult = targetResult,
		deltaTime = deltaTime,
	}

	-- Apply aim adjustments
	local newCFrame = self.aimAdjuster:adjustAim(aimContext)

	-- Update subject
	self.startingSubjectCFrame = newCFrame
	self.subject:PivotTo(newCFrame)
end

-- Get player's strength multiplier from attributes
function AimAssist:getPlayerStrengthMultiplier(): number
	local player = Players.LocalPlayer
	if not player then
		return 1
	end
	
	local attrName = AimAssistConfig.PlayerAttributes.Strength
	local strength = player:GetAttribute(attrName)
	
	if strength == nil then
		return AimAssistConfig.PlayerDefaults.Strength
	end
	
	return math.clamp(strength, 0, 1)
end

-- =============================================================================
-- QUICK CONFIGURATION
-- =============================================================================

-- Configure from a weapon's aimAssist table
function AimAssist:configureFromWeapon(weaponAimAssist: {
	enabled: boolean?,
	range: number?,
	minRange: number?,
	fov: number?,
	sortingBehavior: string?,
	friction: number?,
	tracking: number?,
	centering: number?,
	adsBoost: { Friction: number?, Tracking: number?, Centering: number? }?,
}?)
	if not weaponAimAssist then
		return false
	end
	
	-- Apply range settings
	if weaponAimAssist.range then
		self:setRange(weaponAimAssist.range)
	end
	if weaponAimAssist.minRange then
		self:setMinRange(weaponAimAssist.minRange)
	end
	if weaponAimAssist.fov then
		self:setFieldOfView(weaponAimAssist.fov)
	end
	
	-- Apply sorting behavior
	if weaponAimAssist.sortingBehavior then
		self:setSortingBehavior(weaponAimAssist.sortingBehavior)
	end
	
	-- Apply method strengths (multiplied by player preference)
	local playerMult = self:getPlayerStrengthMultiplier()
	
	if weaponAimAssist.friction then
		self:setMethodStrength(AimAssistEnum.AimAssistMethod.Friction, weaponAimAssist.friction * playerMult)
	end
	if weaponAimAssist.tracking then
		self:setMethodStrength(AimAssistEnum.AimAssistMethod.Tracking, weaponAimAssist.tracking * playerMult)
	end
	if weaponAimAssist.centering then
		self:setMethodStrength(AimAssistEnum.AimAssistMethod.Centering, weaponAimAssist.centering * playerMult)
	end
	
	-- Store base strengths for ADS boost
	self:storeBaseStrengths()
	
	-- Store ADS boost config
	self.adsBoostConfig = weaponAimAssist.adsBoost
	
	return true
end

-- =============================================================================
-- CONSTRUCTOR
-- =============================================================================

function AimAssist.new()
	local defaults = AimAssistConfig.Defaults
	
	local self = {
		enabled = false,
		subject = nil,
		debug = false,
		allowMouseInput = AimAssistConfig.AllowMouseInput,
		thumbstickStates = {},
		lastActiveTouch = nil,
		fieldOfView = defaults.FieldOfView,
		baseStrengths = nil,
		adsBoostConfig = nil,
	}

	self.targetSelector = TargetSelector.new()
	self.aimAdjuster = AimAdjuster.new()
	self.debugVisualizer = DebugVisualizer.new()
	self.easingFuncs = {}

	self.startingSubjectCFrame = nil

	setmetatable(self, AimAssist)
	
	-- Apply default easing
	self:applyDefaultEasing()

	return self
end

function AimAssist:destroy()
	self:disable()
	
	if self.debugVisualizer then
		self.debugVisualizer:destroy()
	end
	
	self.subject = nil
	self.targetSelector = nil
	self.aimAdjuster = nil
	self.debugVisualizer = nil
	self.easingFuncs = nil
end

-- Export types and enums for external use
AimAssist.Enum = AimAssistEnum
AimAssist.Config = AimAssistConfig

return AimAssist
