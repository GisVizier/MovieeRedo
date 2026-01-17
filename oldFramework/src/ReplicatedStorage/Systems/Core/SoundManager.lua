local SoundManager = {}

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)
local RemoteEvents = require(Locations.Modules.RemoteEvents)

-- Services
local soundGroups = {}
local soundPools = {}
local activeSounds = {}
local replicatedPlayerSounds = {} -- [player][category_soundName] = Sound instance

-- Configuration will be loaded from Config system
local Config = nil

function SoundManager:Init()
	Log:RegisterCategory("SOUND", "Sound management and audio effects")

	-- Load configuration
	Config = require(Locations.Modules.Config)

	-- Create SoundGroups
	self:CreateSoundGroups()

	-- Initialize sound pools
	self:InitializeSoundPools()

	-- Preload all sounds asynchronously (don't block initialization)
	task.spawn(function()
		self:PreloadAllSounds()
	end)

	-- Setup RemoteEvent connections if on server
	if RunService:IsServer() then
		self:SetupServerConnections()
	elseif RunService:IsClient() then
		self:SetupClientConnections()
	end

	Log:Info("SOUND", "Initialized SoundManager", {
		SoundGroups = #soundGroups,
		PoolSize = self:GetTotalPoolSize(),
	})
end

function SoundManager:CreateSoundGroups()
	local categories = { "Music", "SFX", "Movement", "Voice", "UI" }

	for _, categoryName in pairs(categories) do
		local soundGroup = Instance.new("SoundGroup")
		soundGroup.Name = categoryName .. "Group"
		soundGroup.Parent = SoundService

		-- Apply category-specific settings from config
		if Config and Config.Audio and Config.Audio.Groups and Config.Audio.Groups[categoryName] then
			local groupConfig = Config.Audio.Groups[categoryName]
			soundGroup.Volume = groupConfig.Volume or 1.0

			-- Apply effects if specified
			if groupConfig.Effects then
				for _, effectConfig in pairs(groupConfig.Effects) do
					self:ApplyEffect(soundGroup, effectConfig)
				end
			end
		end

		soundGroups[categoryName] = soundGroup
		Log:Debug("SOUND", "Created SoundGroup", { Category = categoryName })
	end
end

function SoundManager:InitializeSoundPools()
	if not Config or not Config.Audio or not Config.Audio.Sounds then
		Log:Warn("SOUND", "No sound configuration found")
		return
	end

	-- Create a folder in ReplicatedStorage to store pre-made sounds
	local soundStorage = game:GetService("ReplicatedStorage"):FindFirstChild("PreloadedSounds")
	if not soundStorage then
		soundStorage = Instance.new("Folder")
		soundStorage.Name = "PreloadedSounds"
		soundStorage.Parent = game:GetService("ReplicatedStorage")
	end

	for category, sounds in pairs(Config.Audio.Sounds) do
		soundPools[category] = {}
		local categoryFolder = soundStorage:FindFirstChild(category)
		if not categoryFolder then
			categoryFolder = Instance.new("Folder")
			categoryFolder.Name = category
			categoryFolder.Parent = soundStorage
		end

		for soundName, soundConfig in pairs(sounds) do
			-- Create a premade sound in ReplicatedStorage that can be cloned
			local premadeSound = self:CreateSoundInstance(category, soundName, soundConfig)
			premadeSound.Name = soundName
			premadeSound.Parent = categoryFolder

			-- Store reference to the premade sound
			soundPools[category][soundName] = premadeSound

			Log:Debug("SOUND", "Created premade sound", {
				Category = category,
				Sound = soundName,
				Parent = categoryFolder.Name,
			})
		end
	end
end

function SoundManager:CreateSoundInstance(category, soundName, soundConfig)
	local sound = Instance.new("Sound")
	sound.Name = soundName
	sound.SoundId = soundConfig.Id or ""
	sound.Volume = soundConfig.Volume or 0.5
	sound.Pitch = soundConfig.Pitch or 1.0
	sound.EmitterSize = soundConfig.EmitterSize or 10
	sound.RollOffMode = soundConfig.RollOffMode or Enum.RollOffMode.Inverse
	sound.MinDistance = soundConfig.MinDistance or 10
	sound.MaxDistance = soundConfig.MaxDistance or 10000
	sound.Looped = soundConfig.Looped or false

	-- Assign to appropriate SoundGroup
	if soundGroups[category] then
		sound.SoundGroup = soundGroups[category]
	end

	-- Apply effects
	if soundConfig.Effects then
		for _, effectConfig in pairs(soundConfig.Effects) do
			self:ApplyEffect(sound, effectConfig)
		end
	end

	return sound
end

function SoundManager:ApplyEffect(target, effectConfig)
	local effectType = effectConfig.Type
	local effect = nil

	if effectType == "ReverbSoundEffect" then
		effect = Instance.new("ReverbSoundEffect")
		effect.DecayTime = effectConfig.DecayTime or 1.5
		effect.Density = effectConfig.Density or 1.0
		effect.Diffusion = effectConfig.Diffusion or 1.0
		effect.DryLevel = effectConfig.DryLevel or -6
		effect.WetLevel = effectConfig.WetLevel or 0
	elseif effectType == "DistortionSoundEffect" then
		effect = Instance.new("DistortionSoundEffect")
		effect.Level = effectConfig.Level or 0.5
	elseif effectType == "CompressorSoundEffect" then
		effect = Instance.new("CompressorSoundEffect")
		effect.Threshold = effectConfig.Threshold or -20
		effect.Attack = effectConfig.Attack or 0.1
		effect.Release = effectConfig.Release or 0.1
		effect.GainMakeup = effectConfig.GainMakeup or 0
	elseif effectType == "ChorusSoundEffect" then
		effect = Instance.new("ChorusSoundEffect")
		effect.Depth = effectConfig.Depth or 0.5
		effect.Mix = effectConfig.Mix or 0.5
		effect.Rate = effectConfig.Rate or 0.5
	elseif effectType == "EchoSoundEffect" then
		effect = Instance.new("EchoSoundEffect")
		effect.Delay = effectConfig.Delay or 0.5
		effect.DryLevel = effectConfig.DryLevel or -6
		effect.WetLevel = effectConfig.WetLevel or -6
		effect.Feedback = effectConfig.Feedback or 0.5
	end

	if effect then
		effect.Parent = target
		Log:Debug("SOUND", "Applied effect", {
			Effect = effectType,
			Target = target.Name,
		})
	end
end

function SoundManager:GetSound(category, soundName)
	if not soundPools[category] or not soundPools[category][soundName] then
		Log:Warn("SOUND", "Sound not found in pool", {
			Category = category,
			Sound = soundName,
		})
		return nil
	end

	local premadeSound = soundPools[category][soundName]

	-- Clone the premade sound (this eliminates delay)
	local clonedSound = premadeSound:Clone()

	return clonedSound
end

function SoundManager:PlaySound(category, soundName, parent, pitchOverride)
	local sound = self:GetSound(category, soundName)
	if not sound then
		return nil
	end

	-- Set parent for 3D positioning
	sound.Parent = parent or SoundService

	-- Apply pitch override if provided
	if pitchOverride then
		sound.Pitch = pitchOverride
	end

	-- Play the sound
	sound:Play()

	-- Track active sound
	local soundId = tostring(sound)
	activeSounds[soundId] = {
		sound = sound,
		category = category,
		name = soundName,
		startTime = tick(),
	}

	-- Auto-cleanup when sound finishes (destroy the cloned sound)
	local connection
	connection = sound.Ended:Connect(function()
		activeSounds[soundId] = nil
		sound:Destroy()
		connection:Disconnect()
	end)

	Log:Debug("SOUND", "Played sound", {
		Category = category,
		Sound = soundName,
		Parent = parent and parent.Name or "SoundService",
		Pitch = sound.Pitch,
	})

	return sound
end

function SoundManager:PlaySoundAtPosition(category, soundName, parent)
	local sound = self:PlaySound(category, soundName, parent)
	return sound
end

function SoundManager:StopSound(category, soundName)
	for _, activeSound in pairs(activeSounds) do
		if activeSound.category == category and activeSound.name == soundName then
			activeSound.sound:Stop()
		end
	end
end

function SoundManager:StopAllSounds(category)
	for _, activeSound in pairs(activeSounds) do
		if category == nil or activeSound.category == category then
			activeSound.sound:Stop()
		end
	end
end

function SoundManager:SetCategoryVolume(category, volume)
	if soundGroups[category] then
		soundGroups[category].Volume = volume
		Log:Info("SOUND", "Set category volume", {
			Category = category,
			Volume = volume,
		})
	end
end

function SoundManager:GetCategoryVolume(category)
	if soundGroups[category] then
		return soundGroups[category].Volume
	end
	return 0
end

-- RemoteEvent handlers
function SoundManager:SetupServerConnections()
	-- Handle legacy format: (player, category, soundName, position, pitchOverride)
	-- Handle kit format: (player, {Sound, Position, Owner})
	RemoteEvents:ConnectServer("PlaySoundRequest", function(player, arg1, arg2, arg3, arg4)
		-- Check if this is kit ability format (table with Sound key)
		if type(arg1) == "table" and arg1.Sound then
			local data = arg1
			local soundName = data.Sound
			local position = data.Position
			
			-- Broadcast to all clients
			for _, otherPlayer in pairs(Players:GetPlayers()) do
				if otherPlayer ~= player then
					RemoteEvents:FireClient("PlaySound", otherPlayer, data)
				end
			end
			
			Log:Debug("SOUND", "Replicated kit ability sound", {
				Player = player.Name,
				Sound = soundName,
			})
		else
			-- Legacy format
			local category = arg1
			local soundName = arg2
			local position = arg3
			local pitchOverride = arg4
			
			-- Validate request
			if not self:ValidateSoundRequest(player, category, soundName) then
				return
			end

			-- Play sound for other clients (excluding sender)
			for _, otherPlayer in pairs(Players:GetPlayers()) do
				if otherPlayer ~= player then
					RemoteEvents:FireClient("PlaySound", otherPlayer, category, soundName, position, player, pitchOverride)
				end
			end

			Log:Debug("SOUND", "Replicated sound", {
				Player = player.Name,
				Category = category,
				Sound = soundName,
				Pitch = pitchOverride,
			})
		end
	end)

	RemoteEvents:ConnectServer("StopSoundRequest", function(player, category, soundName)
		-- Validate request
		if not self:ValidateSoundRequest(player, category, soundName) then
			return
		end

		-- Stop sound for other clients (excluding sender)
		for _, otherPlayer in pairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				RemoteEvents:FireClient("StopSound", otherPlayer, category, soundName, player)
			end
		end

		Log:Debug("SOUND", "Replicated sound stop", {
			Player = player.Name,
			Category = category,
			Sound = soundName,
		})
	end)
end

function SoundManager:SetupClientConnections()
	-- Handle both legacy format and kit ability format
	RemoteEvents:ConnectClient("PlaySound", function(arg1, arg2, arg3, arg4, arg5)
		-- Check if this is kit ability format (table with Sound key)
		if type(arg1) == "table" and arg1.Sound then
			local data = arg1
			local soundName = data.Sound
			local position = data.Position
			local ownerUserId = data.Owner
			
			-- Find owner's character for 3D positioning
			local targetParent = SoundService
			if ownerUserId then
				local owner = Players:GetPlayerByUserId(ownerUserId)
				if owner and owner.Character then
					local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
					local bodyPart = CharacterLocations:GetBody(owner.Character)
					targetParent = bodyPart or owner.Character.PrimaryPart or SoundService
				end
			end
			
			-- Try to play as category/soundName (e.g., "SFX/QuakeBall")
			local parts = string.split(soundName, "/")
			if #parts == 2 then
				self:PlaySound(parts[1], parts[2], targetParent)
			else
				-- Assume it's just a sound name in SFX category
				self:PlaySound("SFX", soundName, targetParent)
			end
		else
			-- Legacy format: (category, soundName, _, fromPlayer, pitchOverride)
			local category = arg1
			local soundName = arg2
			local fromPlayer = arg4
			local pitchOverride = arg5
			
			-- Find the player's character for positioning
			local targetParent = SoundService
			if fromPlayer and fromPlayer.Character then
				local CharacterLocations = require(Locations.Modules.Systems.Character.CharacterLocations)
				local bodyPart = CharacterLocations:GetBody(fromPlayer.Character)
				if bodyPart then
					targetParent = bodyPart
				elseif fromPlayer.Character.PrimaryPart then
					targetParent = fromPlayer.Character.PrimaryPart
				end
			end

			-- Generate sound key for tracking
			local soundKey = category .. "_" .. soundName

			-- Initialize player's sound table if needed
			if not replicatedPlayerSounds[fromPlayer] then
				replicatedPlayerSounds[fromPlayer] = {}
			end

			-- Stop any existing sound from this player/category/name
			if replicatedPlayerSounds[fromPlayer][soundKey] then
				replicatedPlayerSounds[fromPlayer][soundKey]:Stop()
				replicatedPlayerSounds[fromPlayer][soundKey]:Destroy()
				replicatedPlayerSounds[fromPlayer][soundKey] = nil
			end

			-- Play the new sound with pitch override
			local sound = self:PlaySound(category, soundName, targetParent, pitchOverride)

			-- Store the new Sound instance for direct control
			if sound then
				replicatedPlayerSounds[fromPlayer][soundKey] = sound
			end
		end
	end)

	RemoteEvents:ConnectClient("StopSound", function(category, soundName, fromPlayer)
		-- Generate sound key
		local soundKey = category .. "_" .. soundName

		-- Look up the exact Sound instance and stop it directly
		if replicatedPlayerSounds[fromPlayer] and replicatedPlayerSounds[fromPlayer][soundKey] then
			replicatedPlayerSounds[fromPlayer][soundKey]:Stop()
			replicatedPlayerSounds[fromPlayer][soundKey]:Destroy()
			replicatedPlayerSounds[fromPlayer][soundKey] = nil
		end
	end)
end

function SoundManager:ValidateSoundRequest(_, category, soundName)
	-- Basic validation
	if not Config.Audio or not Config.Audio.Sounds then
		return false
	end
	if not Config.Audio.Sounds[category] then
		return false
	end
	if not Config.Audio.Sounds[category][soundName] then
		return false
	end

	-- Rate limiting could be added here
	return true
end

function SoundManager:RequestSoundReplication(category, soundName, position, pitchOverride)
	-- Client-side function to request sound replication
	if RunService:IsClient() then
		RemoteEvents:FireServer("PlaySoundRequest", category, soundName, position, pitchOverride)
	end
end

function SoundManager:RequestStopSoundReplication(category, soundName)
	-- Client-side function to request sound stop replication
	if RunService:IsClient() then
		RemoteEvents:FireServer("StopSoundRequest", category, soundName)
	end
end

function SoundManager:GetTotalPoolSize()
	local total = 0
	for _, categoryPools in pairs(soundPools) do
		for _, premadeSound in pairs(categoryPools) do
			if premadeSound then
				total = total + 1
			end
		end
	end
	return total
end

function SoundManager:PreloadAllSounds()
	-- Since we're using premade sounds in ReplicatedStorage,
	-- they should already be loaded when the game starts.
	-- No additional preloading needed with this approach.
	Log:Info("SOUND", "Using premade sound method - no additional preloading needed")
end

function SoundManager:GetActiveSoundCount()
	local count = 0
	for _ in pairs(activeSounds) do
		count = count + 1
	end
	return count
end

return SoundManager
