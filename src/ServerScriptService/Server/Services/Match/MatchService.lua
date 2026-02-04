local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local MatchService = {}

MatchService.RequiredPlayers = 1
MatchService.DefaultGamemodeId = "Duels"

function MatchService:Init(_registry, net)
	self._net = net
	self._registry = _registry

	self._ready = {} -- [userId] = true
	self._loadouts = {} -- [userId] = payload
	self._started = false
	self._pendingTrainingEntry = {} -- [userId] = { areaId, spawnPosition, spawnLookVector }

	self._net:ConnectServer("SubmitLoadout", function(player, payload)
		self:_onSubmitLoadout(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		self._ready[userId] = nil
		self._loadouts[userId] = nil
		self._pendingTrainingEntry[userId] = nil
	end)
end

-- Called by AreaTeleport when player needs to pick loadout before entering training
function MatchService:SetPendingTrainingEntry(player, entryData)
	if not player then return end
	self._pendingTrainingEntry[player.UserId] = entryData
end

function MatchService:GetPendingTrainingEntry(player)
	if not player then return nil end
	return self._pendingTrainingEntry[player.UserId]
end

function MatchService:ClearPendingTrainingEntry(player)
	if not player then return end
	self._pendingTrainingEntry[player.UserId] = nil
end

-- Called when player exits training to reset their state for re-entry
function MatchService:ClearPlayerState(player)
	if not player then return end
	local userId = player.UserId
	self._ready[userId] = nil
	self._loadouts[userId] = nil
	self._pendingTrainingEntry[userId] = nil
end

function MatchService:Start() end

function MatchService:_onSubmitLoadout(player, payload)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.loadout) ~= "table" then
		return
	end

	local userId = player.UserId
	self._loadouts[userId] = payload
	self._ready[userId] = true

	-- Server-side record for verification / later gameplay wiring.
	pcall(function()
		player:SetAttribute("SelectedLoadout", HttpService:JSONEncode(payload))
	end)

	-- Check if this player was entering training mode
	local pendingEntry = self._pendingTrainingEntry[userId]
	if pendingEntry then
		self._pendingTrainingEntry[userId] = nil
		
		-- Add player to training match
		local roundService = self._registry:TryGet("Round")
		if roundService then
			roundService:AddPlayer(player)
		end
		
		-- Fire training entry confirmed (player already teleported via gadget)
		self._net:FireClient("TrainingLoadoutConfirmed", player, {
			areaId = pendingEntry.areaId,
		})
		
		-- Set player state to Training
		player:SetAttribute("PlayerState", "Training")
		return
	end

	-- Regular competitive match flow
	if self._started then
		return
	end

	self:_tryStartMatch()
end

function MatchService:_tryStartMatch()
	if self._started then
		return
	end

	local players = Players:GetPlayers()
	if #players < self.RequiredPlayers then
		return
	end

	for _, p in ipairs(players) do
		if not self._ready[p.UserId] then
			return
		end
	end

	self._started = true

	local userIds = {}
	for _, p in ipairs(players) do
		table.insert(userIds, p.UserId)
	end

	-- For now: single team for testing (1 player). Extend to real teams later.
	local teams = {
		team1 = userIds,
		team2 = {},
	}

	-- Use the local player's chosen mapId when available (single-player test).
	local mapId = nil
	do
		local first = players[1]
		local l = first and self._loadouts[first.UserId]
		mapId = l and l.mapId or nil
	end

	local matchData = {
		players = userIds,
		teams = teams,
		gamemodeId = self.DefaultGamemodeId,
		mapId = mapId or "ApexArena",
		matchCreatedTime = os.time(),
	}

	self._net:FireAllClients("StartMatch", matchData)
end

return MatchService

