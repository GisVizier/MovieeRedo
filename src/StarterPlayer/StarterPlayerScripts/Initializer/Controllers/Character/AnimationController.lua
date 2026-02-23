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
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

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

-- Weapon (legs-only) animation system
AnimationController.WeaponAnimationInstances = {}
AnimationController.WeaponAnimationTracks = {}
AnimationController.WeaponJumpCancelVariants = {}
AnimationController._weaponAnimMode = false -- true = play legs-only variants
-- Per-remote-player weapon anim mode: OtherCharacterWeaponMode[character] = true/false
AnimationController.OtherCharacterWeaponMode = {}
AnimationController.OtherCharacterWeaponTracks = {}

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

-- Emote system properties
AnimationController.CurrentEmoteTrack = nil
AnimationController.EmoteAnimationCache = {}
AnimationController.OtherCharacterEmoteTracks = {}

-- Custom/Kit animation system
AnimationController.CustomAnimationTracks = {}
AnimationController.PreloadedAnimations = {}
AnimationController.ZiplineActive = false
AnimationController.CurrentZiplineAnimationName = nil

-- Connection for re-acquiring Animator after ApplyDescription invalidates it
AnimationController._descriptionAppliedConn = nil
AnimationController._otherDescriptionAppliedConns = {} -- [character] = RBXScriptConnection

local STATE_ANIMATIONS = {
	Walking = "WalkingForward",
	Sprinting = "RunningForward",
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

	if name == "ZiplineIdle" then
		settings.FadeInTime = 0.1
		settings.FadeOutTime = 0.1
		settings.Loop = true
		settings.Priority = Enum.AnimationPriority.Action
	elseif name:match("^Zipline") then
		settings.FadeInTime = 0.05
		settings.FadeOutTime = 0.1
		settings.Loop = false
		settings.Priority = Enum.AnimationPriority.Action
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

	if animationName:match("^Zipline") then
		return "Action"
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
	self:PreloadCharacterAnimations()
	self:_initRigAnimationListener()
end

function AnimationController:_loadAnimationInstances()
	self.AnimationInstances = {}
	self.JumpCancelVariants = {}
	self.WeaponAnimationInstances = {}
	self.WeaponJumpCancelVariants = {}

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
		elseif child:IsA("Folder") and child.Name == "Zipline" then
			for _, zipAnim in ipairs(child:GetChildren()) do
				if zipAnim:IsA("Animation") then
					self.AnimationInstances[zipAnim.Name] = zipAnim
				end
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

	-- Load legs-only weapon variants from Base/Weapon/
	local weaponFolder = baseFolder:FindFirstChild("Weapon")
	if weaponFolder then
		for _, child in ipairs(weaponFolder:GetChildren()) do
			if child:IsA("Animation") then
				local name = child.Name
				local index = name:match("^JumpCancel(%d+)$")
				if index then
					self.WeaponJumpCancelVariants[tonumber(index)] = child
				else
					self.WeaponAnimationInstances[name] = child
				end
			elseif child:IsA("Folder") and child.Name == "Zipline" then
				for _, zipAnim in ipairs(child:GetChildren()) do
					if zipAnim:IsA("Animation") then
						self.WeaponAnimationInstances[zipAnim.Name] = zipAnim
					end
				end
			end
		end

		local wVariants = {}
		for index, anim in pairs(self.WeaponJumpCancelVariants) do
			wVariants[index] = anim
		end

		self.WeaponJumpCancelVariants = {}
		for i = 1, #wVariants do
			if wVariants[i] then
				table.insert(self.WeaponJumpCancelVariants, wVariants[i])
			end
		end

		if #self.WeaponJumpCancelVariants == 0 and self.WeaponAnimationInstances.JumpCancel then
			self.WeaponJumpCancelVariants = { self.WeaponAnimationInstances.JumpCancel }
		end
	end

	return true
end

--[[
	Preloads all animations from Assets.Animations.Character
	Supports subfolders: Base, Kits, etc.
	Animations are stored by both name and animationId for flexible lookup.
]]
function AnimationController:PreloadCharacterAnimations()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return
	end

	local animations = assets:FindFirstChild("Animations")
	if not animations then
		return
	end

	local characterFolder = animations:FindFirstChild("Character")
	if not characterFolder then
		return
	end

	-- Recursively load all animations from Character folder
	local function loadFromFolder(folder)
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Animation") then
				local animId = child.AnimationId
				if animId and animId ~= "" then
					self.PreloadedAnimations[animId] = child
					self.PreloadedAnimations[child.Name] = child
				end
			elseif child:IsA("Folder") then
				loadFromFolder(child)
			end
		end
	end

	loadFromFolder(characterFolder)

	if TestMode.Logging.LogAnimationSystem then
		local count = 0
		for _ in pairs(self.PreloadedAnimations) do
			count = count + 1
		end
		LogService:Info("ANIMATION", "Preloaded character animations", { Count = count / 2 })
	end
end

--[[
	Play any animation by ID with optional settings.
	
	@param animationId: string - rbxassetid:// URL, numeric ID, or animation name from preloaded
	@param settings: table? - Optional settings:
		- FadeInTime: number (default 0.1)
		- FadeOutTime: number (default 0.1)
		- Weight: number (default 1)
		- Speed: number (default 1)
		- Priority: Enum.AnimationPriority (default Action)
		- Looped: boolean (default false)
		- StopOthers: boolean (default true) - Stop other custom animations
	
	@return AnimationTrack? - The playing track, or nil if failed
]]
function AnimationController:PlayAnimation(animationId: string, settings: { [string]: any }?)
	if not self.LocalAnimator then
		return nil
	end

	settings = settings or {}

	-- Resolve animation instance
	local animation = nil

	-- Check preloaded first (by name or ID)
	if self.PreloadedAnimations[animationId] then
		animation = self.PreloadedAnimations[animationId]
	else
		-- Create new animation instance for rbxassetid
		animation = Instance.new("Animation")
		if animationId:match("^rbxassetid://") then
			animation.AnimationId = animationId
		else
			-- Assume it's a numeric ID
			animation.AnimationId = "rbxassetid://" .. animationId
		end
	end

	if not animation or not animation.AnimationId or animation.AnimationId == "" then
		return nil
	end

	-- Stop other custom animations if requested
	if settings.StopOthers ~= false then
		for _, track in pairs(self.CustomAnimationTracks) do
			if track and track.IsPlaying then
				track:Stop(settings.FadeOutTime or 0.1)
			end
		end
	end

	-- Load track
	local track = self.LocalAnimator:LoadAnimation(animation)
	if not track then
		return nil
	end

	-- Apply settings
	track.Priority = settings.Priority or Enum.AnimationPriority.Action
	track.Looped = settings.Looped or false

	-- Play
	track:Play(settings.FadeInTime or 0.1, settings.Weight or 1, settings.Speed or 1)

	-- Store reference
	self.CustomAnimationTracks[animationId] = track

	-- Cleanup when stopped
	track.Stopped:Once(function()
		if self.CustomAnimationTracks[animationId] == track then
			self.CustomAnimationTracks[animationId] = nil
		end
	end)

	return track
end

--[[
	Stop a custom animation by ID.
]]
function AnimationController:StopAnimation(animationId: string, fadeOutTime: number?)
	local track = self.CustomAnimationTracks[animationId]
	if track and track.IsPlaying then
		track:Stop(fadeOutTime or 0.1)
	end
	self.CustomAnimationTracks[animationId] = nil
end

--[[
	Stop all custom animations.
]]
function AnimationController:StopAllCustomAnimations(fadeOutTime: number?)
	for _, track in pairs(self.CustomAnimationTracks) do
		if track and track.IsPlaying then
			track:Stop(fadeOutTime or 0.1)
		end
	end
	self.CustomAnimationTracks = {}
end

--------------------------------------------------------------------------------
-- Server-Authoritative Rig Animation API
-- Client sends requests via reliable remote → server validates and broadcasts
-- to ALL clients (including requester) via reliable remote → each client plays
-- the animation on their local copy of the rig Animator.
--
-- Rig parts are anchored and CFrame-driven, so Roblox built-in Animator
-- replication doesn't work. Instead the server acts as a reliable relay that
-- guarantees delivery (fixing the old unreliable VFXRep looped-stop bug).
-- The server also tracks active looped animations for late joiners.
--------------------------------------------------------------------------------

AnimationController._rigAnimTracks = {} -- [userId] = { [animName] = AnimationTrack }

function AnimationController:PlayRigAnimation(animName: string, settings: { [string]: any }?)
	Net:FireServer("RigAnimationRequest", {
		action = "Play",
		animName = animName,
		Looped = settings and settings.Looped,
		Priority = settings and settings.Priority and tostring(settings.Priority),
		FadeInTime = settings and settings.FadeInTime,
		Speed = settings and settings.Speed,
		StopOthers = settings and settings.StopOthers,
	})
end

function AnimationController:StopRigAnimation(animName: string, fadeOut: number?)
	Net:FireServer("RigAnimationRequest", {
		action = "Stop",
		animName = animName,
		fadeOut = fadeOut or 0.1,
	})
end

function AnimationController:StopAllRigAnimations(fadeOut: number?)
	Net:FireServer("RigAnimationRequest", {
		action = "StopAll",
		fadeOut = fadeOut or 0.15,
	})
end

function AnimationController:_getAnimatorForUserId(userId)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil
	end

	-- Local player: use LocalAnimator
	if player == LocalPlayer then
		return self.LocalAnimator
	end

	-- Remote player: use OtherCharacterAnimators
	local character = player.Character
	if character then
		return self.OtherCharacterAnimators[character]
	end

	return nil
end

function AnimationController:_onRigAnimationBroadcast(data)
	if type(data) ~= "table" then
		return
	end

	local action = data.action
	local userId = data.userId
	if not userId then
		return
	end

	if action == "Play" then
		local animName = data.animName
		if type(animName) ~= "string" or animName == "" then
			return
		end

		local animator = self:_getAnimatorForUserId(userId)
		if not animator then
			return
		end

		local animation = self.PreloadedAnimations[animName]
		if not animation then
			return
		end

		if not self._rigAnimTracks[userId] then
			self._rigAnimTracks[userId] = {}
		end
		local tracks = self._rigAnimTracks[userId]

		-- Stop others if requested
		if data.StopOthers ~= false then
			for name, track in pairs(tracks) do
				if name ~= animName and track and track.IsPlaying then
					track:Stop(0.1)
				end
			end
			local kept = {}
			if tracks[animName] then
				kept[animName] = tracks[animName]
			end
			tracks = kept
			self._rigAnimTracks[userId] = tracks
		end

		-- Stop existing track for this name
		local existing = tracks[animName]
		if existing and existing.IsPlaying then
			existing:Stop(0)
		end

		local track = animator:LoadAnimation(animation)
		if not track then
			return
		end

		local priority = data.Priority
		if type(priority) == "string" and priority ~= "" then
			local ok, val = pcall(function()
				return Enum.AnimationPriority[priority]
			end)
			if ok and val then
				priority = val
			else
				priority = Enum.AnimationPriority.Action4
			end
		else
			priority = Enum.AnimationPriority.Action4
		end

		track.Priority = priority
		track.Looped = data.Looped == true
		track:Play(tonumber(data.FadeInTime) or 0.15, 1, tonumber(data.Speed) or 1)

		tracks[animName] = track

		track.Stopped:Once(function()
			local t = self._rigAnimTracks[userId]
			if t and t[animName] == track then
				t[animName] = nil
			end
		end)

	elseif action == "Stop" then
		local animName = data.animName
		if type(animName) ~= "string" then
			return
		end

		local tracks = self._rigAnimTracks[userId]
		if not tracks then
			return
		end

		local track = tracks[animName]
		if track and track.IsPlaying then
			track:Stop(tonumber(data.fadeOut) or 0.1)
		end
		tracks[animName] = nil

	elseif action == "StopAll" then
		local tracks = self._rigAnimTracks[userId]
		if not tracks then
			return
		end

		local fadeOut = tonumber(data.fadeOut) or 0.15
		for _, track in pairs(tracks) do
			if track and track.IsPlaying then
				track:Stop(fadeOut)
			end
		end
		self._rigAnimTracks[userId] = {}
	end
end

function AnimationController:_initRigAnimationListener()
	Net:ConnectClient("RigAnimationBroadcast", function(data)
		self:_onRigAnimationBroadcast(data)
	end)
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
	self.WeaponAnimationTracks = {}
	self.AnimationSettings = {}

	-- Load full-body tracks from Base/
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

	-- Load legs-only weapon tracks from Base/Weapon/
	for name, animation in pairs(self.WeaponAnimationInstances) do
		local track = self:_loadTrack(self.LocalAnimator, animation, name)
		if track then
			self.WeaponAnimationTracks[name] = track
		end
	end

	if #self.WeaponJumpCancelVariants > 0 then
		self.WeaponAnimationTracks.JumpCancel = {}
		for _, animation in ipairs(self.WeaponJumpCancelVariants) do
			local track = self:_loadTrack(self.LocalAnimator, animation, "JumpCancel")
			if track then
				table.insert(self.WeaponAnimationTracks.JumpCancel, track)
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

	-- Listen for ApplyDescription completion. When it fires, the Animator and all
	-- AnimationTracks may have been destroyed/recreated, so we must re-acquire
	-- the Animator and reload every track.
	if self._descriptionAppliedConn then
		self._descriptionAppliedConn:Disconnect()
		self._descriptionAppliedConn = nil
	end
	self._descriptionAppliedConn = rig:GetAttributeChangedSignal("DescriptionApplied"):Connect(function()
		if not self.LocalCharacter or self.LocalCharacter ~= character then
			return
		end
		local rigHumanoid = rig:FindFirstChildOfClass("Humanoid")
		if not rigHumanoid then
			return
		end
		local newAnimator = rigHumanoid:FindFirstChildOfClass("Animator")
		if not newAnimator then
			newAnimator = Instance.new("Animator")
			newAnimator.Parent = rigHumanoid
		end
		self.LocalAnimator = newAnimator

		-- Reload all animation tracks on the fresh Animator
		self:PreloadAnimations()

		-- Re-play the appropriate animation for the current movement state
		local isGrounded = MovementStateManager:GetIsGrounded()
		local isMoving = MovementStateManager:GetIsMoving()
		if isGrounded then
			if isMoving then
				local currentState = MovementStateManager:GetCurrentState()
				local animName = self:_getStateAnimationName(currentState)
				if animName then
					self:PlayStateAnimation(animName)
				end
			else
				self:PlayIdleAnimation("IdleStanding")
			end
		else
			self:PlayFallingAnimation()
		end

		-- Rig (kit) animations are now replayed by the server-side RigAnimationService
		-- when it detects the DescriptionApplied attribute change on the rig.
	end)
end

function AnimationController:OnLocalCharacterRemoving()
	self:StopAllLocalAnimations()
	self:StopSlideAnimationUpdates()
	self:StopWalkAnimationUpdates()
	self:StopRunAnimationUpdates()
	self:StopCrouchAnimationUpdates()
	self:StopAnimationSpeedUpdates()

	if self._descriptionAppliedConn then
		self._descriptionAppliedConn:Disconnect()
		self._descriptionAppliedConn = nil
	end

	self.LocalCharacter = nil
	self.LocalAnimator = nil
	self.LocalAnimationTracks = {}
	self.WeaponAnimationTracks = {}
	self._weaponAnimMode = false
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

	-- Listen for ApplyDescription completion on this remote rig.
	-- Re-acquire the Animator and clear cached tracks so new ones are loaded fresh.
	local oldConn = self._otherDescriptionAppliedConns[character]
	if oldConn then
		oldConn:Disconnect()
	end
	self._otherDescriptionAppliedConns[character] = rig:GetAttributeChangedSignal("DescriptionApplied"):Connect(function()
		local rigHumanoid = rig:FindFirstChildOfClass("Humanoid")
		if not rigHumanoid then
			return
		end
		local newAnimator = rigHumanoid:FindFirstChildOfClass("Animator")
		if not newAnimator then
			newAnimator = Instance.new("Animator")
			newAnimator.Parent = rigHumanoid
		end
		self.OtherCharacterAnimators[character] = newAnimator

		-- Invalidate cached tracks so they are reloaded on the new Animator
		self.OtherCharacterTracks[character] = {}
		self.OtherCharacterWeaponTracks[character] = {}
		self.OtherCharacterCurrentAnimations[character] = {}

		-- Reset RemoteReplicator LastAnimationId so the next ReplicatePlayers tick
		-- re-plays the current animation on the fresh Animator.
		local ownerPlayer = Players:GetPlayerFromCharacter(character)
		if not ownerPlayer then
			ownerPlayer = Players:FindFirstChild(character.Name)
		end
		if ownerPlayer then
			local RemoteReplicator = require(Locations.Game:WaitForChild("Replication"):WaitForChild("RemoteReplicator"))
			local remoteData = RemoteReplicator.RemotePlayers and RemoteReplicator.RemotePlayers[ownerPlayer.UserId]
			if remoteData then
				remoteData.LastAnimationId = 0
			end
		end
	end)
end

function AnimationController:OnOtherCharacterRemoving(character)
	-- Disconnect ApplyDescription listener for this character
	local descConn = self._otherDescriptionAppliedConns[character]
	if descConn then
		descConn:Disconnect()
		self._otherDescriptionAppliedConns[character] = nil
	end

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
	self.OtherCharacterWeaponMode[character] = nil

	-- Cleanup rig animation tracks for this player
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		self._rigAnimTracks[player.UserId] = nil
	end

	-- Cleanup weapon tracks for this character
	local weaponTracks = self.OtherCharacterWeaponTracks[character]
	if weaponTracks then
		for _, track in pairs(weaponTracks) do
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
	self.OtherCharacterWeaponTracks[character] = nil

end

function AnimationController:OnMovementStateChanged(previousState, newState, _data)
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end
	if self.ZiplineActive then
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

	local animationName = self:_getStateAnimationName(newState)
	if not animationName then
		return
	end

	if isMoving then
		if newState == "Walking" then
			self:StopRunAnimationUpdates()
			self:StartWalkAnimationUpdates()
		elseif newState == "Sprinting" then
			if self:_shouldUseWalkAnimationsForSprint() then
				self:StopRunAnimationUpdates()
				self:StartWalkAnimationUpdates()
			else
				self:StopWalkAnimationUpdates()
				self:StartRunAnimationUpdates()
			end
		elseif newState == "Crouching" then
			self:StartCrouchAnimationUpdates()
		else
			self:PlayStateAnimation(animationName)
		end
	else
		self:StopWalkAnimationUpdates()
		self:StopRunAnimationUpdates()
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
	if self.ZiplineActive then
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
		if currentState == "Walking" then
			self:StopRunAnimationUpdates()
			self:StartWalkAnimationUpdates()
		elseif currentState == "Sprinting" then
			if self:_shouldUseWalkAnimationsForSprint() then
				self:StopRunAnimationUpdates()
				self:StartWalkAnimationUpdates()
			else
				self:StopWalkAnimationUpdates()
				self:StartRunAnimationUpdates()
			end
		elseif currentState == "Crouching" then
			self:StartCrouchAnimationUpdates()
		else
			local animationName = self:_getStateAnimationName(currentState)
			if animationName then
				self:PlayStateAnimation(animationName)
			end
		end
	else
		self:StopWalkAnimationUpdates()
		self:StopRunAnimationUpdates()
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
	if self.ZiplineActive then
		return
	end

	local currentState = MovementStateManager:GetCurrentState()
	local isSliding = (currentState == "Sliding")
	local isJumpCancelProtected = isJumpCancelProtected(self)

	if isGrounded then
		if isJumpCancelProtected then
			return
		end
		self:StopAirborneAnimation()

		if not wasGrounded and not isSliding then
			local primary = self:_getLocalTrackTable()
			local landName = (primary.Land or self.LocalAnimationTracks.Land) and "Land"
				or ((primary.Landing or self.LocalAnimationTracks.Landing) and "Landing")
			if landName then
				self:PlayActionAnimation(landName)
			end
		end

		local isMoving = MovementStateManager:GetIsMoving()
		if isSliding or isMoving then
			if currentState == "Walking" then
				self:StopRunAnimationUpdates()
				self:StartWalkAnimationUpdates()
			elseif currentState == "Sprinting" then
				if self:_shouldUseWalkAnimationsForSprint() then
					self:StopRunAnimationUpdates()
					self:StartWalkAnimationUpdates()
				else
					self:StopWalkAnimationUpdates()
					self:StartRunAnimationUpdates()
				end
			elseif currentState == "Crouching" then
				self:StartCrouchAnimationUpdates()
			else
				local animationName = self:_getStateAnimationName(currentState)
				if animationName then
					self:PlayStateAnimation(animationName)
				end
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

--- Toggle weapon (legs-only) animation mode for the local player.
--- When enabled, body animations play from Base/Weapon/ (arms keyframes deleted).
--- When disabled, body animations play from Base/ (full-body).
function AnimationController:SetWeaponAnimationMode(enabled: boolean)
	local wasEnabled = self._weaponAnimMode
	self._weaponAnimMode = enabled == true

	-- If mode changed while an animation is playing, re-play the current animation
	-- from the correct track table so it swaps immediately.
	if wasEnabled ~= self._weaponAnimMode and self.CurrentAnimationName then
		local name = self.CurrentAnimationName
		local category = getAnimationCategory(name)
		if category == "State" then
			self:PlayStateAnimation(name)
		elseif category == "Idle" then
			self:PlayIdleAnimation(name)
		elseif category == "Airborne" then
			self:PlayAirborneAnimation(name)
		end
	end
end

--- Toggle weapon (legs-only) animation mode for a specific remote player.
function AnimationController:SetWeaponAnimationModeForPlayer(player: Player, enabled: boolean)
	local character = player and player.Character
	if character then
		self.OtherCharacterWeaponMode[character] = enabled == true or nil
	end
end

function AnimationController:_shouldUseWalkAnimationsForSprint(): boolean
	-- Run = walk animation sped up (no separate run animation). In lobby, weapons are unequipped
	-- so weapon mode is off, but we still need to use walk animation for sprint.
	if self._weaponAnimMode == true then
		return true
	end
	local localPlayer = Players.LocalPlayer
	return localPlayer and localPlayer:GetAttribute("InLobby") == true
end

function AnimationController:_getStateAnimationName(stateName: string): string?
	if stateName == "Sprinting" and self:_shouldUseWalkAnimationsForSprint() then
		return "WalkingForward"
	end
	return STATE_ANIMATIONS[stateName]
end

--- Returns the correct track lookup table for the local player.
--- When weapon mode is active AND a weapon variant exists, use it; otherwise fall back to full-body.
function AnimationController:_getLocalTrackTable()
	if self._weaponAnimMode and next(self.WeaponAnimationTracks) then
		return self.WeaponAnimationTracks, self.LocalAnimationTracks
	end
	return self.LocalAnimationTracks, nil
end

function AnimationController:PlayStateAnimation(animationName)
	if not self.LocalAnimator then
		return
	end

	local primary, fallback = self:_getLocalTrackTable()
	local track = primary[animationName]
	-- Fall back to full-body if no weapon variant exists for this specific animation
	if not track and fallback then
		track = fallback[animationName]
	end
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

	local primary, fallback = self:_getLocalTrackTable()
	local track = primary[animationName]
	if not track and fallback then
		track = fallback[animationName]
	end
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

	local primary, fallback = self:_getLocalTrackTable()
	local track = primary[animationName]
	if not track and fallback then
		track = fallback[animationName]
	end
	if type(track) == "table" then
		track = track[1]
	end
	if not track then
		return
	end

	local settings = self.AnimationSettings[animationName] or getDefaultSettings(animationName)

	if
		self.CurrentActionAnimation
		and self.CurrentActionAnimation ~= track
		and self.CurrentActionAnimation.IsPlaying
	then
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

function AnimationController:PlayZiplineAnimation(animationName)
	if not self.LocalAnimator or not animationName then
		return nil
	end
	if not self:_loadAnimationInstances() then
		return nil
	end
	local primary, fallback = self:_getLocalTrackTable()
	local track = primary[animationName]
	if not track and fallback then
		track = fallback[animationName]
	end
	if type(track) == "table" then
		track = track[1]
	end
	if not track then
		return nil
	end

	self.ZiplineActive = true
	self.CurrentZiplineAnimationName = animationName

	self:StopSlideAnimationUpdates()
	self:StopWalkAnimationUpdates()
	self:StopRunAnimationUpdates()
	self:StopCrouchAnimationUpdates()

	if self.CurrentStateAnimation and self.CurrentStateAnimation.IsPlaying then
		local settings = self.AnimationSettings[self.CurrentAnimationName]
			or getDefaultSettings(self.CurrentAnimationName)
		self.CurrentStateAnimation:Stop(settings.FadeOutTime)
	end
	if self.CurrentIdleAnimation and self.CurrentIdleAnimation.IsPlaying then
		local settings = self.AnimationSettings[self.CurrentAnimationName]
			or getDefaultSettings(self.CurrentAnimationName)
		self.CurrentIdleAnimation:Stop(settings.FadeOutTime)
	end
	if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
		local settings = self.AnimationSettings[self.CurrentAnimationName]
			or getDefaultSettings(self.CurrentAnimationName)
		self.CurrentAirborneAnimation:Stop(settings.FadeOutTime)
		self.CurrentAirborneAnimation = nil
	end

	local settings = self.AnimationSettings[animationName] or getDefaultSettings(animationName)
	if
		self.CurrentActionAnimation
		and self.CurrentActionAnimation ~= track
		and self.CurrentActionAnimation.IsPlaying
	then
		self.CurrentActionAnimation:Stop(settings.FadeOutTime)
	end

	if track.IsPlaying then
		track:Stop(0)
	end
	track.Looped = settings.Loop
	track:Play(settings.FadeInTime, settings.Weight, settings.Speed)
	self.CurrentActionAnimation = track
	self:SetCurrentAnimation(animationName)

	return track
end

function AnimationController:StopZiplineAnimation(fadeOutOverride)
	if not self.ZiplineActive then
		return
	end
	self.ZiplineActive = false
	self.CurrentZiplineAnimationName = nil
	local function getFadeOutTime(name)
		if type(fadeOutOverride) == "number" then
			return fadeOutOverride
		end
		local anim = self.AnimationInstances and self.AnimationInstances[name]
		local attr = anim and anim:GetAttribute("FadeOutTime")
		local fadeOutTime = type(attr) == "number" and attr or 0
		if name == "ZiplineIdle" then
			fadeOutTime = math.min(fadeOutTime or 0, 0.05)
		end
		return fadeOutTime or 0
	end
	for name, track in pairs(self.CustomAnimationTracks) do
		if type(name) == "string" and name:match("^Zipline") then
			if track and track.IsPlaying then
				track:Stop(getFadeOutTime(name))
			end
			self.CustomAnimationTracks[name] = nil
		end
	end
	for name, track in pairs(self.LocalAnimationTracks) do
		if type(name) == "string" and name:match("^Zipline") then
			local resolved = track
			if type(resolved) == "table" then
				resolved = resolved[1]
			end
			if resolved and resolved.IsPlaying then
				resolved:Stop(getFadeOutTime(name))
			end
		end
	end
end

function AnimationController:StopAllLocalAnimations()
	for _, trackTable in ipairs({ self.LocalAnimationTracks, self.WeaponAnimationTracks }) do
		for _, track in pairs(trackTable) do
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
	end

	self.CurrentStateAnimation = nil
	self.CurrentIdleAnimation = nil
	self.CurrentAirborneAnimation = nil
	self.CurrentActionAnimation = nil
end

function AnimationController:SelectRandomJumpCancelTrack(forceVariantIndex)
	-- Use weapon (legs-only) JumpCancel tracks if available and weapon mode is on
	local primary, fallback = self:_getLocalTrackTable()
	local jumpCancelTracks = primary.JumpCancel
	if (not jumpCancelTracks or type(jumpCancelTracks) ~= "table") and fallback then
		jumpCancelTracks = fallback.JumpCancel
	end
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

	local primary, fallback = self:_getLocalTrackTable()

	local track = nil
	if animationName == "JumpCancel" then
		track = self:SelectRandomJumpCancelTrack(forceVariantIndex)
		if type(track) == "table" then
			track = track[1]
		end
	else
		track = primary[animationName]
		if not track and fallback then
			track = fallback[animationName]
		end
		if type(track) == "table" then
			track = track[1]
		end
	end

	if not track then
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
	if animationName == "JumpCancel" then
	end
end

function AnimationController:StopAirborneAnimation()
	if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
		local name = self:GetCurrentAnimationName()
		local settings = self.AnimationSettings[name] or getDefaultSettings(name)
		self.CurrentAirborneAnimation:Stop(settings.FadeOutTime)
	end
	self.CurrentAirborneAnimation = nil
end

function AnimationController:PlayFallingAnimation()
	if isJumpCancelProtected(self) then
		return
	end
	self:PlayAirborneAnimation("Falling")
end

function AnimationController:TriggerJumpAnimation()
	self:PlayAirborneAnimation("Jump")
end

function AnimationController:TriggerJumpCancelAnimation()
	self.LastJumpCancelAnimationTime = tick()
	self:PlayAirborneAnimation("JumpCancel")
end

function AnimationController:TriggerWallBoostAnimation(cameraDirection, movementDirection)
	local animationName = "WallBoostForward"
	if cameraDirection and movementDirection then
		animationName = WallBoostDirectionDetector:GetWallBoostAnimationName(cameraDirection, movementDirection)
	end
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
		if currentState ~= "Walking" then
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

function AnimationController:StartRunAnimationUpdates()
	if not self.LocalCharacter or not self.LocalAnimator then
		return
	end

	self:StopRunAnimationUpdates()

	self.CharacterController = ServiceRegistry:GetController("CharacterController")
	if not self.CharacterController then
		return
	end

	local initialAnimationName = self:GetCurrentRunAnimationName()
	self:PlayStateAnimation(initialAnimationName)
	self.CurrentRunAnimationName = initialAnimationName

	self.RunAnimationUpdateConnection = RunService.Heartbeat:Connect(function()
		local currentState = MovementStateManager:GetCurrentState()
		if currentState ~= "Sprinting" then
			self:StopRunAnimationUpdates()
			return
		end

		if not MovementStateManager:GetIsMoving() then
			return
		end

		if self.CurrentAirborneAnimation and self.CurrentAirborneAnimation.IsPlaying then
			return
		end

		local newAnimationName = self:GetCurrentRunAnimationName()
		if newAnimationName ~= self.CurrentRunAnimationName then
			self:PlayStateAnimation(newAnimationName)
			self.CurrentRunAnimationName = newAnimationName
		end
	end)
end

function AnimationController:StopRunAnimationUpdates()
	if self.RunAnimationUpdateConnection then
		self.RunAnimationUpdateConnection:Disconnect()
		self.RunAnimationUpdateConnection = nil
		self.CurrentRunAnimationName = nil
	end
end

function AnimationController:GetCurrentRunAnimationName()
	if self:_shouldUseWalkAnimationsForSprint() then
		return self:GetCurrentWalkAnimationName()
	end

	if not self.CharacterController then
		return "RunningForward"
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return "RunningForward"
	end

	local cameraController = ServiceRegistry:GetController("CameraController")
	if cameraController and cameraController.CurrentMode == "Orbit" then
		return "RunningForward"
	end

	if cameraController then
		local shouldRotateToCamera = true
		if cameraController.ShouldRotateCharacterToCamera then
			shouldRotateToCamera = cameraController:ShouldRotateCharacterToCamera()
		end

		if not shouldRotateToCamera then
			return "RunningForward"
		end
	end

	local cameraDirection = camera.CFrame.LookVector
	local movementDirection = self.CharacterController:CalculateMovementDirection()
	if movementDirection.Magnitude < 0.1 then
		return "RunningForward"
	end

	return WalkDirectionDetector:GetRunAnimationName(cameraDirection, movementDirection)
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
		return false
	end

	local localPlayer = game:GetService("Players").LocalPlayer
	if targetPlayer == localPlayer then
		return false
	end

	local character = targetPlayer.Character
	if not character or not character.Parent then
		return false
	end

	local animator = self.OtherCharacterAnimators[character]
	if not animator or not animator.Parent then
		return false
	end

	if not self:_loadAnimationInstances() then
		return false
	end

	-- Determine if this remote player is in weapon (legs-only) animation mode
	local useWeaponAnims = self.OtherCharacterWeaponMode[character] == true
		and next(self.WeaponAnimationInstances) ~= nil

	-- Pick the right track cache and animation instance table
	local tracks, animInstances, jumpVariants
	if useWeaponAnims then
		tracks = self.OtherCharacterWeaponTracks[character]
		if not tracks then
			tracks = {}
			self.OtherCharacterWeaponTracks[character] = tracks
		end
		animInstances = self.WeaponAnimationInstances
		jumpVariants = self.WeaponJumpCancelVariants
	else
		tracks = self.OtherCharacterTracks[character]
		if not tracks then
			tracks = {}
			self.OtherCharacterTracks[character] = tracks
		end
		animInstances = self.AnimationInstances
		jumpVariants = self.JumpCancelVariants
	end

	local track = tracks[animationName]
	if animationName == "JumpCancel" then
		if not track then
			track = {}
			local variants = #jumpVariants > 0 and jumpVariants
				or { animInstances.JumpCancel or self.AnimationInstances.JumpCancel }
			for _, animation in ipairs(variants) do
				if animation then
					table.insert(track, self:_loadTrack(animator, animation, "JumpCancel"))
				end
			end
			tracks[animationName] = track
		end

		if type(track) == "table" then
			track = track[variantIndex or 1] or track[1]
		end
	elseif not track then
		local animation = animInstances[animationName] or self.AnimationInstances[animationName]
		if not animation then
			return false
		end
		track = self:_loadTrack(animator, animation, animationName)
		tracks[animationName] = track
	end

	if not track then
		return false
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

	return true
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
	if self.ZiplineActive then
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
	local isSprinting = currentState == "Sprinting"
	local baseSpeed
	if isCrouchAnimation then
		baseSpeed = Config.Gameplay.Character.CrouchSpeed
	elseif isSprinting then
		if self:_shouldUseWalkAnimationsForSprint() then
			baseSpeed = Config.Gameplay.Character.WalkSpeed
		else
			baseSpeed = Config.Gameplay.Character.SprintSpeed or Config.Gameplay.Character.WalkSpeed
		end
	else
		baseSpeed = Config.Gameplay.Character.WalkSpeed
	end
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

-- ============================================================================
-- EMOTE SYSTEM METHODS
-- ============================================================================

function AnimationController:_getEmoteAnimationFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end

	local animations = assets:FindFirstChild("Animations")
	if not animations then
		return nil
	end

	return animations:FindFirstChild("Emotes")
end

function AnimationController:_loadEmoteAnimation(emoteId: string): Animation?
	-- Check cache first
	if self.EmoteAnimationCache[emoteId] then
		return self.EmoteAnimationCache[emoteId]
	end

	-- Get animation ID from the EmoteService's registered emote class
	local EmoteService = nil
	local ok, service = pcall(function()
		local Locations =
			require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
		return require(Locations.Game:WaitForChild("Emotes"))
	end)
	if ok then
		EmoteService = service
	end

	if EmoteService and EmoteService.getEmoteClass then
		local emoteClass = EmoteService.getEmoteClass(emoteId)
		if emoteClass and emoteClass.Animations and emoteClass.Animations.Main then
			-- Create Animation instance from the ID
			local animId = emoteClass.Animations.Main
			if not animId:match("^rbxassetid://") then
				animId = "rbxassetid://" .. animId
			end

			local animation = Instance.new("Animation")
			animation.AnimationId = animId
			animation.Name = emoteId .. "_Main"

			self.EmoteAnimationCache[emoteId] = animation
			return animation
		end
	end

	-- Fallback: try loading from Assets folder structure
	local emotesFolder = self:_getEmoteAnimationFolder()
	if not emotesFolder then
		return nil
	end

	local emoteFolder = emotesFolder:FindFirstChild(emoteId)
	if not emoteFolder then
		return nil
	end

	local animFolder = emoteFolder:FindFirstChild("Animation")
	if not animFolder then
		return nil
	end

	-- Find first Animation instance
	for _, child in animFolder:GetChildren() do
		if child:IsA("Animation") then
			self.EmoteAnimationCache[emoteId] = child
			return child
		end
	end

	return nil
end

function AnimationController:PlayEmote(emoteId: string): boolean
	if not self.LocalAnimator then
		return false
	end

	-- Stop current emote if playing
	self:StopEmote()

	-- Load animation
	local animation = self:_loadEmoteAnimation(emoteId)
	if not animation then
		if TestMode.Logging.LogAnimationSystem then
			LogService:Warn("ANIMATION", "Emote animation not found", { EmoteId = emoteId })
		end
		return false
	end

	-- Stop other animations that would conflict
	if self.CurrentStateAnimation and self.CurrentStateAnimation.IsPlaying then
		self.CurrentStateAnimation:Stop(0.2)
	end
	if self.CurrentIdleAnimation and self.CurrentIdleAnimation.IsPlaying then
		self.CurrentIdleAnimation:Stop(0.2)
	end

	-- Load and play emote track
	local track = self.LocalAnimator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action2
	track.Looped = false -- Will be set by emote config if needed

	track:Play(0.2)
	self.CurrentEmoteTrack = track

	-- Connect to track stopped to clear reference
	track.Stopped:Once(function()
		if self.CurrentEmoteTrack == track then
			self.CurrentEmoteTrack = nil
		end
	end)

	return true
end

function AnimationController:StopEmote(): boolean
	if not self.CurrentEmoteTrack then
		return true
	end

	if self.CurrentEmoteTrack.IsPlaying then
		self.CurrentEmoteTrack:Stop(0.2)
	end

	self.CurrentEmoteTrack = nil
	return true
end

function AnimationController:IsEmotePlaying(): boolean
	return self.CurrentEmoteTrack ~= nil and self.CurrentEmoteTrack.IsPlaying
end

function AnimationController:PlayEmoteForOtherPlayer(player: Player, emoteId: string): boolean
	if not player or not emoteId then
		return false
	end

	local character = player.Character
	if not character or not character.Parent then
		return false
	end

	local animator = self.OtherCharacterAnimators[character]
	if not animator then
		return false
	end

	-- Stop current emote for this player
	self:StopEmoteForOtherPlayer(player)

	-- Load animation
	local animation = self:_loadEmoteAnimation(emoteId)
	if not animation then
		return false
	end

	-- Load and play track
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action2
	track.Looped = false

	track:Play(0.2)
	self.OtherCharacterEmoteTracks[character] = track

	-- Cleanup on stopped
	track.Stopped:Once(function()
		if self.OtherCharacterEmoteTracks[character] == track then
			self.OtherCharacterEmoteTracks[character] = nil
		end
	end)

	return true
end

function AnimationController:StopEmoteForOtherPlayer(player: Player): boolean
	if not player then
		return false
	end

	local character = player.Character
	if not character then
		return true
	end

	local track = self.OtherCharacterEmoteTracks[character]
	if track and track.IsPlaying then
		track:Stop(0.2)
	end

	self.OtherCharacterEmoteTracks[character] = nil
	return true
end

return AnimationController
