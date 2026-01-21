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
EmoteService._registered = {}           -- { [emoteId] = emoteClass }
EmoteService._activeEmote = nil         -- Current emote instance for local player
EmoteService._activeByRig = {}          -- { [rig] = { [emoteId] = emoteInstance } } for preview rigs
EmoteService._lastPlayTime = 0          -- For cooldown
EmoteService._replicateConnection = nil

-- Emote control state
EmoteService._movementConnection = nil  -- RenderStepped connection for movement detection
EmoteService._jumpConnection = nil      -- Jump input callback connection
EmoteService._slideConnection = nil     -- Slide input callback connection
EmoteService._savedCameraMode = nil     -- Previous camera mode before emote
EmoteService._savedSpeedMultiplier = 1  -- Previous speed multiplier

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

-- Initialize the emote service
function EmoteService.init()
	if EmoteService._initialized then
		return true
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
				warn("[EmoteService] Failed to preload animations:", err)
			end
		end)
	end
end

-- Load all emote modules
function EmoteService._loadEmotes()
	local folder = getEmotesFolder()
	if not folder then
		warn("[EmoteService] Emotes folder not found")
		return
	end
	
	for _, moduleScript in folder:GetChildren() do
		if moduleScript:IsA("ModuleScript") then
			local ok, emoteClass = pcall(require, moduleScript)
			if ok and typeof(emoteClass) == "table" then
				EmoteService.register(emoteClass)
			else
				warn("[EmoteService] Failed to load emote:", moduleScript.Name, emoteClass)
			end
		end
	end
end

-- Setup replication listener
function EmoteService._setupReplication()
	Net:Init()
	
	EmoteService._replicateConnection = Net:ConnectClient("EmoteReplicate", function(playerId, emoteId, action)
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

-- Play emote for another player
function EmoteService._playForOtherPlayer(playerId: number, emoteId: string)
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return
	end
	
	local emoteClass = EmoteService.getEmoteClass(emoteId)
	if not emoteClass then
		return
	end
	
	-- Get animation controller and play
	local animController = ServiceRegistry:GetController("AnimationController")
	if animController and animController.PlayEmoteForOtherPlayer then
		animController:PlayEmoteForOtherPlayer(player, emoteId)
	end
end

-- Stop emote for another player
function EmoteService._stopForOtherPlayer(playerId: number)
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return
	end
	
	local animController = ServiceRegistry:GetController("AnimationController")
	if animController and animController.StopEmoteForOtherPlayer then
		animController:StopEmoteForOtherPlayer(player)
	end
end

-- Register an emote class
function EmoteService.register(emoteClass: { [string]: any }): boolean
	local emoteId = getEmoteId(emoteClass)
	if not emoteId then
		warn("[EmoteService] Emote missing Id")
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
		warn("[EmoteService] Emote not found:", emoteId)
		return false
	end
	
	-- Stop current emote first
	if EmoteService._activeEmote then
		EmoteService.stop()
	end
	
	-- Get rig
	local rig = EmoteService._getLocalRig()
	if not rig then
		warn("[EmoteService] No rig found for local player")
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
	
	-- Play via AnimationController
	local animController = ServiceRegistry:GetController("AnimationController")
	if animController and animController.PlayEmote then
		local success = animController:PlayEmote(emoteId)
		if not success then
			emote:destroy()
			return false
		end
	end
	
	-- Start emote
	local started = emote:start()
	if not started then
		emote:destroy()
		return false
	end
	
	-- Setup finished callback
	emote:onFinished(function()
		if EmoteService._activeEmote == emote then
			EmoteService.stop()
		end
	end)
	
	EmoteService._activeEmote = emote
	EmoteService._lastPlayTime = tick()
	
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
	-- MOVEMENT CANCELLATION - Cancel emote if AllowMove=false and player moves/jumps
	-- =========================================================================
	local allowMove = emoteData.AllowMove
	if allowMove == nil then
		allowMove = EmoteConfig.Defaults.AllowMove
	end
	
	if not allowMove then
		local MOVEMENT_THRESHOLD = 0.1
		
		-- Get InputController for movement detection
		local inputController = ServiceRegistry:GetController("Input")
		
		-- Connect to RenderStepped to check movement input
		EmoteService._movementConnection = RunService.RenderStepped:Connect(function()
			if not inputController then return end
			
			local moveVector = inputController:GetMovementVector()
			if moveVector then
				local horizontalMag = math.sqrt(moveVector.X * moveVector.X + moveVector.Y * moveVector.Y)
				if horizontalMag > MOVEMENT_THRESHOLD then
					EmoteService.stop()
				end
			end
		end)
		
		-- Connect to Jump callback
		if inputController and inputController.ConnectToInput then
			EmoteService._jumpConnection = inputController:ConnectToInput("Jump", function(isPressed)
				if isPressed and EmoteService._activeEmote then
					EmoteService.stop()
				end
			end)
		end
		
		-- Connect to Slide callback
		if inputController and inputController.ConnectToInput then
			EmoteService._slideConnection = inputController:ConnectToInput("Slide", function(isPressed)
				if isPressed and EmoteService._activeEmote then
					EmoteService.stop()
				end
			end)
		end
	end
	
	-- Fire to server
	Net:FireServer("EmotePlay", emoteId)
	
	return true
end

-- Stop current emote
function EmoteService.stop(): boolean
	if not EmoteService._activeEmote then
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
	
	-- =========================================================================
	-- RESTORE CAMERA MODE - Back to FirstPerson (with isLobby placeholder)
	-- =========================================================================
	local cameraController = ServiceRegistry:GetController("CameraController")
	if cameraController then
		-- isLobby placeholder - will be important later for lobby logic
		local isLobby = false
		
		if isLobby then
			-- In lobby, restore to saved mode
			if EmoteService._savedCameraMode then
				cameraController:SetMode(EmoteService._savedCameraMode)
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
	
	-- Stop animation
	local animController = ServiceRegistry:GetController("AnimationController")
	if animController and animController.StopEmote then
		animController:StopEmote()
	end
	
	-- Stop emote instance (clear reference first to prevent re-entry)
	local emote = EmoteService._activeEmote
	EmoteService._activeEmote = nil
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
function EmoteService.playOnRig(emoteId: string, rig: Model): boolean
	if not emoteId or not rig then
		return false
	end
	
	local emoteClass = EmoteService.getEmoteClass(emoteId)
	if not emoteClass or not emoteClass.Animations or not emoteClass.Animations.Main then
		return false
	end
	
	-- Stop existing emote on this rig
	EmoteService.stopOnRig(emoteId, rig)
	
	-- Get animator from rig
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	
	-- Create and play animation
	local animId = emoteClass.Animations.Main
	if not animId:match("^rbxassetid://") then
		animId = "rbxassetid://" .. animId
	end
	
	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	
	local track = animator:LoadAnimation(animation)
	track.Looped = emoteClass.Loopable or false
	track:Play(0.2)
	
	-- Track it
	if not EmoteService._activeByRig[rig] then
		EmoteService._activeByRig[rig] = {}
	end
	EmoteService._activeByRig[rig][emoteId] = track
	
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
		local track = bucket[emoteId]
		if track and typeof(track) == "Instance" and track:IsA("AnimationTrack") and track.IsPlaying then
			track:Stop(0.2)
		end
		bucket[emoteId] = nil
	else
		for _, track in bucket do
			if track and typeof(track) == "Instance" and track:IsA("AnimationTrack") and track.IsPlaying then
				track:Stop(0.2)
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
