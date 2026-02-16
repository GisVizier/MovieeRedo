local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local LoadoutConfig = require(Configs.LoadoutConfig)
local KitsConfig = require(Configs.KitConfig)
local MapConfig = require(Configs.MapConfig)
local TweenConfig = require(script.TweenConfig)
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)

local module = {}
module.__index = module

local RoundData = {
	players = { 949024059, 9124290782, 1565898941, 204471960 },
	mapId = "ApexArena",
	gamemodeId = "TwoVTwo",
	timeStarted = os.clock(),
}

local SLOT_TYPES = { "Kit", "Primary", "Secondary", "Melee" }
local TIMER_DURATION = 30

local RARITY_TEMPLATE_MAP = {
	Common = "CommonItemPicker",
	Uncommon = "UncommonItemPicker",
	Rare = "RareItemPicker",
	Epic = "EpicItemPicker",
	Legendary = "LegendaryItemPicker",
	Mythic = "MythicItemPicker",
}

local ITEM_TEMPLATE_MAP = {
	Common = "CommonTemp",
	Uncommon = "UncommonTemp",
	Rare = "RareTemp",
	Epic = "EpicTemp",
	Legendary = "LegendaryTemp",
	Mythic = "MythicTemp",
}

local currentTweens = {}

local DEBUG = false
local REVIEW_DURATION = 2
local KIT_RARITY_ORDER = {
	Mythic = 1,
	Legendary = 2,
	Epic = 3,
	Rare = 4,
	Common = 5,
}

local function log(...)
	if not DEBUG then
		return
	end
end

local function getOwnedKits()
	local player = Players.LocalPlayer
	
	-- Training mode: unlock all kits
	if player and player:GetAttribute("TrainingMode") then
		local allKits = {}
		for kitId, _ in pairs(KitsConfig.Kits) do
			table.insert(allKits, kitId)
		end
		return allKits
	end
	
	local json = player and player:GetAttribute("OwnedKits")

	if type(json) == "string" and json ~= "" then
		local ok, list = pcall(function()
			return HttpService:JSONDecode(json)
		end)
		if ok and type(list) == "table" then
			return list
		end
	end

	return PlayerDataTable.getOwnedWeaponsByType("Kit")
end

local function isTrainingMode()
	local player = Players.LocalPlayer
	return player and player:GetAttribute("TrainingMode") == true
end

local function findFirstGuiButton(root)
	if not root then
		return nil
	end

	local direct = root:FindFirstChildWhichIsA("GuiButton", true)
	if direct then
		return direct
	end

	return nil
end

local function findSlotButton(slot)
	if not slot then
		return nil
	end

	local actions = slot:FindFirstChild("Actions")
	if actions then
		local actionButton = actions:FindFirstChild("Action") or actions:FindFirstChild("Button")
		if actionButton and actionButton:IsA("GuiButton") then
			return actionButton
		end
	end

	return findFirstGuiButton(slot)
end

local function ensureSlotButton(slot)
	local button = findSlotButton(slot)
	if button then
		return button
	end

	local fallback = Instance.new("ImageButton")
	fallback.Name = "SlotButton"
	fallback.AutoButtonColor = false
	fallback.BackgroundTransparency = 1
	fallback.Size = UDim2.fromScale(1, 1)
	fallback.Position = UDim2.fromScale(0, 0)
	fallback.ZIndex = 10
	fallback.Parent = slot

	return fallback
end

local function resolveTemplateByRarity(templatesFolder, rarity, explicitName, fallbackName)
	if not templatesFolder then
		return nil
	end

	if explicitName then
		local direct = templatesFolder:FindFirstChild(explicitName)
		if direct then
			return direct
		end
	end

	if rarity and rarity ~= "" then
		local rarityTemplate = templatesFolder:FindFirstChild(rarity .. "Temp")
		if rarityTemplate then
			return rarityTemplate
		end
	end

	if fallbackName then
		return templatesFolder:FindFirstChild(fallbackName)
	end

	return nil
end

local function resolvePickerByRarity(templatesFolder, rarity, explicitName, fallbackName)
	if not templatesFolder then
		return nil
	end

	if explicitName then
		local direct = templatesFolder:FindFirstChild(explicitName)
		if direct then
			return direct
		end
	end

	if rarity and rarity ~= "" then
		local rarityTemplate = templatesFolder:FindFirstChild(rarity .. "ItemPicker")
		if rarityTemplate then
			return rarityTemplate
		end
	end

	if fallbackName then
		return templatesFolder:FindFirstChild(fallbackName)
	end

	return nil
end

local function resolveSkinImage(weaponId, weaponData)
	if not weaponData or weaponData.isKit then
		return nil
	end

	local hasSkinApi = type(PlayerDataTable.getEquippedSkin) == "function"
		and type(PlayerDataTable.getOwnedSkins) == "function"
		and type(PlayerDataTable.isSkinOwned) == "function"

	local skinId = nil
	local ownedSkins = nil
	if hasSkinApi then
		skinId = PlayerDataTable.getEquippedSkin(weaponId)
		ownedSkins = PlayerDataTable.getOwnedSkins(weaponId)
	else
		log("skinApiMissing", weaponId)
		if type(PlayerDataTable.getData) == "function" then
			local equippedSkins = PlayerDataTable.getData("EQUIPPED_SKINS") or {}
			local ownedSkinsMap = PlayerDataTable.getData("OWNED_SKINS") or {}
			skinId = equippedSkins[weaponId]
			ownedSkins = ownedSkinsMap[weaponId] or {}
			log("skinApiFallback", weaponId, skinId, #ownedSkins)
		end
	end

	-- Only show skins that are explicitly equipped (no fallback to first owned)
	if not skinId or skinId == "" then
		log("skinSkipped", weaponId, "no equipped skin")
		return nil
	end

	if
		((hasSkinApi and PlayerDataTable.isSkinOwned(weaponId, skinId)) or (not hasSkinApi and table.find(
			ownedSkins or {},
			skinId
		)))
		and weaponData.skins
		and weaponData.skins[skinId]
		and weaponData.skins[skinId].imageId
	then
		log("skinApplied", weaponId, skinId, weaponData.skins[skinId].imageId)
		return weaponData.skins[skinId].imageId
	end

	log("skinSkipped", weaponId, skinId)
	return nil
end

local function getCanvasGroup(container)
	if not container then
		return nil
	end

	if container:IsA("CanvasGroup") then
		return container
	end

	local canvas = container:FindFirstChild("Canvas")
	if canvas and canvas:IsA("CanvasGroup") then
		return canvas
	end

	local direct = container:FindFirstChildWhichIsA("CanvasGroup")
	if direct then
		return direct
	end

	return nil
end

local function isVisible(instance)
	local current = instance
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

local function isGamepadInputType(inputType)
	return inputType == Enum.UserInputType.Gamepad1
		or inputType == Enum.UserInputType.Gamepad2
		or inputType == Enum.UserInputType.Gamepad3
		or inputType == Enum.UserInputType.Gamepad4
		or inputType == Enum.UserInputType.Gamepad5
		or inputType == Enum.UserInputType.Gamepad6
		or inputType == Enum.UserInputType.Gamepad7
		or inputType == Enum.UserInputType.Gamepad8
end

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections
	self._initialized = false

	self._mapName = ui:FindFirstChild("MapName")
	self._preview = ui:FindFirstChild("Preview")
	self._timer = ui:FindFirstChild("Timer")
	self._itemScroller = ui:FindFirstChild("ItemScroller")
	self._currentItems = ui:FindFirstChild("CurrentItems")

	self._slotTemplates = {}
	self._itemTemplates = {}
	self._gradientSpin = {}
	self._selectedSlot = "Kit"
	self._timerRunning = false
	self._loadoutFinished = false
	self._pendingSelectedItemId = nil
	self._gamepadInputsBound = false
	self._prevAutoSelectGuiEnabled = nil

	self._previewTemplates = nil
	self._itemScrollerTemplates = nil
	self._itemScrollerContainer = nil

	self._currentLoadout = {
		Kit = nil,
		Primary = nil,
		Secondary = nil,
		Melee = nil,
	}

	log("start", ui and ui.Name)

	return self
end

function module:_init()
	if self._initialized then
		return
	end

	self._initialized = true
	log("init")
	self:_setupMapName()
	self:_setupPreviewCharacter()
	self:_setupTemplateReferences()
	self:_setupCurrentItems()
	self:_setupNetworkListeners()
	self:_setupGamepadSlotCycling()
	self:_selectSlot(self._selectedSlot, true)
end

function module:_setupNetworkListeners() end

function module:_getInitialSelectedObject()
	local selectedSlotData = self._slotTemplates[self._selectedSlot]
	if selectedSlotData and selectedSlotData.template then
		local slotButton = findSlotButton(selectedSlotData.template)
		if slotButton and slotButton.Active and slotButton.Interactable then
			return slotButton
		end
	end

	for _, slotType in ipairs(SLOT_TYPES) do
		local slotData = self._slotTemplates[slotType]
		if slotData and slotData.template then
			local slotButton = findSlotButton(slotData.template)
			if slotButton and slotButton.Active and slotButton.Interactable then
				return slotButton
			end
		end
	end

	for _, itemData in self._itemTemplates do
		if itemData and itemData.template then
			local button = itemData.template:FindFirstChild("Button", true) or findFirstGuiButton(itemData.template)
			if button and button:IsA("GuiButton") and button.Active and button.Interactable then
				return button
			end
		end
	end

	return nil
end

function module:_setUINavActive(active)
	if not self._ui or not self._ui.Visible then
		return
	end

	local ok = pcall(function()
		GuiService.AutoSelectGuiEnabled = active
	end)
	if not ok then
		return
	end

	if active then
		local selected = GuiService.SelectedObject
		if not selected or not selected:IsDescendantOf(self._ui) then
			GuiService.SelectedObject = self:_getInitialSelectedObject()
		end
	else
		local selected = GuiService.SelectedObject
		if selected and self._ui and selected:IsDescendantOf(self._ui) then
			GuiService.SelectedObject = nil
		end
	end
end

function module:_startUINavInputWatcher()
	self._connections:cleanupGroup("loadout_uinav")
	self._connections:track(UserInputService, "LastInputTypeChanged", function(inputType)
		if not self._ui or not self._ui.Visible then
			return
		end
		self:_setUINavActive(isGamepadInputType(inputType))
	end, "loadout_uinav")
end


function module:_setupGamepadSlotCycling()
	if self._gamepadInputsBound then
		return
	end

	self._gamepadInputsBound = true

	self._connections:track(UserInputService, "InputBegan", function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if not self._ui or not self._ui.Visible or self._loadoutFinished then
			return
		end

		local inputType = input.UserInputType
		if inputType ~= Enum.UserInputType.Gamepad1
			and inputType ~= Enum.UserInputType.Gamepad2
			and inputType ~= Enum.UserInputType.Gamepad3
			and inputType ~= Enum.UserInputType.Gamepad4
		then
			return
		end

		if input.KeyCode == Enum.KeyCode.ButtonL1 then
			self:_cycleSlotSelection(-1)
		elseif input.KeyCode == Enum.KeyCode.ButtonR1 then
			self:_cycleSlotSelection(1)
		end
	end, "loadout_gamepad")
end

function module:_startGradientSpin(key, root)
	self:_stopGradientSpin(key)
	if not root then
		return
	end

	local gradients = {}
	for _, desc in root:GetDescendants() do
		if desc:IsA("UIGradient") then
			if #desc.Color.Keypoints > 2 then
				table.insert(gradients, desc)
			end
		end
	end

	if #gradients == 0 then
		log("gradientSpin", "no gradients", key)
		return
	end

	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not root or not root.Parent or not isVisible(root) then
			self:_stopGradientSpin(key)
			return
		end

		local delta = dt * 45
		for _, gradient in gradients do
			gradient.Rotation = (gradient.Rotation + delta) % 360
		end
	end)

	self._gradientSpin[key] = connection
end

function module:_stopGradientSpin(key)
	local connection = self._gradientSpin[key]
	if connection then
		connection:Disconnect()
		self._gradientSpin[key] = nil
	end
end

function module:_setupTemplateReferences()
	if self._currentItems then
		self._previewTemplates = self._currentItems:FindFirstChild("previewTemplates")
		if not self._previewTemplates then
		else
			log("previewTemplates", "ok")
		end
	else
	end

	if self._itemScroller then
		local inv = self._itemScroller:FindFirstChild("Inv")
		if inv then
			self._itemScrollerTemplates = inv:FindFirstChild("loayoutTemplates")
			self._itemScrollerContainer = inv
			if not self._itemScrollerTemplates then
			else
				log("itemScrollerTemplates", "ok")
			end
		else
		end
	else
	end
end

function module:fireLoadoutFinished(_loadoutData)
	-- TODO: Fire remote event to server with loadout results
	-- Example: RemoteEvent:FireServer("LoadoutFinished", _loadoutData)
end

function module:_getLocalPlayer()
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		return localPlayer.UserId
	end

	for _, player in Players:GetPlayers() do
		return player.UserId
	end

	return RoundData.players[1]
end

function module:_setupMapName()
	if not self._mapName then
		log("mapName", "missing")
		return
	end

	local mapData = MapConfig[RoundData.mapId]
	if not mapData then
		log("mapData", "missing", RoundData.mapId)
		return
	end

	local mapNameText = self._mapName:FindFirstChild("MapNameText")
	if mapNameText then
		mapNameText.Text = string.upper(mapData.name)
	else
		log("MapNameText", "missing")
	end
end

function module:_setupPreviewCharacter()
	if not self._preview then
		log("previewCharacter", "Preview missing")
		return
	end

	-- Preview might BE the ViewportFrame, or contain it
	local viewportFrame = self._preview
	if not viewportFrame:IsA("ViewportFrame") then
		viewportFrame = self._preview:FindFirstChild("ViewportFrame", true)
	end
	
	if not viewportFrame then
		log("previewCharacter", "ViewportFrame missing", self._preview.ClassName)
		return
	end

	-- WorldModel should be direct child of ViewportFrame
	local worldModel = viewportFrame:FindFirstChildOfClass("WorldModel")
	if not worldModel then
		worldModel = viewportFrame:FindFirstChild("WorldModel", true)
	end
	
	if not worldModel then
		log("previewCharacter", "WorldModel missing")
		return
	end

	local userModel = worldModel:FindFirstChild("User")
	if not userModel then
		log("previewCharacter", "User model missing")
		return
	end

	local humanoid = userModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		log("previewCharacter", "Humanoid missing")
		return
	end

	-- Get local player
	local player = Players.LocalPlayer
	if not player then
		log("previewCharacter", "LocalPlayer missing")
		return
	end

	-- Apply player's clothing and accessories to the existing User rig
	task.spawn(function()
		-- Find the player's rig in workspace.Rigs (created by RigManager with appearance applied)
		local Workspace = game:GetService("Workspace")
		local rigsFolder = Workspace:FindFirstChild("Rigs")
		
		if not rigsFolder then
			-- Wait for it to be created
			rigsFolder = Workspace:WaitForChild("Rigs", 5)
		end
		
		if not rigsFolder then
			log("previewCharacter", "Rigs folder not found in workspace")
			return
		end

		local rigName = player.Name .. "_Rig"
		local playerRig = rigsFolder:FindFirstChild(rigName)
		
		if not playerRig then
			-- Wait for rig to be created
			playerRig = rigsFolder:WaitForChild(rigName, 5)
		end
		
		if not playerRig then
			log("previewCharacter", "Player rig not found:", rigName)
			return
		end
		
		-- Wait for appearance to fully load on the rig
		task.wait(0.5)
		
		if not userModel.Parent then
			log("previewCharacter", "userModel no longer exists")
			return
		end

		log("previewCharacter", "Found player rig:", playerRig:GetFullName())

		-- Clone and apply Shirt
		local shirt = playerRig:FindFirstChildOfClass("Shirt")
		if shirt then
			local existingShirt = userModel:FindFirstChildOfClass("Shirt")
			if existingShirt then
				existingShirt:Destroy()
			end
			shirt:Clone().Parent = userModel
			log("previewCharacter", "Applied Shirt")
		end

		-- Clone and apply Pants
		local pants = playerRig:FindFirstChildOfClass("Pants")
		if pants then
			local existingPants = userModel:FindFirstChildOfClass("Pants")
			if existingPants then
				existingPants:Destroy()
			end
			pants:Clone().Parent = userModel
			log("previewCharacter", "Applied Pants")
		end

		-- Clone and apply BodyColors
		local bodyColors = playerRig:FindFirstChildOfClass("BodyColors")
		if bodyColors then
			local existingBC = userModel:FindFirstChildOfClass("BodyColors")
			if existingBC then
				existingBC:Destroy()
			end
			bodyColors:Clone().Parent = userModel
			log("previewCharacter", "Applied BodyColors")
		end

		-- Clone and apply accessories (hats, hair, face, etc)
		local accessoryCount = 0
		for _, accessory in playerRig:GetChildren() do
			if accessory:IsA("Accessory") then
				local clone = accessory:Clone()
				-- Remove any scripts from accessories
				for _, desc in clone:GetDescendants() do
					if desc:IsA("Script") or desc:IsA("LocalScript") then
						desc:Destroy()
					end
				end
				humanoid:AddAccessory(clone)
				accessoryCount = accessoryCount + 1
			end
		end

		log("previewCharacter", "✓ Applied appearance from workspace rig", player.Name, "accessories:", accessoryCount)
	end)
end

function module:_setupCurrentItems()
	if not self._currentItems then
		log("currentItems", "missing")
		return
	end

	local templateSource = self._currentItems:FindFirstChild("EmptySlotTemplate")
	if not templateSource then
		log("EmptySlotTemplate", "missing")
		return
	end

	for i, slotType in ipairs(SLOT_TYPES) do
		local slot = templateSource:Clone()
		slot.Name = "Slot_" .. slotType
		slot.Visible = true
		slot.LayoutOrder = i

		local uiScale = slot:FindFirstChild("UIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Name = "UIScale"
			uiScale.Parent = slot
		end

		local actions = slot:FindFirstChild("Actions")
		if actions then
			actions.GroupTransparency = 1
		end

		slot.Parent = self._currentItems

		self._slotTemplates[slotType] = {
			template = slot,
			slotType = slotType,
			index = i,
			selected = slotType == self._selectedSlot,
		}

		self:_setupSlotClick(slot, slotType)
		self:_setupSlotHover(slot, slotType)
		self:_updateSlotVisuals(slotType)
	end

	templateSource.Visible = false
end

function module:_setupSlotClick(slot, slotType)
	local button = ensureSlotButton(slot)
	if not button then
		log("slotButton", "missing", slotType)
		return
	end

	self._connections:track(button, "Activated", function()
		log("slotClick", slotType)
		self:_selectSlot(slotType, true)
	end, "slot_" .. slotType)
end

function module:_setupSlotHover(slot, slotType)
	local button = ensureSlotButton(slot)
	if not button then
		log("slotHoverButton", "missing", slotType)
		return
	end

	local groupName = "slotHover_" .. slotType
	local isHovering = false

	self._connections:track(button, "MouseEnter", function()
		if isHovering then
			return
		end
		isHovering = true

		self:_cancelTweens("slotHover_" .. slotType)
		local tweens = {}

		local uiScale = slot:FindFirstChild("UIScale")
		if uiScale then
			local tween = TweenService:Create(uiScale, TweenConfig.get("SlotTemplate", "hover"), {
				Scale = (self._selectedSlot == slotType) and 1.4 or 1.05,
			})
			tween:Play()
			table.insert(tweens, tween)
		else
			log("slotHover", "UIScale missing", slotType)
		end

		currentTweens["slotHover_" .. slotType] = tweens
	end, groupName)

	self._connections:track(button, "MouseLeave", function()
		if not isHovering then
			return
		end
		isHovering = false

		self:_cancelTweens("slotHover_" .. slotType)
		local tweens = {}

		local uiScale = slot:FindFirstChild("UIScale")
		if uiScale then
			local tween = TweenService:Create(uiScale, TweenConfig.get("SlotTemplate", "unhover"), {
				Scale = (self._selectedSlot == slotType) and 1.35 or 1,
			})
			tween:Play()
			table.insert(tweens, tween)
		end

		currentTweens["slotHover_" .. slotType] = tweens
	end, groupName)
end

function module:_selectSlot(slotType, force)
	if not slotType then
		log("selectSlot", "missing")
		return
	end

	if self._selectedSlot == slotType and not force then
		return
	end

	local previousSlot = self._selectedSlot
	self._selectedSlot = slotType
	log("selectSlot", slotType, "previous", previousSlot)

	for sType, slotData in self._slotTemplates do
		slotData.selected = sType == slotType
	end

	if previousSlot and previousSlot ~= slotType then
		self:_updateSlotVisuals(previousSlot)
	end
	self:_updateSlotVisuals(slotType)
	self:_populateItemScroller(slotType)
end

function module:_updateSlotVisuals(slotType)
	local slotData = self._slotTemplates[slotType]
	if not slotData then
		return
	end

	local slot = slotData.template
	local isSelected = slotData.selected

	self:_cancelTweens("slotSelect_" .. slotType)
	local tweens = {}

	local uiScale = slot:FindFirstChild("UIScale")
	if uiScale then
		local tween = TweenService:Create(uiScale, TweenConfig.get("SlotTemplate", "select"), {
			Scale = isSelected and 1.35 or 1,
		})
		tween:Play()
		table.insert(tweens, tween)
	end

	currentTweens["slotSelect_" .. slotType] = tweens
end

function module:_populateItemScroller(slotType)
	self:_clearItemTemplates()

	if not self._itemScrollerTemplates or not self._itemScrollerContainer then
		log("itemScroller", "templates missing", slotType)
		return
	end

	local weapons = {}
	if slotType == "Kit" then
		local ownedKits = getOwnedKits()
		for _, kitId in ipairs(ownedKits) do
			local kitData = KitsConfig.getKit(kitId)
			if kitData then
				table.insert(weapons, {
					id = kitId,
					data = {
						name = kitData.Name,
						imageId = kitData.Icon,
						rarity = kitData.Rarity,
						isKit = true,
					},
				})
			end
		end

		table.sort(weapons, function(a, b)
			local orderA = KIT_RARITY_ORDER[a.data.rarity] or 999
			local orderB = KIT_RARITY_ORDER[b.data.rarity] or 999
			if orderA == orderB then
				return a.data.name < b.data.name
			end
			return orderA < orderB
		end)
	else
		-- Training mode: unlock all weapons
		if isTrainingMode() then
			for _, weaponEntry in ipairs(LoadoutConfig.getWeaponsByType(slotType)) do
				table.insert(weapons, weaponEntry)
			end
		else
			local ownedWeapons = PlayerDataTable.getOwnedWeaponsByType(slotType)
			local ownedLookup = {}
			for _, weaponId in ipairs(ownedWeapons) do
				ownedLookup[weaponId] = true
			end

			for _, weaponEntry in ipairs(LoadoutConfig.getWeaponsByType(slotType)) do
				if ownedLookup[weaponEntry.id] then
					table.insert(weapons, weaponEntry)
				end
			end
		end
	end
	self._pendingSelectedItemId = self._currentLoadout[slotType]
	log("populateItemScroller", slotType, #weapons)

	if slotType ~= "Kit" then
		table.sort(weapons, function(a, b)
			local rarityA = LoadoutConfig.Rarities[a.data.rarity]
			local rarityB = LoadoutConfig.Rarities[b.data.rarity]
			local orderA = rarityA and rarityA.order or 999
			local orderB = rarityB and rarityB.order or 999
			if orderA == orderB then
				return a.data.name < b.data.name
			end
			return orderA < orderB
		end)
	end

	for i, weaponEntry in ipairs(weapons) do
		task.delay((i - 1) * TweenConfig.getDelay("ItemScrollerStagger"), function()
			self:_createItemTemplate(weaponEntry.id, weaponEntry.data, i)
		end)
	end
end

function module:_createItemTemplate(weaponId, weaponData, index)
	if not self._itemScrollerTemplates or not self._itemScrollerContainer then
		return
	end

	local skinImageId = resolveSkinImage(weaponId, weaponData)
	if skinImageId then
		weaponData = {
			name = weaponData.name,
			imageId = skinImageId,
			rarity = weaponData.rarity,
			isKit = false,
		}
	end

	local templateName = ITEM_TEMPLATE_MAP[weaponData.rarity] or "CommonTemp"
	local templateSource =
		resolveTemplateByRarity(self._itemScrollerTemplates, weaponData.rarity, templateName, "CommonTemp")
	if not templateSource then
		log("itemTemplate", "missing", templateName, weaponId)
		return
	end

	local item = templateSource:Clone()
	item.Name = "Item_" .. weaponId
	item.Visible = true
	item.LayoutOrder = index

	local uiScale = item:FindFirstChild("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "UIScale"
		uiScale.Parent = item
	end
	uiScale.Scale = 0

	item.Parent = self._itemScrollerContainer

	local imageLabel = item:FindFirstChild("ItemImage", true) or item:FindFirstChildWhichIsA("ImageLabel", true)
	if imageLabel and weaponData.imageId then
		imageLabel.Image = weaponData.imageId
	end

	local nameLabel = item:FindFirstChild("ItemNameText", true)
		or item:FindFirstChild("Name")
		or item:FindFirstChild("NameLabel")
	if nameLabel then
		nameLabel.Text = weaponData.name
	end

	local kitImage = item:FindFirstChild("KitImage", true)
	if kitImage then
		if weaponData.isKit then
			kitImage.Visible = true
			if weaponData.imageId then
				kitImage.Image = weaponData.imageId
			end
		else
			kitImage.Visible = false
		end
	end

	if imageLabel then
		if weaponData.isKit then
			imageLabel.Visible = false
		else
			imageLabel.Visible = true
		end
	end

	self._itemTemplates[weaponId] = {
		template = item,
		weaponId = weaponId,
		weaponData = weaponData,
		index = index,
	}

	self:_setupItemClick(item, weaponId)
	self:_setupItemHover(item, weaponId)
	self:_animateItemIn(item, weaponId)

	if weaponData.rarity == "Mythic" then
		self:_startGradientSpin("item_" .. weaponId, item)
	end

	if self._pendingSelectedItemId == weaponId then
		self:_updateItemSelectionVisuals(weaponId, true)
	end
end

function module:_animateItemIn(item, weaponId)
	local uiScale = item:FindFirstChild("UIScale")
	if not uiScale then
		return
	end

	self:_cancelTweens("itemShow_" .. weaponId)
	local tweens = {}

	local tween = TweenService:Create(uiScale, TweenConfig.get("ItemTemplate", "show"), {
		Scale = 1,
	})
	tween:Play()
	table.insert(tweens, tween)

	currentTweens["itemShow_" .. weaponId] = tweens
end

function module:_setupItemClick(item, weaponId)
	local button = item:FindFirstChild("Button", true) or findFirstGuiButton(item)
	if not button then
		log("itemButton", "missing", weaponId)
		return
	end

	self._connections:track(button, "Activated", function()
		log("itemClick", weaponId)
		self:_selectItem(weaponId)
	end, "item_" .. weaponId)
end

function module:_setupItemHover(item, weaponId)
	local button = item:FindFirstChild("Button", true) or findFirstGuiButton(item)
	if not button then
		log("itemHoverButton", "missing", weaponId)
		return
	end

	local groupName = "itemHover_" .. weaponId
	local isHovering = false

	self._connections:track(button, "MouseEnter", function()
		if isHovering then
			return
		end
		isHovering = true

		self:_cancelTweens("itemHover_" .. weaponId)
		local tweens = {}

		local uiScale = item:FindFirstChild("UIScale")
		if uiScale then
			local isSelected = self._currentLoadout[self._selectedSlot] == weaponId
			local tween = TweenService:Create(uiScale, TweenConfig.get("ItemTemplate", "hover"), {
				Scale = isSelected and 1.25 or 1.1,
			})
			tween:Play()
			table.insert(tweens, tween)
		else
			log("itemHover", "UIScale missing", weaponId)
		end

		currentTweens["itemHover_" .. weaponId] = tweens
	end, groupName)

	self._connections:track(button, "MouseLeave", function()
		if not isHovering then
			return
		end
		isHovering = false

		self:_cancelTweens("itemHover_" .. weaponId)
		local tweens = {}

		local uiScale = item:FindFirstChild("UIScale")
		if uiScale then
			local isSelected = self._currentLoadout[self._selectedSlot] == weaponId
			local tween = TweenService:Create(uiScale, TweenConfig.get("ItemTemplate", "unhover"), {
				Scale = isSelected and 1.2 or 1,
			})
			tween:Play()
			table.insert(tweens, tween)
		end

		currentTweens["itemHover_" .. weaponId] = tweens
	end, groupName)
end

function module:_updateItemSelectionVisuals(weaponId, isSelected)
	local itemData = self._itemTemplates[weaponId]
	if not itemData then
		return
	end

	self:_cancelTweens("itemSelect_" .. weaponId)
	local tweens = {}

	local uiScale = itemData.template:FindFirstChild("UIScale")
	if uiScale then
		local tween = TweenService:Create(uiScale, TweenConfig.get("ItemTemplate", "select"), {
			Scale = isSelected and 1.2 or 1,
		})
		tween:Play()
		table.insert(tweens, tween)
	else
		log("itemScale", "missing", weaponId)
	end

	currentTweens["itemSelect_" .. weaponId] = tweens
end

function module:_selectItem(weaponId)
	local weaponData = nil
	if self._selectedSlot == "Kit" then
		local kitData = KitsConfig.getKit(weaponId)
		if kitData then
			weaponData = {
				name = kitData.Name,
				imageId = kitData.Icon,
				rarity = kitData.Rarity,
				isKit = true,
			}
		end
	else
		weaponData = LoadoutConfig.getWeapon(weaponId)
	end
	if not weaponData then
		log("selectItem", "weapon missing", weaponId)
		return
	end

	local slotType = self._selectedSlot
	local previousWeaponId = self._currentLoadout[slotType]
	self._currentLoadout[slotType] = weaponId
	PlayerDataTable.setEquippedWeapon(slotType, weaponId)

	if slotType == "Kit" then
		self._export:emit("EquipKitRequest", weaponId)
	end

	if previousWeaponId and previousWeaponId ~= weaponId then
		self:_updateItemSelectionVisuals(previousWeaponId, false)
	end
	self:_updateItemSelectionVisuals(weaponId, true)

	self:_updateSlotWithWeapon(slotType, weaponId, weaponData)
	self:_checkLoadoutComplete()

	self:_advanceSlotSelection(slotType)
end

function module:_advanceSlotSelection(currentSlot)
	if self._loadoutFinished then
		return
	end

	local currentIndex = table.find(SLOT_TYPES, currentSlot)
	if not currentIndex then
		return
	end

	for i = currentIndex + 1, #SLOT_TYPES do
		local nextSlot = SLOT_TYPES[i]
		if not self._currentLoadout[nextSlot] then
			self:_selectSlot(nextSlot, true)
			return
		end
	end
end

function module:_cycleSlotSelection(direction)
	if self._loadoutFinished then
		return
	end

	local current = self._selectedSlot or SLOT_TYPES[1]
	local currentIndex = table.find(SLOT_TYPES, current) or 1
	local delta = (direction and direction >= 0) and 1 or -1
	local nextIndex = currentIndex + delta

	if nextIndex < 1 then
		nextIndex = #SLOT_TYPES
	elseif nextIndex > #SLOT_TYPES then
		nextIndex = 1
	end

	local nextSlot = SLOT_TYPES[nextIndex]
	if nextSlot then
		self:_selectSlot(nextSlot, true)
	end
end

function module:_updateSlotWithWeapon(slotType, weaponId, weaponData)
	local slotData = self._slotTemplates[slotType]
	if not slotData then
		log("updateSlot", "slot missing", slotType)
		return
	end

	local oldSlot = slotData.template

	if not self._previewTemplates then
		log("updateSlot", "previewTemplates missing", slotType)
		return
	end

	local slotSkinImageId = resolveSkinImage(weaponId, weaponData)
	if slotSkinImageId then
		weaponData = {
			name = weaponData.name,
			imageId = slotSkinImageId,
			rarity = weaponData.rarity,
			isKit = false,
		}
	end

	local templateName = RARITY_TEMPLATE_MAP[weaponData.rarity] or "CommonItemPicker"
	local templateSource =
		resolvePickerByRarity(self._previewTemplates, weaponData.rarity, templateName, "CommonItemPicker")
	if not templateSource then
		log("updateSlot", "template missing", templateName, slotType)
		return
	end

	self:_stopGradientSpin("slot_" .. slotType)

	local newSlot = templateSource:Clone()
	newSlot.Name = "Slot_" .. slotType
	newSlot.Visible = true
	newSlot.LayoutOrder = slotData.index

	local actions = newSlot:FindFirstChild("Actions")
	if actions then
		actions.GroupTransparency = 0
	end

	local imageLabel = newSlot:FindFirstChild("ItemImage", true) or newSlot:FindFirstChildWhichIsA("ImageLabel", true)
	if imageLabel and weaponData.imageId then
		imageLabel.Image = weaponData.imageId
	end

	local nameLabel = newSlot:FindFirstChild("ItemNameText", true)
		or newSlot:FindFirstChild("Name")
		or newSlot:FindFirstChild("NameLabel")
	if nameLabel then
		nameLabel.Text = weaponData.name
	end

	local kitImage = newSlot:FindFirstChild("KitImage", true)
	if kitImage then
		if weaponData.isKit then
			kitImage.Visible = true
			if weaponData.imageId then
				kitImage.Image = weaponData.imageId
			end
		else
			kitImage.Visible = false
		end
	end

	if imageLabel then
		if weaponData.isKit then
			imageLabel.Visible = false
		else
			imageLabel.Visible = true
		end
	end

	if weaponData.rarity == "Mythic" then
		self:_startGradientSpin("slot_" .. slotType, newSlot)
	end

	local uiScale = newSlot:FindFirstChild("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "UIScale"
		uiScale.Parent = newSlot
	end

	newSlot.Parent = self._currentItems

	self._connections:cleanupGroup("slot_" .. slotType)
	self._connections:cleanupGroup("slotHover_" .. slotType)

	oldSlot:Destroy()

	slotData.template = newSlot
	slotData.weaponId = weaponId

	self:_setupSlotClick(newSlot, slotType)
	self:_setupSlotHover(newSlot, slotType)
	self:_updateSlotVisuals(slotType)
end

function module:_checkLoadoutComplete()
	local filledCount = 0
	for _, weaponId in self._currentLoadout do
		if weaponId then
			filledCount = filledCount + 1
		end
	end

	log("loadoutCount", filledCount)
	if filledCount >= 4 then
		log("loadoutComplete")
		self:finishLoadout()
	end
end

function module:_cancelTweens(key)
	if currentTweens[key] then
		for _, tween in currentTweens[key] do
			tween:Cancel()
		end
		currentTweens[key] = nil
	end
end

function module:_animateShow()
	self:_cancelTweens("show")
	self:_cancelTweens("hide")

	local tweens = {}

	self._export:show("Black")
	log("animateShow")

	task.delay(TweenConfig.getDelay("MapName"), function()
		self:_showMapName(tweens)
	end)

	task.delay(TweenConfig.getDelay("Preview"), function()
		self:_showPreview(tweens)
	end)

	task.delay(TweenConfig.getDelay("CurrentItems"), function()
		self:_showCurrentItems(tweens)
	end)

	task.delay(TweenConfig.getDelay("Timer"), function()
		self:_showTimer(tweens)
	end)

	task.delay(TweenConfig.getDelay("ItemScroller"), function()
		self:_showItemScroller(tweens)
	end)

	currentTweens["show"] = tweens
end

function module:_showMapName(tweens)
	if not self._mapName then
		log("showMapName", "missing")
		return
	end

	local hiddenPos = TweenConfig.getPosition("MapName", "hidden")
	local shownPos = TweenConfig.getPosition("MapName", "shown")

	self._mapName.Position = hiddenPos
	if self._mapName:IsA("CanvasGroup") then
		self._mapName.GroupTransparency = 1
	end

	local posTween = TweenService:Create(self._mapName, TweenConfig.get("MapName", "show"), {
		Position = shownPos,
	})
	local fadeTween = TweenService:Create(self._mapName, TweenConfig.get("MapName", "fade"), {
		GroupTransparency = 0,
	})

	posTween:Play()
	fadeTween:Play()
	table.insert(tweens, posTween)
	table.insert(tweens, fadeTween)
end

function module:_showPreview(tweens)
	if not self._preview then
		log("showPreview", "missing")
		return
	end

	local canvas = getCanvasGroup(self._preview)

	local hiddenPos = TweenConfig.getPosition("Preview", "hidden")
	local shownPos = TweenConfig.getPosition("Preview", "shown")

	self._preview.Position = hiddenPos

	if canvas then
		canvas.GroupTransparency = 1
	end

	local posTween = TweenService:Create(self._preview, TweenConfig.get("Preview", "show"), {
		Position = shownPos,
	})
	posTween:Play()
	table.insert(tweens, posTween)

	if canvas then
		local fadeTween = TweenService:Create(canvas, TweenConfig.get("Preview", "fade"), {
			GroupTransparency = 0,
		})
		fadeTween:Play()
		table.insert(tweens, fadeTween)
	else
		log("preview", "CanvasGroup missing")
	end
end

function module:_showCurrentItems(tweens)
	if not self._currentItems then
		log("showCurrentItems", "missing")
		return
	end

	for i, slotType in ipairs(SLOT_TYPES) do
		local slotData = self._slotTemplates[slotType]
		if slotData then
			task.delay((i - 1) * TweenConfig.getDelay("CurrentItemsStagger"), function()
				self:_showSlot(slotData, tweens)
			end)
		end
	end
end

function module:_showSlot(slotData, tweens)
	local slot = slotData.template
	local actions = slot:FindFirstChild("Actions")

	if actions then
		actions.GroupTransparency = 1

		local fadeTween = TweenService:Create(actions, TweenConfig.get("SlotTemplate", "show"), {
			GroupTransparency = 0,
		})
		fadeTween:Play()
		table.insert(tweens, fadeTween)
	end
end

function module:_showTimer(tweens)
	if not self._timer then
		log("timer", "missing")
		return
	end

	local timerCanvas = getCanvasGroup(self._timer)
	local timerText = self._timer:FindFirstChild("TimerText")
	local procation = self._timer:FindFirstChild("Procation")

	if timerCanvas then
		timerCanvas.GroupTransparency = 1
		local fadeTween = TweenService:Create(timerCanvas, TweenConfig.get("Timer", "show"), {
			GroupTransparency = 0,
		})
		fadeTween:Play()
		table.insert(tweens, fadeTween)
	else
		log("timer", "CanvasGroup missing")
	end

	if timerText then
		timerText.TextTransparency = 1
		local textTween = TweenService:Create(timerText, TweenConfig.get("Timer", "show"), {
			TextTransparency = 0,
		})
		textTween:Play()
		table.insert(tweens, textTween)
	end

	if procation then
		procation.TextTransparency = 1
		local procationTween = TweenService:Create(procation, TweenConfig.get("Timer", "show"), {
			TextTransparency = 0,
		})
		procationTween:Play()
		table.insert(tweens, procationTween)
	end
end

function module:_showItemScroller(tweens)
	if not self._itemScroller then
		log("itemScroller", "missing")
		return
	end

	local canvas = getCanvasGroup(self._itemScroller)
	if not canvas then
		log("itemScroller", "CanvasGroup missing")
		return
	end

	canvas.GroupTransparency = 1
	local fadeTween = TweenService:Create(canvas, TweenConfig.get("ItemScroller", "show"), {
		GroupTransparency = 0,
	})
	fadeTween:Play()
	table.insert(tweens, fadeTween)
end

function module:_animateHide()
	self:_cancelTweens("show")
	self:_cancelTweens("hide")

	local tweens = {}

	log("animateHide")
	self:_hideMapName(tweens)
	self:_hidePreview(tweens)
	self:_hideCurrentItems(tweens)
	self:_hideTimer(tweens)
	self:_hideItemScroller(tweens)

	currentTweens["hide"] = tweens

	self._export:hide("Black")
end

function module:_hideMapName(tweens)
	if not self._mapName then
		log("hideMapName", "missing")
		return
	end

	local hiddenPos = TweenConfig.getPosition("MapName", "hidden")

	local posTween = TweenService:Create(self._mapName, TweenConfig.get("MapName", "hide"), {
		Position = hiddenPos,
	})
	local fadeTween = TweenService:Create(self._mapName, TweenConfig.get("MapName", "hide"), {
		GroupTransparency = 1,
	})

	posTween:Play()
	fadeTween:Play()
	table.insert(tweens, posTween)
	table.insert(tweens, fadeTween)
end

function module:_hidePreview(tweens)
	if not self._preview then
		log("hidePreview", "missing")
		return
	end

	local canvas = getCanvasGroup(self._preview)

	local hiddenPos = TweenConfig.getPosition("Preview", "hidden")

	local posTween = TweenService:Create(self._preview, TweenConfig.get("Preview", "hide"), {
		Position = hiddenPos,
	})
	posTween:Play()
	table.insert(tweens, posTween)

	if canvas then
		local fadeTween = TweenService:Create(canvas, TweenConfig.get("Preview", "hide"), {
			GroupTransparency = 1,
		})
		fadeTween:Play()
		table.insert(tweens, fadeTween)
	end
end

function module:_hideCurrentItems(tweens)
	if not self._currentItems then
		log("hideCurrentItems", "missing")
		return
	end

	for _, slotType in ipairs(SLOT_TYPES) do
		local slotData = self._slotTemplates[slotType]
		if slotData then
			local slot = slotData.template
			local actions = slot:FindFirstChild("Actions")

			if actions then
				local fadeTween = TweenService:Create(actions, TweenConfig.get("SlotTemplate", "hide"), {
					GroupTransparency = 1,
				})
				fadeTween:Play()
				table.insert(tweens, fadeTween)
			end
		end
	end
end

function module:_hideTimer(tweens)
	if not self._timer then
		log("hideTimer", "missing")
		return
	end

	local timerCanvas = getCanvasGroup(self._timer)
	if timerCanvas then
		local fadeTween = TweenService:Create(timerCanvas, TweenConfig.get("Timer", "hide"), {
			GroupTransparency = 1,
		})
		fadeTween:Play()
		table.insert(tweens, fadeTween)
	end

	local timerText = self._timer:FindFirstChild("TimerText")
	if timerText then
		local fadeTween = TweenService:Create(timerText, TweenConfig.get("Timer", "hide"), {
			TextTransparency = 1,
		})
		fadeTween:Play()
		table.insert(tweens, fadeTween)
	end

	local procation = self._timer:FindFirstChild("Procation")
	if procation then
		local fadeTween = TweenService:Create(procation, TweenConfig.get("Timer", "hide"), {
			TextTransparency = 1,
		})
		fadeTween:Play()
		table.insert(tweens, fadeTween)
	end
end

function module:_hideItemScroller(tweens)
	if self._itemScroller then
		local canvas = getCanvasGroup(self._itemScroller)
		if canvas then
			local fadeTween = TweenService:Create(canvas, TweenConfig.get("ItemScroller", "hide"), {
				GroupTransparency = 1,
			})
			fadeTween:Play()
			table.insert(tweens, fadeTween)
		else
			log("hideItemScroller", "CanvasGroup missing")
		end
	else
		log("hideItemScroller", "missing")
	end

	for _, itemData in self._itemTemplates do
		if itemData and itemData.template then
			local uiScale = itemData.template:FindFirstChild("UIScale")
			if uiScale then
				local tween = TweenService:Create(uiScale, TweenConfig.get("ItemTemplate", "hide"), {
					Scale = 0,
				})
				tween:Play()
				table.insert(tweens, tween)
			end
		end
	end
end

function module:startTimer()
	if self._timerRunning then
		return
	end
	self._timerRunning = true
	log("timerStart")

	task.spawn(function()
		local timerText = self._timer and self._timer:FindFirstChild("TimerText")
		local timerCanvas = self._timer and self._timer:FindFirstChild("Timer")

		local orangeBar = timerCanvas and timerCanvas:FindFirstChild("Frame")
		local whiteBar = timerCanvas and timerCanvas:FindFirstChild("White")

		local orangeOriginalSize = orangeBar and orangeBar.Size
		local whiteOriginalSize = whiteBar and whiteBar.Size

		local startTime = RoundData.timeStarted or os.clock()
		local endTime = startTime + TIMER_DURATION

		while self._initialized and self._timerRunning do
			local currentTime = os.clock()
			local timeLeft = endTime - currentTime

			if timeLeft < 0 then
				timeLeft = 0
			end

			local progress = timeLeft / TIMER_DURATION

			if timerText then
				timerText.Text = string.format("%.2fs", timeLeft)
			end

			if orangeBar and orangeOriginalSize then
				local orangeTween = TweenService:Create(orangeBar, TweenConfig.get("Timer", "progressBar"), {
					Size = UDim2.new(progress, 0, orangeOriginalSize.Y.Scale, orangeOriginalSize.Y.Offset),
				})
				orangeTween:Play()
			end

			if whiteBar and whiteOriginalSize then
				task.delay(TweenConfig.getDelay("TimerWhiteBar"), function()
					local whiteTween = TweenService:Create(whiteBar, TweenConfig.get("Timer", "whiteBar"), {
						Size = UDim2.new(progress, 0, whiteOriginalSize.Y.Scale, whiteOriginalSize.Y.Offset),
					})
					whiteTween:Play()
				end)
			end

			if timeLeft <= 0 then
				log("timerEnd")
				self:finishLoadout()
				break
			end

			task.wait(0.05)
		end

		self._timerRunning = false
	end)
end

function module:_fillEmptySlots()
	for _, slotType in ipairs(SLOT_TYPES) do
		if not self._currentLoadout[slotType] then
			local ownedWeapons = PlayerDataTable.getOwnedWeaponsByType(slotType)
			if #ownedWeapons > 0 then
				local firstWeapon = ownedWeapons[1]
				self._currentLoadout[slotType] = firstWeapon
				PlayerDataTable.setEquippedWeapon(slotType, firstWeapon)
				log("autoFilled", slotType, firstWeapon)
			end
		end
	end
end

function module:_setButtonsActive(active: boolean)
	-- Disable slot and item buttons when finished.
	for _, slotType in ipairs(SLOT_TYPES) do
		local slotData = self._slotTemplates[slotType]
		if slotData and slotData.template then
			local button = findSlotButton(slotData.template)
			if button and button:IsA("GuiButton") then
				button.Active = active
				button.Interactable = active
			end
		end
	end

	for weaponId, itemData in self._itemTemplates do
		if itemData and itemData.template then
			local button = itemData.template:FindFirstChild("Button", true) or findFirstGuiButton(itemData.template)
			if button and button:IsA("GuiButton") then
				button.Active = active
				button.Interactable = active
			end
		end
	end
end

function module:_showLoadoutReview()
	-- Stop timer + hide the scroller so you can review your picked slots.
	self._timerRunning = false

	if self._timer then
		local timerText = self._timer:FindFirstChild("TimerText")
		if timerText then
			timerText.Text = "READY"
		end
	end

	if self._itemScroller then
		local canvas = getCanvasGroup(self._itemScroller)
		if canvas then
			local tween = TweenService:Create(canvas, TweenConfig.get("ItemScroller", "hide"), {
				GroupTransparency = 1,
			})
			tween:Play()
			tween.Completed:Once(function()
				if self._loadoutFinished and self._itemScroller then
					self._itemScroller.Visible = false
				end
			end)
		else
			self._itemScroller.Visible = false
		end
	end

	self:_setButtonsActive(false)
end

function module:finishLoadout()
	if self._loadoutFinished then
		return
	end
	self._loadoutFinished = true
	log("finishLoadout")

	self:_fillEmptySlots()

	local loadoutData = PlayerDataTable.getEquippedLoadout()

	self:fireLoadoutFinished(loadoutData)
	self:_showLoadoutReview()

	self._export:emit("LoadoutComplete", {
		loadout = loadoutData,
		mapId = RoundData.mapId,
		gamemodeId = RoundData.gamemodeId,
	})

	-- After a short review moment, close the Loadout screen.
	task.delay(REVIEW_DURATION, function()
		if self._loadoutFinished and self._ui and self._ui.Parent then
			self._export:hide("Loadout")
		end
	end)
end

function module:setRoundData(data)
	if data.players then
		RoundData.players = data.players
	end

	if data.mapId then
		RoundData.mapId = data.mapId
	end

	if data.gamemodeId then
		RoundData.gamemodeId = data.gamemodeId
	end

	RoundData.timeStarted = data.timeStarted or os.clock()
end

function module:getRoundData()
	return RoundData
end

function module:_resetToOriginals()
	self._export:resetToOriginals("MapName")
	self._export:resetToOriginals("Preview")
	self._export:resetToOriginals("CurrentItems")
	self._export:resetToOriginals("Timer")
	self._export:resetToOriginals("ItemScroller")
end

function module:_clearSlotTemplates()
	for slotType, slotData in self._slotTemplates do
		if slotData and slotData.template then
			slotData.template:Destroy()
		end
		self:_stopGradientSpin("slot_" .. slotType)
	end
	table.clear(self._slotTemplates)
end

function module:_clearItemTemplates()
	for weaponId, itemData in self._itemTemplates do
		self._connections:cleanupGroup("item_" .. weaponId)
		self._connections:cleanupGroup("itemHover_" .. weaponId)
		if itemData and itemData.template then
			itemData.template:Destroy()
		end
		self:_stopGradientSpin("item_" .. weaponId)
	end
	table.clear(self._itemTemplates)
end

function module:show()
	self._ui.Visible = true
	if self._prevAutoSelectGuiEnabled == nil then
		local ok, value = pcall(function()
			return GuiService.AutoSelectGuiEnabled
		end)
		if ok then
			self._prevAutoSelectGuiEnabled = value
		end
	end
	self:_setUINavActive(isGamepadInputType(UserInputService:GetLastInputType()))
	self:_startUINavInputWatcher()
	
	-- Reset loadout state for fresh entry (allows re-entry to training)
	self._loadoutFinished = false
	self._initialized = false
	self._selectedSlot = "Kit"
	self._currentLoadout = {
		Kit = nil,
		Primary = nil,
		Secondary = nil,
		Melee = nil,
	}
	
	self:_animateShow()
	self:_init()
	self:_setUINavActive(isGamepadInputType(UserInputService:GetLastInputType()))
	self:startTimer()
	return true
end

function module:hide()
	self:_animateHide()
	self._connections:cleanupGroup("loadout_uinav")
	self:_setUINavActive(false)
	if self._prevAutoSelectGuiEnabled ~= nil then
		pcall(function()
			GuiService.AutoSelectGuiEnabled = self._prevAutoSelectGuiEnabled
		end)
		self._prevAutoSelectGuiEnabled = nil
	else
		pcall(function()
			GuiService.AutoSelectGuiEnabled = true
		end)
	end

	task.delay(0.6, function()
		self._ui.Visible = false
	end)

	return true
end

function module:_cleanup()
	self._initialized = false
	self._timerRunning = false
	self._loadoutFinished = false

	self:_cancelTweens("show")
	self:_cancelTweens("hide")

	for _, slotType in ipairs(SLOT_TYPES) do
		self:_cancelTweens("slot_" .. slotType)
		self:_cancelTweens("slotHover_" .. slotType)
		self:_cancelTweens("slotSelect_" .. slotType)
		self._connections:cleanupGroup("slot_" .. slotType)
		self._connections:cleanupGroup("slotHover_" .. slotType)
	end

	for weaponId in self._itemTemplates do
		self:_cancelTweens("itemShow_" .. weaponId)
		self:_cancelTweens("itemHover_" .. weaponId)
		self:_cancelTweens("itemSelect_" .. weaponId)
		self._connections:cleanupGroup("item_" .. weaponId)
		self._connections:cleanupGroup("itemHover_" .. weaponId)
		self:_stopGradientSpin("item_" .. weaponId)
	end


	self:_clearSlotTemplates()
	self:_clearItemTemplates()
	for key in self._gradientSpin do
		self:_stopGradientSpin(key)
	end

	self._selectedSlot = "Kit"
	self._pendingSelectedItemId = nil
	self._gamepadInputsBound = false
	self._connections:cleanupGroup("loadout_uinav")
	self._prevAutoSelectGuiEnabled = nil
	table.clear(self._currentLoadout)
	self._currentLoadout = {
		Kit = nil,
		Primary = nil,
		Secondary = nil,
		Melee = nil,
	}

	self:_resetToOriginals()
end

return module
