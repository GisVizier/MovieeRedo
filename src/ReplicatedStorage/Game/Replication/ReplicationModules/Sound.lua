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
local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local Sound = {}

-- Track looped sounds per player: [userId][soundName] = Sound instance
Sound._loopedSounds = {}

local REPLICATED_MOVEMENT_VOLUME = 1.25
local REPLICATED_MOVEMENT_ROLLOFF_MODE = Enum.RollOffMode.InverseTapered
local REPLICATED_MOVEMENT_MIN_DISTANCE = 5.65
local REPLICATED_MOVEMENT_MAX_DISTANCE = 165
local REPLICATED_FOOTSTEP_VOLUME_MULT = 0.35
local REPLICATED_WEAPON_VOLUME = 1.0
local REPLICATED_WEAPON_ROLLOFF_MODE = Enum.RollOffMode.InverseTapered
local REPLICATED_WEAPON_MIN_DISTANCE = 7.5
local REPLICATED_WEAPON_MAX_DISTANCE = 260

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

local function createWeaponSoundInstance(soundId, parent, pitch)
	if type(soundId) ~= "string" or soundId == "" then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = REPLICATED_WEAPON_VOLUME
	if type(pitch) == "number" then
		sound.PlaybackSpeed = pitch
	end
	sound.RollOffMode = REPLICATED_WEAPON_ROLLOFF_MODE
	sound.RollOffMinDistance = REPLICATED_WEAPON_MIN_DISTANCE
	sound.RollOffMaxDistance = REPLICATED_WEAPON_MAX_DISTANCE
	sound.SoundGroup = getSoundGroup("SFX")
	sound.Parent = parent
	return sound
end

function Sound:Validate(_player, data)
	if not data or typeof(data) ~= "table" then
		return false
	end

	if data.category == "Weapon" then
		local soundId = normalizeSoundId(data.soundId)
		if not soundId or ALLOWED_WEAPON_SOUND_IDS[soundId] ~= true then
			return false
		end
		if data.pitch ~= nil and (typeof(data.pitch) ~= "number" or data.pitch < 0.5 or data.pitch > 2.5) then
			return false
		end
		return true
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
		local soundId = normalizeSoundId(data.soundId)
		if not soundId or ALLOWED_WEAPON_SOUND_IDS[soundId] ~= true then
			return
		end
		self:_handleWeaponOneShot(soundId, primaryPart, data)
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

function Sound:_handleWeaponOneShot(soundId, primaryPart, data)
	local sound = createWeaponSoundInstance(soundId, primaryPart, data.pitch)
	if not sound then
		return
	end

	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 0.5)
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
end)

return Sound
