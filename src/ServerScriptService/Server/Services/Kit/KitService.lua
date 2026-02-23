local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KitServiceImpl = require(ReplicatedStorage:WaitForChild("KitSystem"):WaitForChild("KitService"))

local KitService = {}

function KitService:Init(registry, net)
	self._net = net
	self._impl = KitServiceImpl.new(net, registry)
end

function KitService:Start()
	if self._impl then
		self._impl:start()
	end
end

function KitService:NotifyDamage(player, damage, source)
	if self._impl and self._impl.NotifyDamage then
		self._impl:NotifyDamage(player, damage, source)
	end
end

function KitService:InterruptAbility(player, abilityType, reason)
	if self._impl and self._impl.InterruptAbility then
		self._impl:InterruptAbility(player, abilityType, reason)
	end
end

function KitService:OnPlayerDeath(player)
	if self._impl and self._impl.OnPlayerDeath then
		self._impl:OnPlayerDeath(player)
	end
end

function KitService:OnPlayerRespawn(player)
	if self._impl and self._impl.OnPlayerRespawn then
		self._impl:OnPlayerRespawn(player)
	end
end

function KitService:ResetPlayerForTraining(player)
	if self._impl and self._impl.ResetPlayerForTraining then
		self._impl:ResetPlayerForTraining(player)
	end
end

--[[
	Destroys the player's active kit instance, resets server-side kit state
	(equippedKitId, cooldowns, ultimate), pushes zeroed attributes to the player,
	and fires the cleared state to the client.
	Called by MatchManager._returnPlayersToLobby and _resetRound.
]]
function KitService:ClearKit(player)
	if not self._impl then return end
	local impl = self._impl

	-- Destroy the active kit instance (calls OnUnequipped + Destroy)
	if impl._destroyKit then
		pcall(function() impl:_destroyKit(player, "ReturnToLobby") end)
	end

	-- Zero out the server-side data record
	local info = impl._data and impl._data[player]
	if info then
		info.equippedKitId = nil
		info.abilityCooldownEndsAt = 0
		info.ultimate = 0

		-- Push zeroed attributes to the player
		if impl._applyAttributes then
			pcall(function() impl:_applyAttributes(player, info) end)
		end

		-- Tell the client the kit is cleared
		if impl._fireState then
			pcall(function() impl:_fireState(player, info, { lastAction = "ReturnToLobby" }) end)
		end
	end
end

return KitService

