--[[
	IdleActionsManager.lua

	Manages random idle action animations for viewmodels.
	- Waits for the Idle loop to complete
	- Randomly picks an idle action from the weapon's config
	- Plays the idle action, then resumes normal Idle loop
	- Uses weighted random selection for varied animations

	============================================================================
	CONFIGURATION (in ViewmodelConfig.lua)
	============================================================================

	-- Global timing settings
	IdleActions = {
		MinInterval = 5,     -- Min seconds between attempts
		MaxInterval = 15,    -- Max seconds between attempts
		Chance = 0.3,        -- Probability of playing action
	}

	-- Per-weapon idle actions (in each weapon's Animations table)
	Weapons = {
		WeaponName = {
			Animations = {
				IdleActions = {
					{ Name = "ActionName", AnimationId = "rbxassetid://xxx", Weight = 1.0 },
				},
			},
		},
	}

	============================================================================
	HOW IT WORKS
	============================================================================

	1. After viewmodel creation, IdleActionsManager starts
	2. Waits random interval (MinInterval to MaxInterval seconds)
	3. Rolls chance (0.0 - 1.0)
	4. If passed, picks weighted random action from weapon's Animations.IdleActions
	5. Stops Idle loop, plays action animation
	6. When action finishes, resumes Idle loop
	7. Repeat from step 2

	============================================================================
]]

local IdleActionsManager = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)
local Log = require(Locations.Modules.Systems.Core.LogService)

local LocalPlayer = Players.LocalPlayer

-- State
IdleActionsManager.IsActive = false
IdleActionsManager.CurrentWeaponName = nil
IdleActionsManager.ViewmodelAnimator = nil
IdleActionsManager.Animator = nil

-- Timing
IdleActionsManager.LastActionTime = 0
IdleActionsManager.NextActionTime = 0
IdleActionsManager.IsPlayingAction = false

-- Movement tracking (for resetting timer on movement)
IdleActionsManager.WasMoving = false
IdleActionsManager.HasIdleActions = false -- Track if weapon has idle actions

-- Connections
IdleActionsManager.UpdateConnection = nil
IdleActionsManager.ActionStoppedConnection = nil

-- Cached action tracks
IdleActionsManager.ActionTracks = {}

--============================================================================
-- INITIALIZATION
--============================================================================

--[[
	Initialize the manager
	@param viewmodelAnimator table - Reference to ViewmodelAnimator
]]
function IdleActionsManager:Init(viewmodelAnimator)
	Log:RegisterCategory("IDLE_ACTIONS", "Idle action animation management")
	self.ViewmodelAnimator = viewmodelAnimator
	Log:Debug("IDLE_ACTIONS", "IdleActionsManager initialized")
end

--[[
	Start idle actions for a weapon
	@param weaponName string - Name of the weapon
	@param animator Animator - The viewmodel's Animator instance
]]
function IdleActionsManager:Start(weaponName, animator)
	self:Stop()

	self.CurrentWeaponName = weaponName
	self.Animator = animator
	self.IsPlayingAction = false
	self.ActionTracks = {}
	self.WasMoving = false

	-- Check if weapon has idle actions defined
	local actions = ViewmodelConfig:GetIdleActions(weaponName)
	self.HasIdleActions = actions and #actions > 0

	-- Don't start if no idle actions defined
	if not self.HasIdleActions then
		self:DebugLog("No idle actions defined for weapon, skipping", { Weapon = weaponName })
		return
	end

	self.IsActive = true

	-- Load action animations
	self:LoadActionAnimations()

	-- Schedule first action
	self:ScheduleNextAction()

	-- Start update loop
	self.UpdateConnection = RunService.Heartbeat:Connect(function()
		self:Update()
	end)

	self:DebugLog("Started for weapon", { Weapon = weaponName })
end

--[[
	Stop idle actions
]]
function IdleActionsManager:Stop()
	self.IsActive = false
	self.CurrentWeaponName = nil
	self.Animator = nil

	-- Disconnect update
	if self.UpdateConnection then
		self.UpdateConnection:Disconnect()
		self.UpdateConnection = nil
	end

	-- Disconnect action stopped listener
	if self.ActionStoppedConnection then
		self.ActionStoppedConnection:Disconnect()
		self.ActionStoppedConnection = nil
	end

	-- Stop all action tracks
	for _, track in pairs(self.ActionTracks) do
		if track.IsPlaying then
			track:Stop(0)
		end
	end
	self.ActionTracks = {}

	self:DebugLog("Stopped")
end

--============================================================================
-- ANIMATION LOADING
--============================================================================

--[[
	Load action animations from config
]]
function IdleActionsManager:LoadActionAnimations()
	if not self.Animator then
		return
	end

	local actions = ViewmodelConfig:GetIdleActions(self.CurrentWeaponName)
	if #actions == 0 then
		self:DebugLog("No idle actions defined for weapon", { Weapon = self.CurrentWeaponName })
		return
	end

	for _, actionDef in ipairs(actions) do
		if actionDef.AnimationId and actionDef.AnimationId ~= "rbxassetid://0" then
			local animation = Instance.new("Animation")
			animation.AnimationId = actionDef.AnimationId

			local track = self.Animator:LoadAnimation(animation)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = false

			self.ActionTracks[actionDef.Name] = track

			self:DebugLog("Loaded action animation", {
				Name = actionDef.Name,
				AnimationId = actionDef.AnimationId,
			})
		end
	end
end

--============================================================================
-- TIMING & SCHEDULING
--============================================================================

--[[
	Schedule the next action attempt
]]
function IdleActionsManager:ScheduleNextAction()
	local idleConfig = ViewmodelConfig.IdleActions

	-- Random interval between min and max
	local minInterval = idleConfig.MinInterval or 5
	local maxInterval = idleConfig.MaxInterval or 15
	local interval = minInterval + math.random() * (maxInterval - minInterval)

	self.LastActionTime = tick()
	self.NextActionTime = self.LastActionTime + interval

	self:DebugLog("Scheduled next action", {
		Interval = string.format("%.1f", interval),
		NextTime = string.format("%.1f", self.NextActionTime),
	})
end

--[[
	Update loop - check if it's time to try playing an action
]]
function IdleActionsManager:Update()
	if not self.IsActive or self.IsPlayingAction then
		return
	end

	-- Check for movement reset
	local idleConfig = ViewmodelConfig.IdleActions
	if idleConfig.ResetOnMovement then
		local isMoving = self:IsPlayerMoving()

		-- Reset timer when player starts or continues moving
		if isMoving then
			if not self.WasMoving then
				self:DebugLog("Player started moving, resetting idle timer")
			end
			self:ScheduleNextAction()
			self.WasMoving = true
			return
		else
			self.WasMoving = false
		end
	end

	-- Check if it's time to try an action
	if tick() < self.NextActionTime then
		return
	end

	-- Check if we should play an action (random chance)
	local chance = idleConfig.Chance or 0.3

	if math.random() > chance then
		-- Failed the chance roll, schedule next attempt
		self:ScheduleNextAction()
		self:DebugLog("Chance roll failed, scheduling next attempt")
		return
	end

	-- Don't interrupt other animations (reload, fire, etc.)
	if self:IsAnimationBlocking() then
		self:ScheduleNextAction()
		self:DebugLog("Animation blocking, scheduling next attempt")
		return
	end

	-- Try to play a random action
	self:TryPlayAction()
end

--[[
	Check if player is currently moving (walking or running)
	@return boolean - True if player has significant horizontal velocity
]]
function IdleActionsManager:IsPlayerMoving()
	local character = LocalPlayer.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("Root")
	if not root then
		return false
	end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	-- Consider moving if speed > 1 stud/s
	return horizontalSpeed > 1
end

--[[
	Check if important animations are currently playing
	@return boolean - True if we shouldn't interrupt
]]
function IdleActionsManager:IsAnimationBlocking()
	if not self.ViewmodelAnimator then
		return false
	end

	-- Don't interrupt these animations
	local blockingAnimations = { "Fire", "Reload", "Equip", "Attack", "Inspect" }

	for _, animName in ipairs(blockingAnimations) do
		if self.ViewmodelAnimator:IsPlaying(animName) then
			return true
		end
	end

	return false
end

--============================================================================
-- ACTION PLAYBACK
--============================================================================

--[[
	Try to play a random idle action
]]
function IdleActionsManager:TryPlayAction()
	-- Pick a random action based on weights
	local selectedAction = ViewmodelConfig:PickRandomIdleAction(self.CurrentWeaponName)
	if not selectedAction then
		self:ScheduleNextAction()
		return
	end

	-- Get the track for this action
	local track = self.ActionTracks[selectedAction.Name]
	if not track then
		self:DebugLog("No track found for action", { Name = selectedAction.Name })
		self:ScheduleNextAction()
		return
	end

	-- Play the action
	self:PlayAction(selectedAction.Name, track)
end

--[[
	Play an idle action animation
	@param actionName string - Name of the action
	@param track AnimationTrack - The animation track to play
]]
function IdleActionsManager:PlayAction(actionName, track)
	self.IsPlayingAction = true

	-- Stop the idle animation
	if self.ViewmodelAnimator then
		self.ViewmodelAnimator:StopAnimation("Idle")
	end

	-- Play the action
	track:Play(0.2)

	self:DebugLog("Playing idle action", {
		Action = actionName,
		Length = string.format("%.2f", track.Length),
	})

	-- Listen for when action finishes
	if self.ActionStoppedConnection then
		self.ActionStoppedConnection:Disconnect()
	end

	self.ActionStoppedConnection = track.Stopped:Connect(function()
		self:OnActionFinished(actionName)
	end)
end

--[[
	Called when an action animation finishes
	@param actionName string - Name of the action that finished
]]
function IdleActionsManager:OnActionFinished(actionName)
	self.IsPlayingAction = false

	-- Resume idle animation
	if self.ViewmodelAnimator and self.IsActive then
		self.ViewmodelAnimator:PlayAnimation("Idle")
	end

	-- Schedule next action
	self:ScheduleNextAction()

	self:DebugLog("Action finished, resumed idle", { Action = actionName })
end

--============================================================================
-- UTILITY
--============================================================================

--[[
	Force cancel current action (e.g., when player fires)
]]
function IdleActionsManager:CancelAction()
	if not self.IsPlayingAction then
		return
	end

	-- Stop all action tracks
	for name, track in pairs(self.ActionTracks) do
		if track.IsPlaying then
			track:Stop(0.1)
			self:DebugLog("Cancelled action", { Action = name })
		end
	end

	self.IsPlayingAction = false

	-- Clean up connection
	if self.ActionStoppedConnection then
		self.ActionStoppedConnection:Disconnect()
		self.ActionStoppedConnection = nil
	end

	-- Resume idle
	if self.ViewmodelAnimator then
		self.ViewmodelAnimator:PlayAnimation("Idle")
	end

	-- Schedule next action
	self:ScheduleNextAction()
end

--[[
	Check if currently playing an idle action
	@return boolean
]]
function IdleActionsManager:IsPlayingIdleAction()
	return self.IsPlayingAction
end

--[[
	Debug log helper
]]
function IdleActionsManager:DebugLog(message, data)
	if ViewmodelConfig.Debug and ViewmodelConfig.Debug.LogIdleActions then
		Log:Debug("IDLE_ACTIONS", message, data)
	end
end

return IdleActionsManager
