--[[
	R6IKSolver — Production R6 Inverse Kinematics (Local Only)
	============================================================

	2-joint Law of Cosines solver for R6 rigs.
	Simulates upper+lower segments on single-piece R6 limbs.

	FEATURES:
	  • Animation-safe (.Transform zeroed on IK-controlled joints)
	  • Pole vector support (elbow/knee direction control)
	  • Per-joint smoothing (weight)
	  • Angle clamping per joint
	  • Torso pitch (aim up/down)
	  • Per-limb enable/disable + clean reset

	USAGE:
	  local R6IKSolver = require(path.to.R6IKSolver)
	  local ik = R6IKSolver.new(character)  -- call ONCE per character

	  -- Every frame:
	  ik:setArmTarget("Right", position, polePosition)
	  ik:setLegTarget("Left", footPosition, kneePole)
	  ik:setTorsoPitch(radiansFromCamera)
	  ik:update(dt)

	  -- Disable / restore:
	  ik:setEnabled("RightArm", false)
	  ik:destroy()

	MOTOR6D MATH:
	  Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()

	  update() zeros .Transform on IK-controlled joints each frame,
	  so the equation simplifies to:
	    Part1.CFrame = Part0.CFrame * C0 * C1:Inverse()

	  C0 is computed as:
	    C0 = Part0⁻¹ * desiredWorldCF * C1
]]

local PI      = math.pi
local HALF_PI = PI / 2
local CLAMP   = math.clamp
local ACOS    = math.acos
local ABS     = math.abs
local MAX     = math.max
local MIN     = math.min
local CF      = CFrame.new
local ANGLES  = CFrame.Angles
local V3      = Vector3.new

---------------------------------------------------------------------------
-- Safe acos (clamps to [-1,1] to prevent NaN)
---------------------------------------------------------------------------
local function safeAcos(x: number): number
	return ACOS(CLAMP(x, -1, 1))
end

---------------------------------------------------------------------------
-- 2-Joint IK Solver (Law of Cosines)
--
-- originCF:   CFrame at chain root (shoulder/hip)
-- targetPos:  Vector3 end-effector goal
-- l1, l2:     upper/lower segment lengths
-- poleVector: optional Vector3 world pos for elbow/knee direction
--
-- Returns: planeCF, angle1 (shoulder/hip), angle2 (elbow/knee)
---------------------------------------------------------------------------
local function solveTwoJointIK(originCF, targetPos, l1, l2, poleVector)
	local localized     = originCF:PointToObjectSpace(targetPos)
	local localizedUnit = localized.Unit
	local l3            = localized.Magnitude

	-- Rolled plane CFrame (natural shoulder/hip rotation)
	local axis  = V3(0, 0, -1):Cross(localizedUnit)
	local angle = safeAcos(-localizedUnit.Z)

	-- Degenerate axis guard (target directly ahead or behind)
	if axis.Magnitude < 0.001 then
		axis = (angle >= PI * 0.99) and V3(-1, 0, 0) or V3(0, 0, -1)
	end

	local planeCF = originCF * CFrame.fromAxisAngle(axis, angle)

	-- Pole vector: rotate the solve plane so the bend aims at poleVector
	if poleVector then
		local aimDir = targetPos - originCF.Position
		if aimDir.Magnitude > 0.001 then
			aimDir = aimDir.Unit
			local poleDir   = poleVector - originCF.Position
			local projected = poleDir - aimDir * poleDir:Dot(aimDir)

			if projected.Magnitude > 0.001 then
				local projUnit  = projected.Unit
				local currentUp = planeCF.UpVector
				local dot       = CLAMP(currentUp:Dot(projUnit), -1, 1)
				local cross     = currentUp:Cross(projUnit)
				local sign      = cross:Dot(aimDir) >= 0 and 1 or -1
				planeCF         = planeCF * ANGLES(0, 0, sign * safeAcos(dot))
			end
		end
	end

	-- Case 1: too close (fold limb fully)
	if l3 < ABS(l1 - l2) then
		return planeCF * CF(0, 0, MAX(l2, l1) - MIN(l2, l1) - l3), -HALF_PI, PI

	-- Case 2: too far (fully extend)
	elseif l3 > l1 + l2 then
		return planeCF, HALF_PI, 0

	-- Case 3: reachable (solve triangle angles)
	else
		local a1 = -safeAcos((-(l2*l2) + (l1*l1) + (l3*l3)) / (2*l1*l3))
		local a2 =  safeAcos(( (l2*l2) - (l1*l1) + (l3*l3)) / (2*l2*l3))
		return planeCF, a1 + HALF_PI, a2 - a1
	end
end

---------------------------------------------------------------------------
-- World CFrame → Motor6D C0
--
-- Motor6D equation:  Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
--
-- We zero .Transform on IK-controlled joints each frame (in update()), so:
--   Part1.CFrame = Part0.CFrame * C0 * identity * C1:Inverse()
--                = Part0.CFrame * C0 * C1:Inverse()
--
-- Solving for C0:  C0 = Part0⁻¹ * desired * C1
---------------------------------------------------------------------------
local function worldCFrameToC0(motor, worldCF)
	return motor.Part0.CFrame:Inverse() * worldCF * motor.C1
end

---------------------------------------------------------------------------
-- MODULE
---------------------------------------------------------------------------
local R6IKSolver = {}
R6IKSolver.__index = R6IKSolver

local DEFAULT_CONFIG = {
	smoothing           = 0.3,     -- global lerp alpha per frame (0=frozen, 1=snap)

	armSegments         = { upper = 1, lower = 1 },
	legSegments         = { upper = 1, lower = 1 },

	armClamp = {
		joint1 = { -PI, PI },       -- shoulder: full range default
		joint2 = { -PI, PI },       -- elbow: full range default
	},
	legClamp = {
		joint1 = { -1.2, 1.8 },    -- hip: restrict backward bend
		joint2 = { -2.5, 0.1 },    -- knee: bends mostly one way
	},

	torsoPitchClamp     = { -0.8, 0.8 },  -- ±46° vertical aim
	torsoPitchSmoothing = 0.2,
}

---------------------------------------------------------------------------
-- Deep merge (2 levels)
---------------------------------------------------------------------------
local function merge(def, over)
	local out = {}
	for k, v in pairs(def) do
		if type(v) == "table" then
			out[k] = {}
			local ov = (over and over[k]) or {}
			for k2, v2 in pairs(v) do
				if type(v2) == "table" then
					out[k][k2] = {}
					local ov2 = ov[k2] or {}
					for k3, v3 in pairs(v2) do
						out[k][k2][k3] = ov2[k3] ~= nil and ov2[k3] or v3
					end
				else
					out[k][k2] = ov[k2] ~= nil and ov[k2] or v2
				end
			end
		else
			out[k] = (over and over[k] ~= nil) and over[k] or v
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Constructor — call ONCE per character
---------------------------------------------------------------------------
function R6IKSolver.new(character: Model, config: {[string]: any}?)
	assert(character and character:FindFirstChild("Torso"),
		"R6IKSolver.new: needs an R6 character with a Torso")

	local self = setmetatable({}, R6IKSolver)
	self.config = merge(DEFAULT_CONFIG, config)

	-- Cache parts
	self.character = character
	self.torso     = character.Torso
	self.hrp       = character.HumanoidRootPart
	self.humanoid  = character:FindFirstChildOfClass("Humanoid")

	self.parts = {
		["Left Arm"]  = character["Left Arm"],
		["Right Arm"] = character["Right Arm"],
		["Left Leg"]  = character["Left Leg"],
		["Right Leg"] = character["Right Leg"],
	}

	-- Cache motors
	self.motors = {
		["Left Shoulder"]  = self.torso["Left Shoulder"],
		["Right Shoulder"] = self.torso["Right Shoulder"],
		["Left Hip"]       = self.torso["Left Hip"],
		["Right Hip"]      = self.torso["Right Hip"],
		["RootJoint"]      = self.hrp["RootJoint"],
	}

	-- Snapshot original C0/C1 (reference frame, before IK or animation)
	self.origC0 = {}
	self.origC1 = {}
	for name, motor in pairs(self.motors) do
		self.origC0[name] = motor.C0
		self.origC1[name] = motor.C1
	end

	-- Interpolation state: what we're lerping toward / currently at
	self.targetC0  = {}
	self.currentC0 = {}
	for name, motor in pairs(self.motors) do
		self.targetC0[name]  = motor.C0
		self.currentC0[name] = motor.C0
	end

	-- Per-limb state
	-- Valid keys: "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Torso"
	self.enabled       = { LeftArm = false, RightArm = false, LeftLeg = false, RightLeg = false, Torso = false }
	self.limbSmoothing = {}  -- per-limb alpha override (nil = global)
	self.limbOverride  = {}  -- per-limb override (reserved for future use)

	-- IK targets set each frame via setArmTarget / setLegTarget
	self._targets = {
		LeftArm  = { position = nil, pole = nil },
		RightArm = { position = nil, pole = nil },
		LeftLeg  = { position = nil, pole = nil },
		RightLeg = { position = nil, pole = nil },
	}

	-- Cache collar attachments on the rig's Torso for IK origin
	-- Expected: "LeftCollarAttachment" and "RightCollarAttachment" in Torso
	self.shoulderAttachments = {
		Left  = self.torso:FindFirstChild("LeftCollarAttachment"),
		Right = self.torso:FindFirstChild("RightCollarAttachment"),
	}

	-- Torso pitch
	self._pitchTarget  = 0
	self._pitchCurrent = 0

	self._destroyed = false
	return self
end

---------------------------------------------------------------------------
-- CONFIGURATION
---------------------------------------------------------------------------

--- Enable or disable IK on a limb.
--- limbName: "LeftArm" | "RightArm" | "LeftLeg" | "RightLeg" | "Torso"
function R6IKSolver:setEnabled(limbName: string, on: boolean)
	self.enabled[limbName] = on

	-- When disabling, snap motor back to original
	if not on then
		local motorMap = {
			LeftArm  = "Left Shoulder",
			RightArm = "Right Shoulder",
			LeftLeg  = "Left Hip",
			RightLeg = "Right Hip",
		}
		local m = motorMap[limbName]
		if m and self.motors[m] then
			self.targetC0[m]      = self.origC0[m]
			self.currentC0[m]     = self.origC0[m]
			self.motors[m].C0     = self.origC0[m]
		end
		if limbName == "Torso" then
			self._pitchTarget  = 0
			self._pitchCurrent = 0
			local rj = self.motors["RootJoint"]
			if rj then rj.C0 = self.origC0["RootJoint"] end
		end
	end
end

--- Per-limb smoothing override. nil = use config.smoothing.
function R6IKSolver:setLimbSmoothing(limbName: string, alpha: number?)
	self.limbSmoothing[limbName] = alpha
end

--- Per-limb override flag (reserved for future use).
function R6IKSolver:setLimbOverrideAnimation(limbName: string, override: boolean?)
	self.limbOverride[limbName] = override
end

--- Change arm segment lengths at runtime.
function R6IKSolver:setArmSegments(upper: number, lower: number)
	self.config.armSegments.upper = upper
	self.config.armSegments.lower = lower
end

--- Change leg segment lengths at runtime.
function R6IKSolver:setLegSegments(upper: number, lower: number)
	self.config.legSegments.upper = upper
	self.config.legSegments.lower = lower
end

---------------------------------------------------------------------------
-- TARGET SETTERS — call each frame before :update()
---------------------------------------------------------------------------

--- Set arm IK target.
--- side: "Left" | "Right"
--- position: Vector3 world position for the hand/end-effector
--- poleVector: optional Vector3 world position for elbow aim direction
function R6IKSolver:setArmTarget(side: string, position: Vector3, poleVector: Vector3?)
	local key = side .. "Arm"
	self._targets[key].position = position
	self._targets[key].pole     = poleVector
	if not self.enabled[key] then self.enabled[key] = true end
end

--- Set leg IK target.
--- side: "Left" | "Right"
--- position: Vector3 world position for the foot
--- poleVector: optional Vector3 world position for knee aim direction
function R6IKSolver:setLegTarget(side: string, position: Vector3, poleVector: Vector3?)
	local key = side .. "Leg"
	self._targets[key].position = position
	self._targets[key].pole     = poleVector
	if not self.enabled[key] then self.enabled[key] = true end
end

--- Set torso pitch in radians. Positive = look up, negative = look down.
function R6IKSolver:setTorsoPitch(radians: number)
	local c = self.config.torsoPitchClamp
	self._pitchTarget = CLAMP(radians, c[1], c[2])
	if not self.enabled.Torso then self.enabled.Torso = true end
end

---------------------------------------------------------------------------
-- INTERNAL: Arm IK solve
---------------------------------------------------------------------------
function R6IKSolver:_solveArm(side: string)
	local t = self._targets[side .. "Arm"]
	if not t.position then return end

	local mName = side .. " Shoulder"
	local motor = self.motors[mName]
	if not motor or not motor.Part0 or not motor.Part1 then return end

	local c0  = self.origC0[mName]
	local c1  = self.origC1[mName]
	local l1  = self.config.armSegments.upper
	local l2  = self.config.armSegments.lower
	local cl  = self.config.armClamp

	-- Origin at shoulder joint — use shoulder attachment if available, else fallback to C0/C1 math
	local shoulderAttach = self.shoulderAttachments[side]
	local originCF
	if shoulderAttach then
		originCF = shoulderAttach.WorldCFrame
	else
		originCF = self.torso.CFrame * c0
		if side == "Left" then
			originCF = originCF * CF(0, 0, c1.X)
		else
			originCF = originCF * CF(0, 0, -c1.X)
		end
	end

	-- Solve
	local planeCF, a1, a2 = solveTwoJointIK(originCF, t.position, l1, l2, t.pole)

	-- Clamp angles
	a1 = CLAMP(a1, cl.joint1[1], cl.joint1[2])
	a2 = CLAMP(a2, cl.joint2[1], cl.joint2[2])

	-- Build the virtual chain end CFrame (where the visible R6 limb goes)
	local limb   = self.parts[side .. " Arm"]
	local height = limb and limb.Size.Y or 2

	local shoulderCF = planeCF * ANGLES(a1, 0, 0) * CF(0, -l1 * 0.5, 0)
	local elbowCF    = shoulderCF
		* CF(0, -l1 * 0.5, 0)
		* ANGLES(a2, 0, 0)
		* CF(0, -l2 * 0.5, 0)
		* CF(0, (height - l2) * 0.5, 0)  -- center the visible part

	self.targetC0[mName] = worldCFrameToC0(motor, elbowCF)
end

---------------------------------------------------------------------------
-- INTERNAL: Leg IK solve
---------------------------------------------------------------------------
function R6IKSolver:_solveLeg(side: string)
	local t = self._targets[side .. "Leg"]
	if not t.position then return end

	local mName = side .. " Hip"
	local motor = self.motors[mName]
	if not motor or not motor.Part0 or not motor.Part1 then return end

	local c0  = self.origC0[mName]
	local c1  = self.origC1[mName]
	local l1  = self.config.legSegments.upper
	local l2  = self.config.legSegments.lower
	local cl  = self.config.legClamp

	-- R6 hips have a 90° rotation baked in that we must account for
	local hipRot = side == "Left" and ANGLES(0, HALF_PI, 0) or ANGLES(0, -HALF_PI, 0)
	local originCF = self.torso.CFrame * c0 * hipRot * CF(-c1.X, 0, 0)

	-- Leg-specific solve: inverted cross product for natural downward bend
	local localized     = originCF:PointToObjectSpace(t.position)
	local localizedUnit = localized.Unit
	local l3            = localized.Magnitude

	local axis  = V3(0, 0, -1):Cross(-localizedUnit)
	local angle = safeAcos(-localizedUnit.Z)
	if axis.Magnitude < 0.001 then
		axis = (angle >= PI * 0.99) and V3(-1, 0, 0) or V3(0, 0, -1)
	end
	local planeCF = originCF * CFrame.fromAxisAngle(axis, angle):Inverse()

	-- Pole vector for knee direction
	if t.pole then
		local aimDir = t.position - originCF.Position
		if aimDir.Magnitude > 0.001 then
			aimDir = aimDir.Unit
			local poleDir   = t.pole - originCF.Position
			local projected = poleDir - aimDir * poleDir:Dot(aimDir)
			if projected.Magnitude > 0.001 then
				local projUnit  = projected.Unit
				local currentUp = planeCF.UpVector
				local dot       = CLAMP(currentUp:Dot(projUnit), -1, 1)
				local cross     = currentUp:Cross(projUnit)
				local sign      = cross:Dot(aimDir) >= 0 and 1 or -1
				planeCF         = planeCF * ANGLES(0, 0, sign * safeAcos(dot))
			end
		end
	end

	-- Solve angles (leg variant)
	local a1, a2
	if l3 < ABS(l1 - l2) then
		-- Too close: fold
		planeCF = planeCF * CF(0, 0, MAX(l2, l1) - MIN(l2, l1) - l3)
		a1 = -HALF_PI
		a2 = PI
	elseif l3 > l1 + l2 then
		-- Too far: extend
		a1 = HALF_PI
		a2 = 0
	else
		-- Reachable: solve
		local _a1 = -safeAcos((-(l2*l2) + (l1*l1) + (l3*l3)) / (2*l1*l3))
		local _a2 =  safeAcos(( (l2*l2) - (l1*l1) + (l3*l3)) / (2*l2*l3))
		a1 = HALF_PI - _a1
		a2 = -(_a2 - _a1)
	end

	-- Clamp
	a1 = CLAMP(a1, cl.joint1[1], cl.joint1[2])
	a2 = CLAMP(a2, cl.joint2[1], cl.joint2[2])

	-- Build chain
	local limb   = self.parts[side .. " Leg"]
	local height = limb and limb.Size.Y or 2

	local hipCF  = planeCF * ANGLES(a1, 0, 0) * CF(0, -l1 * 0.5, 0)
	local kneeCF = hipCF
		* CF(0, -l1 * 0.5, 0)
		* ANGLES(a2, 0, 0)
		* CF(0, -l2 * 0.5, 0)
		* CF(0, (height - l2) * 0.5, 0)

	self.targetC0[mName] = worldCFrameToC0(motor, kneeCF)
end

---------------------------------------------------------------------------
-- INTERNAL: Torso pitch solve
---------------------------------------------------------------------------
function R6IKSolver:_solveTorso()
	if not self.enabled.Torso then return end
	self.targetC0["RootJoint"] = self.origC0["RootJoint"] * ANGLES(self._pitchCurrent, 0, 0)
end

---------------------------------------------------------------------------
-- UPDATE — call every frame (RenderStepped / Heartbeat)
---------------------------------------------------------------------------
function R6IKSolver:update(dt: number)
	if self._destroyed then return end

	local ZERO_TF = CF()

	-- 0. Zero .Transform on IK-controlled limb motors so the Animator
	--    doesn't fight our C0 writes. This must happen BEFORE solving
	--    because solveTwoJointIK reads Part0.CFrame (which is correct)
	--    and worldCFrameToC0 now assumes Transform = identity.
	local limbMotorMap = {
		LeftArm  = "Left Shoulder",
		RightArm = "Right Shoulder",
		LeftLeg  = "Left Hip",
		RightLeg = "Right Hip",
	}
	for limbName, mName in pairs(limbMotorMap) do
		if self.enabled[limbName] then
			local motor = self.motors[mName]
			if motor then
				motor.Transform = ZERO_TF
			end
		end
	end

	-- 1. Solve all enabled limbs
	if self.enabled.LeftArm  then self:_solveArm("Left")   end
	if self.enabled.RightArm then self:_solveArm("Right")  end
	if self.enabled.LeftLeg  then self:_solveLeg("Left")   end
	if self.enabled.RightLeg then self:_solveLeg("Right")  end

	-- 2. Torso pitch (smoothed separately)
	if self.enabled.Torso then
		local a = CLAMP(self.config.torsoPitchSmoothing, 0, 1)
		self._pitchCurrent = self._pitchCurrent + (self._pitchTarget - self._pitchCurrent) * a
		self:_solveTorso()
	end

	-- 3. Apply smoothed C0 values to actual Motor6Ds
	local motorToLimb = {
		["Left Shoulder"]  = "LeftArm",
		["Right Shoulder"] = "RightArm",
		["Left Hip"]       = "LeftLeg",
		["Right Hip"]      = "RightLeg",
		["RootJoint"]      = "Torso",
	}

	for mName, limbName in pairs(motorToLimb) do
		if self.enabled[limbName] then
			local motor = self.motors[mName]
			if motor and motor.Part0 and motor.Part1 then
				-- Lerp current toward target
				local alpha   = CLAMP(self.limbSmoothing[limbName] or self.config.smoothing, 0, 1)
				local target  = self.targetC0[mName]
				local current = self.currentC0[mName]
				if target and current then
					local new = current:Lerp(target, alpha)
					self.currentC0[mName] = new
					motor.C0 = new
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- RESET — restore one or all limbs to animation control
---------------------------------------------------------------------------
function R6IKSolver:reset(limbName: string?)
	if limbName then
		self:setEnabled(limbName, false)
	else
		for name in pairs(self.enabled) do
			self:setEnabled(name, false)
		end
		self._pitchTarget  = 0
		self._pitchCurrent = 0
	end
end

---------------------------------------------------------------------------
-- DESTROY — full cleanup, restores all original C0s
---------------------------------------------------------------------------
function R6IKSolver:destroy()
	if self._destroyed then return end
	self._destroyed = true

	-- Restore every motor to its original C0
	for name, motor in pairs(self.motors) do
		if motor and self.origC0[name] then
			motor.C0 = self.origC0[name]
		end
	end

	-- Drop all references
	table.clear(self)
end

return R6IKSolver
