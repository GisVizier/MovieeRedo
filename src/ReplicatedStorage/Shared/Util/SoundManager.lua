local SoundManager = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

local DEFAULT_GROUPS = {
	Guns = { Volume = 0.8 },
	Explosions = { Volume = 0.8 },
	Movement = { Volume = 0.6 },
	UI = { Volume = 0.6 },
	Ambience = { Volume = 0.7 },
	Music = { Volume = 0.7 },
	Voice = { Volume = 1.0 },
	SFX = { Volume = 0.8 },
}

local PRESET_DEFINITIONS = {
	Gun_Close = {
		Effects = {
			{
				ClassName = "EqualizerSoundEffect",
				Properties = {
					LowGain = 4.5,
					MidGain = -1.2,
					HighGain = -3.8,
				},
			},
			{
				ClassName = "CompressorSoundEffect",
				Properties = {
					Threshold = -16,
					Ratio = 4.5,
					Attack = 0.01,
					Release = 0.16,
					GainMakeup = 2.4,
				},
			},
		},
	},
	Gun_Distant = {
		VolumeMultiplier = 0.92,
		Effects = {
			{
				ClassName = "EqualizerSoundEffect",
				Properties = {
					LowGain = -1.2,
					MidGain = -0.8,
					HighGain = -2.8,
				},
			},
			{
				ClassName = "ReverbSoundEffect",
				Properties = {
					DecayTime = 1.5,
					Density = 0.4,
					Diffusion = 0.52,
					WetLevel = -18,
					DryLevel = -1,
				},
			},
		},
	},
	Gun_NeutralClose = {
		Effects = {
			{
				ClassName = "EqualizerSoundEffect",
				Properties = {
					LowGain = 1.2,
					MidGain = 0.1,
					HighGain = -0.8,
				},
			},
			{
				ClassName = "CompressorSoundEffect",
				Properties = {
					Threshold = -14,
					Ratio = 3.2,
					Attack = 0.01,
					Release = 0.14,
					GainMakeup = 1.0,
				},
			},
		},
	},
	Gun_NeutralDistant = {
		VolumeMultiplier = 0.9,
		Effects = {
			{
				ClassName = "EqualizerSoundEffect",
				Properties = {
					LowGain = -0.8,
					MidGain = -0.3,
					HighGain = -1.8,
				},
			},
			{
				ClassName = "ReverbSoundEffect",
				Properties = {
					DecayTime = 1.3,
					Density = 0.35,
					Diffusion = 0.48,
					WetLevel = -20,
					DryLevel = -1,
				},
			},
		},
	},
	Explosion_Close = {
		Effects = {
			{
				ClassName = "EqualizerSoundEffect",
				Properties = {
					LowGain = 2.2,
					MidGain = 0.5,
					HighGain = -1.5,
				},
			},
			{
				ClassName = "CompressorSoundEffect",
				Properties = {
					Threshold = -12,
					Ratio = 5,
					Attack = 0.01,
					Release = 0.24,
					GainMakeup = 3.0,
				},
			},
			{
				ClassName = "DistortionSoundEffect",
				Properties = {
					Level = 0.03,
				},
			},
		},
	},
	Explosion_Distant = {
		VolumeMultiplier = 0.78,
		Effects = {
			{
				ClassName = "EqualizerSoundEffect",
				Properties = {
					LowGain = -2.5,
					MidGain = -0.8,
					HighGain = -2.4,
				},
			},
			{
				ClassName = "ReverbSoundEffect",
				Properties = {
					DecayTime = 2.2,
					Density = 0.55,
					Diffusion = 0.6,
					WetLevel = -14,
					DryLevel = -2,
				},
			},
		},
	},
	Indoor = {
		Effects = {
			{
				ClassName = "ReverbSoundEffect",
				Properties = {
					DecayTime = 1.4,
					Density = 0.62,
					Diffusion = 0.7,
					WetLevel = -12,
					DryLevel = -1.5,
				},
			},
		},
	},
	Outdoor = {
		Effects = {
			{
				ClassName = "ReverbSoundEffect",
				Properties = {
					DecayTime = 0.4,
					Density = 0.2,
					Diffusion = 0.25,
					WetLevel = -80,
					DryLevel = 0,
				},
			},
		},
	},
	Muffled = {
		VolumeMultiplier = 0.82,
		Effects = {
			{
				ClassName = "EqualizerSoundEffect",
				Properties = {
					LowGain = 1.0,
					MidGain = -3.0,
					HighGain = -14.0,
				},
			},
		},
	},
}

SoundManager._initialized = false
SoundManager._environmentConnection = nil
SoundManager._environmentTimer = 0
SoundManager._environmentCheckInterval = 0.16
SoundManager._environmentRayLength = 12
SoundManager._isIndoor = false
SoundManager._manualIndoor = nil
SoundManager._groupAliases = {
	SFX = "Guns",
	Weapon = "Guns",
}
SoundManager._variationDefaults = {
	PitchMin = 0.96,
	PitchMax = 1.04,
	VolumeMin = 0.95,
	VolumeMax = 1.05,
	StartOffsetMin = 0,
	StartOffsetMax = 0,
}
SoundManager.GunshotLayers = {
	Default = {},
}

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

local function resolveLocalRootPart()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end
	local character = localPlayer.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

local function setPropertySafe(instance, propertyName, value)
	local ok = pcall(function()
		instance[propertyName] = value
	end)
	return ok
end

function SoundManager:_resolveGroupName(groupName)
	if type(groupName) ~= "string" or groupName == "" then
		return "Guns"
	end
	return self._groupAliases[groupName] or groupName
end

function SoundManager:_getConfiguredGroups()
	local fromConfig = Config.Audio and Config.Audio.Groups or {}
	local merged = {}

	for name, data in pairs(DEFAULT_GROUPS) do
		merged[name] = { Volume = data.Volume }
	end
	for name, data in pairs(fromConfig) do
		if type(data) == "table" then
			merged[name] = { Volume = data.Volume or (merged[name] and merged[name].Volume) or 1 }
		else
			merged[name] = { Volume = (merged[name] and merged[name].Volume) or 1 }
		end
	end

	return merged
end

function SoundManager:_ensureGroup(groupName)
	local resolved = self:_resolveGroupName(groupName)
	local groups = self:_getConfiguredGroups()
	local groupConfig = groups[resolved] or DEFAULT_GROUPS[resolved] or { Volume = 1 }

	local existing = SoundService:FindFirstChild(resolved)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end

	local group = Instance.new("SoundGroup")
	group.Name = resolved
	group.Volume = groupConfig.Volume or 1
	group.Parent = SoundService
	return group
end

function SoundManager:_ensureAllGroups()
	local groups = self:_getConfiguredGroups()
	for groupName in pairs(groups) do
		self:_ensureGroup(groupName)
	end
	for groupName in pairs(DEFAULT_GROUPS) do
		self:_ensureGroup(groupName)
	end
end

function SoundManager:GetSoundGroup(groupName)
	return self:_ensureGroup(groupName)
end

function SoundManager:_clearManagedEffects(sound)
	if not sound then
		return
	end
	for _, child in ipairs(sound:GetChildren()) do
		if child:IsA("SoundEffect") and string.sub(child.Name, 1, 3) == "SM_" then
			child:Destroy()
		end
	end
end

function SoundManager:_applyEffects(sound, effectConfigs, presetName)
	for index, effectData in ipairs(effectConfigs) do
		local className = effectData.ClassName
		if type(className) == "string" and className ~= "" then
			local effect = Instance.new(className)
			effect.Name = string.format("SM_%s_%d", presetName, index)
			local props = effectData.Properties or {}
			for key, value in pairs(props) do
				setPropertySafe(effect, key, value)
			end
			effect.Parent = sound
		end
	end
end

function SoundManager:ApplyPreset(sound, presetName)
	return self:ApplyPresets(sound, { presetName })
end

function SoundManager:ApplyPresets(sound, presetNames)
	if not sound or not sound:IsA("Sound") then
		return sound
	end
	if type(presetNames) ~= "table" then
		return sound
	end

	self:_clearManagedEffects(sound)

	local volumeMultiplier = 1
	for _, presetName in ipairs(presetNames) do
		local preset = PRESET_DEFINITIONS[presetName]
		if preset then
			if type(preset.VolumeMultiplier) == "number" then
				volumeMultiplier *= preset.VolumeMultiplier
			end
			if type(preset.Effects) == "table" then
				self:_applyEffects(sound, preset.Effects, presetName)
			end
		end
	end

	if volumeMultiplier ~= 1 then
		sound.Volume *= volumeMultiplier
	end
	return sound
end

function SoundManager:_applyVariation(sound, options)
	local variation = options and options.Variation or self._variationDefaults
	local pitchMin = variation.PitchMin or self._variationDefaults.PitchMin
	local pitchMax = variation.PitchMax or self._variationDefaults.PitchMax
	local volumeMin = variation.VolumeMin or self._variationDefaults.VolumeMin
	local volumeMax = variation.VolumeMax or self._variationDefaults.VolumeMax
	local offsetMin = variation.StartOffsetMin or self._variationDefaults.StartOffsetMin
	local offsetMax = variation.StartOffsetMax or self._variationDefaults.StartOffsetMax

	if not options or options.DisableVariation ~= true then
		sound.PlaybackSpeed *= Random.new():NextNumber(pitchMin, pitchMax)
		sound.Volume *= Random.new():NextNumber(volumeMin, volumeMax)
	end

	if offsetMax > offsetMin and not sound.Looped then
		sound.TimePosition = Random.new():NextNumber(offsetMin, offsetMax)
	end
end

function SoundManager:_getEnvironmentFlag(explicitIndoor)
	if type(explicitIndoor) == "boolean" then
		return explicitIndoor
	end
	if type(self._manualIndoor) == "boolean" then
		return self._manualIndoor
	end
	return self._isIndoor
end

function SoundManager:setEnvironment(isIndoor)
	if type(isIndoor) == "boolean" then
		self._manualIndoor = isIndoor
	else
		self._manualIndoor = nil
	end
end

function SoundManager:GetIsIndoor()
	return self:_getEnvironmentFlag(nil)
end

function SoundManager:_checkIndoorState()
	local root = resolveLocalRootPart()
	if not root then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { root.Parent }
	params.IgnoreWater = true

	local raycastResult = Workspace:Raycast(root.Position, Vector3.new(0, self._environmentRayLength, 0), params)
	return raycastResult ~= nil
end

function SoundManager:_startEnvironmentWatcher()
	if self._environmentConnection then
		return
	end

	self._environmentConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self._environmentTimer += deltaTime
		if self._environmentTimer < self._environmentCheckInterval then
			return
		end
		self._environmentTimer = 0
		self._isIndoor = self:_checkIndoorState()
	end)
end

function SoundManager:_stopEnvironmentWatcher()
	if self._environmentConnection then
		self._environmentConnection:Disconnect()
		self._environmentConnection = nil
	end
end

function SoundManager:_buildPresetStack(sound, options, sourcePosition)
	local presetStack = {}
	local category = options and options.Category or "Guns"
	local distance = options and options.ListenerDistance

	if distance == nil and type(sourcePosition) == "Vector3" then
		local root = resolveLocalRootPart()
		if root then
			distance = (root.Position - sourcePosition).Magnitude
		end
	end

	local explicitDistant = options and options.IsDistant
	local isDistant = explicitDistant
	if type(isDistant) ~= "boolean" then
		isDistant = type(distance) == "number" and distance >= (options and options.DistantThreshold or 95)
	end

	if category == "Explosions" then
		table.insert(presetStack, isDistant and "Explosion_Distant" or "Explosion_Close")
	elseif category == "Guns" or category == "SFX" or category == "Weapon" then
		table.insert(presetStack, isDistant and "Gun_Distant" or "Gun_Close")
	end

	if options and options.Preset then
		table.insert(presetStack, options.Preset)
	end

	local applyEnvironment = options and options.ApplyEnvironment
	if applyEnvironment == nil then
		applyEnvironment = category == "Explosions" or category == "Guns" or category == "SFX" or category == "Weapon"
	end
	if applyEnvironment then
		local isIndoor = self:_getEnvironmentFlag(options and options.IsIndoor)
		table.insert(presetStack, isIndoor and "Indoor" or "Outdoor")
	end

	if options and options.Occluded then
		table.insert(presetStack, "Muffled")
	end

	self:ApplyPresets(sound, presetStack)
end

function SoundManager:_isOccluded(sourcePosition, sourceParent)
	local root = resolveLocalRootPart()
	if not root or typeof(sourcePosition) ~= "Vector3" then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.IgnoreWater = true
	local blacklist = { root.Parent }
	if sourceParent and sourceParent.Parent then
		table.insert(blacklist, sourceParent)
	end
	params.FilterDescendantsInstances = blacklist

	local cast = Workspace:Raycast(root.Position, sourcePosition - root.Position, params)
	return cast ~= nil
end

function SoundManager:registerSound(sound, category, preset)
	if not sound or not sound:IsA("Sound") then
		return nil
	end

	local group = self:_ensureGroup(category or "Guns")
	sound.SoundGroup = group

	if type(preset) == "string" and preset ~= "" then
		self:ApplyPreset(sound, preset)
	end

	return sound
end

local function applyDefinitionRolloff(sound, definition)
	local rollOffMode = definition.RollOffMode or Enum.RollOffMode.InverseTapered
	sound.RollOffMode = rollOffMode
	if definition.EmitterSize ~= nil then
		sound.EmitterSize = definition.EmitterSize
	end
	local minDistance = definition.RollOffMinDistance or definition.MinDistance or 5
	local maxDistance = definition.RollOffMaxDistance or definition.MaxDistance or 65
	sound.RollOffMinDistance = minDistance
	sound.RollOffMaxDistance = maxDistance
	setPropertySafe(sound, "MinDistance", minDistance)
	setPropertySafe(sound, "MaxDistance", maxDistance)
end

function SoundManager:_createSoundFromDefinition(definition, parent, pitchOverride)
	if not definition then
		return nil
	end
	local normalizedId = normalizeSoundId(definition.Id or definition.SoundId or definition.id)
	if not normalizedId then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = normalizedId
	sound.Volume = definition.Volume or 0.5
	sound.PlaybackSpeed = pitchOverride or definition.Pitch or 1
	sound.Looped = definition.Looped == true
	applyDefinitionRolloff(sound, definition)
	sound.Parent = parent or SoundService

	return sound
end

function SoundManager:_finalizeAndPlay(sound, options, sourcePosition)
	if not sound then
		return nil
	end

	local useOcclusion = options and options.EnableOcclusion == true
	if useOcclusion and typeof(sourcePosition) == "Vector3" then
		options.Occluded = self:_isOccluded(sourcePosition, sound.Parent)
	end

	self:_buildPresetStack(sound, options or {}, sourcePosition)
	self:_applyVariation(sound, options)
	sound:Play()

	if not sound.Looped and (not options or options.AutoCleanup ~= false) then
		local cleanupTime = (options and options.CleanupTime) or math.max(sound.TimeLength, 2) + 0.35
		Debris:AddItem(sound, cleanupTime)
	end

	return sound
end

function SoundManager:play(soundId, options)
	local normalized = normalizeSoundId(soundId)
	if not normalized then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = normalized
	sound.Volume = (options and options.Volume) or 0.7
	sound.PlaybackSpeed = (options and options.PlaybackSpeed) or 1
	sound.Looped = options and options.Looped == true or false
	sound.RollOffMode = (options and options.RollOffMode) or Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = (options and options.RollOffMinDistance) or (options and options.MinDistance) or 6
	sound.RollOffMaxDistance = (options and options.RollOffMaxDistance) or (options and options.MaxDistance) or 120
	setPropertySafe(sound, "MinDistance", sound.RollOffMinDistance)
	setPropertySafe(sound, "MaxDistance", sound.RollOffMaxDistance)

	local parent = (options and options.Parent) or SoundService
	sound.Parent = parent
	self:registerSound(sound, options and options.Category or "Guns")

	return self:_finalizeAndPlay(sound, options, options and options.Position)
end

function SoundManager:playAtPosition(soundId, position, options)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local emitter = Instance.new("Part")
	emitter.Name = "SoundEmitter"
	emitter.Anchored = true
	emitter.CanQuery = false
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(0.2, 0.2, 0.2)
	emitter.CFrame = CFrame.new(position)
	emitter.Parent = Workspace:FindFirstChild("Effects") or Workspace

	local playOptions = options and table.clone(options) or {}
	playOptions.Parent = emitter
	playOptions.Position = position

	local sound = self:play(soundId, playOptions)
	if sound then
		local emitterCleanup = (playOptions.CleanupTime or math.max(sound.TimeLength, 2) + 0.4) + 0.2
		Debris:AddItem(emitter, emitterCleanup)
	else
		emitter:Destroy()
	end
	return sound
end

function SoundManager:PlayGunshot(weaponName, isDistant, isIndoor, listenerDistance, options)
	local requestedLayers = options and options.Layers
	local layers = requestedLayers or self.GunshotLayers[weaponName] or self.GunshotLayers.Default
	if type(layers) ~= "table" or #layers == 0 then
		return {}
	end

	local results = {}
	for _, layer in ipairs(layers) do
		local layerSound = layer.SoundId or layer.Id or layer.soundId or layer.id
		local layerDelay = layer.Delay or 0
		local layerOptions = {
			Category = layer.Category or "Guns",
			Volume = layer.Volume or 1,
			PlaybackSpeed = layer.PlaybackSpeed or 1,
			DisableVariation = layer.DisableVariation == true,
			Variation = layer.Variation,
			EnableOcclusion = layer.EnableOcclusion == true,
			IsDistant = isDistant,
			IsIndoor = isIndoor,
			ListenerDistance = listenerDistance,
			DistantThreshold = layer.DistantThreshold,
			CleanupTime = layer.CleanupTime,
			Parent = options and options.Parent,
			Position = options and options.Position,
		}

		task.delay(layerDelay, function()
			local playedSound
			if options and options.Position then
				playedSound = self:playAtPosition(layerSound, options.Position, layerOptions)
			else
				playedSound = self:play(layerSound, layerOptions)
			end
			if playedSound then
				table.insert(results, playedSound)
			end
		end)
	end

	return results
end

function SoundManager:DuckForExplosion(distance, options)
	local numericDistance = tonumber(distance)
	if not numericDistance then
		return
	end

	local maxDistance = (options and options.MaxDistance) or 24
	if numericDistance > maxDistance then
		return
	end

	local normalized = math.clamp(numericDistance / maxDistance, 0, 1)
	local duckFactor = 0.45 + (0.4 * normalized)
	local attackTime = (options and options.AttackTime) or 0.08
	local releaseTime = (options and options.ReleaseTime) or 0.55

	local musicGroup = self:_ensureGroup("Music")
	local ambienceGroup = self:_ensureGroup("Ambience")
	local originMusicVolume = musicGroup.Volume
	local originAmbienceVolume = ambienceGroup.Volume

	TweenService:Create(musicGroup, TweenInfo.new(attackTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = originMusicVolume * duckFactor,
	}):Play()
	TweenService:Create(ambienceGroup, TweenInfo.new(attackTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = originAmbienceVolume * duckFactor,
	}):Play()

	task.delay(attackTime + releaseTime, function()
		TweenService:Create(musicGroup, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = originMusicVolume,
		}):Play()
		TweenService:Create(ambienceGroup, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Volume = originAmbienceVolume,
		}):Play()
	end)

	if options and type(options.TinnitusSoundId) == "string" and numericDistance <= ((options.TinnitusDistance or 8)) then
		self:play(options.TinnitusSoundId, {
			Category = "UI",
			Volume = options.TinnitusVolume or 0.18,
			RollOffMinDistance = 0,
			RollOffMaxDistance = 0,
			DisableVariation = true,
			AutoCleanup = true,
		})
	end
end

function SoundManager:SetGroupVolume(groupName, value)
	local group = self:_ensureGroup(groupName)
	if not group then
		return
	end
	group.Volume = math.clamp(tonumber(value) or 1, 0, 1)
end

function SoundManager:setGroupVolume(groupName, value)
	self:SetGroupVolume(groupName, value)
end

function SoundManager:Init()
	if self._initialized then
		return
	end
	self._initialized = true

	self:_ensureAllGroups()
	self:PreloadSounds()
	self:_startEnvironmentWatcher()
end

function SoundManager:init()
	self:Init()
end

function SoundManager:Destroy()
	self:_stopEnvironmentWatcher()
	self._initialized = false
end

function SoundManager:PreloadSounds()
	local soundsConfig = Config.Audio and Config.Audio.Sounds

	local preloadItems = {}
	local seenSoundIds = {}

	local function addPreloadSoundId(soundId)
		local normalized = normalizeSoundId(soundId)
		if not normalized or seenSoundIds[normalized] then
			return
		end
		seenSoundIds[normalized] = true
		local preloadSound = Instance.new("Sound")
		preloadSound.SoundId = normalized
		table.insert(preloadItems, preloadSound)
	end

	local function addDefinitions(definitions)
		if type(definitions) ~= "table" then
			return
		end
		for _, definition in pairs(definitions) do
			if type(definition) == "table" then
				addPreloadSoundId(definition.Id or definition.id or definition.SoundId or definition.soundId)
			else
				addPreloadSoundId(definition)
			end
		end
	end

	if soundsConfig then
		for _, categoryConfig in pairs(soundsConfig) do
			addDefinitions(categoryConfig)
		end
	end

	if ViewmodelConfig and type(ViewmodelConfig.Weapons) == "table" then
		for _, weaponCfg in pairs(ViewmodelConfig.Weapons) do
			if type(weaponCfg) == "table" then
				addDefinitions(weaponCfg.Sounds)
			end
		end
	end

	if ViewmodelConfig and type(ViewmodelConfig.Skins) == "table" then
		for _, weaponSkins in pairs(ViewmodelConfig.Skins) do
			if type(weaponSkins) == "table" then
				for _, skinCfg in pairs(weaponSkins) do
					if type(skinCfg) == "table" then
						addDefinitions(skinCfg.Sounds)
					end
				end
			end
		end
	end

	if #preloadItems > 0 then
		ContentProvider:PreloadAsync(preloadItems)
		for _, item in ipairs(preloadItems) do
			item:Destroy()
		end
	end
end

function SoundManager:PlaySound(category, name, parent, pitch)
	local soundsConfig = Config.Audio and Config.Audio.Sounds
	local categoryConfig = soundsConfig and soundsConfig[category]
	local definition = categoryConfig and categoryConfig[name]
	if not definition then
		return nil
	end

	local sound = self:_createSoundFromDefinition(definition, parent, pitch)
	if not sound then
		return nil
	end

	self:registerSound(sound, category)

	local sourcePosition = nil
	if sound.Parent and sound.Parent:IsA("BasePart") then
		sourcePosition = sound.Parent.Position
	end

	return self:_finalizeAndPlay(sound, {
		Category = category,
		EnableOcclusion = false,
		CleanupTime = math.max(sound.TimeLength, 2) + 0.4,
	}, sourcePosition)
end

function SoundManager:RequestSoundReplication(category, name, _position, pitch)
	return self:PlaySound(category, name, SoundService, pitch)
end

return SoundManager
