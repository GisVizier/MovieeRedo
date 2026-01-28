--[[
	RagdollSystem.lua
	
	Handles ragdolling of R6 visual rigs with proper joint limits and physics.
	
	API:
		RagdollSystem:RagdollRig(rig, options) -> boolean
		RagdollSystem:UnragdollRig(rig) -> boolean
		RagdollSystem:IsRagdolled(rig) -> boolean
		
	Options:
		- Velocity: Vector3 - Initial velocity to apply
		- FlingDirection: Vector3 - Direction to fling
		- FlingStrength: number - Strength of fling (default 50)
		- Character: Model - The character model to weld ragdoll to
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RagdollSystem = {}

RagdollSystem._states = {} -- [rig] = { MotorStates, Constraints, Colliders, RootWeld, CharacterState }
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

--[[
	Sets up collision groups for ragdolls (only runs once)
]]
local function setupCollisionGroups()
	if RagdollSystem._collisionGroupSetup then
		return
	end
	
	pcall(function()
		PhysicsService:RegisterCollisionGroup(RAGDOLL_COLLISION_GROUP)
	end)
	
	-- Ragdolls should not collide with:
	-- - Players (the character physics body)
	-- - Other ragdolls (optional, can enable for chaos)
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

	-- Stop collision enforcement if RigManager is enforcing it
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
	local rootWeld = nil

	-- Convert all Motor6Ds to BallSocketConstraints
	for _, motor in ipairs(rig:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
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
	end

	-- Apply physics properties and collision group to all rig parts
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
			part.CanQuery = false  -- Keep out of raycasts
			part.CanTouch = false
			part.Massless = false
			part.Anchored = false
			
			-- Set collision group to avoid colliding with character
			pcall(function()
				part.CollisionGroup = RAGDOLL_COLLISION_GROUP
			end)
			
			-- Apply physical properties
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
		end
	end

	-- Get the rig's HumanoidRootPart
	local rigHRP = rig:FindFirstChild("HumanoidRootPart")
	
	-- If character is provided, weld rig to it and disable its physics
	local character = options.Character
	if character and rigHRP then
		local characterRoot = character:FindFirstChild("Root")
		
		if characterRoot then
			-- Save character physics state
			characterState = {
				RootAnchored = characterRoot.Anchored,
				RootCanCollide = characterRoot.CanCollide,
			}
			
			-- Disable character physics forces during ragdoll
			-- The Root should follow the ragdoll, not fight it
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
			
			-- Weld the rig HRP to the character Root so they move together
			rootWeld = Instance.new("WeldConstraint")
			rootWeld.Name = "RagdollToRootWeld"
			rootWeld.Part0 = rigHRP
			rootWeld.Part1 = characterRoot
			rootWeld.Parent = rigHRP
			
			-- Make Root follow ragdoll (massless, no collision)
			characterRoot.Massless = true
			characterRoot.CanCollide = false
		end
	end

	-- Apply initial velocity/fling
	if rigHRP then
		if options.Velocity then
			rigHRP.AssemblyLinearVelocity = options.Velocity
		elseif options.FlingDirection then
			local strength = options.FlingStrength or 50
			rigHRP.AssemblyLinearVelocity = options.FlingDirection.Unit * strength
		end
		
		-- Add some tumble
		if options.FlingDirection or options.Velocity then
			rigHRP.AssemblyAngularVelocity = Vector3.new(
				math.random() * 8 - 4,
				math.random() * 4 - 2,
				math.random() * 8 - 4
			)
		end
	end

	-- Store state
	rig:SetAttribute("IsRagdolled", true)
	
	self._states[rig] = {
		MotorStates = motorStates,
		Constraints = constraints,
		RootWeld = rootWeld,
		CharacterState = characterState,
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

	-- Destroy the root weld
	if state.RootWeld and state.RootWeld.Parent then
		state.RootWeld:Destroy()
	end

	-- Restore character physics state
	if state.Character and state.CharacterState then
		local characterRoot = state.Character:FindFirstChild("Root")
		if characterRoot then
			characterRoot.Massless = false
			characterRoot.CanCollide = state.CharacterState.RootCanCollide or true
			
			-- Restore physics forces
			local alignOrientation = characterRoot:FindFirstChild("AlignOrientation")
			local vectorForce = characterRoot:FindFirstChild("VectorForce")
			
			if alignOrientation and state.CharacterState.AlignOrientationEnabled ~= nil then
				alignOrientation.Enabled = state.CharacterState.AlignOrientationEnabled
			end
			
			if vectorForce and state.CharacterState.VectorForceEnabled ~= nil then
				vectorForce.Enabled = state.CharacterState.VectorForceEnabled
			end
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
			
			-- Reset collision group
			pcall(function()
				part.CollisionGroup = "Default"
			end)
			
			-- Re-anchor HumanoidRootPart
			if part.Name == "HumanoidRootPart" and part.Parent == rig then
				part.Anchored = true
			end
		end
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
