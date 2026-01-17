local AnimationController = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local Config = require(Locations.Modules.Config)
local TestMode = require(Locations.Modules.TestMode)
local MovementStateManager = require(Locations.Modules.Systems.Movement.MovementStateManager)
local SlidingSystem = require(Locations.Modules.Systems.Movement.SlidingSystem)
local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
local WalkDirectionDetector = require(Locations.Modules.Utils.WalkDirectionDetector)

local player = Players.LocalPlayer

-- State
AnimationController.Initialized = false
AnimationController.LocalCharacter = nil
AnimationController.LocalAnimator = nil
AnimationController.LocalAnimationTracks = {} -- Preloaded animation tracks
AnimationController.CurrentStateAnimation = nil -- Currently playing state animation
AnimationController.CurrentIdleAnimation = nil -- Currently playing idle animation
AnimationController.CurrentAirborneAnimation = nil -- Currently playing airborne animation (Jump/JumpCancel/Falling)
AnimationController.LastReplicatedAnimation = nil -- Track last replicated animation to prevent redundant network calls
AnimationController.LastJumpCancelAnimationIndex = nil -- Track last jump cancel animation to prevent repeats
AnimationController.CurrentSlideAnimationName = nil -- Track current directional slide animation
AnimationController.SlideAnimationUpdateConnection = nil -- Connection for updating slide animations
AnimationController.CurrentWalkAnimationName = nil -- Track current directional walk animation
AnimationController.WalkAnimationUpdateConnection = nil -- Connection for updating walk animations
AnimationController.CurrentCrouchAnimationName = nil -- Track current directional crouch animation
AnimationController.CrouchAnimationUpdateConnection = nil -- Connection for updating crouch animations
AnimationController.CurrentAnimationName = "IdleStanding" -- Track current animation name for enum lookup
AnimationController.CurrentAnimationId = 1 -- Track current animation ID (enum value for replication)
AnimationController.LastAirborneAnimationTime = 0 -- Track when airborne animation started for grace period
AnimationController.AnimationSpeedUpdateConnection = nil -- Connection for updating animation speed based on velocity
AnimationController.CharacterController = nil -- Reference to CharacterController for accessing movement data

-- Other players' animation tracking
AnimationController.OtherCharacterAnimators = {} -- [character] = Animator
AnimationController.OtherCharacterTracks = {} -- [character] = {animationName = track}
AnimationController.OtherCharacterCurrentAnimations = {} -- [character] = {State = track, Idle = track, Airborne = track, Action = track}

function AnimationController:Init()
	Log:RegisterCategory("ANIMATION_CLIENT", "Client-side animation playback and management")

	-- Listen for local character spawn
	RemoteEvents:ConnectClient("CharacterSpawned", function(characterModel)
		if characterModel and characterModel.Parent and characterModel.Name == player.Name then
			self:OnLocalCharacterSpawned(characterModel)
		else
			-- Another player's character spawned
			self:OnOtherCharacterSpawned(characterModel)
		end
	end)

	-- Listen for character removal
	RemoteEvents:ConnectClient("CharacterRemoving", function(characterModel)
		if characterModel and characterModel.Name == player.Name then
			self:OnLocalCharacterRemoving()
		else
			self:OnOtherCharacterRemoving(characterModel)
		end
	end)

	-- DEPRECATED: Animation replication now handled by unified state system
	-- RemoteReplicator now handles animation changes via CharacterStateReplicated
	-- This listener is kept to avoid errors, but does nothing
	RemoteEvents:ConnectClient("PlayAnimation", function(_targetPlayer, _animationName, _category, _variantIndex)
		-- No-op: Animation replication now handled by RemoteReplicator
	end)

	-- Connect to movement state changes to play animations
	MovementStateManager:ConnectToStateChange(function(previousState, newState, data)
		self:OnMovementStateChanged(previousState, newState, data)
	end)

	-- Connect to movement changes for idle vs moving animations
	MovementStateManager:ConnectToMovementChange(function(wasMoving, isMoving)
		self:OnMovementChanged(wasMoving, isMoving)
	end)

	-- Connect to grounded state changes for airborne animations
	MovementStateManager:ConnectToGroundedChange(function(wasGrounded, isGrounded)
		self:OnGroundedChanged(wasGrounded, isGrounded)
	end)

	self.Initialized = true
	Log:Info("ANIMATION_CLIENT", "AnimationController initialized")
end

function AnimationController:OnLocalCharacterSpawned(character)
	self.LocalCharacter = character

	-- NEW: Rig is now in workspace.Rigs - wait for it to be created by RigManager
	-- Poll for the rig since it's created asynchronously
	local rig = nil
	local maxWaitTime = 10
	local startTime = tick()

	while not rig and (tick() - startTime) < maxWaitTime do
		rig = CharacterLocations:GetRig(character)
		if not rig then
			task.wait(0.1)
		end
	end

	if not rig then
		Log:Error("ANIMATION_CLIENT", "Rig not found for local character after waiting")
		return
	end

	-- Wait for Humanoid in Rig
	local humanoid = rig:WaitForChild("Humanoid", 10)
	if not humanoid then
		Log:Error("ANIMATION_CLIENT", "Humanoid not found in Rig")
		return
	end

	-- Wait for server-created Animator (CRITICAL for replication)
	local animator = humanoid:WaitForChild("Animator", 10)
	if not animator then
		Log:Error("ANIMATION_CLIENT", "Animator not found (should be created server-side)")
		return
	end

	self.LocalAnimator = animator
	Log:Info("ANIMATION_CLIENT", "Found server-created Animator for local character")

	-- Preload all animations
	self:PreloadAnimations()

	-- Play initial idle animation (replication now handled by unified state system)
	self:PlayIdleAnimation("IdleStanding")

	-- Start animation speed updates based on velocity
	self:StartAnimationSpeedUpdates()

	Log:Info("ANIMATION_CLIENT", "Local character animation setup complete")
end

function AnimationController:OnLocalCharacterRemoving()
	-- Stop all playing animations
	self:StopAllLocalAnimations()

	-- Stop slide animation updates
	self:StopSlideAnimationUpdates()

	-- Stop walk animation updates
	self:StopWalkAnimationUpdates()

	-- Stop crouch animation updates
	self:StopCrouchAnimationUpdates()

	-- Stop animation speed updates
	self:StopAnimationSpeedUpdates()

	-- Clear references
	self.LocalCharacter = nil
	self.LocalAnimator = nil
	self.LocalAnimationTracks = {}
	self.CurrentStateAnimation = nil
	self.CurrentIdleAnimation = nil
	self.CharacterController = nil

	Log:Debug("ANIMATION_CLIENT", "Local character animation cleanup complete")
end

function AnimationController:OnOtherCharacterSpawned(character)
	if not character or not character.Parent then
		return
	end

	-- Poll for rig in workspace.Rigs (created asynchronously by RigManager)
	local rig = nil
	local maxWaitTime = 10
	local startTime = tick()

	while not rig and (tick() - startTime) < maxWaitTime do
		rig = CharacterLocations:GetRig(character)
		if not rig then task.wait(0.1) end
	end

	if not rig then
		Log:Warn("ANIMATION_CLIENT", "Rig not found for other player after waiting", {
			Character = character.Name
		})
		return
	end

	-- Wait for Humanoid
	local humanoid = rig:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end

	-- Wait for Animator (created server-side)
	local animator = humanoid:WaitForChild("Animator", 5)
	if not animator then
		return
	end

	-- Store animator reference
	self.OtherCharacterAnimators[character] = animator
	self.OtherCharacterTracks[character] = {}
	self.OtherCharacterCurrentAnimations[character] = {}

	Log:Debug("ANIMATION_CLIENT", "Setup animator for other player", { Character = character.Name })
end

function AnimationController:OnOtherCharacterRemoving(character)
	if not character then
		return
	end

	-- Stop all animations for this character
	local tracks = self.OtherCharacterTracks[character]
	if tracks then
		for _, track in pairs(tracks) do
			if track.IsPlaying then
				track:Stop()
			end
		end
	end

	-- Cleanup references
	self.OtherCharacterAnimators[character] = nil
	self.OtherCharacterTracks[character] = nil
	self.OtherCharacterCurrentAnimations[character] = nil

	Log:Debug("ANIMATION_CLIENT", "Cleaned up animations for other player", { Character = character.Name })
end

function AnimationController:PreloadAnimations()
	if not self.LocalAnimator then
		Log:Warn("ANIMATION_CLIENT", "Cannot preload animations - no Animator")
		return
	end

	local animationsToPreload = Config.Animation.Preloading.PreloadList
	local assetIds = {}

	-- Create Animation instances and load them into tracks
	for _, animationName in ipairs(animationsToPreload) do
		local animData = Config.Animation.Animations[animationName]

		-- Handle animations with multiple IDs (like JumpCancel)
		if animData and animData.Ids then
			-- Special handling for JumpCancel with multiple animation IDs
			self.LocalAnimationTracks[animationName] = {} -- Store as array of tracks

			for index, animId in ipairs(animData.Ids) do
				local animation = Instance.new("Animation")
				animation.AnimationId = animId

				local track = self.LocalAnimator:LoadAnimation(animation)
				track.Priority = animData.Priority
				track.Looped = animData.Loop

				-- Store track in array
				self.LocalAnimationTracks[animationName][index] = track

				-- Store asset ID for preloading
				table.insert(assetIds, animId)

				Log:Debug(
					"ANIMATION_CLIENT",
					"Loaded animation track variant",
					{ Animation = animationName, Variant = index }
				)
			end
		elseif animData and animData.Id then
			-- Single animation ID (normal case)
			local animation = Instance.new("Animation")
			animation.AnimationId = animData.Id

			-- Load animation into track (this caches it)
			local track = self.LocalAnimator:LoadAnimation(animation)

			-- Configure track properties
			track.Priority = animData.Priority
			track.Looped = animData.Loop

			-- Store track for instant playback
			self.LocalAnimationTracks[animationName] = track

			-- Store asset ID for ContentProvider preloading
			table.insert(assetIds, animData.Id)

			Log:Debug("ANIMATION_CLIENT", "Loaded animation track", { Animation = animationName })
		end
	end

	-- Preload animation assets using ContentProvider
	if Config.Animation.Preloading.PreloadOnJoin and #assetIds > 0 then
		task.spawn(function()
			local success, err = pcall(function()
				ContentProvider:PreloadAsync(assetIds)
			end)

			if success then
				Log:Info("ANIMATION_CLIENT", "Preloaded animation assets", { Count = #assetIds })
			else
				Log:Warn("ANIMATION_CLIENT", "Failed to preload animations", { Error = err })
			end
		end)
	end
end

function AnimationController:OnMovementStateChanged(previousState, newState, _data)
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	-- Sliding states use directional animations (handled separately)
	local isSliding = (newState == "Sliding" )
	local isMoving = MovementStateManager:GetIsMoving()
	local isGrounded = MovementStateManager:GetIsGrounded()

	-- If airborne and transitioning to a grounded state, play falling animation instead
	if not isGrounded and not isSliding then
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "State changed while airborne, playing falling animation", {
				PreviousState = previousState,
				NewState = newState,
				IsMoving = isMoving,
			})
		end
		-- Make sure falling animation is playing
		if not self.CurrentAirborneAnimation or not self.CurrentAirborneAnimation.IsPlaying then
			self:PlayFallingAnimation()
		end
		return
	end

	-- CRITICAL FIX: Don't play grounded animations if an airborne animation is currently playing
	-- This prevents conflicts when jump cancel triggers state changes (e.g., Sliding -> Walking)
	-- while the JumpCancel animation should remain active
	-- EXCEPTION: Allow sliding state changes - slides take priority and will cancel airborne animations
	if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying and not isSliding then
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Skipping state animation change (airborne animation has priority)", {
				PreviousState = previousState,
				NewState = newState,
				CurrentAirborneAnimation = "playing",
			})
		end
		-- Still handle slide animation updates stopping
		self:StopSlideAnimationUpdates()
		return
	end

	-- EDGE CASE FIX #1: Add grace period after airborne animation starts
	-- Prevents grounded state changes from immediately overriding airborne animations on ramps
	-- BUT allow sliding transitions - slide animations should take priority immediately
	local timeSinceAirborneAnim = tick() - self.LastAirborneAnimationTime
	if timeSinceAirborneAnim < 0.2 and isGrounded and not isSliding then
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Skipping state change (within airborne animation grace period)", {
				TimeSince = timeSinceAirborneAnim,
				PreviousState = previousState,
				NewState = newState,
			})
		end
		return
	end

	-- EDGE CASE FIX #4: Clean up airborne animations when transitioning out of sliding while grounded
	-- This prevents character getting stuck in airborne animation after slide ends
	if (previousState == "Sliding" ) and not isSliding then
		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying and isGrounded then
			if TestMode.Logging.LogAnimationSystem then
				Log:Info("ANIMATION_CLIENT", "Stopping airborne animation (slide ended while grounded)", {
					PreviousState = previousState,
					NewState = newState,
				})
			end
			self:StopAirborneAnimation()
		end
	end

	-- Handle sliding state - start directional slide animation updates
	if isSliding then
		-- EDGE CASE FIX #5: Explicitly stop idle and airborne animations before starting slide
		-- Slide animations should immediately replace any other animations
		if self.CurrentIdleAnimation and self.CurrentIdleAnimation.IsPlaying then
			self.CurrentIdleAnimation:Stop(0.1)
			if TestMode.Logging.LogAnimationSystem then
				Log:Debug("ANIMATION_CLIENT", "Stopped idle animation before slide")
			end
		end
		-- Stop airborne animation when entering slide (even if still playing)
		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
			if TestMode.Logging.LogAnimationSystem then
				Log:Info("ANIMATION_CLIENT", "Stopping airborne animation for slide transition", {
					PreviousState = previousState,
					NewState = newState,
				})
			end
			self:StopAirborneAnimation()
		end
		self:StartSlideAnimationUpdates()
		return
	else
		-- Stop slide animation updates if transitioning away from sliding
		self:StopSlideAnimationUpdates()
	end

	-- Get the animation name for non-sliding states
	local animationName = Config.Animation.StateAnimations[newState]
	if not animationName then
		Log:Warn("ANIMATION_CLIENT", "No animation defined for state", { State = newState })
		return
	end

	if isMoving then
		-- For Walking/Sprinting states, start directional animation updates
		if newState == "Walking" or newState == "Sprinting" then
			self:StartWalkAnimationUpdates()
		elseif newState == "Crouching" then
			-- For Crouching state, start directional crouch animation updates
			self:StartCrouchAnimationUpdates()
		else
			-- For other states, play normal state animation
			self:PlayStateAnimation(animationName)
		end
	else
		-- Stop walk animation updates if not moving
		self:StopWalkAnimationUpdates()

		-- Stop crouch animation updates if not moving
		self:StopCrouchAnimationUpdates()

		-- If not moving, play the idle animation for this state
		local idleAnimationName = self:GetIdleAnimationForState(newState)
		if idleAnimationName then
			self:PlayIdleAnimation(idleAnimationName)
		end
	end

	if TestMode.Logging.LogAnimationSystem then
		Log:Info("ANIMATION_CLIENT", "Movement state changed", {
			PreviousState = previousState,
			NewState = newState,
			IsMoving = isMoving,
			Animation = animationName,
		})
	end
end

function AnimationController:GetIdleAnimationForState(state)
	-- Map states to their idle animations
	if state == "Walking" or state == "Sprinting" then
		return "IdleStanding"
	elseif state == "Crouching" then
		return "IdleCrouching"
	end

	return nil
end

function AnimationController:OnMovementChanged(wasMoving, isMoving)
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	local currentState = MovementStateManager:GetCurrentState()
	local isGrounded = MovementStateManager:GetIsGrounded()

	-- Sliding states always play their animation (no idle state)
	local isSliding = (currentState == "Sliding" )
	if isSliding then
		-- Sliding always plays sliding animation, ignore movement changes
		return
	end

	-- If airborne, don't play grounded animations (falling animation should be playing)
	if not isGrounded then
		Log:Info("ANIMATION_CLIENT", "Movement changed while airborne, keeping airborne animation", {
			WasMoving = wasMoving,
			IsMoving = isMoving,
			CurrentState = currentState,
		})
		return
	end

	Log:Debug("ANIMATION_CLIENT", "Movement state changed", {
		WasMoving = wasMoving,
		IsMoving = isMoving,
		CurrentState = currentState,
	})

	if isMoving then
		-- Started moving - play movement animation or start directional updates
		if currentState == "Walking" or currentState == "Sprinting" then
			-- Start directional walking animation updates
			self:StartWalkAnimationUpdates()
		elseif currentState == "Crouching" then
			-- Start directional crouch animation updates
			self:StartCrouchAnimationUpdates()
		else
			-- For other states, play normal state animation
			local animationName = Config.Animation.StateAnimations[currentState]
			if animationName then
				self:PlayStateAnimation(animationName)
			end
		end
	else
		-- Stopped moving - stop walk and crouch updates and play idle animation
		self:StopWalkAnimationUpdates()
		self:StopCrouchAnimationUpdates()

		local idleAnimationName = self:GetIdleAnimationForState(currentState)
		if idleAnimationName then
			self:PlayIdleAnimation(idleAnimationName)
		end
	end
end

function AnimationController:PlayStateAnimation(animationName)
	if not self.LocalAnimator then
		return
	end

	local track = self.LocalAnimationTracks[animationName]
	if not track then
		Log:Warn("ANIMATION_CLIENT", "Animation track not found", { Animation = animationName })
		return
	end

	if TestMode.Logging.LogAnimationSystem then
		-- Log current animation state before making changes
		Log:Info("ANIMATION_CLIENT", "PlayStateAnimation() called", {
			RequestedAnimation = animationName,
			CurrentState = self.CurrentStateAnimation and "playing" or "nil",
			CurrentIdle = self.CurrentIdleAnimation and "playing" or "nil",
			CurrentAirborne = self.CurrentAirborneAnimation and "playing" or "nil",
		})
	end

	-- Stop current state animation if different
	if self.CurrentStateAnimation and self.CurrentStateAnimation ~= track and self.CurrentStateAnimation.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		self.CurrentStateAnimation:Stop(animData.FadeOutTime)
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Stopped previous state animation", {
				FadeOutTime = animData.FadeOutTime,
			})
		end
	end

	-- Stop idle animation
	if self.CurrentIdleAnimation and self.CurrentIdleAnimation.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		self.CurrentIdleAnimation:Stop(animData.FadeOutTime)
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Stopped idle animation", {
				FadeOutTime = animData.FadeOutTime,
			})
		end
	end

	-- Stop airborne animation when playing a state animation (grounded animations take priority)
	if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		self.CurrentAirborneAnimation:Stop(animData.FadeOutTime)
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Stopped airborne animation for state animation", {
				StateAnimation = animationName,
				FadeOutTime = animData.FadeOutTime,
			})
		end
		self.CurrentAirborneAnimation = nil
	end

	-- Play new animation if not already playing
	if not track.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		track:Play(animData.FadeInTime, animData.Weight)
		self.CurrentStateAnimation = track
		self:SetCurrentAnimation(animationName) -- Track for replication

		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Playing state animation", {
				Animation = animationName,
				AnimationId = animData.Id,
				FadeInTime = animData.FadeInTime,
				Weight = animData.Weight,
				IsPlaying = track.IsPlaying,
			})
			self:LogCurrentAnimationState()
		end
	else
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Animation already playing, skipping", {
				Animation = animationName,
			})
		end
	end
end

function AnimationController:PlayIdleAnimation(animationName)
	if not self.LocalAnimator then
		return
	end

	local track = self.LocalAnimationTracks[animationName]
	if not track then
		Log:Warn("ANIMATION_CLIENT", "Idle animation track not found", { Animation = animationName })
		return
	end

	if TestMode.Logging.LogAnimationSystem then
		-- Log current animation state before making changes
		Log:Info("ANIMATION_CLIENT", "PlayIdleAnimation() called", {
			RequestedAnimation = animationName,
			CurrentState = self.CurrentStateAnimation and "playing" or "nil",
			CurrentIdle = self.CurrentIdleAnimation and "playing" or "nil",
			CurrentAirborne = self.CurrentAirborneAnimation and "playing" or "nil",
		})
	end

	-- Stop current idle animation if different
	if self.CurrentIdleAnimation and self.CurrentIdleAnimation ~= track and self.CurrentIdleAnimation.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		self.CurrentIdleAnimation:Stop(animData.FadeOutTime)
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Stopped previous idle animation", {
				FadeOutTime = animData.FadeOutTime,
			})
		end
	end

	-- Stop state animation
	if self.CurrentStateAnimation and self.CurrentStateAnimation.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		self.CurrentStateAnimation:Stop(animData.FadeOutTime)
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Stopped state animation", {
				FadeOutTime = animData.FadeOutTime,
			})
		end
	end

	-- Play new idle animation if not already playing
	if not track.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		track:Play(animData.FadeInTime, animData.Weight)
		self.CurrentIdleAnimation = track
		self:SetCurrentAnimation(animationName) -- Track for replication

		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Playing idle animation", {
				Animation = animationName,
				AnimationId = animData.Id,
				FadeInTime = animData.FadeInTime,
				Weight = animData.Weight,
			})
			self:LogCurrentAnimationState()
		end
	end
end

function AnimationController:PlayActionAnimation(animationName)
	if not self.LocalAnimator then
		return
	end

	local track = self.LocalAnimationTracks[animationName]
	if not track then
		Log:Warn("ANIMATION_CLIENT", "Action animation track not found", { Animation = animationName })
		return
	end

	-- Action animations don't stop state/idle animations, they play on top
	local animData = Config.Animation.Animations[animationName]
	track:Play(animData.FadeInTime, animData.Weight)
	self:SetCurrentAnimation(animationName) -- Track for replication

	Log:Debug("ANIMATION_CLIENT", "Playing action animation", { Animation = animationName })
end

function AnimationController:StopAllLocalAnimations()
	for _, track in pairs(self.LocalAnimationTracks) do
		if track.IsPlaying then
			track:Stop()
		end
	end

	self.CurrentStateAnimation = nil
	self.CurrentIdleAnimation = nil
end

function AnimationController:PlayAnimationForOtherPlayer(targetPlayer, animationName, category, variantIndex)
	if not targetPlayer or targetPlayer == player then
		return -- Don't play on self
	end

	local character = targetPlayer.Character
	if not character or not character.Parent then
		return
	end

	local animator = self.OtherCharacterAnimators[character]
	if not animator then
		Log:Debug("ANIMATION_CLIENT", "No animator for other player", { Player = targetPlayer.Name })
		return
	end

	-- Get animation data and category
	local animData = Config.Animation.Animations[animationName]
	if not animData then
		Log:Warn("ANIMATION_CLIENT", "Animation data not found", { Animation = animationName })
		return
	end

	-- Default category if not provided
	category = category or animData.Category or "State"

	-- Get or load animation track
	local tracks = self.OtherCharacterTracks[character]
	local track
	local trackKey = animationName

	-- Handle multi-animation variants (JumpCancel)
	if animationName == "JumpCancel" and variantIndex then
		-- For JumpCancel with variant, create unique track key
		trackKey = animationName .. "_" .. variantIndex
		track = tracks[trackKey]

		if not track then
			-- Load specific variant
			local animIds = animData.Ids
			if animIds and animIds[variantIndex] then
				local animation = Instance.new("Animation")
				animation.AnimationId = animIds[variantIndex]

				track = animator:LoadAnimation(animation)
				track.Priority = animData.Priority
				track.Looped = animData.Loop

				tracks[trackKey] = track

				-- Setup auto-transition after animation stops (with grounded state check)
				track.Stopped:Connect(function()
					-- Check player's current state to determine transition
					local remoteReplicator = ServiceRegistry:GetSystem("RemoteReplicator")
					if remoteReplicator then
						local remoteData = remoteReplicator.RemotePlayers[targetPlayer.UserId]
						if not remoteData then
							return
						end

						local isGrounded = remoteData.LastIsGrounded

						-- Only transition to falling if player is still airborne
						-- If grounded, let network replication handle grounded animations
						if isGrounded == false then
							-- Still airborne -> transition to falling
							task.wait(0.1)
							local fallingTrack = tracks["Falling"]
							if fallingTrack and not fallingTrack.IsPlaying then
								local fallingData = Config.Animation.Animations["Falling"]
								fallingTrack:Play(fallingData.FadeInTime, fallingData.Weight)

								if not self.OtherCharacterCurrentAnimations[character] then
									self.OtherCharacterCurrentAnimations[character] = {}
								end
								self.OtherCharacterCurrentAnimations[character].Airborne = fallingTrack
							end
						end
						-- If grounded (isGrounded == true), no action needed - RemoteReplicator handles animation updates
					end
				end)
			end
		end
	else
		-- Normal single animation
		track = tracks[animationName]

		if not track then
			-- Load animation for this character
			local animation = Instance.new("Animation")
			animation.AnimationId = animData.Id

			track = animator:LoadAnimation(animation)
			track.Priority = animData.Priority
			track.Looped = animData.Loop

			tracks[animationName] = track

			-- For one-shot airborne animations, setup auto-transition after animation stops
			if animationName == "Jump" and not animData.Loop then
				track.Stopped:Connect(function()
					-- Check player's current state to determine transition
					local remoteReplicator = ServiceRegistry:GetSystem("RemoteReplicator")
					if remoteReplicator then
						local remoteData = remoteReplicator.RemotePlayers[targetPlayer.UserId]
						if not remoteData then
							return
						end

						local isGrounded = remoteData.LastIsGrounded

						-- Only transition to falling if player is still airborne
						-- If grounded, let network replication handle grounded animations
						if isGrounded == false then
							-- Still airborne -> transition to falling
							task.wait(0.1) -- Small delay to ensure smooth transition
							local fallingTrack = tracks["Falling"]
							if fallingTrack and not fallingTrack.IsPlaying then
								local fallingData = Config.Animation.Animations["Falling"]
								fallingTrack:Play(fallingData.FadeInTime, fallingData.Weight)

								-- Initialize current animations table if needed
								if not self.OtherCharacterCurrentAnimations[character] then
									self.OtherCharacterCurrentAnimations[character] = {}
								end
								self.OtherCharacterCurrentAnimations[character].Airborne = fallingTrack
							end
						end
						-- If grounded (isGrounded == true), no action needed - RemoteReplicator handles animation updates
					end
				end)
			end
		end
	end

	-- Initialize current animations table for this character if needed
	if not self.OtherCharacterCurrentAnimations[character] then
		self.OtherCharacterCurrentAnimations[character] = {}
	end

	local currentAnims = self.OtherCharacterCurrentAnimations[character]

	-- Category-based stopping logic
	if category == "State" then
		-- State animations stop Idle animations (movement takes priority over idle)
		if currentAnims.Idle and currentAnims.Idle.IsPlaying then
			currentAnims.Idle:Stop(animData.FadeOutTime)
		end
		-- Stop previous state animation if different
		if currentAnims.State and currentAnims.State ~= track and currentAnims.State.IsPlaying then
			currentAnims.State:Stop(animData.FadeOutTime)
		end
		-- Stop airborne animations when grounded movement starts
		if currentAnims.Airborne and currentAnims.Airborne.IsPlaying then
			currentAnims.Airborne:Stop(animData.FadeOutTime)
		end
	elseif category == "Idle" then
		-- Idle animations stop State animations (idle replaces movement when stopped)
		if currentAnims.State and currentAnims.State.IsPlaying then
			currentAnims.State:Stop(animData.FadeOutTime)
		end
		-- Stop previous idle animation if different
		if currentAnims.Idle and currentAnims.Idle ~= track and currentAnims.Idle.IsPlaying then
			currentAnims.Idle:Stop(animData.FadeOutTime)
		end
		-- Stop airborne animations when grounded idle starts
		if currentAnims.Airborne and currentAnims.Airborne.IsPlaying then
			currentAnims.Airborne:Stop(animData.FadeOutTime)
		end
	elseif category == "Airborne" then
		-- Airborne animations stop State and Idle (airborne has highest priority)
		if currentAnims.State and currentAnims.State.IsPlaying then
			currentAnims.State:Stop(animData.FadeOutTime)
		end
		if currentAnims.Idle and currentAnims.Idle.IsPlaying then
			currentAnims.Idle:Stop(animData.FadeOutTime)
		end
		-- Stop previous airborne animation if different
		if currentAnims.Airborne and currentAnims.Airborne ~= track and currentAnims.Airborne.IsPlaying then
			currentAnims.Airborne:Stop(animData.FadeOutTime)
		end
	elseif category == "Action" then
		-- Action animations play on top, don't stop anything
		-- Just stop previous action if different
		if currentAnims.Action and currentAnims.Action ~= track and currentAnims.Action.IsPlaying then
			currentAnims.Action:Stop(animData.FadeOutTime)
		end
	end

	-- Play the animation
	-- For Action animations: always restart even if playing (allows spamming)
	-- For other categories: only play if not already playing (prevents redundant replays)
	if category == "Action" then
		-- Action animations: restart from beginning even if already playing
		if track.IsPlaying then
			track:Stop(0) -- Instant stop
		end
		track:Play(animData.FadeInTime, animData.Weight)
		currentAnims[category] = track

		Log:Debug("ANIMATION_CLIENT", "Playing action animation for other player (restart allowed)", {
			Player = targetPlayer.Name,
			Animation = animationName,
			WasAlreadyPlaying = track.IsPlaying,
		})
	elseif not track.IsPlaying then
		-- State/Idle/Airborne animations: only play if not already playing
		track:Play(animData.FadeInTime, animData.Weight)
		currentAnims[category] = track

		Log:Debug("ANIMATION_CLIENT", "Playing animation for other player", {
			Player = targetPlayer.Name,
			Animation = animationName,
			Category = category,
		})
	end
end

function AnimationController:OnGroundedChanged(wasGrounded, isGrounded)
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	local currentState = MovementStateManager:GetCurrentState()
	local isSliding = (currentState == "Sliding" )

	if TestMode.Logging.LogAnimationSystem then
		Log:Info("ANIMATION_CLIENT", "Grounded state changed", {
			WasGrounded = wasGrounded,
			IsGrounded = isGrounded,
			CurrentState = currentState,
			IsSliding = isSliding,
			CurrentAirborne = self.CurrentAirborneAnimation and "playing" or "nil",
		})
	end

	if isGrounded then
		-- Landed - stop airborne animations and play grounded animations
		self:StopAirborneAnimation()

		-- Play appropriate grounded animation based on state and movement
		local isMoving = MovementStateManager:GetIsMoving()
		if isSliding or isMoving then
			local animationName = Config.Animation.StateAnimations[currentState]
			if animationName then
				self:PlayStateAnimation(animationName)
			end
		else
			local idleAnimationName = self:GetIdleAnimationForState(currentState)
			if idleAnimationName then
				self:PlayIdleAnimation(idleAnimationName)
			end
		end
	else
		-- Became airborne - play falling animation if not sliding
		if not isSliding then
			-- Check if we already have an airborne animation playing (e.g., from jump)
			local hasAirborneAnimation = self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying

			-- EDGE CASE FIX #6: Force falling animation even if grounded animation is still playing
			-- This handles walking off edges without jumping
			local shouldForceFalling = false
			if not hasAirborneAnimation then
				shouldForceFalling = true
			elseif self.CurrentAirborneAnimation then
				-- Check if current airborne animation is actually an airborne animation
				-- (not just a mis-categorized state animation)
				local fallingTrack = self.LocalAnimationTracks["Falling"]
				local jumpTrack = self.LocalAnimationTracks["Jump"]
				local jumpCancelTracks = self.LocalAnimationTracks["JumpCancel"]

				local isValidAirborne = self.CurrentAirborneAnimation == fallingTrack
					or self.CurrentAirborneAnimation == jumpTrack

				-- Check JumpCancel variants
				if not isValidAirborne and type(jumpCancelTracks) == "table" then
					for _, track in ipairs(jumpCancelTracks) do
						if self.CurrentAirborneAnimation == track then
							isValidAirborne = true
							break
						end
					end
				end

				if not isValidAirborne then
					shouldForceFalling = true
				end
			end

			if TestMode.Logging.LogAnimationSystem then
				Log:Info("ANIMATION_CLIENT", "Became airborne", {
					HasAirborneAnimation = hasAirborneAnimation,
					ShouldForceFalling = shouldForceFalling,
				})
			end

			if shouldForceFalling then
				-- No airborne animation playing, or wrong animation playing - start falling animation
				self:PlayFallingAnimation()
				-- Falling animation will replicate itself with force flag
			end
		end
	end
end

function AnimationController:SelectRandomJumpCancelTrack()
	local jumpCancelTracks = self.LocalAnimationTracks["JumpCancel"]
	if not jumpCancelTracks or type(jumpCancelTracks) ~= "table" then
		Log:Warn("ANIMATION_CLIENT", "JumpCancel tracks not found or not a table")
		return nil
	end

	local numTracks = #jumpCancelTracks
	if numTracks == 0 then
		Log:Warn("ANIMATION_CLIENT", "No JumpCancel tracks available")
		return nil
	end

	-- If only one track, return it
	if numTracks == 1 then
		return jumpCancelTracks[1], 1
	end

	-- Select random index that's different from last one
	local randomIndex
	repeat
		randomIndex = math.random(1, numTracks)
	until randomIndex ~= self.LastJumpCancelAnimationIndex

	self.LastJumpCancelAnimationIndex = randomIndex

	Log:Debug("ANIMATION_CLIENT", "Selected random JumpCancel animation", {
		SelectedIndex = randomIndex,
		TotalVariants = numTracks,
		PreviousIndex = self.LastJumpCancelAnimationIndex,
	})

	return jumpCancelTracks[randomIndex], randomIndex
end

function AnimationController:PlayAirborneAnimation(animationName, forceVariantIndex)
	if not self.LocalAnimator then
		return
	end

	local track
	local selectedIndex = nil

	-- Special handling for JumpCancel with multiple animations
	if animationName == "JumpCancel" then
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "JUMP CANCEL: Selecting animation variant", {
				ForceVariant = forceVariantIndex,
				IsGrounded = MovementStateManager:GetIsGrounded(),
				CurrentState = MovementStateManager:GetCurrentState(),
			})
		end

		if forceVariantIndex then
			-- Use specific variant (for replication)
			local jumpCancelTracks = self.LocalAnimationTracks["JumpCancel"]
			if jumpCancelTracks and type(jumpCancelTracks) == "table" then
				track = jumpCancelTracks[forceVariantIndex]
				selectedIndex = forceVariantIndex
			end
		else
			-- Select random variant (for local play)
			track, selectedIndex = self:SelectRandomJumpCancelTrack()

			if TestMode.Logging.LogAnimationSystem then
				Log:Info("ANIMATION_CLIENT", "JUMP CANCEL: Selected random variant", {
					VariantIndex = selectedIndex,
					TrackLength = track and track.Length or "nil",
				})
			end
		end
	else
		-- Normal single animation
		track = self.LocalAnimationTracks[animationName]
	end

	if not track then
		Log:Warn("ANIMATION_CLIENT", "Airborne animation track not found", { Animation = animationName })
		return nil
	end

	if TestMode.Logging.LogAnimationSystem then
		-- Log current animation state before making changes
		Log:Info("ANIMATION_CLIENT", "PlayAirborneAnimation() called", {
			RequestedAnimation = animationName,
			VariantIndex = selectedIndex,
			CurrentState = self.CurrentStateAnimation and "playing" or "nil",
			CurrentIdle = self.CurrentIdleAnimation and "playing" or "nil",
			CurrentAirborne = self.CurrentAirborneAnimation and "playing" or "nil",
		})
	end

	-- Stop current airborne animation if different
	if
		self.CurrentAirborneAnimation
		and self.CurrentAirborneAnimation ~= track
		and self.CurrentAirborneAnimation.IsPlaying
	then
		local animData = Config.Animation.Animations[animationName]
		self.CurrentAirborneAnimation:Stop(animData.FadeOutTime)
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Stopped previous airborne animation", {
				FadeOutTime = animData.FadeOutTime,
			})
		end
	end

	-- Stop idle and state animations to prioritize airborne animation
	if self.CurrentIdleAnimation and self.CurrentIdleAnimation.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		self.CurrentIdleAnimation:Stop(animData.FadeOutTime)
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Stopped idle animation (airborne priority)", {
				FadeOutTime = animData.FadeOutTime,
			})
		end
	end

	if self.CurrentStateAnimation and self.CurrentStateAnimation.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		self.CurrentStateAnimation:Stop(animData.FadeOutTime)
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Stopped state animation (airborne priority)", {
				FadeOutTime = animData.FadeOutTime,
			})
		end
	end

	-- Play new airborne animation if not already playing
	if not track.IsPlaying then
		local animData = Config.Animation.Animations[animationName]
		track:Play(animData.FadeInTime, animData.Weight)
		self.CurrentAirborneAnimation = track
		self.LastAirborneAnimationTime = tick() -- Track start time for grace period (Edge Case Fix #1)
		self:SetCurrentAnimation(animationName) -- Track for replication

		if animationName == "JumpCancel" and TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "JUMP CANCEL: Animation started playing", {
				AnimationName = animationName,
				TrackLength = track.Length,
				FadeInTime = animData.FadeInTime,
				FadeOutTime = animData.FadeOutTime,
				IsLoop = animData.Loop,
				SelectedVariant = selectedIndex,
			})
			self:LogCurrentAnimationState()
		elseif TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Playing airborne animation", {
				Animation = animationName,
				AnimationId = animData.Id or animData.Ids,
				SelectedVariant = selectedIndex,
				FadeInTime = animData.FadeInTime,
				Weight = animData.Weight,
			})
			self:LogCurrentAnimationState()
		end

		-- If this is a one-shot animation (Jump/JumpCancel), connect to Stopped event to transition appropriately
		if not animData.Loop then
			track.Stopped:Once(function()
				if animationName == "JumpCancel" and TestMode.Logging.LogAnimationSystem then
					Log:Info("ANIMATION_CLIENT", "JUMP CANCEL: Animation stopped", {
						IsGrounded = MovementStateManager:GetIsGrounded(),
						IsSliding = MovementStateManager:IsSliding(),
						WillTransitionToFalling = not MovementStateManager:GetIsGrounded()
							and not MovementStateManager:IsSliding(),
					})
				end

				local isGrounded = MovementStateManager:GetIsGrounded()
				local isSliding = MovementStateManager:IsSliding()
				local currentState = MovementStateManager:GetCurrentState()

				-- Transition based on current state
				if not isGrounded and not isSliding then
					-- Still airborne and not sliding -> transition to falling
					if animationName == "JumpCancel" and TestMode.Logging.LogAnimationSystem then
						Log:Info("ANIMATION_CLIENT", "JUMP CANCEL: Auto-transitioning to Falling animation")
					end
					self:PlayFallingAnimation()
				elseif isGrounded and not isSliding and currentState ~= "Sliding" and currentState ~= "Standsliding" then
					-- Grounded (or never left ground) and not sliding -> transition to appropriate grounded animation
					-- This handles the edge case where jump doesn't get high enough to trigger airborne state
					-- Also check currentState to prevent race condition where state changed but isSliding() hasn't updated yet
					local isMoving = MovementStateManager:GetIsMoving()

					if TestMode.Logging.LogAnimationSystem then
						Log:Info("ANIMATION_CLIENT", animationName .. ": Animation stopped while grounded, transitioning to grounded animation", {
							CurrentState = currentState,
							IsMoving = isMoving,
						})
					end

					-- EDGE CASE FIX #2: Check if animation is already playing before triggering
					-- Prevents duplicate animation triggering when state change already played the animation
					if isMoving then
						-- Player is moving -> play state animation
						local animName = Config.Animation.StateAnimations[currentState]
						if animName then
							local targetTrack = self.LocalAnimationTracks[animName]
							if not (self.CurrentStateAnimation == targetTrack and targetTrack and targetTrack.IsPlaying) then
								self:PlayStateAnimation(animName)
							elseif TestMode.Logging.LogAnimationSystem then
								Log:Debug("ANIMATION_CLIENT", "Skipping duplicate state animation trigger", {
									Animation = animName,
								})
							end
						end
					else
						-- Player is idle -> play idle animation
						local idleAnimName = self:GetIdleAnimationForState(currentState)
						if idleAnimName then
							local targetTrack = self.LocalAnimationTracks[idleAnimName]
							if not (self.CurrentIdleAnimation == targetTrack and targetTrack and targetTrack.IsPlaying) then
								self:PlayIdleAnimation(idleAnimName)
							elseif TestMode.Logging.LogAnimationSystem then
								Log:Debug("ANIMATION_CLIENT", "Skipping duplicate idle animation trigger", {
									Animation = idleAnimName,
								})
							end
						end
					end
				elseif isSliding or currentState == "Sliding"  then
					-- If sliding, ensure slide animation is playing (in case it wasn't started yet)
					if TestMode.Logging.LogAnimationSystem then
						Log:Info("ANIMATION_CLIENT", animationName .. ": Animation stopped while sliding, ensuring slide animation plays", {
							CurrentState = currentState,
							IsSliding = isSliding,
							SlideAnimationUpdateActive = self.SlideAnimationUpdateConnection ~= nil,
						})
					end

					-- Manually trigger slide animation if slide update system isn't running
					if not self.SlideAnimationUpdateConnection then
						self:StartSlideAnimationUpdates()
					end
				end
				-- Sliding system handles animations, but we ensure it's started if needed
			end)
		end
	end

	-- Return selected index for replication (only relevant for JumpCancel)
	return selectedIndex
end

function AnimationController:StopAirborneAnimation()
	if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
		-- Use a smooth fade out for clean transition to grounded animations
		self.CurrentAirborneAnimation:Stop(0.15)
		if TestMode.Logging.LogAnimationSystem then
			Log:Info("ANIMATION_CLIENT", "Stopped airborne animation (landing)", {
				FadeOutTime = 0.15,
			})
		end
	end
	self.CurrentAirborneAnimation = nil
end

function AnimationController:PlayFallingAnimation()
	-- Only play falling if not sliding (sliding has higher priority)
	if MovementStateManager:IsSliding() then
		return
	end

	self:PlayAirborneAnimation("Falling")
end

-- Public API for triggering jump animation
function AnimationController:TriggerJumpAnimation()
	self:PlayAirborneAnimation("Jump")
end

-- Public API for triggering jump cancel animation
function AnimationController:TriggerJumpCancelAnimation()
	self:PlayAirborneAnimation("JumpCancel")
end

-- Public API for triggering wall boost animation
function AnimationController:TriggerWallBoostAnimation(cameraDirection, movementDirection)
	if not cameraDirection or not movementDirection then
		-- Fallback to forward animation
		self:PlayAirborneAnimation("WallBoostForward")
		return
	end

	-- Determine which directional animation to play
	local WallBoostDirectionDetector = require(Locations.Modules.Utils.WallBoostDirectionDetector)
	local animationName = WallBoostDirectionDetector:GetWallBoostAnimationName(cameraDirection, movementDirection)

	self:PlayAirborneAnimation(animationName)
end

-- Directional slide animation management
function AnimationController:StartSlideAnimationUpdates()
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	-- Stop any existing update connection
	self:StopSlideAnimationUpdates()

	-- Play initial slide animation (PlayStateAnimation handles stopping airborne animations)
	local initialAnimationName = SlidingSystem:GetCurrentSlideAnimationName()
	self:PlayStateAnimation(initialAnimationName)
	self.CurrentSlideAnimationName = initialAnimationName

	-- Start RunService connection to check for animation changes
	local RunService = game:GetService("RunService")
	self.SlideAnimationUpdateConnection = RunService.Heartbeat:Connect(function()
		if not MovementStateManager:IsSliding() then
			-- Stop if no longer sliding
			self:StopSlideAnimationUpdates()
			return
		end

		-- EDGE CASE FIX #3: Don't update slide animations if airborne animation is playing
		-- (Airborne animations have priority, PlayStateAnimation handles cleanup when grounded)
		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
			if TestMode.Logging.LogAnimationSystem then
				Log:Debug("ANIMATION_CLIENT", "Skipping slide animation update (airborne animation has priority)")
			end
			return
		end

		-- Check if slide animation should change
		local newAnimationName = SlidingSystem:GetCurrentSlideAnimationName()
		if newAnimationName ~= self.CurrentSlideAnimationName then
			Log:Info("ANIMATION_CLIENT", "Slide direction changed", {
				OldAnimation = self.CurrentSlideAnimationName,
				NewAnimation = newAnimationName,
			})

			-- Switch to new directional animation
			self:PlayStateAnimation(newAnimationName)
			self.CurrentSlideAnimationName = newAnimationName
		end
	end)

	Log:Info("ANIMATION_CLIENT", "Started directional slide animation updates", {
		InitialAnimation = initialAnimationName,
	})
end

function AnimationController:StopSlideAnimationUpdates()
	if self.SlideAnimationUpdateConnection then
		self.SlideAnimationUpdateConnection:Disconnect()
		self.SlideAnimationUpdateConnection = nil
		self.CurrentSlideAnimationName = nil

		Log:Debug("ANIMATION_CLIENT", "Stopped directional slide animation updates")
	end
end

-- Directional walk animation management
function AnimationController:StartWalkAnimationUpdates()
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	-- Stop any existing update connection
	self:StopWalkAnimationUpdates()

	-- Get CharacterController reference
	self.CharacterController = ServiceRegistry:GetController("CharacterController")
	if not self.CharacterController then
		Log:Warn("ANIMATION_CLIENT", "CharacterController not found for directional walking")
		return
	end

	-- Play initial walk animation
	local initialAnimationName = self:GetCurrentWalkAnimationName()
	self:PlayStateAnimation(initialAnimationName)
	self.CurrentWalkAnimationName = initialAnimationName

	-- Start RunService connection to check for animation changes
	self.WalkAnimationUpdateConnection = RunService.Heartbeat:Connect(function()
		-- Only update if walking or sprinting
		local currentState = MovementStateManager:GetCurrentState()
		if currentState ~= "Walking" and currentState ~= "Sprinting" then
			-- Stop if no longer walking/sprinting
			self:StopWalkAnimationUpdates()
			return
		end

		-- Don't update if not moving (should be playing idle animation)
		if not MovementStateManager:GetIsMoving() then
			return
		end

		-- Don't update if airborne animation is playing
		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
			return
		end

		-- Check if walk animation should change
		local newAnimationName = self:GetCurrentWalkAnimationName()
		if newAnimationName ~= self.CurrentWalkAnimationName then
			if TestMode.Logging.LogAnimationSystem then
				Log:Info("ANIMATION_CLIENT", "Walk direction changed", {
					OldAnimation = self.CurrentWalkAnimationName,
					NewAnimation = newAnimationName,
				})
			end

			-- Switch to new directional animation
			self:PlayStateAnimation(newAnimationName)
			self.CurrentWalkAnimationName = newAnimationName
		end
	end)

	if TestMode.Logging.LogAnimationSystem then
		Log:Info("ANIMATION_CLIENT", "Started directional walk animation updates", {
			InitialAnimation = initialAnimationName,
		})
	end
end

function AnimationController:StopWalkAnimationUpdates()
	if self.WalkAnimationUpdateConnection then
		self.WalkAnimationUpdateConnection:Disconnect()
		self.WalkAnimationUpdateConnection = nil
		self.CurrentWalkAnimationName = nil

		if TestMode.Logging.LogAnimationSystem then
			Log:Debug("ANIMATION_CLIENT", "Stopped directional walk animation updates")
		end
	end
end

function AnimationController:GetCurrentWalkAnimationName()
	if not self.CharacterController then
		return "WalkingForward" -- Default fallback
	end

	-- Get camera direction
	local camera = workspace.CurrentCamera
	if not camera then
		return "WalkingForward"
	end

	local cameraDirection = camera.CFrame.LookVector

	-- Get movement direction from CharacterController
	local movementDirection = self.CharacterController:CalculateMovementDirection()
	if movementDirection.Magnitude < 0.1 then
		return "WalkingForward" -- No movement, default to forward
	end

	-- Use WalkDirectionDetector to determine animation
	return WalkDirectionDetector:GetWalkAnimationName(cameraDirection, movementDirection)
end

-- Directional crouch animation management
function AnimationController:StartCrouchAnimationUpdates()
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	-- Stop any existing update connection
	self:StopCrouchAnimationUpdates()

	-- Get CharacterController reference
	self.CharacterController = ServiceRegistry:GetController("CharacterController")
	if not self.CharacterController then
		Log:Warn("ANIMATION_CLIENT", "CharacterController not found for directional crouching")
		return
	end

	-- Play initial crouch animation
	local initialAnimationName = self:GetCurrentCrouchAnimationName()
	self:PlayStateAnimation(initialAnimationName)
	self.CurrentCrouchAnimationName = initialAnimationName

	-- Start RunService connection to check for animation changes
	self.CrouchAnimationUpdateConnection = RunService.Heartbeat:Connect(function()
		-- Only update if crouching
		local currentState = MovementStateManager:GetCurrentState()
		if currentState ~= "Crouching" then
			-- Stop if no longer crouching
			self:StopCrouchAnimationUpdates()
			return
		end

		-- Don't update if not moving (should be playing idle animation)
		if not MovementStateManager:GetIsMoving() then
			return
		end

		-- Don't update if airborne animation is playing
		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
			return
		end

		-- Check if crouch animation should change
		local newAnimationName = self:GetCurrentCrouchAnimationName()
		if newAnimationName ~= self.CurrentCrouchAnimationName then
			if TestMode.Logging.LogAnimationSystem then
				Log:Info("ANIMATION_CLIENT", "Crouch direction changed", {
					OldAnimation = self.CurrentCrouchAnimationName,
					NewAnimation = newAnimationName,
				})
			end

			-- Switch to new directional animation
			self:PlayStateAnimation(newAnimationName)
			self.CurrentCrouchAnimationName = newAnimationName
		end
	end)

	if TestMode.Logging.LogAnimationSystem then
		Log:Info("ANIMATION_CLIENT", "Started directional crouch animation updates", {
			InitialAnimation = initialAnimationName,
		})
	end
end

function AnimationController:StopCrouchAnimationUpdates()
	if self.CrouchAnimationUpdateConnection then
		self.CrouchAnimationUpdateConnection:Disconnect()
		self.CrouchAnimationUpdateConnection = nil
		self.CurrentCrouchAnimationName = nil

		if TestMode.Logging.LogAnimationSystem then
			Log:Debug("ANIMATION_CLIENT", "Stopped directional crouch animation updates")
		end
	end
end

function AnimationController:GetCurrentCrouchAnimationName()
	if not self.CharacterController then
		return "CrouchWalkingForward" -- Default fallback
	end

	-- Get camera direction
	local camera = workspace.CurrentCamera
	if not camera then
		return "CrouchWalkingForward"
	end

	local cameraDirection = camera.CFrame.LookVector

	-- Get movement direction from CharacterController
	local movementDirection = self.CharacterController:CalculateMovementDirection()
	if movementDirection.Magnitude < 0.1 then
		return "CrouchWalkingForward" -- No movement, default to forward
	end

	-- Use WalkDirectionDetector to determine animation, then convert to crouch version
	local walkAnimName = WalkDirectionDetector:GetWalkAnimationName(cameraDirection, movementDirection)

	-- Convert walk animation name to crouch animation name
	-- "WalkingForward" -> "CrouchWalkingForward", etc.
	local crouchAnimName = walkAnimName:gsub("Walking", "CrouchWalking")

	return crouchAnimName
end

-- =============================================================================
-- ANIMATION ID TRACKING (For Unified State Replication)
-- =============================================================================

-- Updates the current animation name and ID (called internally when playing animations)
function AnimationController:SetCurrentAnimation(animationName)
	if not animationName then
		return
	end

	-- Handle JumpCancel variants
	local enumName = animationName
	if animationName == "JumpCancel" and self.LastJumpCancelAnimationIndex then
		enumName = "JumpCancel" .. self.LastJumpCancelAnimationIndex
	end

	-- Get animation ID from enum
	local animationId = Config.Animation.AnimationEnum[enumName]
	if not animationId then
		Log:Warn("ANIMATION_CLIENT", "Animation not found in enum", { Animation = enumName })
		return
	end

	self.CurrentAnimationName = animationName
	self.CurrentAnimationId = animationId
end

-- Returns the current animation ID for network replication
function AnimationController:GetCurrentAnimationId()
	return self.CurrentAnimationId or 1 -- Default to IdleStanding
end

-- Returns the current animation name (for debugging)
function AnimationController:GetCurrentAnimationName()
	return self.CurrentAnimationName or "IdleStanding"
end

-- =============================================================================
-- ANIMATION STATE DEBUGGING
-- =============================================================================

-- Logs the current state of all animation tracks and detects conflicts
function AnimationController:LogCurrentAnimationState()
	if not TestMode.Logging.LogAnimationSystem then
		return
	end

	-- Get names of currently playing animations
	local stateAnimName = "none"
	local idleAnimName = "none"
	local airborneAnimName = "none"

	-- Check all preloaded tracks to find which ones are playing
	for animName, track in pairs(self.LocalAnimationTracks) do
		if type(track) == "table" and #track > 0 then
			-- Handle multi-variant animations (JumpCancel)
			for variantIndex, variantTrack in ipairs(track) do
				if variantTrack.IsPlaying then
					if animName == "JumpCancel" then
						airborneAnimName = animName .. " (variant " .. variantIndex .. ")"
					end
				end
			end
		elseif track.IsPlaying then
			-- Single animation track
			local animData = Config.Animation.Animations[animName]
			if animData then
				local category = animData.Category
				if category == "State" then
					stateAnimName = animName
				elseif category == "Idle" then
					idleAnimName = animName
				elseif category == "Airborne" then
					airborneAnimName = animName
				end
			end
		end
	end

	-- Check for conflicting animations (multiple categories playing simultaneously)
	local playingCount = 0
	local conflictDetected = false

	if stateAnimName ~= "none" then
		playingCount = playingCount + 1
	end
	if idleAnimName ~= "none" then
		playingCount = playingCount + 1
	end
	if airborneAnimName ~= "none" then
		playingCount = playingCount + 1
	end

	-- Detect conflict: more than one category playing (excluding Action which plays on top)
	if playingCount > 1 then
		conflictDetected = true
	end

	-- Log current state
	if conflictDetected then
		Log:Warn("ANIMATION_CLIENT", "ANIMATION CONFLICT DETECTED!", {
			StateAnimation = stateAnimName,
			IdleAnimation = idleAnimName,
			AirborneAnimation = airborneAnimName,
			ConflictingCategories = playingCount,
			MovementState = MovementStateManager:GetCurrentState(),
			IsGrounded = MovementStateManager:GetIsGrounded(),
			IsMoving = MovementStateManager:GetIsMoving(),
		})
	else
		Log:Info("ANIMATION_CLIENT", "Current Animation State", {
			StateAnimation = stateAnimName,
			IdleAnimation = idleAnimName,
			AirborneAnimation = airborneAnimName,
			TotalPlaying = playingCount,
			MovementState = MovementStateManager:GetCurrentState(),
			IsGrounded = MovementStateManager:GetIsGrounded(),
			IsMoving = MovementStateManager:GetIsMoving(),
		})
	end
end

-- Public function to manually dump animation state (can be called from console)
function AnimationController:DumpAnimationState()
	print("=== ANIMATION STATE DUMP ===")
	print("LocalCharacter:", self.LocalCharacter and self.LocalCharacter.Name or "nil")
	print("LocalAnimator:", self.LocalAnimator and "exists" or "nil")
	print("")

	print("Current Animation Slots:")
	print("  State:", self.CurrentStateAnimation and "playing" or "nil")
	print("  Idle:", self.CurrentIdleAnimation and "playing" or "nil")
	print("  Airborne:", self.CurrentAirborneAnimation and "playing" or "nil")
	print("")

	print("All Animation Tracks:")
	local playingTracks = {}
	local stoppedTracks = {}

	for animName, track in pairs(self.LocalAnimationTracks) do
		if type(track) == "table" and #track > 0 then
			-- Multi-variant animation
			for variantIndex, variantTrack in ipairs(track) do
				local trackInfo = string.format(
					"%s (variant %d): %s (TimePosition: %.2f)",
					animName,
					variantIndex,
					variantTrack.IsPlaying and "PLAYING" or "stopped",
					variantTrack.TimePosition
				)
				if variantTrack.IsPlaying then
					table.insert(playingTracks, trackInfo)
				else
					table.insert(stoppedTracks, trackInfo)
				end
			end
		else
			-- Single animation
			local trackInfo = string.format(
				"%s: %s (TimePosition: %.2f)",
				animName,
				track.IsPlaying and "PLAYING" or "stopped",
				track.TimePosition
			)
			if track.IsPlaying then
				table.insert(playingTracks, trackInfo)
			else
				table.insert(stoppedTracks, trackInfo)
			end
		end
	end

	print("\nCurrently Playing Animations:")
	if #playingTracks == 0 then
		print("  (none)")
	else
		for _, info in ipairs(playingTracks) do
			print("  " .. info)
		end
	end

	print("\nStopped Animations:")
	if #stoppedTracks == 0 then
		print("  (none)")
	else
		for i = 1, math.min(5, #stoppedTracks) do
			print("  " .. stoppedTracks[i])
		end
		if #stoppedTracks > 5 then
			print("  ... and " .. (#stoppedTracks - 5) .. " more")
		end
	end

	print("\nMovement State:")
	print("  Current State:", MovementStateManager:GetCurrentState())
	print("  Is Grounded:", MovementStateManager:GetIsGrounded())
	print("  Is Moving:", MovementStateManager:GetIsMoving())
	print("  Is Sliding:", MovementStateManager:IsSliding())

	print("\nReplication:")
	print("  Current Animation Name:", self.CurrentAnimationName)
	print("  Current Animation ID:", self.CurrentAnimationId)
	print("  Last Replicated:", self.LastReplicatedAnimation or "nil")
	print("===========================")
end

-- =============================================================================
-- ANIMATION SPEED MANAGEMENT (Dynamic speed based on velocity)
-- =============================================================================

function AnimationController:StartAnimationSpeedUpdates()
	-- Stop existing connection if any
	if self.AnimationSpeedUpdateConnection then
		self.AnimationSpeedUpdateConnection:Disconnect()
		self.AnimationSpeedUpdateConnection = nil
	end

	-- Start updating animation speed every frame based on character velocity
	self.AnimationSpeedUpdateConnection = RunService.Heartbeat:Connect(function()
		self:UpdateAnimationSpeed()
	end)

	Log:Debug("ANIMATION_CLIENT", "Started animation speed updates")
end

function AnimationController:StopAnimationSpeedUpdates()
	if self.AnimationSpeedUpdateConnection then
		self.AnimationSpeedUpdateConnection:Disconnect()
		self.AnimationSpeedUpdateConnection = nil
		Log:Debug("ANIMATION_CLIENT", "Stopped animation speed updates")
	end
end

function AnimationController:UpdateAnimationSpeed()
	-- Update local character animation speed
	if self.LocalCharacter then
		local root = self.LocalCharacter:FindFirstChild("Root")
		if root and root:IsA("BasePart") then
			local velocity = root.AssemblyLinearVelocity
			self:SetAnimationSpeedFromVelocity(velocity, self.CurrentStateAnimation, self.CurrentIdleAnimation)
		end
	end

	-- Update other players' animation speeds
	for character, animator in pairs(self.OtherCharacterAnimators) do
		if character and character.Parent then
			local root = character:FindFirstChild("Root")
			if root and root:IsA("BasePart") then
				local velocity = root.AssemblyLinearVelocity
				local currentAnims = self.OtherCharacterCurrentAnimations[character]
				if currentAnims then
					-- Update both state and idle animations for other players
					self:SetAnimationSpeedFromVelocity(velocity, currentAnims.State, currentAnims.Idle)
				end
			end
		end
	end
end

function AnimationController:SetAnimationSpeedFromVelocity(velocity, stateTrack, idleTrack)
	if not velocity then
		return
	end

	-- Calculate horizontal velocity magnitude (ignore Y component)
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontalVelocity.Magnitude

	-- Get configured speeds
	local walkSpeed = Config.Gameplay.Character.WalkSpeed
	local crouchSpeed = Config.Gameplay.Character.CrouchSpeed

	-- Determine which base speed to use based on current animation
	-- Check if we're playing a crouch animation
	local isCrouchAnimation = false
	if self.CurrentCrouchAnimationName then
		-- Crouching with directional animation
		isCrouchAnimation = true
	elseif MovementStateManager and MovementStateManager:GetCurrentState() == "Crouching" then
		-- Crouching (fallback check)
		isCrouchAnimation = true
	end

	local baseSpeed = isCrouchAnimation and crouchSpeed or walkSpeed

	-- Get max animation speed multipliers from config
	local maxWalkAnimSpeed = Config.Animation.Performance.MaxWalkAnimationSpeed or 2.0
	local maxCrouchAnimSpeed = Config.Animation.Performance.MaxCrouchAnimationSpeed or 1.5

	-- Calculate animation speed multiplier
	-- When standing still (speed = 0): multiplier = 0
	-- For walking: When at walk speed (speed = 15): multiplier = 1.0, at sprint speed (speed = 25): multiplier = 1.67
	-- For crouching: When at crouch speed (speed = 10): multiplier = 1.0
	local animationSpeed = 1.0
	if speed > 0.1 then -- Only adjust speed if actually moving (prevent division issues)
		animationSpeed = speed / baseSpeed
	else
		animationSpeed = 0 -- Pause animation when standing still
	end

	-- Clamp to reasonable range based on animation type
	local maxSpeed = isCrouchAnimation and maxCrouchAnimSpeed or maxWalkAnimSpeed
	animationSpeed = math.clamp(animationSpeed, 0, maxSpeed)

	-- Apply to state animation (Walking, CrouchWalking, etc.)
	if stateTrack and stateTrack.IsPlaying then
		stateTrack:AdjustSpeed(animationSpeed)
	end

	-- Apply to idle animation (shouldn't be affected, but included for completeness)
	if idleTrack and idleTrack.IsPlaying then
		-- Idle animations always play at normal speed
		idleTrack:AdjustSpeed(1.0)
	end
end

return AnimationController
