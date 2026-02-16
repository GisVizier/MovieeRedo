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

local Sound = {}

-- Track looped sounds per player: [userId][soundName] = Sound instance
Sound._loopedSounds = {}

local REPLICATED_MOVEMENT_VOLUME = 1.25
local REPLICATED_MOVEMENT_ROLLOFF_MODE = Enum.RollOffMode.Inverse
local REPLICATED_MOVEMENT_MIN_DISTANCE = 0
local REPLICATED_MOVEMENT_MAX_DISTANCE = 270

local LOOPED_SOUNDS = {
	Falling = true,
	Slide = true,
}

local function getSoundDefinition(soundName)
	local audioConfig = Config.Audio
	return audioConfig and audioConfig.Sounds and audioConfig.Sounds.Movement
		and audioConfig.Sounds.Movement[soundName]
end

local function getMovementSoundGroup()
	local existing = SoundService:FindFirstChild("Movement")
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
	if type(pitch) == "number" then
		sound.PlaybackSpeed = pitch
	end
	sound.RollOffMode = REPLICATED_MOVEMENT_ROLLOFF_MODE
	sound.MinDistance = REPLICATED_MOVEMENT_MIN_DISTANCE
	sound.MaxDistance = REPLICATED_MOVEMENT_MAX_DISTANCE
	sound.Looped = looped or false
	sound.SoundGroup = getMovementSoundGroup()
	sound.Parent = parent
	return sound
end

function Sound:Validate(_player, data)
	if not data or typeof(data) ~= "table" then
		return false
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
	if not data or not data.sound then
		return
	end

	local _, primaryPart = getCharacterFromUserId(originUserId)
	if not primaryPart then
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
	Debris:AddItem(sound, sound.TimeLength + 0.5)
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
