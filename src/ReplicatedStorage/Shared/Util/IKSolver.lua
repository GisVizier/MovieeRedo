--[[
	IKSolver.lua
	
	Pure math module for Inverse Kinematics solving.
	No state, no networking - just functions and config.
	
	Used by IKSystem.lua for third-person character rigs.
	Viewmodel arms do NOT use IK - they use animations.
]]

local IKSolver = {}

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

IKSolver.Config = {
	-- Torso pitch limits (radians)
	Torso = {
		MinPitch = math.rad(-40),
		MaxPitch = math.rad(40),
		BlendFactor = 0.6,
	},
	
	-- Head look limits (radians)
	Head = {
		MinPitch = math.rad(-50),
		MaxPitch = math.rad(50),
		MinYaw = math.rad(-30),
		MaxYaw = math.rad(30),
		BlendFactor = 0.9,
	},
	
	-- Arm IK settings
	Arm = {
		BlendFactor = 0.8,
		-- Elbow hint direction (local to arm)
		ElbowHintLeft = Vector3.new(-1, 0, -0.5),
		ElbowHintRight = Vector3.new(1, 0, -0.5),
	},
	
	-- Blend transition speed (per second)
	BlendSpeed = 10,
	
	-- Network update rate (Hz)
	NetworkUpdateRate = 20,
	
	-- Weapon types and their IK behavior
	WeaponTypes = {
		TwoHanded = { rightArm = true, leftArm = true },
		OneHanded = { rightArm = true, leftArm = false },
		Melee = { rightArm = false, leftArm = false }, -- Animation only
		Fists = { rightArm = false, leftArm = false }, -- No IK
	},
	
	-- Per-weapon grip paths (relative to weapon model root)
	-- Format: WeaponId = { RightGrip = "path", LeftGrip = "path", Type = "WeaponType" }
	Weapons = {
		Shotgun = {
			RightGrip = "Root.RightGrip",
			LeftGrip = "Root.LeftGrip",
			Type = "TwoHanded",
		},
		AssaultRifle = {
			RightGrip = "Root.RightGrip",
			LeftGrip = "Root.LeftGrip",
			Type = "TwoHanded",
		},
		Sniper = {
			RightGrip = "Root.RightGrip",
			LeftGrip = "Root.LeftGrip",
			Type = "TwoHanded",
		},
		Revolver = {
			RightGrip = "Root.RightGrip",
			LeftGrip = nil,
			Type = "OneHanded",
		},
		Knife = {
			RightGrip = "Root.RightGrip",
			LeftGrip = nil,
			Type = "Melee",
		},
		ExecutionerBlade = {
			RightGrip = "Root.RightGrip",
			LeftGrip = nil,
			Type = "Melee",
		},
		Fists = {
			RightGrip = nil,
			LeftGrip = nil,
			Type = "Fists",
		},
	},
}

--------------------------------------------------------------------------------
-- MATH UTILITIES
--------------------------------------------------------------------------------

--[[
	Clamp a value between min and max.
]]
local function clamp(value: number, min: number, max: number): number
	return math.max(min, math.min(max, value))
end

--------------------------------------------------------------------------------
-- ARM IK SOLVER (Two-bone for R6)
--------------------------------------------------------------------------------

--[[
	Solves two-bone IK for an R6 arm (single part, no elbow joint).
	Returns the plane CFrame and shoulder/elbow angles.
	
	@param originCF - CFrame of the shoulder joint origin
	@param targetPos - World position to reach
	@param upperLen - Upper arm length
	@param lowerLen - Lower arm length (for R6, usually same as upper)
	@param side - "Left" or "Right"
	@return planeCF, shoulderAngle, elbowAngle
]]
function IKSolver.SolveArmIK(
	originCF: CFrame,
	targetPos: Vector3,
	upperLen: number,
	lowerLen: number,
	side: string
): (CFrame, number, number)
	-- Localize target to origin space
	local localized = originCF:PointToObjectSpace(targetPos)
	local distance = localized.Magnitude
	local unit = distance > 0.001 and localized.Unit or Vector3.new(0, -1, 0)
	
	-- Build plane CFrame oriented toward target
	local forward = Vector3.new(0, 0, -1)
	local axis = forward:Cross(unit)
	local angle = math.acos(clamp(-unit.Z, -1, 1))
	
	local planeCF
	if axis.Magnitude > 0.001 then
		planeCF = originCF * CFrame.fromAxisAngle(axis.Unit, angle)
	else
		planeCF = originCF
	end
	
	-- Clamp distance to reachable range
	local minReach = math.abs(upperLen - lowerLen)
	local maxReach = upperLen + lowerLen
	
	-- Too close - fully compressed
	if distance < minReach then
		local pushBack = minReach - distance
		return planeCF * CFrame.new(0, 0, pushBack), -math.pi / 2, math.pi
	end
	
	-- Too far - fully extended
	if distance > maxReach then
		return planeCF, math.pi / 2, 0
	end
	
	-- Solvable - use law of cosines
	local upperSq = upperLen * upperLen
	local lowerSq = lowerLen * lowerLen
	local distSq = distance * distance
	
	local shoulderAngle = -math.acos(clamp((-lowerSq + upperSq + distSq) / (2 * upperLen * distance), -1, 1))
	local elbowAngle = math.acos(clamp((lowerSq - upperSq + distSq) / (2 * lowerLen * distance), -1, 1))
	
	return planeCF, shoulderAngle + math.pi / 2, elbowAngle - shoulderAngle
end

--------------------------------------------------------------------------------
-- TORSO IK SOLVER
--------------------------------------------------------------------------------

--[[
	Calculates torso pitch based on aim direction.
	
	@param aimPitch - Vertical aim angle in radians (negative = looking up)
	@return Clamped pitch angle for torso rotation
]]
function IKSolver.SolveTorsoPitch(aimPitch: number): number
	local config = IKSolver.Config.Torso
	return clamp(aimPitch, config.MinPitch, config.MaxPitch)
end

--------------------------------------------------------------------------------
-- HEAD IK SOLVER
--------------------------------------------------------------------------------

--[[
	Calculates head rotation based on aim direction.
	
	@param aimPitch - Vertical aim angle in radians
	@param aimYaw - Horizontal aim angle in radians (relative to torso)
	@return CFrame rotation for head
]]
function IKSolver.SolveHeadLook(aimPitch: number, aimYaw: number): CFrame
	local config = IKSolver.Config.Head
	
	local clampedPitch = clamp(aimPitch, config.MinPitch, config.MaxPitch)
	local clampedYaw = clamp(aimYaw, config.MinYaw, config.MaxYaw)
	
	-- Head rotates: pitch (X), then yaw (Y)
	return CFrame.Angles(clampedPitch, clampedYaw, 0)
end

--------------------------------------------------------------------------------
-- MOTOR6D UTILITIES
--------------------------------------------------------------------------------

--[[
	Converts a world CFrame to Motor6D C0 space.
	
	@param motor - The Motor6D joint
	@param worldCFrame - Target world CFrame for Part1
	@return C0 CFrame that achieves the world position
]]
function IKSolver.WorldCFrameToC0(motor: Motor6D, worldCFrame: CFrame): CFrame
	local part0 = motor.Part0
	local c1 = motor.C1
	
	if not part0 then
		return motor.C0
	end
	
	-- C0 = Part0.CFrame:Inverse() * WorldCFrame * C1
	return part0.CFrame:Inverse() * worldCFrame * c1
end

--[[
	Lerp between two CFrames.
	
	@param a - Start CFrame
	@param b - End CFrame  
	@param alpha - Blend factor (0-1)
	@return Interpolated CFrame
]]
function IKSolver.LerpCFrame(a: CFrame, b: CFrame, alpha: number): CFrame
	return a:Lerp(b, clamp(alpha, 0, 1))
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Get attachment from a dot-separated path.
	Example: "Root.RightGrip" finds model.Root.RightGrip
	
	@param model - Parent model to search in
	@param path - Dot-separated path string
	@return Attachment or nil
]]
function IKSolver.GetAttachmentFromPath(model: Model, path: string): Attachment?
	if not model or not path then
		return nil
	end
	
	local current: Instance = model
	for _, partName in ipairs(string.split(path, ".")) do
		current = current:FindFirstChild(partName)
		if not current then
			return nil
		end
	end
	
	if current:IsA("Attachment") then
		return current
	end
	
	return nil
end

--[[
	Get weapon config by ID.
	
	@param weaponId - Weapon identifier
	@return Config table or nil
]]
function IKSolver.GetWeaponConfig(weaponId: string)
	return IKSolver.Config.Weapons[weaponId]
end

--[[
	Check if a weapon type should use arm IK.
	
	@param weaponId - Weapon identifier
	@param side - "Left" or "Right"
	@return boolean
]]
function IKSolver.ShouldUseArmIK(weaponId: string, side: string): boolean
	local weaponConfig = IKSolver.Config.Weapons[weaponId]
	if not weaponConfig then
		return false
	end
	
	local typeConfig = IKSolver.Config.WeaponTypes[weaponConfig.Type]
	if not typeConfig then
		return false
	end
	
	if side == "Left" then
		return typeConfig.leftArm
	else
		return typeConfig.rightArm
	end
end

return IKSolver
