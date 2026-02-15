local ContentProvider = game:GetService("ContentProvider")
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
local ViewmodelRig = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("ViewmodelRig"))
local ViewmodelAppearance = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("ViewmodelAppearance"))
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
local SLIDE_ROLL = math.rad(30) -- Constant tilt to the right when sliding
local SLIDE_PITCH = math.rad(6)
local SLIDE_YAW = math.rad(0) -- No yaw rotation
local SLIDE_TUCK = Vector3.new(0.12, -0.12, 0.18)

local DEFAULT_ADS_EFFECTS_MULTIPLIER = 0.25
local ADS_LERP_SPEED = 15

ViewmodelController._registry = nil
ViewmodelController._net = nil

ViewmodelController._loadout = nil
ViewmodelController._loadoutVm = nil
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
ViewmodelController._ziplineAttrConn = nil
ViewmodelController._equipKeysConn = nil

ViewmodelController._rigStorage = nil
ViewmodelController._storedRigs = nil
ViewmodelController._equippedSkins = nil
ViewmodelController._cachedKitTracks = nil

ViewmodelController._adsActive = false
ViewmodelController._adsBlend = 0
ViewmodelController._adsEffectsMultiplier = DEFAULT_ADS_EFFECTS_MULTIPLIER
ViewmodelController._ziplineActive = false

local RIG_STORAGE_POSITION = CFrame.new(0, 10000, 0)

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

local function isHudVisible(): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return false
	end
	local screenGui = playerGui:FindFirstChild("Gui")
	if not screenGui then
		return false
	end
	local hud = screenGui:FindFirstChild("Hud")
	if not hud or not hud:IsA("GuiObject") then
		return false
	end
	return hud.Visible == true
end

local function isLoadoutVisible(): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return false
	end
	local screenGui = playerGui:FindFirstChild("Gui")
	if not screenGui then
		return false
	end
	local loadout = screenGui:FindFirstChild("Loadout")
	if not loadout or not loadout:IsA("GuiObject") then
		return false
	end
	return loadout.Visible == true
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

	-- Preload kit animations from Assets/Animations/ViewModel/Kits/
	ViewmodelAnimator.PreloadKitAnimations()

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

	if self._net and self._net.ConnectClient then
		self._startMatchConn = self._net:ConnectClient("StartMatch", function(_matchData)
			self:SetActiveSlot("Primary")
		end)

		self._kitConn = self._net:ConnectClient("KitState", function(message)
			self:_onKitMessage(message)
		end)
	end

	if LocalPlayer then
		local function onSelectedLoadoutChanged()
			local raw = LocalPlayer:GetAttribute("SelectedLoadout")
			if type(raw) ~= "string" or raw == "" then
				self:ClearLoadout()
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
				loadout = decoded
			end

			self:CreateLoadout(loadout)
		end

		self._attrConn = LocalPlayer:GetAttributeChangedSignal("SelectedLoadout"):Connect(onSelectedLoadoutChanged)
		task.defer(onSelectedLoadoutChanged)

		local function onZiplineActiveChanged()
			local active = LocalPlayer:GetAttribute("ZiplineActive")
			self:_setZiplineActive(active == true)
		end

		self._ziplineAttrConn = LocalPlayer:GetAttributeChangedSignal("ZiplineActive"):Connect(onZiplineActiveChanged)
		task.defer(onZiplineActiveChanged)
	end

	do
		local inputController = self._registry and self._registry:TryGet("Input")
		local manager = inputController and inputController.Manager or nil

		self._equipKeysConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			local key = input.KeyCode
			local isGamepad = input.UserInputType == Enum.UserInputType.Gamepad1
				or input.UserInputType == Enum.UserInputType.Gamepad2
				or input.UserInputType == Enum.UserInputType.Gamepad3
				or input.UserInputType == Enum.UserInputType.Gamepad4
			local isShoulder = key == Enum.KeyCode.ButtonL1 or key == Enum.KeyCode.ButtonR1

			if gameProcessed and not (isGamepad and isShoulder and isHudVisible() and not isLoadoutVisible()) then
				return
			end

			if manager then
				if
					manager.IsMenuOpen
					or manager.IsChatFocused
					or manager.IsSettingsOpen
				then
					return
				end
			end

			if key == Enum.KeyCode.One then
				self:_tryEquipSlotFromLoadout("Primary")
			elseif key == Enum.KeyCode.Two then
				self:_tryEquipSlotFromLoadout("Secondary")
			elseif key == Enum.KeyCode.Three then
				self:_tryEquipSlotFromLoadout("Melee")
			elseif key == Enum.KeyCode.Four then
				self:SetActiveSlot("Fists")
			elseif isGamepad then
				if isLoadoutVisible() then
					return
				end
				if not isHudVisible() then
					return
				end
				if key == Enum.KeyCode.ButtonL1 then
					self:_cycleEquipSlot(-1)
				elseif key == Enum.KeyCode.ButtonR1 then
					self:_cycleEquipSlot(1)
				end
			end
		end)

		-- Mobile weapon wheel slot change
		if inputController.ConnectToInput then
			inputController:ConnectToInput("SlotChange", function(slot)
				if slot == "Fists" then
					self:SetActiveSlot("Fists")
				else
					self:_tryEquipSlotFromLoadout(slot)
				end
			end)
		end
	end
end

function ViewmodelController:Start() end

function ViewmodelController:_ensureRigStorage(): Folder
	if self._rigStorage and self._rigStorage.Parent then
		return self._rigStorage
	end

	local folder = Instance.new("Folder")
	folder.Name = "ViewmodelRigStorage"
	folder.Parent = ReplicatedStorage
	self._rigStorage = folder

	return folder
end

function ViewmodelController:_destroyAllRigs()
	if self._storedRigs then
		for _, rig in pairs(self._storedRigs) do
			if rig and rig.Destroy then
				rig:Destroy()
			end
		end
		self._storedRigs = nil
	end

	self._cachedKitTracks = nil
end

function ViewmodelController:_createAllRigsForLoadout(loadout: { [string]: any })
	local storage = self:_ensureRigStorage()
	self._storedRigs = {}
	self._equippedSkins = {} -- Track equipped skins for animation lookups

	local toPreload = {}

	-- Get equipped skin for a weapon from PlayerDataTable
	local PlayerDataTable = require(ReplicatedStorage:WaitForChild("PlayerDataTable"))
	local function getEquippedSkin(weaponId: string): string?
		local success, skinId = pcall(function()
			return PlayerDataTable.getEquippedSkin(weaponId)
		end)
		return success and skinId or nil
	end

	local function getModelPath(weaponId: string, skinId: string?): string?
		if weaponId == "Fists" then
			local fistsCfg = ViewmodelConfig.Weapons.Fists
			return fistsCfg and fistsCfg.ModelPath or ViewmodelConfig.Models.Fists
		end

		-- Check for skin-specific model path first
		if skinId and ViewmodelConfig.Skins then
			local weaponSkins = ViewmodelConfig.Skins[weaponId]
			if weaponSkins and weaponSkins[skinId] and weaponSkins[skinId].ModelPath then
				return weaponSkins[skinId].ModelPath
			end
		end

		-- Fall back to base weapon model path
		local weaponCfg = ViewmodelConfig.Weapons[weaponId]
		return weaponCfg and weaponCfg.ModelPath
			or (ViewmodelConfig.Models.ByWeaponId and ViewmodelConfig.Models.ByWeaponId[weaponId])
	end

	local function resolveModelTemplate(modelPath: string): Model?
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local viewModelsRoot = assets and assets:FindFirstChild("ViewModels")
		if not viewModelsRoot then
			return nil
		end

		local current: Instance = viewModelsRoot
		for _, part in ipairs(string.split(modelPath, "/")) do
			current = current:FindFirstChild(part)
			if not current then
				return nil
			end
		end

		if current:IsA("Model") then
			return current
		end
		return nil
	end

	local function createRig(weaponId: string, slotName: string, skinId: string?)
		local modelPath = getModelPath(weaponId, skinId)
		if type(modelPath) ~= "string" or modelPath == "" then
			return nil
		end

		local template = resolveModelTemplate(modelPath)
		if not template then
			-- If skin model not found, fall back to base weapon model
			if skinId then
				LogService:Info("VIEWMODEL", "Skin model not found, falling back to base", { WeaponId = weaponId, SkinId = skinId })
				modelPath = getModelPath(weaponId, nil)
				if type(modelPath) == "string" and modelPath ~= "" then
					template = resolveModelTemplate(modelPath)
				end
			end
			if not template then
				LogService:Warn("VIEWMODEL", "Missing viewmodel template", { WeaponId = weaponId, Path = modelPath })
				return nil
			end
		end

		local clone = template:Clone()
		clone.Name = slotName
		clone:PivotTo(RIG_STORAGE_POSITION)
		clone.Parent = storage

		local rig = ViewmodelRig.new(clone, slotName)
		rig._skinId = skinId -- Store skin ID for animation lookups
		if LocalPlayer then
			rig:AddCleanup(ViewmodelAppearance.BindShirtToLocalRig(LocalPlayer, clone))
		end

		table.insert(toPreload, clone)
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("MeshPart") or desc:IsA("Decal") or desc:IsA("Texture") then
				table.insert(toPreload, desc)
			end
		end

		return rig
	end

	local fistsRig = createRig("Fists", "Fists", nil)
	if fistsRig then
		self._storedRigs.Fists = fistsRig

		if self._animator then
			self._animator:PreloadRig(fistsRig, "Fists", nil)
		end

		self:_preloadKitAnimations(fistsRig)
	end

	local primaryId = loadout and loadout.Primary
	if type(primaryId) == "string" and primaryId ~= "" then
		local primarySkin = getEquippedSkin(primaryId)
		self._equippedSkins.Primary = primarySkin
		local rig = createRig(primaryId, "Primary", primarySkin)
		if rig then
			self._storedRigs.Primary = rig
			if self._animator then
				self._animator:PreloadRig(rig, primaryId, primarySkin)
			end
		end
	end

	local secondaryId = loadout and loadout.Secondary
	if type(secondaryId) == "string" and secondaryId ~= "" then
		local secondarySkin = getEquippedSkin(secondaryId)
		self._equippedSkins.Secondary = secondarySkin
		local rig = createRig(secondaryId, "Secondary", secondarySkin)
		if rig then
			self._storedRigs.Secondary = rig
			if self._animator then
				self._animator:PreloadRig(rig, secondaryId, secondarySkin)
			end
		end
	end

	local meleeId = loadout and loadout.Melee
	if type(meleeId) == "string" and meleeId ~= "" then
		local meleeSkin = getEquippedSkin(meleeId)
		self._equippedSkins.Melee = meleeSkin
		local rig = createRig(meleeId, "Melee", meleeSkin)
		if rig then
			self._storedRigs.Melee = rig
			if self._animator then
				self._animator:PreloadRig(rig, meleeId, meleeSkin)
			end
		end
	end

	if #toPreload > 0 then
		task.spawn(function()
			ContentProvider:PreloadAsync(toPreload)
			LogService:Info("VIEWMODEL", "Model assets preloaded", { Count = #toPreload })
		end)
	end

	LogService:Info("VIEWMODEL", "All rigs created and preloaded", {
		Fists = self._storedRigs.Fists ~= nil,
		Primary = self._storedRigs.Primary ~= nil,
		Secondary = self._storedRigs.Secondary ~= nil,
		Melee = self._storedRigs.Melee ~= nil,
	})

	return self._storedRigs
end

function ViewmodelController:_preloadKitAnimations(fistsRig)
	if not fistsRig or not fistsRig.Animator then
		return
	end

	self._cachedKitTracks = {}

	local toPreload = {}
	local trackCount = 0

	-- System 1: Preload from ViewmodelConfig.Kits (asset ID based)
	local kitsConfig = ViewmodelConfig.Kits
	if type(kitsConfig) == "table" then
		for kitId, kitData in pairs(kitsConfig) do
			self._cachedKitTracks[kitId] = {
				Ability = {},
				Ultimate = {},
			}

			if type(kitData.Ability) == "table" then
				for animName, animId in pairs(kitData.Ability) do
					if type(animId) == "string" and animId ~= "" and animId ~= "rbxassetid://0" then
						local animation = Instance.new("Animation")
						animation.AnimationId = animId

						local track = fistsRig.Animator:LoadAnimation(animation)
						track.Priority = Enum.AnimationPriority.Action2
						track.Looped = false

						track:Play(0)
						track:Stop(0)

						self._cachedKitTracks[kitId].Ability[animName] = track
						table.insert(toPreload, animation)
						trackCount = trackCount + 1
					end
				end
			end

			if type(kitData.Ultimate) == "table" then
				for animName, animId in pairs(kitData.Ultimate) do
					if type(animId) == "string" and animId ~= "" and animId ~= "rbxassetid://0" then
						local animation = Instance.new("Animation")
						animation.AnimationId = animId

						local track = fistsRig.Animator:LoadAnimation(animation)
						track.Priority = Enum.AnimationPriority.Action2
						track.Looped = false

						track:Play(0)
						track:Stop(0)

						self._cachedKitTracks[kitId].Ultimate[animName] = track
						table.insert(toPreload, animation)
						trackCount = trackCount + 1
					end
				end
			end
		end
	end

	-- System 2: Preload from file-based animations (Assets/Animations/ViewModel/Kits/)
	-- This preloads tracks for ViewmodelAnimator:PlayKitAnimation() usage
	local preloadedAnims = ViewmodelAnimator.PreloadKitAnimations()
	if preloadedAnims and self._animator then
		for animKey, animInstance in pairs(preloadedAnims) do
			if animInstance and animInstance:IsA("Animation") then
				local animId = animInstance.AnimationId
				if animId and animId ~= "" and animId ~= "rbxassetid://0" then
					local success, track = pcall(function()
						return fistsRig.Animator:LoadAnimation(animInstance)
					end)

					if success and track then
						track.Priority = Enum.AnimationPriority.Action4
						track.Looped = false

						track:Play(0)
						track:Stop(0)

						-- Cache the track on the animator instance for PlayKitAnimation
						if not self._animator._kitTracks then
							self._animator._kitTracks = {}
						end
						self._animator._kitTracks[animKey] = track
						trackCount = trackCount + 1
					end
				end
			end
		end
	end

	if #toPreload > 0 then
		task.spawn(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
	end

	LogService:Info("VIEWMODEL", "Kit animations preloaded", { Count = trackCount })
end

function ViewmodelController:CreateLoadout(loadout: { [string]: any })
	self._loadout = loadout

	self:_destroyAllRigs()

	if self._loadoutVm then
		self._loadoutVm = nil
	end

	local rigs = self:_createAllRigsForLoadout(loadout)

	self._loadoutVm = {
		Rigs = rigs,
		Destroy = function(obj)
			obj.Rigs = nil
		end,
	}

	self:SetActiveSlot("Primary")

	LogService:Info("VIEWMODEL", "CreateLoadout complete", {
		Primary = tostring(loadout.Primary),
		Secondary = tostring(loadout.Secondary),
		Melee = tostring(loadout.Melee),
	})
end

function ViewmodelController:ClearLoadout()
	self:_destroyAllRigs()
	if self._loadoutVm then
		self._loadoutVm = nil
	end
	self._loadout = nil
	self._activeSlot = nil
	self._previousSlot = nil
	self._adsActive = false
	self._adsBlend = 0
	if self._animator then
		self._animator:Unbind()
	end
end

function ViewmodelController:RefreshLoadoutFromAttributes()
	local raw = LocalPlayer and LocalPlayer:GetAttribute("SelectedLoadout")
	if type(raw) ~= "string" or raw == "" then
		self:ClearLoadout()
		return
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok or type(decoded) ~= "table" then
		return
	end
	local loadout = decoded.loadout or decoded
	if type(loadout) ~= "table" then
		return
	end
	self:CreateLoadout(loadout)
	local slot = LocalPlayer:GetAttribute("EquippedSlot") or "Primary"
	self:SetActiveSlot(slot)
end

function ViewmodelController:SetActiveSlot(slot: string)
	if type(slot) ~= "string" then
		return
	end

	if not self._loadoutVm or not self._loadoutVm.Rigs then
		return
	end

	if not self._loadoutVm.Rigs[slot] then
		slot = "Fists"
	end

	if self._activeSlot == slot then
		return
	end

	self._previousSlot = self._activeSlot
	self._activeSlot = slot
	self._adsActive = false
	self._adsBlend = 0

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

	local cam = getCamera()
	for _, rig in pairs(self._loadoutVm.Rigs) do
		if rig and rig.Model then
			if isFirstPerson(self) and cam then
				rig.Model.Parent = cam
			else
				rig.Model.Parent = nil
			end
		end
	end

	do
		local rig = getRigForSlot(self, slot)
		local weaponId = nil
		local skinId = nil
		if slot == "Fists" then
			weaponId = "Fists"
		elseif self._loadout and type(self._loadout[slot]) == "string" then
			weaponId = self._loadout[slot]
			skinId = self._equippedSkins and self._equippedSkins[slot]
		end
		self._animator:BindRig(rig, weaponId, skinId)
	end

	if self._animator then
		self._animator:Play("Equip", 0.1, true)
	end
	if self._ziplineActive and self._animator then
		self._animator:Play("ZiplineHold", 0.05, true)
	end

	self:_ensureRenderLoop()
end

function ViewmodelController:SetADS(active: boolean, effectsMultiplier: number?)
	self._adsActive = active and true or false
	if type(effectsMultiplier) == "number" then
		self._adsEffectsMultiplier = effectsMultiplier
	else
		self._adsEffectsMultiplier = DEFAULT_ADS_EFFECTS_MULTIPLIER
	end
end

function ViewmodelController:IsADS(): boolean
	return self._adsActive
end

function ViewmodelController:GetADSBlend(): number
	return self._adsBlend
end

function ViewmodelController:_setZiplineActive(active: boolean)
	active = active == true
	if self._ziplineActive == active then
		return
	end
	self._ziplineActive = active
	if active then
		if isFirstPerson(self) then
			if self._animator then
				local fast = LocalPlayer and LocalPlayer:GetAttribute("ZiplineHookupFast") == true
				local hookName = fast and "ZiplineFastHookUp" or "ZiplineHookUp"
				self._animator:Play(hookName, 0.05, true)
				local track = self._animator:GetTrack(hookName)
				if track then
					track.Stopped:Once(function()
						if self._ziplineActive then
							self._animator:Play("ZiplineHold", 0.05, true)
						end
					end)
				else
					self._animator:Play("ZiplineHold", 0.05, true)
				end
			end
			local rig = getRigForSlot(self, self._activeSlot)
			-- zipline animation only
		end
	else
		if self._animator then
			self._animator:Stop("ZiplineHold", 0)
			self._animator:Stop("ZiplineHookUp", 0)
			self._animator:Stop("ZiplineFastHookUp", 0)
		end
	end
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

function ViewmodelController:GetCurrentMovementTrack(): string?
	if not self._animator then
		return nil
	end

	local move = self._animator._currentMove
	if move == "Idle" or move == "Walk" or move == "Run" then
		return move
	end

	return nil
end

function ViewmodelController:SetOffset(offset: CFrame)
	local pos = offset.Position
	local rx, ry, rz = offset:ToEulerAnglesXYZ()
	self._springs.externalPos.Target = pos
	self._springs.externalRot.Target = Vector3.new(rx, ry, rz)

	return function()
		self._springs.externalPos.Target = Vector3.zero
		self._springs.externalRot.Target = Vector3.zero
	end
end

--[[
	Applies recoil to the viewmodel using spring impulses.
	The viewmodel will kick back and naturally return via spring physics.

	@param kickPos: Vector3 - Position impulse (e.g., Vector3.new(0, 0.02, 0.1) for back+up kick)
	@param kickRot: Vector3 - Rotation impulse in radians (e.g., Vector3.new(-0.1, 0, 0) for upward pitch)
]]
function ViewmodelController:ApplyRecoil(kickPos, kickRot)
	if not self._springs then
		return
	end

	if kickPos then
		self._springs.externalPos:Impulse(kickPos)
	end

	if kickRot then
		self._springs.externalRot:Impulse(kickRot)
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
	if type(slot) ~= "string" then
		return
	end
	if not self._loadout or type(self._loadout) ~= "table" then
		return
	end

	-- Block weapon swapping while ability is active
	local kitController = ServiceRegistry:GetController("Kit")
	if kitController and kitController:IsWeaponSwitchLocked() then
		return
	end

	local weaponId = self._loadout[slot]
	if type(weaponId) ~= "string" or weaponId == "" then
		return
	end

	self:SetActiveSlot(slot)
end

function ViewmodelController:_cycleEquipSlot(direction: number)
	if not self._loadout or type(self._loadout) ~= "table" then
		return
	end

	local slots = {}
	for _, slotName in ipairs({ "Primary", "Secondary", "Melee" }) do
		local weaponId = self._loadout[slotName]
		if type(weaponId) == "string" and weaponId ~= "" then
			table.insert(slots, slotName)
		end
	end

	if #slots <= 1 then
		return
	end

	local current = self._activeSlot
	if current == "Fists" or current == nil then
		current = slots[1]
	end

	local currentIndex = 1
	for i, name in ipairs(slots) do
		if name == current then
			currentIndex = i
			break
		end
	end

	local nextIndex = currentIndex + (direction >= 0 and 1 or -1)
	if nextIndex < 1 then
		nextIndex = #slots
	elseif nextIndex > #slots then
		nextIndex = 1
	end

	self:_tryEquipSlotFromLoadout(slots[nextIndex])
end

function ViewmodelController:_ensureRenderLoop()
	if self._renderConn or self._renderBound then
		return
	end

	self._renderBound = true
	pcall(function()
		RunService:UnbindFromRenderStep("ViewmodelRender")
	end)
	RunService:BindToRenderStep("ViewmodelRender", Enum.RenderPriority.Camera.Value + 12, function(dt)
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

	if not isFirstPerson(self) then
		for _, rig in pairs(self._loadoutVm.Rigs) do
			if rig and rig.Model then
				rig.Model.Parent = nil
			end
		end
		return
	end

	-- Parent all rigs to camera, position inactive ones offscreen
	for slotName, slotRig in pairs(self._loadoutVm.Rigs) do
		if slotRig and slotRig.Model then
			if slotRig.Model.Parent ~= cam then
				slotRig.Model.Parent = cam
			end
			-- Move inactive rigs offscreen
			if slotName ~= self._activeSlot then
				slotRig.Model:PivotTo(RIG_STORAGE_POSITION)
			end
		end
	end

	local rig = getRigForSlot(self, self._activeSlot)
	if not rig or not rig.Model or not rig.Anchor then
		return
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

	do
		local isSliding = MovementStateManager:IsSliding()
		if isSliding then
			-- Continuously update tilt based on current slide direction
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
			local roll = -SLIDE_ROLL -- Always tilt right when sliding
			local pitch = -math.clamp(localDir.Z, -1, 1) * SLIDE_PITCH
			self._slideTiltTarget = Vector3.new(pitch, SLIDE_YAW, roll)
			
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

	local pivot = rig.Model:GetPivot()
	local anchorPivot = rig.Anchor:GetPivot()

	local weaponId = nil
	if self._activeSlot == "Fists" then
		weaponId = "Fists"
	elseif self._loadout and type(self._loadout[self._activeSlot]) == "string" then
		weaponId = self._loadout[self._activeSlot]
	end
	local cfg = ViewmodelConfig.Weapons[weaponId or ""] or ViewmodelConfig.Weapons.Fists
	local configOffset = (cfg and cfg.Offset) or CFrame.new()

	local basePosition = rig.Model:FindFirstChild("BasePosition", true)
	local aimPosition = rig.Model:FindFirstChild("AimPosition", true)

	if not basePosition then
		warn("[ViewmodelController] Missing BasePosition attachment on rig:", self._activeSlot)
		return
	end

	if not aimPosition then
		warn("[ViewmodelController] Missing AimPosition attachment on rig:", self._activeSlot)
		return
	end

	-- Get LOCAL offsets from pivot (constant, doesn't change with model position)
	local hipOffset = pivot:ToObjectSpace(basePosition.WorldCFrame)
	local adsOffset = pivot:ToObjectSpace(aimPosition.WorldCFrame)

	-- Smooth ADS blend
	local targetBlend = self._adsActive and 1 or 0
	self._adsBlend = self._adsBlend + (targetBlend - self._adsBlend) * math.min(1, dt * ADS_LERP_SPEED)
	
	-- Snap to target when close enough
	if math.abs(self._adsBlend - targetBlend) < 0.001 then
		self._adsBlend = targetBlend
	end

	-- Lerp between the local offsets, then invert to get alignment
	local targetOffset = hipOffset:Lerp(adsOffset, self._adsBlend)
	local normalAlign = targetOffset:Inverse()

	-- Smoothly remove config offset when ADS
	local baseOffset = configOffset:Lerp(CFrame.new(), self._adsBlend)

	local extPos = springs.externalPos.Position
	local extRot = springs.externalRot.Position
	local externalOffset = CFrame.new(extPos) * CFrame.Angles(extRot.X, extRot.Y, extRot.Z)

	local fxScale = 1 - (self._adsBlend * (1 - self._adsEffectsMultiplier))

	local rotationOffset = CFrame.Angles(
		springs.rotation.Position.X * fxScale, 
		0, 
		springs.rotation.Position.Z * fxScale
	)

	local tiltX = math.clamp(springs.tiltRot.Position.X, -SLIDE_PITCH, SLIDE_PITCH) * fxScale
	local yawAbs = math.abs(SLIDE_YAW)
	local tiltY = math.clamp(springs.tiltRot.Position.Y, -yawAbs, yawAbs) * fxScale
	local tiltZ = math.clamp(springs.tiltRot.Position.Z, -SLIDE_ROLL, SLIDE_ROLL) * fxScale
	local tiltRotOffset = CFrame.Angles(tiltX, tiltY, tiltZ)

	local bobOffset = springs.bob.Position * fxScale
	local tiltPosOffset = springs.tiltPos.Position * fxScale
	local posOffset = bobOffset + tiltPosOffset

	local target = cam.CFrame 
		* normalAlign 
		* baseOffset 
		* externalOffset 
		* rotationOffset 
		* tiltRotOffset 
		* CFrame.new(posOffset)

	rig.Model:PivotTo(target)
end

function ViewmodelController:_onKitMessage(message)
	if type(message) ~= "table" then
		return
	end
	if message.kind ~= "Event" then
		return
	end

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

	if self._cachedKitTracks then
		local kitTracks = self._cachedKitTracks[kitId]
		if kitTracks then
			local section = (abilityType == "Ultimate") and kitTracks.Ultimate or kitTracks.Ability
			if section then
				local track = section[name]
				if track then
					track:Play(0.05)
					return track
				end
			end
		end
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
	self._previousSlot = self._activeSlot or "Fists"
	self:SetActiveSlot("Fists")

	if abilityType == "Ultimate" then
		self:_playKitAnim(kitId, abilityType, "Activate")
	else
		self:_playKitAnim(kitId, abilityType, "Charge")
	end
end

function ViewmodelController:_onLocalAbilityEnd(kitId: string, abilityType: string)
	-- Only play the release animation if configured
	-- Slot restoration is handled by KitController:_unholsterWeapon()
	if abilityType ~= "Ultimate" then
		self:_playKitAnim(kitId, abilityType, "Release")
	end

	self._previousSlot = nil
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
	if self._ziplineAttrConn then
		self._ziplineAttrConn:Disconnect()
		self._ziplineAttrConn = nil
	end
	if self._equipKeysConn then
		self._equipKeysConn:Disconnect()
		self._equipKeysConn = nil
	end

	self:_destroyAllRigs()

	if self._loadoutVm then
		self._loadoutVm = nil
	end

	if self._rigStorage then
		self._rigStorage:Destroy()
		self._rigStorage = nil
	end

	if self._animator then
		self._animator:Unbind()
	end
end

return ViewmodelController
