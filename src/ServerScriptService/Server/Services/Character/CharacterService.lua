local CharacterService = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))

CharacterService.ActiveCharacters = {}
CharacterService.ActiveRagdolls = {} -- [player] = ragdoll model
CharacterService.RagdollWelds = {} -- [player] = WeldConstraint
CharacterService.IsClientSetupComplete = {}
CharacterService.IsSpawningCharacter = {}

-- R6 motor names and their joint config mappings
local MOTOR_TO_JOINT_CONFIG = {
	["Neck"] = "Neck",
	["Left Shoulder"] = "Shoulder",
	["Right Shoulder"] = "Shoulder",
	["Left Hip"] = "Hip",
	["Right Hip"] = "Hip",
	["RootJoint"] = "RootJoint",
}

function CharacterService:Init(registry, net)
	self._registry = registry
	self._net = net

	Players.CharacterAutoLoads = false

	self:_cacheTemplate()
	self:_ensureEntitiesContainer()
	self:_createRagdollContainer()
	self:_bindRemotes()

	Players.PlayerRemoving:Connect(function(player)
		self:EndRagdoll(player)
		self:RemoveCharacter(player)
	end)
end

function CharacterService:Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			task.wait(0.5)
			self._net:FireClient("ServerReady", player)
		end)

			self:_sendExistingCharacters(player)
	end)
end

function CharacterService:_cacheTemplate()
	local modelsFolder = ServerStorage:FindFirstChild("Models")
	if not modelsFolder then
		error("ServerStorage.Models folder missing")
	end

	self._template = modelsFolder:FindFirstChild("Character")
	if not self._template then
		error("ServerStorage.Models.Character template missing")
	end
end

function CharacterService:_bindRemotes()
	self._net:ConnectServer("RequestCharacterSpawn", function(player)
		self:SpawnCharacter(player)
	end)

	self._net:ConnectServer("RequestRespawn", function(player)
		if self.IsSpawningCharacter[player.UserId] then
			return
		end

		if not self.IsClientSetupComplete[player.UserId] then
			return
		end

		self:SpawnCharacter(player)
	end)

	self._net:ConnectServer("CharacterSetupComplete", function(player)
		self.IsClientSetupComplete[player.UserId] = true
	end)

	self._net:ConnectServer("CrouchStateChanged", function(player, isCrouching)
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				self._net:FireClient("CrouchStateChanged", otherPlayer, player, isCrouching)
			end
		end
	end)

	-- Ragdoll test toggle
	self._net:ConnectServer("ToggleRagdollTest", function(player)
		if self.ActiveRagdolls[player] then
			self:EndRagdoll(player)
		else
			self:StartRagdoll(player)
		end
	end)
end

function CharacterService:_createRagdollContainer()
	local container = workspace:FindFirstChild("Ragdolls")
	if not container then
		container = Instance.new("Folder")
		container.Name = "Ragdolls"
		container.Parent = workspace
	end
	self._ragdollContainer = container
end

function CharacterService:_ensureEntitiesContainer()
	local container = workspace:FindFirstChild("Entities")
	if not container then
		container = Instance.new("Folder")
		container.Name = "Entities"
		container.Parent = workspace
	end
	self._entitiesContainer = container
end

function CharacterService:_sendExistingCharacters(player)
	for otherPlayer, character in pairs(self.ActiveCharacters) do
		if otherPlayer ~= player and character and character.Parent then
			self._net:FireClient("CharacterSpawned", player, character)
		end
	end
end

function CharacterService:SpawnCharacter(player)
	if not self._template then
		self:_cacheTemplate()
	end

	if self.IsSpawningCharacter[player.UserId] then
		return nil
	end
	self.IsSpawningCharacter[player.UserId] = true

	self:RemoveCharacter(player)

	local character = Instance.new("Model")
	character.Name = player.Name
	character.Parent = self._entitiesContainer or workspace

	local templateHumanoid = self._template:FindFirstChildOfClass("Humanoid")
	local templateRootPart = self._template:FindFirstChild("HumanoidRootPart")
	local templateHead = self._template:FindFirstChild("Head")

	if not templateHumanoid or not templateRootPart or not templateHead then
		self.IsSpawningCharacter[player.UserId] = nil
		error("Character template missing Humanoid/HRP/Head")
	end

	local humanoid = templateHumanoid:Clone()
	local humanoidRootPart = templateRootPart:Clone()
	local head = templateHead:Clone()

	humanoid.Parent = character
	humanoidRootPart.Parent = character
	head.Parent = character

	humanoidRootPart.Anchored = true
	humanoidRootPart.CanCollide = false
	head.Anchored = true
	head.CanCollide = false

	character.PrimaryPart = humanoidRootPart

	player.Character = character

	local spawnPosition = self:_getSpawnPosition()
	if character.PrimaryPart then
		character:PivotTo(CFrame.new(spawnPosition))
	end

	local headOffset = templateRootPart.CFrame:ToObjectSpace(templateHead.CFrame)
	head.CFrame = humanoidRootPart.CFrame * headOffset

	self.ActiveCharacters[player] = character
	self.IsClientSetupComplete[player.UserId] = false

	local replicationService = self._registry and self._registry:TryGet("ReplicationService")
	if replicationService and replicationService.RegisterPlayer then
		replicationService:RegisterPlayer(player)
	end

	self._net:FireAllClients("CharacterSpawned", character)

	self.IsSpawningCharacter[player.UserId] = nil
	return character
end

function CharacterService:RemoveCharacter(player)
	local character = self.ActiveCharacters[player]
	if not character then
		return
	end

	self._net:FireAllClients("CharacterRemoving", character)

	local replicationService = self._registry and self._registry:TryGet("ReplicationService")
	if replicationService and replicationService.UnregisterPlayer then
		replicationService:UnregisterPlayer(player)
	end

	if player.Character == character then
		player.Character = nil
	end

	character:Destroy()
	self.ActiveCharacters[player] = nil
	self.IsClientSetupComplete[player.UserId] = nil
	self.IsSpawningCharacter[player.UserId] = nil
end

function CharacterService:_getSpawnPosition()
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		return spawnLocation.Position + Vector3.new(0, 3, 0)
	end

	return Vector3.new(0, 5, 0)
end

-- =============================================================================
-- RAGDOLL SYSTEM
-- =============================================================================

function CharacterService:GetRagdoll(player)
	return self.ActiveRagdolls[player]
end

function CharacterService:IsRagdolled(player)
	return self.ActiveRagdolls[player] ~= nil
end

function CharacterService:StartRagdoll(player, options)
	options = options or {}

	-- Already ragdolled?
	if self.ActiveRagdolls[player] then
		return false
	end

	local character = self.ActiveCharacters[player]
	if not character or not character.Parent then
		return false
	end

	local root = character.PrimaryPart
	if not root then
		return false
	end

	-- Create ragdoll clone
	local ragdoll = self:_createRagdollClone(player, character)
	if not ragdoll then
		return false
	end

	-- Position ragdoll at character's current position
	local ragdollHRP = ragdoll:FindFirstChild("HumanoidRootPart")
	if ragdollHRP then
		ragdollHRP.CFrame = root.CFrame
	end

	-- Parent ragdoll to container
	ragdoll.Parent = self._ragdollContainer

	-- Convert motors to ragdoll constraints
	self:_convertMotorsToConstraints(ragdoll)

	-- Apply ragdoll physics properties
	self:_applyRagdollPhysics(ragdoll)

	-- Apply collision group
	self:_applyRagdollCollisionGroup(ragdoll)

	-- Weld ragdoll HRP to character Root (bean follows ragdoll)
	local weld = self:_createRagdollWeld(ragdollHRP, root)
	self.RagdollWelds[player] = weld

	-- Set network owner to server for consistent replication
	for _, part in ipairs(ragdoll:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part:SetNetworkOwner(nil)
			end)
		end
	end

	-- Store ragdoll reference
	self.ActiveRagdolls[player] = ragdoll

	-- Set RagdollActive attribute on character
	character:SetAttribute("RagdollActive", true)

	-- Apply random fling impulse
	if ragdollHRP then
		local randomDir = Vector3.new(
			math.random() * 2 - 1,
			math.random() * 0.5 + 0.5, -- Mostly upward
			math.random() * 2 - 1
		).Unit
		local flingStrength = options.FlingStrength or 80
		local impulse = randomDir * flingStrength * ragdollHRP.AssemblyMass
		ragdollHRP:ApplyImpulse(impulse)

		-- Also apply some angular velocity for tumbling
		ragdollHRP.AssemblyAngularVelocity = Vector3.new(
			math.random() * 10 - 5,
			math.random() * 5 - 2.5,
			math.random() * 10 - 5
		)
	end

	-- Fire RagdollStarted to all clients
	self._net:FireAllClients("RagdollStarted", player, ragdoll)

	return true
end

function CharacterService:EndRagdoll(player)
	local ragdoll = self.ActiveRagdolls[player]
	if not ragdoll then
		return false
	end

	-- Remove weld
	local weld = self.RagdollWelds[player]
	if weld and weld.Parent then
		weld:Destroy()
	end
	self.RagdollWelds[player] = nil

	-- Get ragdoll position before destroying
	local ragdollHRP = ragdoll:FindFirstChild("HumanoidRootPart")
	local ragdollPosition = ragdollHRP and ragdollHRP.Position or nil

	-- Destroy ragdoll
	ragdoll:Destroy()
	self.ActiveRagdolls[player] = nil

	-- Clear RagdollActive attribute
	local character = self.ActiveCharacters[player]
	if character then
		character:SetAttribute("RagdollActive", false)

		-- Optionally reposition the character Root to where ragdoll ended
		local root = character:FindFirstChild("Root")
		if root and ragdollPosition then
			-- Keep character at ragdoll's final position
			root.CFrame = CFrame.new(ragdollPosition) * CFrame.Angles(0, math.rad(root.CFrame:ToEulerAnglesYXZ()), 0)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- Fire RagdollEnded to all clients
	self._net:FireAllClients("RagdollEnded", player)

	return true
end

function CharacterService:_createRagdollClone(player, character)
	-- Get the rig template from CharacterTemplate
	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not characterTemplate then
		warn("[CharacterService] CharacterTemplate not found")
		return nil
	end

	local templateRig = characterTemplate:FindFirstChild("Rig")
	if not templateRig then
		warn("[CharacterService] CharacterTemplate Rig not found")
		return nil
	end

	-- Clone the rig
	local ragdoll = templateRig:Clone()
	ragdoll.Name = player.Name .. "_Ragdoll"
	ragdoll:SetAttribute("OwnerUserId", player.UserId)
	ragdoll:SetAttribute("OwnerName", player.Name)
	ragdoll:SetAttribute("IsRagdoll", true)

	-- Apply player's appearance
	local humanoid = ragdoll:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Ensure animator exists
		if not humanoid:FindFirstChildOfClass("Animator") then
			local animator = Instance.new("Animator")
			animator.Parent = humanoid
		end

		-- Apply appearance asynchronously
		task.spawn(function()
			local ok, desc = pcall(function()
				return Players:GetHumanoidDescriptionFromUserId(player.UserId)
			end)
			if ok and desc and humanoid.Parent then
				pcall(function()
					humanoid:ApplyDescription(desc)
				end)
			end
		end)
	end

	return ragdoll
end

function CharacterService:_convertMotorsToConstraints(ragdoll)
	local ragdollConfig = Config.Gameplay.Character.Ragdoll
	local jointLimits = ragdollConfig and ragdollConfig.JointLimits or {}

	local torso = ragdoll:FindFirstChild("Torso")
	local hrp = ragdoll:FindFirstChild("HumanoidRootPart")

	if not torso then
		warn("[CharacterService] Ragdoll has no Torso")
		return
	end

	-- Find all motors and convert them
	local motorsToProcess = {}

	-- RootJoint is in HumanoidRootPart
	if hrp then
		local rootJoint = hrp:FindFirstChild("RootJoint")
		if rootJoint and rootJoint:IsA("Motor6D") then
			motorsToProcess["RootJoint"] = rootJoint
		end
	end

	-- Other motors are in Torso
	for _, child in ipairs(torso:GetChildren()) do
		if child:IsA("Motor6D") then
			motorsToProcess[child.Name] = child
		end
	end

	-- Convert each motor to a BallSocketConstraint
	for motorName, motor in pairs(motorsToProcess) do
		local configKey = MOTOR_TO_JOINT_CONFIG[motorName]
		local config = configKey and jointLimits[configKey] or {}

		local part0 = motor.Part0
		local part1 = motor.Part1

		if part0 and part1 then
			-- Create attachments
			local att0 = Instance.new("Attachment")
			att0.Name = "RagdollAtt0_" .. motorName
			att0.CFrame = motor.C0
			att0.Parent = part0

			local att1 = Instance.new("Attachment")
			att1.Name = "RagdollAtt1_" .. motorName
			att1.CFrame = motor.C1
			att1.Parent = part1

			-- Create BallSocketConstraint
			local constraint = Instance.new("BallSocketConstraint")
			constraint.Name = "Ragdoll_" .. motorName
			constraint.Attachment0 = att0
			constraint.Attachment1 = att1
			constraint.LimitsEnabled = true
			constraint.UpperAngle = config.UpperAngle or 45

			if config.TwistLowerAngle and config.TwistUpperAngle then
				constraint.TwistLimitsEnabled = true
				constraint.TwistLowerAngle = config.TwistLowerAngle
				constraint.TwistUpperAngle = config.TwistUpperAngle
			end

			if config.MaxFrictionTorque then
				constraint.MaxFrictionTorque = config.MaxFrictionTorque
			end

			constraint.Parent = part0

			-- Disable the motor
			motor.Enabled = false
		end
	end
end

function CharacterService:_applyRagdollPhysics(ragdoll)
	local ragdollConfig = Config.Gameplay.Character.Ragdoll
	local physics = ragdollConfig and ragdollConfig.Physics or {}

	for _, part in ipairs(ragdoll:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = true
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = false
			part.Anchored = false

			-- Apply physical properties
			local density = physics.Density or 0.7
			local friction = physics.Friction or 0.5
			local elasticity = physics.Elasticity or 0

			if part.Name == "Head" then
				density = physics.HeadDensity or density
				friction = physics.HeadFriction or friction
			end

			part.CustomPhysicalProperties = PhysicalProperties.new(
				density,
				friction,
				elasticity,
				1, -- FrictionWeight
				1  -- ElasticityWeight
			)
		end
	end
end

function CharacterService:_applyRagdollCollisionGroup(ragdoll)
	-- Try to use "Ragdolls" collision group
	local success = pcall(function()
		PhysicsService:GetCollisionGroupId("Ragdolls")
	end)

	if not success then
		-- Register the collision group if it doesn't exist
		pcall(function()
			PhysicsService:RegisterCollisionGroup("Ragdolls")
			PhysicsService:CollisionGroupSetCollidable("Ragdolls", "Players", false)
			PhysicsService:CollisionGroupSetCollidable("Ragdolls", "Ragdolls", true)
		end)
	end

	for _, part in ipairs(ragdoll:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part.CollisionGroup = "Ragdolls"
			end)
		end
	end
end

function CharacterService:_createRagdollWeld(ragdollHRP, characterRoot)
	if not ragdollHRP or not characterRoot then
		return nil
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "RagdollToCharacterWeld"
	weld.Part0 = ragdollHRP
	weld.Part1 = characterRoot
	weld.Parent = ragdollHRP

	return weld
end

return CharacterService
