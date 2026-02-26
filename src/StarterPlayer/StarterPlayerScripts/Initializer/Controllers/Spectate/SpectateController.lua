local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local CharacterLocations = require(Locations.Game:WaitForChild("Character"):WaitForChild("CharacterLocations"))
local CompressionUtils = require(Locations.Shared.Util:WaitForChild("CompressionUtils"))
local ServiceRegistry = require(Locations.Shared.Util:WaitForChild("ServiceRegistry"))
local CreateLoadout = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("CreateLoadout"))
local ViewmodelAnimator = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("ViewmodelAnimator"))
local Spring = require(Locations.Game:WaitForChild("Viewmodel"):WaitForChild("Spring"))
local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))
local CameraConfig = require(ReplicatedStorage:WaitForChild("Global"):WaitForChild("Camera"))
local Config = require(Locations.Shared:WaitForChild("Config"):WaitForChild("Config"))
local FOVController = require(Locations.Shared:WaitForChild("Util"):WaitForChild("FOVController"))

local LocalPlayer = Players.LocalPlayer

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function clamp(value, minVal, maxVal)
	return math.max(minVal, math.min(maxVal, value))
end

local SpectateController = {}

SpectateController._registry = nil
SpectateController._net = nil

SpectateController._active = false
SpectateController._targetUserId = nil
SpectateController._targetList = {}
SpectateController._targetIndex = 0
SpectateController._onEndCallbacks = {}

SpectateController._matchMode = nil
SpectateController._team1 = nil
SpectateController._team2 = nil
SpectateController._myTeam = nil

SpectateController._renderConn = nil
SpectateController._vmRenderConn = nil

-- Health watching
SpectateController._spectateHealthConn = nil
SpectateController._specLastHealth = nil
SpectateController._cachedLocalHealth = nil
SpectateController._cachedLocalMaxHealth = nil

-- Emote mode
SpectateController._spectateEmoteMode = false
SpectateController._emoteRenderConn = nil

SpectateController._spectateVmLoadout = nil
SpectateController._spectateAnimator = nil
SpectateController._spectateWeaponIds = nil
SpectateController._specMoveState = nil
SpectateController._vmSprings = nil
SpectateController._prevSpecCamCF = nil
SpectateController._vmBobT = 0
SpectateController._lastSpecTargetPos = nil
SpectateController._spectateStartTime = 0
SpectateController._specCurrentCrouchOffset = 0
SpectateController._specWasSliding = false

local FP_OFFSET = CameraConfig.FirstPerson and CameraConfig.FirstPerson.Offset or Vector3.new(0, 0.4, 0)
local RESPAWN_CHECK_DELAY = 0.5

local ROTATION_SENSITIVITY = -3.2
local ROTATION_SPRING_SPEED = 18
local ROTATION_SPRING_DAMPER = 0.85
local BOB_SPRING_SPEED = 14
local BOB_SPRING_DAMPER = 0.85
local BOB_FREQ = 6
local BOB_AMP_X = 0.04
local BOB_AMP_Y = 0.03

local MOVE_START_SPEED = 1.25
local MOVE_STOP_SPEED = 0.75

-- Slide viewmodel constants (match ViewmodelController)
local SLIDE_SPEED_THRESHOLD = 15 -- Crouch walk ~8, slide typically 30+
local SLIDE_ROLL = math.rad(30)
local SLIDE_PITCH = math.rad(6)
local SLIDE_YAW = math.rad(0)
local SLIDE_TUCK = Vector3.new(0.12, -0.12, 0.18)
local TILT_SPRING_SPEED = 12
local TILT_SPRING_DAMPER = 0.9

local function getRemoteReplicator()
	local game_rep = Locations.Game:FindFirstChild("Replication")
	if not game_rep then return nil end
	local mod = game_rep:FindFirstChild("RemoteReplicator")
	if not mod then return nil end
	return require(mod)
end

local function getPlayerByUserId(userId)
	for _, p in Players:GetPlayers() do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end

local function isPlayerAlive(userId)
	local player = getPlayerByUserId(userId)
	if not player or not player.Character or not player.Character.Parent then
		return false
	end
	if player.Character:GetAttribute("RagdollActive") == true then
		return false
	end
	return true
end

local function getHumanoidHead(userId)
	local player = getPlayerByUserId(userId)
	if not player or not player.Character then return nil end
	return CharacterLocations:GetHumanoidHead(player.Character)
end

local function getRigHead(userId)
	local player = getPlayerByUserId(userId)
	if not player or not player.Character then return nil end
	local rig = CharacterLocations:GetRig(player.Character)
	if not rig then return nil end
	return rig:FindFirstChild("Head")
end

local function getCoreUI()
	local uiController = ServiceRegistry:GetController("UI")
	if not uiController or not uiController.GetCoreUI then return nil end
	return uiController:GetCoreUI()
end

local function getRemoteData(userId)
	local rep = getRemoteReplicator()
	if not rep then return nil end
	return rep.RemotePlayers[userId]
end

SpectateController._hudModule = nil
SpectateController._damagedOverlayModule = nil

function SpectateController:_getHUD()
	if self._hudModule then return self._hudModule end
	local coreUi = getCoreUI()
	if not coreUi then return nil end
	self._hudModule = coreUi:getModule("HUD")
	return self._hudModule
end

function SpectateController:_getDamagedOverlay()
	if self._damagedOverlayModule then return self._damagedOverlayModule end
	local coreUi = getCoreUI()
	if not coreUi then return nil end
	self._damagedOverlayModule = coreUi:getModule("Damaged")
	return self._damagedOverlayModule
end

function SpectateController:Init(registry, net)
	self._registry = registry
	self._net = net

	ServiceRegistry:RegisterController("Spectate", self)

	self._net:ConnectClient("MatchStart", function(matchData)
		self:_onMatchStart(matchData)
	end)

	self._net:ConnectClient("RoundStart", function()
		self:EndSpectate()
	end)

	self._net:ConnectClient("ShowRoundLoadout", function()
		self:EndSpectate()
	end)

	self._net:ConnectClient("PlayerRespawned", function()
		self:EndSpectate()
	end)

	self._net:ConnectClient("ReturnToLobby", function()
		self:EndSpectate()
		self:_clearMatchData()
	end)

	self._net:ConnectClient("ViewmodelActionReplicated", function(compressedPayload)
		self:_onViewmodelActionReplicated(compressedPayload)
	end)

	-- When the spectated player starts/stops an emote, switch to 3rd person view
	self._net:ConnectClient("EmoteReplicate", function(playerId, _emoteId, action)
		self:_onEmoteReplicate(playerId, action)
	end)

	-- VFX forwarding handled by VFXRep's SpectateVFXForward client handler;
	-- it sets data._spectate = true so modules know to use data.ViewModel/Character
end

function SpectateController:Start() end

function SpectateController:GetSpectateViewmodelRig()
	if not self._active or not self._spectateVmLoadout or not self._spectateActiveSlot then
		return nil
	end
	return self._spectateVmLoadout.Rigs[self._spectateActiveSlot]
end

--[[
	Play a kit animation on the spectate viewmodel.
	Called by VFX modules (e.g. Cloudskip) when SpectateVFXForward arrives,
	so spectators see the animation sooner if ViewmodelActionReplicated is delayed.
	Kit abilities use the Fists viewmodel, so we switch to that slot first.
]]
function SpectateController:PlayKitAnimation(trackName)
	if not self._active or not self._spectateVmLoadout then return end
	if not trackName or type(trackName) ~= "string" then return end

	-- Kit animations use Fists viewmodel; switch slot if needed
	if self._spectateActiveSlot ~= "Fists" then
		local fistsRig = self._spectateVmLoadout.Rigs.Fists
		if not fistsRig then return end

		if self._spectateActiveSlot then
			local oldRig = self._spectateVmLoadout.Rigs[self._spectateActiveSlot]
			if oldRig and oldRig.Model then
				oldRig.Model.Parent = nil
			end
		end

		self._spectateActiveSlot = "Fists"
		if fistsRig.Model then
			fistsRig.Model.Parent = workspace.CurrentCamera
		end
		self:_bindAnimator(fistsRig, "Fists")
	end

	self:_playSpectateKitAnim(trackName)
end

function SpectateController:_onMatchStart(matchData)
	self:EndSpectate()

	if type(matchData) ~= "table" then return end

	self._matchMode = matchData.mode
	self._team1 = matchData.team1 or {}
	self._team2 = matchData.team2 or {}

	local myId = LocalPlayer and LocalPlayer.UserId
	if myId then
		self._myTeam = nil
		for _, uid in self._team1 do
			if uid == myId then
				self._myTeam = self._team1
				break
			end
		end
		if not self._myTeam then
			for _, uid in self._team2 do
				if uid == myId then
					self._myTeam = self._team2
					break
				end
			end
		end
	end
end

function SpectateController:_clearMatchData()
	self._matchMode = nil
	self._team1 = nil
	self._team2 = nil
	self._myTeam = nil
end

function SpectateController:IsSpectating()
	return self._active
end

function SpectateController:GetTargetUserId()
	return self._targetUserId
end

function SpectateController:BeginSpectate(killerUserId)
	if self._active then return end

	local targets = self:_buildTargetList(killerUserId)
	if #targets == 0 then
		return
	end

	-- Cache local player's health so we can restore it when spectating ends
	self._cachedLocalHealth = LocalPlayer and LocalPlayer:GetAttribute("Health") or 100
	self._cachedLocalMaxHealth = LocalPlayer and LocalPlayer:GetAttribute("MaxHealth") or 100

	self._active = true
	self._targetList = targets
	self._targetIndex = 1
	self._targetUserId = targets[1]
	self._spectateStartTime = tick()

	self:_buildSpectateViewmodel()
	self:_bindRenderLoop()
	self:_hideTargetRig()
	self:_connectHealthWatcher()

	-- Tell server so "Me" VFX from this target get forwarded to us
	pcall(function()
		self._net:FireServer("SpectateRegister", self._targetUserId)
	end)
end

function SpectateController:OnSpectateEnded(fn)
	table.insert(self._onEndCallbacks, fn)
end

function SpectateController:EndSpectate()
	if not self._active then return end

	self._active = false

	-- Clear slide FOV effect so spectator returns to normal FOV
	pcall(function()
		FOVController:RemoveEffect("Slide")
	end)

	self:_exitEmoteView()
	self:_unbindRenderLoop()
	self:_showTargetRig()
	self:_destroySpectateViewmodel()
	self:_disconnectHealthWatcher()

	self._targetUserId = nil
	self._specWasSliding = false
	self._specCurrentCrouchOffset = 0
	self._targetList = {}
	self._targetIndex = 0

	-- Unregister spectate on server
	pcall(function()
		self._net:FireServer("SpectateRegister", 0)
	end)

	for _, fn in self._onEndCallbacks do
		task.defer(fn)
	end
end

function SpectateController:CycleTarget(direction)
	if not self._active then return end
	if #self._targetList <= 1 then return end

	self:_exitEmoteView()
	self:_showTargetRig()
	self:_destroySpectateViewmodel()
	self:_disconnectHealthWatcher()

	local alive = self:_refreshTargetList()
	if #alive == 0 then
		self:EndSpectate()
		return
	end

	self._targetList = alive
	self._targetIndex = self._targetIndex + direction
	if self._targetIndex < 1 then
		self._targetIndex = #alive
	elseif self._targetIndex > #alive then
		self._targetIndex = 1
	end
	self._targetUserId = alive[self._targetIndex]

	self:_buildSpectateViewmodel()
	self:_hideTargetRig()
	self:_connectHealthWatcher()

	-- Update server registration to new target
	pcall(function()
		self._net:FireServer("SpectateRegister", self._targetUserId)
	end)

	return self._targetUserId
end

-- =============================================================================
-- HEALTH WATCHING
-- =============================================================================

function SpectateController:_connectHealthWatcher()
	self:_disconnectHealthWatcher()

	local targetPlayer = getPlayerByUserId(self._targetUserId)
	if not targetPlayer then return end

	-- Switch the HUD health bar to track the spectated player
	local hud = self:_getHUD()
	if hud and hud.setSpectateTarget then
		pcall(function() hud:setSpectateTarget(targetPlayer) end)
	end

	-- Seed the last-health cache so we can detect damage direction
	self._specLastHealth = targetPlayer:GetAttribute("Health")

	-- Update the damage vignette whenever the spectated player's health changes
	self._spectateHealthConn = targetPlayer:GetAttributeChangedSignal("Health"):Connect(function()
		local health = targetPlayer:GetAttribute("Health") or 0
		local maxHealth = targetPlayer:GetAttribute("MaxHealth") or 100
		local damagedOverlay = self:_getDamagedOverlay()
		if damagedOverlay then
			if type(self._specLastHealth) == "number" and health < self._specLastHealth then
				pcall(function() damagedOverlay:onDamageTaken(self._specLastHealth - health) end)
			end
			pcall(function() damagedOverlay:setHealthState(health, maxHealth) end)
		end
		self._specLastHealth = health
	end)
end

function SpectateController:_disconnectHealthWatcher()
	if self._spectateHealthConn then
		self._spectateHealthConn:Disconnect()
		self._spectateHealthConn = nil
	end
	self._specLastHealth = nil

	-- Restore HUD to local player
	local hud = self:_getHUD()
	if hud and hud.clearSpectateTarget then
		pcall(function() hud:clearSpectateTarget() end)
	end

	-- Restore vignette to local player's cached health
	local damagedOverlay = self:_getDamagedOverlay()
	if damagedOverlay and damagedOverlay.setHealthState then
		local h = self._cachedLocalHealth or 100
		local m = self._cachedLocalMaxHealth or 100
		pcall(function() damagedOverlay:setHealthState(h, m) end)
	end
end

-- =============================================================================
-- EMOTE 3RD PERSON VIEW
-- =============================================================================

function SpectateController:_onEmoteReplicate(playerId, action)
	if not self._active then return end
	if playerId ~= self._targetUserId then return end
	if action == "play" then
		self:_enterEmoteView()
	elseif action == "stop" then
		self:_exitEmoteView()
	end
end

function SpectateController:_enterEmoteView()
	if self._spectateEmoteMode then return end
	self._spectateEmoteMode = true

	-- Hide the first-person viewmodel
	if self._spectateVmLoadout and self._spectateActiveSlot then
		local rig = self._spectateVmLoadout.Rigs[self._spectateActiveSlot]
		if rig and rig.Model then
			rig.Model.Parent = nil
		end
	end

	-- Show the target's full rig so the emote animation is visible
	self:_showTargetRig()

	-- Bind orbit camera
	pcall(function()
		RunService:UnbindFromRenderStep("SpectateEmoteCamera")
	end)
	RunService:BindToRenderStep("SpectateEmoteCamera", Enum.RenderPriority.Camera.Value + 12, function()
		self:_renderEmoteCamera()
	end)
	self._emoteRenderConn = true
end

function SpectateController:_exitEmoteView()
	if not self._spectateEmoteMode then return end
	self._spectateEmoteMode = false

	-- Unbind orbit camera
	if self._emoteRenderConn then
		pcall(function()
			RunService:UnbindFromRenderStep("SpectateEmoteCamera")
		end)
		self._emoteRenderConn = nil
	end

	-- Hide the rig again and restore the viewmodel
	self:_hideTargetRig()
	if self._spectateVmLoadout and self._spectateActiveSlot then
		local rig = self._spectateVmLoadout.Rigs[self._spectateActiveSlot]
		if rig and rig.Model then
			rig.Model.Parent = workspace.CurrentCamera
		end
	end
end

function SpectateController:_renderEmoteCamera()
	if not self._active or not self._targetUserId then return end

	-- Position camera behind and above the target's head
	local head = getHumanoidHead(self._targetUserId) or getRigHead(self._targetUserId)
	if not head then return end

	local camera = workspace.CurrentCamera
	if not camera then return end

	-- Orbit: 10 studs back, 4 up from head — gives a clean over-the-shoulder view
	local lookTarget = head.Position + Vector3.new(0, 1.5, 0)
	local camPos = lookTarget + Vector3.new(0, 3, 9)
	camera.CFrame = CFrame.lookAt(camPos, lookTarget)
end

function SpectateController:_buildTargetList(killerUserId)
	local myId = LocalPlayer and LocalPlayer.UserId
	if not myId then return {} end

	local teamSize = self._myTeam and #self._myTeam or 1

	if teamSize == 1 then
		if killerUserId and killerUserId ~= myId and isPlayerAlive(killerUserId) then
			return { killerUserId }
		end
		return {}
	end

	local teammates = {}
	if self._myTeam then
		for _, uid in self._myTeam do
			if uid ~= myId and isPlayerAlive(uid) then
				table.insert(teammates, uid)
			end
		end
	end

	if #teammates == 0 then
		return {}
	end

	return teammates
end

function SpectateController:_refreshTargetList()
	local fresh = {}
	for _, uid in self._targetList do
		if isPlayerAlive(uid) then
			table.insert(fresh, uid)
		end
	end
	return fresh
end

function SpectateController:_hideTargetRig()
	if not self._targetUserId then return end
	local player = getPlayerByUserId(self._targetUserId)
	if not player or not player.Character then return end
	local rig = CharacterLocations:GetRig(player.Character)
	if not rig then return end

	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end
end

function SpectateController:_showTargetRig()
	if not self._targetUserId then return end
	local player = getPlayerByUserId(self._targetUserId)
	if not player or not player.Character then return end
	local rig = CharacterLocations:GetRig(player.Character)
	if not rig then return end

	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 0
		end
	end
end

function SpectateController:_buildSpectateViewmodel()
	self:_destroySpectateViewmodel()

	local targetPlayer = getPlayerByUserId(self._targetUserId)
	if not targetPlayer then return end

	local loadoutRaw = targetPlayer:GetAttribute("SelectedLoadout")
	if type(loadoutRaw) ~= "string" or loadoutRaw == "" then return end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(loadoutRaw)
	end)
	if not ok or type(decoded) ~= "table" then return end

	local loadoutData = decoded.loadout or decoded

	local vmLoadout = CreateLoadout.create(loadoutData, targetPlayer)
	if not vmLoadout or not vmLoadout.Rigs then return end

	self._spectateVmLoadout = vmLoadout

	self._spectateWeaponIds = {
		Primary = loadoutData.Primary or "",
		Secondary = loadoutData.Secondary or "",
		Melee = loadoutData.Melee or "",
		Fists = "Fists",
	}

	self._vmSprings = {
		rotation = Spring.new(Vector3.zero),
		bob = Spring.new(Vector3.zero),
		tiltRot = Spring.new(Vector3.zero),
		tiltPos = Spring.new(Vector3.zero),
	}
	self._vmSprings.rotation.Speed = ROTATION_SPRING_SPEED
	self._vmSprings.rotation.Damper = ROTATION_SPRING_DAMPER
	self._vmSprings.bob.Speed = BOB_SPRING_SPEED
	self._vmSprings.bob.Damper = BOB_SPRING_DAMPER
	self._vmSprings.tiltRot.Speed = TILT_SPRING_SPEED
	self._vmSprings.tiltRot.Damper = TILT_SPRING_DAMPER
	self._vmSprings.tiltPos.Speed = TILT_SPRING_SPEED
	self._vmSprings.tiltPos.Damper = TILT_SPRING_DAMPER
	self._prevSpecCamCF = nil
	self._vmBobT = 0
	self._lastSpecTargetPos = nil

	local activeSlot = targetPlayer:GetAttribute("EquippedSlot") or "Primary"
	self._spectateActiveSlot = activeSlot

	local rig = vmLoadout.Rigs[activeSlot] or vmLoadout.Rigs.Fists
	if not rig then return end

	if rig.Model then
		rig.Model.Parent = workspace.CurrentCamera
	end

	self:_bindAnimator(rig, self._spectateWeaponIds[activeSlot] or "Fists")

	local rep = getRemoteReplicator()
	if rep then
		local activeState = rep.ActiveViewmodelState[self._targetUserId]
		if activeState then
			for _, payload in pairs(activeState) do
				self:_applyVmAction(payload)
			end
		end
	end
end

function SpectateController:_bindAnimator(rig, weaponId)
	if self._spectateAnimator then
		self._spectateAnimator:Unbind()
	end

	local animator = ViewmodelAnimator.new()
	animator:BindRig(rig, weaponId)

	-- Disconnect the built-in movement loop; it reads LocalPlayer velocity
	-- which is zero/ragdoll during spectate. We drive movement from remote data.
	if animator._conn then
		animator._conn:Disconnect()
		animator._conn = nil
	end

	self._spectateAnimator = animator
	self._specMoveState = "Idle"
end

function SpectateController:_destroySpectateViewmodel()
	if self._spectateAnimator then
		self._spectateAnimator:Unbind()
		self._spectateAnimator = nil
	end

	if self._spectateVmLoadout then
		for _, rig in pairs(self._spectateVmLoadout.Rigs) do
			if rig and rig.Model then
				rig.Model.Parent = nil
			end
			if rig and rig.Destroy then
				rig:Destroy()
			end
		end
		self._spectateVmLoadout = nil
	end

	self._vmSprings = nil
	self._prevSpecCamCF = nil
	self._vmBobT = 0
	self._spectateActiveSlot = nil
	self._spectateWeaponIds = nil
	self._specMoveState = nil
	self._lastSpecTargetPos = nil
end

function SpectateController:_onViewmodelActionReplicated(compressedPayload)
	if not self._active then return end

	local payload = CompressionUtils:DecompressViewmodelAction(compressedPayload)
	if not payload then return end

	local userId = tonumber(payload.PlayerUserId)
	if userId ~= self._targetUserId then return end

	self:_applyVmAction(payload)
end

function SpectateController:_playSpectateKitAnim(trackName)
	local animator = self._spectateAnimator
	if not animator or not animator._rig or not animator._rig.Animator then return end

	local track = animator._kitTracks and animator._kitTracks[trackName]
	if not track then
		-- Ensure kit animations are loaded (ViewmodelController may not have run for a dead spectator)
		ViewmodelAnimator.PreloadKitAnimations()
		local animInstance = ViewmodelAnimator.GetKitAnimation(trackName)
		if not animInstance then return end
		local animId = animInstance.AnimationId
		if type(animId) ~= "string" or animId == "" or animId == "rbxassetid://0" then return end

		local ok, loaded = pcall(function()
			return animator._rig.Animator:LoadAnimation(animInstance)
		end)
		if not ok or not loaded then return end

		local priorityAttr = animInstance:GetAttribute("Priority")
		if type(priorityAttr) == "string" and Enum.AnimationPriority[priorityAttr] then
			loaded.Priority = Enum.AnimationPriority[priorityAttr]
		elseif typeof(priorityAttr) == "EnumItem" then
			loaded.Priority = priorityAttr
		else
			loaded.Priority = Enum.AnimationPriority.Action4
		end

		local loopAttr = animInstance:GetAttribute("Loop") or animInstance:GetAttribute("Looped")
		loaded.Looped = (type(loopAttr) == "boolean" and loopAttr) or false

		animator._kitTracks[trackName] = loaded
		track = loaded
	end

	if track.IsPlaying then track:Stop(0) end

	local fadeTime = 0.1
	local speed = 1
	local weight = 1
	local animInstance = ViewmodelAnimator.GetKitAnimation(trackName)
	if animInstance then
		local fadeAttr = animInstance:GetAttribute("FadeInTime") or animInstance:GetAttribute("FadeTime")
		if type(fadeAttr) == "number" then fadeTime = fadeAttr end
		local speedAttr = animInstance:GetAttribute("Speed")
		if type(speedAttr) == "number" then speed = speedAttr end
		local weightAttr = animInstance:GetAttribute("Weight")
		if type(weightAttr) == "number" then weight = weightAttr end
	end

	track:Play(fadeTime, weight, speed)
end

function SpectateController:_stopSpectateKitAnim(trackName)
	local animator = self._spectateAnimator
	if not animator then return end
	local track = animator._kitTracks and animator._kitTracks[trackName]
	if track and track.IsPlaying then
		track:Stop(0.1)
	end
end

function SpectateController:_applyVmAction(payload)
	if not self._spectateVmLoadout then return end

	local weaponId = tostring(payload.WeaponId or "")
	local actionName = tostring(payload.ActionName or "")
	local trackName = tostring(payload.TrackName or "")
	local isActive = payload.IsActive == true

	if actionName == "Unequip" then
		if self._spectateAnimator then
			self._spectateAnimator:Unbind()
		end
		for _, rig in pairs(self._spectateVmLoadout.Rigs) do
			if rig and rig.Model then
				rig.Model.Parent = nil
			end
		end
		self._spectateActiveSlot = nil
		return
	end

	local slotForWeapon = self:_resolveSlotForWeapon(weaponId)
	if slotForWeapon and slotForWeapon ~= self._spectateActiveSlot then
		if self._spectateActiveSlot then
			local oldRig = self._spectateVmLoadout.Rigs[self._spectateActiveSlot]
			if oldRig and oldRig.Model then
				oldRig.Model.Parent = nil
			end
		end

		self._spectateActiveSlot = slotForWeapon
		local newRig = self._spectateVmLoadout.Rigs[slotForWeapon]
		if newRig and newRig.Model then
			newRig.Model.Parent = workspace.CurrentCamera
		end

		if newRig then
			local newWeaponId = self._spectateWeaponIds[slotForWeapon] or weaponId or "Fists"
			self:_bindAnimator(newRig, newWeaponId)
		end
	end

	if not self._spectateAnimator then return end

	if actionName == "PlayWeaponTrack" or actionName == "PlayAnimation" then
		-- Movement tracks are driven manually in _renderViewmodel; skip them here
		if trackName == "Idle" or trackName == "Walk" or trackName == "Run" then
			return
		end

		if isActive then
			local weaponTrack = self._spectateAnimator:GetTrack(trackName)
			if weaponTrack then
				self._spectateAnimator:Play(trackName, nil, true)
			else
				self:_playSpectateKitAnim(trackName)
			end
		else
			local weaponTrack = self._spectateAnimator:GetTrack(trackName)
			if weaponTrack then
				self._spectateAnimator:Stop(trackName)
			else
				self:_stopSpectateKitAnim(trackName)
			end
		end
	elseif actionName == "ADS" then
		if isActive then
			self._spectateAnimator:Play("ADS")
		else
			self._spectateAnimator:Stop("ADS")
		end
	elseif actionName == "Equip" then
		self._spectateAnimator:Play("Equip", nil, true)
	elseif actionName == "Special" then
		if isActive then
			local weaponTrack = self._spectateAnimator:GetTrack(trackName)
			if weaponTrack then
				self._spectateAnimator:Play(trackName, nil, true)
			end
		else
			local weaponTrack = self._spectateAnimator:GetTrack(trackName)
			if weaponTrack then
				self._spectateAnimator:Stop(trackName)
			end
		end
	elseif actionName == "Inspect" then
		local weaponTrack = self._spectateAnimator:GetTrack(trackName)
		if weaponTrack then
			self._spectateAnimator:Play(trackName, nil, true)
		end
	elseif actionName == "SetTrackSpeed" then
		local encodedTrack, encodedSpeed = string.match(trackName, "^(.+)|([%-%d%.]+)$")
		if encodedTrack and encodedTrack ~= "" then
			local speedValue = tonumber(encodedSpeed)
			if speedValue then
				local track = self._spectateAnimator:GetTrack(encodedTrack)
				if not track then
					track = self._spectateAnimator:GetKitTrack(encodedTrack)
				end
				if track then
					track:AdjustSpeed(speedValue)
				end
			end
		end
	end
end

function SpectateController:_resolveSlotForWeapon(weaponId)
	if not self._spectateVmLoadout or not self._spectateWeaponIds or weaponId == "" then
		return nil
	end
	for slotName, wId in pairs(self._spectateWeaponIds) do
		if wId == weaponId and self._spectateVmLoadout.Rigs[slotName] then
			return slotName
		end
	end
	if self._spectateVmLoadout.Rigs[weaponId] then
		return weaponId
	end
	return self._spectateActiveSlot
end

function SpectateController:_bindRenderLoop()
	if self._renderConn then return end

	pcall(function()
		RunService:UnbindFromRenderStep("SpectateCamera")
	end)
	RunService:BindToRenderStep("SpectateCamera", Enum.RenderPriority.Camera.Value + 11, function(dt)
		self:_renderCamera(dt)
	end)
	self._renderConn = true

	pcall(function()
		RunService:UnbindFromRenderStep("SpectateViewmodel")
	end)
	RunService:BindToRenderStep("SpectateViewmodel", Enum.RenderPriority.Camera.Value + 13, function(dt)
		self:_renderViewmodel(dt)
	end)
	self._vmRenderConn = true
end

function SpectateController:_unbindRenderLoop()
	if self._renderConn then
		pcall(function()
			RunService:UnbindFromRenderStep("SpectateCamera")
		end)
		self._renderConn = nil
	end

	if self._vmRenderConn then
		pcall(function()
			RunService:UnbindFromRenderStep("SpectateViewmodel")
		end)
		self._vmRenderConn = nil
	end
end

function SpectateController:_renderCamera(dt)
	if not self._active or not self._targetUserId then return end
	if self._spectateEmoteMode then return end -- emote orbit camera handles positioning

	-- End spectating once the local player has respawned (character alive, no ragdoll)
	if tick() - self._spectateStartTime > RESPAWN_CHECK_DELAY then
		local localChar = LocalPlayer and LocalPlayer.Character
		if localChar and localChar.Parent and localChar:GetAttribute("RagdollActive") ~= true then
			self:EndSpectate()
			return
		end
	end

	if not isPlayerAlive(self._targetUserId) then
		local alive = self:_refreshTargetList()
		if #alive > 0 then
			self:_showTargetRig()
			self:_destroySpectateViewmodel()
			self._targetList = alive
			self._targetIndex = math.clamp(self._targetIndex, 1, #alive)
			self._targetUserId = alive[self._targetIndex]
			self:_buildSpectateViewmodel()
			self:_hideTargetRig()
		else
			self:EndSpectate()
			return
		end
	end

	self:_hideTargetRig()

	-- Use humanoid Head (same as CameraController), fall back to rig Head
	local head = getHumanoidHead(self._targetUserId) or getRigHead(self._targetUserId)
	if not head then return end

	local remoteData = getRemoteData(self._targetUserId)
	if not remoteData then return end

	-- Compute speed for slide detection (FOV); _lastSpecTargetPos updated in _renderViewmodel
	local speed = 0
	if remoteData.SimulatedPosition and self._lastSpecTargetPos then
		local delta = remoteData.SimulatedPosition - self._lastSpecTargetPos
		speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / math.max(dt, 0.001)
	end

	-- Slide FOV boost (match SlidingSystem: FOVController:AddEffect("Slide") when sliding)
	local isSliding = remoteData.IsCrouching and speed > SLIDE_SPEED_THRESHOLD
	if isSliding and not self._specWasSliding then
		FOVController:AddEffect("Slide")
	elseif not isSliding and self._specWasSliding then
		FOVController:RemoveEffect("Slide")
	end
	self._specWasSliding = isSliding

	-- Replicate CameraController:UpdateFirstPersonCamera pipeline:
	-- Position at Head + FirstPerson.Offset, face character's horizontal direction, apply aim pitch
	local aimPitch = remoteData.LastAimPitch or 0

	local look = remoteData.LastCFrame and remoteData.LastCFrame.LookVector or Vector3.new(0, 0, -1)
	local flatForward = Vector3.new(look.X, 0, look.Z)
	if flatForward.Magnitude < 0.001 then
		flatForward = Vector3.new(0, 0, -1)
	end
	flatForward = flatForward.Unit

	-- Crouch/slide offset (match CameraController) with optional smoothing
	local crouchReduction = Config.Gameplay.Character.CrouchHeightReduction or 2
	local targetCrouchOffset = remoteData.IsCrouching and -crouchReduction or 0
	local cameraConfig = Config.Camera
	if cameraConfig.Smoothing and cameraConfig.Smoothing.EnableCrouchTransition then
		local speedVal = cameraConfig.Smoothing.CrouchTransitionSpeed or 12
		self._specCurrentCrouchOffset = lerp(
			self._specCurrentCrouchOffset,
			targetCrouchOffset,
			clamp(speedVal * dt, 0, 1)
		)
		if math.abs(self._specCurrentCrouchOffset - targetCrouchOffset) < 0.05 then
			self._specCurrentCrouchOffset = targetCrouchOffset
		end
	else
		self._specCurrentCrouchOffset = targetCrouchOffset
	end

	-- FP_OFFSET is purely vertical so world-space addition is identical to yaw-local-space
	local eyePos = head.Position + FP_OFFSET + Vector3.new(0, self._specCurrentCrouchOffset, 0)
	local cameraCF = CFrame.lookAt(eyePos, eyePos + flatForward)
		* CFrame.Angles(math.rad(aimPitch), 0, 0)

	local camera = workspace.CurrentCamera
	if camera then
		camera.CFrame = cameraCF
	end
end

function SpectateController:_renderViewmodel(dt)
	if not self._active then return end
	if self._spectateEmoteMode then return end -- rig is shown; no viewmodel during emote
	if not self._spectateVmLoadout or not self._spectateActiveSlot then return end

	local rig = self._spectateVmLoadout.Rigs[self._spectateActiveSlot]
	if not rig or not rig.Model then return end

	local cam = workspace.CurrentCamera
	if not cam then return end

	if rig.Model.Parent ~= cam then
		rig.Model.Parent = cam
	end

	-- BasePosition alignment (same as ViewmodelController)
	local basePosition = rig.Model:FindFirstChild("BasePosition", true)
	if not basePosition then return end

	local pivot = rig.Model:GetPivot()
	local hipOffset = pivot:ToObjectSpace(basePosition.WorldCFrame)
	local normalAlign = hipOffset:Inverse()

	-- Per-weapon config offset (same as ViewmodelController)
	local weaponId = self._spectateWeaponIds
		and self._spectateWeaponIds[self._spectateActiveSlot] or "Fists"
	local cfg = ViewmodelConfig.Weapons[weaponId] or ViewmodelConfig.Weapons.Fists
	local configOffset = (cfg and cfg.Offset) or CFrame.new()

	-- Compute remote player speed and velocity direction from position delta
	local remoteData = getRemoteData(self._targetUserId)
	local speed = 0
	local velocityDir = Vector3.new(0, 0, -1)
	if remoteData and remoteData.SimulatedPosition then
		local currentPos = remoteData.SimulatedPosition
		if self._lastSpecTargetPos then
			local delta = currentPos - self._lastSpecTargetPos
			local horizontal = Vector3.new(delta.X, 0, delta.Z)
			speed = horizontal.Magnitude / math.max(dt, 0.001)
			if horizontal.Magnitude > 0.01 then
				velocityDir = horizontal.Unit
			end
		end
		self._lastSpecTargetPos = currentPos
	end

	-- Drive movement animations from remote velocity
	if self._spectateAnimator then
		local isMoving = speed > MOVE_START_SPEED
			or (self._specMoveState ~= "Idle" and speed > MOVE_STOP_SPEED)

		local target = isMoving and "Walk" or "Idle"
		self._specMoveState = target

		for _, name in ipairs({ "Idle", "Walk", "Run" }) do
			local track = self._spectateAnimator:GetTrack(name)
			if track then
				if not track.IsPlaying then
					track:Play(0)
				end
				local weight = (name == target) and 1 or 0
				track:AdjustWeight(weight, 0.18)
			end
		end
	end

	-- Spring-based sway and bob (matching ViewmodelController)
	local springs = self._vmSprings
	if springs then
		if self._prevSpecCamCF then
			local diff = self._prevSpecCamCF:ToObjectSpace(cam.CFrame)
			local axis, angle = diff:ToAxisAngle()
			if angle == angle then
				springs.rotation:Impulse(axis * angle * ROTATION_SENSITIVITY)
			end
		end
		self._prevSpecCamCF = cam.CFrame

		if speed > 0.5 then
			local speedScale = math.clamp(speed / 12, 0.7, 1.7)
			self._vmBobT = self._vmBobT + dt * BOB_FREQ * speedScale
			springs.bob.Target = Vector3.new(
				math.sin(self._vmBobT) * BOB_AMP_X,
				math.sin(self._vmBobT * 2) * BOB_AMP_Y,
				0
			)
		else
			self._vmBobT = 0
			springs.bob.Target = Vector3.zero
		end

		-- Slide tilt/tuck (match ViewmodelController when target is sliding)
		local isSliding = remoteData and remoteData.IsCrouching and speed > SLIDE_SPEED_THRESHOLD
		if isSliding then
			local localDir = cam.CFrame:VectorToObjectSpace(velocityDir)
			local roll = -SLIDE_ROLL
			local pitch = -math.clamp(localDir.Z, -1, 1) * SLIDE_PITCH
			springs.tiltRot.Target = Vector3.new(pitch, SLIDE_YAW, roll)
			springs.tiltPos.Target = SLIDE_TUCK
		else
			springs.tiltRot.Target = Vector3.zero
			springs.tiltPos.Target = Vector3.zero
		end

		springs.rotation:TimeSkip(dt)
		springs.bob:TimeSkip(dt)
		springs.tiltRot:TimeSkip(dt)
		springs.tiltPos:TimeSkip(dt)
	end

	-- ViewmodelController applies rotation X and Z only (no Y), matching its pipeline
	local rotPos = springs and springs.rotation.Position or Vector3.zero
	local rotationCF = CFrame.Angles(rotPos.X, 0, rotPos.Z)
	local bobOffset = springs and springs.bob.Position or Vector3.zero
	local tiltRotPos = springs and springs.tiltRot and springs.tiltRot.Position or Vector3.zero
	local tiltPosPos = springs and springs.tiltPos and springs.tiltPos.Position or Vector3.zero
	local tiltRotOffset = CFrame.Angles(
		math.clamp(tiltRotPos.X, -SLIDE_PITCH, SLIDE_PITCH),
		math.clamp(tiltRotPos.Y, -math.abs(SLIDE_YAW), math.abs(SLIDE_YAW)),
		math.clamp(tiltRotPos.Z, -SLIDE_ROLL, SLIDE_ROLL)
	)
	local tiltPosOffset = tiltPosPos

	-- Final positioning: exact same order as ViewmodelController._render (with slide tilt/tuck)
	local target = cam.CFrame
		* normalAlign
		* configOffset
		* rotationCF
		* tiltRotOffset
		* CFrame.new(bobOffset + tiltPosOffset)

	rig.Model:PivotTo(target)
end

function SpectateController:GetTargetInfo()
	if not self._targetUserId then return nil end

	local player = getPlayerByUserId(self._targetUserId)
	if not player then return nil end

	return {
		userId = self._targetUserId,
		displayName = player.DisplayName or player.Name,
		userName = player.Name,
	}
end

function SpectateController:CanCycle()
	return self._active and #self._targetList > 1
end

return SpectateController
