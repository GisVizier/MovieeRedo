--[[
	RagdollSystem.lua

	Client-side R6 ragdoll system for custom character setup.
	Since the Rig is purely visual and doesn't affect physics, we have full control
	over ragdolling without impacting the player's actual movement/collision.

	Architecture:
	- Works with the visual R6 Rig (separate from physics Root/Collider)
	- Uses BallSocketConstraints instead of Motor6Ds for ragdoll effect
	- Applies dynamic physics properties for realistic ragdoll behavior
	- Can enhance ragdolls with force application, limb velocity, etc.

	Usage:
	local RagdollSystem = require(Locations.Modules.Systems.Character.RagdollSystem)
	RagdollSystem:RagdollCharacter(character, options)
	RagdollSystem:UnragdollCharacter(character)
	RagdollSystem:IsRagdolled(character)
]]

local RagdollSystem = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local Config = require(Locations.Modules.Config)
local LogService = require(Locations.Modules.Systems.Core.LogService)

-- State tracking
local RagdollState = {}
local FadeTimers = {} -- Track fade timers for cleanup

-- Constants
local R6_MOTOR_NAMES = {
	"Neck",
	"Left Shoulder",
	"Right Shoulder",
	"Left Hip",
	"Right Hip",
	"RootJoint"
}

-- Ragdoll joint configurations (angle limits and twist for realistic movement)
local JOINT_CONFIGS = {
	Neck = {
		UpperAngle = 45,
		TwistLimitsEnabled = true,
		TwistLowerAngle = -60,
		TwistUpperAngle = 60,
		MaxFrictionTorque = 10,
	},
	["Left Shoulder"] = {
		UpperAngle = 90,
		TwistLimitsEnabled = true,
		TwistLowerAngle = -75,
		TwistUpperAngle = 75,
		MaxFrictionTorque = 5,
	},
	["Right Shoulder"] = {
		UpperAngle = 90,
		TwistLimitsEnabled = true,
		TwistLowerAngle = -75,
		TwistUpperAngle = 75,
		MaxFrictionTorque = 5,
	},
	["Left Hip"] = {
		UpperAngle = 90,
		TwistLimitsEnabled = true,
		TwistLowerAngle = -45,
		TwistUpperAngle = 45,
		MaxFrictionTorque = 5,
	},
	["Right Hip"] = {
		UpperAngle = 90,
		TwistLimitsEnabled = true,
		TwistLowerAngle = -45,
		TwistUpperAngle = 45,
		MaxFrictionTorque = 5,
	},
	RootJoint = {
		UpperAngle = 30,
		TwistLimitsEnabled = true,
		TwistLowerAngle = -45,
		TwistUpperAngle = 45,
		MaxFrictionTorque = 15,
	},
}

-- Physics properties for ragdoll parts
local RAGDOLL_PHYSICS = PhysicalProperties.new(0.7, 0.5, 0, 1, 1)
local HEAD_PHYSICS = PhysicalProperties.new(0.7, 0.3, 0, 1, 1)

-- Collision group for ragdolls (doesn't collide with players)
local RAGDOLL_COLLISION_GROUP = "Ragdolls"
local collisionGroupRegistered = false

-- Utility Functions

local function ensureRagdollCollisionGroup()
	if collisionGroupRegistered then
		return true
	end

	-- Try to register the collision group (may already exist from server)
	local success = pcall(function()
		PhysicsService:RegisterCollisionGroup(RAGDOLL_COLLISION_GROUP)
	end)

	-- Set ragdolls to not collide with players
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(RAGDOLL_COLLISION_GROUP, "Players", false)
	end)

	collisionGroupRegistered = true
	LogService:Debug("RAGDOLL", "Ragdoll collision group ensured", { NewlyCreated = success })
	return true
end

local function applyRagdollCollisionGroup(rig)
	ensureRagdollCollisionGroup()

	local partsProcessed = 0
	for _, part in pairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part.CollisionGroup = RAGDOLL_COLLISION_GROUP
			end)
			partsProcessed = partsProcessed + 1
		end
	end

	LogService:Debug("RAGDOLL", "Applied ragdoll collision group", {
		RigName = rig.Name,
		PartsProcessed = partsProcessed,
	})
end

local function getOrCreateAttachment(part, name, cframe)
	local existing = part:FindFirstChild(name)
	if existing and existing:IsA("Attachment") then
		return existing
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = cframe
	attachment.Parent = part
	return attachment
end

local function createRagdollJoint(motor6D, config)
	local part0 = motor6D.Part0
	local part1 = motor6D.Part1

	if not part0 or not part1 then
		return nil
	end

	-- Create BallSocketConstraint
	local constraint = Instance.new("BallSocketConstraint")
	constraint.Name = "Ragdoll_" .. motor6D.Name
	constraint.LimitsEnabled = true
	constraint.UpperAngle = config.UpperAngle

	if config.TwistLimitsEnabled then
		constraint.TwistLimitsEnabled = true
		constraint.TwistLowerAngle = config.TwistLowerAngle
		constraint.TwistUpperAngle = config.TwistUpperAngle
	end

	if config.MaxFrictionTorque then
		constraint.MaxFrictionTorque = config.MaxFrictionTorque
	end

	-- Use motor6D's existing C0/C1 for attachment positions
	local att0 = getOrCreateAttachment(part0, "RagdollAttachment_" .. motor6D.Name .. "_0", motor6D.C0)
	local att1 = getOrCreateAttachment(part1, "RagdollAttachment_" .. motor6D.Name .. "_1", motor6D.C1)

	constraint.Attachment0 = att0
	constraint.Attachment1 = att1
	constraint.Parent = part0

	return constraint
end

local function stopAnimations(rig)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	for _, track in pairs(humanoid:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
end

local function applyRagdollPhysics(rig)
	-- Apply physics properties to all rig parts
	local torso = rig:FindFirstChild("Torso")
	local head = rig:FindFirstChild("Head")
	local leftArm = rig:FindFirstChild("Left Arm")
	local rightArm = rig:FindFirstChild("Right Arm")
	local leftLeg = rig:FindFirstChild("Left Leg")
	local rightLeg = rig:FindFirstChild("Right Leg")

	if torso then torso.CustomPhysicalProperties = RAGDOLL_PHYSICS end
	if leftArm then leftArm.CustomPhysicalProperties = RAGDOLL_PHYSICS end
	if rightArm then rightArm.CustomPhysicalProperties = RAGDOLL_PHYSICS end
	if leftLeg then leftLeg.CustomPhysicalProperties = RAGDOLL_PHYSICS end
	if rightLeg then rightLeg.CustomPhysicalProperties = RAGDOLL_PHYSICS end
	if head then head.CustomPhysicalProperties = HEAD_PHYSICS end
end

local function resetPhysics(rig)
	-- Reset physics properties to default
	CharacterLocations:ForEachRigPart(rig.Parent, function(rigPart)
		rigPart.CustomPhysicalProperties = nil
	end)
end

local function fadeOutDeadRagdoll(rig, rigName)
	-- Get fade config
	local fadeTime = Config.Gameplay.Character.Ragdoll.DeadRagdoll.FadeTime
	local fadeDuration = Config.Gameplay.Character.Ragdoll.DeadRagdoll.FadeDuration

	-- Wait before fading
	task.wait(fadeTime)

	-- Check if rig still exists
	if not rig or not rig.Parent then
		FadeTimers[rig] = nil
		return
	end

	LogService:Debug("RAGDOLL", "Starting fade-out for dead ragdoll", {
		RigName = rigName,
		FadeDuration = fadeDuration
	})

	if fadeDuration > 0 then
		-- Smooth fade using TweenService
		local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Linear)
		local tweens = {}

		-- Fade all rig parts (iterate directly over rig children)
		for _, child in pairs(rig:GetDescendants()) do
			if child:IsA("BasePart") then
				local tween = TweenService:Create(child, tweenInfo, {
					Transparency = 1
				})
				table.insert(tweens, tween)
				tween:Play()
			end
		end

		-- Wait for fade to complete
		task.wait(fadeDuration)
	else
		-- Instant fade (set transparency directly)
		for _, child in pairs(rig:GetDescendants()) do
			if child:IsA("BasePart") then
				child.Transparency = 1
			end
		end
	end

	-- Destroy the rig after fade
	if rig and rig.Parent then
		rig:Destroy()
		LogService:Info("RAGDOLL", "Dead ragdoll destroyed after fade", {
			RigName = rigName
		})
	end

	-- Clean up timer reference
	FadeTimers[rig] = nil
end

-- Main API Functions

function RagdollSystem:RagdollRig(rig, options)
	options = options or {}

	if not rig then
		LogService:Warn("RAGDOLL", "No Rig provided to RagdollRig")
		return false
	end

	-- Check if already ragdolled (use rig as key since character may be nil)
	if RagdollState[rig] then
		LogService:Debug("RAGDOLL", "Rig already ragdolled", {
			RigName = rig.Name
		})
		return false
	end

	local torso = rig:FindFirstChild("Torso")
	if not torso then
		LogService:Warn("RAGDOLL", "No Torso found in Rig", {
			RigName = rig.Name
		})
		return false
	end

	-- Stop all animations
	stopAnimations(rig)

	-- Store original motor states and create ragdoll constraints
	local motorStates = {}
	local ragdollConstraints = {}

	for _, motorName in ipairs(R6_MOTOR_NAMES) do
		local motor = nil

		if motorName == "RootJoint" then
			local hrp = rig:FindFirstChild("HumanoidRootPart")
			if hrp then
				motor = hrp:FindFirstChild(motorName)
			end
		else
			motor = torso:FindFirstChild(motorName)
		end

		if motor and motor:IsA("Motor6D") then
			motorStates[motorName] = {
				Motor = motor,
				OriginalEnabled = motor.Enabled,
				OriginalC0 = motor.C0,
				OriginalC1 = motor.C1,
			}

			local config = JOINT_CONFIGS[motorName]
			if config then
				local constraint = createRagdollJoint(motor, config)
				if constraint then
					ragdollConstraints[motorName] = constraint
				end
			end

			motor.Enabled = false
		end
	end

	-- Apply ragdoll physics
	applyRagdollPhysics(rig)

	-- Apply ragdoll collision group (so ragdolls don't collide with players)
	applyRagdollCollisionGroup(rig)

	-- Make rig parts physical and visible
	for _, part in pairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
			part.Massless = false
			part.Anchored = false
			part.LocalTransparencyModifier = 0
		end
	end

	-- Make accessories visible too
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, accessory in pairs(humanoid:GetAccessories()) do
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.LocalTransparencyModifier = 0
			end
		end
	end

	-- Apply initial velocity if provided
	if options.Velocity then
		local hrp = rig:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.AssemblyLinearVelocity = options.Velocity
		end
	end

	-- Apply angular velocity if provided
	if options.AngularVelocity then
		local hrp = rig:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.AssemblyAngularVelocity = options.AngularVelocity
		end
	end

	-- Store ragdoll state (keyed by rig for remote players)
	RagdollState[rig] = {
		MotorStates = motorStates,
		RagdollConstraints = ragdollConstraints,
		StartTime = tick(),
	}

	-- Start fade timer for death ragdolls
	if options.IsDeath then
		if FadeTimers[rig] then
			task.cancel(FadeTimers[rig])
		end

		FadeTimers[rig] = task.spawn(function()
			fadeOutDeadRagdoll(rig, rig.Name)
		end)

		LogService:Info("RAGDOLL", "Death ragdoll created with fade timer (direct rig)", {
			RigName = rig.Name,
			FadeTime = Config.Gameplay.Character.Ragdoll.DeadRagdoll.FadeTime,
		})
	end

	LogService:Info("RAGDOLL", "Rig ragdolled directly", {
		RigName = rig.Name,
		MotorCount = #motorStates,
		ConstraintCount = #ragdollConstraints,
	})

	return true
end

function RagdollSystem:RagdollCharacter(character, options)
	options = options or {}

	-- Get the visual Rig (now in workspace.Rigs)
	local rig = CharacterLocations:GetRig(character)
	if not rig then
		LogService:Warn("RAGDOLL", "No Rig found for character", {
			CharacterName = character.Name
		})
		return false
	end

	-- Check if already ragdolled
	if RagdollState[character] then
		LogService:Debug("RAGDOLL", "Character already ragdolled", {
			CharacterName = character.Name
		})
		return false
	end

	local torso = rig:FindFirstChild("Torso")
	if not torso then
		LogService:Warn("RAGDOLL", "No Torso found in Rig")
		return false
	end

	-- CRITICAL: Disable BulkMoveTo sync for local player's Rig by setting a flag
	-- The ClientReplicator will check this flag and skip syncing the rig while ragdolled
	character:SetAttribute("RagdollActive", true)

	-- Stop all animations
	stopAnimations(rig)

	-- Store original motor states and create ragdoll constraints
	local motorStates = {}
	local ragdollConstraints = {}

	for _, motorName in ipairs(R6_MOTOR_NAMES) do
		local motor = nil

		-- Find the motor (RootJoint is in HumanoidRootPart, others in Torso)
		if motorName == "RootJoint" then
			local hrp = rig:FindFirstChild("HumanoidRootPart")
			if hrp then
				motor = hrp:FindFirstChild(motorName)
			end
		else
			motor = torso:FindFirstChild(motorName)
		end

		if motor and motor:IsA("Motor6D") then
			-- Store original state
			motorStates[motorName] = {
				Motor = motor,
				OriginalEnabled = motor.Enabled,
				OriginalC0 = motor.C0,
				OriginalC1 = motor.C1,
			}

			-- Create ragdoll constraint
			local config = JOINT_CONFIGS[motorName]
			if config then
				local constraint = createRagdollJoint(motor, config)
				if constraint then
					ragdollConstraints[motorName] = constraint
				end
			end

			-- Disable motor
			motor.Enabled = false
		end
	end

	-- Apply ragdoll physics
	applyRagdollPhysics(rig)

	-- Apply ragdoll collision group (so ragdolls don't collide with players)
	applyRagdollCollisionGroup(rig)

	-- Make rig parts physical and visible
	CharacterLocations:ForEachRigPart(character, function(rigPart)
		rigPart.CanCollide = true
		rigPart.Massless = false
		rigPart.Anchored = false

		-- Reset transparency so player can see their ragdoll (important for first-person)
		rigPart.LocalTransparencyModifier = 0
	end)

	-- Make accessories visible too
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, accessory in pairs(humanoid:GetAccessories()) do
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.LocalTransparencyModifier = 0
			end
		end
	end

	-- Apply initial velocity if provided
	if options.Velocity then
		local hrp = rig:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.AssemblyLinearVelocity = options.Velocity
		end
	end

	-- Apply angular velocity for spinning effect if provided
	if options.AngularVelocity then
		local hrp = rig:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.AssemblyAngularVelocity = options.AngularVelocity
		end
	end

	-- Store ragdoll state
	RagdollState[character] = {
		MotorStates = motorStates,
		RagdollConstraints = ragdollConstraints,
		StartTime = tick(),
	}

	-- Start fade timer for dead ragdolls (if this is a death ragdoll)
	if options.IsDeath then
		-- Cancel any existing fade timer for this rig
		if FadeTimers[rig] then
			task.cancel(FadeTimers[rig])
		end

		-- Start new fade timer in a separate thread (use rig as key, not character)
		FadeTimers[rig] = task.spawn(function()
			fadeOutDeadRagdoll(rig, rig.Name)
		end)

		LogService:Info("RAGDOLL", "Death ragdoll created with fade timer", {
			RigName = rig.Name,
			FadeTime = Config.Gameplay.Character.Ragdoll.DeadRagdoll.FadeTime,
		})
	end

	LogService:Info("RAGDOLL", "Character ragdolled", {
		CharacterName = character.Name,
		MotorCount = #motorStates,
		ConstraintCount = #ragdollConstraints,
	})

	return true
end

function RagdollSystem:UnragdollCharacter(character)
	local state = RagdollState[character]
	if not state then
		return false
	end

	-- Get the rig (now in workspace.Rigs)
	local rig = CharacterLocations:GetRig(character)
	if not rig then
		return false
	end

	-- Destroy ragdoll constraints
	for motorName, constraint in pairs(state.RagdollConstraints) do
		if constraint and constraint.Parent then
			constraint:Destroy()
		end
	end

	-- Restore motors
	for motorName, motorData in pairs(state.MotorStates) do
		local motor = motorData.Motor
		if motor and motor.Parent then
			motor.C0 = motorData.OriginalC0
			motor.C1 = motorData.OriginalC1
			motor.Enabled = motorData.OriginalEnabled
		end
	end

	-- Reset physics
	resetPhysics(rig)

	-- Make rig parts non-physical again
	CharacterLocations:ForEachRigPart(character, function(rigPart)
		rigPart.CanCollide = false
		rigPart.Massless = true

		-- Stop all velocities
		if rigPart:IsA("BasePart") then
			rigPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			rigPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		end
	end)

	-- Re-anchor HumanoidRootPart for BulkMoveTo sync
	local hrp = rig:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = true
	end

	-- Clean up ragdoll attachments
	CharacterLocations:ForEachRigPart(character, function(rigPart)
		for _, child in pairs(rigPart:GetChildren()) do
			if child:IsA("Attachment") and child.Name:find("RagdollAttachment_") then
				child:Destroy()
			end
		end
	end)

	-- Re-enable BulkMoveTo sync for local player's Rig
	character:SetAttribute("RagdollActive", false)

	-- Clear state
	RagdollState[character] = nil

	LogService:Info("RAGDOLL", "Character unragdolled", {
		CharacterName = character.Name,
	})

	return true
end

function RagdollSystem:IsRagdolled(character)
	return RagdollState[character] ~= nil
end

function RagdollSystem:GetRagdollDuration(character)
	local state = RagdollState[character]
	if not state then
		return 0
	end

	return tick() - state.StartTime
end

function RagdollSystem:Cleanup(character)
	-- Get rig to cancel its fade timer
	local rig = CharacterLocations:GetRig(character)
	if rig and FadeTimers[rig] then
		task.cancel(FadeTimers[rig])
		FadeTimers[rig] = nil
	end

	if RagdollState[character] then
		self:UnragdollCharacter(character)
	end
end

return RagdollSystem
