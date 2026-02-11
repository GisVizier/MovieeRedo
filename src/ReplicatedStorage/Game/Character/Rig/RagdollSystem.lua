--[[
	RagdollSystem.lua
	
	Handles ragdolling of R6 visual rigs with proper joint limits and physics.
	
	Architecture:
		- The rig ragdolls with physics (Motor6Ds -> BallSocketConstraints)
		- The character Root is ANCHORED during ragdoll (not welded)
		- On unragdoll, Root teleports to where the rig ended up
	
	API:
		RagdollSystem:RagdollRig(rig, options) -> boolean
		RagdollSystem:UnragdollRig(rig) -> boolean
		RagdollSystem:IsRagdolled(rig) -> boolean
		
	Options:
		- Velocity: Vector3 - Initial velocity to apply
		- FlingDirection: Vector3 - Direction to fling
		- FlingStrength: number - Strength of fling (default 50)
		- Character: Model - The character model (Root will be anchored)
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RagdollSystem = {}

RagdollSystem._states = {} -- [rig] = { MotorStates, Constraints, CharacterState, Character }
RagdollSystem._collisionGroupSetup = false

-- Collision group name for ragdolls
local RAGDOLL_COLLISION_GROUP = "Ragdolls"

-- Joint limit configurations for R6 rigs
local JOINT_LIMITS = {
	["Neck"] = {
		UpperAngle = 45,
		TwistLowerAngle = -60,
		TwistUpperAngle = 60,
		MaxFrictionTorque = 10,
	},
	["Left Shoulder"] = {
		UpperAngle = 110,
		TwistLowerAngle = -85,
		TwistUpperAngle = 85,
		MaxFrictionTorque = 5,
	},
	["Right Shoulder"] = {
		UpperAngle = 110,
		TwistLowerAngle = -85,
		TwistUpperAngle = 85,
		MaxFrictionTorque = 5,
	},
	["Left Hip"] = {
		UpperAngle = 90,
		TwistLowerAngle = -45,
		TwistUpperAngle = 45,
		MaxFrictionTorque = 5,
	},
	["Right Hip"] = {
		UpperAngle = 90,
		TwistLowerAngle = -45,
		TwistUpperAngle = 45,
		MaxFrictionTorque = 5,
	},
	["RootJoint"] = {
		UpperAngle = 30,
		TwistLowerAngle = -45,
		TwistUpperAngle = 45,
		MaxFrictionTorque = 15,
	},
}

-- Physics properties for ragdoll parts
local RAGDOLL_PHYSICS = {
	Density = 0.7,
	Friction = 0.5,
	Elasticity = 0,
	FrictionWeight = 1,
	ElasticityWeight = 1,
	HeadDensity = 0.7,
	HeadFriction = 0.3,
}

local function findRigHumanoidRootPart(rig)
	if not rig then
		return nil
	end

	local direct = rig:FindFirstChild("HumanoidRootPart")
	if direct and direct:IsA("BasePart") then
		return direct
	end

	local recursive = rig:FindFirstChild("HumanoidRootPart", true)
	if recursive and recursive:IsA("BasePart") then
		return recursive
	end

	return nil
end

local function isAccessoryOrToolDescendant(part, rig)
	if not part or not rig then
		return false
	end

	local node = part
	while node and node ~= rig do
		if node:IsA("Accessory") or node:IsA("Tool") then
			return true
		end
		node = node.Parent
	end

	return false
end

local function shouldRagdollMotor(motor, rig)
	if not motor:IsA("Motor6D") or not motor.Part0 or not motor.Part1 then
		return false
	end
	if not motor.Part0:IsDescendantOf(rig) or not motor.Part1:IsDescendantOf(rig) then
		return false
	end
	if motor.Part0.Name == "Handle" or motor.Part1.Name == "Handle" then
		return false
	end
	if isAccessoryOrToolDescendant(motor.Part0, rig) or isAccessoryOrToolDescendant(motor.Part1, rig) then
		return false
	end

	return true
end

--[[
	Sets up collision groups for ragdolls (only runs once)
]]
local function setupCollisionGroups()
	if RagdollSystem._collisionGroupSetup then
		return
	end
	
	-- Note: On client, we can only set parts to groups that exist.
	-- The server should register these groups. We'll attempt registration
	-- but it may fail silently on client (which is fine).
	pcall(function()
		PhysicsService:RegisterCollisionGroup(RAGDOLL_COLLISION_GROUP)
	end)
	
	-- Ragdolls should not collide with Players (character physics body)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(RAGDOLL_COLLISION_GROUP, "Players", false)
		PhysicsService:CollisionGroupSetCollidable(RAGDOLL_COLLISION_GROUP, "Default", true)
	end)
	
	RagdollSystem._collisionGroupSetup = true
end

--[[
	Creates attachments for a motor to use with BallSocketConstraint
]]
local function createAttachments(part0, part1, motor)
	local att0 = Instance.new("Attachment")
	att0.Name = "RagdollAtt0_" .. motor.Name
	att0.CFrame = motor.C0
	att0.Parent = part0

	local att1 = Instance.new("Attachment")
	att1.Name = "RagdollAtt1_" .. motor.Name
	att1.CFrame = motor.C1
	att1.Parent = part1

	return att0, att1
end

--[[
	Ragdolls a rig by converting Motor6Ds to BallSocketConstraints
	
	@param rig Model - The R6 rig to ragdoll
	@param options table? - Optional configuration
	@return boolean - Whether ragdolling succeeded
]]
function RagdollSystem:RagdollRig(rig, options)
	options = options or {}

	if not rig or self._states[rig] then
		return false
	end

	-- Setup collision groups (once)
	setupCollisionGroups()

	-- Stop collision enforcement if active
	local success, Locations = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
	end)
	
	if success and Locations then
		local CollisionUtils = require(Locations.Shared.Util:WaitForChild("CollisionUtils"))
		CollisionUtils:StopEnsuringNonCollideable(rig)
	end

	local motorStates = {}
	local constraints = {}
	local characterState = nil
	local humanoidState = nil
	
	-- Get the rig's HumanoidRootPart
	local rigHRP = findRigHumanoidRootPart(rig)
	local rigHumanoid = rig:FindFirstChildOfClass("Humanoid") or rig:FindFirstChildWhichIsA("Humanoid", true)

	-- Ragdoll body motors while excluding accessory/tool motors.
	local ragdollMotors = {}
	local ragdollPartSet = {}
	for _, motor in ipairs(rig:GetDescendants()) do
		if shouldRagdollMotor(motor, rig) then
			table.insert(ragdollMotors, motor)
			ragdollPartSet[motor.Part0] = true
			ragdollPartSet[motor.Part1] = true
		end
	end

	if rigHumanoid then
		humanoidState = {
			PlatformStand = rigHumanoid.PlatformStand,
			AutoRotate = rigHumanoid.AutoRotate,
			GettingUp = rigHumanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp),
			Running = rigHumanoid:GetStateEnabled(Enum.HumanoidStateType.Running),
		}

		rigHumanoid.PlatformStand = true
		rigHumanoid.AutoRotate = false
		rigHumanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		rigHumanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
		pcall(function()
			rigHumanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
	if #ragdollMotors == 0 then
		for _, motor in ipairs(rig:GetDescendants()) do
			if motor:IsA("Motor6D")
				and motor.Part0
				and motor.Part1
				and motor.Part0:IsDescendantOf(rig)
				and motor.Part1:IsDescendantOf(rig)
			then
				table.insert(ragdollMotors, motor)
				ragdollPartSet[motor.Part0] = true
				ragdollPartSet[motor.Part1] = true
			end
		end
	end
	if rigHRP then
		ragdollPartSet[rigHRP] = true
	end
	
	-- Handle character Root (anchor it, don't weld)
	local character = options.Character
	local characterRoot = character and character:FindFirstChild("Root")
	
	if characterRoot then
		-- Save character state BEFORE modifying
		characterState = {
			RootCFrame = characterRoot.CFrame,
			RootAnchored = characterRoot.Anchored,
			RootCanCollide = characterRoot.CanCollide,
			RootMassless = characterRoot.Massless,
		}
		
		-- Disable physics forces on Root
		local alignOrientation = characterRoot:FindFirstChild("AlignOrientation")
		local vectorForce = characterRoot:FindFirstChild("VectorForce")
		
		if alignOrientation then
			characterState.AlignOrientationEnabled = alignOrientation.Enabled
			alignOrientation.Enabled = false
		end
		
		if vectorForce then
			characterState.VectorForceEnabled = vectorForce.Enabled
			vectorForce.Enabled = false
		end
		
		-- ANCHOR the Root so it doesn't interfere with ragdoll physics
		-- This is key: we don't weld, we just freeze the Root in place
		characterRoot.Anchored = true
	end

	-- Apply physics properties. Body parts get full ragdoll physics;
	-- cosmetic parts stay non-collideable so attachments/accessories remain stable.
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			local isBodyPart = ragdollPartSet[part] == true

			part.CanQuery = false
			part.CanTouch = false
			part.Anchored = false

			if isBodyPart then
				part.CanCollide = true
				part.Massless = false

				pcall(function()
					part.CollisionGroup = RAGDOLL_COLLISION_GROUP
				end)

				local density = RAGDOLL_PHYSICS.Density
				local friction = RAGDOLL_PHYSICS.Friction

				if part.Name == "Head" then
					density = RAGDOLL_PHYSICS.HeadDensity
					friction = RAGDOLL_PHYSICS.HeadFriction
				end

				part.CustomPhysicalProperties = PhysicalProperties.new(
					density,
					friction,
					RAGDOLL_PHYSICS.Elasticity,
					RAGDOLL_PHYSICS.FrictionWeight,
					RAGDOLL_PHYSICS.ElasticityWeight
				)
			else
				part.CanCollide = false
				part.Massless = true
			end
		end
	end

	-- Apply initial velocity BEFORE converting motors (so parts have momentum)
	if rigHRP then
		if options.Velocity then
			rigHRP.AssemblyLinearVelocity = options.Velocity
			rigHRP:ApplyImpulse(options.Velocity * math.max(rigHRP.AssemblyMass, 1))
		elseif options.FlingDirection then
			local strength = options.FlingStrength or 50
			local direction = options.FlingDirection
			if typeof(direction) == "Vector3" and direction.Magnitude > 0 then
				local flingVelocity = direction.Unit * strength
				rigHRP.AssemblyLinearVelocity = flingVelocity
				rigHRP:ApplyImpulse(flingVelocity * math.max(rigHRP.AssemblyMass, 1))
			end
		end
		
		-- Add some tumble for natural ragdoll feel
		if options.FlingDirection or options.Velocity then
			rigHRP.AssemblyAngularVelocity = Vector3.new(
				math.random() * 12 - 6,
				math.random() * 6 - 3,
				math.random() * 12 - 6
			)
		end
	end

	-- Convert body Motor6Ds to BallSocketConstraints
	for _, motor in ipairs(ragdollMotors) do
		-- Save motor state for restoration
		motorStates[motor] = {
			Enabled = motor.Enabled,
			C0 = motor.C0,
			C1 = motor.C1,
			Part0 = motor.Part0,
		}

		-- Create attachments
		local att0, att1 = createAttachments(motor.Part0, motor.Part1, motor)
		
		-- Create BallSocketConstraint with limits
		local constraint = Instance.new("BallSocketConstraint")
		constraint.Name = "Ragdoll_" .. motor.Name
		constraint.Attachment0 = att0
		constraint.Attachment1 = att1
		
		-- Apply joint limits
		local limits = JOINT_LIMITS[motor.Name]
		if limits then
			constraint.LimitsEnabled = true
			constraint.UpperAngle = limits.UpperAngle
			constraint.TwistLimitsEnabled = true
			constraint.TwistLowerAngle = limits.TwistLowerAngle
			constraint.TwistUpperAngle = limits.TwistUpperAngle
			constraint.MaxFrictionTorque = limits.MaxFrictionTorque or 0
			constraint.Restitution = 0
		end
		
		constraint.Parent = motor.Part0
		constraints[motor] = { Constraint = constraint, Att0 = att0, Att1 = att1 }
		
		-- Disable the motor
		motor.Enabled = false
	end

	-- Store state
	rig:SetAttribute("IsRagdolled", true)
	
	self._states[rig] = {
		MotorStates = motorStates,
		Constraints = constraints,
		CharacterState = characterState,
		HumanoidState = humanoidState,
		Character = character,
	}

	return true
end

--[[
	Restores a rig from ragdoll state back to normal
	
	@param rig Model - The rig to unragdoll
	@return boolean - Whether unragdolling succeeded
]]
function RagdollSystem:UnragdollRig(rig)
	local state = self._states[rig]
	if not state or not rig then
		return false
	end

	local rigHRP = findRigHumanoidRootPart(rig)
	local rigHumanoid = rig:FindFirstChildOfClass("Humanoid") or rig:FindFirstChildWhichIsA("Humanoid", true)
	local character = state.Character
	local characterState = state.CharacterState
	local humanoidState = state.HumanoidState
	
	-- Get the rig's current position (where ragdoll ended up)
	local finalRigCFrame = rigHRP and rigHRP.CFrame or nil

	-- Restore character Root state
	if character and characterState then
		local characterRoot = character:FindFirstChild("Root")
		if characterRoot then
			-- Teleport Root to where the rig ended up (before unanchoring)
			if finalRigCFrame then
				-- Keep Root's Y rotation but use rig's position
				local currentRotY = characterRoot.CFrame - characterRoot.CFrame.Position
				local upright = CFrame.new(finalRigCFrame.Position) * CFrame.Angles(0, currentRotY:ToEulerAnglesYXZ())
				characterRoot.CFrame = CFrame.new(finalRigCFrame.Position + Vector3.new(0, 2, 0))
			end
			
			-- Restore physics properties
			characterRoot.Massless = characterState.RootMassless or false
			characterRoot.CanCollide = characterState.RootCanCollide or true
			
			-- Restore physics forces
			local alignOrientation = characterRoot:FindFirstChild("AlignOrientation")
			local vectorForce = characterRoot:FindFirstChild("VectorForce")
			
			if alignOrientation and characterState.AlignOrientationEnabled ~= nil then
				alignOrientation.Enabled = characterState.AlignOrientationEnabled
			end
			
			if vectorForce and characterState.VectorForceEnabled ~= nil then
				vectorForce.Enabled = characterState.VectorForceEnabled
			end
			
			-- Unanchor Root (do this last!)
			characterRoot.Anchored = characterState.RootAnchored or false
			
			-- Clear any residual velocity
			characterRoot.AssemblyLinearVelocity = Vector3.zero
			characterRoot.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- Destroy constraints and attachments
	for motor, constraintData in pairs(state.Constraints) do
		if constraintData.Constraint and constraintData.Constraint.Parent then
			constraintData.Constraint:Destroy()
		end
		if constraintData.Att0 and constraintData.Att0.Parent then
			constraintData.Att0:Destroy()
		end
		if constraintData.Att1 and constraintData.Att1.Parent then
			constraintData.Att1:Destroy()
		end

		-- Restore motor state
		local data = state.MotorStates[motor]
		if data and motor.Parent then
			motor.C0 = data.C0
			motor.C1 = data.C1
			motor.Enabled = data.Enabled
		end
	end

	-- Restore part properties (rig is cosmetic, so back to non-collideable)
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			
			-- Reset collision group
			pcall(function()
				part.CollisionGroup = "Default"
			end)
			
			-- Re-anchor HumanoidRootPart
			if part.Name == "HumanoidRootPart" and part:IsDescendantOf(rig) then
				part.Anchored = true
			end
		end
	end

	if rigHumanoid and humanoidState then
		rigHumanoid.PlatformStand = humanoidState.PlatformStand
		rigHumanoid.AutoRotate = humanoidState.AutoRotate
		rigHumanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, humanoidState.GettingUp)
		rigHumanoid:SetStateEnabled(Enum.HumanoidStateType.Running, humanoidState.Running)
		pcall(function()
			rigHumanoid:ChangeState(Enum.HumanoidStateType.Running)
		end)
	end

	-- Restart collision enforcement
	local success, Locations = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
	end)
	
	if success and Locations then
		local CollisionUtils = require(Locations.Shared.Util:WaitForChild("CollisionUtils"))
		CollisionUtils:EnsureNonCollideable(rig, {
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Massless = true,
			UseHeartbeat = true,
			HeartbeatInterval = 0.25,
		})
	end

	rig:SetAttribute("IsRagdolled", false)
	self._states[rig] = nil

	return true
end

--[[
	Checks if a rig is currently ragdolled
	
	@param rig Model - The rig to check
	@return boolean - Whether the rig is ragdolled
]]
function RagdollSystem:IsRagdolled(rig)
	return self._states[rig] ~= nil
end

--[[
	Gets the ragdoll state for a rig (internal use)
	
	@param rig Model - The rig to get state for
	@return table? - The ragdoll state or nil
]]
function RagdollSystem:GetState(rig)
	return self._states[rig]
end

return RagdollSystem
