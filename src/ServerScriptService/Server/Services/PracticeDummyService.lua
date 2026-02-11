local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local DummyConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DummyConfig"))
local Net = require(Locations.Shared.Net.Net)

local PracticeDummyService = {}
PracticeDummyService.__index = PracticeDummyService
local DEBUG_LOGGING = false

local _initialized = false
local _registry = nil
local _template = nil
local _spawnPositions = {} -- { { name = string, cframe = CFrame } }
local _activeDummies = {} -- { [dummy] = { spawnCFrame, pseudoPlayer, emote } }
local _dummyIdCounter = -10000
local _emoteClasses = {}
local _moveEnabled = false
local _movementConn = nil
local _movementStart = 0
local _movementDistance = 5

--------------------------------------------------
-- Private Helpers
--------------------------------------------------

local function getNextDummyId()
	_dummyIdCounter = _dummyIdCounter - 1
	return _dummyIdCounter
end

local function cacheTemplate()
	local modelsFolder = ServerStorage:FindFirstChild("Models")
	if not modelsFolder then
		warn("[PracticeDummyService] ServerStorage.Models folder not found")
		return false
	end

	_template = modelsFolder:FindFirstChild("Dummy")
	if not _template then
		warn("[PracticeDummyService] ServerStorage.Models.Dummy template not found")
		return false
	end

	return true
end

local function cacheEmoteModules()
	local emotesScript = ReplicatedStorage:FindFirstChild("Game")
	emotesScript = emotesScript and emotesScript:FindFirstChild("Emotes")
	local emotesFolder = emotesScript and emotesScript:FindFirstChild("Emotes")

	if emotesFolder then
		for _, moduleScript in emotesFolder:GetChildren() do
			if moduleScript:IsA("ModuleScript") then
				local ok, emoteClass = pcall(require, moduleScript)
				if ok and typeof(emoteClass) == "table" and emoteClass.Id then
					table.insert(_emoteClasses, {
						class = emoteClass,
						id = emoteClass.Id,
					})
				end
			end
		end
	end

	if #_emoteClasses == 0 then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local animations = assets and assets:FindFirstChild("Animations")
		local emotes = animations and animations:FindFirstChild("Emotes")
		if emotes then
			for _, emoteFolder in emotes:GetChildren() do
				if emoteFolder:IsA("Folder") then
					local isLoopable = string.find(string.lower(emoteFolder.Name), "loop") ~= nil
						or string.find(string.lower(emoteFolder.Name), "idle") ~= nil
						or string.find(string.lower(emoteFolder.Name), "dance") ~= nil
					table.insert(_emoteClasses, {
						class = { Id = emoteFolder.Name, Loopable = isLoopable },
						id = emoteFolder.Name,
					})
				end
			end
		end
	end
end

local function scanPracticeSpawns()
	_spawnPositions = {}

	local world = workspace:FindFirstChild("World")
	local spawnFolder = world and world:FindFirstChild("DummySpawns")
	if not spawnFolder then
		warn("[PracticeDummyService] workspace.World.DummySpawns not found")
		return
	end

	local entries = {}
	for _, child in spawnFolder:GetChildren() do
		if string.sub(child.Name, 1, #"PracticeSpawn") == "PracticeSpawn" then
			local spawnCFrame
			if child:IsA("Model") then
				spawnCFrame = child:GetPivot()
			elseif child:IsA("BasePart") then
				spawnCFrame = child.CFrame
			end
			if spawnCFrame then
				table.insert(entries, { name = child.Name, cframe = spawnCFrame })
			end
		end
	end

	table.sort(entries, function(a, b)
		return a.name < b.name
	end)

	_spawnPositions = entries
end

local function setupDummyPhysics(dummy)
	local root = dummy:FindFirstChild("Root")
	if not root then
		warn("[PracticeDummyService] No Root part found in dummy")
		return false
	end

	dummy.PrimaryPart = root

	root.Anchored = false
	root.CanCollide = true
	root.Massless = false

	root.CustomPhysicalProperties = PhysicalProperties.new(
		50,
		2,
		0,
		100,
		0
	)

	local attachment = root:FindFirstChild("YAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "YAttachment"
		attachment.Parent = root
	end

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "StayUpright"
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.CFrame = CFrame.new()
	alignOrientation.MaxTorque = 100000
	alignOrientation.Responsiveness = 50
	alignOrientation.RigidityEnabled = false
	alignOrientation.Parent = root

	local colliderParts =
		{ "Body", "Feet", "Head", "CrouchBody", "CrouchHead", "CollisionBody", "CollisionHead", "HumanoidRootPart" }
	for _, partName in colliderParts do
		local part = root:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = true
			part.CanTouch = false

			local existingWeld = false
			for _, child in part:GetChildren() do
				if child:IsA("WeldConstraint") or child:IsA("Weld") then
					existingWeld = true
					break
				end
			end

			if not existingWeld then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end

	local rig = dummy:FindFirstChild("Rig")
	if rig then
		local rigHRP = rig:FindFirstChild("HumanoidRootPart")
		if rigHRP then
			rigHRP.Anchored = false
			rigHRP.CanCollide = false
			rigHRP.CanQuery = false
			rigHRP.CanTouch = false
			rigHRP.Massless = true

			local existingWeld = false
			for _, child in rigHRP:GetChildren() do
				if child:IsA("WeldConstraint") or child:IsA("Weld") then
					if child.Part0 == root or child.Part1 == root then
						existingWeld = true
						break
					end
				end
			end

			if not existingWeld then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = rigHRP
				weld.Parent = rigHRP
			end
		end

		for _, part in rig:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Massless = true
				if part.Name ~= "HumanoidRootPart" then
					part.Anchored = false
				end
			end
		end
	end

	local collider = dummy:FindFirstChild("Collider")
	if collider then
		for _, descendant in collider:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.Massless = true
				descendant.CanCollide = false
				descendant.CanQuery = true
				descendant.CanTouch = false

				local hasWeld = false
				for _, child in descendant:GetChildren() do
					if child:IsA("WeldConstraint") or child:IsA("Weld") then
						hasWeld = true
						break
					end
				end

				if not hasWeld then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
		end
	end

	return true
end

local function getCharacterWorldPosition(character)
	if not character or not character:IsA("Model") then
		return nil
	end

	local root = character.PrimaryPart
		or character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Root")
		or character:FindFirstChildWhichIsA("BasePart", true)

	if root then
		return root.Position
	end

	local ok, pivot = pcall(function()
		return character:GetPivot()
	end)
	if ok then
		return pivot.Position
	end

	return nil
end

local function fireEmoteToNearbyPlayers(dummyPosition, emoteId, action, rig)
	local recipients = nil

	local roundService = _registry and (_registry:TryGet("Round") or _registry:TryGet("RoundService"))
	if roundService and type(roundService.GetTrainingPlayers) == "function" then
		local ok, trainingPlayers = pcall(function()
			return roundService:GetTrainingPlayers()
		end)
		if ok and type(trainingPlayers) == "table" and #trainingPlayers > 0 then
			recipients = trainingPlayers
		end
	end

	if not recipients then
		recipients = Players:GetPlayers()
	end

	for _, player in recipients do
		if player and player.Parent == Players then
			Net:FireClient("EmoteReplicate", player, 0, emoteId, action, rig)
		end
	end
end

local function playSpawnEmote(dummy)
	if not DummyConfig.SpawnEmote.Enabled then
		return nil
	end
	if #_emoteClasses == 0 then
		return nil
	end
	local rig = dummy:FindFirstChild("Rig")
	if not rig then
		return nil
	end

	local validEmotes = {}
	for _, entry in _emoteClasses do
		if entry.id ~= "Template" then
			table.insert(validEmotes, entry)
		end
	end
	if #validEmotes == 0 then
		return nil
	end

	local emoteEntry = validEmotes[math.random(#validEmotes)]
	local emoteClass = emoteEntry.class
	local isLoopable = emoteClass.Loopable or false
	local dummyPosition = dummy.PrimaryPart and dummy.PrimaryPart.Position or dummy:GetPivot().Position

	fireEmoteToNearbyPlayers(dummyPosition, emoteEntry.id, "play", rig)

	local emoteInfo = {
		id = emoteEntry.id,
		rig = rig,
		loopable = isLoopable,
		dummyPosition = dummyPosition,
	}

	local stopDelay = tonumber(DummyConfig.SpawnEmote.LoopDuration) or 10
	if stopDelay > 0 then
		task.delay(stopDelay, function()
			fireEmoteToNearbyPlayers(dummyPosition, emoteEntry.id, "stop", rig)
		end)
	end

	return emoteInfo
end

local function stopEmote(dummy)
	local dummyInfo = _activeDummies[dummy]
	if dummyInfo and dummyInfo.emote then
		local emoteInfo = dummyInfo.emote
		if emoteInfo.rig and emoteInfo.dummyPosition then
			fireEmoteToNearbyPlayers(emoteInfo.dummyPosition, emoteInfo.id, "stop", emoteInfo.rig)
		end
		dummyInfo.emote = nil
	end
end

local function initializeCombat(dummy, pseudoPlayer)
	if not DummyConfig.CombatEnabled then
		return nil
	end

	local combatService = _registry and _registry:TryGet("CombatService")
	if combatService then
		combatService:InitializePlayer(pseudoPlayer)
		return combatService:GetResource(pseudoPlayer)
	end
	return nil
end

local function cleanupCombat(pseudoPlayer)
	if not DummyConfig.CombatEnabled then
		return
	end
	local combatService = _registry and _registry:TryGet("CombatService")
	if combatService and combatService.CleanupPlayer then
		combatService:CleanupPlayer(pseudoPlayer)
	end
end

local function registerAimAssistTargets(dummy)
	CollectionService:AddTag(dummy, "AimAssistTarget")
	local rig = dummy:FindFirstChild("Rig")
	if rig then
		local head = rig:FindFirstChild("Head")
		if head then
			CollectionService:AddTag(head, "Head")
		end
		local upperTorso = rig:FindFirstChild("UpperTorso")
		if upperTorso then
			CollectionService:AddTag(upperTorso, "UpperTorso")
		end
		local torso = rig:FindFirstChild("Torso")
		if torso then
			CollectionService:AddTag(torso, "Torso")
		end
	end
end

local function spawnDummyAt(spawnIndex)
	if not _template then
		return nil
	end
	local spawnData = _spawnPositions[spawnIndex]
	if not spawnData then
		return nil
	end

	local dummy = _template:Clone()
	dummy.Name = "PracticeDummy_" .. spawnIndex
	setupDummyPhysics(dummy)

	local world = workspace:FindFirstChild("World")
	local spawnFolder = world and world:FindFirstChild("DummySpawns")
	dummy.Parent = spawnFolder or workspace

	if dummy.PrimaryPart then
		dummy:PivotTo(spawnData.cframe)
	end

	local collisionGroupService = _registry and _registry:TryGet("CollisionGroupService")
	if collisionGroupService then
		collisionGroupService:SetCharacterCollisionGroup(dummy)
	end

	registerAimAssistTargets(dummy)

	local humanoid = dummy:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		humanoid.MaxHealth = DummyConfig.MaxHealth
		humanoid.Health = DummyConfig.Health
	end

	local pseudoPlayer = {
		UserId = getNextDummyId(),
		Name = dummy.Name,
		Character = dummy,
		GetAttribute = function(self, name)
			return dummy:GetAttribute(name)
		end,
		SetAttribute = function(self, name, value)
			dummy:SetAttribute(name, value)
		end,
	}

	_activeDummies[dummy] = {
		spawnCFrame = spawnData.cframe,
		pseudoPlayer = pseudoPlayer,
		emote = nil,
	}

	local resource = initializeCombat(dummy, pseudoPlayer)
	local emote = playSpawnEmote(dummy)
	if emote then
		_activeDummies[dummy].emote = emote
	end

	if resource then
		resource.OnDeath:once(function()
			local dummyInfo = _activeDummies[dummy]
			if not dummyInfo then
				return
			end
			stopEmote(dummy)
			cleanupCombat(dummyInfo.pseudoPlayer)
			_activeDummies[dummy] = nil
			if dummy and dummy.Parent then
				dummy:Destroy()
			end
		end)
	elseif humanoid then
		humanoid.Died:Once(function()
			local dummyInfo = _activeDummies[dummy]
			if not dummyInfo then
				return
			end
			stopEmote(dummy)
			cleanupCombat(dummyInfo.pseudoPlayer)
			_activeDummies[dummy] = nil
			if dummy and dummy.Parent then
				dummy:Destroy()
			end
		end)
	end

	return dummy
end

local function updateMovement()
	if not _moveEnabled then
		return
	end
	local t = os.clock() - _movementStart
	local offset = math.sin(t * 1.5) * _movementDistance

	for dummy, info in pairs(_activeDummies) do
		if dummy and dummy.Parent and info.spawnCFrame then
			local base = info.spawnCFrame
			dummy:PivotTo(base * CFrame.new(offset, 0, 0))
		end
	end
end

local function startMovement()
	if _movementConn then
		_movementConn:Disconnect()
	end
	_movementStart = os.clock()
	_movementConn = RunService.Heartbeat:Connect(updateMovement)
end

local function stopMovement()
	if _movementConn then
		_movementConn:Disconnect()
		_movementConn = nil
	end
end

--------------------------------------------------
-- Public API
--------------------------------------------------

function PracticeDummyService:Init(registry, _net)
	if _initialized then
		return
	end
	_initialized = true
	_registry = registry

	if not cacheTemplate() then
		return
	end

	cacheEmoteModules()
end

function PracticeDummyService:Start()
	scanPracticeSpawns()
end

function PracticeDummyService:Stop()
	stopMovement()
	_moveEnabled = false

	for dummy, info in pairs(_activeDummies) do
		stopEmote(dummy)
		cleanupCombat(info.pseudoPlayer)
		if dummy and dummy.Parent then
			dummy:Destroy()
		end
	end
	_activeDummies = {}
end

function PracticeDummyService:Reset(count, moveEnabled)
	if DEBUG_LOGGING then
		print("[PracticeDummyService] Reset called with count:", count, "moveEnabled:", moveEnabled)
	end

	self:Stop()
	scanPracticeSpawns()

	if DEBUG_LOGGING then
		print("[PracticeDummyService] Found", #_spawnPositions, "spawn positions")
		for i, pos in ipairs(_spawnPositions) do
			print("[PracticeDummyService]   Spawn", i, ":", pos.name)
		end
	end

	local maxCount = #_spawnPositions
	local spawnCount = math.clamp(tonumber(count) or 1, 1, 8)
	if maxCount > 0 then
		spawnCount = math.min(spawnCount, maxCount)
	else
		spawnCount = 0
	end

	if DEBUG_LOGGING then
		print("[PracticeDummyService] Will spawn", spawnCount, "dummies (max available:", maxCount, ")")
	end

	for i = 1, spawnCount do
		local dummy = spawnDummyAt(i)
		if dummy then
			if DEBUG_LOGGING then
				print("[PracticeDummyService] Spawned dummy", i, ":", dummy.Name)
			end
		else
			if DEBUG_LOGGING then
				print("[PracticeDummyService] FAILED to spawn dummy", i)
			end
		end
	end

	_moveEnabled = moveEnabled == true
	if _moveEnabled then
		startMovement()
		print("[PracticeDummyService] Movement enabled")
	end
end

return PracticeDummyService
