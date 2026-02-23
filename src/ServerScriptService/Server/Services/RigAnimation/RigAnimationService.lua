local RigAnimationService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local RigManager = require(Locations.Game:WaitForChild("Character"):WaitForChild("Rig"):WaitForChild("RigManager"))

RigAnimationService._net = nil
RigAnimationService._registry = nil
RigAnimationService._matchManager = nil

-- Server-side state tracking for late joiners.
-- [player] = { [animName] = { animName, Looped, Priority, FadeInTime, Speed } }
RigAnimationService._activeAnimations = {}

local function resolveMatchManager(self)
	local manager = self._matchManager
	if manager and manager.GetPlayersInMatch then
		return manager
	end
	if self._registry and self._registry.TryGet then
		local resolved = self._registry:TryGet("MatchManager")
		if resolved and resolved.GetPlayersInMatch then
			self._matchManager = resolved
			return resolved
		end
	end
	return nil
end

local function getMatchPlayers(self, sourcePlayer)
	local matchManager = resolveMatchManager(self)
	if matchManager then
		local ok, scoped = pcall(function()
			return matchManager:GetPlayersInMatch(sourcePlayer)
		end)
		if ok and type(scoped) == "table" then
			return scoped
		end
	end
	return Players:GetPlayers()
end

function RigAnimationService:Init(registry, net)
	self._registry = registry
	self._net = net

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
		self._activeAnimations[player] = nil
	end)
end

function RigAnimationService:Start()
end

function RigAnimationService:_broadcastToAll(sourcePlayer, payload)
	local recipients = getMatchPlayers(self, sourcePlayer)
	for _, target in ipairs(recipients) do
		if target and target.Parent then
			self._net:FireClient("RigAnimationBroadcast", target, payload)
		end
	end
end

function RigAnimationService:_handlePlay(player, data)
	local animName = data.animName
	if type(animName) ~= "string" or animName == "" then
		return
	end

	-- Validate rig exists
	local rig = RigManager:GetActiveRig(player)
	if not rig then
		return
	end

	local playerAnims = self._activeAnimations[player]
	if not playerAnims then
		playerAnims = {}
		self._activeAnimations[player] = playerAnims
	end

	-- Track StopOthers on the server state
	if data.StopOthers ~= false then
		local kept = {}
		playerAnims = kept
		self._activeAnimations[player] = playerAnims
	end

	playerAnims[animName] = {
		animName = animName,
		Looped = data.Looped == true,
		Priority = data.Priority,
		FadeInTime = data.FadeInTime,
		Speed = data.Speed,
	}

	self:_broadcastToAll(player, {
		action = "Play",
		userId = player.UserId,
		animName = animName,
		Looped = data.Looped,
		Priority = data.Priority,
		FadeInTime = data.FadeInTime,
		Speed = data.Speed,
		StopOthers = data.StopOthers,
	})
end

function RigAnimationService:_handleStop(player, data)
	local animName = data.animName
	if type(animName) ~= "string" or animName == "" then
		return
	end

	local playerAnims = self._activeAnimations[player]
	if playerAnims then
		playerAnims[animName] = nil
	end

	self:_broadcastToAll(player, {
		action = "Stop",
		userId = player.UserId,
		animName = animName,
		fadeOut = data.fadeOut,
	})
end

function RigAnimationService:_handleStopAll(player, data)
	self._activeAnimations[player] = {}

	self:_broadcastToAll(player, {
		action = "StopAll",
		userId = player.UserId,
		fadeOut = data.fadeOut,
	})
end

-- Called by CharacterService when a character spawns.
function RigAnimationService:OnCharacterSpawned(player, character)
	local rig = RigManager:CreateRig(player, character)
	return rig
end

-- Called by CharacterService when a character is removed.
function RigAnimationService:OnCharacterRemoving(player)
	self._activeAnimations[player] = nil
end

-- Send active looped animations to a late-joining client so they see current state.
function RigAnimationService:SendActiveAnimationsToPlayer(targetPlayer)
	if not targetPlayer or not targetPlayer.Parent then
		return
	end

	for sourcePlayer, anims in pairs(self._activeAnimations) do
		if sourcePlayer ~= targetPlayer and sourcePlayer.Parent and anims then
			for _, animData in pairs(anims) do
				if animData.Looped then
					self._net:FireClient("RigAnimationBroadcast", targetPlayer, {
						action = "Play",
						userId = sourcePlayer.UserId,
						animName = animData.animName,
						Looped = true,
						Priority = animData.Priority,
						FadeInTime = animData.FadeInTime,
						Speed = animData.Speed,
						StopOthers = false,
					})
				end
			end
		end
	end
end

return RigAnimationService
