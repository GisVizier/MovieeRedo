local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local HttpService = game:GetService("HttpService")

local Dialogue = require(ReplicatedStorage:WaitForChild("Dialogue"))
local DialogueConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DialogueConfig"))

local UIController = {}

UIController._registry = nil
UIController._net = nil
UIController._coreUi = nil
UIController._kitController = nil

local function safeCall(fn, ...)
	local args = table.pack(...)
	local ok, err = pcall(function()
		fn(table.unpack(args, 1, args.n))
	end)
	return ok, err
end

-- Preload all dialogue sounds for smoother playback
local function preloadDialogueSounds()
	local soundIds = {}
	
	-- Recursively collect all sound IDs from dialogue config
	local function collectSounds(tbl)
		if type(tbl) ~= "table" then return end
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

	-- Preload dialogue sounds in background
	preloadDialogueSounds()

	-- Lobby state flag (used by camera/emotes to block first person)
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", true)
	end

	-- Current match data
	self._currentMapId = nil

	self._net:ConnectClient("StartMatch", function(matchData)
		self:_onStartMatch(matchData)
	end)

	-- Round system events
	self._net:ConnectClient("ShowRoundLoadout", function(data)
		self:_onShowRoundLoadout(data)
	end)

	self._net:ConnectClient("RoundStart", function(data)
		self:_onRoundStart(data)
	end)

	self._net:ConnectClient("MatchEnd", function(data)
		self:_onMatchEnd(data)
	end)

	self._net:ConnectClient("ReturnToLobby", function(data)
		self:_onReturnToLobby(data)
	end)

	-- Training mode entry flow
	self._net:ConnectClient("ShowTrainingLoadout", function(data)
		self:_onShowTrainingLoadout(data)
	end)

	self._net:ConnectClient("TrainingLoadoutConfirmed", function(data)
		self:_onTrainingLoadoutConfirmed(data)
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

function UIController:Start() end

function UIController:_bootstrapUi()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:WaitForChild("Gui", 30)
	if not screenGui then
		warn("[UIController] Gui ScreenGui not found in PlayerGui")
		return
	end

	local CoreUI = require(ReplicatedStorage:WaitForChild("CoreUI"))
	local ui = CoreUI.new(screenGui)
	ui:init()
	self._coreUi = ui

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
	}) do
		local inst = ui:getUI(name)
		if inst and inst:IsA("GuiObject") then
			inst.Visible = false
		end
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
		local ServiceRegistry =
			require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("ServiceRegistry"))
		ServiceRegistry:RegisterController("Kit", kitController)
	end

	-- UI event wiring
	ui:on("EquipKitRequest", function(kitId)
		if self._kitController then
			self._kitController:requestEquipKit(kitId)
		end
	end)

	ui:on("LoadoutComplete", function(data)
		self:_onLoadoutComplete(data)
	end)

	-- Emote wheel input wiring
	self:_setupEmoteWheelInput(ui)

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

	local payload = {
		mapId = data.mapId or "ApexArena",
		gamemodeId = data.gamemodeId,
		loadout = loadout,
	}

	self._net:FireServer("SubmitLoadout", payload)
end

function UIController:_setupEmoteWheelInput(ui)
	local inputController = self._registry and self._registry:TryGet("Input")
	if not inputController then
		warn("[UIController] InputController not found, emote wheel input disabled")
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

	if not self._coreUi then
		return
	end

	-- Store map ID for round loadout
	if typeof(matchData) == "table" and matchData.mapId then
		self._currentMapId = matchData.mapId
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
end

function UIController:_onShowRoundLoadout(data)
	if not self._coreUi then
		return
	end

	-- Hide HUD temporarily
	safeCall(function()
		self._coreUi:hide("HUD")
	end)

	-- Set up loadout module with round data
	local loadoutModule = self._coreUi:getModule("Loadout")
	if loadoutModule and loadoutModule.setRoundData then
		local player = Players.LocalPlayer
		pcall(function()
			loadoutModule:setRoundData({
				players = { player.UserId },
				mapId = self._currentMapId or "ApexArena",
				gamemodeId = "Duel",
				timeStarted = os.clock(),
			})
		end)
	end

	-- Allow camera movement during loadout selection (Orbit mode)
	local cameraController = self._registry and self._registry:TryGet("Camera")
	if cameraController and type(cameraController.SetCameraMode) == "function" then
		cameraController:SetCameraMode("Orbit")
	end

	-- Show loadout UI
	safeCall(function()
		self._coreUi:show("Loadout", true)
	end)
end

function UIController:_onRoundStart(data)
	if not self._coreUi then
		return
	end

	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", false)
		player:SetAttribute("PlayerState", "InMatch")
	end

	-- Hide loadout if visible
	safeCall(function()
		self._coreUi:hide("Loadout")
	end)

	-- Show HUD
	safeCall(function()
		self._coreUi:show("HUD", true)
	end)

	-- Force first person camera for competitive match
	local cameraController = self._registry and self._registry:TryGet("Camera")
	if cameraController and type(cameraController.SetCameraMode) == "function" then
		cameraController:SetCameraMode("FirstPerson")
	end
end

function UIController:_onMatchEnd(data)
	if not self._coreUi then
		return
	end

	-- Could show victory/defeat screen here
	-- For now, just hide HUD
	safeCall(function()
		self._coreUi:hide("HUD")
	end)
end

function UIController:_onReturnToLobby(data)
	if not self._coreUi then
		return
	end

	-- Reset state
	self._currentMapId = nil

	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("InLobby", true)
		player:SetAttribute("PlayerState", "Lobby")
	end

	-- Hide all match UI
	safeCall(function()
		self._coreUi:hide("HUD")
	end)
	safeCall(function()
		self._coreUi:hide("Loadout")
	end)

	-- Force third person (Orbit) camera for lobby
	local cameraController = self._registry and self._registry:TryGet("Camera")
	if cameraController and type(cameraController.SetCameraMode) == "function" then
		cameraController:SetCameraMode("Orbit")
	end

	-- Lobby: No blocking UI - gameplay is enabled by default
end

-- Training mode entry: show loadout UI after teleporting to training area
function UIController:_onShowTrainingLoadout(data)
	if not self._coreUi then
		return
	end

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

	self._pendingTrainingAreaId = nil
end

return UIController
