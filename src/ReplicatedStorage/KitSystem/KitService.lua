local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local KitConfig = require(ReplicatedStorage.Configs.KitConfig)

local KitService = {}
KitService.__index = KitService

function KitService.new(net)
	local self = setmetatable({}, KitService)

	self._net = net
	self._data = {}
	self._playerKits = {}
	self._started = false

	return self
end

function KitService:_ensurePlayer(player: Player)
	if self._data[player] then
		return self._data[player]
	end

	local owned = { "WhiteBeard", "Genji", "Aki" }
	local info = {
		gems = 15000,
		ownedKits = owned,
		equippedKitId = nil,
		ultimate = 0,
		abilityCooldownEndsAt = 0,
	}
	self._data[player] = info

	self:_applyAttributes(player, info)

	return info
end

function KitService:_isOwned(info, kitId: string): boolean
	return table.find(info.ownedKits, kitId) ~= nil
end

function KitService:_applyAttributes(player: Player, info)
	player:SetAttribute("Gems", info.gems or 0)
	player:SetAttribute("OwnedKits", HttpService:JSONEncode(info.ownedKits or {}))
	player:SetAttribute("Ultimate", info.ultimate or 0)

	if not info.equippedKitId then
		player:SetAttribute("KitData", nil)
		return
	end

	local kitData = KitConfig.buildKitData(info.equippedKitId, {
		abilityCooldownEndsAt = info.abilityCooldownEndsAt or 0,
		ultimate = info.ultimate or 0,
	})

	local encoded = kitData and HttpService:JSONEncode(kitData) or nil
	player:SetAttribute("KitData", encoded)
end

function KitService:_fireState(player: Player, info, state)
	if not self._net then
		return
	end

	state.kind = "State"
	state.serverNow = os.clock()
	state.equippedKitId = info.equippedKitId
	state.ultimate = info.ultimate
	state.abilityCooldownEndsAt = info.abilityCooldownEndsAt

	self._net:FireClient("KitState", player, state)
end

function KitService:_fireEvent(player: Player, eventName: string, payload)
	if not self._net then
		return
	end

	local message = payload or {}
	message.kind = "Event"
	message.event = eventName
	message.serverTime = os.clock()
	self._net:FireClient("KitState", player, message)
end

function KitService:_fireEventAll(eventName: string, payload)
	if not self._net then
		return
	end

	local message = payload or {}
	message.kind = "Event"
	message.event = eventName
	message.serverTime = os.clock()
	self._net:FireAllClients("KitState", message)
end

local function makeExtraData(position: Vector3?)
	-- Contract: extraData is always a table for VFX events.
	return {
		position = position,
	}
end

-- Public helper for kit modules:
-- Lets a kit author replicate any custom event + VFX path without a registry.
function KitService:ReplicateVFXAll(eventName: string, payload)
	-- Dummy-simple: replicate any custom VFX event to all clients.
	-- Contract:
	-- - payload.kitId: string
	-- - payload.effect: string (used by client dispatcher)
	-- - payload.extraData.position: Vector3
	if type(payload) ~= "table" then
		return
	end
	if type(payload.kitId) ~= "string" or type(payload.effect) ~= "string" then
		return
	end
	local extra = payload.extraData
	if type(extra) ~= "table" or typeof(extra.position) ~= "Vector3" then
		return
	end

	payload.extraData = makeExtraData(extra.position)
	self:_fireEventAll(eventName, payload)
end

function KitService:_destroyKit(player: Player, reason: string?)
	local kit = self._playerKits[player]
	if not kit then
		return
	end

	local kitId = kit._ctx and kit._ctx.kitId or nil
	local character = player.Character
	local root = character and character.PrimaryPart or nil
	local position = root and root.Position or nil

	pcall(function()
		if kit.OnUnequipped then
			kit:OnUnequipped()
		end
	end)

	pcall(function()
		if kit.Destroy then
			kit:Destroy()
		end
	end)

	self._playerKits[player] = nil

	if kitId then
		self:_fireEventAll("KitUnequipped", {
			playerId = player.UserId,
			kitId = kitId,
			position = position,
			reason = reason,
		})
	end
end

function KitService:_loadKit(kitId: string)
	local kitConfig = KitConfig.getKit(kitId)
	if not kitConfig then
		return nil, "InvalidKit"
	end

	local kitsRoot = ReplicatedStorage:FindFirstChild("KitSystem")
	local kitModules = kitsRoot and kitsRoot:FindFirstChild("Kits")
	if not kitModules then
		return nil, "MissingKitsFolder"
	end

	local moduleName = kitConfig.Module or kitId
	local kitModuleScript = kitModules:FindFirstChild(moduleName)
	if not kitModuleScript then
		return nil, "MissingKitModule"
	end

	local ok, kitDef = pcall(require, kitModuleScript)
	if not ok or type(kitDef) ~= "table" or type(kitDef.new) ~= "function" then
		return nil, "BadKitModule"
	end

	return kitDef
end

function KitService:_ensureKitInstance(player: Player, info)
	local kitId = info.equippedKitId
	if not kitId then
		self:_destroyKit(player, "NoKit")
		return nil
	end

	local existing = self._playerKits[player]
	if existing and existing._ctx and existing._ctx.kitId == kitId then
		return existing
	end

	self:_destroyKit(player, "Swap")

	local kitDef, err = self:_loadKit(kitId)
	if not kitDef then
		self:_fireState(player, info, { lastError = err or "InvalidKit" })
		return nil
	end

	local ctx = {
		player = player,
		character = player.Character,
		kitId = kitId,
		kitConfig = KitConfig.getKit(kitId),
		service = self,
	}

	local okNew, kit = pcall(function()
		return kitDef.new(ctx)
	end)

	if not okNew or not kit then
		self:_fireState(player, info, { lastError = "BadKitInstance" })
		return nil
	end

	self._playerKits[player] = kit

	pcall(function()
		local character = player.Character
		if kit.SetCharacter then
			kit:SetCharacter(character)
		end
	end)

	pcall(function()
		if kit.OnEquipped then
			kit:OnEquipped()
		end
	end)

	local character = player.Character
	local root = character and character.PrimaryPart or nil
	local position = root and root.Position or nil

	self:_fireEventAll("KitEquipped", {
		playerId = player.UserId,
		kitId = kitId,
		position = position,
	})

	return kit
end

function KitService:_purchase(player: Player, info, kitId: string)
	local kit = KitConfig.getKit(kitId)
	if not kit then
		self:_fireState(player, info, { lastError = "InvalidKit" })
		return
	end

	if self:_isOwned(info, kitId) then
		self:_fireState(player, info, { lastError = "AlreadyOwned" })
		return
	end

	local price = kit.Price or 0
	if (info.gems or 0) < price then
		self:_fireState(player, info, { lastError = "InsufficientFunds" })
		return
	end

	info.gems = (info.gems or 0) - price
	table.insert(info.ownedKits, kitId)

	self:_fireState(player, info, { lastAction = "Purchased" })
end

function KitService:_equip(player: Player, info, kitId: string)
	if not KitConfig.getKit(kitId) then
		self:_fireState(player, info, { lastError = "InvalidKit" })
		return
	end

	if not self:_isOwned(info, kitId) then
		self:_fireState(player, info, { lastError = "NotOwned" })
		return
	end

	info.equippedKitId = kitId
	info.abilityCooldownEndsAt = 0

	self:_applyAttributes(player, info)
	self:_ensureKitInstance(player, info)
	self:_fireState(player, info, { lastAction = "Equipped" })
end

function KitService:_activateAbility(player: Player, info, abilityType: string, inputState, extraData)
	local kitId = info.equippedKitId
	if not kitId then
		self:_fireState(player, info, { lastError = "NoKitEquipped" })
		return
	end

	print("[KitService] ActivateAbility", {
		player = player.Name,
		userId = player.UserId,
		kitId = kitId,
		abilityType = abilityType,
		inputState = tostring(inputState),
	})

	local character = player.Character
	if not character or not character.Parent then
		self:_fireState(player, info, { lastError = "NoCharacter" })
		return
	end

	local kit = self:_ensureKitInstance(player, info)
	if not kit then
		return
	end

	local now = os.clock()
	local root = character.PrimaryPart
	local position = root and root.Position or nil

	local isAbility = abilityType == "Ability"
	local isUltimate = abilityType == "Ultimate"
	if not isAbility and not isUltimate then
		self:_fireState(player, info, { lastError = "BadAbilityType" })
		return
	end

	local payload = {
		playerId = player.UserId,
		kitId = kitId,
		effect = abilityType,
		abilityType = abilityType,
		inputState = inputState,
		position = position,
	}

	local function rejectInterrupt()
		print("[KitService] AbilityInterrupted", {
			player = player.Name,
			kitId = kitId,
			abilityType = abilityType,
		})
		payload.extraData = makeExtraData(position)
		self:_fireEvent(player, "AbilityInterrupted", payload)
	end

	local function callKit()
		if isAbility then
			return kit:OnAbility(inputState, extraData)
		end
		return kit:OnUltimate(inputState, extraData)
	end

	if inputState ~= Enum.UserInputState.Begin then
		pcall(callKit)
		print("[KitService] AbilityEnded", {
			player = player.Name,
			kitId = kitId,
			abilityType = abilityType,
		})
		payload.extraData = makeExtraData(position)
		self:_fireEventAll("AbilityEnded", payload)
		return
	end

	if isAbility and now < (info.abilityCooldownEndsAt or 0) then
		rejectInterrupt()
		return
	end

	if isUltimate then
		local cost = KitConfig.getUltimateCost(kitId)
		if (info.ultimate or 0) < cost then
			rejectInterrupt()
			return
		end
	end

	local okCall, did = pcall(callKit)
	if not okCall or did ~= true then
		rejectInterrupt()
		return
	end

	if isAbility then
		info.abilityCooldownEndsAt = now + KitConfig.getAbilityCooldown(kitId)
		self:_applyAttributes(player, info)
		self:_fireState(player, info, { lastAction = "AbilityBegan" })
	else
		info.ultimate = (info.ultimate or 0) - KitConfig.getUltimateCost(kitId)
		self:_applyAttributes(player, info)
		self:_fireState(player, info, { lastAction = "UltimateBegan" })
	end

	payload.extraData = makeExtraData(position)
	print("[KitService] AbilityActivated", {
		player = player.Name,
		kitId = kitId,
		abilityType = abilityType,
		position = position,
	})
	self:_fireEventAll("AbilityActivated", payload)
end

function KitService:addUltimate(player: Player, amount: number)
	local info = self:_ensurePlayer(player)
	info.ultimate = (info.ultimate or 0) + amount
	self:_applyAttributes(player, info)
	self:_fireState(player, info, { lastAction = "UltChanged" })
end

function KitService:start()
	if self._started then
		return self
	end
	self._started = true

	Players.PlayerAdded:Connect(function(player)
		local info = self:_ensurePlayer(player)

		player.CharacterAdded:Connect(function(character)
			local kit = self._playerKits[player]
			if kit then
				pcall(function()
					if kit.SetCharacter then
						kit:SetCharacter(character)
					end
				end)
			end
		end)

		self:_fireState(player, info, { lastAction = "Init" })
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._data[player] = nil
		self:_destroyKit(player, "Left")
	end)

	for _, player in Players:GetPlayers() do
		local info = self:_ensurePlayer(player)
		self:_fireState(player, info, { lastAction = "Init" })
	end

	if self._net then
		self._net:ConnectServer("KitRequest", function(player, payload)
			local info = self:_ensurePlayer(player)
			if typeof(payload) ~= "table" then
				self:_fireState(player, info, { lastError = "BadRequest" })
				return
			end

			local action = payload.action
			if action == "PurchaseKit" then
				self:_purchase(player, info, payload.kitId)
			elseif action == "EquipKit" then
				self:_equip(player, info, payload.kitId)
			elseif action == "ActivateAbility" then
				self:_activateAbility(player, info, payload.abilityType, payload.inputState, payload.extraData)
			elseif action == "RequestKitState" then
				self:_fireState(player, info, { lastAction = "State" })
			else
				self:_fireState(player, info, { lastError = "BadAction" })
			end
		end)
	end

	return self
end

return KitService
