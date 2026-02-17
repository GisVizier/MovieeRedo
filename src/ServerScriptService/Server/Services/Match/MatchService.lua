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
	self._trainingLoadoutShields = {} -- [userId] = { forceField, characterAddedConn }

	self._net:ConnectServer("SubmitLoadout", function(player, payload)
		self:_onSubmitLoadout(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		self._ready[userId] = nil
		self._loadouts[userId] = nil
		self._pendingTrainingEntry[userId] = nil
		self:_removeTrainingLoadoutShield(player)
	end)
end

-- Called by AreaTeleport when player needs to pick loadout before entering training
function MatchService:SetPendingTrainingEntry(player, entryData)
	if not player then return end
	self._pendingTrainingEntry[player.UserId] = entryData
	self:_applyTrainingLoadoutShield(player)
end

function MatchService:GetPendingTrainingEntry(player)
	if not player then return nil end
	return self._pendingTrainingEntry[player.UserId]
end

function MatchService:ClearPendingTrainingEntry(player)
	if not player then return end
	self._pendingTrainingEntry[player.UserId] = nil
end

--[[
	Adds default ForceField and invulnerability while player is picking weapons in training ground.
	Ensures they cannot be hit during loadout selection.
]]
function MatchService:_applyTrainingLoadoutShield(player)
	if not player then return end
	local userId = player.UserId

	-- Clean up any existing shield first
	self:_removeTrainingLoadoutShield(player)

	local function addForceFieldToCharacter(character)
		if not character or not character:IsA("Model") then return end
		local existing = character:FindFirstChildOfClass("ForceField")
		if existing then return end
		local ff = Instance.new("ForceField")
		ff.Visible = true
		ff.Parent = character
		return ff
	end

	local forceField = addForceFieldToCharacter(player.Character)

	-- Set invulnerable via CombatService (blocks damage through our pipeline)
	local combatService = self._registry and self._registry:TryGet("CombatService")
	if combatService and combatService.SetInvulnerable then
		combatService:SetInvulnerable(player, true)
	end

	-- Re-apply ForceField if character respawns while still picking
	local characterAddedConn = player.CharacterAdded:Connect(function(newCharacter)
		if not self._pendingTrainingEntry[userId] then return end
		task.defer(function()
			addForceFieldToCharacter(newCharacter)
		end)
	end)

	self._trainingLoadoutShields[userId] = {
		forceField = forceField,
		characterAddedConn = characterAddedConn,
	}
end

--[[
	Removes ForceField and invulnerability when loadout is confirmed or player leaves.
]]
function MatchService:_removeTrainingLoadoutShield(player)
	if not player then return end
	local userId = player.UserId
	local data = self._trainingLoadoutShields[userId]
	if not data then return end
	self._trainingLoadoutShields[userId] = nil

	if data.characterAddedConn then
		data.characterAddedConn:Disconnect()
	end

	if data.forceField and data.forceField.Parent then
		data.forceField:Destroy()
	end

	-- Also remove any ForceField that might have been added by CharacterAdded
	local character = player.Character
	if character then
		local ff = character:FindFirstChildOfClass("ForceField")
		if ff then ff:Destroy() end
	end

	local combatService = self._registry and self._registry:TryGet("CombatService")
	if combatService and combatService.SetInvulnerable then
		combatService:SetInvulnerable(player, false)
	end
end

-- Called when player exits training to reset their state for re-entry
function MatchService:ClearPlayerState(player)
	if not player then return end
	local userId = player.UserId
	self._ready[userId] = nil
	self._loadouts[userId] = nil
	self._pendingTrainingEntry[userId] = nil
	player:SetAttribute("CurrentArea", nil)
	player:SetAttribute("SelectedLoadout", nil)
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
		self:_removeTrainingLoadoutShield(player)

		-- Add player to training match
		local roundService = self._registry:TryGet("Round")
		if roundService then
			roundService:AddPlayer(player)
		end
		
		-- Reset HP, ultimate, and kit state when entering training from lobby
		local combatService = self._registry:TryGet("CombatService")
		if combatService and combatService.ResetPlayerCombat then
			combatService:ResetPlayerCombat(player)
		end
		local kitService = self._registry:TryGet("KitService")
		if kitService and kitService.ResetPlayerForTraining then
			kitService:ResetPlayerForTraining(player)
		end
		
		-- Fire training entry confirmed (player already teleported via gadget)
		self._net:FireClient("TrainingLoadoutConfirmed", player, {
			areaId = pendingEntry.areaId,
		})
		
		-- Set player state to Training and track which area they're in
		player:SetAttribute("PlayerState", "Training")
		player:SetAttribute("CurrentArea", pendingEntry.areaId)
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

