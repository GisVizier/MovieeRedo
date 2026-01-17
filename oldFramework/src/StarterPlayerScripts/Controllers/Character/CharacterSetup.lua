local CharacterSetup = {}

-- =============================================================================
-- DEVELOPER TOGGLES
-- =============================================================================
-- Rig visibility is now controlled by Config.Gameplay.Character.ShowRigForTesting
-- Set to true in GameplayConfig.lua to show R6 rig (arms, legs, torso) for testing
-- =============================================================================

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local Config = require(Locations.Modules.Config)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local SlidingSystem = require(Locations.Modules.Systems.Movement.SlidingSystem)
local CrouchUtils = require(Locations.Modules.Systems.Character.CrouchUtils)
local RigManager = require(Locations.Modules.Systems.Character.RigManager)
local MovementInputProcessor = require(script.Parent.Parent.Input.MovementInputProcessor)

-- Constants
local LocalPlayer = Players.LocalPlayer

-- Reference to main CharacterController (will be set by CharacterController:Init)
CharacterSetup.CharacterController = nil

-- Character setup state tracking
CharacterSetup.IsSettingUpCharacter = false

function CharacterSetup:Init(characterController)
	self.CharacterController = characterController

	LogService:Info("CHARACTER", "CharacterSetup initialized")
end

function CharacterSetup:InitializeController()
	LogService:Info("CHARACTER", "CharacterController:Init() called", {
		CallStack = debug.traceback("", 2),
	})

	-- Initialize cooldown timers to current time so first actions work correctly
	local currentTime = tick()
	self.CharacterController.LastCrouchTime = currentTime - 1 -- Start 1 second ago so first crouch action works
	self.CharacterController.LastGroundedTime = currentTime -- Initialize as if player was just grounded

	LogService:Debug("CHARACTER", "Initialized cooldown timers", {
		LastCrouchTime = self.CharacterController.LastCrouchTime,
		CurrentTime = currentTime,
	})

	-- Initialize movement input processor
	self.CharacterController.MovementInputProcessor = MovementInputProcessor
	self.CharacterController.MovementInputProcessor:Init(self.CharacterController)

	SlidingSystem:Init()

	-- Connect to movement state changes to handle automatic crouch after slide
	MovementStateManager:ConnectToStateChange(function(previousState, newState)
		if
			previousState == MovementStateManager.States.Sliding
			and newState == MovementStateManager.States.Crouching
		then
			-- Automatic crouch after slide - set up crouch state without cooldown penalty
			self.CharacterController:HandleAutomaticCrouchAfterSlide()
		end
		-- Note: Leg visibility system removed for FPS mode
	end)

	-- Handle crouch state replication from other players
	RemoteEvents:ConnectClient("CrouchStateChanged", function(otherPlayer, isCrouching)
		-- Apply crouch visual state to OTHER player's character so we can see it
		-- This only handles other players, not our own character
		if otherPlayer ~= LocalPlayer then
			local otherCharacter = otherPlayer.Character
			if otherCharacter then
				if isCrouching then
					CrouchUtils:ApplyVisualCrouch(otherCharacter, true) -- skipClearanceCheck for replication
				else
					CrouchUtils:RemoveVisualCrouch(otherCharacter)
				end
			end
		end
	end)

	LogService:Info("CHARACTER", "CharacterController initialized")
	self.CharacterController:StartMovementLoop()
end

function CharacterSetup:ConnectToInputs(inputManager, cameraController)
	self.CharacterController.ConnectionCount = self.CharacterController.ConnectionCount + 1

	LogService:Info("CHARACTER", "ConnectToInputs called", {
		ConnectionCount = self.CharacterController.ConnectionCount,
		InputsAlreadyConnected = self.CharacterController.InputsConnected,
		HasInputManager = inputManager ~= nil,
		HasCameraController = cameraController ~= nil,
		CurrentInputManager = self.CharacterController.InputManager ~= nil,
		CallStack = debug.traceback(),
	})

	-- Prevent duplicate connections
	if self.CharacterController.InputsConnected then
		LogService:Warn("CHARACTER", "Inputs already connected - ignoring duplicate call", {
			ConnectionCount = self.CharacterController.ConnectionCount,
		})
		return
	end

	self.CharacterController.InputManager = inputManager
	self.CharacterController.CameraController = cameraController

	if not self.CharacterController.InputManager then
		LogService:Warn("CHARACTER", "No InputManager provided to CharacterController")
		return
	end

	self.CharacterController.InputManager:ConnectToInput("Movement", function(movement)
		self.CharacterController.MovementInput = movement

		-- Update movement state in MovementStateManager for animations and other systems
		local isMoving = movement.Magnitude > 0
		MovementStateManager:UpdateMovementState(isMoving)
	end)

	LogService:Debug("CHARACTER", "Connecting Jump input handler")
	self.CharacterController.InputManager:ConnectToInput("Jump", function(isJumping)
		if isJumping then
			-- Jump pressed - delegate to movement input processor
			self.CharacterController.MovementInputProcessor:OnJumpPressed()
		else
			-- Jump released - delegate to movement input processor
			self.CharacterController.MovementInputProcessor:OnJumpReleased()
		end
	end)

	self.CharacterController.InputManager:ConnectToInput("Sprint", function(isSprinting)
		self.CharacterController.IsSprinting = isSprinting
		self:HandleSprint(isSprinting)
	end)

	self.CharacterController.InputManager:ConnectToInput("Crouch", function(isCrouching)
		self.CharacterController.IsCrouching = isCrouching
		self.CharacterController:HandleCrouchWithSlidePriority(isCrouching)
	end)

	self.CharacterController.InputManager:ConnectToInput("Slide", function(isSliding)
		self.CharacterController:HandleSlideInput(isSliding)
	end)

	-- Connect camera mode toggle
	if cameraController then
		self.CharacterController.InputManager:ConnectToInput("ToggleCameraMode", function()
			cameraController:ToggleCameraMode()
		end)
		LogService:Debug("CHARACTER", "Connected camera mode toggle")
	end

	-- Mark inputs as connected to prevent duplicates
	self.CharacterController.InputsConnected = true
	LogService:Info("CHARACTER", "Input connections established successfully")
end

function CharacterSetup:HandleSprint(isSprinting)
	if not self.CharacterController.Character then
		return
	end

	-- Check auto-sprint setting
	local autoSprint = Config.Gameplay.Character.AutoSprint

	if isSprinting or autoSprint then
		-- Only sprint if in walking state (can't sprint while crouching/sliding)
		if MovementStateManager:IsWalking() then
			MovementStateManager:TransitionTo(MovementStateManager.States.Sprinting)
		end
	else
		-- Return to walking if currently sprinting and sprint key released
		if MovementStateManager:IsSprinting() then
			MovementStateManager:TransitionTo(MovementStateManager.States.Walking)
		end
	end
end

function CharacterSetup:OnCharacterSpawned(character)
	LogService:Info("CHARACTER", "OnCharacterSpawned called", {
		CharacterName = character.Name,
		LocalPlayerName = LocalPlayer.Name,
		IsOwnCharacter = character.Name == LocalPlayer.Name,
		CurrentCharacter = self.CharacterController.Character and self.CharacterController.Character.Name or "nil",
		CallStack = debug.traceback(),
	})

	if character.Name ~= LocalPlayer.Name then
		return
	end

	-- Mark that we're setting up a character
	self.IsSettingUpCharacter = true

	-- CRITICAL: Wait for character to fully replicate to client
	local maxWaitTime = 2
	local startTime = tick()
	while not character.PrimaryPart and (tick() - startTime) < maxWaitTime do
		task.wait(0.05)
	end

	if not character.PrimaryPart then
		LogService:Error("CHARACTER", "Character has no PrimaryPart after waiting - aborting setup")
		return
	end

	-- CRITICAL: Store spawn position before destroying server's Humanoid model
	local spawnPosition = character.PrimaryPart.Position

	-- BARO'S PATTERN: Clone-then-destroy to keep player.Character reference intact for voice chat
	-- This replaces server's minimal Humanoid model with full local character
	local characterTemplate = ReplicatedStorage:WaitForChild("CharacterTemplate")

	LogService:Info("CHARACTER", "Rebuilding character with full template (own player)", {
		SpawnPosition = spawnPosition,
		ExistingChildren = #character:GetChildren(),
	})

	-- CRITICAL: DO NOT destroy Humanoid, HumanoidRootPart, or Head!
	-- These are needed for voice chat AND CoreGui healthbar connection
	-- Destroying and cloning the Humanoid breaks Roblox's CoreGui healthbar tracking

	-- Clone ALL missing parts from template (Root, Collider that server didn't have)
	-- EXCLUDE Rig (will be created in workspace.Rigs by RigManager)
	-- EXCLUDE Hitbox for local player (only needed for other players' hit detection)
	-- Also EXCLUDE Humanoid, HumanoidRootPart, Head (keep server's versions for CoreGui)
	local excludeForLocal = { "Rig", "Hitbox", "Humanoid", "HumanoidRootPart", "Head" }
	for _, templatePart in pairs(characterTemplate:GetChildren()) do
		-- Only clone if this part doesn't exist yet AND it's not excluded
		local shouldExclude = false
		for _, excludeName in ipairs(excludeForLocal) do
			if templatePart.Name == excludeName then
				shouldExclude = true
				break
			end
		end

		if not shouldExclude and not character:FindFirstChild(templatePart.Name) then
			local newObject = templatePart:Clone()
			newObject.Parent = character
		end
	end

	-- NEW: Create Rig in workspace.Rigs using RigManager
	-- This allows the rig to persist after death/respawn for ragdoll effects
	RigManager:Init()
	local rig = RigManager:CreateRig(LocalPlayer, character)
	if not rig then
		LogService:Error("CHARACTER", "Failed to create rig in RigContainer")
		return
	end

	LogService:Debug("CHARACTER", "Character rebuild complete", {
		NewChildren = #character:GetChildren(),
	})

	-- Restore PrimaryPart reference (cloning breaks it)
	local CharacterUtils = require(Locations.Modules.Systems.Character.CharacterUtils)
	CharacterUtils:RestorePrimaryPartAfterClone(character, characterTemplate)

	-- Get Root part
	local root = CharacterLocations:GetRoot(character)
	if not root then
		LogService:Error("CHARACTER", "Root part not found after rebuilding character")
		return
	end

	-- CRITICAL: Unanchor Root for client physics
	root.Anchored = false

	-- Position character at spawn point
	character:PivotTo(CFrame.new(spawnPosition))

	-- Setup physics constraints for client-side control
	MovementUtils:SetupPhysicsConstraints(root)

	-- Configure physics properties
	CharacterUtils:ConfigurePhysicsProperties(character)

	-- CRITICAL: Setup welds to attach Collider and Rig parts to Root
	local success = CrouchUtils:SetupLegacyWelds(character)
	if not success then
		LogService:Error("CHARACTER", "Failed to setup welds for local player character")
		return
	end

	-- Configure Rig's Humanoid properties (disable state machine, etc.)
	-- NEW: Rig is now in workspace.Rigs, get it using CharacterLocations
	if rig then
		local rigHumanoid = rig:FindFirstChildOfClass("Humanoid")
		if rigHumanoid then
			local humanoidConfig = Config.System.Humanoid

			-- Apply all critical Humanoid settings
			rigHumanoid.EvaluateStateMachine = humanoidConfig.EvaluateStateMachine
			rigHumanoid.RequiresNeck = humanoidConfig.RequiresNeck
			rigHumanoid.BreakJointsOnDeath = humanoidConfig.BreakJointsOnDeath
			rigHumanoid.AutoJumpEnabled = humanoidConfig.AutoJumpEnabled
			rigHumanoid.AutoRotate = humanoidConfig.AutoRotate

			-- Disable unnecessary states for performance
			for _, state in ipairs(humanoidConfig.DisabledStates) do
				rigHumanoid:SetStateEnabled(state, false)
			end

			-- Apply player's avatar appearance to Rig
			local avatarSuccess, err = pcall(function()
				local humanoidDescription = Players:GetHumanoidDescriptionFromUserId(LocalPlayer.UserId)
				rigHumanoid:ApplyDescription(humanoidDescription)
			end)

			if not avatarSuccess then
				LogService:Warn("CHARACTER", "Failed to apply avatar to Rig (local player)", {
					Player = LocalPlayer.Name,
					Error = err,
				})
			else
				LogService:Info("CHARACTER", "Applied avatar to Rig (local player)", {
					Player = LocalPlayer.Name,
				})
			end

			-- Hide rig parts based on ShowRigForTesting setting
			-- When false: Hide everything (head, torso, arms, legs)
			-- When true: Show only limbs (arms, legs) for animation testing, hide head/torso
			-- Rig only visible to other players for animations
			-- Later: Emote system will temporarily make rig visible during emotes

			-- Define which parts to show when testing
			local limbPartsToShow = { "Torso", "Left Leg", "Right Leg" } --{ "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
			local limbPartsSet = {}
			for _, partName in ipairs(limbPartsToShow) do
				limbPartsSet[partName] = true
			end

			-- Hide all rig parts by default (camera controller handles visibility per camera mode)
			CharacterLocations:ForEachRigPart(character, function(rigPart)
				local showForTesting = Config.Gameplay.Character.ShowRigForTesting and limbPartsSet[rigPart.Name]
				rigPart.LocalTransparencyModifier = showForTesting and 0 or 1
			end)

			-- Always hide face decal
			local rigHead = rig:FindFirstChild("Head")
			if rigHead then
				local face = rigHead:FindFirstChild("face")
				if face and face:IsA("Decal") then
					face.Transparency = 1
				end
			end

			-- Hide all accessories by default (camera controller will show them in third person)
			for _, accessory in pairs(rigHumanoid:GetAccessories()) do
				local handle = accessory:FindFirstChild("Handle")
				if handle and handle:IsA("BasePart") then
					handle.LocalTransparencyModifier = 1
				end
			end

			if Config.Gameplay.Character.ShowRigForTesting then
				LogService:Debug("CHARACTER", "ShowRigForTesting enabled - limbs visible (arms, legs)")
			else
				LogService:Debug("CHARACTER", "Rig parts hidden for local player (will show in third person)")
			end

			-- Disable CastShadow for all Rig parts to prevent self-shadowing in first-person
			CharacterLocations:ForEachRigPart(character, function(rigPart)
				rigPart.CastShadow = false
			end)

			LogService:Debug("CHARACTER", "Disabled CastShadow for all Rig parts")

			LogService:Debug("CHARACTER", "Configured Rig Humanoid properties", {
				EvaluateStateMachine = rigHumanoid.EvaluateStateMachine,
				AutoRotate = rigHumanoid.AutoRotate,
			})
		end
	end

	-- Store character reference
	self.CharacterController.Character = character
	self.CharacterController.PrimaryPart = root

	-- Reset input state to prevent carryover from previous character
	if self.CharacterController.InputManager then
		self.CharacterController.InputManager:ResetInputState()
		LogService:Debug("CHARACTER", "Reset InputManager state for new character")
	end

	-- Initialize character rotation to match current camera angle
	if self.CharacterController.CameraController then
		local cameraAngles = self.CharacterController.CameraController:GetCameraAngles()
		local cameraYAngle = math.rad(cameraAngles.X)

		-- Set cached camera rotation
		self.CharacterController.CachedCameraYAngle = cameraYAngle
		self.CharacterController.LastCameraAngles = cameraAngles

		LogService:Debug("CHARACTER", "Initialized character rotation to camera angle", {
			CameraAngle = cameraAngles.X,
		})
	end

	-- Setup Humanoid death detection for Roblox's reset button
	local humanoid = CharacterLocations:GetHumanoidInstance(character)
	if humanoid then
		-- Listen for both Died event and health reaching 0
		humanoid.Died:Connect(function()
			-- Prevent respawn during active character setup
			if self.IsSettingUpCharacter then
				LogService:Warn("CHARACTER", "Respawn request ignored - character setup in progress")
				return
			end

			LogService:Info("CHARACTER", "Humanoid.Died event - requesting respawn")
			RemoteEvents:FireServer("RequestRespawn")
		end)

		-- Also listen to HealthChanged in case Died doesn't fire
		humanoid.HealthChanged:Connect(function(health)
			if health <= 0 then
				-- Prevent respawn during active character setup
				if self.IsSettingUpCharacter then
					return -- Silently ignore
				end

				LogService:Info("CHARACTER", "Humanoid health <= 0 - requesting respawn")
				RemoteEvents:FireServer("RequestRespawn")
			end
		end)

		LogService:Debug("CHARACTER", "Connected Humanoid death listeners for reset button")
	else
		LogService:Warn("CHARACTER", "No Humanoid found - reset button won't work")
	end

	-- Continue with normal setup
	self:SetupCharacterComponents()
end

function CharacterSetup:SetupCharacterComponents()
	self.CharacterController.FeetPart = CharacterLocations:GetFeet(self.CharacterController.Character)
	if not self.CharacterController.FeetPart then
		LogService:Warn("CHARACTER", "No Feet part found - using PrimaryPart for ground detection")
		self.CharacterController.FeetPart = self.CharacterController.PrimaryPart
	end

	self:SetupModernPhysics()
	self:SetupRaycast()
	self:ConfigureCharacterParts()

	-- Setup crouch system for client-side control (state tracking only)
	if not CrouchUtils.CharacterCrouchState[self.CharacterController.Character] then
		CrouchUtils.CharacterCrouchState[self.CharacterController.Character] = {
			IsCrouched = false,
		}
	end

	-- Setup movement state manager with character reference for automatic visual crouch
	MovementStateManager:SetCharacter(self.CharacterController.Character)

	-- Apply initial character rotation to match camera
	if self.CharacterController.AlignOrientation and self.CharacterController.CachedCameraYAngle then
		MovementUtils:SetCharacterRotation(
			self.CharacterController.AlignOrientation,
			self.CharacterController.CachedCameraYAngle
		)
		LogService:Debug("CHARACTER", "Applied initial character rotation to AlignOrientation")
	end

	-- Setup sliding system
	SlidingSystem:SetupCharacter(
		self.CharacterController.Character,
		self.CharacterController.PrimaryPart,
		self.CharacterController.VectorForce,
		self.CharacterController.AlignOrientation,
		self.CharacterController.RaycastParams
	)

	-- Set camera controller for slide direction updates
	if self.CharacterController.CameraController then
		SlidingSystem:SetCameraController(self.CharacterController.CameraController)
	end

	-- Set character controller reference for wall collision handling
	SlidingSystem:SetCharacterController(self.CharacterController)

	if Config.Gameplay.Character.HideFromLocalPlayer then
		self:HideCharacterParts()
	end

	-- Restart movement loop if it was disconnected (during respawn)
	if not self.CharacterController.Connection then
		LogService:Info("CHARACTER", "Restarting movement loop for respawned character")
		self.CharacterController:StartMovementLoop()
	end

	-- Start custom replication for this character
	local ClientReplicator = require(LocalPlayer.PlayerScripts.Systems.Replication.ClientReplicator)
	ClientReplicator:Start(self.CharacterController.Character, self.CharacterController.PrimaryPart)

	-- Mark character setup as complete
	self.IsSettingUpCharacter = false

	LogService:Info("CHARACTER", "Character movement setup complete", {
		CharacterName = self.CharacterController.Character.Name,
		HasPrimaryPart = self.CharacterController.PrimaryPart ~= nil,
		HasInputManager = self.CharacterController.InputManager ~= nil,
		HasCameraController = self.CharacterController.CameraController ~= nil,
		ReplicationActive = true,
	})

	-- Notify server that client-side setup is fully complete
	RemoteEvents:FireServer("CharacterSetupComplete")
	LogService:Debug("CHARACTER", "Sent CharacterSetupComplete to server")
end

function CharacterSetup:OnCharacterRemoving(character)
	LogService:Info("CHARACTER", "OnCharacterRemoving called", {
		CharacterName = character.Name,
		IsOwnCharacter = character.Name == LocalPlayer.Name,
		CurrentCharacter = self.CharacterController.Character and self.CharacterController.Character.Name or "nil",
	})

	if character.Name == LocalPlayer.Name and self.CharacterController.Character == character then
		LogService:Info("CHARACTER", "Cleaning up local player character for respawn")

		-- Stop custom replication
		local ClientReplicator = require(LocalPlayer.PlayerScripts.Systems.Replication.ClientReplicator)
		ClientReplicator:Stop()

		-- Cleanup sliding system
		SlidingSystem:Cleanup()

		-- Full character cleanup
		self:CleanupCharacter()

		LogService:Info("CHARACTER", "Character cleanup complete - ready for respawn")
	end
end

function CharacterSetup:SetupModernPhysics()
	if not self.CharacterController.PrimaryPart then
		return
	end

	-- Try immediate access first (most common case)
	self.CharacterController.VectorForce = self.CharacterController.PrimaryPart:FindFirstChild("VectorForce")
	self.CharacterController.AlignOrientation = self.CharacterController.PrimaryPart:FindFirstChild("AlignOrientation")
	self.CharacterController.Attachment0 = self.CharacterController.PrimaryPart:FindFirstChild("MovementAttachment0")
	self.CharacterController.Attachment1 = self.CharacterController.PrimaryPart:FindFirstChild("MovementAttachment1")

	-- If all found, we're done
	if
		self.CharacterController.VectorForce
		and self.CharacterController.AlignOrientation
		and self.CharacterController.Attachment0
		and self.CharacterController.Attachment1
	then
		LogService:Debug("CHARACTER", "Found all physics constraints immediately")
		return
	end

	-- Otherwise wait with timeout (but don't spawn - stay synchronous for movement setup)
	local timeout = 2 -- Shorter timeout
	local startTime = tick()

	while (tick() - startTime) < timeout do
		if not self.CharacterController.VectorForce then
			self.CharacterController.VectorForce = self.CharacterController.PrimaryPart:FindFirstChild("VectorForce")
		end
		if not self.CharacterController.AlignOrientation then
			self.CharacterController.AlignOrientation =
				self.CharacterController.PrimaryPart:FindFirstChild("AlignOrientation")
		end
		if not self.CharacterController.Attachment0 then
			self.CharacterController.Attachment0 =
				self.CharacterController.PrimaryPart:FindFirstChild("MovementAttachment0")
		end
		if not self.CharacterController.Attachment1 then
			self.CharacterController.Attachment1 =
				self.CharacterController.PrimaryPart:FindFirstChild("MovementAttachment1")
		end

		-- Check if we have everything
		if
			self.CharacterController.VectorForce
			and self.CharacterController.AlignOrientation
			and self.CharacterController.Attachment0
			and self.CharacterController.Attachment1
		then
			LogService:Debug("CHARACTER", "Found all physics constraints after waiting")
			return
		end

		task.wait(0.1)
	end

	-- Log what's missing
	LogService:Warn("CHARACTER", "Missing physics constraints after timeout", {
		VectorForce = self.CharacterController.VectorForce ~= nil,
		AlignOrientation = self.CharacterController.AlignOrientation ~= nil,
		MovementAttachment0 = self.CharacterController.Attachment0 ~= nil,
		MovementAttachment1 = self.CharacterController.Attachment1 ~= nil,
	})
end

function CharacterSetup:SetupRaycast()
	self.CharacterController.RaycastParams = RaycastParams.new()
	self.CharacterController.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.CharacterController.RaycastParams.FilterDescendantsInstances = { self.CharacterController.Character }

	-- Filter function to ignore nocollide objects and character parts
	self.CharacterController.RaycastParams.RespectCanCollide = true -- This automatically ignores CanCollide = false parts

	-- Use Players collision group to ignore other players (since Players don't collide with Players)
	self.CharacterController.RaycastParams.CollisionGroup = "Players"
end

function CharacterSetup:CleanupCharacter()
	self.CharacterController:StopUncrouchChecking()

	-- Cleanup crouch system
	if self.CharacterController.Character then
		CrouchUtils:CleanupWelds(self.CharacterController.Character)
	end

	-- NEW: Mark rig as dead so it can persist for ragdoll
	-- This keeps the rig in workspace.Rigs instead of destroying it
	local rig = CharacterLocations:GetRig(self.CharacterController.Character)
	if rig then
		RigManager:MarkRigAsDead(rig)
		-- Cleanup old dead rigs (keep only 3 most recent)
		RigManager:CleanupDeadRigs(LocalPlayer, 3)
	end

	-- Disconnect movement loop if active
	if self.CharacterController.Connection then
		self.CharacterController.Connection:Disconnect()
		self.CharacterController.Connection = nil
	end

	-- Clear all references
	self.CharacterController.Character = nil
	self.CharacterController.PrimaryPart = nil
	self.CharacterController.FeetPart = nil
	self.CharacterController.VectorForce = nil
	self.CharacterController.AlignOrientation = nil
	self.CharacterController.Attachment0 = nil
	self.CharacterController.Attachment1 = nil
	self.CharacterController.RaycastParams = nil
	self.CharacterController.IsGrounded = false
	self.CharacterController.WasGrounded = false
	self.CharacterController.IsSprinting = false
	self.CharacterController.IsCrouching = false
	self.CharacterController.JumpExecutedThisInput = false
	self.CharacterController.LastGroundedTime = 0

	-- Reset input connection state
	self.CharacterController.InputsConnected = false
	LogService:Info("CHARACTER", "Character cleanup complete - inputs can be reconnected")
end

function CharacterSetup:ConfigureCharacterParts()
	if not self.CharacterController.Character or not self.CharacterController.PrimaryPart then
		return
	end

	-- Configure character parts for movement physics
	for _, part in pairs(self.CharacterController.Character:GetChildren()) do
		if part:IsA("BasePart") and part ~= self.CharacterController.PrimaryPart then
			-- Exclude Humanoid parts (HumanoidRootPart and Head) - they should remain non-collidable for voice chat
			if part.Name ~= "HumanoidRootPart" and part.Name ~= "Head" then
				-- Allow character parts to be affected by forces but don't interfere with physics
				part.CanCollide = true
				part.CanTouch = true
			end
		end
	end
end

function CharacterSetup:HideCharacterParts()
	if not self.CharacterController.Character then
		return
	end

	local partsToHide = Config.Gameplay.Character.PartsToHide

	for _, partName in ipairs(partsToHide) do
		local part = nil

		-- Use CharacterLocations to find the part in the new structure
		if partName == "Body" then
			part = CharacterLocations:GetBody(self.CharacterController.Character)
		elseif partName == "Head" then
			part = CharacterLocations:GetHead(self.CharacterController.Character)
		elseif partName == "Feet" then
			part = CharacterLocations:GetFeet(self.CharacterController.Character)
		elseif partName == "CrouchBody" then
			part = CharacterLocations:GetCrouchBody(self.CharacterController.Character)
		elseif partName == "CrouchHead" then
			part = CharacterLocations:GetCrouchHead(self.CharacterController.Character)
		else
			-- Fallback for any other parts not in Collider structure
			part = self.CharacterController.Character:FindFirstChild(partName)
		end

		if part and part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end
end

-- Note: UpdateBodyTransparency function removed for FPS mode
-- All rig parts are always fully transparent for local player
-- Later: Emote system will handle temporary rig visibility during emotes

return CharacterSetup
