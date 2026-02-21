local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local DestructionSounds = {}

local MaterialPools = {
	Concrete = {
		Medium = {
			"rbxassetid://76678693090428",
			"rbxassetid://104412096828030",
			"rbxassetid://139760416220144",
			"rbxassetid://132343037577986",
			"rbxassetid://119424958602166",
		},
	},
	Wood = {
		Medium = {
			"rbxassetid://17058167304",
			"rbxassetid://17058167976",
			"rbxassetid://18175936378",
			"rbxassetid://18175937734",
			"rbxassetid://18182040495",
			"rbxassetid://18182040009",
			"rbxassetid://18182039273",
		},
	},
	Metal = {
		Medium = {
			"rbxassetid://119327889863960",
			"rbxassetid://129708418579614",
			"rbxassetid://127673242455600",
			"rbxassetid://129579973050330",
			"rbxassetid://99466378770184",
			"rbxassetid://113753206575812",
		},
	},
	Dirt = {
		Medium = {
			"rbxassetid://73310852086916",
			"rbxassetid://118228479568107",
			"rbxassetid://95163876873776",
			"rbxassetid://89157500089304",
		},
	},
	Neon = {
		Medium = {
			"rbxassetid://9116274241",
			"rbxassetid://157325701",
			"rbxassetid://9116278356",
		},
	},
	Glass = {
		Medium = {
			"rbxassetid://97080605297571",
			"rbxassetid://111788755452828",
			"rbxassetid://113990805801121",
			"rbxassetid://137377843684496",
		},
	},
}

local SmallPool = {
	"rbxassetid://18162108025",
	"rbxassetid://18162108347",
	"rbxassetid://18162108976",
	"rbxassetid://18162108602",
	"rbxassetid://18936229850",
	"rbxassetid://18936228225",
	"rbxassetid://18936230287",
	"rbxassetid://18936228761",
	"rbxassetid://18936229282",
}

local NERF_VOLUME_IDS = {
	["rbxassetid://18863861716"] = true,
	["rbxassetid://18863852357"] = true,
	["rbxassetid://18863852788"] = true,
	["rbxassetid://18863853896"] = true,
	["rbxassetid://18863853260"] = true,
	["rbxassetid://18863853582"] = true,
}

local MaterialAliases = {
	Asphalt = "Concrete",
	Brick = "Concrete",
	Grass = "Dirt",
	LeafyGrass = "Dirt",
	Ground = "Dirt",
	Mud = "Dirt",
	Sand = "Dirt",
	Plastic = "Concrete",
	Rock = "Concrete",
	Slate = "Concrete",
	SmoothPlastic = "Glass",
	DiamondPlate = "Metal",
	WoodPlanks = "Wood",
}

local lastPlayedByWall = setmetatable({}, { __mode = "k" })

local rng = Random.new()

local function getSoundSettings(settings)
	return settings and settings.DestructionSounds or nil
end

local function normalizeMaterial(materialValue)
	local materialName
	if typeof(materialValue) == "EnumItem" then
		materialName = materialValue.Name
	elseif type(materialValue) == "string" then
		materialName = materialValue
	else
		materialName = "Concrete"
	end

	materialName = MaterialAliases[materialName] or materialName
	if MaterialPools[materialName] == nil then
		materialName = "Concrete"
	end
	return materialName
end

local function getMaterialConfig(soundSettings, materialName)
	local materialTable = soundSettings and soundSettings.Material
	if type(materialTable) ~= "table" then
		return nil
	end
	return materialTable[materialName]
end

local function chooseIntensity(soundSettings, hitboxSize)
	local threshold = (soundSettings and soundSettings.SmallCutoffVolume) or 24
	local hitboxVolume = math.abs(hitboxSize.X * hitboxSize.Y * hitboxSize.Z)
	if hitboxVolume <= threshold then
		return "Small"
	end
	return "Medium"
end

local function shouldEmitForWall(soundSettings, wall)
	if wall == nil then
		return true
	end

	local minInterval = (soundSettings and soundSettings.MinIntervalPerWall) or 0.08
	if minInterval <= 0 then
		return true
	end

	local now = os.clock()
	local last = lastPlayedByWall[wall]
	if last and (now - last) < minInterval then
		return false
	end

	lastPlayedByWall[wall] = now
	return true
end

local function selectSoundId(materialName, intensity)
	if intensity == "Small" then
		return SmallPool[rng:NextInteger(1, #SmallPool)]
	end

	local pool = MaterialPools[materialName] and MaterialPools[materialName].Medium
	if not pool or #pool == 0 then
		return SmallPool[rng:NextInteger(1, #SmallPool)]
	end
	return pool[rng:NextInteger(1, #pool)]
end

function DestructionSounds.BuildEvent(wall, impactPosition, hitboxSize, settings)
	local soundSettings = getSoundSettings(settings)
	if not (soundSettings and soundSettings.Enabled) then
		return nil
	end

	if wall == nil or not wall:IsA("BasePart") then
		return nil
	end

	if not shouldEmitForWall(soundSettings, wall) then
		return nil
	end

	local materialName = normalizeMaterial(wall.Material)
	local materialConfig = getMaterialConfig(soundSettings, materialName)
	if materialConfig and materialConfig.Enabled == false then
		return nil
	end

	local emitPosition = impactPosition
	if typeof(impactPosition) == "Vector3" then
		emitPosition = wall:GetClosestPointOnSurface(impactPosition)
	else
		emitPosition = wall.Position
	end

	local intensity = chooseIntensity(soundSettings, hitboxSize)
	return {
		Material = materialName,
		Intensity = intensity,
		Position = emitPosition,
		VolumeMultiplier = (materialConfig and materialConfig.Volume) or 1,
	}
end

function DestructionSounds.PlayEvent(eventData, settings)
	local soundSettings = getSoundSettings(settings)
	if not (soundSettings and soundSettings.Enabled) then
		return nil
	end

	if type(eventData) ~= "table" then
		return nil
	end

	local materialName = normalizeMaterial(eventData.Material)
	local materialConfig = getMaterialConfig(soundSettings, materialName)
	if materialConfig and materialConfig.Enabled == false then
		return nil
	end

	local intensity = eventData.Intensity == "Small" and "Small" or "Medium"
	local soundId = selectSoundId(materialName, intensity)
	if not soundId then
		return nil
	end

	local emitter = Instance.new("Part")
	emitter.Name = "DestructionSoundEmitter"
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.Massless = true
	emitter.Transparency = 1
	emitter.Size = Vector3.new(0.25, 0.25, 0.25)
	emitter.CFrame = CFrame.new(eventData.Position or Vector3.zero)
	emitter.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = soundSettings.RollOffMinDistance or 10
	sound.RollOffMaxDistance = rng:NextInteger(
		soundSettings.RollOffMaxDistanceMin or 150,
		soundSettings.RollOffMaxDistanceMax or 170
	)
	sound.PlaybackSpeed = rng:NextNumber(
		soundSettings.PlaybackSpeedMin or 1,
		soundSettings.PlaybackSpeedMax or 1.1
	)

	local baseVolume = (soundSettings.BaseVolume or 1)
		* (eventData.VolumeMultiplier or 1)
		* rng:NextNumber(soundSettings.VolumeJitterMin or 1.15, soundSettings.VolumeJitterMax or 1.25)
	if NERF_VOLUME_IDS[soundId] then
		baseVolume = math.max(0, baseVolume - 0.1)
	end
	sound.Volume = baseVolume

	if eventData.TimePosition and eventData.TimePosition > 0 then
		sound.TimePosition = eventData.TimePosition
	else
		sound.TimePosition = rng:NextNumber(
			soundSettings.TimePositionMin or 0.05,
			soundSettings.TimePositionMax or 0.0715
		)
	end

	sound.Parent = emitter
	CollectionService:AddTag(sound, "SoundEffect")
	sound:Play()

	local fadeOutDelay = rng:NextNumber(
		soundSettings.FadeOutDelayMin or 0.65,
		soundSettings.FadeOutDelayMax or 0.75
	)
	task.delay(fadeOutDelay, function()
		if sound and sound.Parent then
			local fadeTween = TweenService:Create(
				sound,
				TweenInfo.new(rng:NextNumber(soundSettings.FadeOutTimeMin or 0.7, soundSettings.FadeOutTimeMax or 0.8)),
				{ Volume = 0 }
			)
			fadeTween:Play()
		end
	end)

	Debris:AddItem(emitter, soundSettings.EmitterLifetime or 2)
	return sound
end

function DestructionSounds.PlayBatch(eventList, settings)
	if type(eventList) ~= "table" then
		return
	end

	for _, eventData in ipairs(eventList) do
		DestructionSounds.PlayEvent(eventData, settings)
	end
end

return DestructionSounds
