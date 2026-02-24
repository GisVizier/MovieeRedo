local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Dialogue = require(ReplicatedStorage:WaitForChild("Dialogue"))
local DialogueConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DialogueConfig"))
local ServiceRegistry =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("ServiceRegistry"))

local UIController = {}

UIController._registry = nil
UIController._net = nil
UIController._coreUi = nil
UIController._kitController = nil
UIController._stormData = nil
UIController._stormVisualActive = false
UIController._stormCameraCheckConnection = nil

local function updateDeathTemplateText(specClone: Instance, killerName: string?)
	-- Your template uses "PlayersName"
	local playersName = specClone:FindFirstChild("PlayersName", true)
	if playersName and playersName:IsA("TextLabel") then
		playersName.Text = killerName or playersName.Text
		return
	end

	for _, d in ipairs(specClone:GetDescendants()) do
		if d:IsA("TextLabel") then
			if killerName and killerName ~= "" then
				d.Text = killerName
			end
			return
		end
	end
end

local function playKilledSkull(screenGui: ScreenGui)
	-- Gui > KilledPlayer > Killed > (Bg, KillSkull, UIScale)
	local killedPlayer = screenGui:FindFirstChild("KilledPlayer", true)
	if not killedPlayer then
		return
	end

	local killed = killedPlayer:FindFirstChild("Killed", true)
	if not killed or not killed:IsA("GuiObject") then
		return
	end

	local skull = killed:FindFirstChild("KillSkull", true)
	local bg = killed:FindFirstChild("Bg", true)
	local uiScale = killed:FindFirstChildOfClass("UIScale") or killed:FindFirstChild("UIScale")

	-- Store original values once (before any animation runs)
	if skull and skull:IsA("ImageLabel") then
		skull:SetAttribute(
			"_origImageTransparency",
			skull:GetAttribute("_origImageTransparency") or skull.ImageTransparency
		)
	end
	if bg and bg:IsA("ImageLabel") then
		bg:SetAttribute("_origImageTransparency", bg:GetAttribute("_origImageTransparency") or bg.ImageTransparency)
	end
	if uiScale and uiScale:IsA("UIScale") then
		uiScale:SetAttribute("_origScale", uiScale:GetAttribute("_origScale") or uiScale.Scale)
	end

	-- Increment run ID so any stale task.delay from a previous call bails out
	local runId = (killed:GetAttribute("_skullRunId") or 0) + 1
	killed:SetAttribute("_skullRunId", runId)

	-- Reset to hidden start state
	if uiScale and uiScale:IsA("UIScale") then
		uiScale.Scale = 0.65
	end
	if skull and skull:IsA("ImageLabel") then
		skull.ImageTransparency = 1
	end
	if bg and bg:IsA("ImageLabel") then
		bg.ImageTransparency = 1
	end
	killed.Visible = true

	-- Pop + fade in
	local popInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local fadeInInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeOutInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local tweens = {}
	if uiScale and uiScale:IsA("UIScale") then
		table.insert(tweens, TweenService:Create(uiScale, popInfo, { Scale = uiScale:GetAttribute("_origScale") or 1 }))
	end
	if skull and skull:IsA("ImageLabel") then
		table.insert(
			tweens,
			TweenService:Create(
				skull,
				fadeInInfo,
				{ ImageTransparency = skull:GetAttribute("_origImageTransparency") or 0.29 }
			)
		)
	end
	if bg and bg:IsA("ImageLabel") then
		table.insert(
			tweens,
			TweenService:Create(
				bg,
				fadeInInfo,
				{ ImageTransparency = bg:GetAttribute("_origImageTransparency") or 0.79 }
			)
		)
	end
	for _, t in ipairs(tweens) do
		t:Play()
	end

	task.delay(1.05, function()
		-- A newer call started; let it own the animation
		if killed:GetAttribute("_skullRunId") ~= runId then
			return
		end
		if not killed.Parent then
			return
		end

		local outTweens = {}
		if uiScale and uiScale:IsA("UIScale") then
			table.insert(outTweens, TweenService:Create(uiScale, fadeOutInfo, { Scale = 0.85 }))
		end
		if skull and skull:IsA("ImageLabel") then
			table.insert(outTweens, TweenService:Create(skull, fadeOutInfo, { ImageTransparency = 1 }))
		end
		if bg and bg:IsA("ImageLabel") then
			table.insert(outTweens, TweenService:Create(bg, fadeOutInfo, { ImageTransparency = 1 }))
		end

		for _, t in ipairs(outTweens) do
			t:Play()
		end

		-- Hide the element once fully faded out
		local doneTween = outTweens[1] or outTweens[2] or outTweens[3]
		if doneTween then
			doneTween.Completed:Once(function()
				if killed:GetAttribute("_skullRunId") ~= runId then
					return
				end
				killed.Visible = false
			end)
		end
	end)
end

local function showPlayerDeathNotification(playerGui: PlayerGui, data)
	local screenGui = playerGui:FindFirstChild("Gui")
	if not screenGui then
		return
	end

	-- Exact hierarchy from Studio:
	-- Gui > KilledPlayer > PlayerDeath > Spec (template)
	local killedPlayer = screenGui:FindFirstChild("KilledPlayer", true)
	if not killedPlayer then
		return
	end

	local playerDeath = killedPlayer:FindFirstChild("PlayerDeath", true)
	if not playerDeath or not playerDeath:IsA("GuiObject") then
		return
	end

	local specTemplate = playerDeath:FindFirstChild("Spec", true)
	if not specTemplate or not specTemplate:IsA("GuiObject") then
		return
	end

	local spec = specTemplate:Clone()
	spec.Name = "Entry"
	spec.Visible = true
	spec.Parent = playerDeath

	local killerDisplay = (data and data.killerData and (data.killerData.displayName or data.killerData.userName))
		or (data and data.killerName)
		or "UNKNOWN"
	updateDeathTemplateText(spec, killerDisplay)

	-- Play skull animation alongside the entry (same UI system).
	pcall(function()
		playKilledSkull(screenGui)
	end)

	-- Animate like the existing setup expects: fade in/out via CanvasGroup transparency.
	-- "Fade up" comes from the UIListLayout stacking entries upward over time.
	if spec:IsA("CanvasGroup") then
		spec.GroupTransparency = 1
	end

	local fadeInInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeOutInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local fadeIn = TweenService:Create(spec, fadeInInfo, { GroupTransparency = 0 })
	fadeIn:Play()

	task.delay(1.25, function()
		if not spec.Parent then
			return
		end
		local fadeOut = TweenService:Create(spec, fadeOutInfo, { GroupTransparency = 1 })
		fadeOut:Play()
		fadeOut.Completed:Once(function()
			if spec and spec.Parent then
				spec:Destroy()
			end
		end)
	end)
end

local function safeCall(fn, ...)
	local args = table.pack(...)
	local ok, err = pcall(function()
		fn(table.unpack(args, 1, args.n))
	end)
	return ok, err
end

local function getHorizontalDistance(pos1: Vector3, pos2: Vector3): number
	local dx = pos1.X - pos2.X
	local dz = pos1.Z - pos2.Z
	return math.sqrt(dx * dx + dz * dz)
end

function UIController:_stopStormCameraCheckLoop()
	if self._stormCameraCheckConnection then
		self._stormCameraCheckConnection:Disconnect()
		self._stormCameraCheckConnection = nil
	end
end

function UIController:_isCameraInStormZone(): boolean
	if not self._stormData or self._stormData.active ~= true then
		return false
	end

	local center = self._stormData.center
	local radius = self._stormData.currentRadius or self._stormData.initialRadius
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" then
		return false
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local camPos = camera.CFrame.Position
	local dist = getHorizontalDistance(camPos, center)
	return dist > radius
end

function UIController:_syncStormVisualFromCamera()
	if not self._coreUi then
		return
	end

	local shouldShow = self:_isCameraInStormZone()
	if self._stormVisualActive == shouldShow then
		return
	end

	self._stormVisualActive = shouldShow
	if shouldShow then
		safeCall(function()
			self._coreUi:show("Storm")
		end)
	else
		safeCall(function()
			self._coreUi:hide("Storm")
		end)
	end
end

function UIController:_startStormCameraCheckLoop()
	self:_stopStormCameraCheckLoop()

	self._stormCameraCheckConnection = RunService.RenderStepped:Connect(function()
		if not self._stormData or self._stormData.active ~= true then
			return
		end
		self:_syncStormVisualFromCamera()
	end)
end

-- Preload all dialogue sounds for smoother playback
local function preloadDialogueSounds()
	local soundIds = {}

	-- Recursively collect all sound IDs from dialogue config
	local function collectSounds(tbl)
		if type(tbl) ~= "table" then
			return
		end
		for key, value in pairs(tbl) do
			if key == "SoundInstance" and value then
				if type(value) == "number" then
					table.insert(soundIds, "rbxassetid://" .. tostring(value))
				elseif type(value) == "string" and string.match(value, "^rbxassetid://") then
					table.insert(soundIds, value)
				end
			elseif type(value) == "table" then
				collectSounds(value)
			end
		end
	end

	collectSounds(DialogueConfig.Dialogues)

	-- Preload all collected sounds
	if #soundIds > 0 then
		task.spawn(function()
			local assets = {}
			for _, id in ipairs(soundIds) do
				local sound = Instance.new("Sound")
				sound.SoundId = id
				table.insert(assets, sound)
			end
			pcall(function()
				ContentProvider:PreloadAsync(assets)
			end)
			-- Clean up temporary sound instances
			for _, sound in ipairs(assets) do
				sound:Destroy()
			end
		end)
	end
end

function UIController:Init(registry, net)
	self._registry = registry
	self._net = net
	ServiceRegistry:RegisterController("UI", self)

	-- Preload dialogue sounds in background
	preloadDialogueSounds()

	-- Lobby state flag (used by camera/emotes to block first person)
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", true)
	end

	-- Current match data
	self._currentMapId = nil
	self._matchTeam1 = nil
	self._matchTeam2 = nil
	self._matchMode = nil

	self._net:ConnectClient("MatchStart", function(matchData)
		self:_onStartMatch(matchData)
	end)

	-- Round system events
	self._net:ConnectClient("ShowRoundLoadout", function(data)
		self:_onShowRoundLoadout(data)
	end)

	self._net:ConnectClient("RoundStart", function(data)
		self:_onRoundStart(data)
	end)

	self._net:ConnectClient("ScoreUpdate", function(data)
		self:_onScoreUpdate(data)
	end)

	-- Round outcome: show win/lose/draw animation
	self._net:ConnectClient("RoundOutcome", function(data)
		self:_onRoundOutcome(data)
	end)

	-- Round kill: mark dead player in HUD counter
	self._net:ConnectClient("RoundKill", function(data)
		if self._coreUi and data then
			pcall(function()
				self._coreUi:emit("RoundKill", data)
			end)
		end
	end)

	self._net:ConnectClient("MatchStatsUpdate", function(data)
		if self._coreUi and data then
			pcall(function()
				self._coreUi:emit("MatchStatsUpdate", data)
			end)
		end
	end)

	self._net:ConnectClient("MatchEnd", function(data)
		self:_onMatchEnd(data)
	end)

	self._net:ConnectClient("ReturnToLobby", function(data)
		self:_onReturnToLobby(data)
	end)

	-- Map selection (competitive)
	self._net:ConnectClient("ShowMapSelection", function(data)
		self:_onShowMapSelection(data)
	end)

	self._net:ConnectClient("MapVoteUpdate", function(data)
		self:_onMapVoteUpdate(data)
	end)

	self._net:ConnectClient("MapVoteResult", function(data)
		self:_onMapVoteResult(data)
	end)

	self._net:ConnectClient("BetweenRoundFreeze", function(data)
		self:_onBetweenRoundFreeze(data)
	end)

	-- Timer halving: when all players confirm loadout early, server halves the countdown.
	self._net:ConnectClient("LoadoutTimerHalved", function(data)
		self:_onLoadoutTimerHalved(data)
	end)

	-- All players ready - lock loadout and jump to 5 seconds
	self._net:ConnectClient("LoadoutLocked", function(data)
		self:_onLoadoutLocked(data)
	end)

	-- Storm system events
	self._net:ConnectClient("StormStart", function(data)
		self:_onStormStart(data)
	end)

	self._net:ConnectClient("StormEnter", function(data)
		self:_onStormEnter(data)
	end)

	self._net:ConnectClient("StormLeave", function(data)
		self:_onStormLeave(data)
	end)

	self._net:ConnectClient("StormSound", function(data)
		self:_onStormSound(data)
	end)

	self._net:ConnectClient("StormUpdate", function(data)
		self:_onStormUpdate(data)
	end)

	-- M key shortcut: confirm swap during between-round phase
	-- (same as clicking the swap button — opens the full loadout picker)
	self._betweenRounds = false
	self._betweenRoundEndTime = 0
	self._betweenRoundDuration = 10
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M and self._betweenRounds and self._coreUi then
			local loadoutModule = self._coreUi:getModule("Loadout")
			if loadoutModule and loadoutModule.confirmSwap then
				pcall(function() loadoutModule:confirmSwap() end)
			end
		end
	end)

	-- Party system events
	self._net:ConnectClient("PartyInviteReceived", function(data)
		if self._coreUi and data then
			pcall(function()
				self._coreUi:emit("PartyInviteReceived", data)
			end)
		end
	end)

	self._net:ConnectClient("PartyUpdate", function(data)
		if self._coreUi and data then
			pcall(function()
				self._coreUi:emit("PartyUpdate", data)
			end)
		end
	end)

	self._net:ConnectClient("PartyInviteBusy", function(data)
		if self._coreUi and data then
			pcall(function()
				self._coreUi:emit("PartyInviteBusy", data)
			end)
		end
	end)

	self._net:ConnectClient("PartyInviteDeclined", function(data)
		if self._coreUi and data then
			pcall(function()
				self._coreUi:emit("PartyInviteDeclined", data)
			end)
		end
	end)

	self._net:ConnectClient("PartyDisbanded", function(data)
		if self._coreUi and data then
			pcall(function()
				self._coreUi:emit("PartyDisbanded", data)
			end)
		end
	end)

	self._net:ConnectClient("PartyKicked", function(data)
		if self._coreUi and data then
			pcall(function()
				self._coreUi:emit("PartyKicked", data)
			end)
		end
	end)

	-- Training mode entry flow
	self._net:ConnectClient("ShowTrainingLoadout", function(data)
		self:_onShowTrainingLoadout(data)
	end)

	self._net:ConnectClient("TrainingLoadoutConfirmed", function(data)
		self:_onTrainingLoadoutConfirmed(data)
	end)

	self._net:ConnectClient("PlayerLeftMatch", function(data)
		if self._coreUi and data then
			pcall(function()
				self._coreUi:emit("PlayerLeftMatch", data)
			end)
		end
	end)

	self._net:ConnectClient("PlayerKilled", function(data)
		if self._coreUi then
			self._coreUi:emit("PlayerKilled", data)

			local localUserId = player and player.UserId

			-- Show KilledPlayer > PlayerDeath > Spec ONLY to the killer, with the victim's name
			if data and data.killerUserId == localUserId then
				local pg = player:FindFirstChild("PlayerGui")
				if pg then
					-- Resolve victim display name
					local victimDisplay = (
						data.victimData and (data.victimData.displayName or data.victimData.userName)
					)
						or (data.victimUserId and (function()
							local vp = Players:GetPlayerByUserId(data.victimUserId)
							return vp and (vp.DisplayName or vp.Name)
						end)())
						or "Unknown"
					pcall(function()
						showPlayerDeathNotification(pg, { killerName = victimDisplay })
					end)
				end
			end

			-- Show kill screen (who killed you) ONLY to the victim
			if data and data.victimUserId == localUserId then
				self:_showKillScreen(data)
			end
		end
	end)

	-- Listen for client-side trigger from AreaTeleport gadget
	if player then
		player:GetAttributeChangedSignal("_showTrainingLoadout"):Connect(function()
			local areaId = player:GetAttribute("_showTrainingLoadout")
			if areaId and areaId ~= "" then
				player:SetAttribute("_showTrainingLoadout", nil) -- Clear immediately
				self:_onShowTrainingLoadout({ areaId = areaId })
			end
		end)
	end

	task.spawn(function()
		self:_bootstrapUi()
	end)
end

function UIController:GetCoreUI()
	return self._coreUi
end

function UIController:Start() end

function UIController:_setupPlayerListData(ui)
	local coreUi = self._coreUi
	if not coreUi then
		return
	end

	local PlayerDataTable = require(ReplicatedStorage:WaitForChild("PlayerDataTable"))
	-- Ensure replica client is requested so we receive PeekableData
	PlayerDataTable.init()

	local ok, Replica = pcall(require, ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ReplicaClient"))
	if not ok or not Replica then
		return
	end

	local function buildPayload(replica)
		local userId = replica.Tags and replica.Tags.UserId
		if not userId or type(userId) ~= "number" then
			return nil
		end
		local data = replica.Data or {}
		local player = Players:GetPlayerByUserId(userId)
		local displayName = player and player.DisplayName or nil
		local username = player and player.Name or nil
		return {
			userId = userId,
			displayName = displayName,
			username = username,
			wins = type(data.WINS) == "number" and data.WINS or 0,
			streak = type(data.STREAK) == "number" and data.STREAK or 0,
			crowns = type(data.CROWNS) == "number" and data.CROWNS or 0,
		}
	end

	local function emitJoined(replica)
		local payload = buildPayload(replica)
		if payload then
			safeCall(function()
				coreUi:emit("PlayerList_PlayerJoined", payload)
			end)
		end
	end

	local function emitUpdated(replica)
		local payload = buildPayload(replica)
		if payload then
			safeCall(function()
				coreUi:emit("PlayerList_PlayerUpdated", payload)
			end)
		end
	end

	Replica.OnNew("PeekableData", function(replica)
		emitJoined(replica)
		replica:OnChange(function()
			emitUpdated(replica)
		end)
	end)
end

function UIController:_bootstrapUi()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("Gui", 30)
	if not screenGui then
		return
	end

	local CoreUI = require(ReplicatedStorage:WaitForChild("CoreUI"))
	local ui = CoreUI.new(screenGui)
	ui:init()
	self._coreUi = ui

	self:_setupPlayerListData(ui)

	-- Force-hide any UI that might be Visible by default in Studio.
	for _, name in ipairs({
		"Start",
		"Actions",
		"Catgory",
		"Kits",
		"Party",
		"Settings",
		"Map",
		"Loadout",
		"Black",
		"TallFade",
		"HUD",
		"Emotes",
		"Dialogue",
		"Spec",
	}) do
		local inst = ui:getUI(name)
		if inst and inst:IsA("GuiObject") then
			inst.Visible = false
		end
	end

	-- Spec arrow events
	ui:on("SpecArrowLeft", function()
		self:_onSpecCycle(-1)
	end)
	ui:on("SpecArrowRight", function()
		self:_onSpecCycle(1)
	end)

	-- Hide Spec/Kill UI whenever spectating ends (respawn, round start, etc.)
	local spectateController = self._registry and self._registry:TryGet("Spectate")
	if spectateController and spectateController.OnSpectateEnded then
		spectateController:OnSpectateEnded(function()
			if self._coreUi then
				safeCall(function()
					self._coreUi:hide("Spec")
				end)
				safeCall(function()
					self._coreUi:hide("Kill")
				end)
			end
		end)
	end

	-- Kit controller
	do
		local inputController = self._registry and self._registry:TryGet("Input")
		local KitController = require(ReplicatedStorage:WaitForChild("KitSystem"):WaitForChild("KitController"))
		local kitController = KitController.new(player, ui, self._net, inputController)
		kitController:init()
		self._kitController = kitController
		ui._kitController = kitController

		-- Register in ServiceRegistry so other systems can access it
		ServiceRegistry:RegisterController("Kit", kitController)
	end

	-- UI event wiring
	ui:on("EquipKitRequest", function(kitId)
		-- During between-rounds, don't equip the kit on the server
		-- (it would create the kit model on the character while waiting)
		-- The kit will be equipped when RoundStart fires via SubmitLoadout
		if self._betweenRounds then
			return
		end
		if self._kitController then
			self._kitController:requestEquipKit(kitId)
		end
	end)

	ui:on("LoadoutComplete", function(data)
		self:_onLoadoutComplete(data)
	end)

	-- Between-round: player pressed the swap button inside the Loadout module
	-- → switch to Orbit camera so they can see their character while picking
	ui:on("SwapLoadoutOpened", function()
		-- Switch to Orbit camera and unlock mouse for the picker
		local cameraController = self._registry and self._registry:TryGet("Camera")
		if cameraController and type(cameraController.SetCameraMode) == "function" then
			cameraController:SetCameraMode("Orbit")
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true

		-- NOW destroy weapons – the player has committed to swapping
		-- 1) Viewmodel (first-person arms/weapon rigs)
		local viewmodelController = self._registry and self._registry:TryGet("Viewmodel")
		if viewmodelController and viewmodelController.ClearLoadout then
			pcall(function() viewmodelController:ClearLoadout() end)
		end

		-- 2) WeaponController (weapon logic, crosshair, aim-assist)
		local weaponController = self._registry and self._registry:TryGet("Weapon")
		if weaponController then
			if type(weaponController._unequipCurrentWeapon) == "function" then
				pcall(function() weaponController:_unequipCurrentWeapon() end)
			end
			if type(weaponController.HideCrosshair) == "function" then
				pcall(function() weaponController:HideCrosshair() end)
			end
		end

		-- 3) Third-person weapon model on local rig
		local replicationController = self._registry and self._registry:TryGet("Replication")
		if replicationController and type(replicationController.ClearWeapons) == "function" then
			pcall(function() replicationController:ClearWeapons() end)
		end

		-- 4) Clear EquippedSlot so nothing re-equips from listeners
		local lp = Players.LocalPlayer
		if lp then
			lp:SetAttribute("EquippedSlot", nil)
		end
	end)

	-- Player has filled all 4 slots - notify server they're ready
	ui:on("LoadoutReady", function(data)
		self:_onLoadoutReady(data)
	end)

	-- Player changed weapons after already having 4 slots filled - re-submit loadout
	ui:on("LoadoutChanged", function(data)
		self:_onLoadoutChanged(data)
	end)

	-- NOTE: LoadoutWeaponChanged forwarding removed - Loadout's _export:emit already
	-- fires to CoreUI's global event system which HUD listens to directly.
	-- Forwarding here caused an infinite loop.

	-- Map module vote relay → server
	ui:on("MapVote", function(mapId)
		self._net:FireServer("SubmitMapVote", { mapId = mapId })
	end)

	ui:on("MapVoteComplete", function(selectedMapId)
		-- Server controls transition in competitive; this is informational only
	end)

	-- Party system relays (client → server)
	ui:on("PartyInviteSend", function(data)
		self._net:FireServer("PartyInviteSend", data)
	end)

	ui:on("PartyInviteResponse", function(data)
		self._net:FireServer("PartyInviteResponse", data)
	end)

	ui:on("PartyKick", function(data)
		self._net:FireServer("PartyKick", data)
	end)

	ui:on("PartyLeave", function()
		self._net:FireServer("PartyLeave")
	end)

	task.defer(function()
		self._net:FireServer("PartyRequestState")
	end)

	-- Emote wheel input wiring
	self:_setupEmoteWheelInput(ui)

	-- Kill screen hidden - restore HUD health/loadout bars
	ui:on("KillScreenHidden", function()
		local hudModule = self._coreUi:getModule("HUD")
		if hudModule and hudModule._showHealthAndLoadoutBars then
			pcall(function()
				hudModule:_showHealthAndLoadoutBars()
			end)
		end
	end)

	-- No UI shown on init - gameplay is enabled by default
end

function UIController:_onLoadoutComplete(data)
	if typeof(data) ~= "table" then
		return
	end

	local loadout = data.loadout
	if typeof(loadout) ~= "table" then
		return
	end

	-- During between-rounds, DON'T submit yet — _onRoundStart will submit
	-- the cached PlayerDataTable loadout.  Submitting now would set
	-- SelectedLoadout on the server, causing weapons to be created early.
	if self._betweenRounds then
		return
	end

	local payload = {
		mapId = data.mapId or "ApexArena",
		gamemodeId = data.gamemodeId,
		loadout = loadout,
	}

	self._net:FireServer("SubmitLoadout", payload)

	-- Loadout UI stays visible with "READY" text until the server fires RoundStart.
	-- _onRoundStart will hide Loadout, show HUD, and switch to FirstPerson camera.
end

function UIController:_onLoadoutReady(data)
	-- During between-rounds, don't submit — _onRoundStart handles it
	if self._betweenRounds then
		return
	end

	-- Player has filled all 4 slots - notify server they're ready AND submit loadout
	-- This ensures SelectedLoadout is set even if timer expires before LoadoutComplete
	if typeof(data) ~= "table" then
		return
	end

	local loadout = data.loadout
	if typeof(loadout) ~= "table" then
		return
	end

	local payload = {
		mapId = data.mapId or "ApexArena",
		gamemodeId = data.gamemodeId,
		loadout = loadout,
	}

	-- Fire both LoadoutReady (marks player as ready) and SubmitLoadout (sets SelectedLoadout)
	self._net:FireServer("LoadoutReady", payload)
	self._net:FireServer("SubmitLoadout", payload)
end

function UIController:_onLoadoutChanged(data)
	-- During between-rounds, don't submit — _onRoundStart handles it
	if self._betweenRounds then
		return
	end

	-- Player changed weapons after already having 4 slots filled - re-submit loadout
	if typeof(data) ~= "table" then
		return
	end

	local loadout = data.loadout
	if typeof(loadout) ~= "table" then
		return
	end

	local payload = {
		mapId = data.mapId or "ApexArena",
		gamemodeId = data.gamemodeId,
		loadout = loadout,
	}

	-- Just submit the updated loadout (player is already marked as ready)
	self._net:FireServer("SubmitLoadout", payload)
end

function UIController:_setupEmoteWheelInput(ui)
	local inputController = self._registry and self._registry:TryGet("Input")
	if not inputController then
		return
	end

	local emoteWheelOpen = false

	-- Helper to get current mode setting
	local function isHoldMode()
		local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
		local modeIndex = PlayerDataTable.get("Controls", "EmoteWheelMode")
		-- 1 = Hold, 2 = Toggle (default to Hold if not set)
		return modeIndex == nil or modeIndex == 1
	end

	inputController:ConnectToInput("Emotes", function(isPressed)
		local holdMode = isHoldMode()

		if isPressed then
			if not emoteWheelOpen then
				-- Open the wheel
				emoteWheelOpen = true
				ui:show("Emotes")
			elseif not holdMode then
				-- Toggle mode: pressing again closes without selecting
				emoteWheelOpen = false
				ui:hide("Emotes")
			end
		else
			-- Key released
			if emoteWheelOpen and holdMode then
				-- Hold mode: release selects the hovered emote
				local emotesModule = ui:getModule("Emotes")
				if emotesModule and emotesModule._activateHovered then
					emotesModule:_activateHovered()
				end
				-- Always hide on release in Hold mode (even if nothing was hovered)
				ui:hide("Emotes")
				emoteWheelOpen = false
			end
		end
	end)

	-- Listen for when emote is selected (closes wheel in both modes)
	ui:on("EmoteSelected", function()
		emoteWheelOpen = false
	end)
end

function UIController:_onStartMatch(matchData)
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", false)
	end

	self:_stopSpectate()

	if not self._coreUi then
		return
	end

	-- Store match data for spectating and round loadout
	if typeof(matchData) == "table" then
		if matchData.mapId then
			self._currentMapId = matchData.mapId
		end
		self._matchTeam1 = matchData.team1
		self._matchTeam2 = matchData.team2
		self._matchMode = matchData.mode
	end

	-- Hide any lobby/map UI. We intentionally do NOT show HUD (Rojo UI test flow).
	safeCall(function()
		self._coreUi:hide("Start")
	end)
	safeCall(function()
		self._coreUi:hide("Map")
	end)
	safeCall(function()
		self._coreUi:hide("Loadout")
	end)

	-- Match start: show in-game HUD.
	safeCall(function()
		self._coreUi:show("HUD", true)
	end)

	-- Allow Map module to receive round data if you want to show it later
	local mapModule = self._coreUi:getModule("Map")
	if mapModule and mapModule.setRoundData and typeof(matchData) == "table" then
		pcall(function()
			mapModule:setRoundData(matchData)
		end)
	end

	-- Core module: match start (team data)
	pcall(function()
		self._coreUi:emit("MatchStart", matchData)
	end)
end

function UIController:_onShowRoundLoadout(data)
	if not self._coreUi then
		return
	end

	self:_stopSpectate()

	-- Hide HUD and Map (in case map selection was showing)
	safeCall(function()
		self._coreUi:hide("HUD")
	end)
	safeCall(function()
		self._coreUi:hide("Map")
	end)

	-- Set up loadout module with round data including server duration
	local loadoutModule = self._coreUi:getModule("Loadout")
	if loadoutModule then
		local player = Players.LocalPlayer
		if loadoutModule.setRoundData then
			pcall(function()
				loadoutModule:setRoundData({
					players = { player.UserId },
					mapId = self._currentMapId or "ApexArena",
					gamemodeId = "Duel",
					timeStarted = os.clock(),
					duration = data and data.duration or nil,
					roundNumber = data and data.roundNumber or nil,
				})
			end)
		end

		-- Orbit camera during loadout
		local cameraController = self._registry and self._registry:TryGet("Camera")
		if cameraController and type(cameraController.SetCameraMode) == "function" then
			cameraController:SetCameraMode("Orbit")
		end

		-- Explicitly unlock mouse for loadout selection (teleport may have locked it)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true

		-- Show loadout UI in ROUND 1 mode (ready checks enabled, can jump to 5s)
		pcall(function()
			loadoutModule:show({ isBetweenRound = false })
		end)
	end

	-- Notify HUD to hide health/loadout bars
	pcall(function()
		self._coreUi:emit("LoadoutOpened")
	end)
end

--------------------------------------------------------------------------------
-- MAP SELECTION (COMPETITIVE)
--------------------------------------------------------------------------------

function UIController:_onShowMapSelection(data)
	if not self._coreUi then
		return
	end

	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", false)
	end

	-- Hide lobby/other UI
	safeCall(function()
		self._coreUi:hide("Start")
	end)
	safeCall(function()
		self._coreUi:hide("HUD")
	end)
	safeCall(function()
		self._coreUi:hide("Loadout")
	end)

	-- Build team data for the Map module
	local teams = { team1 = data.team1 or {}, team2 = data.team2 or {} }
	local allPlayers = {}
	for _, uid in ipairs(teams.team1) do
		table.insert(allPlayers, uid)
	end
	for _, uid in ipairs(teams.team2) do
		table.insert(allPlayers, uid)
	end

	-- Configure the Map module
	local mapModule = self._coreUi:getModule("Map")
	if mapModule then
		if mapModule.setCompetitiveMode then
			mapModule:setCompetitiveMode(true)
		end
		if mapModule.setRoundData then
			pcall(function()
				mapModule:setRoundData({
					players = allPlayers,
					teams = teams,
					gamemodeId = "Duel",
					matchCreatedTime = os.time(),
					mapSelectionDuration = data.duration or 20,
				})
			end)
		end
	end

	self._currentMapId = nil

	-- Sky camera during map selection (random angle, high up)
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		local angle = math.random() * math.pi * 2
		local skyPos = Vector3.new(math.cos(angle) * 60, 180, math.sin(angle) * 60)
		camera.CFrame = CFrame.lookAt(skyPos, Vector3.new(0, 0, 0))
	end

	-- Explicitly unlock mouse for map selection UI (QueueController may not have run yet)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	safeCall(function()
		self._coreUi:show("Map", true)
	end)
end

function UIController:_onMapVoteUpdate(data)
	if not self._coreUi then
		return
	end

	local mapModule = self._coreUi:getModule("Map")
	if mapModule and data and data.oduserId and data.mapId then
		if mapModule.onRemoteVote then
			pcall(function()
				mapModule:onRemoteVote(data.oduserId, data.mapId)
			end)
		end
	end
end

function UIController:_onMapVoteResult(data)
	if not self._coreUi then
		return
	end

	local winningMapId = data and data.winningMapId or "ApexArena"
	self._currentMapId = winningMapId

	-- Hide Map UI — server will fire MatchTeleport + ShowRoundLoadout next
	safeCall(function()
		self._coreUi:hide("Map")
	end)

	-- Restore camera and mouse if player was in waiting room
	local player = game:GetService("Players").LocalPlayer
	if player:GetAttribute("InWaitingRoom") then
		player:SetAttribute("InWaitingRoom", nil)

		-- Restore camera to custom (first person)
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end

		-- Re-lock mouse for gameplay
		local UserInputService = game:GetService("UserInputService")
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end

function UIController:_onBetweenRoundFreeze(data)
	if not self._coreUi then
		return
	end

	-- Clean up storm visuals from previous round (clouds, mesh)
	self:_stopStormCameraCheckLoop()
	self._stormVisualActive = false
	self._stormData = nil
	local stormModule = self._coreUi:getModule("Storm")
	if stormModule then
		safeCall(function()
			if stormModule.destroyStormMesh then
				stormModule:destroyStormMesh()
			end
			if stormModule._restoreStormClouds then
				stormModule:_restoreStormClouds()
			end
		end)
	end
	safeCall(function()
		self._coreUi:hide("Storm")
	end)

	self._betweenRounds = true

	-- Track between-round timing
	local duration = (data and type(data.duration) == "number") and data.duration or 10
	self._betweenRoundDuration = duration
	self._betweenRoundEndTime = os.clock() + duration

	-- CLEAR HUD loadout slots (weapons, icons, etc.)
	local hudModule = self._coreUi:getModule("HUD")
	if hudModule and hudModule.ClearLoadoutSlots then
		pcall(function()
			hudModule:ClearLoadoutSlots()
		end)
	end

	-- Block weapon attacks while between rounds (server-side attribute).
	-- Weapons stay visually equipped; the ViewmodelController ignores
	-- attribute changes via BetweenRoundActive, so no new loadout spawns.
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		localPlayer:SetAttribute("AttackDisabled", true)
	end

	-- Tell HUD loadout is "open" (hides health/item bars, keeps score visible)
	pcall(function()
		self._coreUi:emit("LoadoutOpened")
	end)

	-- Show HUD so the score counter is visible during the between-round wait
	safeCall(function()
		self._coreUi:show("HUD", true)
	end)

	-- Push score update to HUD
	pcall(function()
		self._coreUi:emit("BetweenRoundFreeze", data)
	end)

	-- ----------------------------------------------------------------
	-- NEW BETWEEN-ROUND FLOW
	-- Show ONLY the countdown timer + "Swap Loadout" button.
	-- The full picker opens only when the player presses the swap button
	-- (or M key).  Camera stays at FirstPerson until confirmSwap fires
	-- SwapLoadoutOpened, which switches it to Orbit.
	-- ----------------------------------------------------------------
	local loadoutModule = self._coreUi:getModule("Loadout")
	if loadoutModule then
		local player = Players.LocalPlayer

		-- Cache the previous round's loadout so we can pre-populate slots
		local previousLoadout = nil
		local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
		local equipped = PlayerDataTable.getEquippedLoadout()
		if equipped and equipped.Kit then
			previousLoadout = equipped
		end

		-- Provide round data (duration, map, etc.) to the module
		pcall(function()
			loadoutModule:setRoundData({
				players = { player and player.UserId or 0 },
				mapId = self._currentMapId or "ApexArena",
				gamemodeId = "Duel",
				timeStarted = os.clock(),
				duration = duration,
			})
		end)

		-- Show in between-round mode: only timer + swap button are revealed
		pcall(function()
			loadoutModule:show({ isBetweenRound = true })
		end)

		-- Silently pre-populate slot state with the previous loadout so if the
		-- player never swaps, finishLoadout() re-submits the correct loadout.
		if previousLoadout and loadoutModule.prepopulateLoadout then
			task.defer(function()
				pcall(function()
					loadoutModule:prepopulateLoadout(previousLoadout)
				end)
			end)
		end
	end

	-- Unlock mouse immediately so the swap button is clickable
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	-- Deferred re-application: character/weapon controllers that process
	-- MatchFrozen on the same frame may re-lock the mouse.  We override them
	-- one frame later to guarantee the cursor is visible for the swap button.
	task.defer(function()
		if self._betweenRounds then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end)
end

function UIController:_onLoadoutTimerHalved(data)
	if not self._coreUi then
		return
	end
	if not data or type(data.remaining) ~= "number" then
		return
	end

	local loadoutModule = self._coreUi:getModule("Loadout")
	if loadoutModule and loadoutModule.halveTimer then
		pcall(function()
			loadoutModule:halveTimer(data.remaining)
		end)
	end
end

function UIController:_onLoadoutLocked(data)
	if not self._coreUi then
		return
	end

	local loadoutModule = self._coreUi:getModule("Loadout")
	if loadoutModule then
		-- IMMEDIATELY submit loadout to server when locked
		-- This ensures SelectedLoadout is set BEFORE the server's timer expires and fires RoundStart
		local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
		local loadoutData = PlayerDataTable.getEquippedLoadout()
		if loadoutData then
			local payload = {
				mapId = self._currentMapId or "ApexArena",
				gamemodeId = "Duel",
				loadout = loadoutData,
			}
			self._net:FireServer("SubmitLoadout", payload)
		end

		-- Lock the loadout UI (no more weapon changes)
		if loadoutModule.lockLoadout then
			pcall(function()
				loadoutModule:lockLoadout()
			end)
		end

		-- Jump timer to 5 seconds
		if loadoutModule.halveTimer and data and type(data.remaining) == "number" then
			pcall(function()
				loadoutModule:halveTimer(data.remaining)
			end)
		end
	end
end

function UIController:_onRoundStart(data)
	if not self._coreUi then
		return
	end

	self:_stopSpectate()

	local wasBetweenRound = self._betweenRounds
	self._betweenRounds = false

	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", false)
		player:SetAttribute("PlayerState", "InMatch")
		-- Clear between-round flags so weapons & attacks work normally again
		player:SetAttribute("BetweenRoundActive", nil)
		player:SetAttribute("AttackDisabled", nil)
	end

	-- Track whether the player actually clicked "Swap Loadout" during
	-- the between-round phase.  If they didn't, their weapons are still
	-- equipped and we can skip the destroy→recreate cycle entirely.
	local playerSwapped = false

	-- In between-round mode: make sure finishLoadout ran (fills empty slots),
	-- then submit the authoritative loadout to the server.
	if wasBetweenRound then
		local loadoutModule = self._coreUi:getModule("Loadout")

		-- Did the player actually open the loadout picker?
		playerSwapped = loadoutModule and loadoutModule._swapConfirmed == true

		-- If the timer already fired finishLoadout(), this is a no-op.
		-- If the player was still picking, this fills remaining empty slots.
		if loadoutModule and loadoutModule.finishLoadout then
			pcall(function()
				loadoutModule:finishLoadout()
			end)
		end

		-- Read the authoritative loadout built from _currentLoadout (not Replica)
		local loadoutData = loadoutModule and loadoutModule._finalLoadout
		if not loadoutData then
			-- Fallback: read from PlayerDataTable
			local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
			loadoutData = PlayerDataTable.getEquippedLoadout()
		end

		if loadoutData then
			local payload = {
				mapId = self._currentMapId or "ApexArena",
				gamemodeId = "Duel",
				loadout = loadoutData,
			}
			self._net:FireServer("SubmitLoadout", payload)
			-- Small delay to let server set the attribute
			task.wait(0.05)
		end
	end

	-- Hide loadout if visible - call directly on module since we showed it directly
	local loadoutModule = self._coreUi:getModule("Loadout")
	if loadoutModule and loadoutModule.hide then
		pcall(function()
			loadoutModule:hide()
		end)
	end
	-- Also try CoreUI hide in case it was opened via CoreUI
	safeCall(function()
		self._coreUi:hide("Loadout")
	end)
	-- Notify HUD to show health/loadout bars
	pcall(function()
		self._coreUi:emit("LoadoutClosed")
	end)

	-- Get the loadout to apply (prefer module's _finalLoadout over Replica)
	local hudLoadoutData = loadoutModule and loadoutModule._finalLoadout
	if not hudLoadoutData then
		local PlayerDataTable2 = require(ReplicatedStorage.PlayerDataTable)
		hudLoadoutData = PlayerDataTable2.getEquippedLoadout()
	end

	-- REBUILD HUD with fresh loadout (resets ult if kit changed)
	local hudModule = self._coreUi:getModule("HUD")
	if hudModule and hudModule.RebuildLoadoutSlots then
		pcall(function()
			hudModule:RebuildLoadoutSlots(hudLoadoutData)
		end)
	end

	-- Show HUD
	safeCall(function()
		self._coreUi:show("HUD", true)
	end)

	-- Force first person camera for competitive match
	local cameraController = self._registry and self._registry:TryGet("Camera")
	if cameraController and type(cameraController.SetCameraMode) == "function" then
		cameraController:SetCameraMode("FirstPerson")
	end

	-- Only destroy → recreate the viewmodel if the player actually swapped.
	-- If they didn't swap, their weapons were never destroyed, so we leave
	-- them alone (no flicker, no race-condition risk).
	if wasBetweenRound and playerSwapped then
		-- Create loadout from SelectedLoadout attribute (weapons were cleared when swap opened)
		local viewmodelController = self._registry and self._registry:TryGet("Viewmodel")
		if viewmodelController and viewmodelController.RefreshLoadoutFromAttributes then
			pcall(function()
				viewmodelController:RefreshLoadoutFromAttributes()
			end)
		end

		-- Refresh weapon controller to re-equip
		local weaponController = self._registry and self._registry:TryGet("Weapon")
		if weaponController and weaponController.OnRespawnRefresh then
			task.defer(function()
				pcall(function()
					weaponController:OnRespawnRefresh()
				end)
			end)
		end
	elseif not wasBetweenRound then
		-- Normal round-start (Round 1): the usual flow
		local viewmodelController = self._registry and self._registry:TryGet("Viewmodel")
		if viewmodelController and viewmodelController.RefreshLoadoutFromAttributes then
			pcall(function()
				viewmodelController:RefreshLoadoutFromAttributes()
			end)
		end

		local weaponController = self._registry and self._registry:TryGet("Weapon")
		if weaponController and weaponController.OnRespawnRefresh then
			task.defer(function()
				pcall(function()
					weaponController:OnRespawnRefresh()
				end)
			end)
		end
	end
	-- If wasBetweenRound and !playerSwapped: weapons are already equipped, do nothing.

	-- Show round start animation on HUD with round number
	local hudModule = self._coreUi:getModule("HUD")
	if hudModule and hudModule.RoundStart then
		local roundNumber = data and data.roundNumber or 1
		pcall(function()
			hudModule:RoundStart(roundNumber)
		end)
	end

	-- Core module: round number
	pcall(function()
		self._coreUi:emit("RoundStart", data)
	end)
end

function UIController:_onScoreUpdate(data)
	if not self._coreUi then
		return
	end

	-- Core module: team scores
	pcall(function()
		self._coreUi:emit("ScoreUpdate", data)
	end)
end

function UIController:_onRoundOutcome(data)
	if not self._coreUi then
		return
	end

	-- Get the HUD module and call RoundEnd with the outcome
	local hudModule = self._coreUi:getModule("HUD")
	if hudModule and hudModule.RoundEnd then
		local outcome = data and data.outcome or "draw"
		pcall(function()
			hudModule:RoundEnd(outcome)
		end)
	end

	-- Also emit to CoreUI in case other modules want to listen
	pcall(function()
		self._coreUi:emit("RoundOutcome", data)
	end)
end

function UIController:_onMatchEnd(data)
	if not self._coreUi then
		return
	end

	self:_stopSpectate()
	self._betweenRounds = false
	self:_stopStormCameraCheckLoop()
	self._stormVisualActive = false
	self._stormData = nil

	-- Hide all match UI
	safeCall(function()
		self._coreUi:hide("HUD")
	end)
	safeCall(function()
		self._coreUi:hide("Loadout")
	end)
	safeCall(function()
		self._coreUi:hide("Storm")
	end)

	-- Explicitly destroy storm mesh and restore clouds
	local stormModule = self._coreUi:getModule("Storm")
	if stormModule then
		safeCall(function()
			if stormModule.destroyStormMesh then
				stormModule:destroyStormMesh()
			end
			if stormModule._restoreStormClouds then
				stormModule:_restoreStormClouds()
			end
		end)
	end

	-- Hide crosshair
	local weaponController = self._registry and self._registry:TryGet("Weapon")
	if weaponController and type(weaponController.HideCrosshair) == "function" then
		weaponController:HideCrosshair()
	end
end

--------------------------------------------------------------------------------
-- STORM SYSTEM HANDLERS
--------------------------------------------------------------------------------

function UIController:_onStormStart(data)
	-- Emit to CoreUI for any listeners
	if self._coreUi then
		pcall(function()
			self._coreUi:emit("StormStart", data)
		end)

		-- Show "STORM INCOMING" announcement via HUD
		local hudModule = self._coreUi:getModule("HUD")
		if hudModule and hudModule.StormStarted then
			pcall(function()
				hudModule:StormStarted()
			end)
		end

		-- Create local storm mesh (client-side only)
		local stormModule = self._coreUi:getModule("Storm")
		if stormModule and stormModule.createStormMesh then
			pcall(function()
				stormModule:createStormMesh(data)
			end)
		end
	end

	-- Store storm data for UI updates and camera-based visual checks.
	self._stormData = {
		active = true,
		center = data.center,
		initialRadius = data.initialRadius,
		currentRadius = data.initialRadius,
		targetRadius = data.targetRadius,
		shrinkDuration = data.shrinkDuration,
	}

	self._stormVisualActive = false
	self:_startStormCameraCheckLoop()
	self:_syncStormVisualFromCamera()
end

function UIController:_onStormEnter(data)
	-- Character-based enter event is server-authoritative for damage only.
	-- Visuals are now camera-driven in _syncStormVisualFromCamera.
end

function UIController:_onStormLeave(data)
	-- Character-based leave event is server-authoritative for damage only.
	-- Visuals are now camera-driven in _syncStormVisualFromCamera.
end

function UIController:_onStormSound(data)
	if not self._coreUi then
		return
	end

	local stormModule = self._coreUi:getModule("Storm")
	if stormModule then
		if data.sound == "stormforming" and stormModule.playFormingSound then
			pcall(function()
				stormModule:playFormingSound()
			end)
		end
	end
end

function UIController:_onStormUpdate(data)
	if not self._coreUi then
		return
	end

	if self._stormData then
		self._stormData.currentRadius = data.currentRadius
	end

	-- Update the Storm UI with new radius info
	local stormModule = self._coreUi:getModule("Storm")
	if stormModule and stormModule.updateRadius and self._stormData then
		pcall(function()
			stormModule:updateRadius(data.currentRadius, self._stormData.targetRadius, self._stormData.initialRadius)
		end)
	end

	self:_syncStormVisualFromCamera()
end

function UIController:_showKillScreen(data)
	if not self._coreUi then
		return
	end

	local player = Players.LocalPlayer
	local killModule = self._coreUi:getModule("Kill")
	if not killModule then
		return
	end

	-- Build killer data for the Kill UI
	local killerUserId = data.killerUserId
	local isSelfKill = not killerUserId or killerUserId == player.UserId

	-- Get wins/streak - for self-kills use local data, for real kills use 0 (unknown)
	local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
	local wins = 0
	local streak = 0
	if isSelfKill then
		wins = PlayerDataTable.getData("WINS") or 0
		streak = PlayerDataTable.getData("STREAK") or 0
	end

	local killerInfo = {
		userId = isSelfKill and player.UserId or killerUserId,
		displayName = isSelfKill and player.DisplayName
			or (data.killerData and data.killerData.displayName or "Unknown"),
		userName = isSelfKill and player.Name or (data.killerData and data.killerData.userName or "unknown"),
		kitId = isSelfKill and nil or (data.killerData and data.killerData.kitId),
		weaponId = isSelfKill and nil or data.weaponId, -- Don't show weapon for self-kills
		wins = wins,
		streak = streak,
		health = isSelfKill and 0 or (data.killerData and data.killerData.health or 100),
		teamColor = Color3.fromRGB(255, 100, 100), -- Red team color for enemy
	}

	-- If self-kill, use blue team color
	if isSelfKill then
		killerInfo.teamColor = Color3.fromRGB(100, 150, 255)
	end

	-- Set killer data and show the Kill UI
	if killModule.setKillerData then
		pcall(function()
			killModule:setKillerData(killerInfo)
		end)
	end

	-- Hide HUD health/loadout bars but keep counter visible
	local hudModule = self._coreUi:getModule("HUD")
	if hudModule and hudModule._hideHealthAndLoadoutBars then
		pcall(function()
			hudModule:_hideHealthAndLoadoutBars()
		end)
	end

	-- Show Kill UI
	safeCall(function()
		self._coreUi:show("Kill", true)
	end)

	-- Start spectating
	self:_startSpectate(data.killerUserId)
end

function UIController:_startSpectate(killerUserId)
	local spectateController = self._registry and self._registry:TryGet("Spectate")
	if not spectateController then
		return
	end

	spectateController:BeginSpectate(killerUserId)

	if not spectateController:IsSpectating() then
		return
	end

	local specModule = self._coreUi and self._coreUi:getModule("Spec")
	if not specModule then
	else
		local info = spectateController:GetTargetInfo()
		if info then
			specModule:setTarget(info)
		end
		specModule:setArrowsVisible(spectateController:CanCycle())
		safeCall(function()
			self._coreUi:show("Spec", true)
		end)
	end
end

function UIController:_stopSpectate()
	local spectateController = self._registry and self._registry:TryGet("Spectate")
	if spectateController then
		spectateController:EndSpectate()
	end

	if self._coreUi then
		safeCall(function()
			self._coreUi:hide("Spec")
		end)
		safeCall(function()
			self._coreUi:hide("Kill")
		end)
	end
end

function UIController:_onSpecCycle(direction)
	local spectateController = self._registry and self._registry:TryGet("Spectate")
	if not spectateController or not spectateController:IsSpectating() then
		return
	end

	spectateController:CycleTarget(direction)

	local specModule = self._coreUi and self._coreUi:getModule("Spec")
	if not specModule then
		return
	end

	local info = spectateController:GetTargetInfo()
	if info then
		specModule:setTarget(info)
	end
end

function UIController:_onReturnToLobby(data)
	if not self._coreUi then
		return
	end

	-- Stop spectating
	self:_stopSpectate()

	-- Reset state
	self._currentMapId = nil
	self._matchTeam1 = nil
	self._matchTeam2 = nil
	self._matchMode = nil
	self._betweenRounds = false
	self:_stopStormCameraCheckLoop()
	self._stormVisualActive = false
	self._stormData = nil

	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", true)
		player:SetAttribute("PlayerState", "Lobby")
		player:SetAttribute("MatchFrozen", nil)
		player:SetAttribute("ExternalMoveMult", 1)
	end

	-- Hide all match UI
	safeCall(function()
		self._coreUi:hide("HUD")
	end)
	safeCall(function()
		self._coreUi:hide("Loadout")
	end)
	safeCall(function()
		self._coreUi:hide("Storm")
	end)

	-- Hide crosshair and restore mouse cursor for lobby
	local weaponController = self._registry and self._registry:TryGet("Weapon")
	if weaponController then
		if type(weaponController.HideCrosshair) == "function" then
			weaponController:HideCrosshair()
		end
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	-- Core module: cleanup thumbnails and restore PlayerList via proper methods
	pcall(function()
		self._coreUi:emit("ReturnToLobby")
	end)
	safeCall(function()
		local playerListModule = self._coreUi:getModule("PlayerList")
		if playerListModule and playerListModule.setMatchStatus then
			playerListModule:setMatchStatus("InLobby")
		end
		-- Force local player section update so "In Game" correctly changes to "In Lobby"
		if player then
			self._coreUi:emit("PlayerList_PlayerUpdated", {
				userId = player.UserId,
				displayName = player.DisplayName,
				username = player.Name,
				section = "InLobby",
			})
		end
	end)

	-- Force third person (Orbit) camera for lobby
	local cameraController = self._registry and self._registry:TryGet("Camera")
	if cameraController and type(cameraController.SetCameraMode) == "function" then
		cameraController:SetCameraMode("Orbit")
	end
end

-- Training mode entry: show loadout UI after teleporting to training area
function UIController:_onShowTrainingLoadout(data)
	if not self._coreUi then
		return
	end

	-- Hide player list when entering training (uses proper module methods)
	safeCall(function()
		self._coreUi:emit("TrainingStart")
	end)

	-- Store pending training entry area
	self._pendingTrainingAreaId = data and data.areaId or nil

	-- Set TrainingMode flag to unlock all weapons/kits in loadout UI
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("TrainingMode", true)
	end

	-- Set up loadout module with TrainingGrounds map
	local loadoutModule = self._coreUi:getModule("Loadout")
	if loadoutModule and loadoutModule.setRoundData then
		pcall(function()
			loadoutModule:setRoundData({
				players = { player.UserId },
				mapId = "TrainingGrounds",
				gamemodeId = "Training",
				timeStarted = os.clock(),
			})
		end)
	end

	-- Show loadout UI
	safeCall(function()
		self._coreUi:show("Loadout", true)
	end)
	-- Notify HUD to hide health/loadout bars
	pcall(function()
		self._coreUi:emit("LoadoutOpened")
	end)
end

-- Training mode entry confirmed: show HUD and force first person
function UIController:_onTrainingLoadoutConfirmed(data)
	if not self._coreUi then
		return
	end

	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", false)
		player:SetAttribute("PlayerState", "Training")
		player:SetAttribute("TrainingMode", nil) -- Clear training mode flag
	end

	-- Hide loadout UI
	safeCall(function()
		self._coreUi:hide("Loadout")
	end)
	-- Notify HUD to show health/loadout bars
	pcall(function()
		self._coreUi:emit("LoadoutClosed")
	end)

	-- Emit before show so HUD skips counter (top bar) in training ground
	self._coreUi:emit("TrainingHUDShow")

	-- Show HUD for training with correct data
	safeCall(function()
		self._coreUi:show("HUD", true)
	end)

	-- Update HUD with training round data
	local hudModule = self._coreUi:getModule("HUD")
	if hudModule and hudModule.setRoundData then
		pcall(function()
			hudModule:setRoundData({
				players = { player.UserId },
				mapId = "TrainingGrounds",
				gamemodeId = "Training",
				timeStarted = os.clock(),
			})
		end)
	end

	-- Play kit dialogue (RoundStart lines) for local player only
	if player then
		local selectedLoadout = player:GetAttribute("SelectedLoadout")
		if selectedLoadout then
			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(selectedLoadout)
			end)
			if ok and decoded and decoded.loadout and decoded.loadout.Kit then
				local kitId = decoded.loadout.Kit
				-- Small delay to let UI settle, then play random RoundStart dialogue
				task.delay(0.3, function()
					Dialogue.generate(kitId, "RoundStart", "Default")
				end)
			end
		end
	end

	-- Force first person camera for training
	local cameraController = self._registry and self._registry:TryGet("Camera")
	if cameraController and type(cameraController.SetCameraMode) == "function" then
		cameraController:SetCameraMode("FirstPerson")
	end

	-- Reset crosshair so it matches the newly selected loadout
	task.delay(0.2, function()
		local weaponController = self._registry and self._registry:TryGet("Weapon")
		if weaponController and type(weaponController.RefreshCrosshair) == "function" then
			weaponController:RefreshCrosshair()
		end
	end)

	self._pendingTrainingAreaId = nil
end

return UIController
