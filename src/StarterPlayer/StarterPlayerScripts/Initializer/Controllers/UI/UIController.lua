local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

function UIController:Init(registry, net)
	self._registry = registry
	self._net = net

	-- Default: gameplay is gated until StartMatch from server.
	self:SetGameplayEnabled(false)

	self._net:ConnectClient("StartMatch", function(matchData)
		self:_onStartMatch(matchData)
	end)

	task.spawn(function()
		self:_bootstrapUi()
	end)
end

function UIController:Start() end

function UIController:SetGameplayEnabled(enabled: boolean)
	local inputController = self._registry and self._registry:TryGet("Input")
	if inputController and inputController.SetGameplayEnabled then
		inputController:SetGameplayEnabled(enabled)
	end

	local movementController = self._registry and self._registry:TryGet("Movement")
	if movementController and movementController.SetGameplayEnabled then
		movementController:SetGameplayEnabled(enabled)
	end

	local cameraController = self._registry and self._registry:TryGet("Camera")
	if cameraController and cameraController.SetGameplayEnabled then
		cameraController:SetGameplayEnabled(enabled)
	end
end

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
	for _, name in ipairs({ "Start", "Actions", "Catgory", "Kits", "Party", "Settings", "Map", "Loadout", "Black", "TallFade", "HUD", "Emotes", "Dialogue" }) do
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
		local ServiceRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("ServiceRegistry"))
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

	-- Initial UI: Loadout only (RojoUiReference testing flow).
	do
		local loadoutModule = ui:getModule("Loadout")
		if loadoutModule and loadoutModule.setRoundData then
			local userIds = {}
			for _, p in ipairs(Players:GetPlayers()) do
				table.insert(userIds, p.UserId)
			end

			pcall(function()
				loadoutModule:setRoundData({
					players = userIds,
					mapId = "ApexArena",
					gamemodeId = "Duels",
					timeStarted = os.clock(),
				})
			end)
		end
	end

	ui:show("Loadout", true)
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
	self:SetGameplayEnabled(true)

	if not self._coreUi then
		return
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

return UIController

