--[[
	Sound Replication Module

	Plays movement sounds on remote player characters via VFXRep.
	Supports one-shot sounds (Land, Jump, Crouch, SlideCancel)
	and looped sounds (Falling, Slide) with start/stop actions.

	Usage from client:
	  One-shot:  VFXRep:Fire("Others", { Module = "Sound" }, { sound = "Land", pitch = 1.0 })
	  Looped:    VFXRep:Fire("Others", { Module = "Sound" }, { sound = "Falling", action = "start" })
	             VFXRep:Fire("Others", { Module = "Sound" }, { sound = "Falling", action = "stop" })
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local SoundManager = require(Locations.Shared.Util:WaitForChild("SoundManager"))
local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local Sound = {}

-- Track looped sounds per player: [userId][soundName] = Sound instance
Sound._loopedSounds = {}
-- Track one-shot weapon action sounds by token: [userId][token] = Sound instance
Sound._weaponActionSounds = {}

local REPLICATED_MOVEMENT_VOLUME = 1.6
local REPLICATED_MOVEMENT_ROLLOFF_MODE = Enum.RollOffMode.InverseTapered
local REPLICATED_MOVEMENT_MIN_DISTANCE = 10
local REPLICATED_MOVEMENT_MAX_DISTANCE = 250
local REPLICATED_FOOTSTEP_VOLUME_MULT = 0.55
local REPLICATED_WEAPON_VOLUME = 1.0
local REPLICATED_WEAPON_ROLLOFF_MODE = Enum.RollOffMode.InverseTapered
local REPLICATED_WEAPON_MIN_DISTANCE = 7.5
local REPLICATED_WEAPON_MAX_DISTANCE = 360
local REPLICATED_WEAPON_DISTANT_THRESHOLD = 95

local LOOPED_SOUNDS = {
	Falling = true,
	Slide = true,
}

local ALLOWED_WEAPON_SOUND_IDS = {}

local function normalizeSoundId(soundRef)
	if type(soundRef) == "table" then
		soundRef = soundRef.Id or soundRef.id or soundRef.SoundId or soundRef.soundId
	end

	if type(soundRef) == "number" then
		if soundRef <= 0 then
			return nil
		end
		return "rbxassetid://" .. tostring(math.floor(soundRef))
	end

	if type(soundRef) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(soundRef, "^%s+", "")
	trimmed = string.gsub(trimmed, "%s+$", "")
	if trimmed == "" then
		return nil
	end

	if string.match(trimmed, "^rbxassetid://%d+$") then
		return trimmed
	end
	if string.match(trimmed, "^rbxasset://") then
		return trimmed
	end

	local numeric = tonumber(trimmed)
	if numeric and numeric > 0 then
		return "rbxassetid://" .. tostring(math.floor(numeric))
	end

	return nil
end

local function registerAllowedWeaponSound(soundRef)
	local soundId = normalizeSoundId(soundRef)
	if soundId then
		ALLOWED_WEAPON_SOUND_IDS[soundId] = true
	end
end

local function registerSoundMap(map)
	if type(map) ~= "table" then
		return
	end
	for _, soundRef in pairs(map) do
		registerAllowedWeaponSound(soundRef)
	end
end

local function buildAllowedWeaponSounds()
	local weapons = ViewmodelConfig and ViewmodelConfig.Weapons
	if type(weapons) == "table" then
		for _, weaponCfg in pairs(weapons) do
			if type(weaponCfg) == "table" then
				registerSoundMap(weaponCfg.Sounds)
			end
		end
	end

	local skins = ViewmodelConfig and ViewmodelConfig.Skins
	if type(skins) == "table" then
		for _, weaponSkins in pairs(skins) do
			if type(weaponSkins) == "table" then
				for _, skinCfg in pairs(weaponSkins) do
					if type(skinCfg) == "table" then
						registerSoundMap(skinCfg.Sounds)
					end
				end
			end
		end
	end
end

buildAllowedWeaponSounds()

local function getViewmodelSoundRoot()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	local sounds = assets:FindFirstChild("Sounds")
	if not sounds then
		return nil
	end
	local viewModel = sounds:FindFirstChild("ViewModel")
	if not viewModel then
		return nil
	end
	return viewModel
end

local function resolveWeaponActionSoundDefinitionRaw(weaponId, actionName, skinId)
	if type(weaponId) ~= "string" or weaponId == "" then
		return nil
	end
	if type(actionName) ~= "string" or actionName == "" then
		return nil
	end

	local weaponCfg = ViewmodelConfig and ViewmodelConfig.Weapons and ViewmodelConfig.Weapons[weaponId]
	if type(weaponCfg) ~= "table" then
		return nil
	end

	local soundRef = nil
	if type(skinId) == "string" and skinId ~= "" and ViewmodelConfig and ViewmodelConfig.Skins then
		local weaponSkins = ViewmodelConfig.Skins[weaponId]
		local skinCfg = weaponSkins and weaponSkins[skinId]
		if type(skinCfg) == "table" and type(skinCfg.Sounds) == "table" then
			soundRef = skinCfg.Sounds[actionName]
		end
	end
	if soundRef == nil and type(weaponCfg.Sounds) == "table" then
		soundRef = weaponCfg.Sounds[actionName]
	end
	if soundRef == nil then
		return nil
	end

	local soundId = normalizeSoundId(soundRef)
	if soundId then
		if ALLOWED_WEAPON_SOUND_IDS[soundId] ~= true then
			return nil
		end
		return {
			SoundId = soundId,
			Source = "id",
		}
	end

	if type(soundRef) == "string" and soundRef ~= "" then
		local soundRoot = getViewmodelSoundRoot()
		if not soundRoot then
			return nil
		end
		local weaponFolder = soundRoot:FindFirstChild(weaponId)
		if not weaponFolder then
			return nil
		end

		if type(skinId) == "string" and skinId ~= "" then
			local skinFolder = weaponFolder:FindFirstChild(skinId)
			if skinFolder then
				local skinTemplate = skinFolder:FindFirstChild(soundRef)
				if skinTemplate and skinTemplate:IsA("Sound") then
					return {
						Template = skinTemplate,
						Source = "template",
					}
				end
			end
		end

		local template = weaponFolder:FindFirstChild(soundRef)
		if template and template:IsA("Sound") then
			return {
				Template = template,
				Source = "template",
			}
		end
	end

	return nil
end

local function resolveWeaponActionSoundDefinition(weaponId, actionName, skinId)
	local resolved = resolveWeaponActionSoundDefinitionRaw(weaponId, actionName, skinId)
	if resolved then
		return resolved
	end
	if type(skinId) == "string" and skinId ~= "" then
		return resolveWeaponActionSoundDefinitionRaw(weaponId, actionName, nil)
	end
	return nil
end

local function getSoundDefinition(soundName)
	local audioConfig = Config.Audio
	return audioConfig and audioConfig.Sounds and audioConfig.Sounds.Movement
		and audioConfig.Sounds.Movement[soundName]
end

local function getSoundGroup(name)
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	return nil
end

local function getWeaponSoundGroup()
	return getSoundGroup("Guns") or getSoundGroup("SFX")
end

local function getCharacterFromUserId(userId)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return nil, nil
	end
	local character = player.Character
	if not character then
		return nil, nil
	end
	local primaryPart = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	return character, primaryPart
end

local function createSoundInstance(definition, parent, pitch, looped)
	if not definition or not definition.Id then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = definition.Id
	sound.Volume = REPLICATED_MOVEMENT_VOLUME
	if definition.Id == Config.Audio.SoundIds.FootstepPlastic
		or definition.Id == Config.Audio.SoundIds.FootstepGrass
		or definition.Id == Config.Audio.SoundIds.FootstepMetal
		or definition.Id == Config.Audio.SoundIds.FootstepWood
		or definition.Id == Config.Audio.SoundIds.FootstepConcrete
		or definition.Id == Config.Audio.SoundIds.FootstepFabric
		or definition.Id == Config.Audio.SoundIds.FootstepSand
		or definition.Id == Config.Audio.SoundIds.FootstepGlass then
		sound.Volume *= REPLICATED_FOOTSTEP_VOLUME_MULT
	end
	if type(pitch) == "number" then
		sound.PlaybackSpeed = pitch
	end
	sound.RollOffMode = REPLICATED_MOVEMENT_ROLLOFF_MODE
	sound.RollOffMinDistance = REPLICATED_MOVEMENT_MIN_DISTANCE
	sound.RollOffMaxDistance = REPLICATED_MOVEMENT_MAX_DISTANCE
	sound.Looped = looped or false
	sound.SoundGroup = getSoundGroup("Movement")
	sound.Parent = parent
	return sound
end

local function createWeaponSoundInstance(soundDef, parent, pitch)
	if type(soundDef) ~= "table" then
		return nil
	end

	local sound = nil
	if soundDef.Template and soundDef.Template:IsA("Sound") then
		sound = soundDef.Template:Clone()
	elseif type(soundDef.SoundId) == "string" and soundDef.SoundId ~= "" then
		sound = Instance.new("Sound")
		sound.SoundId = soundDef.SoundId
		sound.Volume = REPLICATED_WEAPON_VOLUME
	else
		return nil
	end

	if type(pitch) == "number" then
		sound.PlaybackSpeed = pitch
	end
	if sound.Volume <= 0 then
		sound.Volume = REPLICATED_WEAPON_VOLUME
	end
	sound.RollOffMode = REPLICATED_WEAPON_ROLLOFF_MODE
	sound.RollOffMinDistance = REPLICATED_WEAPON_MIN_DISTANCE
	sound.RollOffMaxDistance = REPLICATED_WEAPON_MAX_DISTANCE
	sound.SoundGroup = getWeaponSoundGroup()
	sound.Parent = parent
	return sound
end

local function getLocalListenerDistance(position)
	if typeof(position) ~= "Vector3" then
		return nil
	end
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end
	local character = localPlayer.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if not root then
		return nil
	end
	return (root.Position - position).Magnitude
end

local function applyWeaponSpatialPreset(sound, sourcePosition, weaponId)
	if not sound or not sourcePosition then
		return
	end

	local distance = getLocalListenerDistance(sourcePosition)
	local isDistant = type(distance) == "number" and distance >= REPLICATED_WEAPON_DISTANT_THRESHOLD
	local isIndoor = SoundManager:GetIsIndoor()
	local closePreset = "Gun_Close"
	local distantPreset = "Gun_Distant"
	if weaponId == "Shorty" then
		closePreset = "Gun_NeutralClose"
		distantPreset = "Gun_NeutralDistant"
	end

	SoundManager:ApplyPresets(sound, {
		isDistant and distantPreset or closePreset,
		isIndoor and "Indoor" or "Outdoor",
	})
end

function Sound:Validate(_player, data)
	if not data or typeof(data) ~= "table" then
		return false
	end

	if data.category == "Weapon" then
		if data.stop == true then
			local key = data.key or data.token
			return typeof(key) == "string" and key ~= ""
		end

		if typeof(data.weaponId) ~= "string" or data.weaponId == "" then
			return false
		end
		if typeof(data.action) ~= "string" or data.action == "" then
			return false
		end
		if data.skinId ~= nil and (typeof(data.skinId) ~= "string" or data.skinId == "") then
			return false
		end
		if data.pitch ~= nil and (typeof(data.pitch) ~= "number" or data.pitch < 0.5 or data.pitch > 2.5) then
			return false
		end
		if data.key ~= nil and (typeof(data.key) ~= "string" or data.key == "") then
			return false
		end
		return resolveWeaponActionSoundDefinition(data.weaponId, data.action, data.skinId) ~= nil
	end

	if not data.sound or typeof(data.sound) ~= "string" then
		return false
	end
	if not getSoundDefinition(data.sound) then
		return false
	end
	return true
end

function Sound:Execute(originUserId, data)
	if not data then
		return
	end

	local _, primaryPart = getCharacterFromUserId(originUserId)
	if not primaryPart then
		return
	end

	if data.category == "Weapon" then
		if data.stop == true then
			self:_stopWeaponActionSound(originUserId, data.key or data.token)
			return
		end

		local soundDef = resolveWeaponActionSoundDefinition(data.weaponId, data.action, data.skinId)
		if not soundDef then
			return
		end
		self:_handleWeaponOneShot(originUserId, soundDef, primaryPart, data)
		return
	end

	if not data.sound then
		return
	end

	local soundName = data.sound
	local isLooped = LOOPED_SOUNDS[soundName]

	if isLooped then
		self:_handleLoopedSound(originUserId, soundName, primaryPart, data)
	else
		self:_handleOneShotSound(soundName, primaryPart, data)
	end
end

function Sound:_handleOneShotSound(soundName, primaryPart, data)
	local definition = getSoundDefinition(soundName)
	if not definition then
		return
	end

	local sound = createSoundInstance(definition, primaryPart, data.pitch, false)
	if not sound then
		return
	end

	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 0.5)
end

function Sound:_handleWeaponOneShot(userId, soundDef, primaryPart, data)
	local sound = createWeaponSoundInstance(soundDef, primaryPart, data.pitch)
	if not sound then
		return
	end

	applyWeaponSpatialPreset(sound, primaryPart.Position, data and data.weaponId)

	local key = data and (data.key or data.token)
	if typeof(key) == "string" and key ~= "" then
		self._weaponActionSounds[userId] = self._weaponActionSounds[userId] or {}
		self._weaponActionSounds[userId][key] = sound
	end

	sound:Play()
	sound.Ended:Connect(function()
		if typeof(key) == "string" and key ~= "" then
			local byToken = self._weaponActionSounds[userId]
			if byToken and byToken[key] == sound then
				byToken[key] = nil
				if next(byToken) == nil then
					self._weaponActionSounds[userId] = nil
				end
			end
		end
	end)
	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 0.5)
end

function Sound:_stopWeaponActionSound(userId, token)
	if typeof(userId) ~= "number" or typeof(token) ~= "string" or token == "" then
		return
	end

	local byToken = self._weaponActionSounds[userId]
	if not byToken then
		return
	end

	local sound = byToken[token]
	if sound then
		sound:Stop()
		sound:Destroy()
		byToken[token] = nil
		if next(byToken) == nil then
			self._weaponActionSounds[userId] = nil
		end
	end
end

function Sound:_handleLoopedSound(userId, soundName, primaryPart, data)
	local action = data.action or "start"

	if action == "stop" then
		self:_stopLoopedSound(userId, soundName)
	elseif action == "start" then
		-- Stop existing first if any
		self:_stopLoopedSound(userId, soundName)

		local definition = getSoundDefinition(soundName)
		if not definition then
			return
		end

		local sound = createSoundInstance(definition, primaryPart, data.pitch, true)
		if not sound then
			return
		end

		if not self._loopedSounds[userId] then
			self._loopedSounds[userId] = {}
		end
		self._loopedSounds[userId][soundName] = sound
		sound:Play()
	end
end

function Sound:_stopLoopedSound(userId, soundName)
	local playerSounds = self._loopedSounds[userId]
	if not playerSounds then
		return
	end

	local sound = playerSounds[soundName]
	if sound then
		sound:Stop()
		sound:Destroy()
		playerSounds[soundName] = nil
	end
end

-- Clean up when a player leaves
Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	local playerSounds = Sound._loopedSounds[userId]
	if playerSounds then
		for _, sound in pairs(playerSounds) do
			if sound then
				sound:Stop()
				sound:Destroy()
			end
		end
		Sound._loopedSounds[userId] = nil
	end

	local actionSounds = Sound._weaponActionSounds[userId]
	if actionSounds then
		for _, sound in pairs(actionSounds) do
			if sound then
				sound:Stop()
				sound:Destroy()
			end
		end
		Sound._weaponActionSounds[userId] = nil
	end
end)

return Sound
