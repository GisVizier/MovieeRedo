local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionManager = require(ReplicatedStorage.CoreUI.ConnectionManager)

local KitController = {}
KitController.__index = KitController

function KitController.new(player: Player?, coreUi: any?, net: any?, inputController: any?)
	local self = setmetatable({}, KitController)

	self._player = player or Players.LocalPlayer
	self._coreUi = coreUi
	self._net = net
	self._input = inputController
	self._connections = ConnectionManager.new()

	self._activeKitId = nil
	self._state = nil

	return self
end

function KitController:init()
	if self._net and self._net.ConnectClient then
		self._connections:add(self._net:ConnectClient("KitState", function(state)
			self:_onKitMessage(state)
		end), "remotes")
	end

	-- Ability/Ultimate input should route through your InputController so it respects chat/menu/settings gating + configurable binds.
	if self._input and self._input.ConnectToInput then
		self._input:ConnectToInput("Ability", function(inputState)
			self:requestActivateAbility("Ability", inputState)
		end)
		self._input:ConnectToInput("Ultimate", function(inputState)
			self:requestActivateAbility("Ultimate", inputState)
		end)
	end

	return self
end

function KitController:_emit(eventName: string, ...)
	if not self._coreUi or not self._coreUi.emit then
		return
	end
	local args = table.pack(...)
	pcall(function()
		self._coreUi:emit(eventName, table.unpack(args, 1, args.n))
	end)
end

function KitController:requestPurchaseKit(kitId: string)
	if self._net then
		self._net:FireServer("KitRequest", { action = "PurchaseKit", kitId = kitId })
	end
end

function KitController:requestEquipKit(kitId: string)
	if self._net then
		self._net:FireServer("KitRequest", { action = "EquipKit", kitId = kitId })
	end
end

function KitController:requestActivateAbility(abilityType: string, inputState, clientData)
	if self._net then
		self._net:FireServer("KitRequest", {
			action = "ActivateAbility",
			abilityType = abilityType,
			inputState = inputState,
			clientData = clientData,
		})
	end
end

function KitController:_onKitMessage(message)
	if typeof(message) ~= "table" then
		return
	end

	if message.kind == "Event" then
		self:_onKitEvent(message)
		return
	end

	self:_onKitState(message)
end

function KitController:_onKitState(state)
	self._state = state

	local kitId = state.equippedKitId
	if kitId ~= self._activeKitId then
		self._activeKitId = kitId
		if type(kitId) == "string" then
			self:_emit("KitEquipped", kitId)
		else
			self:_emit("KitUnequipped")
		end
	end

	if state.lastError then
		self:_emit("KitError", state.lastError)
	end
end

function KitController:_onKitEvent(event)
	local localPlayer = self._player
	local isLocal = event.playerId == (localPlayer and localPlayer.UserId)

	if event.event == "KitEquipped" then
		self:_emit("KitEquipped", event.kitId, event.playerId)
	elseif event.event == "KitUnequipped" then
		self:_emit("KitUnequipped", event.kitId, event.playerId)
	elseif event.event == "AbilityActivated" then
		if isLocal then
			self:_emit("KitLocalAbilityActivated", event.kitId, event.abilityType)
		end
		self:_emit("KitAbilityActivated", event.kitId, event.playerId, event.abilityType)
	elseif event.event == "AbilityEnded" then
		if isLocal then
			self:_emit("KitLocalAbilityEnded", event.kitId, event.abilityType)
		end
		self:_emit("KitAbilityEnded", event.kitId, event.playerId, event.abilityType)
	end
end

function KitController:destroy()
	self._connections:cleanupAll()
	self._connections:destroy()
end

return KitController
