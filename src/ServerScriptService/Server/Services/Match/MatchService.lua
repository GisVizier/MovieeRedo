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

	self._net:ConnectServer("SubmitLoadout", function(player, payload)
		self:_onSubmitLoadout(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		self._ready[userId] = nil
		self._loadouts[userId] = nil
	end)
end

function MatchService:Start() end

function MatchService:_onSubmitLoadout(player, payload)
	if self._started then
		return
	end

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

	local loadout = payload.loadout

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

