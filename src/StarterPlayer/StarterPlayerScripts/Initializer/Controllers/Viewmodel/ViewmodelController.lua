local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local CreateLoadout = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("CreateLoadout"))
local ViewmodelEffects = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("ViewmodelEffects"))
local ViewmodelAnimator = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("ViewmodelAnimator"))
local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local ViewmodelController = {}

local LocalPlayer = Players.LocalPlayer

ViewmodelController._registry = nil
ViewmodelController._net = nil

ViewmodelController._loadout = nil
ViewmodelController._loadoutVm = nil -- object from CreateLoadout
ViewmodelController._activeSlot = nil
ViewmodelController._previousSlot = nil

ViewmodelController._effects = nil
ViewmodelController._animator = nil

ViewmodelController._renderConn = nil
ViewmodelController._kitConn = nil
ViewmodelController._startMatchConn = nil
ViewmodelController._attrConn = nil
ViewmodelController._equipKeysConn = nil

ViewmodelController._gameplayEnabled = false

local function getCameraController(self)
	return self._registry and self._registry:TryGet("Camera") or nil
end

local function isFirstPerson(self): boolean
	local camController = getCameraController(self)
	if not camController or type(camController.GetCurrentMode) ~= "function" then
		return false
	end
	return camController:GetCurrentMode() == "FirstPerson"
end

local function getCamera(): Camera?
	return workspace.CurrentCamera
end

local function getRigForSlot(self, slot: string)
	return self._loadoutVm and self._loadoutVm.Rigs and self._loadoutVm.Rigs[slot] or nil
end

function ViewmodelController:Init(registry, net)
	self._registry = registry
	self._net = net

	ServiceRegistry:SetRegistry(registry)
	ServiceRegistry:RegisterController("Viewmodel", self)

	self._effects = ViewmodelEffects.new()
	self._animator = ViewmodelAnimator.new()

	-- Listen for match start (Option A: equip Primary).
	if self._net and self._net.ConnectClient then
		self._startMatchConn = self._net:ConnectClient("StartMatch", function(_matchData)
			self._gameplayEnabled = true
			self:SetActiveSlot("Primary")
		end)

		-- Listen to kit events directly (avoid UI dependencies).
		self._kitConn = self._net:ConnectClient("KitState", function(message)
			self:_onKitMessage(message)
		end)
	end

	-- Create loadout viewmodels when server records SelectedLoadout.
	if LocalPlayer then
		local function onSelectedLoadoutChanged()
			local raw = LocalPlayer:GetAttribute("SelectedLoadout")
			if type(raw) ~= "string" or raw == "" then
				return
			end

			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(raw)
			end)
			if not ok or type(decoded) ~= "table" then
				return
			end

			local payload = decoded
			local loadout = payload.loadout
			if type(loadout) ~= "table" then
				-- Some callers may store the loadout directly.
				loadout = decoded
			end

			self:CreateLoadout(loadout)
		end

		self._attrConn = LocalPlayer:GetAttributeChangedSignal("SelectedLoadout"):Connect(onSelectedLoadoutChanged)
		-- Handle case where it was already set (studio testing / late init).
		task.defer(onSelectedLoadoutChanged)
	end

	-- Temporary equip hotkeys (PC): 1=Primary, 2=Secondary, 3=Fists, 4=Melee.
	-- IMPORTANT: uses InputController gating flags so it won't fire in menus/chat.
	do
		local inputController = self._registry and self._registry:TryGet("Input")
		local manager = inputController and inputController.Manager or nil

		self._equipKeysConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end

			-- Gate with InputManager state (matches rest of gameplay input).
			if manager then
				if manager.IsMenuOpen or manager.IsChatFocused or manager.IsSettingsOpen or not manager.GameplayEnabled then
					return
				end
			end

			local key = input.KeyCode
			if key == Enum.KeyCode.One then
				self:_tryEquipSlotFromLoadout("Primary")
			elseif key == Enum.KeyCode.Two then
				self:_tryEquipSlotFromLoadout("Secondary")
			elseif key == Enum.KeyCode.Three then
				self:SetActiveSlot("Fists")
			elseif key == Enum.KeyCode.Four then
				self:_tryEquipSlotFromLoadout("Melee")
			end
		end)
	end
end

function ViewmodelController:Start() end

function ViewmodelController:CreateLoadout(loadout: {[string]: any})
	self._loadout = loadout

	if self._loadoutVm then
		self._loadoutVm:Destroy()
		self._loadoutVm = nil
	end

	self._loadoutVm = CreateLoadout.create(loadout, LocalPlayer)

	-- Default equip should be Primary (fallback is handled by SetActiveSlot).
	self:SetActiveSlot("Primary")

	LogService:Info("VIEWMODEL", "CreateLoadout complete", {
		Primary = tostring(loadout.Primary),
		Secondary = tostring(loadout.Secondary),
		Melee = tostring(loadout.Melee),
	})
end

function ViewmodelController:SetActiveSlot(slot: string)
	if type(slot) ~= "string" then
		return
	end

	if not self._loadoutVm or not self._loadoutVm.Rigs then
		return
	end

	-- Fists are the fallback.
	if not self._loadoutVm.Rigs[slot] then
		slot = "Fists"
	end

	if self._activeSlot == slot then
		return
	end

	self._previousSlot = self._activeSlot
	self._activeSlot = slot

	-- Update HUD selection highlight via player attribute.
	-- HUD expects Primary/Secondary/Melee (Kit is rendered as ability slot but selection maps to Primary).
	do
		if LocalPlayer then
			local hudSlot = slot
			if hudSlot == "Fists" then
				hudSlot = "Primary"
			end
			if hudSlot == "Primary" or hudSlot == "Secondary" or hudSlot == "Melee" then
				LocalPlayer:SetAttribute("EquippedSlot", hudSlot)
			end
		end
	end

	-- Re-parent: only active rig is parented to camera.
	local cam = getCamera()
	for name, rig in pairs(self._loadoutVm.Rigs) do
		if rig and rig.Model then
			rig.Model.Parent = (name == slot and cam and isFirstPerson(self)) and cam or nil
		end
	end

	-- Reset effects on swaps for crisp feel.
	self._effects:Reset()

	-- Bind animator to the active rig (movement loops).
	do
		local rig = getRigForSlot(self, slot)
		local weaponId = nil
		if slot == "Fists" then
			weaponId = "Fists"
		elseif self._loadout and type(self._loadout[slot]) == "string" then
			weaponId = self._loadout[slot]
		end
		self._animator:BindRig(rig, weaponId)
	end

	self:_ensureRenderLoop()
end

function ViewmodelController:_tryEquipSlotFromLoadout(slot: string)
	-- Do not "make up" weapons: only switch if the selected loadout actually has a weapon ID for that slot.
	if type(slot) ~= "string" then
		return
	end
	if not self._loadout or type(self._loadout) ~= "table" then
		return
	end

	local weaponId = self._loadout[slot]
	if type(weaponId) ~= "string" or weaponId == "" then
		return
	end

	-- If the rig doesn't exist (missing model), SetActiveSlot will safely fall back to fists.
	self:SetActiveSlot(slot)
end

function ViewmodelController:_ensureRenderLoop()
	if self._renderConn then
		return
	end

	self._renderConn = RunService.RenderStepped:Connect(function(dt)
		self:_render(dt)
	end)
end

function ViewmodelController:_render(dt: number)
	if not self._loadoutVm or not self._activeSlot then
		return
	end

	local cam = getCamera()
	if not cam then
		return
	end

	-- First-person only: if not FP, keep everything unparented.
	if not isFirstPerson(self) then
		for _, rig in pairs(self._loadoutVm.Rigs) do
			if rig and rig.Model then
				rig.Model.Parent = nil
			end
		end
		return
	end

	local rig = getRigForSlot(self, self._activeSlot)
	if not rig or not rig.Model or not rig.Anchor then
		return
	end

	-- Ensure active model is parented to camera.
	if rig.Model.Parent ~= cam then
		rig.Model.Parent = cam
	end

	local weaponId = nil
	if self._activeSlot == "Fists" then
		weaponId = "Fists"
	elseif self._loadout and type(self._loadout[self._activeSlot]) == "string" then
		weaponId = self._loadout[self._activeSlot]
	end

	local cfg = ViewmodelConfig.Weapons[weaponId or ""] or ViewmodelConfig.Weapons.Fists
	local baseOffset = (cfg and cfg.Offset) or CFrame.new()

	local effectsOffset = self._effects:Update(dt, cam.CFrame, weaponId)

	-- Align rig so its Anchor part matches the camera.
	-- Equivalent to Moviee: Camera.CFrame * (modelPivot:ToObjectSpace(anchorPivot))^-1 * offsets
	local pivot = rig.Model:GetPivot()
	local anchorPivot = rig.Anchor:GetPivot()
	local align = pivot:ToObjectSpace(anchorPivot):Inverse()

	local target = cam.CFrame * align * baseOffset * effectsOffset
	rig.Model:PivotTo(target)
end

function ViewmodelController:_onKitMessage(message)
	if type(message) ~= "table" then
		return
	end
	if message.kind ~= "Event" then
		return
	end

	-- Only local visuals.
	if message.playerId ~= (LocalPlayer and LocalPlayer.UserId) then
		return
	end

	if message.event == "AbilityActivated" then
		self:_onLocalAbilityBegin(message.kitId, message.abilityType)
	elseif message.event == "AbilityEnded" then
		self:_onLocalAbilityEnd(message.kitId, message.abilityType)
	end
end

function ViewmodelController:_playKitAnim(kitId: string, abilityType: string, name: string)
	if type(kitId) ~= "string" or type(name) ~= "string" then
		return nil
	end

	local kitCfg = ViewmodelConfig.Kits and ViewmodelConfig.Kits[kitId]
	if type(kitCfg) ~= "table" then
		return nil
	end

	local section = (abilityType == "Ultimate") and kitCfg.Ultimate or kitCfg.Ability
	if type(section) ~= "table" then
		return nil
	end

	local animId = section[name]
	if type(animId) ~= "string" or animId == "" or animId == "rbxassetid://0" then
		return nil
	end

	local rig = getRigForSlot(self, "Fists")
	if not rig or not rig.Animator then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	local track = rig.Animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action2
	track.Looped = false
	track:Play(0.05)
	return track
end

function ViewmodelController:_onLocalAbilityBegin(kitId: string, abilityType: string)
	-- Swap to fists for now (kit visuals reuse fists).
	self._previousSlot = self._activeSlot or "Fists"
	self:SetActiveSlot("Fists")

	-- Moviee-style generic names:
	-- Ability: Charge
	-- Ultimate: Activate
	if abilityType == "Ultimate" then
		self:_playKitAnim(kitId, abilityType, "Activate")
	else
		self:_playKitAnim(kitId, abilityType, "Charge")
	end
end

function ViewmodelController:_onLocalAbilityEnd(kitId: string, abilityType: string)
	local track = nil
	if abilityType ~= "Ultimate" then
		track = self:_playKitAnim(kitId, abilityType, "Release")
	end

	local returnSlot = self._previousSlot or "Primary"
	self._previousSlot = nil

	if track then
		track.Stopped:Once(function()
			self:SetActiveSlot(returnSlot)
		end)
	else
		self:SetActiveSlot(returnSlot)
	end
end

function ViewmodelController:Destroy()
	if self._renderConn then
		self._renderConn:Disconnect()
		self._renderConn = nil
	end
	if self._kitConn then
		self._kitConn:Disconnect()
		self._kitConn = nil
	end
	if self._startMatchConn then
		self._startMatchConn:Disconnect()
		self._startMatchConn = nil
	end
	if self._attrConn then
		self._attrConn:Disconnect()
		self._attrConn = nil
	end
	if self._equipKeysConn then
		self._equipKeysConn:Disconnect()
		self._equipKeysConn = nil
	end

	if self._loadoutVm then
		self._loadoutVm:Destroy()
		self._loadoutVm = nil
	end

	if self._animator then
		self._animator:Unbind()
	end
end

return ViewmodelController

