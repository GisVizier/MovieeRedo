local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConnectionManager = require(ReplicatedStorage.CoreUI.ConnectionManager)
local KitConfig = require(ReplicatedStorage.Configs.KitConfig)

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

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
	
	-- Viewmodel state for ability usage
	self._holsteredSlot = nil -- Weapon slot to restore after ability ends
	self._abilityActive = false
	self._weaponSwitchLocked = false -- Manual weapon switch lock

	return self
end

function KitController:init()
	if self._net and self._net.ConnectClient then
		self._connections:add(self._net:ConnectClient("KitState", function(state)
			self:_onKitMessage(state)
		end), "remotes")
	end

	-- Clean up kit abilities when the local player dies
	if self._net and self._net.ConnectClient then
		self._connections:add(self._net:ConnectClient("PlayerKilled", function(data)
			if data and data.victimUserId == self._player.UserId then
				self:_onLocalPlayerDied()
			end
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

	-- Call OnEquip if the kit has it
	if kitInstance.OnEquip then
		local equipCtx = {
			player = self._player,
			character = self._player and self._player.Character,
			kitId = kitId,
		}
		pcall(function()
			kitInstance:OnEquip(equipCtx)
		end)
	end

	return kitInstance
end

function KitController:_interruptClientKit(reason: string)
	local kit = self._clientKit
	local kitId = self._clientKitId
	if not kit or type(kitId) ~= "string" then
		return
	end
	
	-- Call OnUnequip if the kit has it
	if kit.OnUnequip then
		pcall(function()
			kit:OnUnequip(reason)
		end)
	end
	
	-- Restore weapon on client-side interrupt
	self:_unholsterWeapon()

	local function callInterrupt(handlerTable, abilityType)
		if type(handlerTable) ~= "table" then
			return
		end
		local fn = handlerTable.OnInterrupt
		if type(fn) ~= "function" then
			return
		end
		local viewmodelController = ServiceRegistry:GetController("Viewmodel")
		local viewmodelAnimator = viewmodelController and viewmodelController._animator or nil
		local abilityRequest = {
			kitId = kitId,
			abilityType = abilityType,
			player = self._player,
			character = self._player and self._player.Character or nil,
			humanoidRootPart = self._player and self._player.Character and self._player.Character.PrimaryPart or nil,
			timestamp = os.clock(),
			viewmodelController = viewmodelController,
			viewmodelAnimator = viewmodelAnimator,
			-- No Send() on interrupts triggered by system state; ability should just cancel local work.
		}
		pcall(fn, handlerTable, abilityRequest, reason)
	end

	callInterrupt(kit.Ability, "Ability")
	callInterrupt(kit.Ultimate, "Ultimate")
end

--[[
	Called when the local player dies. Force-interrupts all active kit abilities,
	resets controller state, and ensures a clean slate for respawn.
]]
function KitController:_onLocalPlayerDied()
	-- Interrupt any active client kit abilities (stops animations, VFX, sounds, loops)
	self:_interruptClientKit("Death")

	-- Force-reset controller state so nothing lingers into the next life
	self._abilityActive = false
	self._holsteredSlot = nil
	self._weaponSwitchLocked = false
end

function KitController:_onAbilityInput(abilityType: string, inputState)
	-- Safety: if _abilityActive is stuck true but we're no longer on Fists,
	-- a previous ability was interrupted without proper cleanup — reset the state.
	if self._abilityActive then
		local vmController = ServiceRegistry:GetController("Viewmodel")
		if vmController and vmController:GetActiveSlot() ~= "Fists" then
			self._abilityActive = false
			self._holsteredSlot = nil
			self._weaponSwitchLocked = false
		end
	end

	-- Manual-send pipeline:
	-- - Build a request object for the active client kit module
	-- - The kit decides when/if to call request.Send(extraData)
	local kitId = self._activeKitId or (self._state and self._state.equippedKitId) or nil
	local clientKit = self:_loadClientKit(kitId)

	local character = self._player and self._player.Character or nil
	local hrp = character and character.PrimaryPart or nil

	-- Get viewmodel controller and animator for kit abilities
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	local viewmodelAnimator = viewmodelController and viewmodelController._animator or nil

	local sent = false
	local allowMultipleSends = false
	local function send(extraData)
		if extraData and extraData.allowMultiple == true then
			allowMultipleSends = true
		end
		if sent and not allowMultipleSends then
			return false
		end
		sent = true
		self:requestActivateAbility(abilityType, inputState, extraData)
		return true
	end
	
	-- Cooldown helpers
	-- Server sends: abilityCooldownEndsAt (server os.clock()), serverNow (server os.clock() when sent)
	-- We convert to client time by calculating the offset
	local state = self._state
	local cooldownEndsAt = state and state.abilityCooldownEndsAt or 0
	local serverNow = state and state.serverNow or 0
	local receivedAt = state and state.receivedAt or 0
	
	-- Calculate when cooldown ends in client time
	-- cooldownEndsAt - serverNow = seconds remaining when state was sent
	-- receivedAt + (cooldownEndsAt - serverNow) = when it ends in client time
	local function getClientCooldownEndTime()
		if cooldownEndsAt == 0 then return 0 end
		local secondsRemaining = cooldownEndsAt - serverNow
		return receivedAt + secondsRemaining
	end
	
	local function isOnCooldown()
		local endTime = getClientCooldownEndTime()
		return os.clock() < endTime
	end
	
	local function getCooldownRemaining()
		local endTime = getClientCooldownEndTime()
		return math.max(0, endTime - os.clock())
	end
	
	-- StartAbility: Called by client kit to commit to using the ability
	-- Holsters weapon, switches to fists, returns context with viewmodelAnimator
	local abilityStarted = false
	local function startAbility()
		if abilityStarted then
			-- Already started, just return the context
			return { viewmodelAnimator = viewmodelAnimator }
		end
		abilityStarted = true
		
		-- Holster weapon and switch to fists
		self:_holsterWeapon()
		
		return {
			viewmodelAnimator = viewmodelAnimator,
		}
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
		
		-- Cooldown checking
		IsOnCooldown = isOnCooldown,
		GetCooldownRemaining = getCooldownRemaining,
		
		-- Start the ability (holsters weapon, returns viewmodel context)
		StartAbility = startAbility,
		
		-- Direct viewmodel access (for OnEnded/OnInterrupt when ability already started)
		viewmodelController = viewmodelController,
		viewmodelAnimator = viewmodelAnimator,
	}

	local handlerTable = clientKit and clientKit[abilityType] or nil
	local fn = nil
	if inputState == Enum.UserInputState.Begin then
		fn = handlerTable and handlerTable.OnStart or nil
	else
		fn = handlerTable and handlerTable.OnEnded or nil
	end

	if type(fn) == "function" then
		local ok, err = pcall(fn, handlerTable, abilityRequest)
		if not ok then
			warn("[KitController] Client kit error:", err)
		end
		return
	end

	-- Fallback behavior if a client kit doesn't exist / doesn't handle this input edge.
	-- (Preserves current gameplay while you migrate kits to client modules.)
	self:requestActivateAbility(abilityType, inputState)
end

--[[
	Holsters the current weapon and switches to Fists viewmodel.
	Called when an ability starts.
]]
function KitController:_holsterWeapon()
	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		return
	end
	
	-- Store current slot to restore later
	local currentSlot = viewmodelController:GetActiveSlot()
	if currentSlot and currentSlot ~= "Fists" then
		self._holsteredSlot = currentSlot
	elseif not self._holsteredSlot then
		-- Default to Primary if we don't have a stored slot
		self._holsteredSlot = "Primary"
	end
	
	self._abilityActive = true
	
	-- Switch to Fists viewmodel
	viewmodelController:SetActiveSlot("Fists")
end

--[[
	Restores the previously holstered weapon.
	Called when an ability ends.
]]
function KitController:_unholsterWeapon()
	if not self._abilityActive then
		return
	end

	local viewmodelController = ServiceRegistry:GetController("Viewmodel")
	if not viewmodelController then
		self._abilityActive = false
		self._holsteredSlot = nil
		return
	end

	self._abilityActive = false

	-- Restore previous weapon slot only if still on Fists
	-- (player may have already swapped weapons manually)
	local slotToRestore = self._holsteredSlot or "Primary"
	self._holsteredSlot = nil

	if viewmodelController:GetActiveSlot() == "Fists" then
		viewmodelController:SetActiveSlot(slotToRestore)
	end
end

--[[
	Returns true if an ability is currently active (player has fists out).
]]
function KitController:IsAbilityActive(): boolean
	return self._abilityActive == true
end

--[[
	Manually lock weapon switching.
	Call this to prevent player from switching weapons.
	@return function - Call to unlock
]]
function KitController:LockWeaponSwitch()
	self._weaponSwitchLocked = true
	
	-- Return unlock function for convenience
	return function()
		self:UnlockWeaponSwitch()
	end
end

--[[
	Manually unlock weapon switching.
]]
function KitController:UnlockWeaponSwitch()
	self._weaponSwitchLocked = false
end

--[[
	Returns true if weapon switching should be blocked.
	ViewmodelController checks this before allowing slot changes.
]]
function KitController:IsWeaponSwitchLocked(): boolean
	return self._weaponSwitchLocked == true
end

--[[
	Returns true if ability is currently on cooldown.
]]
function KitController:IsAbilityOnCooldown(): boolean
	local state = self._state
	if not state then return false end
	
	local cooldownEndsAt = state.abilityCooldownEndsAt or 0
	if cooldownEndsAt == 0 then return false end
	
	local serverNow = state.serverNow or 0
	local receivedAt = state.receivedAt or 0
	
	-- Convert server time to client time
	local secondsRemaining = cooldownEndsAt - serverNow
	local clientEndTime = receivedAt + secondsRemaining
	
	return os.clock() < clientEndTime
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
	state.receivedAt = os.clock() -- Track when we received this state
	self._state = state

	local kitId = state.equippedKitId
	if kitId ~= self._activeKitId then
		-- Interrupt local-only work for the previous kit before swapping.
		self:_interruptClientKit("KitChanged")
		self._activeKitId = kitId
		if type(kitId) == "string" then
			-- Load the client kit immediately so OnEquip is called
			self:_loadClientKit(kitId)
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
			-- Restore weapon when ability ends (server confirmed)
			self:_unholsterWeapon()
			self:_emit("KitLocalAbilityEnded", event.kitId, event.abilityType)
		end
		self:_emit("KitAbilityEnded", event.kitId, event.playerId, event.abilityType)
	elseif event.event == "AbilityInterrupted" then
		-- Server rejected / cancelled. Cancel any local prediction.
		if isLocal then
			-- Restore weapon on interrupt as well
			self:_unholsterWeapon()
			
			local clientKit = self:_loadClientKit(event.kitId)
			local handlerTable = clientKit and clientKit[event.abilityType] or nil
			local fn = handlerTable and handlerTable.OnInterrupt or nil
			if type(fn) == "function" then
				local character = self._player and self._player.Character or nil
				local hrp = character and character.PrimaryPart or nil
				local viewmodelController = ServiceRegistry:GetController("Viewmodel")
				local viewmodelAnimator = viewmodelController and viewmodelController._animator or nil
				local abilityRequest = {
					kitId = event.kitId,
					abilityType = event.abilityType,
					inputState = event.inputState,
					player = self._player,
					character = character,
					humanoidRootPart = hrp,
					timestamp = os.clock(),
					viewmodelController = viewmodelController,
					viewmodelAnimator = viewmodelAnimator,
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
