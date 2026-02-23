local RigAnimationService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local RigManager = require(Locations.Game:WaitForChild("Character"):WaitForChild("Rig"):WaitForChild("RigManager"))

RigAnimationService._net = nil
RigAnimationService._registry = nil

-- [player] = { [animName] = { track: AnimationTrack, settings: table } }
RigAnimationService._activeAnimations = {}

-- [animName] = Animation instance (cached from Assets)
RigAnimationService._animationCache = {}

RigAnimationService._descriptionConns = {} -- [rig] = RBXScriptConnection

local function encodePriority(priorityValue)
	if typeof(priorityValue) == "EnumItem" then
		return priorityValue
	end
	if type(priorityValue) == "string" and priorityValue ~= "" then
		local ok, val = pcall(function()
			return Enum.AnimationPriority[priorityValue]
		end)
		if ok and val then
			return val
		end
	end
	return Enum.AnimationPriority.Action4
end

local function preloadAnimations(cache)
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

	local function loadFromFolder(folder)
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Animation") then
				local animId = child.AnimationId
				if animId and animId ~= "" then
					cache[animId] = child
					cache[child.Name] = child
				end
			elseif child:IsA("Folder") then
				loadFromFolder(child)
			end
		end
	end

	loadFromFolder(characterFolder)
end

local function getAnimatorForPlayer(player)
	local rig = RigManager:GetActiveRig(player)
	if not rig then
		return nil, nil
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, rig
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	return animator, rig
end

function RigAnimationService:Init(registry, net)
	self._registry = registry
	self._net = net

	preloadAnimations(self._animationCache)

	self._net:ConnectServer("RigAnimationRequest", function(player, data)
		if type(data) ~= "table" then
			return
		end

		local action = data.action
		if action == "Play" then
			self:_handlePlay(player, data)
		elseif action == "Stop" then
			self:_handleStop(player, data)
		elseif action == "StopAll" then
			self:_handleStopAll(player, data)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)
end

function RigAnimationService:Start()
end

function RigAnimationService:_handlePlay(player, data)
	local animName = data.animName
	if type(animName) ~= "string" or animName == "" then
		return
	end

	local animation = self._animationCache[animName]
	if not animation then
		if type(animName) == "string" and animName:match("^rbxassetid://") then
			animation = Instance.new("Animation")
			animation.AnimationId = animName
			self._animationCache[animName] = animation
		else
			return
		end
	end

	local animator, rig = getAnimatorForPlayer(player)
	if not animator then
		return
	end

	local playerAnims = self._activeAnimations[player]
	if not playerAnims then
		playerAnims = {}
		self._activeAnimations[player] = playerAnims
	end

	-- Stop other kit animations if requested
	if data.StopOthers ~= false then
		for name, entry in pairs(playerAnims) do
			if name ~= animName and entry.track and entry.track.IsPlaying then
				entry.track:Stop(0.1)
			end
		end
		if data.StopOthers ~= false then
			local kept = {}
			if playerAnims[animName] then
				kept[animName] = playerAnims[animName]
			end
			playerAnims = kept
			self._activeAnimations[player] = playerAnims
		end
	end

	-- Stop existing track for this name if already playing
	local existing = playerAnims[animName]
	if existing and existing.track then
		existing.track:Stop(0)
	end

	local track = animator:LoadAnimation(animation)
	if not track then
		return
	end

	local priority = encodePriority(data.Priority)
	local looped = data.Looped == true
	local fadeIn = tonumber(data.FadeInTime) or 0.15
	local speed = tonumber(data.Speed) or 1

	track.Priority = priority
	track.Looped = looped
	track:Play(fadeIn, 1, speed)

	playerAnims[animName] = {
		track = track,
		settings = {
			Looped = looped,
			Priority = priority,
			FadeInTime = fadeIn,
			Speed = speed,
		},
	}

	track.Stopped:Once(function()
		local anims = self._activeAnimations[player]
		if anims and anims[animName] and anims[animName].track == track then
			anims[animName] = nil
		end
	end)

	self:_bindDescriptionListener(player, rig)
end

function RigAnimationService:_handleStop(player, data)
	local animName = data.animName
	if type(animName) ~= "string" or animName == "" then
		return
	end

	local playerAnims = self._activeAnimations[player]
	if not playerAnims then
		return
	end

	local entry = playerAnims[animName]
	if entry and entry.track and entry.track.IsPlaying then
		entry.track:Stop(tonumber(data.fadeOut) or 0.1)
	end
	playerAnims[animName] = nil
end

function RigAnimationService:_handleStopAll(player, data)
	local playerAnims = self._activeAnimations[player]
	if not playerAnims then
		return
	end

	local fadeOut = tonumber(data.fadeOut) or 0.15
	for _, entry in pairs(playerAnims) do
		if entry.track and entry.track.IsPlaying then
			entry.track:Stop(fadeOut)
		end
	end
	self._activeAnimations[player] = {}
end

function RigAnimationService:_replayActiveAnimations(player)
	local playerAnims = self._activeAnimations[player]
	if not playerAnims or not next(playerAnims) then
		return
	end

	local animator = getAnimatorForPlayer(player)
	if not animator then
		return
	end

	for animName, entry in pairs(playerAnims) do
		local animation = self._animationCache[animName]
		if animation then
			local track = animator:LoadAnimation(animation)
			if track then
				local s = entry.settings
				track.Priority = s.Priority or Enum.AnimationPriority.Action4
				track.Looped = s.Looped or false
				track:Play(s.FadeInTime or 0.15, 1, s.Speed or 1)
				entry.track = track

				track.Stopped:Once(function()
					local anims = self._activeAnimations[player]
					if anims and anims[animName] and anims[animName].track == track then
						anims[animName] = nil
					end
				end)
			end
		end
	end
end

function RigAnimationService:_bindDescriptionListener(player, rig)
	if not rig then
		return
	end

	if self._descriptionConns[rig] then
		return
	end

	self._descriptionConns[rig] = rig:GetAttributeChangedSignal("DescriptionApplied"):Connect(function()
		task.defer(function()
			if player and player.Parent then
				self:_replayActiveAnimations(player)
			end
		end)
	end)

	rig.Destroying:Connect(function()
		local conn = self._descriptionConns[rig]
		if conn then
			conn:Disconnect()
			self._descriptionConns[rig] = nil
		end
	end)
end

function RigAnimationService:_cleanupPlayer(player)
	local playerAnims = self._activeAnimations[player]
	if playerAnims then
		for _, entry in pairs(playerAnims) do
			if entry.track and entry.track.IsPlaying then
				pcall(function()
					entry.track:Stop(0)
				end)
			end
		end
	end
	self._activeAnimations[player] = nil

	local rig = RigManager:GetActiveRig(player)
	if rig and self._descriptionConns[rig] then
		self._descriptionConns[rig]:Disconnect()
		self._descriptionConns[rig] = nil
	end
end

-- Called by CharacterService when a character spawns so the rig is created server-side.
function RigAnimationService:OnCharacterSpawned(player, character)
	local rig = RigManager:CreateRig(player, character)
	if rig then
		self:_bindDescriptionListener(player, rig)
	end
	return rig
end

-- Called by CharacterService when a character is removed.
function RigAnimationService:OnCharacterRemoving(player)
	self:_cleanupPlayer(player)
end

return RigAnimationService
