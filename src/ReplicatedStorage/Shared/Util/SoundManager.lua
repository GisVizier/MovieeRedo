local SoundManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))

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

function SoundManager:Init()
	local groupsConfig = Config.Audio and Config.Audio.Groups
	if not groupsConfig then
		return
	end

	for groupName, groupConfig in pairs(groupsConfig) do
		local existing = SoundService:FindFirstChild(groupName)
		if not existing or not existing:IsA("SoundGroup") then
			local group = Instance.new("SoundGroup")
			group.Name = groupName
			group.Volume = groupConfig.Volume or 1
			group.Parent = SoundService
		end
	end

	-- Preload all sound assets so they play instantly
	self:PreloadSounds()
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

local function getSoundGroup(category)
	local groupsConfig = Config.Audio and Config.Audio.Groups
	local groupConfig = groupsConfig and groupsConfig[category]
	if not groupConfig then
		return nil
	end

	local existing = SoundService:FindFirstChild(category)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end

	local group = Instance.new("SoundGroup")
	group.Name = category
	group.Volume = groupConfig.Volume or 1
	group.Parent = SoundService
	return group
end

local function createSound(definition, parent, pitchOverride, soundGroup)
	if not definition or not definition.Id then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = definition.Id
	sound.Volume = definition.Volume or 0.5
	sound.PlaybackSpeed = pitchOverride or (definition.Pitch or 1.0)
	sound.RollOffMode = definition.RollOffMode or Enum.RollOffMode.Linear
	sound.EmitterSize = definition.EmitterSize or 10
	sound.MinDistance = definition.MinDistance or 5
	sound.MaxDistance = definition.MaxDistance or 30
	if soundGroup then
		sound.SoundGroup = soundGroup
	end
	sound.Parent = parent or SoundService
	return sound
end

function SoundManager:PlaySound(category, name, parent, pitch)
	local soundsConfig = Config.Audio and Config.Audio.Sounds
	local categoryConfig = soundsConfig and soundsConfig[category]
	local definition = categoryConfig and categoryConfig[name]
	if not definition then
		return
	end

	local soundGroup = getSoundGroup(category)
	local sound = createSound(definition, parent, pitch, soundGroup)
	if not sound then
		return
	end

	sound:Play()
	-- TimeLength is 0 for sounds that haven't loaded yet; use a safe minimum
	local cleanupTime = math.max(sound.TimeLength, 3) + 0.5
	Debris:AddItem(sound, cleanupTime)
end

function SoundManager:RequestSoundReplication(category, name, _position, pitch)
	self:PlaySound(category, name, SoundService, pitch)
end

return SoundManager
