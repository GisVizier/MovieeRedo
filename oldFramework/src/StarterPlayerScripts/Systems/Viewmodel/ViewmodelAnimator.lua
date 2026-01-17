local ViewmodelAnimator = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local Log = require(Locations.Modules.Systems.Core.LogService)

local LocalPlayer = Players.LocalPlayer

-- Lazy-load CharacterController to avoid circular dependencies
local CharacterController = nil
local function getCharacterController()
	if CharacterController then
		return CharacterController
	end
	local playerScripts = LocalPlayer:WaitForChild("PlayerScripts", 3)
	if playerScripts then
		local controllers = playerScripts:FindFirstChild("Controllers")
		if controllers then
			local module = controllers:FindFirstChild("CharacterController")
			if module then
				CharacterController = require(module)
				return CharacterController
			end
		end
	end
	return nil
end

ViewmodelAnimator.Controller = nil
ViewmodelAnimator.Animator = nil
ViewmodelAnimator.AnimationTracks = {}
ViewmodelAnimator.CurrentConfig = nil
ViewmodelAnimator.CurrentMovementAnimation = nil
ViewmodelAnimator.MovementUpdateConnection = nil
ViewmodelAnimator.CurrentWeaponName = nil

-- Idle Actions Manager (lazy loaded)
ViewmodelAnimator.IdleActionsManager = nil

ViewmodelAnimator.AnimationPriorities = {
	Idle = Enum.AnimationPriority.Core,
	Walk = Enum.AnimationPriority.Movement,
	Run = Enum.AnimationPriority.Movement,
	ADS = Enum.AnimationPriority.Action,
	Fire = Enum.AnimationPriority.Action2,
	Reload = Enum.AnimationPriority.Action3,
	Equip = Enum.AnimationPriority.Action2,
	Inspect = Enum.AnimationPriority.Action,
	Attack = Enum.AnimationPriority.Action2,
}

function ViewmodelAnimator:Init(controller)
	self.Controller = controller

	-- Initialize IdleActionsManager
	self.IdleActionsManager = require(script.Parent.IdleActionsManager)
	self.IdleActionsManager:Init(self)

	Log:Debug("VIEWMODEL", "ViewmodelAnimator initialized")
end

function ViewmodelAnimator:SetupAnimations(viewmodel, config)
	self:Cleanup()

	local animController = viewmodel:FindFirstChildOfClass("AnimationController")
	if not animController then
		Log:Error("VIEWMODEL", "No AnimationController found on viewmodel")
		return
	end

	self.Animator = animController:FindFirstChildOfClass("Animator")
	if not self.Animator then
		self.Animator = Instance.new("Animator")
		self.Animator.Parent = animController
	end

	self.CurrentConfig = config
	self.AnimationTracks = {}

	local animations = config.Animations
	if not animations then
		Log:Warn("VIEWMODEL", "No animations defined in config")
		return
	end

	local assetsToPreload = {}

	for animName, animId in pairs(animations) do
		-- Skip IdleActions table - those are handled by IdleActionsManager
		if type(animId) == "string" and animId ~= "rbxassetid://0" then
			local animation = Instance.new("Animation")
			animation.AnimationId = animId

			local track = self.Animator:LoadAnimation(animation)
			track.Priority = self.AnimationPriorities[animName] or Enum.AnimationPriority.Core

			if animName == "Idle" or animName == "Walk" or animName == "Run" then
				track.Looped = true
			else
				track.Looped = false
			end

			self.AnimationTracks[animName] = track
			table.insert(assetsToPreload, animId)

			Log:Debug("VIEWMODEL", "Loaded animation track", { Animation = animName })
		end
	end

	if #assetsToPreload > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(assetsToPreload)
			end)
		end)
	end

	self:StartMovementUpdates()

	if self.AnimationTracks["Idle"] then
		self:PlayAnimation("Idle")
	end

	-- Start idle actions system
	-- Get weapon name from config or controller
	local weaponName = self.Controller and self.Controller.CurrentWeaponName
	if weaponName and self.IdleActionsManager then
		self.CurrentWeaponName = weaponName
		self.IdleActionsManager:Start(weaponName, self.Animator)
	end

	Log:Info("VIEWMODEL", "Viewmodel animations setup complete", { TrackCount = #assetsToPreload })
end

function ViewmodelAnimator:StartMovementUpdates()
	if self.MovementUpdateConnection then
		self.MovementUpdateConnection:Disconnect()
	end

	self.MovementUpdateConnection = RunService.Heartbeat:Connect(function()
		self:UpdateMovementAnimation()
	end)
end

function ViewmodelAnimator:StopMovementUpdates()
	if self.MovementUpdateConnection then
		self.MovementUpdateConnection:Disconnect()
		self.MovementUpdateConnection = nil
	end
end

function ViewmodelAnimator:UpdateMovementAnimation()
	if not self.Animator then
		return
	end

	local character = LocalPlayer.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("Root")
	if not root then
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	local isGrounded = MovementStateManager:GetIsGrounded()
	local currentState = MovementStateManager:GetCurrentState()
	local isSliding = currentState == "Sliding"

	-- Get sprint state from CharacterController instead of using speed threshold
	local charController = getCharacterController()
	local isSprinting = charController and charController.IsSprinting or false

	-- Get air movement config
	local airConfig = ViewmodelConfig.AirMovement
	local allowAirRunning = airConfig and airConfig.AllowAirRunning or false

	local targetAnimation = "Idle"
	local isAirborne = not isGrounded

	if isSliding then
		targetAnimation = "Idle"
	elseif isAirborne then
		-- Allow running animation while airborne if enabled and moving
		if allowAirRunning and horizontalSpeed > 1 then
			-- Use sprint state for Run animation, not speed
			if isSprinting and self.AnimationTracks["Run"] then
				targetAnimation = "Run"
			else
				targetAnimation = "Walk"
			end
		else
			targetAnimation = "Idle"
		end
	elseif isSprinting and horizontalSpeed > 1 then
		-- Sprinting: play Run animation if available
		targetAnimation = self.AnimationTracks["Run"] and "Run" or "Walk"
	elseif horizontalSpeed > 1 then
		-- Walking (not sprinting)
		targetAnimation = "Walk"
	else
		targetAnimation = "Idle"
	end

	if self.CurrentMovementAnimation ~= targetAnimation then
		if self.CurrentMovementAnimation then
			local currentTrack = self.AnimationTracks[self.CurrentMovementAnimation]
			if currentTrack and currentTrack.IsPlaying then
				currentTrack:Stop(0.2)
			end
		end

		local newTrack = self.AnimationTracks[targetAnimation]
		if newTrack then
			newTrack:Play(0.2)
		end

		self.CurrentMovementAnimation = targetAnimation
	end

	-- Adjust animation speed based on grounded state and movement
	local currentTrack = self.AnimationTracks[self.CurrentMovementAnimation]
	if currentTrack and currentTrack.IsPlaying then
		if self.CurrentMovementAnimation == "Walk" or self.CurrentMovementAnimation == "Run" then
			local baseSpeedMultiplier = math.clamp(horizontalSpeed / 15, 0.5, 2.0)

			-- Apply air animation speed if airborne
			if isAirborne and allowAirRunning then
				local airAnimSpeed = airConfig.AirAnimationSpeed or 0.45
				currentTrack:AdjustSpeed(baseSpeedMultiplier * airAnimSpeed)
			else
				local groundedAnimSpeed = airConfig and airConfig.GroundedAnimationSpeed or 1.0
				currentTrack:AdjustSpeed(baseSpeedMultiplier * groundedAnimSpeed)
			end
		end
	end
end

function ViewmodelAnimator:PlayAnimation(animationName)
	if not self.Animator then
		return
	end

	local track = self.AnimationTracks[animationName]
	if not track then
		Log:Debug("VIEWMODEL", "Animation track not found", { Animation = animationName })
		return
	end

	-- Cancel any idle action if we're playing an important animation
	if animationName == "Fire" or animationName == "Attack" or animationName == "Reload" or animationName == "Equip" or animationName == "Inspect" then
		if self.IdleActionsManager then
			self.IdleActionsManager:CancelAction()
		end
	end

	if animationName == "Fire" or animationName == "Attack" or animationName == "Reload" or animationName == "Equip" then
		if track.IsPlaying then
			track:Stop(0)
		end
		track:Play(0.05)
	elseif animationName == "ADS" then
		if not track.IsPlaying then
			track:Play(0.15)
		end
	else
		if not track.IsPlaying then
			track:Play(0.2)
		end
	end

	Log:Debug("VIEWMODEL", "Playing animation", { Animation = animationName })
end

function ViewmodelAnimator:StopAnimation(animationName)
	if not self.Animator then
		return
	end

	local track = self.AnimationTracks[animationName]
	if track and track.IsPlaying then
		track:Stop(0.2)
		Log:Debug("VIEWMODEL", "Stopped animation", { Animation = animationName })
	end
end

function ViewmodelAnimator:StopAllAnimations()
	for _, track in pairs(self.AnimationTracks) do
		if track.IsPlaying then
			track:Stop(0)
		end
	end
	self.CurrentMovementAnimation = nil
end

function ViewmodelAnimator:IsPlaying(animationName)
	local track = self.AnimationTracks[animationName]
	return track and track.IsPlaying
end

function ViewmodelAnimator:GetTrack(animationName)
	return self.AnimationTracks[animationName]
end

function ViewmodelAnimator:LoadAnimation(animationName, animationId, priority)
	if not self.Animator then
		Log:Warn("VIEWMODEL", "Cannot load animation - no Animator", { Animation = animationName })
		return false
	end

	if not animationId or animationId == "" or animationId == "rbxassetid://0" then
		Log:Warn("VIEWMODEL", "Invalid animation ID", { Animation = animationName, ID = animationId })
		return false
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local success, result = pcall(function()
		return self.Animator:LoadAnimation(animation)
	end)

	if not success then
		Log:Warn("VIEWMODEL", "Failed to load animation", { Animation = animationName, Error = result })
		return false
	end

	local track = result
	track.Priority = priority or self.AnimationPriorities[animationName] or Enum.AnimationPriority.Action
	track.Looped = false

	self.AnimationTracks[animationName] = track

	Log:Debug("VIEWMODEL", "Dynamically loaded animation", { Animation = animationName, ID = animationId })
	return true
end

function ViewmodelAnimator:Cleanup()
	self:StopMovementUpdates()
	self:StopAllAnimations()

	-- Stop idle actions
	if self.IdleActionsManager then
		self.IdleActionsManager:Stop()
	end

	self.AnimationTracks = {}
	self.Animator = nil
	self.CurrentConfig = nil
	self.CurrentMovementAnimation = nil
	self.CurrentWeaponName = nil
end

return ViewmodelAnimator
