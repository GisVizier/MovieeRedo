local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))
local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local CrouchUtils = require(Locations.Game:WaitForChild("Character"):WaitForChild("CrouchUtils"))
local DEBUG_VM_REPL = true
local function vmLog(...)
	if DEBUG_VM_REPL then
		warn("[VM-ThirdPersonWeaponManager]", ...)
	end
end

local ThirdPersonWeaponManager = {}
ThirdPersonWeaponManager.__index = ThirdPersonWeaponManager

local DEFAULT_SCALE = 0.5725
local DEFAULT_OFFSET = CFrame.new(0, .75, 0)

local LOOPED_TRACKS = {
	Idle = true,
	Walk = true,
	Run = true,
	ADS = true,
}

local ACTION_FALLBACK_TRACK = {
	Fire = "Fire",
	Reload = "Reload",
	Inspect = "Inspect",
	Special = "Special",
	Equip = "Equip",
}

local TRACK_PRIORITIES = {
	Idle = Enum.AnimationPriority.Movement,
	Walk = Enum.AnimationPriority.Movement,
	Run = Enum.AnimationPriority.Movement,
	ADS = Enum.AnimationPriority.Action,
	Fire = Enum.AnimationPriority.Action4,
	Reload = Enum.AnimationPriority.Action4,
	Inspect = Enum.AnimationPriority.Action4,
	Special = Enum.AnimationPriority.Action4,
	Equip = Enum.AnimationPriority.Action4,
}

local CROUCH_REPLICATION_OFFSET = CFrame.new(0, -0.75, 0)

local function getAssetsRoot()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local viewModels = assets and assets:FindFirstChild("ViewModels")
	local animations = assets and assets:FindFirstChild("Animations")
	local viewModelAnimations = animations and animations:FindFirstChild("ViewModel")
	return viewModels, viewModelAnimations
end

local function resolveModelTemplate(modelPath: string)
	local viewModels = select(1, getAssetsRoot())
	if not viewModels then
		return nil
	end

	local current = viewModels
	local parts = string.split(modelPath, "/")
	for _, partName in ipairs(parts) do
		current = current:FindFirstChild(partName)
		if not current then
			return nil
		end
	end

	return current
end

local function resolveAnimationInstance(weaponId: string, animRef: string)
	if type(animRef) ~= "string" or animRef == "" then
		return nil
	end

	if string.find(animRef, "rbxassetid://") then
		local animation = Instance.new("Animation")
		animation.AnimationId = animRef
		return animation
	end

	local viewModelAnimations = select(2, getAssetsRoot())
	if not viewModelAnimations then
		return nil
	end

	local weaponFolder = viewModelAnimations:FindFirstChild(weaponId)
	if not weaponFolder then
		return nil
	end

	local direct = weaponFolder:FindFirstChild(animRef)
	if direct and direct:IsA("Animation") then
		return direct
	end

	local defaultFolder = weaponFolder:FindFirstChild("Viewmodel") or weaponFolder:FindFirstChild("ViewModel")
	if not defaultFolder then
		return nil
	end

	local animation = defaultFolder:FindFirstChild(animRef)
	if animation and animation:IsA("Animation") then
		return animation
	end

	return nil
end

local function resolveNestedChild(root: Instance, path: string): Instance?
	local current = root
	for _, partName in ipairs(string.split(path, "/")) do
		current = current and current:FindFirstChild(partName) or nil
		if not current then
			return nil
		end
	end
	return current
end

local function ensureAnimator(model: Model)
	local animationController = model:FindFirstChildOfClass("AnimationController")
	if not animationController then
		animationController = Instance.new("AnimationController")
		animationController.Name = "AnimationController"
		animationController.Parent = model
	end

	local animator = animationController:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animationController
	end

	return animator
end

local function findModelRoot(model: Model)
	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart", true)
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local cameraPart = model:FindFirstChild("Camera", true)
	if cameraPart and cameraPart:IsA("BasePart") then
		return cameraPart
	end

	local primaryPart = model.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function configureModelParts(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.Anchored = false
		end
	end
end

local function stripFakeModel(model: Model)
	local fake = model:FindFirstChild("Fake")
	if fake then
		fake:Destroy()
		return true
	end
	return false
end

local function stopTracks(tracks)
	for _, track in pairs(tracks) do
		if track and track.IsPlaying then
			pcall(function()
				track:Stop(0.05)
			end)
		end
	end
end

function ThirdPersonWeaponManager.new(rig: Model)
	if not rig then
		return nil
	end

	local self = setmetatable({}, ThirdPersonWeaponManager)
	self.Rig = rig
	self.WeaponModel = nil
	self.WeaponId = nil
	self.WeaponRoot = nil
	self.Weld = nil
	self.Animator = nil
	self.Tracks = {}
	self.ReplicationOffset = DEFAULT_OFFSET
	self.AimPitch = 0
	self._ownerCharacter = nil
	self._lastOwnerResolve = 0
	self._forcedCrouching = nil

	return self
end

function ThirdPersonWeaponManager:_getRigRoot()
	if not self.Rig then
		return nil
	end
	return self.Rig:FindFirstChild("HumanoidRootPart") or self.Rig.PrimaryPart
end

function ThirdPersonWeaponManager:_loadTracks(weaponId: string, weaponConfig)
	self.Tracks = {}
	if not self.Animator or not weaponConfig or not weaponConfig.Animations then
		return
	end

	for trackName, animRef in pairs(weaponConfig.Animations) do
		local animation = resolveAnimationInstance(weaponId, animRef)
		if animation then
			local ok, track = pcall(function()
				return self.Animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = TRACK_PRIORITIES[trackName] or Enum.AnimationPriority.Action
				track.Looped = LOOPED_TRACKS[trackName] == true
				self.Tracks[trackName] = track
			end
		end
	end
end

function ThirdPersonWeaponManager:_getOwnerPlayer(): Player?
	if not self.Rig then
		return nil
	end

	local ownerUserId = self.Rig:GetAttribute("OwnerUserId")
	if type(ownerUserId) == "number" then
		return Players:GetPlayerByUserId(ownerUserId)
	end

	local character = self:_resolveOwnerCharacter()
	if character then
		return Players:GetPlayerFromCharacter(character)
	end

	return nil
end

function ThirdPersonWeaponManager:_loadFistsKitTracks()
	local ownerPlayer = nil
	if self.Rig then
		local ownerUserId = self.Rig:GetAttribute("OwnerUserId")
		if type(ownerUserId) == "number" then
			ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
		end
	end
	if not ownerPlayer then
		local character = self:_resolveOwnerCharacter()
		if character then
			ownerPlayer = Players:GetPlayerFromCharacter(character)
		end
	end
	if not ownerPlayer then
		return
	end

	local rawKitData = ownerPlayer:GetAttribute("KitData")
	if type(rawKitData) ~= "string" or rawKitData == "" then
		return
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(rawKitData)
	end)
	if not ok or type(decoded) ~= "table" then
		return
	end

	local kitId = decoded.KitId
	if type(kitId) ~= "string" or kitId == "" then
		return
	end

	local kitCfg = ViewmodelConfig.Kits and ViewmodelConfig.Kits[kitId]
	if type(kitCfg) ~= "table" then
		return
	end

	local function loadSection(section)
		if type(section) ~= "table" then
			return
		end
		for trackName, animRef in pairs(section) do
			if type(trackName) == "string" and type(animRef) == "string" and animRef ~= "" then
				local animation = resolveAnimationInstance("Fists", animRef)
				if animation then
					local okLoad, track = pcall(function()
						return self.Animator:LoadAnimation(animation)
					end)
					if okLoad and track then
						track.Priority = TRACK_PRIORITIES[trackName] or Enum.AnimationPriority.Action4
						track.Looped = false
						self.Tracks[trackName] = track
					end
				end
			end
		end
	end

	loadSection(kitCfg.Ability)
	loadSection(kitCfg.Ultimate)
end

function ThirdPersonWeaponManager:_resolveOwnerCharacter(): Model?
	-- Fast path: cached character still valid.
	if self._ownerCharacter and self._ownerCharacter.Parent then
		return self._ownerCharacter
	end

	if not self.Rig then
		return nil
	end

	-- If rig is directly parented to character, use it.
	local parentModel = self.Rig.Parent
	if parentModel and parentModel:IsA("Model") and parentModel:FindFirstChild("Collider") then
		self._ownerCharacter = parentModel
		return self._ownerCharacter
	end

	-- Preferred lookup: OwnerUserId attribute from RigManager.
	local ownerUserId = self.Rig:GetAttribute("OwnerUserId")
	if type(ownerUserId) == "number" then
		local ownerPlayer = Players:GetPlayerByUserId(ownerUserId)
		if ownerPlayer and ownerPlayer.Character and ownerPlayer.Character.Parent then
			self._ownerCharacter = ownerPlayer.Character
			return self._ownerCharacter
		end
	end

	-- Fallback by owner name in Entities/workspace.
	local ownerName = self.Rig:GetAttribute("OwnerName")
	if type(ownerName) == "string" and ownerName ~= "" then
		local entities = workspace:FindFirstChild("Entities")
		local character = (entities and entities:FindFirstChild(ownerName)) or workspace:FindFirstChild(ownerName)
		if character and character:IsA("Model") then
			self._ownerCharacter = character
			return self._ownerCharacter
		end
	end

	return nil
end

function ThirdPersonWeaponManager:_resolveOwnerPlayer(): Player?
	if not self.Rig then
		return nil
	end

	local ownerUserId = self.Rig:GetAttribute("OwnerUserId")
	if type(ownerUserId) == "number" then
		return Players:GetPlayerByUserId(ownerUserId)
	end

	local character = self:_resolveOwnerCharacter()
	if character then
		return Players:GetPlayerFromCharacter(character)
	end

	return nil
end

function ThirdPersonWeaponManager:_resolveOwnerKitId(): string?
	local ownerPlayer = self:_resolveOwnerPlayer()
	if not ownerPlayer then
		return nil
	end

	local rawKitData = ownerPlayer:GetAttribute("KitData")
	if type(rawKitData) ~= "string" or rawKitData == "" then
		return nil
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(rawKitData)
	end)
	if not ok or type(decoded) ~= "table" then
		return nil
	end

	local kitId = decoded.KitId
	if type(kitId) ~= "string" or kitId == "" then
		return nil
	end

	return kitId
end

function ThirdPersonWeaponManager:_resolveReplicatedTrackAnimation(trackName: string): Animation?
	if type(trackName) ~= "string" or trackName == "" then
		return nil
	end

	if string.find(trackName, "rbxassetid://") then
		local animation = Instance.new("Animation")
		animation.AnimationId = trackName
		return animation
	end

	if self.WeaponId then
		local weaponAnimation = resolveAnimationInstance(self.WeaponId, trackName)
		if weaponAnimation then
			return weaponAnimation
		end
	end

	if self.WeaponId ~= "Fists" then
		return nil
	end

	local viewModelAnimations = select(2, getAssetsRoot())
	if not viewModelAnimations then
		return nil
	end

	local kitsFolder = viewModelAnimations:FindFirstChild("Kits")
	if not kitsFolder then
		return nil
	end

	local nested = resolveNestedChild(kitsFolder, trackName)
	if nested and nested:IsA("Animation") then
		return nested
	end

	local ownerKitId = self:_resolveOwnerKitId()
	if ownerKitId then
		local kitFolder = kitsFolder:FindFirstChild(ownerKitId)
		if kitFolder then
			local byKit = resolveNestedChild(kitFolder, trackName)
			if byKit and byKit:IsA("Animation") then
				return byKit
			end
			local shortByKit = kitFolder:FindFirstChild(trackName, true)
			if shortByKit and shortByKit:IsA("Animation") then
				return shortByKit
			end
		end
	end

	local anyMatch = kitsFolder:FindFirstChild(trackName, true)
	if anyMatch and anyMatch:IsA("Animation") then
		return anyMatch
	end

	return nil
end

function ThirdPersonWeaponManager:_ensureReplicatedTrack(trackName: string): AnimationTrack?
	if type(trackName) ~= "string" or trackName == "" or not self.Animator then
		return nil
	end

	local cached = self.Tracks[trackName]
	if cached then
		return cached
	end

	local animation = self:_resolveReplicatedTrackAnimation(trackName)
	if not animation then
		return nil
	end

	local ok, track = pcall(function()
		return self.Animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return nil
	end

	local priorityAttr = animation:GetAttribute("Priority")
	if type(priorityAttr) == "string" and Enum.AnimationPriority[priorityAttr] then
		track.Priority = Enum.AnimationPriority[priorityAttr]
	elseif typeof(priorityAttr) == "EnumItem" then
		track.Priority = priorityAttr
	else
		track.Priority = TRACK_PRIORITIES[trackName] or Enum.AnimationPriority.Action4
	end

	local loopAttr = animation:GetAttribute("Loop")
	if type(loopAttr) ~= "boolean" then
		loopAttr = animation:GetAttribute("Looped")
	end
	if type(loopAttr) == "boolean" then
		track.Looped = loopAttr
	else
		track.Looped = LOOPED_TRACKS[trackName] == true
	end

	self.Tracks[trackName] = track
	return track
end

function ThirdPersonWeaponManager:_getStanceOffset(): CFrame
	if not self.Rig then
		return CFrame.new()
	end

	-- Resolve at most ~4 times per second when not cached to avoid per-frame lookup work.
	local now = tick()
	local character = self._ownerCharacter
	if not character or not character.Parent or (now - self._lastOwnerResolve) > 0.25 then
		self._lastOwnerResolve = now
		character = self:_resolveOwnerCharacter()
	end

	if not character or not character:IsA("Model") then
		return CFrame.new()
	end

	local isCrouched = nil
	if self._forcedCrouching ~= nil then
		isCrouched = self._forcedCrouching
	else
		isCrouched = CrouchUtils:IsVisuallycrouched(character)
	end

	if isCrouched then
		local root = character.PrimaryPart or CharacterLocations:GetRoot(character) or CharacterLocations:GetHumanoidRootPart(character)
		local standingHead = CharacterLocations:GetHead(character)
		local crouchHead = CharacterLocations:GetCrouchHead(character)
		
		if root and standingHead and crouchHead then
			local standingLocal = root.CFrame:PointToObjectSpace(standingHead.Position)
			local crouchLocal = root.CFrame:PointToObjectSpace(crouchHead.Position)
			local deltaY = crouchLocal.Y - standingLocal.Y
			if math.abs(deltaY) > 0.01 then
				return CFrame.new(0, deltaY, 0)
			end
		end

		return CROUCH_REPLICATION_OFFSET
	end

	return CFrame.new()
end

function ThirdPersonWeaponManager:SetCrouching(isCrouching: boolean?)
	if isCrouching == nil then
		self._forcedCrouching = nil
	else
		self._forcedCrouching = isCrouching == true
	end
end

function ThirdPersonWeaponManager:_playTrack(trackName: string, restart: boolean?)
	local track = self.Tracks[trackName] or self:_ensureReplicatedTrack(trackName)
	if not track then
		return
	end

	if restart and track.IsPlaying then
		track:Stop(0.05)
	end

	if not track.IsPlaying then
		track:Play(0.05, 1, 1)
	end
end

function ThirdPersonWeaponManager:_stopTrack(trackName: string)
	local track = self.Tracks[trackName]
	if track and track.IsPlaying then
		track:Stop(0.05)
	end
end

function ThirdPersonWeaponManager:EquipWeapon(weaponId: string): boolean
	if type(weaponId) ~= "string" or weaponId == "" then
		self:UnequipWeapon()
		return false
	end

	self:UnequipWeapon()

	local weaponConfig = ViewmodelConfig.Weapons and ViewmodelConfig.Weapons[weaponId]
	local modelPath = weaponConfig and weaponConfig.ModelPath
		or (ViewmodelConfig.Models and ViewmodelConfig.Models.ByWeaponId and ViewmodelConfig.Models.ByWeaponId[weaponId])
	if type(modelPath) ~= "string" or modelPath == "" then
		return false
	end

	local template = resolveModelTemplate(modelPath)
	if not template or not template:IsA("Model") then
		vmLog("Equip failed: missing template", tostring(weaponId), tostring(modelPath))
		return false
	end

	local rigRoot = self:_getRigRoot()
	if not rigRoot then
		vmLog("Equip failed: missing rig root", tostring(weaponId))
		return false
	end

	local model = template:Clone()
	model.Name = string.format("ThirdPerson_%s", weaponId)

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:Destroy()
	end

	configureModelParts(model)
	local removedFake = stripFakeModel(model)
	vmLog("Stripped Fake model", "weapon=", tostring(weaponId), "removed=", tostring(removedFake))

	local modelRoot = findModelRoot(model)
	if not modelRoot then
		vmLog("Equip failed: no model root", tostring(weaponId))
		model:Destroy()
		return false
	end

	model.PrimaryPart = modelRoot

	local replicationConfig = weaponConfig and weaponConfig.Replication or nil
	local scale = replicationConfig and tonumber(replicationConfig.Scale) or DEFAULT_SCALE
	local offset = replicationConfig and replicationConfig.Offset or DEFAULT_OFFSET
	if typeof(offset) ~= "CFrame" then
		offset = DEFAULT_OFFSET
	end

	scale = math.clamp(scale, 0.01, 10)
	pcall(function()
		model:ScaleTo(scale)
	end)

	self.ReplicationOffset = offset
	model.Parent = self.Rig
	local stanceOffset = self:_getStanceOffset()
	model:PivotTo(rigRoot.CFrame * (self.ReplicationOffset * stanceOffset * CFrame.Angles(math.rad(self.AimPitch), 0, 0)))

	local weld = Instance.new("Weld")
	weld.Name = "ThirdPersonWeaponWeld"
	weld.Part0 = rigRoot
	weld.Part1 = modelRoot
	weld.C0 = self.ReplicationOffset * stanceOffset * CFrame.Angles(math.rad(self.AimPitch), 0, 0)
	weld.C1 = CFrame.new()
	weld.Parent = rigRoot

	-- self.Rig.Parent = workspace
	
	self.WeaponModel = model
	self.WeaponRoot = modelRoot
	self.Weld = weld
	self.Animator = ensureAnimator(model)
	self.WeaponId = weaponId

	self:_loadTracks(weaponId, weaponConfig)
	if weaponId == "Fists" then
		self:_loadFistsKitTracks()
	end
	self:_playTrack("Idle")
	vmLog("Equip success", "weapon=", weaponId, "rig=", self.Rig and self.Rig:GetFullName() or "?")

	return true
end

function ThirdPersonWeaponManager:ApplyReplicatedAction(actionName: string, trackName: string?, isActive: boolean?)
	if not self.WeaponModel then
		return
	end

	local resolvedTrack = trackName
	if type(resolvedTrack) ~= "string" or resolvedTrack == "" then
		resolvedTrack = ACTION_FALLBACK_TRACK[actionName]
	end

	if actionName == "ADS" then
		if isActive == true then
			self:_playTrack(resolvedTrack or "ADS", true)
		else
			self:_stopTrack("ADS")
			if resolvedTrack and resolvedTrack ~= "ADS" then
				self:_playTrack(resolvedTrack, true)
			end
		end
		return
	end

	if actionName == "PlayWeaponTrack" or actionName == "PlayAnimation" then
		if resolvedTrack then
			if isActive == false then
				self:_stopTrack(resolvedTrack)
			else
				self:_playTrack(resolvedTrack, true)
			end
		end
		return
	end

	if actionName == "Special" and isActive == false then
		if resolvedTrack then
			self:_stopTrack(resolvedTrack)
		end
		return
	end

	if resolvedTrack then
		self:_playTrack(resolvedTrack, true)
	end
end

function ThirdPersonWeaponManager:UpdateTransform(rootCFrame: CFrame, aimPitch: number?)
	self.AimPitch = tonumber(aimPitch) or 0

	local stanceOffset = self:_getStanceOffset()
	local pitchOffset = CFrame.Angles(math.rad(self.AimPitch), 0, 0)
	if self.Weld then
		self.Weld.C0 = self.ReplicationOffset * stanceOffset * pitchOffset
		return
	end

	if self.WeaponModel and self.WeaponModel.PrimaryPart and rootCFrame then
		self.WeaponModel:PivotTo(rootCFrame * (self.ReplicationOffset * stanceOffset * pitchOffset))
	end
end

function ThirdPersonWeaponManager:UnequipWeapon()
	vmLog("Unequip", self.WeaponId or "none")
	stopTracks(self.Tracks)
	self.Tracks = {}

	if self.Weld then
		self.Weld:Destroy()
		self.Weld = nil
	end

	if self.WeaponModel then
		self.WeaponModel:Destroy()
		self.WeaponModel = nil
	end

	self.WeaponRoot = nil
	self.Animator = nil
	self.WeaponId = nil
	self.ReplicationOffset = DEFAULT_OFFSET
end

function ThirdPersonWeaponManager:GetWeaponModel(): Model?
	return self.WeaponModel
end

function ThirdPersonWeaponManager:GetWeaponId(): string?
	return self.WeaponId
end

function ThirdPersonWeaponManager:HasWeapon(): boolean
	return self.WeaponModel ~= nil
end

function ThirdPersonWeaponManager:Destroy()
	self:UnequipWeapon()
	self.Rig = nil
	self._ownerCharacter = nil
	self._forcedCrouching = nil
end

return ThirdPersonWeaponManager
