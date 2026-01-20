local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))

local CreateLoadout = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("CreateLoadout"))
local ViewmodelAnimator = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("ViewmodelAnimator"))
local MovementStateManager = require(Locations.Game:WaitForChild("Movement"):WaitForChild("MovementStateManager"))
local Spring = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("Spring"))
local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local ViewmodelController = {}

local LocalPlayer = Players.LocalPlayer

local ROTATION_SENSITIVITY = -3.2
local ROTATION_SPRING_SPEED = 18
local ROTATION_SPRING_DAMPER = 0.85

local MOVE_SPEED_REFERENCE = 16
local MOVE_ROLL_MAX = math.rad(16)
local MOVE_PITCH_MAX = math.rad(8)
local MOVE_ROTATION_FORCE = 0.85

local BOB_SPRING_SPEED = 14
local BOB_SPRING_DAMPER = 0.85
local BOB_FREQ = 6
local BOB_AMP_X = 0.04
local BOB_AMP_Y = 0.03
local VERT_SPEED_REFERENCE = 24
local VERT_AMP_Y = 0.08

local TILT_SPRING_SPEED = 12
local TILT_SPRING_DAMPER = 0.9
local SLIDE_ROLL = math.rad(14)
local SLIDE_PITCH = math.rad(6)
local SLIDE_TUCK = Vector3.new(0.12, -0.12, 0.18)

ViewmodelController._registry = nil
ViewmodelController._net = nil

ViewmodelController._loadout = nil
ViewmodelController._loadoutVm = nil -- object from CreateLoadout
ViewmodelController._activeSlot = nil
ViewmodelController._previousSlot = nil

ViewmodelController._animator = nil
ViewmodelController._springs = nil
ViewmodelController._prevCamCF = nil
ViewmodelController._bobT = 0
ViewmodelController._wasSliding = false
ViewmodelController._slideTiltTarget = Vector3.zero

ViewmodelController._renderConn = nil
ViewmodelController._renderBound = false
ViewmodelController._kitConn = nil
ViewmodelController._startMatchConn = nil
ViewmodelController._attrConn = nil
ViewmodelController._equipKeysConn = nil

ViewmodelController._gameplayEnabled = false
ViewmodelController._externalOffsetFunc = nil -- Function for continuous offset updates (e.g. ADS)

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

local function getRootPart(): BasePart?
	local character = LocalPlayer and LocalPlayer.Character
	if not character then
		return nil
	end
	return character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
end

local function getRigForSlot(self, slot: string)
	return self._loadoutVm and self._loadoutVm.Rigs and self._loadoutVm.Rigs[slot] or nil
end

local function axisAngleToCFrame(vec: Vector3): CFrame
	local angle = vec.Magnitude
	if angle < 1e-5 then
		return CFrame.new()
	end
	return CFrame.fromAxisAngle(vec / angle, angle)
end

function ViewmodelController:Init(registry, net)
	self._registry = registry
	self._net = net

	ServiceRegistry:SetRegistry(registry)
	ServiceRegistry:RegisterController("Viewmodel", self)

	self._animator = ViewmodelAnimator.new()
	self._springs = {
		rotation = Spring.new(Vector3.zero),
		bob = Spring.new(Vector3.zero),
		tiltRot = Spring.new(Vector3.zero),
		tiltPos = Spring.new(Vector3.zero),
		externalPos = Spring.new(Vector3.zero),
		externalRot = Spring.new(Vector3.zero),
	}
	self._springs.rotation.Speed = ROTATION_SPRING_SPEED
	self._springs.rotation.Damper = ROTATION_SPRING_DAMPER
	self._springs.bob.Speed = BOB_SPRING_SPEED
	self._springs.bob.Damper = BOB_SPRING_DAMPER
	self._springs.tiltRot.Speed = TILT_SPRING_SPEED
	self._springs.tiltRot.Damper = TILT_SPRING_DAMPER
	self._springs.tiltPos.Speed = TILT_SPRING_SPEED
	self._springs.tiltPos.Damper = TILT_SPRING_DAMPER
	self._springs.externalPos.Speed = 12
	self._springs.externalPos.Damper = 0.85
	self._springs.externalRot.Speed = 12
	self._springs.externalRot.Damper = 0.85
	self._prevCamCF = nil
	self._bobT = 0
	self._wasSliding = false
	self._slideTiltTarget = Vector3.zero

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

	-- Equip hotkeys (PC): 1=Primary, 2=Secondary, 3=Melee.
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
				if
					manager.IsMenuOpen
					or manager.IsChatFocused
					or manager.IsSettingsOpen
					or not manager.GameplayEnabled
				then
					return
				end
			end

			local key = input.KeyCode
			if key == Enum.KeyCode.One then
				self:_tryEquipSlotFromLoadout("Primary")
			elseif key == Enum.KeyCode.Two then
				self:_tryEquipSlotFromLoadout("Secondary")
			elseif key == Enum.KeyCode.Three then
				self:_tryEquipSlotFromLoadout("Melee")
			end
		end)
	end
end

function ViewmodelController:Start() end

function ViewmodelController:CreateLoadout(loadout: { [string]: any })
	self._loadout = loadout

	if self._loadoutVm then
		self._loadoutVm:Destroy()
		self._loadoutVm = nil
	end

	self._loadoutVm = CreateLoadout.create(loadout, LocalPlayer)

	-- Preload viewmodel animations before the rig is ever shown.
	if self._animator and self._loadoutVm and self._loadoutVm.Rigs then
		for slot, rig in pairs(self._loadoutVm.Rigs) do
			local weaponId = nil
			if slot == "Fists" then
				weaponId = "Fists"
			else
				local id = self._loadout and self._loadout[slot]
				if type(id) == "string" then
					weaponId = id
				end
			end
			if weaponId then
				self._animator:PreloadRig(rig, weaponId)
			end
		end
	end

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

	-- Play equip animation when switching weapons.
	if self._animator then
		self._animator:Play("Equip", 0.1, true)
	end

	self:_ensureRenderLoop()
end

function ViewmodelController:PlayViewmodelAnimation(name: string, fade: number?, restart: boolean?)
	if self._animator and type(self._animator.Play) == "function" then
		self._animator:Play(name, fade, restart)
	end
end

function ViewmodelController:PlayWeaponTrack(name: string, fade: number?)
	if not self._animator or type(self._animator.GetTrack) ~= "function" then
		return nil
	end

	local track = self._animator:GetTrack(name)
	if track then
		track:Play(fade or 0.1)
	end
	return track
end

--[[
	SetOffset: Set an external offset for the viewmodel.
	
	@param offsetOrFunc - Either a static CFrame OR a function that returns a CFrame.
	                      If a function is passed, it will be called every frame to get the offset.
	                      This is useful for ADS where the offset needs to track an attachment.
	@return function - Call this to reset the offset back to zero.
]]
function ViewmodelController:SetOffset(offsetOrFunc: CFrame | () -> CFrame)
	-- Check if it's a function (for continuous updates like ADS)
	if type(offsetOrFunc) == "function" then
		self._externalOffsetFunc = offsetOrFunc
		-- Immediately apply the first frame
		local offset = offsetOrFunc()
		if offset then
			local pos = offset.Position
			local rx, ry, rz = offset:ToEulerAnglesXYZ()
			self._springs.externalPos.Target = pos
			self._springs.externalRot.Target = Vector3.new(rx, ry, rz)
		end
	else
		-- Static CFrame - clear any function and set directly
		self._externalOffsetFunc = nil
		local pos = offsetOrFunc.Position
		local rx, ry, rz = offsetOrFunc:ToEulerAnglesXYZ()
		self._springs.externalPos.Target = pos
		self._springs.externalRot.Target = Vector3.new(rx, ry, rz)
	end

	return function()
		self._externalOffsetFunc = nil
		self._springs.externalPos.Target = Vector3.zero
		self._springs.externalRot.Target = Vector3.zero
	end
end

function ViewmodelController:GetActiveRig()
	if not self._loadoutVm or not self._activeSlot then
		return nil
	end
	return self._loadoutVm.Rigs[self._activeSlot]
end

function ViewmodelController:GetRigForSlot(slot: string)
	if not self._loadoutVm or not self._loadoutVm.Rigs then
		return nil
	end
	return self._loadoutVm.Rigs[slot]
end

function ViewmodelController:GetActiveSlot(): string?
	return self._activeSlot
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
	if self._renderConn or self._renderBound then
		return
	end

	-- Update AFTER CameraController ("MovieeV2CameraController" runs at Camera + 10).
	-- This removes the 1-frame "delay" feeling when flicking the camera.
	self._renderBound = true
	pcall(function()
		RunService:UnbindFromRenderStep("ViewmodelRender")
	end)
	RunService:BindToRenderStep("ViewmodelRender", Enum.RenderPriority.Camera.Value + 11, function(dt)
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

	local springs = self._springs
	if not springs then
		return
	end

	local yawCF
	do
		local look = cam.CFrame.LookVector
		local yaw = math.atan2(look.X, look.Z)
		yawCF = CFrame.Angles(0, yaw, 0)
	end

	-- Rotation spring from camera delta + movement direction.
	do
		if self._prevCamCF then
			local diff = self._prevCamCF:ToObjectSpace(cam.CFrame)
			local axis, angle = diff:ToAxisAngle()
			if angle == angle then
				local angularDisp = axis * angle
				springs.rotation:Impulse(angularDisp * ROTATION_SENSITIVITY)
			end
		end
		self._prevCamCF = cam.CFrame

		local root = getRootPart()
		local vel = root and root.AssemblyLinearVelocity or Vector3.zero
		local horizontal = Vector3.new(vel.X, 0, vel.Z)
		local localVel = yawCF:VectorToObjectSpace(horizontal)
		local moveX = math.clamp(localVel.X / MOVE_SPEED_REFERENCE, -1, 1)
		local moveZ = math.clamp(localVel.Z / MOVE_SPEED_REFERENCE, -1, 1)
		local roll = moveX * MOVE_ROLL_MAX
		local pitch = -moveZ * MOVE_PITCH_MAX
		springs.rotation:Impulse(Vector3.new(pitch, 0, roll) * MOVE_ROTATION_FORCE)
	end

	-- Walk bob (figure-eight path).
	local bobTarget = Vector3.zero
	do
		local root = getRootPart()
		local vel = root and root.AssemblyLinearVelocity or Vector3.zero
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local grounded = MovementStateManager:GetIsGrounded()
		local isMoving = grounded and speed > 0.5
		local verticalOffset = math.clamp(vel.Y / VERT_SPEED_REFERENCE, -1, 1) * VERT_AMP_Y
		if isMoving then
			local speedScale = math.clamp(speed / 12, 0.7, 1.7)
			self._bobT += dt * BOB_FREQ * speedScale
			bobTarget =
				Vector3.new(math.sin(self._bobT) * BOB_AMP_X, math.sin(self._bobT * 2) * BOB_AMP_Y + verticalOffset, 0)
		else
			self._bobT = 0
			bobTarget = Vector3.new(0, verticalOffset, 0)
		end
		springs.bob.Target = bobTarget
	end

	-- Slide tilt (tuck + rotate).
	do
		local isSliding = MovementStateManager:IsSliding()
		if isSliding then
			if not self._wasSliding then
				local root = getRootPart()
				local vel = root and root.AssemblyLinearVelocity or Vector3.zero
				local horizontal = Vector3.new(vel.X, 0, vel.Z)
				local localDir
				if horizontal.Magnitude > 0.1 then
					local slideDir = horizontal.Unit
					localDir = yawCF:VectorToObjectSpace(slideDir)
				else
					localDir = Vector3.new(0, 0, -1)
				end
				local roll = -math.clamp(localDir.X, -1, 1) * SLIDE_ROLL
				local pitch = -math.clamp(localDir.Z, -1, 1) * SLIDE_PITCH
				self._slideTiltTarget = Vector3.new(pitch, 0, roll)
			end
			self._wasSliding = true
			springs.tiltRot.Target = self._slideTiltTarget
			springs.tiltPos.Target = SLIDE_TUCK
		else
			self._wasSliding = false
			self._slideTiltTarget = Vector3.zero
			springs.tiltRot.Target = Vector3.zero
			springs.tiltPos.Target = Vector3.zero
		end
	end

	-- Align rig so its Anchor part matches the camera.
	-- Equivalent to Moviee: Camera.CFrame * (modelPivot:ToObjectSpace(anchorPivot))^-1 * offsets
	local pivot = rig.Model:GetPivot()
	local anchorPivot = rig.Anchor:GetPivot()
	local align = pivot:ToObjectSpace(anchorPivot):Inverse()

	local weaponId = nil
	if self._activeSlot == "Fists" then
		weaponId = "Fists"
	elseif self._loadout and type(self._loadout[self._activeSlot]) == "string" then
		weaponId = self._loadout[self._activeSlot]
	end
	local cfg = ViewmodelConfig.Weapons[weaponId or ""] or ViewmodelConfig.Weapons.Fists
	local baseOffset = (cfg and cfg.Offset) or CFrame.new()
	
	-- If we have an offset function (e.g. ADS tracking), call it each frame to update targets
	if self._externalOffsetFunc then
		local offset = self._externalOffsetFunc()
		if offset then
			local pos = offset.Position
			local rx, ry, rz = offset:ToEulerAnglesXYZ()
			springs.externalPos.Target = pos
			springs.externalRot.Target = Vector3.new(rx, ry, rz)
		end
	end
	
	local extPos = springs.externalPos.Position
	local extRot = springs.externalRot.Position
	local externalOffset = CFrame.new(extPos) * CFrame.Angles(extRot.X, extRot.Y, extRot.Z)

	local rotationOffset = CFrame.Angles(springs.rotation.Position.X, 0, springs.rotation.Position.Z)
	local tiltRotOffset = CFrame.Angles(springs.tiltRot.Position.X, 0, springs.tiltRot.Position.Z)
	local offset = springs.bob.Position + springs.tiltPos.Position

	local target = cam.CFrame
		* align
		* baseOffset
		* externalOffset
		* rotationOffset
		* tiltRotOffset
		* CFrame.new(offset)
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
	if self._renderBound then
		self._renderBound = false
		pcall(function()
			RunService:UnbindFromRenderStep("ViewmodelRender")
		end)
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
