local CharacterController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local RigManager = require(Locations.Game:WaitForChild("Character"):WaitForChild("Rig"):WaitForChild("RigManager"))
local RagdollSystem = require(Locations.Game:WaitForChild("Character"):WaitForChild("Rig"):WaitForChild("RagdollSystem"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local CharacterUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterUtils"))
local CrouchUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("CrouchUtils"))
local MovementUtils = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementUtils"))

CharacterController._net = nil
CharacterController._registry = nil
CharacterController._spawnRequested = false
CharacterController._setupInProgress = {}
CharacterController._deathConnections = {}
CharacterController._healthConnections = {}
CharacterController._respawnRequested = false

-- Ragdoll tracking
CharacterController._activeRagdolls = {} -- [player] = ragdoll model
CharacterController._savedCameraMode = nil -- Saved camera mode before ragdoll

function CharacterController:_applyRigCollisionFilters(character)
	CharacterLocations:ForEachRigPart(character, function(part)

		task.delay(3, function()
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end)

	end)
end

function CharacterController:Init(registry, net)
	self._registry = registry
	self._net = net

	RigManager:Init()

	self._net:ConnectClient("ServerReady", function()
		self:_requestSpawn("ServerReady")
	end)

	self._net:ConnectClient("CharacterSpawned", function(character)
		warn("[CLIENT_TRACE] CharacterSpawned received char=" .. (character and character.Name or "nil"))
		self:_onCharacterSpawned(character)
	end)

	self._net:ConnectClient("CharacterRemoving", function(character)
		warn("[CLIENT_TRACE] CharacterRemoving received char=" .. (character and character.Name or "nil"))
		self:_onCharacterRemoving(character)
	end)

	self._net:ConnectClient("PlayerRagdolled", function(player, ragdollData)
		warn("[CLIENT_TRACE] PlayerRagdolled received player=" .. (player and player.Name or "nil"))
		self:_onPlayerRagdolled(player, ragdollData)
	end)

	-- Ragdoll events
	self._net:ConnectClient("RagdollStarted", function(player, ragdoll)
		warn("[CLIENT_TRACE] RagdollStarted received player=" .. (player and player.Name or "nil"))
		self:_onRagdollStarted(player, ragdoll)
	end)

	self._net:ConnectClient("RagdollEnded", function(player)
		warn("[CLIENT_TRACE] RagdollEnded received player=" .. (player and player.Name or "nil"))
		self:_onRagdollEnded(player)
	end)

	task.spawn(function()
		task.wait(3)
		self:_requestSpawn("Fallback")
	end)
end

function CharacterController:Start()
	-- No-op for now.
end

function CharacterController:_requestSpawn(source)
	if self._spawnRequested then
		return
	end

	self._spawnRequested = true
	self._net:FireServer("RequestCharacterSpawn")
end

function CharacterController:_onCharacterSpawned(character)
	if not character or not character.Parent then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		player = Players:FindFirstChild(character.Name)
	end
	if not player then
		return
	end

	if self._setupInProgress[character] then
		return
	end
	self._setupInProgress[character] = true

	if player == Players.LocalPlayer then
		self._respawnRequested = false
		self:_setupLocalCharacter(player, character)
		self._net:FireServer("CharacterSetupComplete")
		self._net:FireServer("RequestInitialStates")
	else
		self:_setupRemoteCharacter(player, character)
	end

	self._setupInProgress[character] = nil
end

function CharacterController:_onCharacterRemoving(character)
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		player = Players:FindFirstChild(character.Name)
	end
	if not player then
		return
	end

	local rig = RigManager:GetActiveRig(player)
	if rig then
		if rig:GetAttribute("IsRagdolled") then
			RigManager:MarkRigAsDead(rig)
		else
			RigManager:DestroyRig(rig)
		end
	end

	CrouchUtils:CleanupWelds(character)

	if player == Players.LocalPlayer then
		local connection = self._deathConnections[character]
		if connection then
			connection:Disconnect()
			self._deathConnections[character] = nil
		end

		local healthConn = self._healthConnections[character]
		if healthConn then
			if typeof(healthConn) == "RBXScriptConnection" then
				healthConn:Disconnect()
			elseif type(healthConn) == "table" and healthConn.Disconnect then
				healthConn:Disconnect()
			end
			self._healthConnections[character] = nil
		end

		local movementController = self._registry and self._registry:TryGet("Movement")
		if movementController and movementController.OnLocalCharacterRemoving then
			movementController:OnLocalCharacterRemoving()
		end

		local replicationController = self._registry and self._registry:TryGet("Replication")
		if replicationController and replicationController.OnLocalCharacterRemoving then
			replicationController:OnLocalCharacterRemoving()
		end
		local animationController = self._registry and self._registry:TryGet("AnimationController")
		if animationController and animationController.OnLocalCharacterRemoving then
			animationController:OnLocalCharacterRemoving()
		end
	else
		local animationController = self._registry and self._registry:TryGet("AnimationController")
		if animationController and animationController.OnOtherCharacterRemoving then
			animationController:OnOtherCharacterRemoving(character)
		end
	end
end

function CharacterController:_onPlayerRagdolled(player, ragdollData)
	if not player then
		return
	end

	local rig = RigManager:GetActiveRig(player)
	if not rig then
		return
	end

	if RagdollSystem:RagdollRig(rig, ragdollData) then
		RigManager:MarkRigAsDead(rig)
	end

	local replicationController = self._registry and self._registry:TryGet("Replication")
	if replicationController and replicationController.SetPlayerRagdolled then
		replicationController:SetPlayerRagdolled(player, true)
	end
end

function CharacterController:_setupLocalCharacter(player, character)
	local characterTemplate = ReplicatedStorage:WaitForChild("CharacterTemplate")

	local spawnPosition = character.PrimaryPart and character.PrimaryPart.Position or character:GetPivot().Position

	local exclude = {
		Rig = true,
		Hitbox = true,
		Humanoid = true,
		HumanoidRootPart = true,
		Head = true,
	}

	for _, templateChild in ipairs(characterTemplate:GetChildren()) do
		if not exclude[templateChild.Name] and not character:FindFirstChild(templateChild.Name) then
			local newObject = templateChild:Clone()
			newObject.Parent = character
		end
	end

	CharacterUtils:RestorePrimaryPartAfterClone(character, characterTemplate)

	if character.PrimaryPart then
		character:PivotTo(CFrame.new(spawnPosition))
	end

	local root = character:FindFirstChild("Root")
	if root and root:IsA("BasePart") then
		root.Anchored = false
		MovementUtils:SetupPhysicsConstraints(root)
	end

	if Config.Gameplay.Character.EnableRig then
		local rig = RigManager:GetActiveRig(player)
		if not rig then
			RigManager:CreateRig(player, character)
		end
		self:_applyRigCollisionFilters(character)
	end

	CrouchUtils:SetupLegacyWelds(character)

	CharacterLocations:ForEachColliderPart(character, function(part)
		part.Anchored = false
		part.Massless = false
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end)

	if root and root:IsA("BasePart") then
		root.Massless = false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	-- Safety: ensure direct humanoid parts are hidden/anchored even if setup was partial.
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		humanoidRootPart.Massless = true
		humanoidRootPart.CanCollide = false
		humanoidRootPart.CanQuery = false
		humanoidRootPart.CanTouch = false
		humanoidRootPart.Transparency = 1
		humanoidRootPart.Anchored = true
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "Head" then
			child.Massless = true
			child.CanCollide = false
			child.CanQuery = false
			child.CanTouch = false
			child.Transparency = 1
			child.Anchored = true
			break
		end
	end

	local movementController = self._registry and self._registry:TryGet("Movement")
	if movementController and movementController.OnLocalCharacterReady then
		movementController:OnLocalCharacterReady(character)
	end

	local animationController = self._registry and self._registry:TryGet("AnimationController")
	if animationController and animationController.OnLocalCharacterReady then
		animationController:OnLocalCharacterReady(character)
	end

	local replicationController = self._registry and self._registry:TryGet("Replication")
	if replicationController and replicationController.OnLocalCharacterReady then
		replicationController:OnLocalCharacterReady(character)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and not self._deathConnections[character] then
		self._deathConnections[character] = humanoid.Died:Connect(function()
			warn("[CHAR_DEATH] Humanoid.Died -> RequestRespawn")
			if self._respawnRequested then
				return
			end
			self._respawnRequested = true
			self._net:FireServer("RequestRespawn")
		end)
	end

	-- Keep HUD health in sync with the local humanoid.
	-- HUD reads Players.LocalPlayer attributes "Health" and "MaxHealth".
	if humanoid and not self._healthConnections[character] then
		local localPlayer = Players.LocalPlayer
		local function publishHealth()
			if not humanoid.Parent then
				return
			end
			if localPlayer then
				localPlayer:SetAttribute("Health", humanoid.Health)
				localPlayer:SetAttribute("MaxHealth", humanoid.MaxHealth)
			end
		end

		local c1 = humanoid.HealthChanged:Connect(function()
			publishHealth()
		end)
		local c2 = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			publishHealth()
		end)

		-- Store as a small composite disconnectable.
		self._healthConnections[character] = {
			Disconnect = function()
				c1:Disconnect()
				c2:Disconnect()
			end,
		}

		publishHealth()
	end
end

function CharacterController:_setupRemoteCharacter(player, character)
	if not character.PrimaryPart then
		character:GetPropertyChangedSignal("PrimaryPart"):Wait()
	end

	local rig = nil
	if Config.Gameplay.Character.EnableRig then
		rig = RigManager:GetActiveRig(player)
		if rig then
			self:_applyRigCollisionFilters(character)
			return
		end

		rig = RigManager:CreateRig(player, character)
		if not rig or not character.PrimaryPart then
			return
		end
		self:_applyRigCollisionFilters(character)
	else
		return
	end

	local animationController = self._registry and self._registry:TryGet("AnimationController")
	if animationController and animationController.OnOtherCharacterSpawned then
		animationController:OnOtherCharacterSpawned(character)
	end

	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	local rigOffset = CFrame.new()
	if characterTemplate then
		local templateRoot = characterTemplate:FindFirstChild("Root")
		local templateRig = characterTemplate:FindFirstChild("Rig")
		local templateRigHRP = templateRig and templateRig:FindFirstChild("HumanoidRootPart")
		if templateRoot and templateRigHRP then
			rigOffset = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
		end
	end

	-- Use Root if available, fallback to PrimaryPart for remote characters
	local rootPart = character:FindFirstChild("Root") or character.PrimaryPart
	if not rootPart then
		return
	end
	local targetCFrame = rootPart.CFrame * rigOffset
	for _, part in ipairs(rig:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame = targetCFrame
		end
	end
end

-- =============================================================================
-- RAGDOLL SYSTEM
-- =============================================================================

function CharacterController:GetRagdoll(player)
	return self._activeRagdolls[player]
end

function CharacterController:IsRagdolled(player)
	return self._activeRagdolls[player] ~= nil
end

function CharacterController:_onRagdollStarted(player, ragdoll)
	if not player or not ragdoll then
		return
	end

	self._activeRagdolls[player] = ragdoll

	-- If this is the local player, switch camera to ragdoll mode
	if player == Players.LocalPlayer then
		local cameraController = self._registry and self._registry:TryGet("Camera")
		if cameraController then
			-- Save current camera mode
			if cameraController.GetCurrentMode then
				self._savedCameraMode = cameraController:GetCurrentMode()
			end

			-- Force orbit mode and focus on ragdoll head
			local ragdollHead = ragdoll:FindFirstChild("Head")
			if ragdollHead then
				if cameraController.SetRagdollFocus then
					cameraController:SetRagdollFocus(ragdollHead)
				end
			end
		end

		print("[CharacterController] Local player ragdoll started")
	end
end

function CharacterController:_onRagdollEnded(player)
	if not player then
		return
	end

	self._activeRagdolls[player] = nil

	-- If this is the local player, restore camera
	if player == Players.LocalPlayer then
		local cameraController = self._registry and self._registry:TryGet("Camera")
		if cameraController then
			if cameraController.ClearRagdollFocus then
				cameraController:ClearRagdollFocus()
			end

			-- Restore saved camera mode
			if self._savedCameraMode and cameraController.SetCameraMode then
				cameraController:SetCameraMode(self._savedCameraMode)
			end
			self._savedCameraMode = nil
		end

		print("[CharacterController] Local player ragdoll ended")
	end
end

return CharacterController
