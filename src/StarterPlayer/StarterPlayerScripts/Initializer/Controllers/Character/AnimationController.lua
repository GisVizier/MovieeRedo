local AnimationController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local SlidingSystem = require(Locations.Game:WaitForChild("Movement"):WaitForChild("SlidingSystem"))
local WalkDirectionDetector = require(Locations.Shared.Util:WaitForChild("WalkDirectionDetector"))
local WallBoostDirectionDetector = require(Locations.Shared.Util:WaitForChild("WallBoostDirectionDetector"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local AnimationIds = require(Locations.Shared:WaitForChild("Types"):WaitForChild("AnimationIds"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local TestMode = require(Locations.Shared.Util:WaitForChild("TestMode"))
local Net = require(Locations.Shared.Net.Net)

local DEBUG_THROTTLE_SECONDS = 0.2
local lastDebugTimes = {}

local function getJumpCancelAge()
	if SlidingSystem and SlidingSystem.LastJumpCancelTime and SlidingSystem.LastJumpCancelTime > 0 then
		return tick() - SlidingSystem.LastJumpCancelTime
	end
	return nil
end

local function debugLog(hypothesisId, location, message, data)
	local now = tick()
	local key = string.format("%s|%s|%s", tostring(hypothesisId), tostring(location), tostring(message))
	local lastTime = lastDebugTimes[key]
	if lastTime and (now - lastTime) < DEBUG_THROTTLE_SECONDS then
		return
	end
	lastDebugTimes[key] = now

	local ok, payload = pcall(function()
		return {
			sessionId = "debug-session",
			runId = AnimationController.DebugRunId or "run1",
			hypothesisId = hypothesisId,
			location = location,
			message = message,
			data = data,
			timestamp = DateTime.now().UnixTimestampMillis,
		}
	end)
	if not ok then
		return
	end

	Net:FireServer("DebugLog", payload)
end

local function isJumpCancelProtected(self)
	local jumpCancelGrace = Config.Gameplay.Sliding.JumpCancel.AnimationGraceTime or 0
	local jumpCancelAge = tick() - (self.LastJumpCancelAnimationTime or 0)
	return self.CurrentAirborneAnimation
		and self.CurrentAirborneAnimation.IsPlaying
		and self:GetCurrentAnimationName() == "JumpCancel"
		and jumpCancelGrace > 0
		and jumpCancelAge >= 0
		and jumpCancelAge < jumpCancelGrace
end

AnimationController.Initialized = false
AnimationController.LocalCharacter = nil
AnimationController.LocalAnimator = nil
AnimationController.LocalAnimationTracks = {}
AnimationController.AnimationInstances = {}
AnimationController.AnimationSettings = {}
AnimationController.JumpCancelVariants = {}

AnimationController.CurrentStateAnimation = nil
AnimationController.CurrentIdleAnimation = nil
AnimationController.CurrentAirborneAnimation = nil
AnimationController.CurrentActionAnimation = nil
AnimationController.CurrentSlideAnimationName = nil
AnimationController.CurrentWalkAnimationName = nil
AnimationController.CurrentCrouchAnimationName = nil
AnimationController.CurrentAnimationName = "IdleStanding"
AnimationController.CurrentAnimationId = 1
AnimationController.LastAirborneAnimationTime = 0
AnimationController.LastJumpCancelAnimationIndex = nil
AnimationController.LastJumpCancelAnimationTime = 0

AnimationController.SlideAnimationUpdateConnection = nil
AnimationController.WalkAnimationUpdateConnection = nil
AnimationController.CrouchAnimationUpdateConnection = nil
AnimationController.AnimationSpeedUpdateConnection = nil

AnimationController.OtherCharacterAnimators = {}
AnimationController.OtherCharacterTracks = {}
AnimationController.OtherCharacterCurrentAnimations = {}

local STATE_ANIMATIONS = {
	Walking = "WalkingForward",
	Sprinting = "WalkingForward",
	Crouching = "CrouchWalkingForward",
	IdleStanding = "IdleStanding",
	IdleCrouching = "IdleCrouching",
}

local function getAnimationFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	local animations = assets:FindFirstChild("Animations")
	local character = animations and animations:FindFirstChild("Character")
	local base = character and character:FindFirstChild("Base")

	return base
end

local function getDefaultSettings(name)
	local settings = {
		FadeInTime = 0.2,
		FadeOutTime = 0.2,
		Weight = 1.0,
		Loop = true,
		Priority = Enum.AnimationPriority.Core,
		Speed = 1.0,
	}

	if name == "Jump" or name == "JumpCancel" or name:match("^WallBoost") then
		settings.FadeInTime = 0.05
		settings.FadeOutTime = 0.15
		settings.Loop = false
		if name == "JumpCancel" then
			settings.Priority = Enum.AnimationPriority.Action
		end
	end

	if name == "Falling" then
		settings.FadeInTime = 0.2
		settings.FadeOutTime = 0.15
		settings.Loop = true
	end

	if name == "Land" or name == "Landing" then
		settings.FadeInTime = 0.05
		settings.FadeOutTime = 0.15
		settings.Loop = false
		settings.Priority = Enum.AnimationPriority.Action
	end

	if name:match("^Sliding") then
		settings.FadeInTime = 0.1
		settings.FadeOutTime = 0.15
		settings.Priority = Enum.AnimationPriority.Movement
		settings.Loop = true
	end

	if name:match("^CrouchWalking") then
		settings.FadeInTime = 0.2
		settings.FadeOutTime = 0.2
	end

	return settings
end

local function applyAttributes(animation, settings)
	if not animation then
		return settings
	end

	local fadeIn = animation:GetAttribute("FadeInTime")
	if type(fadeIn) == "number" then
		settings.FadeInTime = fadeIn
	end

	local fadeOut = animation:GetAttribute("FadeOutTime")
	if type(fadeOut) == "number" then
		settings.FadeOutTime = fadeOut
	end

	local weight = animation:GetAttribute("Weight")
	if type(weight) == "number" then
		settings.Weight = weight
	end

	local speed = animation:GetAttribute("Speed")
	if type(speed) == "number" then
		settings.Speed = speed
	end

	local loop = animation:GetAttribute("Loop")
	if type(loop) == "boolean" then
		settings.Loop = loop
	end

	local priority = animation:GetAttribute("Priority")
	if type(priority) == "string" then
		local enumValue = Enum.AnimationPriority[priority]
		if enumValue then
			settings.Priority = enumValue
		end
	end

	return settings
end

local function getAnimationCategory(animationName)
	if animationName == "IdleStanding" or animationName == "IdleCrouching" then
		return "Idle"
	end

	if animationName == "Jump" or animationName == "JumpCancel" or animationName == "Falling" then
		return "Airborne"
	end

	if animationName == "Land" or animationName == "Landing" then
		return "Action"
	end

	if animationName:match("^WallBoost") then
		return "Airborne"
	end

	return "State"
end

function AnimationController:Init(registry, net)
	self._registry = registry
	self._net = net

	ServiceRegistry:RegisterController("AnimationController", self)

	MovementStateManager:ConnectToStateChange(function(previousState, newState, data)
		self:OnMovementStateChanged(previousState, newState, data)
	end)

	MovementStateManager:ConnectToMovementChange(function(wasMoving, isMoving)
		self:OnMovementChanged(wasMoving, isMoving)
	end)

	MovementStateManager:ConnectToGroundedChange(function(wasGrounded, isGrounded)
		self:OnGroundedChanged(wasGrounded, isGrounded)
	end)

	self.Initialized = true
end

function AnimationController:Start()
	-- No-op
end

function AnimationController:_loadAnimationInstances()
	self.AnimationInstances = {}
	self.JumpCancelVariants = {}

	local baseFolder = getAnimationFolder()
	if not baseFolder then
		LogService:Warn("ANIMATION", "Animation Base folder missing")
		return false
	end

	for _, child in ipairs(baseFolder:GetChildren()) do
		if child:IsA("Animation") then
			local name = child.Name
			local index = name:match("^JumpCancel(%d+)$")
			if index then
				self.JumpCancelVariants[tonumber(index)] = child
			else
				self.AnimationInstances[name] = child
			end
		end
	end

	local variants = {}
	for index, anim in pairs(self.JumpCancelVariants) do
		variants[index] = anim
	end

	self.JumpCancelVariants = {}
	for i = 1, #variants do
		if variants[i] then
			table.insert(self.JumpCancelVariants, variants[i])
		end
	end

	if #self.JumpCancelVariants == 0 and self.AnimationInstances.JumpCancel then
		self.JumpCancelVariants = { self.AnimationInstances.JumpCancel }
	end

	return true
end

function AnimationController:_loadTrack(animator, animation, name)
	if not animation.AnimationId or animation.AnimationId == "" then
		if TestMode.Logging.LogAnimationSystem then
			LogService:Warn("ANIMATION", "Animation missing AnimationId", { Animation = name })
		end
		return nil
	end

	local settings = self.AnimationSettings[name]
	if not settings then
		settings = applyAttributes(animation, getDefaultSettings(name))
		self.AnimationSettings[name] = settings
	end

	local track = animator:LoadAnimation(animation)
	track.Priority = settings.Priority
	track.Looped = settings.Loop
	if name == "JumpCancel" then
		track.Looped = false
	end

	return track
end

function AnimationController:PreloadAnimations()
	if not self.LocalAnimator then
		return
	end

	if not self:_loadAnimationInstances() then
		return
	end

	self.LocalAnimationTracks = {}
	self.AnimationSettings = {}

	for name, animation in pairs(self.AnimationInstances) do
		local track = self:_loadTrack(self.LocalAnimator, animation, name)
		if track then
			self.LocalAnimationTracks[name] = track
		end
	end

	if #self.JumpCancelVariants > 0 then
		self.LocalAnimationTracks.JumpCancel = {}
		for _, animation in ipairs(self.JumpCancelVariants) do
			local track = self:_loadTrack(self.LocalAnimator, animation, "JumpCancel")
			if track then
				table.insert(self.LocalAnimationTracks.JumpCancel, track)
			end
		end
	end
end

function AnimationController:OnLocalCharacterReady(character)
	self.LocalCharacter = character

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
		LogService:Warn("ANIMATION", "Rig not found for local character")
		return
	end

	local humanoid = rig:WaitForChild("Humanoid", 10)
	if not humanoid then
		LogService:Warn("ANIMATION", "Humanoid not found in rig")
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	self.LocalAnimator = animator
	self:PreloadAnimations()
	self:PlayIdleAnimation("IdleStanding")
	self:StartAnimationSpeedUpdates()
end

function AnimationController:OnLocalCharacterRemoving()
	self:StopAllLocalAnimations()
	self:StopSlideAnimationUpdates()
	self:StopWalkAnimationUpdates()
	self:StopCrouchAnimationUpdates()
	self:StopAnimationSpeedUpdates()

	self.LocalCharacter = nil
	self.LocalAnimator = nil
	self.LocalAnimationTracks = {}
	self.CurrentStateAnimation = nil
	self.CurrentIdleAnimation = nil
	self.CurrentAirborneAnimation = nil
end

function AnimationController:OnOtherCharacterSpawned(character)
	if not character or not character.Parent then
		return
	end

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
		return
	end

	local humanoid = rig:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	self.OtherCharacterAnimators[character] = animator
	self.OtherCharacterTracks[character] = {}
	self.OtherCharacterCurrentAnimations[character] = {}
end

function AnimationController:OnOtherCharacterRemoving(character)
	local tracks = self.OtherCharacterTracks[character]
	if tracks then
		for _, track in pairs(tracks) do
			if typeof(track) == "Instance" and track.IsPlaying then
				track:Stop()
			elseif type(track) == "table" then
				for _, variant in ipairs(track) do
					if variant.IsPlaying then
						variant:Stop()
					end
				end
			end
		end
	end

	self.OtherCharacterAnimators[character] = nil
	self.OtherCharacterTracks[character] = nil
	self.OtherCharacterCurrentAnimations[character] = nil
end

function AnimationController:OnMovementStateChanged(previousState, newState, _data)
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	local isSliding = (newState == "Sliding")
	local isMoving = MovementStateManager:GetIsMoving()
	local isGrounded = MovementStateManager:GetIsGrounded()
	local isJumpCancelProtected = isJumpCancelProtected(self)

	if not isGrounded and not isSliding then
		if isJumpCancelProtected(self) then
			return
		end
		-- #region agent log
		debugLog("H2", "AnimationController.lua:OnMovementStateChanged", "falling branch", {
			previousState = previousState,
			newState = newState,
			isSliding = isSliding,
			isMoving = isMoving,
			isGrounded = isGrounded,
			currentAirborne = self.CurrentAirborneAnimation and self:GetCurrentAnimationName() or nil,
		})
		-- #endregion
		if not self.CurrentAirborneAnimation or not self.CurrentAirborneAnimation.IsPlaying then
			self:PlayFallingAnimation()
		end
		return
	end

	if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying and not isSliding then
		self:StopSlideAnimationUpdates()
		return
	end

	local timeSinceAirborneAnim = tick() - self.LastAirborneAnimationTime
	if timeSinceAirborneAnim < 0.2 and isGrounded and not isSliding then
		return
	end

	if previousState == "Sliding" and not isSliding then
		if
			self.CurrentAirborneAnimation
			and self.CurrentAirborneAnimation.IsPlaying
			and isGrounded
			and not isJumpCancelProtected
		then
			self:StopAirborneAnimation()
		end
	end

	if isJumpCancelProtected and not isSliding then
		return
	end

	if isSliding then
		if self.CurrentIdleAnimation and self.CurrentIdleAnimation.IsPlaying then
			self.CurrentIdleAnimation:Stop(0.1)
		end
		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
			self:StopAirborneAnimation()
		end
		self:StartSlideAnimationUpdates()
		return
	end

	self:StopSlideAnimationUpdates()

	local animationName = STATE_ANIMATIONS[newState]
	if not animationName then
		return
	end

	if isMoving then
		if newState == "Walking" or newState == "Sprinting" then
			self:StartWalkAnimationUpdates()
		elseif newState == "Crouching" then
			self:StartCrouchAnimationUpdates()
		else
			self:PlayStateAnimation(animationName)
		end
	else
		self:StopWalkAnimationUpdates()
		self:StopCrouchAnimationUpdates()

		local idleAnimationName = self:GetIdleAnimationForState(newState)
		if idleAnimationName then
			self:PlayIdleAnimation(idleAnimationName)
		end
	end
end

function AnimationController:GetIdleAnimationForState(state)
	if state == "Walking" or state == "Sprinting" then
		return "IdleStanding"
	elseif state == "Crouching" then
		return "IdleCrouching"
	end

	return nil
end

function AnimationController:OnMovementChanged(_wasMoving, isMoving)
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	local currentState = MovementStateManager:GetCurrentState()
	local isGrounded = MovementStateManager:GetIsGrounded()
	local isJumpCancelProtected = isJumpCancelProtected(self)

	local isSliding = (currentState == "Sliding")
	if isSliding then
		return
	end

	if isJumpCancelProtected then
		return
	end

	if not isGrounded then
		return
	end

	if isMoving then
		if currentState == "Walking" or currentState == "Sprinting" then
			self:StartWalkAnimationUpdates()
		elseif currentState == "Crouching" then
			self:StartCrouchAnimationUpdates()
		else
			local animationName = STATE_ANIMATIONS[currentState]
			if animationName then
				self:PlayStateAnimation(animationName)
			end
		end
	else
		self:StopWalkAnimationUpdates()
		self:StopCrouchAnimationUpdates()

		local idleAnimationName = self:GetIdleAnimationForState(currentState)
		if idleAnimationName then
			self:PlayIdleAnimation(idleAnimationName)
		end
	end
end

function AnimationController:OnGroundedChanged(wasGrounded, isGrounded)
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	local currentState = MovementStateManager:GetCurrentState()
	local isSliding = (currentState == "Sliding")
	local isJumpCancelProtected = isJumpCancelProtected(self)
	-- #region agent log
	debugLog("H3", "AnimationController.lua:OnGroundedChanged", "grounded transition", {
		wasGrounded = wasGrounded,
		isGrounded = isGrounded,
		currentState = currentState,
		isSliding = isSliding,
		currentAirborne = self.CurrentAirborneAnimation and self:GetCurrentAnimationName() or nil,
		jumpCancelAge = getJumpCancelAge(),
	})
	-- #endregion

	if isGrounded then
		if isJumpCancelProtected then
			return
		end
		self:StopAirborneAnimation()

		if not wasGrounded and not isSliding then
			local landName = self.LocalAnimationTracks.Land and "Land"
				or (self.LocalAnimationTracks.Landing and "Landing")
			if landName then
				self:PlayActionAnimation(landName)
			end
		end

		local isMoving = MovementStateManager:GetIsMoving()
		if isSliding or isMoving then
			local animationName = STATE_ANIMATIONS[currentState]
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
		if not isSliding then
			local hasAirborneAnimation = self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying
			if not hasAirborneAnimation then
				self:PlayFallingAnimation()
			end
		end
	end
end

function AnimationController:IsCharacterGrounded()
	if MovementStateManager and MovementStateManager.GetIsGrounded then
		local grounded = MovementStateManager:GetIsGrounded()
		if grounded ~= nil then
			return grounded
		end
	end

	if self.LocalCharacter then
		local humanoid = self.LocalCharacter:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid.FloorMaterial ~= Enum.Material.Air
		end
	end

	return false
end

function AnimationController:PlayStateAnimation(animationName)
	if not self.LocalAnimator then
		return
	end

	local track = self.LocalAnimationTracks[animationName]
	if type(track) == "table" then
		track = track[1]
	end
	if not track then
		return
	end

	local settings = self.AnimationSettings[animationName] or getDefaultSettings(animationName)

	if self.CurrentStateAnimation and self.CurrentStateAnimation ~= track and self.CurrentStateAnimation.IsPlaying then
		self.CurrentStateAnimation:Stop(settings.FadeOutTime)
	end

	if self.CurrentIdleAnimation and self.CurrentIdleAnimation.IsPlaying then
		self.CurrentIdleAnimation:Stop(settings.FadeOutTime)
	end

	if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
		self.CurrentAirborneAnimation:Stop(settings.FadeOutTime)
		self.CurrentAirborneAnimation = nil
	end

	if not track.IsPlaying then
		track:Play(settings.FadeInTime, settings.Weight, settings.Speed)
		self.CurrentStateAnimation = track
		self:SetCurrentAnimation(animationName)
	end
end

function AnimationController:PlayIdleAnimation(animationName)
	if not self.LocalAnimator then
		return
	end

	local track = self.LocalAnimationTracks[animationName]
	if type(track) == "table" then
		track = track[1]
	end
	if not track then
		return
	end

	local settings = self.AnimationSettings[animationName] or getDefaultSettings(animationName)

	if self.CurrentIdleAnimation and self.CurrentIdleAnimation ~= track and self.CurrentIdleAnimation.IsPlaying then
		self.CurrentIdleAnimation:Stop(settings.FadeOutTime)
	end

	if self.CurrentStateAnimation and self.CurrentStateAnimation.IsPlaying then
		self.CurrentStateAnimation:Stop(settings.FadeOutTime)
	end

	if not track.IsPlaying then
		track:Play(settings.FadeInTime, settings.Weight, settings.Speed)
		self.CurrentIdleAnimation = track
		self:SetCurrentAnimation(animationName)
	end
end

function AnimationController:PlayActionAnimation(animationName)
	if not self.LocalAnimator then
		return
	end

	local track = self.LocalAnimationTracks[animationName]
	if type(track) == "table" then
		track = track[1]
	end
	if not track then
		return
	end

	local settings = self.AnimationSettings[animationName] or getDefaultSettings(animationName)

	if self.CurrentActionAnimation and self.CurrentActionAnimation ~= track and self.CurrentActionAnimation.IsPlaying then
		self.CurrentActionAnimation:Stop(settings.FadeOutTime)
	end

	if track.IsPlaying then
		track:Stop(0)
	end
	-- Enforce loop behavior from settings; some assets may have Loop=true set.
	track.Looped = settings.Loop
	track:Play(settings.FadeInTime, settings.Weight, settings.Speed)
	self.CurrentActionAnimation = track
	self:SetCurrentAnimation(animationName)
end

function AnimationController:StopAllLocalAnimations()
	for _, track in pairs(self.LocalAnimationTracks) do
		if typeof(track) == "Instance" then
			if track.IsPlaying then
				track:Stop()
			end
		elseif type(track) == "table" then
			for _, variant in ipairs(track) do
				if variant.IsPlaying then
					variant:Stop()
				end
			end
		end
	end

	self.CurrentStateAnimation = nil
	self.CurrentIdleAnimation = nil
	self.CurrentAirborneAnimation = nil
	self.CurrentActionAnimation = nil
end

function AnimationController:SelectRandomJumpCancelTrack(forceVariantIndex)
	local jumpCancelTracks = self.LocalAnimationTracks.JumpCancel
	if not jumpCancelTracks or type(jumpCancelTracks) ~= "table" then
		return nil, nil
	end

	local numTracks = #jumpCancelTracks
	if numTracks == 0 then
		return nil, nil
	end

	if forceVariantIndex and jumpCancelTracks[forceVariantIndex] then
		self.LastJumpCancelAnimationIndex = forceVariantIndex
		return jumpCancelTracks[forceVariantIndex], forceVariantIndex
	end

	if numTracks == 1 then
		self.LastJumpCancelAnimationIndex = 1
		return jumpCancelTracks[1], 1
	end

	local randomIndex
	repeat
		randomIndex = math.random(1, numTracks)
	until randomIndex ~= self.LastJumpCancelAnimationIndex

	self.LastJumpCancelAnimationIndex = randomIndex

	return jumpCancelTracks[randomIndex], randomIndex
end

function AnimationController:PlayAirborneAnimation(animationName, forceVariantIndex)
	if not self.LocalAnimator then
		return
	end

	local track = nil
	if animationName == "JumpCancel" then
		track = self:SelectRandomJumpCancelTrack(forceVariantIndex)
		if type(track) == "table" then
			track = track[1]
		end
	else
		track = self.LocalAnimationTracks[animationName]
		if type(track) == "table" then
			track = track[1]
		end
	end

	if not track then
		if animationName == "JumpCancel" then
			warn("[ANIMATION] JumpCancel track missing - cannot play")
		end
		return
	end

	if animationName == "JumpCancel" then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		if track.IsPlaying then
			track:Stop(0)
		end
	end

	local settings = self.AnimationSettings[animationName] or getDefaultSettings(animationName)

	if
		self.CurrentAirborneAnimation
		and self.CurrentAirborneAnimation ~= track
		and self.CurrentAirborneAnimation.IsPlaying
	then
		self.CurrentAirborneAnimation:Stop(settings.FadeOutTime)
	end

	if self.CurrentStateAnimation and self.CurrentStateAnimation.IsPlaying then
		self.CurrentStateAnimation:Stop(settings.FadeOutTime)
	end

	if self.CurrentIdleAnimation and self.CurrentIdleAnimation.IsPlaying then
		self.CurrentIdleAnimation:Stop(settings.FadeOutTime)
	end

	track:Play(settings.FadeInTime, settings.Weight, settings.Speed)
	self.CurrentAirborneAnimation = track
	self.LastAirborneAnimationTime = tick()
	self:SetCurrentAnimation(animationName)
	-- #region agent log
	debugLog("H1", "AnimationController.lua:PlayAirborneAnimation", "airborne play", {
		animationName = animationName,
		looped = track.Looped,
		isGrounded = MovementStateManager:GetIsGrounded(),
		currentState = MovementStateManager:GetCurrentState(),
		jumpCancelAge = getJumpCancelAge(),
	})
	-- #endregion
	if animationName == "JumpCancel" then
	end
end

function AnimationController:StopAirborneAnimation()
	if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
		local name = self:GetCurrentAnimationName()
		local settings = self.AnimationSettings[name] or getDefaultSettings(name)
		-- #region agent log
		debugLog("H1", "AnimationController.lua:StopAirborneAnimation", "airborne stop", {
			animationName = name,
			looped = self.CurrentAirborneAnimation.Looped,
			isGrounded = MovementStateManager:GetIsGrounded(),
			currentState = MovementStateManager:GetCurrentState(),
		jumpCancelAge = getJumpCancelAge(),
		})
		-- #endregion
		self.CurrentAirborneAnimation:Stop(settings.FadeOutTime)
	end
	self.CurrentAirborneAnimation = nil
end

function AnimationController:PlayFallingAnimation()
	if isJumpCancelProtected(self) then
		return
	end
	-- #region agent log
	debugLog("H2", "AnimationController.lua:PlayFallingAnimation", "falling play", {
		isGrounded = MovementStateManager:GetIsGrounded(),
		currentState = MovementStateManager:GetCurrentState(),
		currentAirborne = self.CurrentAirborneAnimation and self:GetCurrentAnimationName() or nil,
		jumpCancelAge = getJumpCancelAge(),
	})
	-- #endregion
	self:PlayAirborneAnimation("Falling")
end

function AnimationController:TriggerJumpAnimation()
	-- #region agent log
	debugLog("H4", "AnimationController.lua:TriggerJumpAnimation", "jump trigger", {
		isGrounded = MovementStateManager:GetIsGrounded(),
		currentState = MovementStateManager:GetCurrentState(),
	})
	-- #endregion
	self:PlayAirborneAnimation("Jump")
end

function AnimationController:TriggerJumpCancelAnimation()
	-- #region agent log
	debugLog("H4", "AnimationController.lua:TriggerJumpCancelAnimation", "jump cancel trigger", {
		isGrounded = MovementStateManager:GetIsGrounded(),
		currentState = MovementStateManager:GetCurrentState(),
		jumpCancelAge = getJumpCancelAge(),
	})
	-- #endregion
	self.LastJumpCancelAnimationTime = tick()
	self:PlayAirborneAnimation("JumpCancel")
end

function AnimationController:TriggerWallBoostAnimation(cameraDirection, movementDirection)
	local animationName = "WallBoostForward"
	if cameraDirection and movementDirection then
		animationName = WallBoostDirectionDetector:GetWallBoostAnimationName(cameraDirection, movementDirection)
	end
	-- #region agent log
	debugLog("H4", "AnimationController.lua:TriggerWallBoostAnimation", "wall boost trigger", {
		animationName = animationName,
		isGrounded = MovementStateManager:GetIsGrounded(),
		currentState = MovementStateManager:GetCurrentState(),
	})
	-- #endregion
	self:PlayAirborneAnimation(animationName)
end

function AnimationController:StartSlideAnimationUpdates()
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	self:StopSlideAnimationUpdates()

	local initialAnimationName = SlidingSystem:GetCurrentSlideAnimationName()
	self:PlayStateAnimation(initialAnimationName)
	self.CurrentSlideAnimationName = initialAnimationName

	self.SlideAnimationUpdateConnection = RunService.Heartbeat:Connect(function()
		local currentState = MovementStateManager:GetCurrentState()
		if currentState ~= "Sliding" then
			self:StopSlideAnimationUpdates()
			return
		end

		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
			return
		end

		local newAnimationName = SlidingSystem:GetCurrentSlideAnimationName()
		if newAnimationName ~= self.CurrentSlideAnimationName then
			self:PlayStateAnimation(newAnimationName)
			self.CurrentSlideAnimationName = newAnimationName
		end
	end)
end

function AnimationController:StopSlideAnimationUpdates()
	if self.SlideAnimationUpdateConnection then
		self.SlideAnimationUpdateConnection:Disconnect()
		self.SlideAnimationUpdateConnection = nil
		self.CurrentSlideAnimationName = nil
	end
end

function AnimationController:StartWalkAnimationUpdates()
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	self:StopWalkAnimationUpdates()

	self.CharacterController = ServiceRegistry:GetController("CharacterController")
	if not self.CharacterController then
		return
	end

	local initialAnimationName = self:GetCurrentWalkAnimationName()
	self:PlayStateAnimation(initialAnimationName)
	self.CurrentWalkAnimationName = initialAnimationName

	self.WalkAnimationUpdateConnection = RunService.Heartbeat:Connect(function()
		local currentState = MovementStateManager:GetCurrentState()
		if currentState ~= "Walking" and currentState ~= "Sprinting" then
			self:StopWalkAnimationUpdates()
			return
		end

		if not MovementStateManager:GetIsMoving() then
			return
		end

		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
			return
		end

		local newAnimationName = self:GetCurrentWalkAnimationName()
		if newAnimationName ~= self.CurrentWalkAnimationName then
			self:PlayStateAnimation(newAnimationName)
			self.CurrentWalkAnimationName = newAnimationName
		end
	end)
end

function AnimationController:StopWalkAnimationUpdates()
	if self.WalkAnimationUpdateConnection then
		self.WalkAnimationUpdateConnection:Disconnect()
		self.WalkAnimationUpdateConnection = nil
		self.CurrentWalkAnimationName = nil
	end
end

function AnimationController:GetCurrentWalkAnimationName()
	if not self.CharacterController then
		return "WalkingForward"
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return "WalkingForward"
	end

	local cameraController = ServiceRegistry:GetController("CameraController")
	if cameraController and cameraController.CurrentMode == "Orbit" then
		return "WalkingForward"
	end

	-- Check if we're in Orbit mode (character faces movement, not camera)
	if cameraController then
		local shouldRotateToCamera = true
		if cameraController.ShouldRotateCharacterToCamera then
			shouldRotateToCamera = cameraController:ShouldRotateCharacterToCamera()
		end

		-- In Orbit mode, character rotation is driven by movement direction (not camera).
		-- Use character facing as the reference so directional animations are based on
		-- movement relative to character rotation (not raw input or camera yaw).
		if not shouldRotateToCamera then
			return "WalkingForward"
		end
	end

	local cameraDirection = camera.CFrame.LookVector
	local movementDirection = self.CharacterController:CalculateMovementDirection()
	if movementDirection.Magnitude < 0.1 then
		return "WalkingForward"
	end

	return WalkDirectionDetector:GetWalkAnimationName(cameraDirection, movementDirection)
end

function AnimationController:StartCrouchAnimationUpdates()
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	self:StopCrouchAnimationUpdates()

	self.CharacterController = ServiceRegistry:GetController("CharacterController")
	if not self.CharacterController then
		return
	end

	local initialAnimationName = self:GetCurrentCrouchAnimationName()
	self:PlayStateAnimation(initialAnimationName)
	self.CurrentCrouchAnimationName = initialAnimationName

	self.CrouchAnimationUpdateConnection = RunService.Heartbeat:Connect(function()
		local currentState = MovementStateManager:GetCurrentState()
		if currentState ~= "Crouching" then
			self:StopCrouchAnimationUpdates()
			return
		end

		if not MovementStateManager:GetIsMoving() then
			return
		end

		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
			return
		end

		local newAnimationName = self:GetCurrentCrouchAnimationName()
		if newAnimationName ~= self.CurrentCrouchAnimationName then
			self:PlayStateAnimation(newAnimationName)
			self.CurrentCrouchAnimationName = newAnimationName
		end
	end)
end

function AnimationController:StopCrouchAnimationUpdates()
	if self.CrouchAnimationUpdateConnection then
		self.CrouchAnimationUpdateConnection:Disconnect()
		self.CrouchAnimationUpdateConnection = nil
		self.CurrentCrouchAnimationName = nil
	end
end

function AnimationController:GetCurrentCrouchAnimationName()
	if not self.CharacterController then
		return "CrouchWalkingForward"
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return "CrouchWalkingForward"
	end

	local cameraController = ServiceRegistry:GetController("CameraController")
	if cameraController and cameraController.CurrentMode == "Orbit" then
		return "CrouchWalkingForward"
	end

	-- Check if we're in Orbit mode (character faces movement, not camera)
	if cameraController then
		local shouldRotateToCamera = true
		if cameraController.ShouldRotateCharacterToCamera then
			shouldRotateToCamera = cameraController:ShouldRotateCharacterToCamera()
		end

		-- In Orbit mode, use character facing as reference for directional crouch animations.
		if not shouldRotateToCamera then
			return "CrouchWalkingForward"
		end
	end

	local cameraDirection = camera.CFrame.LookVector
	local movementDirection = self.CharacterController:CalculateMovementDirection()
	if movementDirection.Magnitude < 0.1 then
		return "CrouchWalkingForward"
	end

	local walkAnimName = WalkDirectionDetector:GetWalkAnimationName(cameraDirection, movementDirection)
	local crouchAnimName = walkAnimName:gsub("Walking", "CrouchWalking")

	return crouchAnimName
end

function AnimationController:SetCurrentAnimation(animationName)
	if not animationName then
		return
	end

	local enumName = animationName
	if animationName == "JumpCancel" and self.LastJumpCancelAnimationIndex then
		enumName = "JumpCancel" .. tostring(self.LastJumpCancelAnimationIndex)
	end

	local animationId = AnimationIds:GetId(enumName)
	if not animationId then
		return
	end

	self.CurrentAnimationName = animationName
	self.CurrentAnimationId = animationId
end

function AnimationController:GetCurrentAnimationId()
	return self.CurrentAnimationId or 1
end

function AnimationController:GetCurrentAnimationName()
	return self.CurrentAnimationName or "IdleStanding"
end

function AnimationController:PlayAnimationForOtherPlayer(targetPlayer, animationName, category, variantIndex)
	if not targetPlayer or not animationName then
		return
	end

	local localPlayer = game:GetService("Players").LocalPlayer
	if targetPlayer == localPlayer then
		return
	end

	local character = targetPlayer.Character
	if not character or not character.Parent then
		return
	end

	local animator = self.OtherCharacterAnimators[character]
	if not animator then
		return
	end

	if not self:_loadAnimationInstances() then
		return
	end

	local tracks = self.OtherCharacterTracks[character]
	if not tracks then
		tracks = {}
		self.OtherCharacterTracks[character] = tracks
	end

	local track = tracks[animationName]
	if animationName == "JumpCancel" then
		if not track then
			track = {}
			local variants = #self.JumpCancelVariants > 0 and self.JumpCancelVariants
				or { self.AnimationInstances.JumpCancel }
			for _, animation in ipairs(variants) do
				table.insert(track, self:_loadTrack(animator, animation, "JumpCancel"))
			end
			tracks[animationName] = track
		end

		if type(track) == "table" then
			track = track[variantIndex or 1] or track[1]
		end
	elseif not track then
		local animation = self.AnimationInstances[animationName]
		if not animation then
			return
		end
		track = self:_loadTrack(animator, animation, animationName)
		tracks[animationName] = track
	end

	if not track then
		return
	end

	category = category or getAnimationCategory(animationName)
	local currentAnims = self.OtherCharacterCurrentAnimations[character] or {}
	self.OtherCharacterCurrentAnimations[character] = currentAnims

	local settings = self.AnimationSettings[animationName] or getDefaultSettings(animationName)

	if category == "State" then
		if currentAnims.Idle and currentAnims.Idle.IsPlaying then
			currentAnims.Idle:Stop(settings.FadeOutTime)
		end
		if currentAnims.State and currentAnims.State ~= track and currentAnims.State.IsPlaying then
			currentAnims.State:Stop(settings.FadeOutTime)
		end
		if currentAnims.Airborne and currentAnims.Airborne.IsPlaying then
			currentAnims.Airborne:Stop(settings.FadeOutTime)
		end
	elseif category == "Idle" then
		if currentAnims.State and currentAnims.State.IsPlaying then
			currentAnims.State:Stop(settings.FadeOutTime)
		end
		if currentAnims.Idle and currentAnims.Idle ~= track and currentAnims.Idle.IsPlaying then
			currentAnims.Idle:Stop(settings.FadeOutTime)
		end
		if currentAnims.Airborne and currentAnims.Airborne.IsPlaying then
			currentAnims.Airborne:Stop(settings.FadeOutTime)
		end
	elseif category == "Airborne" then
		if currentAnims.State and currentAnims.State.IsPlaying then
			currentAnims.State:Stop(settings.FadeOutTime)
		end
		if currentAnims.Idle and currentAnims.Idle.IsPlaying then
			currentAnims.Idle:Stop(settings.FadeOutTime)
		end
		if currentAnims.Airborne and currentAnims.Airborne ~= track and currentAnims.Airborne.IsPlaying then
			currentAnims.Airborne:Stop(settings.FadeOutTime)
		end
	elseif category == "Action" then
		if currentAnims.Action and currentAnims.Action ~= track and currentAnims.Action.IsPlaying then
			currentAnims.Action:Stop(settings.FadeOutTime)
		end
	end

	if category == "Action" then
		if track.IsPlaying then
			track:Stop(0)
		end
		track:Play(settings.FadeInTime, settings.Weight, settings.Speed)
		currentAnims[category] = track
	elseif not track.IsPlaying then
		track:Play(settings.FadeInTime, settings.Weight, settings.Speed)
		currentAnims[category] = track
	end
end

function AnimationController:StartAnimationSpeedUpdates()
	if self.AnimationSpeedUpdateConnection then
		self.AnimationSpeedUpdateConnection:Disconnect()
		self.AnimationSpeedUpdateConnection = nil
	end

	self.AnimationSpeedUpdateConnection = RunService.Heartbeat:Connect(function()
		self:UpdateAnimationSpeed()
	end)
end

function AnimationController:StopAnimationSpeedUpdates()
	if self.AnimationSpeedUpdateConnection then
		self.AnimationSpeedUpdateConnection:Disconnect()
		self.AnimationSpeedUpdateConnection = nil
	end
end

function AnimationController:UpdateAnimationSpeed()
	if not self.LocalCharacter then
		return
	end

	self.CharacterController = self.CharacterController or ServiceRegistry:GetController("CharacterController")
	if not self.CharacterController then
		return
	end

	local primaryPart = self.CharacterController.PrimaryPart
	if not primaryPart then
		return
	end

	local velocity = primaryPart.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	local currentState = MovementStateManager:GetCurrentState()
	local isSliding = currentState == "Sliding"
	local isGrounded = self:IsCharacterGrounded()

	if not isSliding then
		-- #region agent log
		debugLog("H1", "AnimationController.lua:UpdateAnimationSpeed", "airborne gating", {
			isGrounded = isGrounded,
			currentState = currentState,
			currentAirborne = self.CurrentAirborneAnimation and self:GetCurrentAnimationName() or nil,
			currentAirborneLooped = self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.Looped or nil,
		jumpCancelAge = getJumpCancelAge(),
		})
		-- #endregion
		if isGrounded then
			if self.CurrentAirborneAnimation then
				if self.CurrentAirborneAnimation.IsPlaying then
					-- Allow non-looping airborne animations (Jump/JumpCancel/WallBoost) to finish on ground.
					if self.CurrentAirborneAnimation.Looped then
						self:StopAirborneAnimation()
					end
				else
					self.CurrentAirborneAnimation = nil
				end
			end
		else
			local airborneTrack = self.CurrentAirborneAnimation
			if not airborneTrack or not airborneTrack.IsPlaying then
				self:PlayFallingAnimation()
			end
		end
	end

	local isCrouchAnimation = MovementStateManager:IsCrouching()
	local baseSpeed = isCrouchAnimation and Config.Gameplay.Character.CrouchSpeed or Config.Gameplay.Character.WalkSpeed
	local speedMultiplier = baseSpeed > 0 and (horizontalSpeed / baseSpeed) or 1

	local maxSpeed = isCrouchAnimation and 1.5 or 2.0
	speedMultiplier = math.clamp(speedMultiplier, 0, maxSpeed)

	if self.CurrentStateAnimation and self.CurrentStateAnimation.IsPlaying then
		self.CurrentStateAnimation:AdjustSpeed(speedMultiplier)
	end
	if self.CurrentIdleAnimation and self.CurrentIdleAnimation.IsPlaying then
		self.CurrentIdleAnimation:AdjustSpeed(speedMultiplier)
	end
end

return AnimationController
