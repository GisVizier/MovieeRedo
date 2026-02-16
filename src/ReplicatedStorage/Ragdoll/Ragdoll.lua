--[[
	Ragdoll.lua - Clone-Based Ragdoll System
	
	Uses a CLONE of the rig for ragdoll physics.
	Original rig is hidden during ragdoll, then shown on recovery.
	This avoids complex state management on the original rig.
	
	API:
		Module.Ragdoll(target, knockbackForce?, duration?)
		Module.GetBackUp(target)
		Module.IsRagdolled(target) -> boolean
		Module.SetupRig(player, rig, character) -- Called by RigManager
		Module.CleanupRig(rig) -- Called when rig destroyed
]]

local Module = {}
Module.RagdollStates = {} -- Server: [player] = true
Module.Ragdollers = {}    -- Client: [rig] = RagdollData

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local IsClient = RunService:IsClient()
local IsServer = RunService:IsServer()

-- Collision group for ragdolls
local RAGDOLL_GROUP = "Ragdolls"
pcall(function()
	PhysicsService:RegisterCollisionGroup(RAGDOLL_GROUP)
	PhysicsService:CollisionGroupSetCollidable(RAGDOLL_GROUP, RAGDOLL_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(RAGDOLL_GROUP, "Players", false)
	PhysicsService:CollisionGroupSetCollidable(RAGDOLL_GROUP, "Default", true)
end)

-- Physics properties for ragdoll parts
local RAGDOLL_PHYSICS = PhysicalProperties.new(0.7, 0.3, 0.1, 1, 1)

-- Joint configuration
local JOINT_CONFIG = {
	["Neck"] = { UpperAngle = 45, TwistLower = -70, TwistUpper = 70, TwistEnabled = true },
	["Left Shoulder"] = { UpperAngle = 110, TwistLower = -85, TwistUpper = 85, TwistEnabled = true },
	["Right Shoulder"] = { UpperAngle = 110, TwistLower = -85, TwistUpper = 85, TwistEnabled = true },
	["Left Hip"] = { UpperAngle = 90, TwistLower = -45, TwistUpper = 45, TwistEnabled = false },
	["Right Hip"] = { UpperAngle = 90, TwistLower = -45, TwistUpper = 45, TwistEnabled = false },
}

local JOINT_OFFSETS = {
	["Neck"] = { C0 = CFrame.new(0, 1, 0), C1 = CFrame.new(0, -0.5, 0) },
	["Left Shoulder"] = { C0 = CFrame.new(-1.3, 0.75, 0), C1 = CFrame.new(0.2, 0.75, 0) },
	["Right Shoulder"] = { C0 = CFrame.new(1.3, 0.75, 0), C1 = CFrame.new(-0.2, 0.75, 0) },
	["Left Hip"] = { C0 = CFrame.new(-0.5, -1, 0), C1 = CFrame.new(0, 1, 0) },
	["Right Hip"] = { C0 = CFrame.new(0.5, -1, 0), C1 = CFrame.new(0, 1, 0) },
}

-- Limb collider sizes (from 4thAxis)
local COLLIDER_SIZES = {
	["Head"] = Vector3.new(1, 1, 1),
	["Torso"] = Vector3.new(2, 2, 1),
	["Left Arm"] = Vector3.new(1, 2, 1),
	["Right Arm"] = Vector3.new(1, 2, 1),
	["Left Leg"] = Vector3.new(1, 2, 1),
	["Right Leg"] = Vector3.new(1, 2, 1),
}

-- Create invisible collision part for a limb (from 4thAxis original)
local function createJointCollider(limb)
	local collider = Instance.new("Part")
	collider.Name = "JointCollider"
	collider.Size = COLLIDER_SIZES[limb.Name] or Vector3.new(1, 1, 1)
	collider.Transparency = 1
	collider.BrickColor = BrickColor.new("Really red")
	collider.CanCollide = true
	collider.Massless = true
	collider.CustomPhysicalProperties = RAGDOLL_PHYSICS
	
	pcall(function()
		collider.CollisionGroup = RAGDOLL_GROUP
	end)
	
	-- Weld to limb
	local weld = Instance.new("Weld")
	weld.Part0 = collider
	weld.Part1 = limb
	weld.C0 = CFrame.identity
	weld.Parent = collider
	
	collider.Parent = limb
	return collider
end

local function resolvePlayer(target)
	if typeof(target) ~= "Instance" then return nil end
	if target:IsA("Player") then return target end
	if target:IsA("Model") then
		return Players:GetPlayerFromCharacter(target) or Players:FindFirstChild(target.Name)
	end
	return nil
end

local function getRemote()
	local remote = script:FindFirstChild("RagdollEvent")
	if not remote then
		if IsServer then
			remote = Instance.new("RemoteEvent")
			remote.Name = "RagdollEvent"
			remote.Parent = script
		else
			remote = script:WaitForChild("RagdollEvent", 10)
		end
	end
	return remote
end

local RagdollEvent = getRemote()

-- =============================================================================
-- SHARED
-- =============================================================================

function Module.IsRagdolled(target)
	local player = resolvePlayer(target)
	if not player then return false end
	
	if IsServer then
		return Module.RagdollStates[player] == true
	else
		for _, data in Module.Ragdollers do
			if data.Player == player then
				return data.IsActive
			end
		end
		local char = player.Character
		return char and char:GetAttribute("RagdollActive") == true
	end
end

function Module.GetRig(target)
	local player = resolvePlayer(target)
	if not player then return nil end
	
	for rig, data in Module.Ragdollers do
		if data.Player == player then
			-- Return the ragdoll clone if active, otherwise the original rig
			return data.RagdollClone or rig
		end
	end
	return nil
end

-- =============================================================================
-- SERVER
-- =============================================================================

if IsServer then
	function Module.Ragdoll(target, knockbackForce, duration)
		local player = resolvePlayer(target)
		if not player or Module.RagdollStates[player] then return false end
		
		local character = player.Character
		if not character then return false end
		
		Module.RagdollStates[player] = true
		character:SetAttribute("RagdollActive", true)
		RagdollEvent:FireAllClients(player, true, knockbackForce)
		
		if duration and duration > 0 then
			task.delay(duration, function()
				if Module.RagdollStates[player] then
					Module.GetBackUp(player)
				end
			end)
		end
		return true
	end
	
	function Module.GetBackUp(target)
		local player = resolvePlayer(target)
		if not player or not Module.RagdollStates[player] then return false end
		
		Module.RagdollStates[player] = nil
		local character = player.Character
		if character then
			character:SetAttribute("RagdollActive", false)
		end
		RagdollEvent:FireAllClients(player, false)
		return true
	end
	
	RagdollEvent.OnServerEvent:Connect(function(player, targetPlayer, isRagdoll, force, dur)
		local resolved = resolvePlayer(targetPlayer)
		if resolved ~= player then return end
		if isRagdoll then
			Module.Ragdoll(player, force, dur)
		else
			Module.GetBackUp(player)
		end
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		Module.RagdollStates[player] = nil
	end)
end

-- =============================================================================
-- CLIENT
-- =============================================================================

if IsClient then
	local LocalPlayer = Players.LocalPlayer
	
	-- Register rig for ragdolling (called by RigManager)
	function Module.SetupRig(player, rig, character)
		if Module.Ragdollers[rig] then return end
		
		Module.Ragdollers[rig] = {
			Player = player,
			Rig = rig,
			Character = character,
			IsActive = false,
			RagdollClone = nil,
			SavedState = nil,
		}
	end
	
	function Module.CleanupRig(rig)
		local data = Module.Ragdollers[rig]
		if data then
			if data.RagdollClone and data.RagdollClone.Parent then
				data.RagdollClone:Destroy()
			end
			Module.Ragdollers[rig] = nil
		end
	end
	
	-- Create ragdoll clone with physics constraints (4thAxis style with JointColliders)
	local function createRagdollClone(rig)
		local clone = rig:Clone()
		clone.Name = rig.Name .. "_Ragdoll"
		
		-- Remove Highlights from clone
		for _, desc in clone:GetDescendants() do
			if desc:IsA("Highlight") then
				desc:Destroy()
			end
		end

		-- Remove third-person weapon models (no weapons visible on death)
		for _, child in ipairs(clone:GetChildren()) do
			if child:IsA("Model") and string.match(child.Name, "^ThirdPerson_") then
				child:Destroy()
			end
		end

		-- Collect main limb parts for colliders
		local mainLimbs = {}
		for _, part in clone:GetChildren() do
			if part:IsA("BasePart") and COLLIDER_SIZES[part.Name] then
				mainLimbs[part.Name] = part
			end
		end
		
		-- Setup constraints for each motor
		for _, motor in clone:GetDescendants() do
			if motor:IsA("Motor6D") and JOINT_OFFSETS[motor.Name] then
				local offsets = JOINT_OFFSETS[motor.Name]
				local config = JOINT_CONFIG[motor.Name] or JOINT_CONFIG["Left Hip"]
				
				-- Create attachments
				local att0 = Instance.new("Attachment")
				att0.Name = "RagdollAtt0"
				att0.CFrame = offsets.C0
				att0.Parent = motor.Part0
				
				local att1 = Instance.new("Attachment")
				att1.Name = "RagdollAtt1"
				att1.CFrame = offsets.C1
				att1.Parent = motor.Part1
				
				-- Create constraint with full 4thAxis physics properties
				local constraint = Instance.new("BallSocketConstraint")
				constraint.Name = "RagdollJoint"
				constraint.Attachment0 = att0
				constraint.Attachment1 = att1
				constraint.LimitsEnabled = true
				constraint.UpperAngle = config.UpperAngle
				constraint.TwistLimitsEnabled = config.TwistEnabled
				constraint.TwistLowerAngle = config.TwistLower
				constraint.TwistUpperAngle = config.TwistUpper
				-- Key physics properties from 4thAxis
				constraint.Radius = 0.15
				constraint.MaxFrictionTorque = 50
				constraint.Restitution = 0
				constraint.Parent = motor.Part0
				
				-- Disable the motor
				motor.Enabled = false
			end
		end
		
		-- Setup humanoid for ragdoll
		local hum = clone:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			hum:ChangeState(Enum.HumanoidStateType.Physics)
			hum.AutoRotate = false
			hum.RequiresNeck = false
			hum.PlatformStand = true
		end
		
		-- Setup physics on parts - visual parts are NON-COLLIDEABLE, only JointColliders collide
		for _, part in clone:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
				part.Massless = false
				-- Visual parts don't collide - JointColliders handle collision
				part.CanCollide = false
				part.CustomPhysicalProperties = RAGDOLL_PHYSICS
				pcall(function()
					part.CollisionGroup = RAGDOLL_GROUP
				end)
			end
		end
		
		-- Create JointColliders for main limbs (this is what makes ragdolls feel natural)
		for limbName, limb in mainLimbs do
			createJointCollider(limb)
		end
		
		return clone
	end
	
	-- Activate ragdoll
	local function activate(player, knockbackForce)
		local data
		for _, d in Module.Ragdollers do
			if d.Player == player then data = d break end
		end
		if not data or data.IsActive then return end
		
		local rig = data.Rig
		local character = data.Character or player.Character
		local root = character and character:FindFirstChild("Root")
		
		-- Calculate ground offset while standing
		local groundOffset = 3
		if root then
			local collider = character:FindFirstChild("Collider")
			local feet = collider and collider:FindFirstChild("Default") and collider.Default:FindFirstChild("Feet")
			if feet then
				groundOffset = root.Position.Y - (feet.Position.Y - feet.Size.Y / 2)
			end
		end
		
		-- Save state
		data.SavedState = {
			GroundOffset = groundOffset,
		}
		
		if root then
			data.SavedState.RootAnchored = root.Anchored
			local ao = root:FindFirstChild("AlignOrientation")
			local vf = root:FindFirstChild("VectorForce")
			if ao then data.SavedState.AOEnabled = ao.Enabled; ao.Enabled = false end
			if vf then data.SavedState.VFEnabled = vf.Enabled; vf.Enabled = false end
			root.Anchored = true
		end
		
		-- Disable character humanoid states
		local charHum = character and character:FindFirstChildOfClass("Humanoid")
		if charHum then
			charHum:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
			charHum:SetStateEnabled(Enum.HumanoidStateType.Running, false)
		end
		
		-- Create ragdoll clone
		local ragdollClone = createRagdollClone(rig)
		ragdollClone.Parent = Workspace:FindFirstChild("Rigs") or Workspace
		data.RagdollClone = ragdollClone
		
		-- Hide original rig (save original transparencies for parts, decals, particles)
		data.SavedTransparencies = {}
		data.SavedParticles = {}
		for _, desc in rig:GetDescendants() do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				data.SavedTransparencies[desc] = desc.Transparency
				desc.Transparency = 1
			elseif desc:IsA("ParticleEmitter") then
				data.SavedParticles[desc] = desc.Enabled
				desc.Enabled = false
			end
		end
		
		data.IsActive = true
		rig:SetAttribute("IsRagdolled", true)
		
		-- Apply knockback to clone
		local cloneHRP = ragdollClone:FindFirstChild("HumanoidRootPart")
		if cloneHRP and knockbackForce then
			local velocity = nil
			if typeof(knockbackForce) == "Vector3" then
				velocity = knockbackForce
			else
				local magnitude = tonumber(knockbackForce) or 0
				if magnitude > 0 then
					velocity = cloneHRP.CFrame.LookVector * magnitude
				end
			end

			if typeof(velocity) == "Vector3" and velocity.Magnitude > 0.001 then
				cloneHRP.AssemblyLinearVelocity = velocity
				cloneHRP:ApplyImpulse(velocity * math.max(cloneHRP.AssemblyMass, 1))

				-- Deterministic tumble derived from fling direction (matches RagdollSystem)
				local horiz = Vector3.new(velocity.X, 0, velocity.Z)
				local tumbleAxis = horiz.Magnitude > 0.001 and Vector3.new(-horiz.Z, 0, horiz.X) or Vector3.new(1, 0, 0)
				cloneHRP.AssemblyAngularVelocity = tumbleAxis.Unit * 6
			end
		end
	end
	
	-- Deactivate ragdoll
	local function deactivate(player)
		local data
		for _, d in Module.Ragdollers do
			if d.Player == player then data = d break end
		end
		if not data or not data.IsActive then return end
		
		local rig = data.Rig
		local character = data.Character or player.Character
		local root = character and character:FindFirstChild("Root")
		local ragdollClone = data.RagdollClone
		local saved = data.SavedState or {}
		
		-- Get final position from ragdoll clone
		local finalPos = nil
		if ragdollClone then
			local cloneHRP = ragdollClone:FindFirstChild("HumanoidRootPart")
			if cloneHRP then
				finalPos = cloneHRP.Position
			end
		end
		
		-- Find ground
		local groundY = nil
		if finalPos then
			local params = RaycastParams.new()
			params.FilterDescendantsInstances = { character, rig, ragdollClone }
			params.FilterType = Enum.RaycastFilterType.Exclude
			local result = Workspace:Raycast(finalPos + Vector3.new(0, 3, 0), Vector3.new(0, -50, 0), params)
			if result then
				groundY = result.Position.Y
			end
		end
		
		-- Destroy ragdoll clone
		if ragdollClone then
			ragdollClone:Destroy()
			data.RagdollClone = nil
		end
		
		-- Show original rig (restore original transparencies + particles)
		local savedTransparencies = data.SavedTransparencies or {}
		local savedParticles = data.SavedParticles or {}
		for _, desc in rig:GetDescendants() do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				desc.Transparency = savedTransparencies[desc] or 0
			elseif desc:IsA("ParticleEmitter") then
				desc.Enabled = savedParticles[desc] ~= nil and savedParticles[desc] or true
			end
		end
		data.SavedTransparencies = nil
		data.SavedParticles = nil
		
		-- Position Root at final location
		if root and finalPos then
			local offset = saved.GroundOffset or 3
			local targetY = groundY and (groundY + offset) or finalPos.Y
			local _, yaw, _ = root.CFrame:ToOrientation()
			root.CFrame = CFrame.new(finalPos.X, targetY, finalPos.Z) * CFrame.Angles(0, yaw, 0)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		
		-- Enable movement forces
		if root then
			local ao = root:FindFirstChild("AlignOrientation")
			local vf = root:FindFirstChild("VectorForce")
			if ao and saved.AOEnabled ~= nil then ao.Enabled = saved.AOEnabled end
			if vf and saved.VFEnabled ~= nil then vf.Enabled = saved.VFEnabled end
			root.Anchored = saved.RootAnchored or false
		end
		
		-- Restore character humanoid
		local charHum = character and character:FindFirstChildOfClass("Humanoid")
		if charHum then
			charHum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
			charHum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
			charHum:ChangeState(Enum.HumanoidStateType.Running)
		end
		
		data.IsActive = false
		rig:SetAttribute("IsRagdolled", false)
		data.SavedState = nil
	end
	
	-- Public API
	function Module.Ragdoll(target, knockbackForce, duration)
		local player = resolvePlayer(target)
		if player == LocalPlayer then
			RagdollEvent:FireServer(player, true, knockbackForce, duration)
			activate(player, knockbackForce)
		end
	end
	
	function Module.GetBackUp(target)
		local player = resolvePlayer(target)
		if player == LocalPlayer then
			RagdollEvent:FireServer(player, false)
			deactivate(player)
		end
	end
	
	-- Listen for server events
	RagdollEvent.OnClientEvent:Connect(function(player, isRagdoll, force)
		if isRagdoll then
			activate(player, force)
		else
			deactivate(player)
		end
	end)
end

return Module
