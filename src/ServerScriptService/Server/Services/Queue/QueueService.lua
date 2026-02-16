--[[
	QueueService
	
	Server-side service for managing queue pads and matchmaking.
	Supports multiple concurrent queues with per-pad team zones.
	
	Queue Pad Structure:
	- QueuePad (Model) [Tagged: "QueuePad"]
	  ├── Team1 (Model) - zone for first player
	  │   ├── Inner
	  │   └── Outer
	  └── Team2 (Model) - zone for second player
	      ├── Inner
	      └── Outer
	
	API:
	- QueueService:GetQueuedPlayers(padName) -> { Team1 = {}, Team2 = {} }
	- QueueService:IsPlayerQueued(player) -> boolean
	- QueueService:ForceStartMatch(padName) -> void
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("MatchmakingConfig"))

local QueueService = {}

-- DEBUG: Set to true to enable extensive logging
local DEBUG_ENABLED = false  -- Disable verbose server logging (detection works)
local DEBUG_INTERVAL = 10 -- Print debug summary every N seconds
local FORCE_ZONE_VISUALIZATION = true -- Always show zone boxes

local function debugPrint(...)
	if DEBUG_ENABLED then
	end
end

local function debugWarn(...)
	if DEBUG_ENABLED then
	end
end

function QueueService:Init(registry, net)
	debugPrint("=== QueueService:Init() CALLED ===")
	
	self._registry = registry
	self._net = net

	self._queues = {}

	self._zones = {}

	self._countdowns = {}

	self._zoneCheckConnection = nil
	self._lastZoneCheck = 0
	self._lastDebugPrint = 0

	self:_setupZones()
	self:_setupPlayerRemoving()
	
	debugPrint("=== QueueService:Init() COMPLETE ===")
end

function QueueService:Start()
	debugPrint("=== QueueService:Start() CALLED ===")
	self:_startZoneChecking()
	debugPrint("=== QueueService:Start() COMPLETE - Zone checking started ===")
end

function QueueService:GetQueuedPlayers(padName)
	local queue = self._queues[padName]
	if not queue then
		return { Team1 = {}, Team2 = {} }
	end

	return {
		Team1 = table.clone(queue.Team1),
		Team2 = table.clone(queue.Team2),
	}
end

function QueueService:IsPlayerQueued(player)
	for _, queue in self._queues do
		if table.find(queue.Team1, player) or table.find(queue.Team2, player) then
			return true
		end
	end
	return false
end

function QueueService:ForceStartMatch(padName)
	local countdown = self._countdowns[padName]
	if countdown and countdown.active then
		self:_cancelCountdown(padName)
	end
	self:_startMatch(padName)
end

function QueueService:_setupZones()
	local padTag = MatchmakingConfig.Queue.PadTag
	local defaultSize = MatchmakingConfig.Queue.DefaultZoneSize

	debugPrint("Setting up zones with tag:", padTag)
	debugPrint("Default zone size:", defaultSize)

	local taggedPads = CollectionService:GetTagged(padTag)
	debugPrint("Found", #taggedPads, "pads with tag '" .. padTag .. "'")
	
	if #taggedPads == 0 then
		debugWarn("NO PADS FOUND! Make sure your queue pads are tagged with '" .. padTag .. "'")
	end

	for i, pad in taggedPads do
		debugPrint("  Pad", i, ":", pad.Name, "| Path:", pad:GetFullName())
		self:_registerPad(pad)
	end

	CollectionService:GetInstanceAddedSignal(padTag):Connect(function(pad)
		debugPrint("NEW PAD ADDED:", pad.Name, "| Path:", pad:GetFullName())
		self:_registerPad(pad)
	end)

	CollectionService:GetInstanceRemovedSignal(padTag):Connect(function(pad)
		debugPrint("PAD REMOVED:", pad.Name)
		self:_unregisterPad(pad)
	end)
	
	-- Print summary of registered zones
	local zoneCount = 0
	for _ in self._zones do
		zoneCount = zoneCount + 1
	end
	debugPrint("Total zones registered:", zoneCount)
end

function QueueService:_registerPad(pad)
	local padName = pad.Name
	local modeId = MatchmakingConfig.getModeFromPadName(padName)
	local modeConfig = MatchmakingConfig.getMode(modeId)

	debugPrint("--- Registering pad:", padName, "---")
	debugPrint("  Mode ID:", modeId)
	debugPrint("  Mode config:", modeConfig and modeConfig.name or "NIL")

	self._queues[padName] = {
		Team1 = {},
		Team2 = {},
	}

	self._countdowns[padName] = {
		active = false,
		thread = nil,
		remaining = 0,
	}

	local defaultSize = MatchmakingConfig.Queue.DefaultZoneSize

	local team1Model = pad:FindFirstChild("Team1")
	local team2Model = pad:FindFirstChild("Team2")
	
	debugPrint("  Team1 model found:", team1Model ~= nil, team1Model and team1Model.ClassName or "N/A")
	debugPrint("  Team2 model found:", team2Model ~= nil, team2Model and team2Model.ClassName or "N/A")

	if team1Model then
		local zonePart = self:_getZonePart(team1Model)
		debugPrint("  Team1 zonePart:", zonePart and zonePart.Name or "NIL", zonePart and zonePart.ClassName or "N/A")
		if zonePart then
			local zoneSize = zonePart:GetAttribute("ZoneSize") or defaultSize
			debugPrint("  Team1 zone size:", zoneSize)
			debugPrint("  Team1 zone position:", zonePart.Position)
			debugPrint("  Team1 zone CFrame:", zonePart.CFrame)
			self._zones[zonePart] = {
				pad = pad,
				padName = padName,
				team = "Team1",
				zonePart = zonePart,
				size = zoneSize,
				currentPlayer = nil,
				modeId = modeId,
			}
			self:_updatePadVisual(zonePart, "empty")
			self:_createZoneVisualizer(zonePart, zoneSize)
		else
			debugWarn("  FAILED to find zonePart for Team1!")
		end
	end

	if team2Model then
		local zonePart = self:_getZonePart(team2Model)
		debugPrint("  Team2 zonePart:", zonePart and zonePart.Name or "NIL", zonePart and zonePart.ClassName or "N/A")
		if zonePart then
			local zoneSize = zonePart:GetAttribute("ZoneSize") or defaultSize
			debugPrint("  Team2 zone size:", zoneSize)
			debugPrint("  Team2 zone position:", zonePart.Position)
			debugPrint("  Team2 zone CFrame:", zonePart.CFrame)
			self._zones[zonePart] = {
				pad = pad,
				padName = padName,
				team = "Team2",
				zonePart = zonePart,
				size = zoneSize,
				currentPlayer = nil,
				modeId = modeId,
			}
			self:_updatePadVisual(zonePart, "empty")
			self:_createZoneVisualizer(zonePart, zoneSize)
		else
			debugWarn("  FAILED to find zonePart for Team2!")
		end
	end

	if not team1Model and not team2Model then
		debugWarn("  No Team1 or Team2 found, using pad itself as zone")
		local zoneSize = pad:GetAttribute("ZoneSize") or defaultSize
		local zonePart = self:_getZonePart(pad)
		if zonePart then
			self._zones[zonePart] = {
				pad = pad,
				padName = padName,
				team = "Team1",
				zonePart = zonePart,
				size = zoneSize,
				currentPlayer = nil,
				modeId = modeId,
			}
			self:_updatePadVisual(zonePart, "empty")
			self:_createZoneVisualizer(zonePart, zoneSize)
		end
	end
	
	debugPrint("--- Pad registration complete:", padName, "---")
end

function QueueService:_createZoneVisualizer(zonePart, zoneSize)
	local debugConfig = MatchmakingConfig.Queue.Debug or {}
	
	-- Force visualization if debug flag is set
	if not FORCE_ZONE_VISUALIZATION then
		if not debugConfig.ShowZones then
			return
		end
	end
	
	debugPrint("Creating zone visualizer for:", zonePart.Name, "Size:", zoneSize)

	local existing = zonePart:FindFirstChild("QueueZoneVisualizer")
	if existing and existing:IsA("BoxHandleAdornment") then
		existing.Size = zoneSize
		existing.Color3 = debugConfig.ZoneColor or Color3.fromRGB(0, 255, 0)
		existing.Transparency = debugConfig.ZoneTransparency or 0.5
		debugPrint("  Updated existing visualizer")
		return
	end

	local adornment = Instance.new("BoxHandleAdornment")
	adornment.Name = "QueueZoneVisualizer"
	adornment.Adornee = zonePart
	adornment.AlwaysOnTop = true
	adornment.ZIndex = 10
	adornment.Size = zoneSize
	adornment.Color3 = debugConfig.ZoneColor or Color3.fromRGB(0, 255, 0)
	adornment.Transparency = debugConfig.ZoneTransparency or 0.5
	adornment.Parent = zonePart
	debugPrint("  Created new visualizer")
end

function QueueService:_getZonePart(model)
	debugPrint("_getZonePart called for:", model.Name, "Class:", model.ClassName)
	
	if model:IsA("BasePart") then
		debugPrint("  Model is a BasePart, returning it directly")
		return model
	end

	local inner = model:FindFirstChild("Inner")
	debugPrint("  Looking for 'Inner' child:", inner ~= nil)
	
	if inner then
		debugPrint("  Inner found, class:", inner.ClassName)
		if inner:IsA("BasePart") then
			debugPrint("  Inner is BasePart, returning it")
			return inner
		elseif inner:IsA("Model") then
			debugPrint("  Inner is Model, searching descendants")
			for _, child in inner:GetDescendants() do
				if child:IsA("BasePart") then
					debugPrint("  Found BasePart in Inner:", child.Name)
					return child
				end
			end
		else
			-- Handle Folder or other container types
			debugPrint("  Inner is", inner.ClassName, "- searching children")
			for _, child in inner:GetChildren() do
				if child:IsA("BasePart") then
					debugPrint("  Found BasePart child of Inner:", child.Name)
					return child
				end
			end
		end
	end

	debugPrint("  Falling back to searching all descendants")
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			debugPrint("  Found BasePart descendant:", child.Name)
			return child
		end
	end

	debugWarn("  NO BasePart found in model:", model.Name)
	debugWarn("  Children:", table.concat(
		(function()
			local names = {}
			for _, child in model:GetChildren() do
				table.insert(names, child.Name .. "(" .. child.ClassName .. ")")
			end
			return names
		end)(), ", "
	))
	return nil
end

function QueueService:_unregisterPad(pad)
	local padName = pad.Name

	self._queues[padName] = nil

	if self._countdowns[padName] then
		if self._countdowns[padName].thread then
			task.cancel(self._countdowns[padName].thread)
		end
		self._countdowns[padName] = nil
	end

	for zonePart, zoneData in self._zones do
		if zoneData.pad == pad then
			self._zones[zonePart] = nil
		end
	end
end

function QueueService:_setupPlayerRemoving()
	Players.PlayerRemoving:Connect(function(player)
		self:_removePlayerFromAllQueues(player)
	end)
end

function QueueService:_startZoneChecking()
	local interval = MatchmakingConfig.Queue.ZoneCheckInterval
	debugPrint("Starting zone checking with interval:", interval, "seconds")

	self._zoneCheckConnection = RunService.Heartbeat:Connect(function()
		local now = tick()
		if now - self._lastZoneCheck >= interval then
			self._lastZoneCheck = now
			self:_checkAllZones()
		end
		
		-- Periodic debug summary
		if DEBUG_ENABLED and now - self._lastDebugPrint >= DEBUG_INTERVAL then
			self._lastDebugPrint = now
			self:_printDebugSummary()
		end
	end)
end

function QueueService:_printDebugSummary()
	local zoneCount = 0
	local occupiedCount = 0
	for _, zoneData in self._zones do
		zoneCount = zoneCount + 1
		if zoneData.currentPlayer then
			occupiedCount = occupiedCount + 1
		end
	end
	
	local playerCount = #Players:GetPlayers()
	
	
	-- Check each player's position relative to zones
	for _, player in Players:GetPlayers() do
		local playerPosition = self:_getPlayerPosition(player)
		if playerPosition then
			
			-- Check distance to each zone
			for zonePart, zoneData in self._zones do
				local dist = (playerPosition - zonePart.Position).Magnitude
				if dist < 100 then
				end
			end
		else
			-- Fallback: try to get from character parts directly
			local character = player.Character
			if character then
				local rootPart = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
				if rootPart then
				else
				end
			else
			end
		end
	end
	
	-- Print zone details
	for zonePart, zoneData in self._zones do
	end
end

function QueueService:_checkAllZones()
	local zoneCount = 0
	for _ in self._zones do
		zoneCount = zoneCount + 1
	end
	
	if zoneCount == 0 then
		-- Only warn once per session to avoid spam
		if not self._warnedNoZones then
			debugWarn("_checkAllZones: NO ZONES REGISTERED!")
			self._warnedNoZones = true
		end
		return
	end

	for zonePart, zoneData in self._zones do
		if not zonePart.Parent then
			debugWarn("Zone part has no parent:", zoneData.padName, zoneData.team)
			continue
		end

		local playersInZone = self:_getPlayersInZone(zoneData)
		local newPlayer = playersInZone[1]

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

function QueueService:_getPlayerPosition(player)
	-- First try to get position from ReplicationService (custom character system)
	local replicationService = self._registry:TryGet("ReplicationService")
	if replicationService and replicationService.PlayerStates then
		local playerData = replicationService.PlayerStates[player]
		if playerData and playerData.LastState and playerData.LastState.Position then
			return playerData.LastState.Position
		end
	end
	
	-- Fallback to reading from character parts (for standard characters)
	local character = player.Character
	if character then
		local rootPart = character:FindFirstChild("Root") or character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			return rootPart.Position
		end
	end
	
	return nil
end

function QueueService:_getPlayersInZone(zoneData)
	local zonePart = zoneData.zonePart
	local size = zoneData.size

	local playersInZone = {}
	local halfSize = size / 2
	local verticalTolerance = MatchmakingConfig.Queue.VerticalTolerance or halfSize.Y

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			-- debugPrint("Player", player.Name, "has no character")
			continue
		end

		-- Get player position from ReplicationService or fallback to character parts
		local playerPosition = self:_getPlayerPosition(player)
		if not playerPosition then
			if not self._warnedNoPosition then
				debugWarn("Player", player.Name, "has no position (no ReplicationService data or Root/HumanoidRootPart)")
				self._warnedNoPosition = true
			end
			continue
		end

		local localPos = zonePart.CFrame:PointToObjectSpace(playerPosition)

		local inX = math.abs(localPos.X) <= halfSize.X
		local inZ = math.abs(localPos.Z) <= halfSize.Z
		local inY = math.abs(localPos.Y) <= verticalTolerance
		
		-- Detailed position check logging (only when close to zone)
		local distToCenter = (playerPosition - zonePart.Position).Magnitude
		if distToCenter < 50 then -- Only log if within 50 studs
			debugPrint("Player", player.Name, "near zone", zoneData.padName, zoneData.team)
			debugPrint("  Player world pos:", playerPosition, "(from ReplicationService)")
			debugPrint("  Zone world pos:", zonePart.Position)
			debugPrint("  Local pos:", localPos)
			debugPrint("  Half size:", halfSize)
			debugPrint("  Vertical tolerance:", verticalTolerance)
			debugPrint("  inX:", inX, "(|" .. math.abs(localPos.X) .. "| <= " .. halfSize.X .. ")")
			debugPrint("  inZ:", inZ, "(|" .. math.abs(localPos.Z) .. "| <= " .. halfSize.Z .. ")")
			debugPrint("  inY:", inY, "(|" .. math.abs(localPos.Y) .. "| <= " .. verticalTolerance .. ")")
		end

		if inX and inZ and inY then
			local inMatch = self:_isPlayerInMatch(player)
			debugPrint("Player", player.Name, "IS IN ZONE", zoneData.padName, zoneData.team, "| inMatch:", inMatch)
			if not inMatch then
				table.insert(playersInZone, player)
				break
			else
				debugPrint("  SKIPPED - player is in match")
			end
		end
	end

	return playersInZone
end

function QueueService:_isPlayerInMatch(player)
	local matchManager = self._registry:TryGet("MatchManager")
	if matchManager then
		local match = matchManager:GetMatchForPlayer(player)
		if match then
			debugPrint("Player", player.Name, "is in match:", match.matchId or "unknown")
		end
		return match ~= nil
	end
	return false
end

function QueueService:_onPlayerEnterZone(zoneData, player)
	local padName = zoneData.padName
	local team = zoneData.team


	self:_removePlayerFromAllQueues(player)

	local queue = self._queues[padName]
	if queue then
		table.insert(queue[team], player)
	end

	self:_updatePadVisual(zoneData.zonePart, "occupied")

	self._net:FireAllClients("QueuePadUpdate", {
		padName = padName,
		team = team,
		occupied = true,
		playerId = player.UserId,
	})

	self:_checkQueueReady(padName)
end

function QueueService:_onPlayerExitZone(zoneData, player)
	local padName = zoneData.padName
	local team = zoneData.team


	local queue = self._queues[padName]
	if queue then
		local index = table.find(queue[team], player)
		if index then
			table.remove(queue[team], index)
		end
	end

	self:_updatePadVisual(zoneData.zonePart, "empty")

	self._net:FireAllClients("QueuePadUpdate", {
		padName = padName,
		team = team,
		occupied = false,
		playerId = nil,
	})

	local countdown = self._countdowns[padName]
	if countdown and countdown.active then
		self:_cancelCountdown(padName)
	end
end

function QueueService:_removePlayerFromAllQueues(player)
	for padName, queue in self._queues do
		for teamName, teamPlayers in queue do
			local index = table.find(teamPlayers, player)
			if index then
				table.remove(teamPlayers, index)

				for zonePart, zoneData in self._zones do
					if zoneData.padName == padName and zoneData.team == teamName and zoneData.currentPlayer == player then
						zoneData.currentPlayer = nil
						self:_updatePadVisual(zonePart, "empty")

						self._net:FireAllClients("QueuePadUpdate", {
							padName = padName,
							team = teamName,
							occupied = false,
							playerId = nil,
						})
					end
				end

				local countdown = self._countdowns[padName]
				if countdown and countdown.active then
					self:_cancelCountdown(padName)
				end
			end
		end
	end
end

function QueueService:_checkQueueReady(padName)
	local queue = self._queues[padName]
	if not queue then
		return
	end

	local modeId = MatchmakingConfig.getModeFromPadName(padName)
	local mode = MatchmakingConfig.getMode(modeId)

	if not mode or not mode.hasTeams then
		return
	end

	local required = mode.playersPerTeam or 1

	local team1Count = #queue.Team1
	local team2Count = #queue.Team2

	if team1Count >= required and team2Count >= required then
		local countdown = self._countdowns[padName]
		if not countdown.active then
			self:_startCountdown(padName)
		end
	end
end

function QueueService:_startCountdown(padName)
	local countdown = self._countdowns[padName]
	if countdown.active then
		return
	end

	countdown.active = true
	countdown.remaining = MatchmakingConfig.Queue.CountdownDuration

	for zonePart, zoneData in self._zones do
		if zoneData.padName == padName and zoneData.currentPlayer then
			self:_updatePadVisual(zonePart, "countdown")
		end
	end

	self._net:FireAllClients("QueueCountdownStart", {
		padName = padName,
		duration = countdown.remaining,
	})

	countdown.thread = task.spawn(function()
		while countdown.active and countdown.remaining > 0 do
			task.wait(1)

			if not countdown.active then
				break
			end

			countdown.remaining = countdown.remaining - 1

			self._net:FireAllClients("QueueCountdownTick", {
				padName = padName,
				remaining = countdown.remaining,
			})
		end

		if countdown.active and countdown.remaining <= 0 then
			self:_onCountdownComplete(padName)
		end
	end)
end

function QueueService:_cancelCountdown(padName)
	local countdown = self._countdowns[padName]
	if not countdown or not countdown.active then
		return
	end

	countdown.active = false
	countdown.remaining = 0

	if countdown.thread then
		task.cancel(countdown.thread)
		countdown.thread = nil
	end

	for zonePart, zoneData in self._zones do
		if zoneData.padName == padName then
			if zoneData.currentPlayer then
				self:_updatePadVisual(zonePart, "occupied")
			else
				self:_updatePadVisual(zonePart, "empty")
			end
		end
	end

	self._net:FireAllClients("QueueCountdownCancel", {
		padName = padName,
	})
end

function QueueService:_onCountdownComplete(padName)
	local countdown = self._countdowns[padName]
	countdown.active = false
	countdown.thread = nil

	for zonePart, zoneData in self._zones do
		if zoneData.padName == padName and zoneData.currentPlayer then
			self:_updatePadVisual(zonePart, "ready")
		end
	end

	self:_startMatch(padName)
end

function QueueService:_startMatch(padName)
	local queue = self._queues[padName]
	if not queue then
		return
	end

	local modeId = MatchmakingConfig.getModeFromPadName(padName)
	local mode = MatchmakingConfig.getMode(modeId)

	if not mode then
		return
	end

	local required = mode.playersPerTeam or 1

	local team1 = {}
	local team2 = {}

	for i = 1, math.min(required, #queue.Team1) do
		local player = queue.Team1[i]
		table.insert(team1, player.UserId)
	end

	for i = 1, math.min(required, #queue.Team2) do
		local player = queue.Team2[i]
		table.insert(team2, player.UserId)
	end

	self._net:FireAllClients("QueueMatchReady", {
		padName = padName,
		team1 = team1,
		team2 = team2,
		mode = modeId,
	})

	local matchManager = self._registry:TryGet("MatchManager")
	if matchManager then
		matchManager:CreateMatch({
			mode = modeId,
			team1 = team1,
			team2 = team2,
			mapId = MatchmakingConfig.DefaultMap,
		})
	else
	end

	self:_clearQueue(padName)
end

function QueueService:_clearQueue(padName)
	for zonePart, zoneData in self._zones do
		if zoneData.padName == padName then
			zoneData.currentPlayer = nil
			self:_updatePadVisual(zonePart, "empty")
		end
	end

	local queue = self._queues[padName]
	if queue then
		queue.Team1 = {}
		queue.Team2 = {}
	end
end

function QueueService:_updatePadVisual(zonePart, state)
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

	if zonePart:IsA("BasePart") then
		zonePart.Color = color
	end

	local parent = zonePart.Parent
	if parent then
		for _, child in parent:GetChildren() do
			if child:IsA("BasePart") and child ~= zonePart then
				child.Color = color
			end
		end
	end
end

return QueueService
