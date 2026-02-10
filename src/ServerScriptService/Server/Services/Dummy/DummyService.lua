--[[
	DummyService.lua
	Server-side service that spawns and manages combat dummies for testing.
	
	Features:
	- Spawns dummies at designated DummySpawn markers
	- Sets up proper physics (Root as bean, welded collider parts)
	- Plays random emotes on spawn using EmoteBase
	- Respawns dummies after death
	- Full CombatService integration for damage/status effects
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local DummyConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DummyConfig"))
local WeldUtils = require(Locations.Shared.Util:WaitForChild("WeldUtils"))
local Net = require(Locations.Shared.Net.Net)

local DummyService = {}
DummyService.__index = DummyService

-- Internal state
local _initialized = false
local _registry = nil
local _template = nil
local _spawnPositions = {} -- { { position = Vector3, cframe = CFrame } }
local _activeDummies = {} -- { [dummy] = { spawnIndex, pseudoPlayer, emote } }
local _dummyIdCounter = 0 -- For generating unique negative IDs
local _emoteClasses = {} -- { { class = table, id = string } }

--------------------------------------------------
-- Private Functions
--------------------------------------------------

-- Get unique negative ID for dummy (to distinguish from real players)
local function getNextDummyId()
	_dummyIdCounter = _dummyIdCounter - 1
	return _dummyIdCounter
end

-- Cache the dummy template from ServerStorage
local function cacheTemplate()
	local modelsFolder = ServerStorage:FindFirstChild("Models")
	if not modelsFolder then
		warn("[DummyService] ServerStorage.Models folder not found")
		return false
	end

	_template = modelsFolder:FindFirstChild("Dummy")
	if not _template then
		warn("[DummyService] ServerStorage.Models.Dummy template not found")
		return false
	end

	return true
end

-- Cache emote IDs from the Emotes folder (client handles animation loading)
local function cacheEmoteModules()
	-- Get emote modules from Game/Emotes/Emotes/
	local emotesScript = ReplicatedStorage:FindFirstChild("Game")
	emotesScript = emotesScript and emotesScript:FindFirstChild("Emotes")
	local emotesFolder = emotesScript and emotesScript:FindFirstChild("Emotes")

	if emotesFolder then
		for _, moduleScript in emotesFolder:GetChildren() do
			if moduleScript:IsA("ModuleScript") then
				local ok, emoteClass = pcall(require, moduleScript)
				if ok and typeof(emoteClass) == "table" and emoteClass.Id then
					-- Server only needs ID and Loopable flag (clients handle animation loading)
					table.insert(_emoteClasses, {
						class = emoteClass,
						id = emoteClass.Id,
					})
				end
			end
		end
	end

	-- Fallback: scan Assets/Animations/Emotes for emote IDs (if no modules found)
	if #_emoteClasses == 0 then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local animations = assets and assets:FindFirstChild("Animations")
		local emotes = animations and animations:FindFirstChild("Emotes")

		if emotes then
			for _, emoteFolder in emotes:GetChildren() do
				if emoteFolder:IsA("Folder") then
					-- Guess if loopable based on name
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

-- Scan for spawn markers and record their positions
local function scanSpawnMarkers()
	local world = workspace:FindFirstChild("World")
	if not world then
		warn("[DummyService] workspace.World not found")
		return
	end

	local spawnFolder = world:FindFirstChild("DummySpawns")
	if not spawnFolder then
		warn("[DummyService] workspace.World.DummySpawns not found")
		return
	end

	-- Find all DummySpawn markers
	for _, child in spawnFolder:GetChildren() do
		if child.Name == DummyConfig.MarkerName then
			local spawnCFrame

			if child:IsA("Model") then
				spawnCFrame = child:GetPivot()
			elseif child:IsA("BasePart") then
				spawnCFrame = child.CFrame
			else
				continue
			end

			table.insert(_spawnPositions, {
				position = spawnCFrame.Position,
				cframe = spawnCFrame,
			})

			-- Destroy the marker
			child:Destroy()
		end
	end
end

-- Set up the dummy's physics and welds
local function setupDummyPhysics(dummy)
	local root = dummy:FindFirstChild("Root")
	if not root then
		warn("[DummyService] No Root part found in dummy")
		return false
	end

	-- Set Root as PrimaryPart (the physics bean)
	dummy.PrimaryPart = root

	-- Root physics setup
	root.Anchored = false
	root.CanCollide = true
	root.Massless = false

	-- Make dummy heavy and grippy (hard to push)
	root.CustomPhysicalProperties = PhysicalProperties.new(
		50, -- Density (high = heavy, default ~0.7)
		2, -- Friction (high = grippy)
		0, -- Elasticity (no bounce)
		100, -- FrictionWeight
		0 -- ElasticityWeight
	)

	-- Keep dummy upright with AlignOrientation
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
	alignOrientation.CFrame = CFrame.new() -- World upright
	alignOrientation.MaxTorque = 100000 -- Strong torque to stay upright
	alignOrientation.Responsiveness = 50 -- Fast correction
	alignOrientation.RigidityEnabled = false
	alignOrientation.Parent = root

	-- Parts that should be welded to Root (inside Root folder)
	local colliderParts =
		{ "Body", "Feet", "Head", "CrouchBody", "CrouchHead", "CollisionBody", "CollisionHead", "HumanoidRootPart" }
	local weldedCount = 0

	for _, partName in colliderParts do
		local part = root:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			-- These are hitbox/collider parts
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = true -- Can be hit by raycasts
			part.CanTouch = false

			-- Check if already welded
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

			weldedCount = weldedCount + 1
		end
	end

	-- Setup Rig (visual only)
	local rig = dummy:FindFirstChild("Rig")
	if rig then
		local rigHRP = rig:FindFirstChild("HumanoidRootPart")
		if rigHRP then
			-- Weld rig to Root
			rigHRP.Anchored = false
			rigHRP.CanCollide = false
			rigHRP.CanQuery = false
			rigHRP.CanTouch = false
			rigHRP.Massless = true

			-- Check if already welded
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

		-- Make all rig parts non-collidable
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

	-- Setup Collider folder parts
	local collider = dummy:FindFirstChild("Collider")
	if collider then
		for _, descendant in collider:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.Massless = true
				descendant.CanCollide = false
				descendant.CanQuery = true -- Hitboxes
				descendant.CanTouch = false

				-- Weld to Root if not already
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

-- Fire emote to nearby players (client-side emote playback)
local function fireEmoteToNearbyPlayers(dummyPosition, emoteId, action, rig)
	local replicateDistance = DummyConfig.SpawnEmote.ReplicateDistance or 150
	local playerCount = 0

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char and char.PrimaryPart then
			local distance = (char.PrimaryPart.Position - dummyPosition).Magnitude
			if distance <= replicateDistance then
				-- Fire EmoteReplicate: (playerId, emoteId, action, rig)
				-- playerId = 0 indicates this is a rig-based emote (dummy/NPC)
				Net:FireClient("EmoteReplicate", player, 0, emoteId, action, rig)
				playerCount = playerCount + 1
			end
		end
	end

	return playerCount
end

-- Play random spawn emote on dummy (fires to nearby clients)
local function playSpawnEmote(dummy)
	if not DummyConfig.SpawnEmote.Enabled then
		return nil
	end

	if #_emoteClasses == 0 then
		return nil
	end

	-- Get the Rig (this is where animations play on client)
	local rig = dummy:FindFirstChild("Rig")
	if not rig then
		warn("[DummyService] No Rig found in dummy, cannot play emote")
		return nil
	end

	-- Pick random emote (skip "Template" emote if it exists)
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

	-- Get dummy position for distance check
	local dummyPosition = dummy.PrimaryPart and dummy.PrimaryPart.Position or dummy:GetPivot().Position

	-- Fire to nearby players
	local playerCount = fireEmoteToNearbyPlayers(dummyPosition, emoteEntry.id, "play", rig)

	-- Store emote info for stopping later
	local emoteInfo = {
		id = emoteEntry.id,
		rig = rig,
		loopable = isLoopable,
		dummyPosition = dummyPosition,
	}

	-- If loopable, stop after configured duration
	if isLoopable then
		task.delay(DummyConfig.SpawnEmote.LoopDuration, function()
			-- Fire stop to nearby players
			local stopCount = fireEmoteToNearbyPlayers(dummyPosition, emoteEntry.id, "stop", rig)
		end)
	end

	return emoteInfo
end

-- Stop emote on dummy (fires to nearby clients)
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

-- Initialize combat for a dummy and return the CombatResource
-- Returns the resource so caller can connect to OnDeath directly
local function initializeCombat(dummy, pseudoPlayer)
	if not DummyConfig.CombatEnabled then
		warn("[DummyService] Combat disabled in config, skipping combat init for", dummy.Name)
		return nil
	end

	local combatService = _registry and _registry:TryGet("CombatService")
	if combatService then
		combatService:InitializePlayer(pseudoPlayer)
		-- Return the resource immediately after initialization
		local resource = combatService:GetResource(pseudoPlayer)
		if not resource then
			warn(string.format("[DummyService] Failed to get CombatResource for %s", pseudoPlayer.Name))
		end
		return resource
	else
		warn("[DummyService] CombatService not found! Registry:", _registry and "exists" or "nil")
		return nil
	end
end

-- Clean up combat for a dummy
local function cleanupCombat(pseudoPlayer)
	if not DummyConfig.CombatEnabled then
		return
	end

	local combatService = _registry and _registry:TryGet("CombatService")
	if combatService and combatService.CleanupPlayer then
		combatService:CleanupPlayer(pseudoPlayer)
	end
end

-- Spawn a dummy at the given spawn index
local function spawnDummy(spawnIndex)
	if not _template then
		warn("[DummyService] No template cached")
		return nil
	end

	local spawnData = _spawnPositions[spawnIndex]
	if not spawnData then
		warn("[DummyService] Invalid spawn index:", spawnIndex)
		return nil
	end

	-- Clone template
	local dummy = _template:Clone()
	dummy.Name = "Dummy_" .. spawnIndex

	-- Set up physics and welds BEFORE parenting
	setupDummyPhysics(dummy)

	-- Parent to workspace
	local world = workspace:FindFirstChild("World")
	local spawnFolder = world and world:FindFirstChild("DummySpawns")
	dummy.Parent = spawnFolder or workspace

	-- Position at spawn AFTER parenting
	if dummy.PrimaryPart then
		dummy:PivotTo(spawnData.cframe)
	end

	-- Apply collision groups (same as players)
	local collisionGroupService = _registry and _registry:TryGet("CollisionGroupService")
	if collisionGroupService then
		collisionGroupService:SetCharacterCollisionGroup(dummy)
	end

	-- Tag dummy for Aim Assist targeting
	CollectionService:AddTag(dummy, "AimAssistTarget")

	-- Tag specific bones for better aim assist targeting
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

	-- Get humanoid and set health (use recursive search for nested Humanoid in Rig subfolder)
	local humanoid = dummy:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		humanoid.MaxHealth = DummyConfig.MaxHealth
		humanoid.Health = DummyConfig.Health
	else
		warn(string.format("[DummyService] %s: NO HUMANOID FOUND! This will break combat.", dummy.Name))
	end

	-- Create pseudo-player for combat system
	local pseudoPlayer = {
		UserId = getNextDummyId(),
		Name = dummy.Name,
		Character = dummy,
		-- Mimic player methods that combat system might call
		GetAttribute = function(self, name)
			return dummy:GetAttribute(name)
		end,
		SetAttribute = function(self, name, value)
			dummy:SetAttribute(name, value)
		end,
	}

	-- Store dummy info
	_activeDummies[dummy] = {
		spawnIndex = spawnIndex,
		pseudoPlayer = pseudoPlayer,
		emote = nil,
	}

	-- Initialize combat and get resource directly
	local resource = initializeCombat(dummy, pseudoPlayer)

	-- Play spawn emote (after dummy exists and is parented)
	local emote = playSpawnEmote(dummy)
	if emote then
		_activeDummies[dummy].emote = emote
	end

	-- Connect death handler via CombatResource.OnDeath (fires when internal health reaches 0)
	-- This is more reliable than humanoid.Died since CombatService tracks health separately
	if resource then
		resource.OnDeath:once(function(killer, weaponId)
			print(string.format("[DummyService] OnDeath fired for %s (killer=%s, weapon=%s)",
				dummy.Name, killer and killer.Name or "nil", tostring(weaponId)))

			local dummyInfo = _activeDummies[dummy]
			if not dummyInfo then
				warn("[DummyService] OnDeath: dummyInfo not found for", dummy.Name)
				return
			end

			local savedSpawnIndex = dummyInfo.spawnIndex
			local savedPseudoPlayer = dummyInfo.pseudoPlayer
			print(string.format("[DummyService] %s died, savedSpawnIndex=%d, scheduling respawn in %ds",
				dummy.Name, savedSpawnIndex, DummyConfig.RespawnDelay))

			stopEmote(dummy)
			cleanupCombat(savedPseudoPlayer)
			_activeDummies[dummy] = nil

			task.delay(DummyConfig.RespawnDelay, function()
				print(string.format("[DummyService] Respawn timer fired for spawnIndex=%d", savedSpawnIndex))
				if dummy and dummy.Parent then
					dummy:Destroy()
				end
				local newDummy = spawnDummy(savedSpawnIndex)
				print(string.format("[DummyService] Respawn result for spawnIndex=%d: %s",
					savedSpawnIndex, newDummy and newDummy.Name or "FAILED"))
			end)
		end)
	else
		-- Fallback to humanoid.Died if CombatService not available
		warn(string.format("[DummyService] No CombatResource for %s - using humanoid.Died fallback", dummy.Name))
		if humanoid then
			humanoid.Died:Once(function()
				print(string.format("[DummyService] Humanoid.Died fallback fired for %s", dummy.Name))

				local dummyInfo = _activeDummies[dummy]
				if not dummyInfo then
					warn("[DummyService] Humanoid.Died: dummyInfo not found for", dummy.Name)
					return
				end

				local savedSpawnIndex = dummyInfo.spawnIndex
				local savedPseudoPlayer = dummyInfo.pseudoPlayer
				print(string.format("[DummyService] %s died (fallback), savedSpawnIndex=%d", dummy.Name, savedSpawnIndex))

				stopEmote(dummy)
				cleanupCombat(savedPseudoPlayer)
				_activeDummies[dummy] = nil

				task.delay(DummyConfig.RespawnDelay, function()
					print(string.format("[DummyService] Respawn timer (fallback) fired for spawnIndex=%d", savedSpawnIndex))
					if dummy and dummy.Parent then
						dummy:Destroy()
					end
					local newDummy = spawnDummy(savedSpawnIndex)
					print(string.format("[DummyService] Respawn result (fallback) for spawnIndex=%d: %s",
						savedSpawnIndex, newDummy and newDummy.Name or "FAILED"))
				end)
			end)
		end
	end

	return dummy
end

-- Spawn all dummies at recorded positions
local function spawnAllDummies()
	for i = 1, #_spawnPositions do
		spawnDummy(i)
	end
end

--------------------------------------------------
-- Public API
--------------------------------------------------

function DummyService:Init(registry, net)
	if _initialized then
		return
	end
	_initialized = true
	_registry = registry

	-- Cache template
	if not cacheTemplate() then
		warn("[DummyService] Failed to cache template - dummies will not spawn")
		return
	end

	-- Cache emote modules
	cacheEmoteModules()
end

function DummyService:Start()
	-- Scan for spawn markers (destroys them after recording)
	scanSpawnMarkers()

	-- Spawn dummies at all positions
	if #_spawnPositions > 0 then
		spawnAllDummies()
	else
	end
end

-- Get all active dummies
function DummyService:GetDummies()
	local dummies = {}
	for dummy, _ in _activeDummies do
		table.insert(dummies, dummy)
	end
	return dummies
end

-- Get dummy count
function DummyService:GetDummyCount()
	local count = 0
	for _ in _activeDummies do
		count = count + 1
	end
	return count
end

-- Manually spawn a dummy at a position (for testing)
function DummyService:SpawnAt(position)
	if not _template then
		return nil
	end

	-- Add new spawn position
	local newIndex = #_spawnPositions + 1
	_spawnPositions[newIndex] = {
		position = position,
		cframe = CFrame.new(position),
	}

	return spawnDummy(newIndex)
end

-- Destroy all dummies
function DummyService:DestroyAll()
	for dummy, info in _activeDummies do
		-- Stop emote
		stopEmote(dummy)

		-- Cleanup combat
		cleanupCombat(info.pseudoPlayer)

		-- Destroy
		if dummy and dummy.Parent then
			dummy:Destroy()
		end
	end

	_activeDummies = {}
end

-- Respawn all dummies
function DummyService:RespawnAll()
	self:DestroyAll()
	task.wait(0.1) -- Brief delay for cleanup
	spawnAllDummies()
end

return DummyService
