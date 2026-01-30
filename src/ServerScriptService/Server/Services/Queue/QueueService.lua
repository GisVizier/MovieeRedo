--[[
	QueueService
	
	Server-side service for managing queue pads and matchmaking.
	
	Features:
	- Zone-based player detection on queue pads
	- Countdown management when teams are ready
	- Automatic match creation when countdown completes
	
	API:
	- QueueService:GetQueuedPlayers() -> { Team1 = {}, Team2 = {} }
	- QueueService:IsPlayerQueued(player) -> boolean
	- QueueService:ForceStartMatch() -> void
	- QueueService:SetMode(modeId) -> void
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))

local QueueService = {}

function QueueService:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Zone data: { [pad] = { pad, team, center, size, currentPlayer } }
	self._zones = {}

	-- Queued players by team: { Team1 = { player1 }, Team2 = { player2 } }
	self._queuedPlayers = {
		Team1 = {},
		Team2 = {},
	}

	-- Countdown state
	self._countdownActive = false
	self._countdownThread = nil
	self._countdownRemaining = 0

	-- Current mode (Duel, TwoVTwo, etc.)
	self._currentMode = MatchmakingConfig.DefaultMode

	-- Zone check connection
	self._zoneCheckConnection = nil
	self._lastZoneCheck = 0

	self:_setupZones()
	self:_setupPlayerRemoving()
end

function QueueService:Start()
	self:_startZoneChecking()
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function QueueService:GetQueuedPlayers()
	return {
		Team1 = table.clone(self._queuedPlayers.Team1),
		Team2 = table.clone(self._queuedPlayers.Team2),
	}
end

function QueueService:IsPlayerQueued(player)
	for _, teamPlayers in self._queuedPlayers do
		if table.find(teamPlayers, player) then
			return true
		end
	end
	return false
end

function QueueService:ForceStartMatch()
	if self._countdownActive then
		self:_cancelCountdown()
	end
	self:_startMatch()
end

function QueueService:SetMode(modeId)
	if MatchmakingConfig.Modes[modeId] then
		self._currentMode = modeId
	end
end

--------------------------------------------------------------------------------
-- ZONE SETUP
--------------------------------------------------------------------------------

function QueueService:_setupZones()
	local padTag = MatchmakingConfig.Queue.PadTag
	local defaultSize = MatchmakingConfig.Queue.DefaultZoneSize

	for _, pad in CollectionService:GetTagged(padTag) do
		self:_registerPad(pad)
	end

	-- Listen for new pads added at runtime
	CollectionService:GetInstanceAddedSignal(padTag):Connect(function(pad)
		self:_registerPad(pad)
	end)

	CollectionService:GetInstanceRemovedSignal(padTag):Connect(function(pad)
		self._zones[pad] = nil
	end)
end

function QueueService:_registerPad(pad)
	local team = pad:GetAttribute("Team") or "Team1"
	local zoneSize = pad:GetAttribute("ZoneSize") or MatchmakingConfig.Queue.DefaultZoneSize

	self._zones[pad] = {
		pad = pad,
		team = team,
		size = zoneSize,
		currentPlayer = nil,
	}

	-- Set initial visual
	self:_updatePadVisual(pad, "empty")
end

function QueueService:_setupPlayerRemoving()
	Players.PlayerRemoving:Connect(function(player)
		self:_removePlayerFromQueue(player)
	end)
end

--------------------------------------------------------------------------------
-- ZONE CHECKING
--------------------------------------------------------------------------------

function QueueService:_startZoneChecking()
	local interval = MatchmakingConfig.Queue.ZoneCheckInterval

	self._zoneCheckConnection = RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - self._lastZoneCheck >= interval then
			self._lastZoneCheck = now
			self:_checkAllZones()
		end
	end)
end

function QueueService:_checkAllZones()
	for pad, zoneData in self._zones do
		if not pad.Parent then
			continue
		end

		local playersInZone = self:_getPlayersInZone(zoneData)
		local newPlayer = playersInZone[1] -- First player in zone

		if newPlayer ~= zoneData.currentPlayer then
			local oldPlayer = zoneData.currentPlayer
			zoneData.currentPlayer = newPlayer

			if oldPlayer then
				self:_onPlayerExitZone(zoneData, oldPlayer)
			end
			if newPlayer then
				self:_onPlayerEnterZone(zoneData, newPlayer)
			end
		end
	end
end

function QueueService:_getPlayersInZone(zoneData)
	local pad = zoneData.pad
	local center = pad.Position
	local size = zoneData.size

	local playersInZone = {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		local playerPos = rootPart.Position
		local halfSize = size / 2

		-- Simple AABB check
		local inX = math.abs(playerPos.X - center.X) <= halfSize.X
		local inY = math.abs(playerPos.Y - center.Y) <= halfSize.Y
		local inZ = math.abs(playerPos.Z - center.Z) <= halfSize.Z

		if inX and inY and inZ then
			table.insert(playersInZone, player)
		end
	end

	return playersInZone
end

--------------------------------------------------------------------------------
-- ZONE EVENTS
--------------------------------------------------------------------------------

function QueueService:_onPlayerEnterZone(zoneData, player)
	local team = zoneData.team

	-- Remove from other team if somehow there
	self:_removePlayerFromQueue(player)

	-- Add to this team
	table.insert(self._queuedPlayers[team], player)

	-- Update pad visual
	self:_updatePadVisual(zoneData.pad, "occupied")

	-- Notify clients
	self._net:FireAllClients("QueuePadUpdate", {
		padId = zoneData.pad.Name,
		team = team,
		occupied = true,
		playerId = player.UserId,
	})

	-- Check if we can start countdown
	self:_checkQueueReady()
end

function QueueService:_onPlayerExitZone(zoneData, player)
	local team = zoneData.team

	-- Remove from queue
	local index = table.find(self._queuedPlayers[team], player)
	if index then
		table.remove(self._queuedPlayers[team], index)
	end

	-- Update pad visual
	self:_updatePadVisual(zoneData.pad, "empty")

	-- Notify clients
	self._net:FireAllClients("QueuePadUpdate", {
		padId = zoneData.pad.Name,
		team = team,
		occupied = false,
		playerId = nil,
	})

	-- Cancel countdown if active
	if self._countdownActive then
		self:_cancelCountdown()
	end
end

function QueueService:_removePlayerFromQueue(player)
	for team, teamPlayers in self._queuedPlayers do
		local index = table.find(teamPlayers, player)
		if index then
			table.remove(teamPlayers, index)

			-- Find and update the pad they were on
			for _, zoneData in self._zones do
				if zoneData.currentPlayer == player then
					zoneData.currentPlayer = nil
					self:_updatePadVisual(zoneData.pad, "empty")

					self._net:FireAllClients("QueuePadUpdate", {
						padId = zoneData.pad.Name,
						team = team,
						occupied = false,
						playerId = nil,
					})
				end
			end

			-- Cancel countdown if active
			if self._countdownActive then
				self:_cancelCountdown()
			end

			break
		end
	end
end

--------------------------------------------------------------------------------
-- QUEUE READY CHECK
--------------------------------------------------------------------------------

function QueueService:_checkQueueReady()
	local mode = MatchmakingConfig.getMode(self._currentMode)
	if not mode or not mode.hasTeams then
		return -- Training mode doesn't use queue
	end

	local required = mode.playersPerTeam or 1

	local team1Count = #self._queuedPlayers.Team1
	local team2Count = #self._queuedPlayers.Team2

	if team1Count >= required and team2Count >= required then
		if not self._countdownActive then
			self:_startCountdown()
		end
	end
end

--------------------------------------------------------------------------------
-- COUNTDOWN
--------------------------------------------------------------------------------

function QueueService:_startCountdown()
	if self._countdownActive then
		return
	end

	self._countdownActive = true
	self._countdownRemaining = MatchmakingConfig.Queue.CountdownDuration

	-- Update pad visuals
	for _, zoneData in self._zones do
		if zoneData.currentPlayer then
			self:_updatePadVisual(zoneData.pad, "countdown")
		end
	end

	-- Notify clients
	self._net:FireAllClients("QueueCountdownStart", {
		duration = self._countdownRemaining,
	})

	-- Start countdown thread
	self._countdownThread = task.spawn(function()
		while self._countdownActive and self._countdownRemaining > 0 do
			task.wait(1)

			if not self._countdownActive then
				break
			end

			self._countdownRemaining = self._countdownRemaining - 1

			self._net:FireAllClients("QueueCountdownTick", {
				remaining = self._countdownRemaining,
			})
		end

		if self._countdownActive and self._countdownRemaining <= 0 then
			self:_onCountdownComplete()
		end
	end)
end

function QueueService:_cancelCountdown()
	if not self._countdownActive then
		return
	end

	self._countdownActive = false
	self._countdownRemaining = 0

	if self._countdownThread then
		task.cancel(self._countdownThread)
		self._countdownThread = nil
	end

	-- Reset pad visuals
	for _, zoneData in self._zones do
		if zoneData.currentPlayer then
			self:_updatePadVisual(zoneData.pad, "occupied")
		else
			self:_updatePadVisual(zoneData.pad, "empty")
		end
	end

	-- Notify clients
	self._net:FireAllClients("QueueCountdownCancel", {})
end

function QueueService:_onCountdownComplete()
	self._countdownActive = false
	self._countdownThread = nil

	-- Update pad visuals to ready
	for _, zoneData in self._zones do
		if zoneData.currentPlayer then
			self:_updatePadVisual(zoneData.pad, "ready")
		end
	end

	-- Start the match
	self:_startMatch()
end

--------------------------------------------------------------------------------
-- MATCH START
--------------------------------------------------------------------------------

function QueueService:_startMatch()
	local mode = MatchmakingConfig.getMode(self._currentMode)
	if not mode then
		warn("[QueueService] Invalid mode:", self._currentMode)
		return
	end

	local required = mode.playersPerTeam or 1

	-- Get the players for each team (up to required count)
	local team1 = {}
	local team2 = {}

	for i = 1, math.min(required, #self._queuedPlayers.Team1) do
		local player = self._queuedPlayers.Team1[i]
		table.insert(team1, player.UserId)
	end

	for i = 1, math.min(required, #self._queuedPlayers.Team2) do
		local player = self._queuedPlayers.Team2[i]
		table.insert(team2, player.UserId)
	end

	-- Notify clients that match is ready
	self._net:FireAllClients("QueueMatchReady", {
		team1 = team1,
		team2 = team2,
		mode = self._currentMode,
	})

	-- Hand off to RoundService
	local roundService = self._registry:TryGet("Round")
	if roundService then
		roundService:StartMatch({
			mode = self._currentMode,
			team1 = team1,
			team2 = team2,
		})
	end

	-- Clear queue (players are now in match)
	self:_clearQueue()
end

function QueueService:_clearQueue()
	-- Reset all zones
	for _, zoneData in self._zones do
		zoneData.currentPlayer = nil
		self:_updatePadVisual(zoneData.pad, "empty")
	end

	-- Clear queued players
	self._queuedPlayers.Team1 = {}
	self._queuedPlayers.Team2 = {}
end

--------------------------------------------------------------------------------
-- PAD VISUALS
--------------------------------------------------------------------------------

function QueueService:_updatePadVisual(pad, state)
	local colors = MatchmakingConfig.PadVisuals
	local color

	if state == "empty" then
		color = colors.EmptyColor
	elseif state == "occupied" then
		color = colors.OccupiedColor
	elseif state == "countdown" then
		color = colors.CountdownColor
	elseif state == "ready" then
		color = colors.ReadyColor
	else
		color = colors.EmptyColor
	end

	-- Update the pad color
	if pad:IsA("BasePart") then
		pad.Color = color
	end

	-- Also check for a child part named "Visual" or "Surface"
	local visualPart = pad:FindFirstChild("Visual") or pad:FindFirstChild("Surface")
	if visualPart and visualPart:IsA("BasePart") then
		visualPart.Color = color
	end
end

return QueueService
