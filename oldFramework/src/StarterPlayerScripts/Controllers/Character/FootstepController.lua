local FootstepController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Config = require(Locations.Modules.Config)
local MovementUtils = require(Locations.Modules.Systems.Movement.MovementUtils)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local SoundManager = require(Locations.Modules.Systems.Core.SoundManager)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)

FootstepController.Character = nil
FootstepController.PrimaryPart = nil
FootstepController.RaycastParams = nil
FootstepController.LastFootstepTime = 0
FootstepController.Connection = nil
FootstepController.IsActive = false

function FootstepController:Init()
	LogService:RegisterCategory("FOOTSTEP", "Footstep sound management")
	LogService:Info("FOOTSTEP", "FootstepController initialized")
end

function FootstepController:OnCharacterSpawned(character)
	if not character then
		return
	end
	
	local characterController = ServiceRegistry:GetController("CharacterController")
	if not characterController then
		LogService:Warn("FOOTSTEP", "CharacterController not found")
		return
	end
	
	self.Character = character
	self.PrimaryPart = characterController.PrimaryPart
	self.RaycastParams = characterController.RaycastParams
	self.LastFootstepTime = 0
	
	self:StartFootstepLoop()
	
	LogService:Debug("FOOTSTEP", "Character setup complete", {
		Character = character.Name,
	})
end

function FootstepController:OnCharacterRemoving(_character)
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	
	self.Character = nil
	self.PrimaryPart = nil
	self.RaycastParams = nil
	self.IsActive = false
	
	LogService:Debug("FOOTSTEP", "Character cleanup complete")
end

function FootstepController:StartFootstepLoop()
	if self.Connection then
		self.Connection:Disconnect()
	end
	
	self.IsActive = true
	
	self.Connection = RunService.Heartbeat:Connect(function()
		self:UpdateFootsteps()
	end)
end

function FootstepController:UpdateFootsteps()
	if not self.Character or not self.PrimaryPart then
		return
	end
	
	local characterController = ServiceRegistry:GetController("CharacterController")
	if not characterController then
		return
	end
	
	if not characterController.IsGrounded then
		return
	end
	
	if MovementStateManager:IsSliding() then
		return
	end
	
	local velocity = self.PrimaryPart.AssemblyLinearVelocity
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local horizontalSpeed = horizontalVelocity.Magnitude
	
	local minSpeedForFootsteps = 2
	if horizontalSpeed < minSpeedForFootsteps then
		return
	end
	
	local footstepConfig = Config.Audio.Footsteps
	if not footstepConfig then
		return
	end
	
	local walkSpeed = Config.Gameplay.Character.WalkSpeed or 16
	
	local factor = footstepConfig.Factor or 8.1
	if MovementStateManager:IsCrouching() then
		factor = footstepConfig.CrouchFactor or 12.0
	elseif MovementStateManager:IsSprinting() then
		factor = footstepConfig.SprintFactor or 6.0
	end
	
	local effectiveSpeed = math.max(horizontalSpeed, walkSpeed * 0.5)
	local footstepInterval = factor / effectiveSpeed
	
	local currentTime = tick()
	if (currentTime - self.LastFootstepTime) < footstepInterval then
		return
	end
	
	self.LastFootstepTime = currentTime
	
	local isGrounded, materialName = MovementUtils:CheckGroundedWithMaterial(
		self.Character,
		self.PrimaryPart,
		self.RaycastParams
	)
	
	if not isGrounded or not materialName then
		return
	end
	
	local soundName = footstepConfig.MaterialMap[materialName] or footstepConfig.DefaultSound or "FootstepConcrete"
	
	local feetPart = CharacterLocations:GetFeet(self.Character) or self.PrimaryPart
	
	local pitchVariation = 0.9 + math.random() * 0.2
	
	-- Play locally
	SoundManager:PlaySound("Movement", soundName, feetPart, pitchVariation)
	
	-- Replicate to others
	SoundManager:RequestSoundReplication("Movement", soundName, feetPart.Position, pitchVariation)
end

return FootstepController
