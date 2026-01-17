local InteractableController = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local Config = require(Locations.Modules.Config)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local SoundManager = require(Locations.Modules.Systems.Core.SoundManager)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
local SlidingSystem = require(Locations.Modules.Systems.Movement.SlidingSystem)

-- Constants
local LocalPlayer = Players.LocalPlayer
local InteractableConfig = Config.Interactable

-- State tracking
InteractableController.Character = nil
InteractableController.JumpPads = {}
InteractableController.Ladders = {}
InteractableController.LastTriggers = {} -- Cooldown tracking keyed by part reference
InteractableController.DetectionConnection = nil
InteractableController.LastJumpPadTime = 0 -- Track when jump pad was last triggered

-- Ladder climbing state
InteractableController.IsOnLadder = false
InteractableController.CurrentLadder = nil
InteractableController.CurrentLadderSound = nil

-- Performance optimization
local tick_func = tick
local vector3_new = Vector3.new

function InteractableController:Init()
	LogService:Debug("InteractableController", "Initializing interactable system")

	-- Initialize cooldown tracking
	self.LastTriggers = {}

	-- Only use the custom CharacterSpawned event from the initialization system
	-- Don't listen to LocalPlayer.CharacterAdded to avoid double initialization

	LocalPlayer.CharacterRemoving:Connect(function()
		self:OnCharacterRemoving()
	end)
end

function InteractableController:OnCharacterSpawned(character)
	-- Clean up any existing state first
	self:OnCharacterRemoving()

	self.Character = character

	-- Use task.spawn to wait for character parts to be ready
	task.spawn(function()
		-- Wait for character parts to be fully loaded
		local body = CharacterLocations:GetBody(self.Character)
		local head = CharacterLocations:GetHead(self.Character)
		local feet = CharacterLocations:GetFeet(self.Character)

		while not body or not head or not feet do
			task.wait(0.1)
			-- Verify character is still valid during waiting
			if not self.Character or not self.Character.Parent then
				LogService:Warn("InteractableController", "Character became invalid during initialization")
				return
			end
			body = CharacterLocations:GetBody(self.Character)
			head = CharacterLocations:GetHead(self.Character)
			feet = CharacterLocations:GetFeet(self.Character)
		end

		-- Find all interactables in the world
		self:FindInteractables()

		-- Start detection loop
		self:StartDetection()

		LogService:Info(
			"InteractableController",
			string.format("Found %d jump pads and %d ladders", #self.JumpPads, #self.Ladders)
		)
	end)
end

function InteractableController:OnCharacterRemoving()
	-- Clean up
	if self.DetectionConnection then
		self.DetectionConnection:Disconnect()
		self.DetectionConnection = nil
	end

	self.Character = nil
	self.IsOnLadder = false
	self.CurrentLadder = nil
	self:StopLadderSound()
	self.LastTriggers = {}
	self.LastJumpPadTime = 0

	LogService:Info("InteractableController", "Character removed, cleaning up")
end

function InteractableController:FindInteractables()
	-- Clear existing arrays
	self.JumpPads = {}
	self.Ladders = {}

	-- Find jump pads (startup only)
	local jumpPadObjects = CollectionService:GetTagged(InteractableConfig.CollectionService.JumpPadTag)
	for _, object in pairs(jumpPadObjects) do
		self:ProcessInteractableObject(object, "JumpPad")
	end

	-- Find ladders (startup only)
	local ladderObjects = CollectionService:GetTagged(InteractableConfig.CollectionService.LadderTag)
	for _, object in pairs(ladderObjects) do
		self:ProcessInteractableObject(object, "Ladder")
	end

	-- No dynamic listening - interactables are loaded once on startup only
end

function InteractableController:ProcessInteractableObject(object, interactableType)
	-- Handle both folders and models
	local itemsToProcess = {}

	if object:IsA("Folder") then
		-- If it's a folder, check all children for models
		for _, child in pairs(object:GetChildren()) do
			if child:IsA("Model") then
				table.insert(itemsToProcess, child)
			end
		end
	elseif object:IsA("Model") then
		-- If it's directly a model, process it
		table.insert(itemsToProcess, object)
	end

	-- Process each model
	for _, model in pairs(itemsToProcess) do
		-- Use task.spawn to handle each model asynchronously
		task.spawn(function()
			-- Wait for hitbox part to be replicated (with 5 second timeout)
			local hitbox = model:WaitForChild(InteractableConfig.CollectionService.HitboxName, 5)
			if hitbox and hitbox:IsA("BasePart") then
				local interactableData = {
					Hitbox = hitbox,
					Model = model,
					Type = interactableType,
				}

				if interactableType == "JumpPad" then
					table.insert(self.JumpPads, interactableData)
				elseif interactableType == "Ladder" then
					table.insert(self.Ladders, interactableData)
				end

				LogService:Debug(
					"InteractableController",
					string.format("Registered %s: %s", interactableType, model.Name)
				)
			else
				LogService:Warn(
					"InteractableController",
					string.format(
						"%s model '%s' missing %s part or timed out waiting",
						interactableType,
						model.Name,
						InteractableConfig.CollectionService.HitboxName
					)
				)
			end
		end)
	end
end

function InteractableController:StartDetection()
	if self.DetectionConnection then
		self.DetectionConnection:Disconnect()
	end

	-- Run detection on every heartbeat (60fps)
	self.DetectionConnection = RunService.Heartbeat:Connect(function()
		self:UpdateDetection()
	end)
end

function InteractableController:UpdateDetection()
	if not self.Character or not self.Character.Parent then
		return
	end

	-- Check jump pads
	for _, jumpPadData in pairs(self.JumpPads) do
		if self:IsPlayerOverlappingPart(self.Character, jumpPadData.Hitbox) then
			self:OnJumpPadDetected(jumpPadData)
		end
	end

	-- Check ladders
	local playerOnAnyLadder = false
	for _, ladderData in pairs(self.Ladders) do
		if self:IsPlayerOverlappingPart(self.Character, ladderData.Hitbox) then
			self:OnLadderDetected(ladderData)
			playerOnAnyLadder = true
		end
	end

	-- If player was on a ladder but is no longer overlapping any ladder, reset ladder state
	if self.IsOnLadder and not playerOnAnyLadder then
		self.IsOnLadder = false
		self.CurrentLadder = nil
		self:StopLadderSound()
		LogService:Info("InteractableController", "Player left ladder area")
	end
end

function InteractableController:IsPlayerOverlappingPart(character, part)
	-- Get normal character parts
	local head = CharacterLocations:GetHead(character)
	local body = CharacterLocations:GetBody(character)
	local feet = CharacterLocations:GetFeet(character)

	if not head or not body or not feet then
		return false
	end

	-- Set up overlap parameters
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { part }
	overlapParams.RespectCanCollide = InteractableConfig.Detection.RespectCanCollide

	-- Check for overlaps with head, body, and feet
	local headOverlaps = workspace:GetPartsInPart(head, overlapParams)
	local bodyOverlaps = workspace:GetPartsInPart(body, overlapParams)
	local feetOverlaps = workspace:GetPartsInPart(feet, overlapParams)

	return #headOverlaps > 0 or #bodyOverlaps > 0 or #feetOverlaps > 0
end

function InteractableController:OnLadderDetected(ladderData)
	-- Get movement input from CharacterController
	local characterController = ServiceRegistry:GetController("CharacterController")
	if not characterController or not characterController.MovementInput then
		return
	end

	local movementInput = characterController.MovementInput
	if movementInput.Magnitude < 0.1 then
		-- Not moving - exit ladder if we were on it
		if self.IsOnLadder and self.CurrentLadder == ladderData then
			self.IsOnLadder = false
			self.CurrentLadder = nil
			self:StopLadderSound()
			LogService:Info(
				"InteractableController",
				string.format("Stopped climbing ladder: %s", ladderData.Model.Name)
			)
		end
		return
	end

	-- Apply ladder climbing for any movement
	self:ApplyLadderClimbing(ladderData, movementInput)

	-- Set ladder state
	if not self.IsOnLadder then
		-- Cancel any active slide when starting to climb
		if SlidingSystem.IsSliding then
			SlidingSystem:StopSlide(false, true) -- false = don't transition to crouch, true = remove visual immediately
			LogService:Info("InteractableController", "Cancelled slide due to ladder climbing")
		end

		self.IsOnLadder = true
		self.CurrentLadder = ladderData
		self:StartLadderSound(ladderData)
		LogService:Info("InteractableController", string.format("Started climbing ladder: %s", ladderData.Model.Name))
	end
end

function InteractableController:ApplyLadderClimbing(_ladderData, movementInput)
	local primaryPart = self.Character.PrimaryPart
	if not primaryPart then
		return
	end

	-- Linear upward velocity based on movement input magnitude
	local inputMagnitude = movementInput.Magnitude
	local upwardVelocity = inputMagnitude * (InteractableConfig.Ladders.ClimbSpeed * 0.4) -- More responsive

	-- Set upward velocity directly for linear movement (preserve horizontal movement)
	local currentVelocity = primaryPart.AssemblyLinearVelocity
	primaryPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		upwardVelocity, -- Set velocity directly, not add to it
		currentVelocity.Z
	)
end

function InteractableController:OnJumpPadDetected(jumpPadData)
	-- Check cooldown
	local currentTime = tick_func()
	local lastTrigger = self.LastTriggers[jumpPadData.Hitbox]

	if lastTrigger and (currentTime - lastTrigger) < InteractableConfig.JumpPads.Cooldown then
		return -- Still on cooldown
	end

	-- Apply jump pad effect
	self:ApplyJumpPadEffect(jumpPadData)

	-- Record trigger time for cooldown
	self.LastTriggers[jumpPadData.Hitbox] = currentTime

	LogService:Info("InteractableController", string.format("Jump pad triggered: %s", jumpPadData.Model.Name))
end

function InteractableController:ApplyJumpPadEffect(jumpPadData)
	local primaryPart = self.Character.PrimaryPart
	if not primaryPart then
		return
	end

	-- Get current velocity
	local currentVelocity = primaryPart.AssemblyLinearVelocity

	-- Calculate new velocity
	local newVelocity = vector3_new(
		InteractableConfig.JumpPads.PreserveHorizontalMomentum and currentVelocity.X or 0,
		InteractableConfig.JumpPads.UpwardForce,
		InteractableConfig.JumpPads.PreserveHorizontalMomentum and currentVelocity.Z or 0
	)

	-- Apply the velocity
	primaryPart.AssemblyLinearVelocity = newVelocity

	-- Record jump pad timing to prevent auto-jump interference
	self.LastJumpPadTime = tick_func()

	-- Play jump pad sound locally (no 3D positioning for local client)
	SoundManager:PlaySound("Movement", "JumpPad")

	-- Request sound replication to other players (with 3D positioning at jump pad)
	local jumpPadPosition = jumpPadData.Hitbox.Position
	SoundManager:RequestSoundReplication("Movement", "JumpPad", jumpPadPosition)

	-- TODO: Add particle effects if enabled
end

-- Public getters for other systems
function InteractableController:IsPlayerOnLadder()
	return self.IsOnLadder
end

function InteractableController:GetCurrentLadder()
	return self.CurrentLadder
end

function InteractableController:GetTimeSinceLastJumpPad()
	return tick_func() - self.LastJumpPadTime
end

function InteractableController:WasJumpPadRecentlyTriggered(timeWindow)
	timeWindow = timeWindow or 0.1 -- Default 100ms window
	return self:GetTimeSinceLastJumpPad() < timeWindow
end

function InteractableController:StartLadderSound(_ladderData)
	-- Stop any existing ladder sound first
	self:StopLadderSound()

	-- Start new ladder climbing sound locally (no 3D positioning for local client)
	self.CurrentLadderSound = SoundManager:PlaySound("Movement", "LadderClimb")

	-- Request sound replication to other players (with 3D positioning at player body)
	local bodyPart = CharacterLocations:GetBody(self.Character) or self.Character.PrimaryPart
	if bodyPart then
		SoundManager:RequestSoundReplication("Movement", "LadderClimb", bodyPart.Position)
	end
end

function InteractableController:StopLadderSound()
	if self.CurrentLadderSound then
		self.CurrentLadderSound:Stop()
		self.CurrentLadderSound = nil
	end

	-- Stop the sound for other players too by requesting stop sound replication
	SoundManager:RequestStopSoundReplication("Movement", "LadderClimb")
end

return InteractableController
