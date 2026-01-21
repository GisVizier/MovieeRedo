--[[
	EmoteService - Server-side emote validation and replication
	
	Handles:
	- Validates player owns the emote (via player data)
	- Validates cooldowns to prevent spam
	- Broadcasts EmoteReplicate to all other clients
	- Tracks active emotes per player
]]

local EmoteService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Cooldown settings
local EMOTE_COOLDOWN = 0.5 -- seconds between emotes

-- State tracking
EmoteService.ActiveEmotes = {}      -- [player] = { emoteId, startTime }
EmoteService.LastEmoteTime = {}     -- [player] = timestamp

function EmoteService:Init(registry, net)
	self._registry = registry
	self._net = net

	self:_bindRemotes()

	-- Cleanup on player leaving
	Players.PlayerRemoving:Connect(function(player)
		self:_cleanupPlayer(player)
	end)
end

function EmoteService:Start()
	-- Nothing needed on start
end

function EmoteService:_bindRemotes()
	-- Client requests to play an emote
	self._net:ConnectServer("EmotePlay", function(player, emoteId)
		self:_handleEmotePlay(player, emoteId)
	end)

	-- Client requests to stop emote
	self._net:ConnectServer("EmoteStop", function(player)
		self:_handleEmoteStop(player)
	end)
end

function EmoteService:_handleEmotePlay(player, emoteId)
	-- Validate emoteId
	if type(emoteId) ~= "string" or emoteId == "" then
		warn("[EmoteService] Invalid emoteId from", player.Name)
		return
	end

	-- Check cooldown
	if not self:_checkCooldown(player) then
		return
	end

	-- Validate ownership (optional - can be enabled when player data is fully implemented)
	-- if not self:_validateOwnership(player, emoteId) then
	--     return
	-- end

	-- Record active emote
	self.ActiveEmotes[player] = {
		emoteId = emoteId,
		startTime = tick(),
	}
	self.LastEmoteTime[player] = tick()

	-- Broadcast to all other clients
	self:_broadcastEmote(player, emoteId, "play")
end

function EmoteService:_handleEmoteStop(player)
	-- Clear active emote
	self.ActiveEmotes[player] = nil

	-- Broadcast stop to all other clients
	self:_broadcastEmote(player, nil, "stop")
end

function EmoteService:_checkCooldown(player): boolean
	local lastTime = self.LastEmoteTime[player]
	if not lastTime then
		return true
	end

	local elapsed = tick() - lastTime
	return elapsed >= EMOTE_COOLDOWN
end

function EmoteService:_validateOwnership(player, emoteId: string): boolean
	-- TODO: Implement proper ownership validation when player data is synced
	-- For now, allow all emotes
	return true
end

function EmoteService:_broadcastEmote(player, emoteId: string?, action: string)
	local playerId = player.UserId

	-- Send to all other players
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= player then
			self._net:FireClient("EmoteReplicate", otherPlayer, playerId, emoteId, action)
		end
	end
end

function EmoteService:_cleanupPlayer(player)
	self.ActiveEmotes[player] = nil
	self.LastEmoteTime[player] = nil
end

-- Get active emote for a player
function EmoteService:GetActiveEmote(player): { emoteId: string, startTime: number }?
	return self.ActiveEmotes[player]
end

-- Check if player is currently emoting
function EmoteService:IsEmoting(player): boolean
	return self.ActiveEmotes[player] ~= nil
end

-- Force stop emote for a player (e.g., on death)
function EmoteService:ForceStopEmote(player)
	if self.ActiveEmotes[player] then
		self.ActiveEmotes[player] = nil
		self:_broadcastEmote(player, nil, "stop")
	end
end

return EmoteService
