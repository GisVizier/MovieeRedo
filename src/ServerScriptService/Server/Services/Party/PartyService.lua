--[[
	PartyService

	Server-authoritative party system with cross-server persistence.
	Party state is stored in MemoryStoreService and synced across servers
	via MessagingService.

	Persistence rules:
	- Leader disconnects   → party is disbanded for everyone
	- Non-leader disconnects → stays in party for OFFLINE_GRACE seconds
	- Non-leader rejoins (any server) → party state restored
	- Grace period expires  → auto-removed from party
	- All members offline past grace → party auto-expires via TTL

	Public API (for other services):
	- PartyService:GetParty(player)            -> partyData | nil
	- PartyService:GetPartyMembers(player)     -> { userId, ... } | nil
	- PartyService:IsInParty(player)           -> boolean
	- PartyService:GetPartySize(player)        -> number
	- PartyService:IsPartyLeader(player)       -> boolean
	- PartyService:RemoveFromParty(player)     -> void
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")

local PartyService = {}

local MAX_PARTY_SIZE = 5
local INVITE_TIMEOUT = 5
local OFFLINE_GRACE = 300
local STORE_TTL = 3600
local MSG_TOPIC = "PartyEvents"
local ENABLE_CROSS_SERVER = false

function PartyService:Init(registry, net)
	self._registry = registry
	self._net = net

	self._parties = {}
	self._playerToParty = {}
	self._pendingInvites = {}
	self._offlineTimers = {}

	if ENABLE_CROSS_SERVER then
		self._partyStore = MemoryStoreService:GetHashMap("PartyData")
		self._playerStore = MemoryStoreService:GetHashMap("PlayerParty")
	else
		self._partyStore = nil
		self._playerStore = nil
	end

	self:_setupNetworkEvents()
	self:_setupPlayerEvents()
	if ENABLE_CROSS_SERVER then
		self:_setupMessaging()
	end
end

function PartyService:Start() end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function PartyService:GetParty(player)
	local partyId = self._playerToParty[player.UserId]
	if not partyId then
		return nil
	end
	return self._parties[partyId]
end

function PartyService:GetPartyMembers(player)
	local party = self:GetParty(player)
	if not party then
		return nil
	end
	return party.members
end

function PartyService:IsInParty(player)
	return self._playerToParty[player.UserId] ~= nil
end

function PartyService:GetPartySize(player)
	local party = self:GetParty(player)
	return party and #party.members or 0
end

function PartyService:IsPartyLeader(player)
	local party = self:GetParty(player)
	return party ~= nil and party.leaderId == player.UserId
end

function PartyService:RemoveFromParty(player)
	self:_leaveParty(player)
end

--------------------------------------------------------------------------------
-- MEMORYSTORE HELPERS
--------------------------------------------------------------------------------

function PartyService:_savePartyToStore(party)
	if not ENABLE_CROSS_SERVER or not self._partyStore or not self._playerStore then
		return
	end
	local storeData = {
		leaderId = party.leaderId,
		members = party.members,
		offlineMembers = party.offlineMembers or {},
		maxSize = party.maxSize,
		createdAt = party.createdAt,
	}
	local ok, err = pcall(function()
		self._partyStore:SetAsync(party.id, storeData, STORE_TTL)
	end)
	if not ok then
		warn("[PartyService] Failed to save party to store:", err)
	end
	for _, uid in ipairs(party.members) do
		pcall(function()
			self._playerStore:SetAsync(tostring(uid), party.id, STORE_TTL)
		end)
	end
end

function PartyService:_removePartyFromStore(partyId, memberList)
	if not ENABLE_CROSS_SERVER or not self._partyStore or not self._playerStore then
		return
	end
	pcall(function()
		self._partyStore:RemoveAsync(partyId)
	end)
	if memberList then
		for _, uid in ipairs(memberList) do
			pcall(function()
				self._playerStore:RemoveAsync(tostring(uid))
			end)
		end
	end
end

function PartyService:_removePlayerFromStore(userId)
	if not ENABLE_CROSS_SERVER or not self._playerStore then
		return
	end
	pcall(function()
		self._playerStore:RemoveAsync(tostring(userId))
	end)
end

function PartyService:_loadPartyFromStore(partyId)
	if not ENABLE_CROSS_SERVER or not self._partyStore then
		return nil
	end
	local ok, data = pcall(function()
		return self._partyStore:GetAsync(partyId)
	end)
	if ok and data then
		return data
	end
	return nil
end

function PartyService:_loadPlayerPartyId(userId)
	if not ENABLE_CROSS_SERVER or not self._playerStore then
		return nil
	end
	local ok, partyId = pcall(function()
		return self._playerStore:GetAsync(tostring(userId))
	end)
	if ok and partyId then
		return partyId
	end
	return nil
end

--------------------------------------------------------------------------------
-- MESSAGING
--------------------------------------------------------------------------------

function PartyService:_setupMessaging()
	if not ENABLE_CROSS_SERVER then
		return
	end
	pcall(function()
		MessagingService:SubscribeAsync(MSG_TOPIC, function(message)
			local data = message.Data
			if type(data) ~= "table" then
				return
			end
			self:_handleRemoteEvent(data)
		end)
	end)
end

function PartyService:_publish(action, partyId, extra)
	if not ENABLE_CROSS_SERVER then
		return
	end
	local payload = {
		action = action,
		partyId = partyId,
		serverId = game.JobId,
	}
	if extra then
		for k, v in pairs(extra) do
			payload[k] = v
		end
	end
	pcall(function()
		MessagingService:PublishAsync(MSG_TOPIC, payload)
	end)
end

function PartyService:_handleRemoteEvent(data)
	if data.serverId == game.JobId then
		return
	end

	local action = data.action
	local partyId = data.partyId

	if action == "update" then
		self:_syncPartyFromStore(partyId)
	elseif action == "disband" then
		self:_handleRemoteDisband(partyId, data.memberList)
	elseif action == "kick" then
		local kickedUserId = data.kickedUserId
		if kickedUserId then
			local p = Players:GetPlayerByUserId(kickedUserId)
			if p then
				self._playerToParty[kickedUserId] = nil
				self:_clearPlayerAttributes(p)
				self._net:FireClient("PartyKicked", p, { partyId = partyId })
			end
		end
		self:_syncPartyFromStore(partyId)
	end
end

function PartyService:_localDisbandParty(party)
	print("[PartyService] _localDisbandParty: cleaning up party", party.id, "on this server")
	self:_handleRemoteDisband(party.id, party.members)
end

function PartyService:_syncPartyFromStore(partyId)
	local storeData = self:_loadPartyFromStore(partyId)
	if not storeData then
		local party = self._parties[partyId]
		if party then
			self:_localDisbandParty(party)
		end
		return
	end

	local party = self._parties[partyId]
	if not party then
		party = {
			id = partyId,
			leaderId = storeData.leaderId,
			members = storeData.members,
			offlineMembers = storeData.offlineMembers or {},
			maxSize = storeData.maxSize or MAX_PARTY_SIZE,
			createdAt = storeData.createdAt or tick(),
		}
		self._parties[partyId] = party
	else
		party.leaderId = storeData.leaderId
		party.members = storeData.members
		party.offlineMembers = storeData.offlineMembers or {}
	end

	local memberSet = {}
	for _, uid in ipairs(party.members) do
		memberSet[uid] = true
		self._playerToParty[uid] = partyId
	end

	for uid, pid in pairs(self._playerToParty) do
		if pid == partyId and not memberSet[uid] then
			self._playerToParty[uid] = nil
			local p = Players:GetPlayerByUserId(uid)
			if p then
				self:_clearPlayerAttributes(p)
				self._net:FireClient("PartyDisbanded", p, { partyId = partyId })
			end
		end
	end

	for _, uid in ipairs(party.members) do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			self:_setPlayerAttributes(p, party)
		end
	end

	self:_broadcastPartyUpdate(party)
end

function PartyService:_handleRemoteDisband(partyId, memberList)
	local party = self._parties[partyId]
	local uids = memberList or (party and party.members) or {}

	for _, uid in ipairs(uids) do
		self._playerToParty[uid] = nil
		local p = Players:GetPlayerByUserId(uid)
		if p then
			self:_clearPlayerAttributes(p)
			self._net:FireClient("PartyDisbanded", p, { partyId = partyId })
		end
	end

	if party then
		self._parties[partyId] = nil
	end
end

--------------------------------------------------------------------------------
-- NETWORK EVENTS
--------------------------------------------------------------------------------

function PartyService:_setupNetworkEvents()
	self._net:ConnectServer("PartyInviteSend", function(player, data)
		if type(data) ~= "table" or type(data.targetUserId) ~= "number" then
			return
		end
		self:_handleInviteSend(player, data.targetUserId)
	end)

	self._net:ConnectServer("PartyInviteResponse", function(player, data)
		if type(data) ~= "table" or type(data.accept) ~= "boolean" then
			return
		end
		self:_handleInviteResponse(player, data.accept)
	end)

	self._net:ConnectServer("PartyKick", function(player, data)
		if type(data) ~= "table" or type(data.targetUserId) ~= "number" then
			return
		end
		self:_handleKick(player, data.targetUserId)
	end)

	self._net:ConnectServer("PartyLeave", function(player)
		self:_leaveParty(player)
	end)
end

--------------------------------------------------------------------------------
-- PLAYER EVENTS (JOIN / LEAVE)
--------------------------------------------------------------------------------

function PartyService:_setupPlayerEvents()
	Players.PlayerAdded:Connect(function(player)
		self:_onPlayerAdded(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:_onPlayerAdded(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:_onPlayerRemoving(player)
	end)
end

function PartyService:_onPlayerAdded(player)
	if not ENABLE_CROSS_SERVER then
		return
	end
	local userId = player.UserId
	local partyId = self:_loadPlayerPartyId(userId)
	if not partyId then
		return
	end

	local storeData = self:_loadPartyFromStore(partyId)
	if not storeData then
		self:_removePlayerFromStore(userId)
		return
	end

	if not table.find(storeData.members, userId) then
		self:_removePlayerFromStore(userId)
		return
	end

	local party = self._parties[partyId]
	if not party then
		party = {
			id = partyId,
			leaderId = storeData.leaderId,
			members = storeData.members,
			offlineMembers = storeData.offlineMembers or {},
			maxSize = storeData.maxSize or MAX_PARTY_SIZE,
			createdAt = storeData.createdAt or tick(),
		}
		self._parties[partyId] = party
	else
		party.members = storeData.members
		party.offlineMembers = storeData.offlineMembers or {}
		party.leaderId = storeData.leaderId
	end

	if party.offlineMembers[tostring(userId)] then
		party.offlineMembers[tostring(userId)] = nil
		self:_savePartyToStore(party)
	end

	for _, uid in ipairs(party.members) do
		self._playerToParty[uid] = partyId
	end

	self:_setPlayerAttributes(player, party)
	self:_broadcastPartyUpdate(party)
	self:_publish("update", partyId)
end

function PartyService:_onPlayerRemoving(player)
	local userId = player.UserId
	print("[PartyService] _onPlayerRemoving: userId", userId)
	self:_cancelPendingInviteFor(userId)

	local timer = self._offlineTimers[userId]
	if timer then
		pcall(task.cancel, timer)
		self._offlineTimers[userId] = nil
	end

	local party = self:GetParty(player)
	if not party then
		return
	end

	if party.leaderId == userId then
		self:_disbandParty(party)
		return
	end

	if not ENABLE_CROSS_SERVER then
		print("[PartyService] _onPlayerRemoving: non-leader removed immediately (cross-server disabled)")
		self:_removeMemberById(party, userId, false)
		return
	end

	party.offlineMembers = party.offlineMembers or {}
	party.offlineMembers[tostring(userId)] = tick()
	self:_savePartyToStore(party)
	self:_broadcastPartyUpdate(party)
	self:_publish("update", party.id)

	self._offlineTimers[userId] = task.delay(OFFLINE_GRACE, function()
		self._offlineTimers[userId] = nil
		local currentParty = self._parties[party.id]
		if not currentParty then
			return
		end
		if not table.find(currentParty.members, userId) then
			return
		end
		local p = Players:GetPlayerByUserId(userId)
		if p then
			return
		end
		self:_removeMemberById(currentParty, userId)
	end)
end

--------------------------------------------------------------------------------
-- INVITE FLOW
--------------------------------------------------------------------------------

function PartyService:_handleInviteSend(sender, targetUserId)
	print("[PartyService] _handleInviteSend: sender", sender.UserId, "-> target", targetUserId)
	if sender.UserId == targetUserId then
		return
	end

	local target = Players:GetPlayerByUserId(targetUserId)
	if not target then
		print("[PartyService] _handleInviteSend: target not in server")
		return
	end

	local senderParty = self:GetParty(sender)
	if senderParty and senderParty.leaderId ~= sender.UserId then
		print("[PartyService] _handleInviteSend: sender is not leader, rejected")
		return
	end

	if senderParty and #senderParty.members >= MAX_PARTY_SIZE then
		print("[PartyService] _handleInviteSend: party full")
		return
	end

	if self._playerToParty[targetUserId] then
		print("[PartyService] _handleInviteSend: target already in party, sending busy")
		self._net:FireClient("PartyInviteBusy", sender, {
			targetUserId = targetUserId,
			reason = "already_in_party",
		})
		return
	end

	if self._pendingInvites[targetUserId] then
		print("[PartyService] _handleInviteSend: target has pending invite, sending busy")
		self._net:FireClient("PartyInviteBusy", sender, {
			targetUserId = targetUserId,
			reason = "pending_invite",
		})
		return
	end

	local timeoutThread = task.delay(INVITE_TIMEOUT, function()
		local invite = self._pendingInvites[targetUserId]
		if invite and invite.fromUserId == sender.UserId then
			self._pendingInvites[targetUserId] = nil
			self._net:FireClient("PartyInviteDeclined", sender, {
				targetUserId = targetUserId,
			})
		end
	end)

	self._pendingInvites[targetUserId] = {
		fromUserId = sender.UserId,
		partyId = senderParty and senderParty.id or nil,
		expiresAt = tick() + INVITE_TIMEOUT,
		timeoutThread = timeoutThread,
	}

	self._net:FireClient("PartyInviteReceived", target, {
		fromUserId = sender.UserId,
		fromDisplayName = sender.DisplayName,
		fromUsername = sender.Name,
		partyId = senderParty and senderParty.id or nil,
		timeout = INVITE_TIMEOUT,
	})
end

function PartyService:_handleInviteResponse(target, accept)
	print("[PartyService] _handleInviteResponse: target", target.UserId, "accept:", accept)
	local invite = self._pendingInvites[target.UserId]
	if not invite then
		print("[PartyService] _handleInviteResponse: no pending invite for target")
		return
	end

	if invite.timeoutThread then
		pcall(task.cancel, invite.timeoutThread)
	end
	self._pendingInvites[target.UserId] = nil

	local sender = Players:GetPlayerByUserId(invite.fromUserId)

	if not accept then
		if sender then
			self._net:FireClient("PartyInviteDeclined", sender, {
				targetUserId = target.UserId,
			})
		end
		return
	end

	local senderParty = nil
	if sender then
		senderParty = self:GetParty(sender)
	end

	if not senderParty then
		if not sender then
			return
		end
		senderParty = self:_createParty(sender)
	end

	if #senderParty.members >= MAX_PARTY_SIZE then
		return
	end

	self:_addMember(senderParty, target)
end

--------------------------------------------------------------------------------
-- KICK
--------------------------------------------------------------------------------

function PartyService:_handleKick(leader, targetUserId)
	local party = self:GetParty(leader)
	if not party or party.leaderId ~= leader.UserId then
		print("[PartyService] _handleKick: rejected - not leader or no party")
		return
	end

	if targetUserId == leader.UserId then
		return
	end

	if not self:_isMember(party, targetUserId) then
		print("[PartyService] _handleKick: userId", targetUserId, "is not a member of party", party.id)
		return
	end

	print("[PartyService] _handleKick: leader", leader.UserId, "kicking", targetUserId, "from party", party.id)
	local target = Players:GetPlayerByUserId(targetUserId)
	if target then
		self:_removeMember(party, target, true)
	else
		self:_removeMemberById(party, targetUserId, true)
	end
end

--------------------------------------------------------------------------------
-- PARTY LIFECYCLE
--------------------------------------------------------------------------------

function PartyService:_createParty(leader)
	local partyId = HttpService:GenerateGUID(false)

	local party = {
		id = partyId,
		leaderId = leader.UserId,
		members = { leader.UserId },
		offlineMembers = {},
		maxSize = MAX_PARTY_SIZE,
		createdAt = tick(),
	}

	self._parties[partyId] = party
	self._playerToParty[leader.UserId] = partyId

	self:_setPlayerAttributes(leader, party)
	self:_savePartyToStore(party)
	self:_broadcastPartyUpdate(party)
	self:_publish("update", partyId)

	return party
end

function PartyService:_addMember(party, player)
	print("[PartyService] _addMember: adding userId", player.UserId, "to party", party.id)
	table.insert(party.members, player.UserId)
	self._playerToParty[player.UserId] = party.id
	party.offlineMembers = party.offlineMembers or {}
	party.offlineMembers[tostring(player.UserId)] = nil

	self:_setPlayerAttributes(player, party)
	self:_savePartyToStore(party)
	self:_broadcastPartyUpdate(party)
	self:_publish("update", party.id)
end

function PartyService:_removeMember(party, player, isKick)
	local userId = player.UserId
	local idx = table.find(party.members, userId)
	if not idx then
		print("[PartyService] _removeMember: userId", userId, "not found in party", party.id)
		return
	end

	table.remove(party.members, idx)
	self._playerToParty[userId] = nil
	self:_clearPlayerAttributes(player)
	self:_removePlayerFromStore(userId)

	if party.offlineMembers then
		party.offlineMembers[tostring(userId)] = nil
	end

	if isKick then
		print("[PartyService] _removeMember: KICKED userId", userId, "from party", party.id)
		self._net:FireClient("PartyKicked", player, { partyId = party.id })
	else
		print("[PartyService] _removeMember: userId", userId, "LEFT party", party.id)
		self._net:FireClient("PartyDisbanded", player, { partyId = party.id })
	end

	if #party.members <= 1 or party.leaderId == userId then
		print("[PartyService] _removeMember: auto-disbanding party", party.id, "(remaining:", #party.members, ")")
		self:_disbandParty(party)
		return
	end

	self:_savePartyToStore(party)
	self:_broadcastPartyUpdate(party)
	if isKick then
		self:_publish("kick", party.id, { kickedUserId = userId })
	else
		self:_publish("update", party.id)
	end
end

function PartyService:_removeMemberById(party, userId, isKick)
	local idx = table.find(party.members, userId)
	if not idx then
		print("[PartyService] _removeMemberById: userId", userId, "not found in party", party.id)
		return
	end

	table.remove(party.members, idx)
	self._playerToParty[userId] = nil
	self:_removePlayerFromStore(userId)

	if party.offlineMembers then
		party.offlineMembers[tostring(userId)] = nil
	end

	local p = Players:GetPlayerByUserId(userId)
	if p then
		self:_clearPlayerAttributes(p)
		if isKick then
			print("[PartyService] _removeMemberById: KICKED userId", userId, "from party", party.id)
			self._net:FireClient("PartyKicked", p, { partyId = party.id })
		else
			print("[PartyService] _removeMemberById: userId", userId, "LEFT party", party.id)
			self._net:FireClient("PartyDisbanded", p, { partyId = party.id })
		end
	end

	if #party.members <= 1 or party.leaderId == userId then
		print("[PartyService] _removeMemberById: auto-disbanding party", party.id, "(remaining:", #party.members, ")")
		self:_disbandParty(party)
		return
	end

	self:_savePartyToStore(party)
	self:_broadcastPartyUpdate(party)
	if isKick then
		self:_publish("kick", party.id, { kickedUserId = userId })
	else
		self:_publish("update", party.id)
	end
end

function PartyService:_leaveParty(player)
	local party = self:GetParty(player)
	if not party then
		print("[PartyService] _leaveParty: player", player.UserId, "is not in a party")
		return
	end

	if party.leaderId == player.UserId then
		print("[PartyService] _leaveParty: leader", player.UserId, "disbanding party", party.id)
		self:_disbandParty(party)
		return
	end

	print("[PartyService] _leaveParty: non-leader", player.UserId, "leaving party", party.id)
	self:_removeMember(party, player, false)
end

function PartyService:_disbandParty(party)
	print("[PartyService] _disbandParty: disbanding party", party.id, "members:", table.concat(party.members, ","))
	local membersCopy = {}
	for _, uid in ipairs(party.members) do
		table.insert(membersCopy, uid)
	end

	for _, userId in ipairs(membersCopy) do
		self._playerToParty[userId] = nil
		local p = Players:GetPlayerByUserId(userId)
		if p then
			self:_clearPlayerAttributes(p)
			print("[PartyService] _disbandParty: firing PartyDisbanded to userId", userId)
			self._net:FireClient("PartyDisbanded", p, { partyId = party.id })
		end

		local timer = self._offlineTimers[userId]
		if timer then
			pcall(task.cancel, timer)
			self._offlineTimers[userId] = nil
		end
	end

	self:_removePartyFromStore(party.id, membersCopy)
	self._parties[party.id] = nil
	self:_publish("disband", party.id, { memberList = membersCopy })
end

function PartyService:_isMember(party, userId)
	return table.find(party.members, userId) ~= nil
end

--------------------------------------------------------------------------------
-- BROADCAST & ATTRIBUTES
--------------------------------------------------------------------------------

function PartyService:_broadcastPartyUpdate(party)
	local payload = {
		partyId = party.id,
		leaderId = party.leaderId,
		members = party.members,
		maxSize = party.maxSize,
	}

	for _, userId in ipairs(party.members) do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			self._net:FireClient("PartyUpdate", p, payload)
		end
	end
end

function PartyService:_setPlayerAttributes(player, party)
	player:SetAttribute("InParty", true)
	player:SetAttribute("PartyId", party.id)
	player:SetAttribute("PartyLeader", party.leaderId == player.UserId)
end

function PartyService:_clearPlayerAttributes(player)
	player:SetAttribute("InParty", nil)
	player:SetAttribute("PartyId", nil)
	player:SetAttribute("PartyLeader", nil)
end

function PartyService:_cancelPendingInviteFor(userId)
	local invite = self._pendingInvites[userId]
	if invite then
		if invite.timeoutThread then
			pcall(task.cancel, invite.timeoutThread)
		end
		self._pendingInvites[userId] = nil
	end
end

return PartyService
