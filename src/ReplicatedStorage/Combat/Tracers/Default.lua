--[[
	Default.lua
	Default tracer module - handles hit effects
	
	FX are loaded from ReplicatedStorage.Assets.Tracers.Default:
	- Trail/FX - Auto-attached by Tracers system
	- Muzzle   - Auto-attached by Tracers system
	- Hit      - Attached on world impact
	- Highlight - Used for player hit effects
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local ReturnService = require(ReplicatedStorage.Shared.Util.FXLibaray)
local Utils = ReturnService()
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))

local CharacterLocations = require(ReplicatedStorage:WaitForChild("Game"):WaitForChild("Character"):WaitForChild("CharacterLocations"))

local Default = {}
Default.Id = "Default"
Default.Name = "Default Tracer"

local cachedLoadoutRaw: string? = nil
local cachedLoadoutTable: { [string]: any }? = nil

local function scaleNumberRange(rangeValue: NumberRange, scale: number): NumberRange
	return NumberRange.new(rangeValue.Min * scale, rangeValue.Max * scale)
end

local function scaleNumberSequence(sequenceValue: NumberSequence, scale: number): NumberSequence
	local keypoints = sequenceValue.Keypoints
	local scaled = table.create(#keypoints)
	for index, point in ipairs(keypoints) do
		scaled[index] = NumberSequenceKeypoint.new(point.Time, point.Value * scale, point.Envelope * scale)
	end
	return NumberSequence.new(scaled)
end

local function applyMuzzleFxScale(fxRoot: Instance, scale: number)
	if not fxRoot or scale == 1 then
		return
	end

	local function scaleFxItem(item: Instance)
		if item:IsA("ParticleEmitter") then
			item.Size = scaleNumberSequence(item.Size, scale)
			item.Speed = scaleNumberRange(item.Speed, scale)
		elseif item:IsA("Trail") then
			item.WidthScale = scaleNumberSequence(item.WidthScale, scale)
		elseif item:IsA("Beam") then
			item.Width0 *= scale
			item.Width1 *= scale
		elseif item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
			item.Range *= scale
		end
	end

	scaleFxItem(fxRoot)
	for _, item in ipairs(fxRoot:GetDescendants()) do
		scaleFxItem(item)
	end
end

local function getCurrentWeaponMuzzleScale(): number
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return 1
	end

	local selectedLoadout = localPlayer:GetAttribute("SelectedLoadout")
	if type(selectedLoadout) ~= "string" or selectedLoadout == "" then
		cachedLoadoutRaw = nil
		cachedLoadoutTable = nil
		return 1
	end

	if selectedLoadout ~= cachedLoadoutRaw then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(selectedLoadout)
		end)
		if ok and type(decoded) == "table" then
			cachedLoadoutTable = decoded.loadout or decoded
			if type(cachedLoadoutTable) ~= "table" then
				cachedLoadoutTable = nil
			end
		else
			cachedLoadoutTable = nil
		end
		cachedLoadoutRaw = selectedLoadout
	end

	local loadout = cachedLoadoutTable
	if type(loadout) ~= "table" then
		return 1
	end

	local displaySlot = localPlayer:GetAttribute("DisplaySlot")
	local equippedSlot = localPlayer:GetAttribute("EquippedSlot")
	if displaySlot == "Ability" then
		equippedSlot = "Kit"
	end
	if type(equippedSlot) ~= "string" or equippedSlot == "" then
		equippedSlot = "Primary"
	end

	local weaponId = loadout[equippedSlot]
	if type(weaponId) ~= "string" or weaponId == "" then
		return 1
	end

	local weaponConfig = LoadoutConfig.getWeapon(weaponId)
	if type(weaponConfig) ~= "table" then
		return 1
	end

	local tracerConfig = weaponConfig.tracer
	local configuredScale = type(tracerConfig) == "table" and tracerConfig.muzzleScale or nil
	if type(configuredScale) ~= "number" then
		configuredScale = weaponConfig.muzzleScale
	end
	if type(configuredScale) ~= "number" then
		configuredScale = weaponConfig.MuzzleScale
	end

	if type(configuredScale) ~= "number" or configuredScale <= 0 then
		return 1
	end

	return configuredScale
end

local function getGunModelScale(gunModel: Model?): number
	if not gunModel or typeof(gunModel) ~= "Instance" then
		return 1
	end

	if not gunModel.GetScale then
		return 1
	end

	local ok, modelScale = pcall(function()
		return gunModel:GetScale()
	end)
	if not ok or type(modelScale) ~= "number" or modelScale <= 0 then
		return 1
	end

	return modelScale
end

local function resolveMuzzleScaleOption(options)
	if type(options) ~= "table" then
		return nil
	end

	local configuredScale = options.muzzleScale
	if type(configuredScale) ~= "number" or configuredScale <= 0 then
		return nil
	end

	return configuredScale
end

--[[
	Muzzle flash effect
	@param origin Vector3 - Barrel position
	@param gunModel Model? - The weapon model
	@param attachment Attachment - Tracer attachment for VFX
	@param tracers table - Reference to Tracers system
	@param muzzleAttachment Attachment? - The gun's muzzle attachment
]]
function Default:Muzzle(
	origin: Vector3,
	gunModel: Model?,
	attachment: Attachment,
	tracers,
	muzzleAttachment: Attachment?,
	options: { muzzleScale: number? }?
)
	if not muzzleAttachment then return end
	
	local FxFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Tracers"):WaitForChild("Defualt")
	
	local endFX = FxFolder.Muzzle:FindFirstChild("FX")
	if endFX then
		endFX = endFX:Clone()
		endFX.Parent = muzzleAttachment

		local configuredScale = resolveMuzzleScaleOption(options) or getCurrentWeaponMuzzleScale()
		local finalScale = math.clamp(configuredScale * getGunModelScale(gunModel), 0.05, 20)
		applyMuzzleFxScale(endFX, finalScale)
		
		Utils.PlayAttachment(endFX, 5)
		
		for _, light in endFX:GetChildren() do
			if light:FindFirstChild("info") then
				ReturnService("MovieeTweenMethod")(light).play()
			end
		end
	end
end

--[[
	Finds the appearance rig to highlight for a character
	- Dummies: rig is character:FindFirstChild("Rig")
	- Players: rig is in workspace.Rigs/<PlayerName>_Rig
]]
local function findRigToHighlight(character: Model): Instance?
	if not character then return nil end
	
	-- Check for dummy rig (directly on character)
	local dummyRig = character:FindFirstChild("Rig")
	if dummyRig then
		return dummyRig
	end
	
	-- For players: use CharacterLocations to get the proper appearance rig
	local playerRig = CharacterLocations:GetRig(character)
	if playerRig then
		return playerRig
	end
	
	-- Fallback: check workspace.Rigs manually by name
	local rigsFolder = Workspace:FindFirstChild("Rigs")
	if rigsFolder then
		local ownerName = character:GetAttribute("OwnerName") or character.Name
		local rigName = ownerName .. "_Rig"
		local foundRig = rigsFolder:FindFirstChild(rigName)
		if foundRig then return foundRig end
	end
	
	-- Last fallback: the character itself
	return character
end

--[[
	Hit player effect - highlight with smooth tween
	@param hitPosition Vector3
	@param hitPart BasePart
	@param targetCharacter Model
	@param attachment Attachment
	@param tracers table - Reference to Tracers system
]]
function Default:HitPlayer(hitPosition: Vector3, hitPart: BasePart, targetCharacter: Model, attachment: Attachment, tracers)
	if not targetCharacter then return end

	local rigToHighlight = findRigToHighlight(targetCharacter)
	if not rigToHighlight then return end

	local existingHighlight = rigToHighlight:FindFirstChild("HitHighlight")
	if existingHighlight and existingHighlight:IsA("Highlight") then
		existingHighlight:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "HitHighlight"

	highlight.Adornee = rigToHighlight
	highlight.FillColor = Color3.fromRGB(255, 11, 3)
	--highlight.OutlineColor = Color3.fromRGB(4, 4, 4)
	highlight.FillTransparency = .45
	highlight.OutlineTransparency = 1

	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = rigToHighlight

	local tween = TweenService:Create(
		highlight,
		TweenInfo.new(0.67, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, .15),
		{FillTransparency = 1, OutlineTransparency = 1}
	)
	tween:Play()


	--task.delay(HIGHLIGHT_DURATION, function()
	--	if not highlight or not highlight.Parent then return end

	--	local tweenOut = TweenService:Create(
	--		highlight,
	--		TweenInfo.new(HIGHLIGHT_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	--		{ FillTransparency = 1, OutlineTransparency = 1 }
	--	)
	--	tweenOut:Play()
	tween.Completed:Once(function()
		if highlight and highlight.Parent then
			highlight:Destroy()
		end
	end)
	--end)
	
	-- TODO: Add impact particle to attachment
end

--[[
	Hit world effect - impact VFX
	@param hitPosition Vector3
	@param hitNormal Vector3
	@param hitPart BasePart
	@param attachment Attachment - The tracer attachment (not used for hit, we create a new one)
	@param tracers table - Reference to Tracers system
]]

function Default:HitWorld(hitPosition: Vector3, hitNormal: Vector3, hitPart: BasePart, attachment: Attachment, tracers)
	if not tracers then return end

	-- Create a hit attachment at the impact position
	local hitAttachment = tracers:CreateHitAttachment(hitPosition, hitNormal, 2)
	if not hitAttachment then return end

	-- Attach hit FX
	local fxClone = tracers:AttachHitFX(self.Id, hitAttachment)
	if not fxClone then return end

	Utils.PlayAttachment(fxClone, 10)	

	-- Emit all particle emitters
	--task.delay(0.025, function()
		--for _, fx in fxClone:GetDescendants() do
		--	if fx:IsA("ParticleEmitter") then
		--		fx:Emit(fx:GetAttribute("EmitCount") or 5)
		--	end
		--end
	--end)
end

return Default
