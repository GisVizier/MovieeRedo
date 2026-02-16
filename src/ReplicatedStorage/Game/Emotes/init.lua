--[[
	EmoteService - Client-side emote management
	
	Handles:
	- Discovering and registering emote modules from Emotes/ subfolder
	- Provides play(), stop(), stopAll() APIs
	- Fires EmotePlay remote to server
	- Listens for EmoteReplicate to play other players' emotes
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local Net = require(Locations.Shared.Net.Net)
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local EmoteConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("EmoteConfig"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))

local EmoteBase = require(script.EmoteBase)

local EmoteService = {}
EmoteService.__index = EmoteService

local LocalPlayer = Players.LocalPlayer

-- Internal state
EmoteService._initialized = false
EmoteService._registered = {} -- { [emoteId] = emoteClass }
EmoteService._activeEmote = nil -- Current emote instance for local player
EmoteService._activeByRig = {} -- { [rig] = { [emoteId] = emoteInstance } } for preview rigs
EmoteService._activeByPlayer = {} -- { [playerId] = emoteInstance } for other players' emotes
EmoteService._lastPlayTime = 0 -- For cooldown
EmoteService._replicateConnection = nil

-- Emote control state
EmoteService._movementConnection = nil -- RenderStepped connection for movement detection
EmoteService._jumpConnection = nil -- Jump input callback connection
EmoteService._slideConnection = nil -- Slide input callback connection
EmoteService._sprintConnection = nil -- Sprint input callback connection
EmoteService._savedCameraMode = nil -- Previous camera mode before emote
EmoteService._savedSpeedMultiplier = 1 -- Previous speed multiplier

-- Get emote modules folder
local function getEmotesFolder()
	return script:FindFirstChild("Emotes")
end

-- Get emote ID from class
local function getEmoteId(emoteClass: { [string]: any }): string?
	if not emoteClass then
		return nil
	end
	return emoteClass.Id or emoteClass.id or emoteClass.EmoteId
end

-- Get emote data from class
local function getEmoteData(emoteClass: { [string]: any }): { [string]: any }
	return {
		Id = emoteClass.Id or emoteClass.id,
		DisplayName = emoteClass.DisplayName or emoteClass.displayName or emoteClass.Id,
		Rarity = emoteClass.Rarity or emoteClass.rarity or "Common",
		Loopable = emoteClass.Loopable,
		AllowMove = emoteClass.AllowMove,
		Speed = emoteClass.Speed,
		FadeInTime = emoteClass.FadeInTime,
		FadeOutTime = emoteClass.FadeOutTime,
		MoveSpeedMultiplier = emoteClass.MoveSpeedMultiplier or 1,
	}
end

local function setupAutoStopIfNeeded(emote, loopable, hasMainTrack)
	if not emote or loopable == true or not hasMainTrack then
		return
	end

	if type(emote.SetupAutoStop) == "function" then
		emote:SetupAutoStop("Main")
	end
end

-- Initialize the emote service
function EmoteService.init()
	if EmoteService._initialized then
		return true
	end

	if LocalPlayer then
		LocalPlayer:SetAttribute("IsEmoting", false)
	end

	EmoteService._initialized = true
	EmoteService._loadEmotes()
	EmoteService._preloadAnimations()
	EmoteService._setupReplication()

	return true
end

-- Preload all animation assets from emote modules
function EmoteService._preloadAnimations()
	local animationIds = {}

	for emoteId, emoteClass in EmoteService._registered do
		if emoteClass.Animations and typeof(emoteClass.Animations) == "table" then
			for animName, animId in emoteClass.Animations do
				if typeof(animId) == "string" and animId ~= "" then
					-- Normalize to rbxassetid format
					local assetId = animId
					if not assetId:match("^rbxassetid://") then
						assetId = "rbxassetid://" .. animId
					end
					table.insert(animationIds, assetId)
				end
			end
		end
	end

	if #animationIds > 0 then
		task.spawn(function()
			local ok, err = pcall(function()
				ContentProvider:PreloadAsync(animationIds)
			end)
			if not ok then
			end
		end)
	end
end

-- Load all emote modules
function EmoteService._loadEmotes()
	local folder = getEmotesFolder()
	if not folder then
		return
	end

	for _, moduleScript in folder:GetChildren() do
		if moduleScript:IsA("ModuleScript") then
			local ok, emoteClass = pcall(require, moduleScript)
			if ok and typeof(emoteClass) == "table" then
				EmoteService.register(emoteClass)
			else
			end
		end
	end
end

-- Setup replication listener
function EmoteService._setupReplication()
	Net:Init()

	-- Extended format: (playerId, emoteId, action, rig?)
	-- If rig is provided, it's a dummy/NPC emote - play directly on that rig
	-- If playerId > 0, it's a player emote - look up their rig
	EmoteService._replicateConnection = Net:ConnectClient("EmoteReplicate", function(playerId, emoteId, action, rig)
		-- Direct rig provided (dummies/NPCs)
		if rig and typeof(rig) == "Instance" then
			if action == "play" then
				EmoteService._playForRig(rig, emoteId)
			elseif action == "stop" then
				EmoteService._stopForRig(rig)
			end
			return
		end

		-- Player-based emote (existing logic)
		if playerId == LocalPlayer.UserId then
			-- Already handled locally
			return
		end

		if action == "play" then
			EmoteService._playForOtherPlayer(playerId, emoteId)
		elseif action == "stop" then
			EmoteService._stopForOtherPlayer(playerId)
		end
	end)
end

-- Get cosmetic rig for another player
function EmoteService._getRigForPlayer(player: Player): Model?
	if not player or not player.Character then
		return nil
	end

	return CharacterLocations:GetRig(player.Character)
end

-- Play emote for another player (creates full emote instance with props)
function EmoteService._playForOtherPlayer(playerId: number, emoteId: string)
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return
	end

	local emoteClass = EmoteService.getEmoteClass(emoteId)
	if not emoteClass then
		return
	end

	-- Stop any existing emote for this player
	EmoteService._stopForOtherPlayer(playerId)

	-- Get the player's cosmetic rig
	local rig = EmoteService._getRigForPlayer(player)
	if not rig then
		return
	end

	-- Create emote instance for this player's rig
	local emoteData = getEmoteData(emoteClass)
	local emote = nil

	if emoteClass.new then
		local ok, result = pcall(function()
			return emoteClass.new(emoteId, emoteData, rig)
		end)
		if ok then
			emote = result
		else
		end
	end

	if not emote then
		emote = EmoteBase.new(emoteId, emoteData, rig)
	end

	-- Start the emote (spawns props, etc.)
	local started = emote:start()
	if not started then
		emote:destroy()
		return
	end

	-- Play animation with proper looping
	local loopable = emoteData.Loopable
	if loopable == nil then
		loopable = EmoteConfig.Defaults.Loopable
	end

	-- Play animation using the emote's helper (respects looping)
	local hasMainTrack = false
	if emoteClass.Animations and emoteClass.Animations.Main then
		local track = emote:PlayAnimation("Main")
		if track then
			track.Looped = loopable
			hasMainTrack = true
		end
	end
	setupAutoStopIfNeeded(emote, loopable, hasMainTrack)

	-- Store emote for cleanup
	EmoteService._activeByPlayer[playerId] = emote
end

-- Stop emote for another player
function EmoteService._stopForOtherPlayer(playerId: number)
	local emote = EmoteService._activeByPlayer[playerId]
	if emote then
		-- Stop and destroy emote instance (cleans up props, animations, etc.)
		pcall(function()
			emote:stop()
		end)
		pcall(function()
			emote:destroy()
		end)
		EmoteService._activeByPlayer[playerId] = nil
	end

	-- Also stop animation via AnimationController as backup
	local player = Players:GetPlayerByUserId(playerId)
	if player then
		local animController = ServiceRegistry:GetController("AnimationController")
		if animController and animController.StopEmoteForOtherPlayer then
			animController:StopEmoteForOtherPlayer(player)
		end
	end
end

-- Play emote for a rig directly (dummies/NPCs)
function EmoteService._playForRig(rig: Model, emoteId: string)
	if not rig or not rig:IsA("Model") then
		return
	end

	local emoteClass = EmoteService.getEmoteClass(emoteId)
	if not emoteClass then
		return
	end

	-- Stop any existing emote for this rig
	EmoteService._stopForRig(rig)

	-- Create emote instance for this rig
	local emoteData = getEmoteData(emoteClass)
	local emote = nil

	if emoteClass.new then
		local ok, result = pcall(function()
			return emoteClass.new(emoteId, emoteData, rig)
		end)
		if ok then
			emote = result
		else
		end
	end

	if not emote then
		emote = EmoteBase.new(emoteId, emoteData, rig)
	end

	-- Start the emote (spawns props, etc.)
	local started = emote:start()
	if not started then
		pcall(function()
			emote:destroy()
		end)
		return
	end

	-- Play animation with proper looping
	local loopable = emoteData.Loopable
	if loopable == nil then
		loopable = EmoteConfig.Defaults.Loopable
	end

	-- Play animation using the emote's helper (respects looping)
	local hasMainTrack = false
	if emoteClass.Animations and emoteClass.Animations.Main then
		local track = emote:PlayAnimation("Main")
		if track then
			track.Looped = loopable
			hasMainTrack = true
		end
	end
	setupAutoStopIfNeeded(emote, loopable, hasMainTrack)

	-- Store emote for cleanup (keyed by rig instance)
	EmoteService._activeByRig[rig] = EmoteService._activeByRig[rig] or {}
	EmoteService._activeByRig[rig][emoteId] = emote
end

-- Stop emote for a rig directly (dummies/NPCs)
function EmoteService._stopForRig(rig: Model)
	if not rig then
		return
	end

	local rigEmotes = EmoteService._activeByRig[rig]
	if rigEmotes then
		for emoteId, emote in rigEmotes do
			pcall(function()
				emote:stop()
			end)
			pcall(function()
				emote:destroy()
			end)
		end
		EmoteService._activeByRig[rig] = nil
	end
end

-- Register an emote class
function EmoteService.register(emoteClass: { [string]: any }): boolean
	local emoteId = getEmoteId(emoteClass)
	if not emoteId then
		return false
	end

	EmoteService._registered[emoteId] = emoteClass
	return true
end

-- Get registered emote class
function EmoteService.getEmoteClass(emoteId: string): { [string]: any }?
	return EmoteService._registered[emoteId]
end

-- Get emote data
function EmoteService.getEmoteData(emoteId: string): { [string]: any }?
	local emoteClass = EmoteService.getEmoteClass(emoteId)
	if not emoteClass then
		return nil
	end
	return getEmoteData(emoteClass)
end

-- Get emote info for UI
function EmoteService.getEmoteInfo(emoteId: string): { id: string, displayName: string, rarity: string }?
	local data = EmoteService.getEmoteData(emoteId)
	if not data then
		return nil
	end
	return {
		id = emoteId,
		displayName = data.DisplayName or emoteId,
		rarity = data.Rarity or "Common",
	}
end

-- Get emote rarity
function EmoteService.getEmoteRarity(emoteId: string): string?
	local data = EmoteService.getEmoteData(emoteId)
	return data and data.Rarity or nil
end

-- Get list of all registered emotes
function EmoteService.getEmoteList(): { { [string]: any } }
	local list = {}
	for _, emoteClass in EmoteService._registered do
		table.insert(list, emoteClass)
	end
	return list
end

-- Get list of emote IDs
function EmoteService.getEmoteIds(): { string }
	local ids = {}
	for emoteId, _ in EmoteService._registered do
		table.insert(ids, emoteId)
	end
	return ids
end

-- Check cooldown
function EmoteService._checkCooldown(): boolean
	if not EmoteConfig.Cooldown.Enabled then
		return true
	end

	local elapsed = tick() - EmoteService._lastPlayTime
	return elapsed >= EmoteConfig.Cooldown.Duration
end

-- Get cosmetic rig for local player
function EmoteService._getLocalRig(): Model?
	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	return CharacterLocations:GetRig(character)
end

-- Play an emote
function EmoteService.play(emoteId: string): boolean
	if not EmoteService._initialized then
		EmoteService.init()
	end

	-- Check cooldown
	if not EmoteService._checkCooldown() then
		return false
	end

	local emoteClass = EmoteService.getEmoteClass(emoteId)
	if not emoteClass then
		return false
	end

	-- Stop current emote first
	if EmoteService._activeEmote then
		EmoteService.stop()
	end

	-- Get rig
	local rig = EmoteService._getLocalRig()
	if not rig then
		return false
	end

	-- Create emote instance
	local emoteData = getEmoteData(emoteClass)
	local emote = nil

	if emoteClass.new then
		local ok, result = pcall(function()
			return emoteClass.new(emoteId, emoteData, rig)
		end)
		if ok then
			emote = result
		end
	end

	if not emote then
		emote = EmoteBase.new(emoteId, emoteData, rig)
	end

	-- Start emote (runs custom start logic like prop spawning)
	local started = emote:start()
	if not started then
		emote:destroy()
		return false
	end

	-- Play animation with proper looping
	-- (Some emotes play their own animation in start(), others don't)
	local loopable = emoteData.Loopable
	if loopable == nil then
		loopable = EmoteConfig.Defaults.Loopable
	end

	-- Check if animation was already played by start(), if not play it now
	local existingTrack = emote:GetTrack("Main")
	local hasMainTrack = false
	if not existingTrack and emoteClass.Animations and emoteClass.Animations.Main then
		local track = emote:PlayAnimation("Main")
		if track then
			track.Looped = loopable
			hasMainTrack = true
		end
	elseif existingTrack then
		-- Ensure looping is set correctly even if start() played it
		existingTrack.Looped = loopable
		hasMainTrack = true
	end
	setupAutoStopIfNeeded(emote, loopable, hasMainTrack)

	-- Setup finished callback
	emote:onFinished(function()
		if EmoteService._activeEmote == emote then
			EmoteService.stop()
		end
	end)

	EmoteService._activeEmote = emote
	EmoteService._lastPlayTime = tick()
	LocalPlayer:SetAttribute("IsEmoting", true)

	-- =========================================================================
	-- CAMERA MODE SWITCH - Force to Orbit mode while emoting
	-- =========================================================================
	local cameraController = ServiceRegistry:GetController("CameraController")
	if cameraController then
		EmoteService._savedCameraMode = cameraController:GetCurrentMode()
		cameraController:SetMode("Orbit")
	end

	-- =========================================================================
	-- SPEED MULTIPLIER - Apply emote speed to player movement
	-- =========================================================================
	local speedMult = emoteData.MoveSpeedMultiplier or 1
	EmoteService._savedSpeedMultiplier = LocalPlayer:GetAttribute("EmoteSpeedMultiplier") or 1
	LocalPlayer:SetAttribute("EmoteSpeedMultiplier", speedMult)

	-- =========================================================================
	-- ALWAYS CANCEL ON: Jump, Slide, Sprint (even if AllowMove = true)
	-- =========================================================================
	local inputController = ServiceRegistry:GetController("Input")

	if inputController and inputController.ConnectToInput then
		-- Jump cancels emote
		EmoteService._jumpConnection = inputController:ConnectToInput("Jump", function(isPressed)
			if isPressed and EmoteService._activeEmote then
				EmoteService.stop()
			end
		end)

		-- Slide cancels emote
		EmoteService._slideConnection = inputController:ConnectToInput("Slide", function(isPressed)
			if isPressed and EmoteService._activeEmote then
				EmoteService.stop()
			end
		end)

		-- Sprint cancels emote
		EmoteService._sprintConnection = inputController:ConnectToInput("Sprint", function(isPressed)
			if isPressed and EmoteService._activeEmote then
				EmoteService.stop()
			end
		end)
	end

	-- =========================================================================
	-- MOVEMENT CANCELLATION - Only cancel on WASD if AllowMove = false
	-- =========================================================================
	local allowMove = emoteData.AllowMove
	if allowMove == nil then
		allowMove = EmoteConfig.Defaults.AllowMove
	end

	if not allowMove then
		local MOVEMENT_THRESHOLD = 0.1

		-- Connect to RenderStepped to check movement input
		EmoteService._movementConnection = RunService.RenderStepped:Connect(function()
			if not inputController then
				return
			end

			local moveVector = inputController:GetMovementVector()
			if moveVector then
				local horizontalMag = math.sqrt(moveVector.X * moveVector.X + moveVector.Y * moveVector.Y)
				if horizontalMag > MOVEMENT_THRESHOLD then
					EmoteService.stop()
				end
			end
		end)
	end

	-- Fire to server
	Net:FireServer("EmotePlay", emoteId)

	return true
end

-- Stop current emote
function EmoteService.stop(): boolean
	if not EmoteService._activeEmote then
		LocalPlayer:SetAttribute("IsEmoting", false)
		return true
	end

	-- =========================================================================
	-- CLEANUP MOVEMENT DETECTION
	-- =========================================================================
	if EmoteService._movementConnection then
		EmoteService._movementConnection:Disconnect()
		EmoteService._movementConnection = nil
	end

	if EmoteService._jumpConnection then
		EmoteService._jumpConnection:Disconnect()
		EmoteService._jumpConnection = nil
	end

	if EmoteService._slideConnection then
		EmoteService._slideConnection:Disconnect()
		EmoteService._slideConnection = nil
	end

	if EmoteService._sprintConnection then
		EmoteService._sprintConnection:Disconnect()
		EmoteService._sprintConnection = nil
	end

	-- =========================================================================
	-- RESTORE CAMERA MODE - Back to saved mode in lobby, FirstPerson otherwise
	-- =========================================================================
	local cameraController = ServiceRegistry:GetController("CameraController")
	if cameraController then
		-- Check if player is in lobby
		local isLobby = LocalPlayer and LocalPlayer:GetAttribute("InLobby") == true

		if isLobby then
			-- In lobby, restore to saved mode or default to Orbit
			if EmoteService._savedCameraMode then
				cameraController:SetMode(EmoteService._savedCameraMode)
			else
				cameraController:SetMode("Orbit")
			end
		else
			-- Not in lobby, force FirstPerson
			cameraController:SetMode("FirstPerson")
		end
		EmoteService._savedCameraMode = nil
	end

	-- =========================================================================
	-- RESTORE SPEED MULTIPLIER
	-- =========================================================================
	LocalPlayer:SetAttribute("EmoteSpeedMultiplier", 1)
	EmoteService._savedSpeedMultiplier = 1

	-- Stop emote instance (clear reference first to prevent re-entry)
	-- The emote's stop() method handles stopping animations via StopAllAnimations()
	local emote = EmoteService._activeEmote
	EmoteService._activeEmote = nil
	LocalPlayer:SetAttribute("IsEmoting", false)
	if emote then
		emote:stop()
		emote:destroy()
	end

	-- Fire to server
	Net:FireServer("EmoteStop")

	return true
end

-- Stop all emotes (alias for stop)
function EmoteService.stopAll(): boolean
	return EmoteService.stop()
end

-- ============================================================================
-- PREVIEW RIG METHODS (for viewport previews, no server replication)
-- ============================================================================

-- Play emote on a specific rig (for preview viewports)
-- Creates a full emote instance and calls start() so custom logic (props, etc.) runs
function EmoteService.playOnRig(emoteId: string, rig: Model): boolean
	if not emoteId or not rig then
		return false
	end

	local emoteClass = EmoteService.getEmoteClass(emoteId)
	if not emoteClass then
		return false
	end

	-- Stop existing emote on this rig
	EmoteService.stopOnRig(emoteId, rig)

	-- Create emote instance with the preview rig
	local emoteData = getEmoteData(emoteClass)
	local emote = nil

	if emoteClass.new then
		local ok, result = pcall(function()
			return emoteClass.new(emoteId, emoteData, rig)
		end)
		if ok then
			emote = result
		end
	end

	if not emote then
		emote = EmoteBase.new(emoteId, emoteData, rig)
	end

	-- Mark as preview
	emote._isPreview = true

	-- Wrap stop() to auto-restart for preview dummies
	local originalStop = emote.stop
	emote.stop = function(self)
		local result = originalStop(self)
		-- After stop returns, restart the emote (if not destroyed)
		task.defer(function()
			-- Check if emote was destroyed (stopOnRig sets _data to nil)
			if self._data and self._rig then
				self:start()
			end
		end)
		return result
	end

	-- Start the emote (runs custom start logic like prop spawning)
	emote:start()

	-- Play animation if available
	local loopable = emoteData.Loopable
	if loopable == nil then
		loopable = EmoteConfig.Defaults.Loopable
	end
	local hasMainTrack = false
	if emoteClass.Animations and emoteClass.Animations.Main then
		local track = emote:PlayAnimation("Main")
		if track then
			track.Looped = loopable
			hasMainTrack = true
		end
	end
	setupAutoStopIfNeeded(emote, loopable, hasMainTrack)

	-- Store emote instance (not just track)
	if not EmoteService._activeByRig[rig] then
		EmoteService._activeByRig[rig] = {}
	end
	EmoteService._activeByRig[rig][emoteId] = emote

	return true
end

-- Stop emote on a specific rig
function EmoteService.stopOnRig(emoteId: string, rig: Model): boolean
	if not rig then
		return true
	end

	local bucket = EmoteService._activeByRig[rig]
	if not bucket then
		return true
	end

	if emoteId then
		local emote = bucket[emoteId]
		if emote then
			-- Call stop and destroy on the emote instance
			if type(emote.stop) == "function" then
				pcall(function()
					emote:stop()
				end)
			end
			if type(emote.destroy) == "function" then
				pcall(function()
					emote:destroy()
				end)
			end
		end
		bucket[emoteId] = nil
	else
		for _, emote in bucket do
			if emote then
				if type(emote.stop) == "function" then
					pcall(function()
						emote:stop()
					end)
				end
				if type(emote.destroy) == "function" then
					pcall(function()
						emote:destroy()
					end)
				end
			end
		end
		EmoteService._activeByRig[rig] = nil
	end

	return true
end

-- Check if an emote is playing
function EmoteService.isPlaying(): boolean
	return EmoteService._activeEmote ~= nil
end

-- Get current emote ID
function EmoteService.getCurrentEmoteId(): string?
	if not EmoteService._activeEmote then
		return nil
	end
	return EmoteService._activeEmote._id
end

-- Cleanup
function EmoteService.destroy()
	EmoteService.stop()

	if EmoteService._replicateConnection then
		EmoteService._replicateConnection:Disconnect()
		EmoteService._replicateConnection = nil
	end

	EmoteService._registered = {}
	EmoteService._initialized = false
end

return EmoteService
