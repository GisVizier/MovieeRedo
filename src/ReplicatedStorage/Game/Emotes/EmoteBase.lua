--[[
	EmoteBase - Base class for all emotes
	
	Handles:
	- Animation loading from Assets/Animations/Emotes/{EmoteId}/Animation/
	- Sound loading from Assets/Animations/Emotes/{EmoteId}/Sound/
	- Movement cancellation when AllowMove = false
	- Delegates animation playback to AnimationController
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local EmoteConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("EmoteConfig"))

local EmoteBase = {}
EmoteBase.__index = EmoteBase

-- Static properties that subclasses should override
EmoteBase.Id = "EmoteBase"
EmoteBase.DisplayName = "Emote"
EmoteBase.Rarity = "Common"
EmoteBase.Loopable = false
EmoteBase.AllowMove = true
EmoteBase.Speed = 1

function EmoteBase.new(emoteId: string, emoteData: { [string]: any }, rig: Instance?)
	local self = setmetatable({}, EmoteBase)
	
	self._id = emoteId
	self._data = emoteData or {}
	self._rig = rig
	self._active = false
	self._animation = nil
	self._sound = nil
	self._animationTrack = nil
	self._moveConnection = nil
	self._stoppedConnection = nil
	self._onFinished = nil
	self._tracks = {}  -- { [animKey] = AnimationTrack }
	
	return self
end

-- Get emote folder from Assets
function EmoteBase:_getEmoteFolder(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	
	local animations = assets:FindFirstChild("Animations")
	if not animations then
		return nil
	end
	
	local emotes = animations:FindFirstChild("Emotes")
	if not emotes then
		return nil
	end
	
	return emotes:FindFirstChild(self._id)
end

-- Get animation instance from emote folder
function EmoteBase:_getAnimation(): Animation?
	local emoteFolder = self:_getEmoteFolder()
	if not emoteFolder then
		return nil
	end
	
	local animFolder = emoteFolder:FindFirstChild("Animation")
	if not animFolder then
		return nil
	end
	
	-- Return first Animation found
	for _, child in animFolder:GetChildren() do
		if child:IsA("Animation") then
			return child
		end
	end
	
	return nil
end

-- Get sound instance from emote folder
function EmoteBase:_getSound(): Sound?
	local emoteFolder = self:_getEmoteFolder()
	if not emoteFolder then
		return nil
	end
	
	local soundFolder = emoteFolder:FindFirstChild("Sound")
	if not soundFolder then
		return nil
	end
	
	-- Return first Sound found
	for _, child in soundFolder:GetChildren() do
		if child:IsA("Sound") then
			return child
		end
	end
	
	return nil
end

-- Get emote settings merged with defaults
function EmoteBase:_getSettings(): { [string]: any }
	local defaults = EmoteConfig.Defaults
	local data = self._data or {}
	
	return {
		Loopable = data.Loopable ~= nil and data.Loopable or defaults.Loopable,
		AllowMove = data.AllowMove ~= nil and data.AllowMove or defaults.AllowMove,
		Speed = data.Speed or defaults.Speed,
		FadeInTime = data.FadeInTime or defaults.FadeInTime,
		FadeOutTime = data.FadeOutTime or defaults.FadeOutTime,
		Priority = data.Priority or defaults.Priority,
	}
end

-- Get the Animator from the rig
function EmoteBase:_getAnimator(): Animator?
	if not self._rig then
		return nil
	end
	
	local humanoid = self._rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	
	return animator
end

-- Play an animation by key from the Animations table
-- Returns the AnimationTrack or nil if failed
function EmoteBase:PlayAnimation(animKey: string, fadeTime: number?, priority: Enum.AnimationPriority?): AnimationTrack?
	-- Get animation ID from class's Animations table
	local emoteClass = getmetatable(self)
	local animations = emoteClass and emoteClass.Animations
	if not animations then
		warn("[EmoteBase] No Animations table found for", self._id)
		return nil
	end
	
	local animId = animations[animKey]
	if not animId then
		warn("[EmoteBase] Animation key not found:", animKey, "for", self._id)
		return nil
	end
	
	-- Normalize animation ID
	if not animId:match("^rbxassetid://") then
		animId = "rbxassetid://" .. animId
	end
	
	-- Get animator
	local animator = self:_getAnimator()
	if not animator then
		warn("[EmoteBase] No animator found for", self._id)
		return nil
	end
	
	-- Stop existing track for this key
	if self._tracks[animKey] then
		self._tracks[animKey]:Stop(fadeTime or 0.2)
	end
	
	-- Create and load animation
	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	
	local track = animator:LoadAnimation(animation)
	track.Priority = priority or Enum.AnimationPriority.Action
	track.Looped = self._data.Loopable or false
	track:Play(fadeTime or 0.2)
	
	-- Adjust speed if set
	local speed = self._data.Speed or 1
	if speed ~= 1 then
		track:AdjustSpeed(speed)
	end
	
	-- Store track
	self._tracks[animKey] = track
	
	return track
end

-- Stop a specific animation by key
function EmoteBase:StopAnimation(animKey: string, fadeTime: number?)
	local track = self._tracks[animKey]
	if track and track.IsPlaying then
		track:Stop(fadeTime or 0.2)
	end
	self._tracks[animKey] = nil
end

-- Stop all playing animations
function EmoteBase:StopAllAnimations(fadeTime: number?)
	for animKey, track in self._tracks do
		if track and track.IsPlaying then
			track:Stop(fadeTime or 0.2)
		end
	end
	self._tracks = {}
end

-- Get a playing animation track by key
function EmoteBase:GetTrack(animKey: string): AnimationTrack?
	return self._tracks[animKey]
end

-- Watch for movement to cancel emote
function EmoteBase:_watchMovement()
	if self._moveConnection then
		self._moveConnection:Disconnect()
		self._moveConnection = nil
	end
	
	if not self._rig then
		return
	end
	
	local humanoid = self._rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	
	self._moveConnection = humanoid.Running:Connect(function(speed)
		if speed > 0.5 then
			self:stop()
		end
	end)
end

-- Start the emote
function EmoteBase:start(): boolean
	if self._active then
		return true
	end
	
	self._active = true
	
	local settings = self:_getSettings()
	
	-- Setup movement cancellation if not allowed to move
	if not settings.AllowMove then
		self:_watchMovement()
	end
	
	return true
end

-- Stop the emote
function EmoteBase:stop(): boolean
	if not self._active then
		return true
	end
	
	self._active = false
	
	-- Disconnect movement watcher
	if self._moveConnection then
		self._moveConnection:Disconnect()
		self._moveConnection = nil
	end
	
	-- Disconnect stopped listener
	if self._stoppedConnection then
		self._stoppedConnection:Disconnect()
		self._stoppedConnection = nil
	end
	
	-- Fire finished callback
	if self._onFinished then
		task.spawn(self._onFinished)
	end
	
	return true
end

-- Alias for stop
EmoteBase.endEmote = EmoteBase.stop

-- Set callback for when emote finishes
function EmoteBase:onFinished(callback: () -> ())
	self._onFinished = callback
end

-- Get emote info
function EmoteBase:getInfo(): { id: string, displayName: string, rarity: string }
	return {
		id = self._id,
		displayName = self._data.DisplayName or self._id,
		rarity = self._data.Rarity or "Common",
	}
end

-- Check if emote is active
function EmoteBase:isActive(): boolean
	return self._active
end

-- Destroy the emote instance
function EmoteBase:destroy()
	self:stop()
	self:StopAllAnimations(0.1)
	
	self._rig = nil
	self._data = nil
	self._animation = nil
	self._sound = nil
	self._animationTrack = nil
	self._tracks = {}
	self._onFinished = nil
end

return EmoteBase
