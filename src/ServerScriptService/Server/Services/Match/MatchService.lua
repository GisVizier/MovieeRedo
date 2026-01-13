local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local MatchService = {}

MatchService.RequiredPlayers = 1
MatchService.DefaultGamemodeId = "Duels"

local function isValidMapId(mapId)
	return typeof(mapId) == "string" and #mapId > 0 and #mapId < 128
end

function MatchService:Init(_registry, net)
	self._net = net
	self._registry = _registry

	self._ready = {} -- [userId] = true
	self._loadouts = {} -- [userId] = payload
	self._votesByUserId = {} -- [userId] = mapId
	self._started = false

	self._net:ConnectServer("MapVoteCast", function(player, mapId)
		self:_onMapVoteCast(player, mapId)
	end)

	self._net:ConnectServer("SubmitLoadout", function(player, payload)
		self:_onSubmitLoadout(player, payload)
	end)

	Players.PlayerAdded:Connect(function(player)
		-- Late join: send current vote snapshot so their UI has correct % immediately.
		self._net:FireClient("MapVoteUpdate", player, self:_buildVotesByMapSnapshot())
	end)
	-- If players already exist when this service initializes, sync them too.
	for _, player in ipairs(Players:GetPlayers()) do
		self._net:FireClient("MapVoteUpdate", player, self:_buildVotesByMapSnapshot())
	end

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		self._ready[userId] = nil
		self._loadouts[userId] = nil

		-- Remove their vote and broadcast updated snapshot.
		if self._votesByUserId[userId] ~= nil then
			self._votesByUserId[userId] = nil
			self._net:FireAllClients("MapVoteUpdate", self:_buildVotesByMapSnapshot())
		end
	end)
end

function MatchService:Start() end

function MatchService:_buildVotesByMapSnapshot()
	local votesByMap = {}
	for userId, mapId in pairs(self._votesByUserId) do
		if isValidMapId(mapId) then
			if not votesByMap[mapId] then
				votesByMap[mapId] = {}
			end
			table.insert(votesByMap[mapId], userId)
		end
	end
	return votesByMap
end

function MatchService:_onMapVoteCast(player, mapId)
	if self._started then
		return
	end

	if not player or not player.Parent then
		return
	end

	if not isValidMapId(mapId) then
		return
	end

	local userId = player.UserId
	self._votesByUserId[userId] = mapId

	-- Broadcast full snapshot so every client can update % for all maps.
	self._net:FireAllClients("MapVoteUpdate", self:_buildVotesByMapSnapshot())
end

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

	-- If player never explicitly voted, treat their submitted mapId as their vote.
	-- This helps keep UI/server state consistent in the current flow.
	if isValidMapId(payload.mapId) and self._votesByUserId[userId] == nil then
		self._votesByUserId[userId] = payload.mapId
		self._net:FireAllClients("MapVoteUpdate", self:_buildVotesByMapSnapshot())
	end

	-- Server-side record for verification / later gameplay wiring.
	pcall(function()
		player:SetAttribute("SelectedLoadout", HttpService:JSONEncode(payload))
	end)

	-- Log final loadout on submit
	local loadout = payload.loadout
	print(("[MatchService] Loadout submitted: userId=%d mapId=%s kit=%s primary=%s secondary=%s melee=%s"):format(
		userId,
		tostring(payload.mapId),
		tostring(loadout.Kit),
		tostring(loadout.Primary),
		tostring(loadout.Secondary),
		tostring(loadout.Melee)
	))

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

	-- Log all final loadouts at match start
	print(("[MatchService] StartMatch: mapId=%s players=%d"):format(tostring(matchData.mapId), #userIds))
	for _, p in ipairs(players) do
		local entry = self._loadouts[p.UserId]
		local loadout = entry and entry.loadout or nil
		if typeof(loadout) == "table" then
			print(("[MatchService] FinalLoadout: userId=%d kit=%s primary=%s secondary=%s melee=%s"):format(
				p.UserId,
				tostring(loadout.Kit),
				tostring(loadout.Primary),
				tostring(loadout.Secondary),
				tostring(loadout.Melee)
			))
		else
			print(("[MatchService] FinalLoadout: userId=%d <missing>"):format(p.UserId))
		end
	end

	self._net:FireAllClients("StartMatch", matchData)
end

return MatchService

