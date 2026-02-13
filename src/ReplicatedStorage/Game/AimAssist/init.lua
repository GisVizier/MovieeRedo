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

local DEBUG_LOGS = false
local function debugLog(...)
	if DEBUG_LOGS then
		print(...)
	end
end

local function isGamepadInputType(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.Gamepad1
		or inputType == Enum.UserInputType.Gamepad2
		or inputType == Enum.UserInputType.Gamepad3
		or inputType == Enum.UserInputType.Gamepad4
		or inputType == Enum.UserInputType.Gamepad5
		or inputType == Enum.UserInputType.Gamepad6
		or inputType == Enum.UserInputType.Gamepad7
		or inputType == Enum.UserInputType.Gamepad8
end

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

	-- Bind BEFORE CameraController (record starting CFrame)
	-- CameraController runs at Camera + 10, so we run at Camera + 9
	RunService:BindToRenderStep(bindNames.Start, Enum.RenderPriority.Camera.Value + 9, function()
		self:startAimAssist()
	end)

	-- Bind AFTER CameraController (apply aim assist adjustments)
	-- Run after camera update but before viewmodel render so gun follows assisted view
	RunService:BindToRenderStep(bindNames.Apply, Enum.RenderPriority.Camera.Value + 11, function(deltaTime: number)
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
	if not self.thumbstickStates then
		return false
	end

	local deadzone = AimAssistConfig.Input.GamepadDeadzone
	local requireStickMovement = AimAssistConfig.Input.GamepadRequireStickMovement == true
	local timeout = AimAssistConfig.Input.GamepadInactivityTimeout or 1.0

	for _, magnitude in self.thumbstickStates do
		if magnitude > deadzone then
			return true
		end
	end

	if requireStickMovement then
		return false
	end

	local lastType = UserInputService:GetLastInputType()
	if isGamepadInputType(lastType) then
		return true
	end

	if self.lastActiveGamepad and (os.clock() - self.lastActiveGamepad) < timeout then
		return true
	end

	return false
end

function AimAssist:updateGamepadEligibility(keyCode: Enum.KeyCode, position: Vector3)
	self.thumbstickStates[keyCode] = Vector2.new(position.X, position.Y).Magnitude
	self.lastActiveGamepad = os.clock()
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
	-- For PC testing: bypass cursor lock check if mouse input is allowed
	if self:getMouseEligibility() then
		return true
	end
	
	-- For gamepad/touch: require cursor lock (combat mode)
	if not self:isCursorLocked() then
		return false
	end
	
	-- Check gamepad/touch eligibility
	return self:getGamepadEligibility() or self:getTouchEligibility()
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

-- Set camera sensitivity multiplier (from CameraController)
function AimAssist:setSensitivityMultiplier(multiplier: number)
	self.sensitivityMultiplier = math.max(0.1, multiplier)
end

-- Set ADS state (from WeaponController)
function AimAssist:setADSState(isADS: boolean)
	self.isADS = isADS
end

-- Set firing state (from WeaponController)
function AimAssist:setFiringState(isFiring: boolean)
	self.isFiring = isFiring
end

-- Get the target acquired event (for WeaponController to listen to)
function AimAssist:getTargetAcquiredEvent()
	return self.targetAcquiredEvent.Event
end

-- Check if target has been in sight long enough for auto-shoot
function AimAssist:canAutoShoot(): boolean
	if not self.hasTarget then
		return false
	end

	local acquisitionDelay = AimAssistConfig.AutoShoot.AcquisitionDelay
	local timeSinceAcquisition = tick() - self.lastTargetAcquisitionTime

	return timeSinceAcquisition >= acquisitionDelay
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
-- SNAP TO TARGET (ADS Feature)
-- =============================================================================

--[[
	Instantly snaps the camera toward the nearest valid target.
	Call this when ADS is activated for Fortnite-style snap aim.
	
	@param snapConfig: { strength: number?, maxAngle: number? }
		- strength: 0-1, how much to rotate toward target (default 0.5)
		- maxAngle: max degrees to snap (default 15)
	@return boolean: true if snapped to a target, false if no valid target
]]
function AimAssist:snapToTarget(snapConfig: { strength: number?, maxAngle: number? }?): boolean
	if not AimAssistConfig.AllowSnap then
		return false
	end

	if not self.subject or not self.subject:IsA("Camera") then
		return false
	end
	
	-- Get nearest target
	local targetResult = self.targetSelector:selectTarget(self.subject)
	if not targetResult then
		debugLog("[AimAssist] Snap: No valid target found")
		return false
	end
	
	local config = snapConfig or {}
	local strength = config.strength or 0.5
	local maxAngle = config.maxAngle or 15
	
	-- Check if target is within max snap angle
	if targetResult.angle > maxAngle then
		debugLog(string.format("[AimAssist] Snap: Target too far (%.1f° > %.1f° max)", targetResult.angle, maxAngle))
		return false
	end
	
	local camera = self.subject
	local targetPos = targetResult.bestPosition
	local currentCFrame = camera.CFrame
	
	-- Calculate ideal CFrame looking at target
	local idealCFrame = CFrame.lookAt(currentCFrame.Position, targetPos)
	
	-- Calculate actual snap strength based on angle (closer = stronger snap)
	local angleRatio = 1 - (targetResult.angle / maxAngle)
	local actualStrength = strength * angleRatio
	
	-- Interpolate toward target
	local newCFrame = currentCFrame:Lerp(idealCFrame, actualStrength)
	
	-- Apply the snap
	camera.CFrame = newCFrame
	
	-- Calculate how much we rotated
	local rotationDelta = math.deg(math.acos(math.clamp(currentCFrame.LookVector:Dot(newCFrame.LookVector), -1, 1)))
	
	debugLog(string.format(
		"[AimAssist] SNAP! Target: %s | Angle: %.1f° | Strength: %.2f | Rotated: %.1f°",
		targetResult.instance and targetResult.instance.Name or "?",
		targetResult.angle,
		actualStrength,
		rotationDelta
	))
	
	return true
end

--[[
	Performs ADS snap and applies boost in one call.
	Convenience function for weapon ADS activation.
	
	@param snapConfig: { strength: number?, maxAngle: number? }?
	@param boostConfig: { Friction: number?, Tracking: number?, Centering: number? }?
	@return boolean: true if snapped to a target
]]
function AimAssist:activateADS(snapConfig: { strength: number?, maxAngle: number? }?, boostConfig: { Friction: number?, Tracking: number?, Centering: number? }?): boolean
	-- Apply continuous boost
	self:applyADSBoost(boostConfig)
	
	-- Perform snap
	return self:snapToTarget(snapConfig)
end

--[[
	Deactivates ADS - restores base strengths.
]]
function AimAssist:deactivateADS()
	self:restoreBaseStrengths()
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

	-- Cameras use .CFrame, not GetPivot
	if self.subject:IsA("Camera") then
		self.startingSubjectCFrame = self.subject.CFrame
	else
		self.startingSubjectCFrame = self.subject:GetPivot()
	end
end

-- Applies aim assist to the subject
function AimAssist:applyAimAssist(deltaTime: number?)
	if not self.subject then
		return
	end

	-- Get current camera CFrame (cameras don't have GetPivot, use .CFrame)
	local currCFrame
	if self.subject:IsA("Camera") then
		currCFrame = self.subject.CFrame
	else
		currCFrame = self.subject:GetPivot()
	end

	-- Check eligibility
	local targetResult: TargetSelector.SelectTargetResult? = nil
	local isEligible = self:isEligible()
	if isEligible then
		targetResult = self.targetSelector:selectTarget(self.subject)
	end

	-- Debug visualization
	if self.debug then
		local allTargetPoints: { TargetSelector.TargetEntry } = self.targetSelector:getAllTargetPoints()
		self.debugVisualizer:update(targetResult, self.fieldOfView, allTargetPoints)
	end

	-- Track target acquisition for auto-shoot
	-- Only consider target "acquired" if crosshair is ON target (within angle threshold)
	local hadTarget = self.hasTarget
	local hasTargetNow = false

	if targetResult ~= nil then
		local maxAngle = AimAssistConfig.AutoShoot.MaxAngleForAutoShoot
		hasTargetNow = targetResult.angle < maxAngle
	end

	-- Fire signal when target state changes
	if hasTargetNow ~= hadTarget then
		self.hasTarget = hasTargetNow

		if hasTargetNow then
			-- Target acquired (crosshair on target)
			self.lastTargetAcquisitionTime = tick()
			self.targetAcquiredEvent:Fire({
				hasTarget = true,
				targetInfo = {
					instance = targetResult.instance,
					position = targetResult.bestPosition,
					distance = targetResult.distance,
					angle = targetResult.angle,
				}
			})
		else
			-- Target lost (crosshair moved off target or no target in FOV)
			self.targetAcquiredEvent:Fire({
				hasTarget = false,
				targetInfo = nil,
			})
		end
	end

	-- No target = no adjustment needed
	if not targetResult then
		self.startingSubjectCFrame = currCFrame
		return
	end

	-- Calculate state multiplier based on ADS/Firing state
	local stateMultiplier = self:getStateMultiplier()

	-- Calculate adjustment strength from easing functions
	local adjustmentStrength = self:getPlayerStrengthMultiplier() * stateMultiplier * self.sensitivityMultiplier
	for attribute, ease in self.easingFuncs do
		local value = targetResult[attribute]
		if value then
			adjustmentStrength *= ease(value)
		end
	end

	-- Log periodically (every ~1 second)
	self._logTimer = (self._logTimer or 0) + (deltaTime or 0)
	if self._logTimer > 1 then
		self._logTimer = 0
		debugLog(string.format(
			"[AimAssist] TARGET: %s | Angle: %.1f° | Distance: %.1f | Strength: %.2f | Friction: %.2f | Tracking: %.2f | Centering: %.2f",
			targetResult.instance and targetResult.instance.Name or "?",
			targetResult.angle,
			targetResult.distance,
			adjustmentStrength,
			self.aimAdjuster:getMethodStrength("friction"),
			self.aimAdjuster:getMethodStrength("tracking"),
			self.aimAdjuster:getMethodStrength("centering")
		))
	end

	-- Build aim context
	local aimContext: AimAdjuster.AimContext = {
		subjectCFrame = currCFrame,
		startingCFrame = self.startingSubjectCFrame or currCFrame,
		adjustmentStrength = adjustmentStrength,
		targetResult = targetResult,
		deltaTime = deltaTime,
	}

	-- Apply aim adjustments
	local newCFrame = self.aimAdjuster:adjustAim(aimContext)

	-- Calculate how much the CFrame changed
	local positionDelta = (newCFrame.Position - currCFrame.Position).Magnitude
	local rotationDelta = math.deg(math.acos(math.clamp(currCFrame.LookVector:Dot(newCFrame.LookVector), -1, 1)))

	-- Only apply if there's a meaningful change
	if positionDelta > 0.0001 or rotationDelta > 0.001 then
		-- Update camera (cameras use .CFrame, not PivotTo)
		if self.subject:IsA("Camera") then
			self.subject.CFrame = newCFrame
		else
			self.subject:PivotTo(newCFrame)
		end
		
		-- Log when actually applying adjustment
		if self._logTimer == 0 then
			debugLog(string.format("[AimAssist] APPLIED: Rotation delta = %.3f°", rotationDelta))
		end
	end

	-- Update starting CFrame for next frame
	self.startingSubjectCFrame = newCFrame
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

-- Get state multiplier based on ADS/Firing state
function AimAssist:getStateMultiplier(): number
	local stateMultipliers = AimAssistConfig.StateMultipliers

	-- ADS + Firing (strongest, then adsBoost is applied on top)
	if self.isADS and self.isFiring then
		return stateMultipliers.ADSFiring
	end

	-- ADS only
	if self.isADS then
		return stateMultipliers.ADS
	end

	-- Firing only
	if self.isFiring then
		return stateMultipliers.Firing
	end

	-- Idle (gentlest)
	return stateMultipliers.Idle
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
	if AimAssistConfig.SmoothPullOnly then
		local smoothCentering = weaponAimAssist.centering
			or weaponAimAssist.tracking
			or weaponAimAssist.friction
			or AimAssistConfig.Defaults.Centering
		smoothCentering = math.clamp(smoothCentering * 1.35, 0.3, 0.85)
		self:setMethodStrength(AimAssistEnum.AimAssistMethod.Friction, 0)
		self:setMethodStrength(AimAssistEnum.AimAssistMethod.Tracking, 0)
		self:setMethodStrength(AimAssistEnum.AimAssistMethod.Centering, smoothCentering)
		self:setIgnoreLineOfSight(false)
	else
		if weaponAimAssist.friction then
			self:setMethodStrength(AimAssistEnum.AimAssistMethod.Friction, weaponAimAssist.friction)
		end
		if weaponAimAssist.tracking then
			self:setMethodStrength(AimAssistEnum.AimAssistMethod.Tracking, weaponAimAssist.tracking)
		end
		if weaponAimAssist.centering then
			self:setMethodStrength(AimAssistEnum.AimAssistMethod.Centering, weaponAimAssist.centering)
		end
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
		lastActiveGamepad = nil,
		lastActiveTouch = nil,
		fieldOfView = defaults.FieldOfView,
		baseStrengths = nil,
		adsBoostConfig = nil,

		-- State tracking for tiered assist
		isADS = false,
		isFiring = false,

		-- Sensitivity scaling
		sensitivityMultiplier = 1.0,

		-- Auto-shoot tracking
		hasTarget = false,
		lastTargetAcquisitionTime = 0,
		targetAcquiredEvent = Instance.new("BindableEvent"),
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

	if self.targetAcquiredEvent then
		self.targetAcquiredEvent:Destroy()
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
