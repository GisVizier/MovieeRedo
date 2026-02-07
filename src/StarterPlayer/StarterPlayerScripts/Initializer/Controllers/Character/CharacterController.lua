local CharacterController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local RigManager = require(Locations.Game:WaitForChild("Character"):WaitForChild("Rig"):WaitForChild("RigManager"))
local RagdollModule = require(ReplicatedStorage:WaitForChild("Ragdoll"):WaitForChild("Ragdoll"))
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

-- Hitbox debug
CharacterController._hitboxDebugEnabled = false
CharacterController._remoteColliders = {} -- [character] = collider folder

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
		self:_onCharacterSpawned(character)
	end)

	self._net:ConnectClient("CharacterRemoving", function(character)
		self:_onCharacterRemoving(character)
	end)

	-- Legacy event (deprecated, use RagdollStarted instead)
	self._net:ConnectClient("PlayerRagdolled", function(player, ragdollData)
		self:_onPlayerRagdolled(player, ragdollData)
	end)

	-- Crouch state replication for remote player colliders
	self._net:ConnectClient("CrouchStateChanged", function(player, isCrouching)
		if player and player.Character and player ~= Players.LocalPlayer then
			self:_setRemoteColliderCrouch(player.Character, isCrouching)
		end
	end)

	-- Ragdoll events
	self._net:ConnectClient("RagdollStarted", function(player, ragdoll)
		self:_onRagdollStarted(player, ragdoll)
	end)

	self._net:ConnectClient("RagdollEnded", function(player)
		self:_onRagdollEnded(player)
	end)

	-- Respawn: server sends spawn position, client teleports (same as Exit gadget)
	self._net:ConnectClient("PlayerRespawned", function(data)
		if not data or not data.spawnPosition then
			return
		end

		local movementController = self._registry and self._registry:TryGet("Movement")
		if movementController and type(movementController.Teleport) == "function" then
			movementController:Teleport(data.spawnPosition, data.spawnLookVector)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		if character then
			self:_onCharacterRemoving(character)
		else
			self:_cleanupPlayer(player)
		end
	end)

	-- Hitbox debug keybind (F4 to toggle)
	local UserInputService = game:GetService("UserInputService")
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F4 then
			self:ToggleHitboxDebug()
		end
		-- Debug: H = test death (triggers full ragdoll -> respawn flow)
		if input.KeyCode == Enum.KeyCode.H then
			print("[CharacterController] Test death requested (H)")
			self._net:FireServer("RequestTestDeath")
		end
	end)

	self:_setupExistingCharacters()
	task.delay(1, function()
		self:_setupExistingCharacters()
	end)

	task.spawn(function()
		task.wait(3)
		self:_requestSpawn("Fallback")
	end)
end

function CharacterController:Start()
	-- No-op for now.
end

function CharacterController:_setupExistingCharacters()
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= Players.LocalPlayer then
			-- player.Character relies on property replication which can be slow.
			-- Fallback: look for character in Entities folder by player name.
			local character = player.Character
			if not character then
				local entities = workspace:FindFirstChild("Entities")
				if entities then
					character = entities:FindFirstChild(player.Name)
				end
				if not character then
					character = workspace:FindFirstChild(player.Name)
				end
			end
			if character then
				self:_onCharacterSpawned(character)
			end
		end
	end
end

function CharacterController:_cleanupPlayer(player)
	if not player then
		return
	end

	local rig = RigManager:GetActiveRig(player)
	if rig then
		RigManager:DestroyRig(rig)
	end

	for character, collider in pairs(self._remoteColliders) do
		if collider and collider:GetAttribute("OwnerUserId") == player.UserId then
			if collider.Parent then
				collider:Destroy()
			end
			self._remoteColliders[character] = nil
		elseif not character or not character.Parent then
			self._remoteColliders[character] = nil
		end
	end
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
		self._net:FireServer("ClientReplicationReady")
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
	-- Legacy event - redirect to new handler
	self:_onRagdollStarted(player, ragdollData)
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
			warn("[CHAR_DEATH] Humanoid.Died - server handles ragdoll and respawn")
			-- Respawn is now server-controlled via CombatService death ragdoll.
			-- The server will trigger ragdoll, wait for it to play, then respawn.
			-- We no longer fire RequestRespawn here to avoid racing the ragdoll.
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
		else
			rig = RigManager:CreateRig(player, character)
			if not rig or not character.PrimaryPart then
				return
			end
			self:_applyRigCollisionFilters(character)
		end
	end

	local animationController = self._registry and self._registry:TryGet("AnimationController")
	if animationController and animationController.OnOtherCharacterSpawned then
		animationController:OnOtherCharacterSpawned(character)
	end

	local characterTemplate = ReplicatedStorage:FindFirstChild("CharacterTemplate")
	if not characterTemplate then
		return
	end

	-- Clone Collider for remote character hit detection
	self:_setupRemoteCollider(character, characterTemplate)

	local rigOffset = CFrame.new()
	local templateRoot = characterTemplate:FindFirstChild("Root")
	local templateRig = characterTemplate:FindFirstChild("Rig")
	local templateRigHRP = templateRig and templateRig:FindFirstChild("HumanoidRootPart")
	if templateRoot and templateRigHRP then
		rigOffset = templateRoot.CFrame:Inverse() * templateRigHRP.CFrame
	end

	-- Use Root if available, fallback to PrimaryPart for remote characters
	local rootPart = character:FindFirstChild("Root") or character.PrimaryPart
	if not rootPart then
		return
	end

	if rig then
		local targetCFrame = rootPart.CFrame * rigOffset
		for _, part in ipairs(rig:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CFrame = targetCFrame
			end
		end
	end
end

-- Setup hit detection collider for remote characters
function CharacterController:_setupRemoteCollider(character, characterTemplate)
	-- Don't setup twice
	if character:FindFirstChild("Collider") then
		return
	end

	local templateCollider = characterTemplate:FindFirstChild("Collider")
	if not templateCollider then
		warn("[CharacterController] CharacterTemplate missing Collider")
		return
	end

	-- Get template Root for offset calculations
	local templateRoot = characterTemplate:FindFirstChild("Root")
	if not templateRoot then
		warn("[CharacterController] CharacterTemplate missing Root")
		return
	end

	-- Clone the collider
	local collider = templateCollider:Clone()
	collider.Name = "Collider"

	-- Store owner info for hit detection
	local player = Players:GetPlayerFromCharacter(character) or Players:FindFirstChild(character.Name)
	if player then
		collider:SetAttribute("OwnerUserId", player.UserId)
	end

	-- Get anchor part (Root for character, fallback to PrimaryPart)
	local anchorPart = character:FindFirstChild("Root") or character.PrimaryPart
	if not anchorPart then
		collider:Destroy()
		return
	end

	-- Helper to setup collider part - use template positions directly
	local function setupColliderPart(part, templatePart, isActive)
		if not part:IsA("BasePart") then
			return
		end

		-- Get offset from template Root to this template part
		local partOffset = templateRoot.CFrame:ToObjectSpace(templatePart.CFrame)

		-- Position part relative to character's anchor
		part.CFrame = anchorPart.CFrame * partOffset

		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = isActive
		part.CanTouch = false
		part.Massless = true

		-- Debug visualization
		if self._hitboxDebugEnabled and isActive then
			part.Transparency = 0.5
			part.Color = Color3.fromRGB(255, 0, 0) -- Red for active
			part.Material = Enum.Material.ForceField
		else
			part.Transparency = 1
		end

		-- Weld to anchor
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchorPart
		weld.Part1 = part
		weld.Parent = part
	end

	-- Get Hitbox folder (new structure: Collider/Hitbox/Standing and Crouching)
	local hitboxFolder = collider:FindFirstChild("Hitbox")
	local templateHitboxFolder = templateCollider:FindFirstChild("Hitbox")

	if not hitboxFolder or not templateHitboxFolder then
		warn("[CharacterController] Collider missing Hitbox folder")
		collider:Destroy()
		return
	end

	-- Setup Standing hitbox parts - active by default
	local standingFolder = hitboxFolder:FindFirstChild("Standing")
	local templateStandingFolder = templateHitboxFolder:FindFirstChild("Standing")
	if standingFolder and templateStandingFolder then
		for _, part in standingFolder:GetChildren() do
			local templatePart = templateStandingFolder:FindFirstChild(part.Name)
			if templatePart then
				setupColliderPart(part, templatePart, true)
			end
		end
	end

	-- Setup Crouching hitbox parts - inactive by default
	local crouchingFolder = hitboxFolder:FindFirstChild("Crouching")
	local templateCrouchingFolder = templateHitboxFolder:FindFirstChild("Crouching")
	if crouchingFolder and templateCrouchingFolder then
		for _, part in crouchingFolder:GetChildren() do
			local templatePart = templateCrouchingFolder:FindFirstChild(part.Name)
			if templatePart then
				setupColliderPart(part, templatePart, false)
			end
		end
	end

	collider.Parent = character
	self._remoteColliders[character] = collider
end

-- Switch remote player's collider between standing/crouching
function CharacterController:_setRemoteColliderCrouch(character, isCrouching)
	local collider = character:FindFirstChild("Collider")
	if not collider then
		return
	end

	local hitboxFolder = collider:FindFirstChild("Hitbox")
	if not hitboxFolder then
		return
	end

	local standingFolder = hitboxFolder:FindFirstChild("Standing")
	local crouchingFolder = hitboxFolder:FindFirstChild("Crouching")

	-- Update Standing parts
	if standingFolder then
		for _, part in standingFolder:GetChildren() do
			if part:IsA("BasePart") then
				local isActive = not isCrouching
				part.CanQuery = isActive

				-- Debug visualization
				if self._hitboxDebugEnabled then
					if isActive then
						part.Transparency = 0.5
						part.Color = Color3.fromRGB(255, 0, 0)
						part.Material = Enum.Material.ForceField
					else
						part.Transparency = 0.8
						part.Color = Color3.fromRGB(100, 100, 100)
					end
				else
					part.Transparency = 1
				end
			end
		end
	end

	-- Update Crouching parts
	if crouchingFolder then
		for _, part in crouchingFolder:GetChildren() do
			if part:IsA("BasePart") then
				local isActive = isCrouching
				part.CanQuery = isActive

				-- Debug visualization
				if self._hitboxDebugEnabled then
					if isActive then
						part.Transparency = 0.5
						part.Color = Color3.fromRGB(0, 150, 255) -- Blue for crouch
						part.Material = Enum.Material.ForceField
					else
						part.Transparency = 0.8
						part.Color = Color3.fromRGB(100, 100, 100)
					end
				else
					part.Transparency = 1
				end
			end
		end
	end
end

-- Toggle hitbox debug visualization
function CharacterController:ToggleHitboxDebug()
	self._hitboxDebugEnabled = not self._hitboxDebugEnabled
	print("[CharacterController] Hitbox debug:", self._hitboxDebugEnabled and "ENABLED" or "DISABLED")

	-- Update all existing colliders
	for character, collider in pairs(self._remoteColliders) do
		if character and character.Parent and collider and collider.Parent then
			-- Check current crouch state
			local isCrouching = character:GetAttribute("IsCrouching") or false

			local hitboxFolder = collider:FindFirstChild("Hitbox")
			if not hitboxFolder then
				continue
			end

			local standingFolder = hitboxFolder:FindFirstChild("Standing")
			local crouchingFolder = hitboxFolder:FindFirstChild("Crouching")

			if standingFolder then
				for _, part in standingFolder:GetChildren() do
					if part:IsA("BasePart") then
						local isActive = not isCrouching and part.CanQuery
						if self._hitboxDebugEnabled then
							if isActive then
								part.Transparency = 0.5
								part.Color = Color3.fromRGB(255, 0, 0)
								part.Material = Enum.Material.ForceField
							else
								part.Transparency = 0.8
								part.Color = Color3.fromRGB(100, 100, 100)
							end
						else
							part.Transparency = 1
						end
					end
				end
			end

			if crouchingFolder then
				for _, part in crouchingFolder:GetChildren() do
					if part:IsA("BasePart") then
						local isActive = isCrouching and part.CanQuery
						if self._hitboxDebugEnabled then
							if isActive then
								part.Transparency = 0.5
								part.Color = Color3.fromRGB(0, 150, 255)
								part.Material = Enum.Material.ForceField
							else
								part.Transparency = 0.8
								part.Color = Color3.fromRGB(100, 100, 100)
							end
						else
							part.Transparency = 1
						end
					end
				end
			end
		else
			-- Clean up invalid entries
			self._remoteColliders[character] = nil
		end
	end

	return self._hitboxDebugEnabled
end

-- Get hitbox debug state
function CharacterController:IsHitboxDebugEnabled()
	return self._hitboxDebugEnabled
end

-- =============================================================================
-- RAGDOLL SYSTEM (uses RagdollModule)
-- =============================================================================

function CharacterController:GetRagdoll(player)
	return RagdollModule.GetRig(player)
end

function CharacterController:IsRagdolled(player)
	return RagdollModule.IsRagdolled(player)
end

function CharacterController:_onRagdollStarted(player, ragdollData)
	if not player then
		return
	end

	ragdollData = ragdollData or {}

	-- Build knockback force from ragdoll data
	local knockbackForce = nil
	if ragdollData.Velocity then
		knockbackForce = ragdollData.Velocity
	elseif ragdollData.FlingDirection then
		local strength = ragdollData.FlingStrength or 50
		knockbackForce = ragdollData.FlingDirection.Unit * strength
	end

	-- Ragdoll the player (RagdollModule handles rig targeting)
	RagdollModule.Ragdoll(player, knockbackForce)

	-- Track for this controller
	local rig = RagdollModule.GetRig(player)
	if rig then
		self._activeRagdolls[player] = rig
	end

	-- If this is the local player, handle camera
	if player == Players.LocalPlayer then
		local cameraController = self._registry and self._registry:TryGet("Camera")
		if cameraController then
			-- Save current camera mode
			if cameraController.GetCurrentMode then
				self._savedCameraMode = cameraController:GetCurrentMode()
			end

			-- Focus camera on ragdoll head
			if rig then
				local rigHead = rig:FindFirstChild("Head")
				if rigHead and cameraController.SetRagdollFocus then
					cameraController:SetRagdollFocus(rigHead)
				end
			end
		end
	end
end

function CharacterController:_onRagdollEnded(player)
	if not player then
		return
	end

	-- Unragdoll the player (RagdollModule handles rig targeting)
	RagdollModule.GetBackUp(player)

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
