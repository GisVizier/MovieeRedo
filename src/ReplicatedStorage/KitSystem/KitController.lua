local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionManager = require(ReplicatedStorage.CoreUI.ConnectionManager)
local KitConfig = require(ReplicatedStorage.Configs.KitConfig)

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
	self._clientKit = nil
	self._clientKitId = nil

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
			self:_onAbilityInput("Ability", inputState)
		end)
		self._input:ConnectToInput("Ultimate", function(inputState)
			self:_onAbilityInput("Ultimate", inputState)
		end)
	end

	return self
end

function KitController:_loadClientKit(kitId: string?)
	if type(kitId) ~= "string" then
		return nil
	end

	if self._clientKit and self._clientKitId == kitId then
		return self._clientKit
	end

	-- Tear down previous kit instance (and give it a chance to cancel local state).
	self:_interruptClientKit("Swap")

	if self._clientKit and self._clientKit.Destroy then
		pcall(function()
			self._clientKit:Destroy()
		end)
	end

	self._clientKit = nil
	self._clientKitId = nil

	local kitData = KitConfig.getKit(kitId)
	local moduleName = (kitData and kitData.Module) or kitId

	local kitsRoot = ReplicatedStorage:FindFirstChild("KitSystem")
	local clientKits = kitsRoot and kitsRoot:FindFirstChild("ClientKits")
	local moduleScript = clientKits and clientKits:FindFirstChild(moduleName)
	if not moduleScript then
		return nil
	end

	local okRequire, kitDef = pcall(require, moduleScript)
	if not okRequire or type(kitDef) ~= "table" then
		warn("[KitController] Bad client kit module", kitId, moduleName)
		return nil
	end

	local ctx = {
		player = self._player,
		kitId = kitId,
		kitConfig = kitData,
	}

	local kitInstance = nil
	if type(kitDef.new) == "function" then
		local okNew, inst = pcall(function()
			return kitDef.new(ctx)
		end)
		if okNew then
			kitInstance = inst
		end
	else
		-- Allow modules that just export tables of handlers (no constructor).
		kitInstance = kitDef
	end

	if type(kitInstance) ~= "table" then
		warn("[KitController] Failed to create client kit instance", kitId, moduleName)
		return nil
	end

	self._clientKit = kitInstance
	self._clientKitId = kitId

	return kitInstance
end

function KitController:_interruptClientKit(reason: string)
	local kit = self._clientKit
	local kitId = self._clientKitId
	if not kit or type(kitId) ~= "string" then
		return
	end

	local function callInterrupt(handlerTable, abilityType)
		if type(handlerTable) ~= "table" then
			return
		end
		local fn = handlerTable.OnInterrupt
		if type(fn) ~= "function" then
			return
		end
		local abilityRequest = {
			kitId = kitId,
			abilityType = abilityType,
			player = self._player,
			character = self._player and self._player.Character or nil,
			humanoidRootPart = self._player and self._player.Character and self._player.Character.PrimaryPart or nil,
			timestamp = os.clock(),
			-- No Send() on interrupts triggered by system state; ability should just cancel local work.
		}
		pcall(fn, handlerTable, abilityRequest, reason)
	end

	callInterrupt(kit.Ability, "Ability")
	callInterrupt(kit.Ultimate, "Ultimate")
end

function KitController:_onAbilityInput(abilityType: string, inputState)
	-- Manual-send pipeline:
	-- - Build a request object for the active client kit module
	-- - The kit decides when/if to call request.Send(extraData)
	local kitId = self._activeKitId or (self._state and self._state.equippedKitId) or nil
	local clientKit = self:_loadClientKit(kitId)

	local character = self._player and self._player.Character or nil
	local hrp = character and character.PrimaryPart or nil

	local sent = false
	local function send(extraData)
		if sent then
			return false
		end
		sent = true
		self:requestActivateAbility(abilityType, inputState, extraData)
		return true
	end

	local abilityRequest = {
		kitId = kitId,
		abilityType = abilityType,
		inputState = inputState,
		player = self._player,
		character = character,
		humanoidRootPart = hrp,
		timestamp = os.clock(),
		Send = send,
	}

	local handlerTable = clientKit and clientKit[abilityType] or nil
	local fn = nil
	if inputState == Enum.UserInputState.Begin then
		fn = handlerTable and handlerTable.OnStart or nil
	else
		fn = handlerTable and handlerTable.OnEnded or nil
	end

	if type(fn) == "function" then
		-- Note: handler is responsible for calling abilityRequest.Send(...) if it wants server replication.
		pcall(fn, handlerTable, abilityRequest)
		return
	end

	-- Fallback behavior if a client kit doesn't exist / doesn't handle this input edge.
	-- (Preserves current gameplay while you migrate kits to client modules.)
	self:requestActivateAbility(abilityType, inputState)
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

function KitController:requestActivateAbility(abilityType: string, inputState, extraData)
	if self._net then
		print("[KitController] ActivateAbility request", {
			abilityType = abilityType,
			inputState = tostring(inputState),
		})
		self._net:FireServer("KitRequest", {
			action = "ActivateAbility",
			abilityType = abilityType,
			inputState = inputState,
			extraData = extraData,
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
		-- Interrupt local-only work for the previous kit before swapping.
		self:_interruptClientKit("KitChanged")
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
	elseif event.event == "AbilityInterrupted" then
		-- Server rejected / cancelled. Cancel any local prediction.
		if isLocal then
			local clientKit = self:_loadClientKit(event.kitId)
			local handlerTable = clientKit and clientKit[event.abilityType] or nil
			local fn = handlerTable and handlerTable.OnInterrupt or nil
			if type(fn) == "function" then
				local character = self._player and self._player.Character or nil
				local hrp = character and character.PrimaryPart or nil
				local abilityRequest = {
					kitId = event.kitId,
					abilityType = event.abilityType,
					inputState = event.inputState,
					player = self._player,
					character = character,
					humanoidRootPart = hrp,
					timestamp = os.clock(),
				}
				pcall(fn, handlerTable, abilityRequest, "ServerInterrupted")
			end
			self:_emit("KitLocalAbilityInterrupted", event.kitId, event.abilityType)
		end
		self:_emit("KitAbilityInterrupted", event.kitId, event.playerId, event.abilityType)
	end
end

function KitController:destroy()
	self:_interruptClientKit("Destroy")
	if self._clientKit and self._clientKit.Destroy then
		pcall(function()
			self._clientKit:Destroy()
		end)
	end
	self._clientKit = nil
	self._clientKitId = nil
	self._connections:cleanupAll()
	self._connections:destroy()
end

return KitController
