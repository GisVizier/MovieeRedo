local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local LoadoutConfig = require(Configs.LoadoutConfig)
local KitConfig = require(Configs.KitConfig)
local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)
local TweenConfig = require(script.TweenConfig)

local module = {}
module.__index = module

type HealthBar = CanvasGroup & {
	Image: ImageLabel & {
		UIGradient: UIGradient,
	},
	White: ImageLabel & {
		UIGradient: UIGradient,
	},
	Bg: ImageLabel,
}

type UltBar = CanvasGroup & {
	Image: ImageLabel & {
		UIGradient: UIGradient,
	},
	White: ImageLabel & {
		UIGradient: UIGradient,
	},
	Bg: ImageLabel,
}

type HealthBarHolder = CanvasGroup & {
	HealthBar: HealthBar,
	Text: TextLabel,
	SideBar: ImageLabel,
	UnderHealthBg: ImageLabel,
}

type UltBarHolder = CanvasGroup & {
	Bg: ImageLabel,
	Bar: UltBar,
}

type BarHolders = CanvasGroup & {
	HealthBarHolder: HealthBarHolder,
	UltBarHolder: UltBarHolder,
}

type PlayerHolder = CanvasGroup & {
	Holder: CanvasGroup & {
		RotHolder: CanvasGroup & {
			PlayerImage: ImageLabel,
		},
	},
	Bg: ImageLabel,
}

type UI = Frame

local SLOT_ORDER = { "Kit", "Primary", "Secondary", "Melee" }

local HEALTH_COLORS = {
	{ threshold = 0.6, color = Color3.fromRGB(70, 250, 126) },
	{ threshold = 0.35, color = Color3.fromRGB(250, 220, 70) },
	{ threshold = 0.2, color = Color3.fromRGB(250, 150, 50) },
	{ threshold = 0, color = Color3.fromRGB(250, 70, 70) },
}

local currentTweens = {}

local function cancelTweens(key)
	if currentTweens[key] then
		for _, tween in currentTweens[key] do
			tween:Cancel()
		end
		currentTweens[key] = nil
	end
end

local function getHealthColor(percent)
	for _, data in HEALTH_COLORS do
		if percent >= data.threshold then
			return data.color
		end
	end
	return HEALTH_COLORS[#HEALTH_COLORS].color
end

local function calculateGradientOffset(percent)
	return Vector2.new(percent, 0.5)
end

local function getRarityColor(rarityName)
	return LoadoutConfig.getRarityColor(rarityName)
end

function module.start(export, ui: UI)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections
	self._initialized = false

	self._viewedPlayer = nil
	self._currentHealth = 0
	self._currentMaxHealth = 100
	self._currentUlt = 0
	self._maxUlt = 100

	self._weaponTemplates = {}
	self._weaponData = {}
	self._selectedSlot = nil

	local playerSpace = ui.PlayerSpace

	self._playerSpace = playerSpace
	self._healthBar = playerSpace.BarHolders.HealthBarHolder.HealthBar
	self._healthText = playerSpace.BarHolders.HealthBarHolder.Text
	self._ultBar = playerSpace.BarHolders.UltBarHolder.Bar

	self._playerImage = playerSpace.PlayerHolder.Holder.RotHolder.PlayerImage

	self._playerHolderOriginalPosition = playerSpace.PlayerHolder.Position
	self._barHoldersOriginalPosition = playerSpace.BarHolders.Position

	self:_cacheWeaponUI()

	return self
end

function module:_cacheWeaponUI()
	self._itemHolderSpace = self._ui:FindFirstChild("ItemHolderSpace", true)
	if not self._itemHolderSpace then
		return
	end

	self._itemHolderOriginalPosition = self._itemHolderSpace.Position

	self._ammoCounter = self._ui:FindFirstChild("Counter", true)
	self._ammoCounterAmmo = self._ammoCounter and self._ammoCounter:FindFirstChild("Ammo", true)
	self._ammoCounterMax = self._ammoCounter and self._ammoCounter:FindFirstChild("Max", true)
	self._ammoCounterReloading = self._ammoCounter and self._ammoCounter:FindFirstChild("Reloading", true)
	self._ammoCounterAmmoColor = self._ammoCounterAmmo and self._ammoCounterAmmo.TextColor3
	self._ammoCounterMaxColor = self._ammoCounterMax and self._ammoCounterMax.TextColor3

	local actionsFrame = self._itemHolderSpace:FindFirstChild("Actions") or self._itemHolderSpace
	self._itemListFrame = actionsFrame:FindFirstChild("ItemHolder")
	self._weaponTemplateSource = self._itemListFrame and self._itemListFrame:FindFirstChild("Item1")
	self._abilityTemplateSource = self._itemListFrame and self._itemListFrame:FindFirstChild("Ability")
	self._actionsListFrame = self._itemHolderSpace:FindFirstChild("ListFrame")
	self._actionsTemplate = self._actionsListFrame and self._actionsListFrame:FindFirstChild("ActionFrame")

	if not self._weaponTemplateSource then
		self._weaponTemplateSource = actionsFrame:FindFirstChild("Item1", true)
	end
	if not self._abilityTemplateSource then
		self._abilityTemplateSource = actionsFrame:FindFirstChild("Ability", true)
	end
	if not self._actionsTemplate then
		self._actionsTemplate = actionsFrame:FindFirstChild("ActionFrame", true)
	end

	if self._weaponTemplateSource then
		self._weaponTemplateSource.Visible = false
	end
	if self._abilityTemplateSource then
		self._abilityTemplateSource.Visible = false
	end
	if self._actionsTemplate then
		self._actionsTemplate.Visible = false
	end

	self._itemDesc = actionsFrame:FindFirstChild("ItemDesc") or self._ui:FindFirstChild("ItemDesc", true)
	if self._itemDesc then
		self._itemDescActions = self._itemDesc:FindFirstChild("Actions")
		if self._itemDescActions then
			self._itemDescOriginalPos = self._itemDescActions.Position
		end

		local actionsFrame = self._itemDescActions and self._itemDescActions:FindFirstChild("Actions")
		local ammoFrame = actionsFrame and actionsFrame:FindFirstChild("Ammo")
		local infoFrame = actionsFrame and actionsFrame:FindFirstChild("Info")
		local rarityFrame = infoFrame and infoFrame:FindFirstChild("Rarity")

		self._itemDescAmmoFrame = ammoFrame
		self._itemDescAmmo = ammoFrame and ammoFrame:FindFirstChild("Ammo")
		self._itemDescMax = ammoFrame and ammoFrame:FindFirstChild("Max")
		self._itemDescAmmoColor = self._itemDescAmmo and self._itemDescAmmo.TextColor3
		self._itemDescMaxColor = self._itemDescMax and self._itemDescMax.TextColor3
		self._itemDescName = infoFrame and infoFrame:FindFirstChild("name")
		self._itemDescRarityText = rarityFrame and rarityFrame:FindFirstChild("RarityText")
		self._itemDescRarityLabels = {}

		if rarityFrame then
			for _, child in rarityFrame:GetChildren() do
				if child:IsA("TextLabel") then
					table.insert(self._itemDescRarityLabels, child)
				end
			end
		end
	end
end

function module:setViewedPlayer(player, character)
	self._viewedPlayer = player
	self._viewedCharacter = character
end

function module:showForPlayer(player, character)
	self:setViewedPlayer(player, character)
	self._export:show()
end

function module:_updatePlayerThumbnail()
	if not self._viewedPlayer then
		return
	end

	local userId = self._viewedPlayer.UserId
	self._playerImage.Image = "rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=420&h=420"
end

function module:_initPlayerData()
	if not self._viewedPlayer then
		return
	end

	local player = self._viewedPlayer
	local hasKitData = player:GetAttribute("KitData") ~= nil

	PlayerDataTable.init()
	local equipped = PlayerDataTable.getEquippedLoadout()

	player:SetAttribute("Health", 100)
	player:SetAttribute("MaxHealth", 100)
	player:SetAttribute("Ultimate", 0)
	player:SetAttribute("EquippedSlot", "Primary")

	local kitId = equipped.Kit
	if not hasKitData then
		local kitData = kitId and KitConfig.buildKitData(kitId, { abilityCooldownEndsAt = 0, ultimate = 0 }) or nil
		player:SetAttribute("KitData", kitData and HttpService:JSONEncode(kitData) or nil)
	end

	local weaponTypes = { "Primary", "Secondary", "Melee" }

	for _, slotType in weaponTypes do
		local weaponId = equipped[slotType]
		local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)

		if weaponConfig then
			local weaponData = {
				Gun = weaponConfig.name,
				GunId = weaponConfig.id,
				GunType = weaponConfig.weaponType,
				Ammo = weaponConfig.clipSize,
				MaxAmmo = weaponConfig.maxAmmo,
				ClipSize = weaponConfig.clipSize,
				Reloading = false,
				OnCooldown = false,
				Cooldown = weaponConfig.cooldown or 0,
				ReloadTime = weaponConfig.reloadTime or 0,
				Rarity = weaponConfig.rarity,
			}

			local jsonData = HttpService:JSONEncode(weaponData)
			player:SetAttribute(slotType .. "Data", jsonData)
		else
			player:SetAttribute(slotType .. "Data", nil)
		end
	end
end

function module:_clearPlayerData()
	if not self._viewedPlayer then
		return
	end

	local player = self._viewedPlayer

	player:SetAttribute("Health", nil)
	player:SetAttribute("MaxHealth", nil)
	player:SetAttribute("Ultimate", nil)
	player:SetAttribute("EquippedSlot", nil)
	player:SetAttribute("KitData", nil)

	local weaponTypes = { "Primary", "Secondary", "Melee" }

	for _, slotType in weaponTypes do
		player:SetAttribute(slotType .. "Data", nil)
	end
end

function module:_decodeAttribute(attributeValue)
	if type(attributeValue) == "table" then
		return attributeValue
	end

	if type(attributeValue) ~= "string" then
		return nil
	end

	local success, data = pcall(function()
		return HttpService:JSONDecode(attributeValue)
	end)

	if success then
		return data
	end

	return nil
end

-- Prefer syncing from server authoritative SelectedLoadout (MatchService sets it on submit).
-- Returns true if a loadout was successfully applied.
function module:_syncFromSelectedLoadout(): boolean
	if not self._viewedPlayer then
		return false
	end

	local raw = self._viewedPlayer:GetAttribute("SelectedLoadout")
	local decoded = self:_decodeAttribute(raw)
	if type(decoded) ~= "table" then
		return false
	end

	local loadout = decoded.loadout
	if type(loadout) ~= "table" and decoded.Kit ~= nil then
		-- Some builds store the loadout directly.
		loadout = decoded
	end
	if type(loadout) ~= "table" then
		return false
	end

	-- Sync to PlayerDataTable so skin resolution works consistently.
	PlayerDataTable.init()
	for _, slotType in ipairs(SLOT_ORDER) do
		local weaponId = loadout[slotType]
		if weaponId ~= nil then
			PlayerDataTable.setEquippedWeapon(slotType, weaponId)
		end
	end

	-- Seed KitData for HUD ability slot template.
	do
		local kitId = loadout.Kit
		local kitData = kitId and KitConfig.buildKitData(kitId, { abilityCooldownEndsAt = 0, ultimate = 0 }) or nil
		self._viewedPlayer:SetAttribute("KitData", kitData and HttpService:JSONEncode(kitData) or nil)
	end

	-- Seed weapon data blobs for HUD (Primary/Secondary/Melee).
	for _, slotType in ipairs({ "Primary", "Secondary", "Melee" }) do
		local weaponId = loadout[slotType]
		local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)

		if weaponConfig then
			local weaponData = {
				Gun = weaponConfig.name,
				GunId = weaponConfig.id,
				GunType = weaponConfig.weaponType,
				Ammo = weaponConfig.clipSize,
				MaxAmmo = weaponConfig.maxAmmo,
				ClipSize = weaponConfig.clipSize,
				Reloading = false,
				OnCooldown = false,
				Cooldown = weaponConfig.cooldown or 0,
				ReloadTime = weaponConfig.reloadTime or 0,
				Rarity = weaponConfig.rarity,
			}

			self._viewedPlayer:SetAttribute(slotType .. "Data", HttpService:JSONEncode(weaponData))
		else
			self._viewedPlayer:SetAttribute(slotType .. "Data", nil)
		end
	end

	-- Ensure EquippedSlot exists so HUD selection highlights correctly.
	if self._viewedPlayer:GetAttribute("EquippedSlot") == nil then
		self._viewedPlayer:SetAttribute("EquippedSlot", "Primary")
	end

	return true
end

function module:getWeaponData(slotType)
	if not self._viewedPlayer then
		return nil
	end

	local jsonData = self._viewedPlayer:GetAttribute(slotType .. "Data")
	return self:_decodeAttribute(jsonData)
end

function module:getKitData()
	if not self._viewedPlayer then
		return nil
	end

	local jsonData = self._viewedPlayer:GetAttribute("KitData")
	return self:_decodeAttribute(jsonData)
end

function module:getCurrentWeaponData()
	if not self._viewedPlayer then
		return nil
	end

	local equippedSlot = self._viewedPlayer:GetAttribute("EquippedSlot")
	if not equippedSlot then
		return nil
	end

	return self:getWeaponData(equippedSlot)
end

function module:_applyRarity(template, color)
	if not template or not color then
		return
	end

	local rarity = template:FindFirstChild("Rarity", true)
	if rarity and rarity:IsA("CanvasGroup") then
		rarity.GroupColor3 = color
	end

	local bar = template:FindFirstChild("Bar", true)
	if bar and bar:IsA("ImageLabel") then
		bar.ImageColor3 = color
	end

	local bgRarity = template:FindFirstChild("BgRarity", true)
	if bgRarity and bgRarity:IsA("ImageLabel") then
		bgRarity.ImageColor3 = color
	end
end

function module:_getWeaponImage(weaponId)
	if not weaponId then
		return nil
	end

	local skinId = PlayerDataTable.getEquippedSkin(weaponId)
	if skinId then
		local skin = LoadoutConfig.getWeaponSkin(weaponId, skinId)
		if skin and skin.imageId then
			local weapon = LoadoutConfig.getWeapon(weaponId)
			return skin.imageId, weapon and weapon.rarity or nil
		end
	end

	local weapon = LoadoutConfig.getWeapon(weaponId)
	if weapon then
		return weapon.imageId, weapon.rarity
	end

	return nil
end

function module:_setupTemplateReloadState(templateData, isReloading, reloadTime)
	if not templateData or not templateData.reloading or not templateData.reloadGradient then
		return
	end

	local function clearReloadFlag()
		if not self._viewedPlayer or not templateData.slot or templateData.slot == "Kit" then
			return
		end

		local attributeName = templateData.slot .. "Data"
		local jsonData = self._viewedPlayer:GetAttribute(attributeName)
		local data = self:_decodeAttribute(jsonData)
		if not data then
			return
		end

		if data.Reloading == false then
			return
		end

		data.Reloading = false

		local success, encoded = pcall(function()
			return HttpService:JSONEncode(data)
		end)

		if success then
			self._viewedPlayer:SetAttribute(attributeName, encoded)
		end
	end

	local key = "reload_" .. templateData.slot
	cancelTweens(key)

	if not isReloading then
		templateData.reloading.GroupTransparency = 0
		templateData.reloadGradient.Offset = Vector2.new(0.5, -1)
		if templateData.reloadBg then
			templateData.reloadBg.ImageTransparency = 1
		end
		return
	end

	templateData.reloading.GroupTransparency = 0
	templateData.reloadGradient.Offset = Vector2.new(0.5, 0)
	if templateData.reloadBg then
		templateData.reloadBg.ImageTransparency = 1
	end

	local tweens = {}

	if templateData.reloadBg then
		local fadeIn = TweenService:Create(templateData.reloadBg, TweenConfig.get("Reload", "fadeIn"), {
			ImageTransparency = TweenConfig.Values.ReloadBgVisible,
		})
		fadeIn:Play()
		table.insert(tweens, fadeIn)
	end

	local duration = reloadTime and reloadTime > 0 and reloadTime or TweenConfig.Values.ReloadDuration
	local gradientTween = TweenService:Create(
		templateData.reloadGradient,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{
			Offset = Vector2.new(0.5, -1),
		}
	)
	gradientTween:Play()
	table.insert(tweens, gradientTween)

	gradientTween.Completed:Once(function()
		clearReloadFlag()
		if templateData.reloadBg then
			local fadeOut = TweenService:Create(templateData.reloadBg, TweenConfig.get("Reload", "fadeOut"), {
				ImageTransparency = 1,
			})
			fadeOut:Play()
			table.insert(tweens, fadeOut)
			fadeOut.Completed:Once(function()
				if templateData.reloading then
					templateData.reloading.GroupTransparency = 0
				end
			end)
		else
			templateData.reloading.GroupTransparency = 0
		end
	end)

	currentTweens[key] = tweens
end

function module:_createTemplate(slotType, templateSource, iconImage, rarityColor, order)
	if not templateSource or not self._itemListFrame then
		return nil
	end

	local template = templateSource:Clone()
	template.Name = "Slot_" .. slotType
	template.Visible = true
	template.LayoutOrder = order
	template.Parent = self._itemListFrame

	local uiScale = template:FindFirstChild("UIScale")
	if uiScale then
		uiScale.Scale = TweenConfig.Values.DeselectedScale
	end

	if iconImage then
		local iconHolder = template:FindFirstChild("IconHolder", true)
		if iconHolder then
			local icon = iconHolder:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				icon.Image = iconImage
			end

			local bg = iconHolder:FindFirstChild("bg")
			if bg and bg:IsA("ImageLabel") then
				bg.Image = iconImage
			end

			local reloadIcon = iconHolder:FindFirstChild("Reloading", true)
			if reloadIcon then
				local reloadIconImage = reloadIcon:FindFirstChild("Icon")
				if reloadIconImage and reloadIconImage:IsA("ImageLabel") then
					reloadIconImage.Image = iconImage
				end
			end
		end
	end

	self:_applyRarity(template, rarityColor)

	local reloading = template:FindFirstChild("Reloading", true)
	local reloadGradient = reloading and reloading:FindFirstChild("UIGradient")
	local reloadBg = reloading and reloading:FindFirstChild("Bg")
	local reloadGradImage = reloading and reloading:FindFirstChild("grad")

	if reloadBg and rarityColor then
		reloadBg.ImageColor3 = rarityColor
	end

	if reloading and reloading:IsA("CanvasGroup") then
		reloading.GroupTransparency = 0
	end
	if reloadGradient then
		reloadGradient.Offset = Vector2.new(0.5, -1)
	end
	if reloadBg then
		reloadBg.ImageTransparency = 1
	end
	if reloadGradImage and iconImage then
		reloadGradImage.Image = iconImage
	end

	local data = {
		slot = slotType,
		template = template,
		uiScale = uiScale,
		reloading = reloading,
		reloadGradient = reloadGradient,
		reloadBg = reloadBg,
	}

	self._weaponTemplates[slotType] = data

	return data
end

function module:_clearTemplates()
	for _, data in self._weaponTemplates do
		if data.template and data.template.Parent then
			data.template:Destroy()
		end
	end
	table.clear(self._weaponTemplates)
end

function module:_buildLoadoutTemplates()
	if not self._itemListFrame then
		return
	end

	local order = 1
	local activeSlots = {}

	local kitData = self:getKitData()
	if kitData and self._abilityTemplateSource then
		activeSlots.Kit = true
		if not self._weaponTemplates.Kit then
			local rarityInfo = kitData.Rarity and KitConfig.RarityInfo[kitData.Rarity]
			local rarityColor = rarityInfo and rarityInfo.COLOR or Color3.new(1, 1, 1)
			self:_createTemplate("Kit", self._abilityTemplateSource, kitData.Icon, rarityColor, order)
		else
			self._weaponTemplates.Kit.template.LayoutOrder = order
		end
		order += 1
	end

	for _, slotType in { "Primary", "Secondary", "Melee" } do
		local data = self:getWeaponData(slotType)
		if data and self._weaponTemplateSource then
			activeSlots[slotType] = true
			if not self._weaponTemplates[slotType] then
				local weaponId = data.GunId or data.Gun
				local imageId, rarityName = self:_getWeaponImage(weaponId)
				local rarityColor = getRarityColor(rarityName)
				self:_createTemplate(slotType, self._weaponTemplateSource, imageId, rarityColor, order)
			else
				self._weaponTemplates[slotType].template.LayoutOrder = order
			end
			order += 1
		end
	end

	for slotType, data in self._weaponTemplates do
		if not activeSlots[slotType] then
			if data.template and data.template.Parent then
				data.template:Destroy()
			end
			self._weaponTemplates[slotType] = nil
		end
	end
end

function module:_setSelectedSlot(slotType)
	if slotType == "Kit" then
		slotType = "Primary"
	end

	self._selectedSlot = slotType

	for slot, data in self._weaponTemplates do
		local targetScale = slot == slotType and TweenConfig.Values.SelectedScale or TweenConfig.Values.DeselectedScale
		if data.uiScale then
			local key = "select_" .. slot
			cancelTweens(key)
			local tween = TweenService:Create(data.uiScale, TweenConfig.get("Selection", "update"), {
				Scale = targetScale,
			})
			tween:Play()
			currentTweens[key] = { tween }
		end
	end

	if slotType and slotType ~= "Kit" then
		local data = self._weaponData[slotType]
		if data then
			self:_updateItemDesc(data)
			self:_animateItemDesc()
		else
			self:_hideItemDesc()
		end
	else
		self:_hideItemDesc()
	end

	self:_populateActions(slotType)
end

function module:_updateItemDesc(weaponData)
	if not weaponData then
		return
	end

	local maxAmmo = weaponData.MaxAmmo or 0
	local ammo = weaponData.Ammo or 0
	local clipSize = weaponData.ClipSize or 0
	
	-- Hide ammo display for weapons that don't use ammo (melee weapons)
	local usesAmmo = clipSize > 0 or maxAmmo > 0

	if self._itemDescAmmoFrame then
		if self._itemDescAmmoFrame:IsA("CanvasGroup") then
			self._itemDescAmmoFrame.GroupTransparency = usesAmmo and 0 or 1
		else
			self._itemDescAmmoFrame.Visible = usesAmmo
		end
	end
	
	if self._ammoCounter then
		if self._ammoCounter:IsA("CanvasGroup") then
			self._ammoCounter.GroupTransparency = usesAmmo and 0 or 1
		else
			self._ammoCounter.Visible = usesAmmo
		end
	end

	if usesAmmo then
		if self._itemDescAmmo then
			self._itemDescAmmo.Text = tostring(ammo)
		end

		if self._itemDescMax then
			self._itemDescMax.Text = tostring(maxAmmo)
		end

		if self._ammoCounterAmmo then
			self._ammoCounterAmmo.Text = tostring(ammo)
		end

		if self._ammoCounterMax then
			self._ammoCounterMax.Text = tostring(maxAmmo)
		end

		local outOfAmmo = ammo <= 0 and maxAmmo <= 0
		local emptyColor = Color3.fromRGB(250, 70, 70)

		if self._itemDescAmmo then
			self._itemDescAmmo.TextColor3 = outOfAmmo and emptyColor or self._itemDescAmmoColor
		end
		if self._itemDescMax then
			self._itemDescMax.TextColor3 = outOfAmmo and emptyColor or self._itemDescMaxColor
		end
		if self._ammoCounterAmmo then
			self._ammoCounterAmmo.TextColor3 = outOfAmmo and emptyColor or self._ammoCounterAmmoColor
		end
		if self._ammoCounterMax then
			self._ammoCounterMax.TextColor3 = outOfAmmo and emptyColor or self._ammoCounterMaxColor
		end
	end

	if self._ammoCounterReloading then
		local isReloading = weaponData.Reloading == true and usesAmmo
		if self._ammoCounterReloading:IsA("TextLabel") then
			self._ammoCounterReloading.Text = "RELOADING"
		end
		if self._ammoCounterReloading:IsA("GuiObject") then
			self._ammoCounterReloading.Visible = isReloading
		elseif self._ammoCounterReloading:IsA("CanvasGroup") then
			self._ammoCounterReloading.GroupTransparency = isReloading and 0 or 1
		end
	end

	if self._itemDescName then
		self._itemDescName.Text = tostring(weaponData.Gun or weaponData.GunId or "WEAPON")
	end

	if self._itemDescRarityText then
		local rarityName = weaponData.Rarity or "Common"
		self._itemDescRarityText.Text = tostring(rarityName):upper()
		local rarityColor = getRarityColor(rarityName)
		for _, label in self._itemDescRarityLabels do
			label.TextColor3 = rarityColor
		end
	end
end

function module:_clearActions()
	if not self._actionsListFrame then
		return
	end

	for _, child in self._actionsListFrame:GetChildren() do
		if child.Name:match("^Action_") then
			child:Destroy()
		end
	end
end

function module:_getActionList(slotType, weaponData)
	local actions = {}
	if not slotType or slotType == "Kit" then
		warn("[HUD] Actions skipped: slotType", slotType)
		return actions
	end

	local weaponId = weaponData and (weaponData.GunId or weaponData.Gun)
	local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)
	local actionFlags = weaponConfig and weaponConfig.actions
	if not weaponId then
		warn("[HUD] Actions missing weaponId for slot", slotType)
	elseif not weaponConfig then
		warn("[HUD] Actions missing weaponConfig for", weaponId, "slot", slotType)
	elseif not actionFlags then
		warn("[HUD] Actions missing action flags for", weaponId, "slot", slotType)
	end

	local canQuickMelee = actionFlags and actionFlags.canQuickUseMelee
	local canQuickAbility = actionFlags and actionFlags.canQuickUseAblility

	if actionFlags == nil then
		if weaponConfig and weaponConfig.weaponType then
			canQuickMelee = weaponConfig.weaponType ~= "Melee"
			canQuickAbility = true
		else
			canQuickMelee = slotType ~= "Melee"
			canQuickAbility = true
		end
	end

	if canQuickMelee and slotType ~= "Melee" then
		table.insert(actions, { id = "QuickMelee", label = "QUICK MELEE", key = "V" })
	end

	if canQuickAbility then
		table.insert(actions, { id = "QuickAbility", label = "USE ABILITY", key = "E" })
	end

	return actions
end

function module:_populateActions(slotType)
	self:_clearActions()

	if not self._actionsListFrame or not self._actionsTemplate then
		warn("[HUD] Actions missing list/template")
		return
	end

	local weaponData = slotType and self._weaponData[slotType]
	local actions = self:_getActionList(slotType, weaponData)
	warn("[HUD] Actions count", #actions, "slot", slotType)

	for i, action in ipairs(actions) do
		local actionFrame = self._actionsTemplate:Clone()
		actionFrame.Name = "Action_" .. action.id
		actionFrame.Visible = true
		actionFrame.LayoutOrder = i
		actionFrame.Parent = self._actionsListFrame

		local contentFrame = actionFrame:FindFirstChild("ContentFrame")
		local actionLabel = contentFrame and contentFrame:FindFirstChild("ActionLabel")
		if actionLabel and actionLabel:IsA("TextLabel") then
			actionLabel.Text = action.label
		end

		local inputFrame = contentFrame and contentFrame:FindFirstChild("InputFrame")
		local keyLabel = inputFrame and inputFrame:FindFirstChild("KeyboardImageLabel")
		keyLabel = keyLabel and keyLabel:FindFirstChild("ActionLabel")
		if keyLabel and keyLabel:IsA("TextLabel") then
			keyLabel.Text = action.key
		end
	end
end

function module:_animateItemDesc()
	if not self._itemDescActions or not self._itemDescOriginalPos then
		return
	end

	cancelTweens("item_desc")

	local startPos = UDim2.new(
		self._itemDescOriginalPos.X.Scale + TweenConfig.Values.ItemDescOffset,
		self._itemDescOriginalPos.X.Offset,
		self._itemDescOriginalPos.Y.Scale,
		self._itemDescOriginalPos.Y.Offset
	)

	self._itemDescActions.Position = startPos
	self._itemDescActions.GroupTransparency = 1

	local tween = TweenService:Create(self._itemDescActions, TweenConfig.get("ItemDesc", "show"), {
		Position = self._itemDescOriginalPos,
		GroupTransparency = 0,
	})
	tween:Play()
	currentTweens["item_desc"] = { tween }
end

function module:_hideItemDesc()
	if not self._itemDescActions or not self._itemDescOriginalPos then
		return
	end

	cancelTweens("item_desc")

	local startPos = UDim2.new(
		self._itemDescOriginalPos.X.Scale + TweenConfig.Values.ItemDescOffset,
		self._itemDescOriginalPos.X.Offset,
		self._itemDescOriginalPos.Y.Scale,
		self._itemDescOriginalPos.Y.Offset
	)

	local tween = TweenService:Create(self._itemDescActions, TweenConfig.get("ItemDesc", "hide"), {
		Position = startPos,
		GroupTransparency = 1,
	})
	tween:Play()
	currentTweens["item_desc"] = { tween }
end

function module:_setHealthBar(health, maxHealth, instant)
	local percent = math.clamp(health / maxHealth, 0, 1)
	local newOffset = calculateGradientOffset(percent)
	local newColor = getHealthColor(percent)

	self._healthText.Text = math.floor(health) .. "/" .. math.floor(maxHealth)

	local mainGradient = self._healthBar.Image.UIGradient
	local whiteGradient = self._healthBar.White.UIGradient

	if instant then
		mainGradient.Offset = newOffset
		whiteGradient.Offset = newOffset
		self._healthBar.Image.ImageColor3 = newColor
		return
	end

	cancelTweens("health_main")
	cancelTweens("health_white")
	cancelTweens("health_color")

	local mainTween = TweenService:Create(mainGradient, TweenConfig.get("Bar", "main"), {
		Offset = newOffset,
	})
	mainTween:Play()
	currentTweens["health_main"] = { mainTween }

	local colorTween = TweenService:Create(self._healthBar.Image, TweenConfig.get("Bar", "main"), {
		ImageColor3 = newColor,
	})
	colorTween:Play()
	currentTweens["health_color"] = { colorTween }

	task.delay(TweenConfig.getDelay("WhiteBar"), function()
		if not self._ui or not self._ui.Parent then
			return
		end

		cancelTweens("health_white")

		local whiteTween = TweenService:Create(whiteGradient, TweenConfig.get("Bar", "white"), {
			Offset = newOffset,
		})
		whiteTween:Play()
		currentTweens["health_white"] = { whiteTween }
	end)
end

function module:_setUltBar(ult, instant)
	local percent = math.clamp(ult / self._maxUlt, 0, 1)
	local newOffset = calculateGradientOffset(percent)

	local mainGradient = self._ultBar.Image.UIGradient
	local whiteGradient = self._ultBar.White.UIGradient

	if instant then
		mainGradient.Offset = newOffset
		whiteGradient.Offset = newOffset
		return
	end

	cancelTweens("ult_main")
	cancelTweens("ult_white")

	local mainTween = TweenService:Create(mainGradient, TweenConfig.get("Bar", "main"), {
		Offset = newOffset,
	})
	mainTween:Play()
	currentTweens["ult_main"] = { mainTween }

	task.delay(TweenConfig.getDelay("WhiteBar"), function()
		if not self._ui or not self._ui.Parent then
			return
		end

		cancelTweens("ult_white")

		local whiteTween = TweenService:Create(whiteGradient, TweenConfig.get("Bar", "white"), {
			Offset = newOffset,
		})
		whiteTween:Play()
		currentTweens["ult_white"] = { whiteTween }
	end)
end

function module:_setupHealthConnection()
	if not self._viewedPlayer then
		return
	end

	self._connections:cleanupGroup("hud_health")

	local function onHealthChanged()
		local health = self._viewedPlayer:GetAttribute("Health") or 100
		local maxHealth = self._viewedPlayer:GetAttribute("MaxHealth") or 100

		self._currentHealth = health
		self._currentMaxHealth = maxHealth

		self:_setHealthBar(health, maxHealth, false)
	end

	self._connections:track(self._viewedPlayer, "AttributeChanged", function(attributeName)
		if attributeName == "Health" or attributeName == "MaxHealth" then
			onHealthChanged()
		end
	end, "hud_health")

	onHealthChanged()
end

function module:_setupUltConnection()
	if not self._viewedPlayer then
		return
	end

	self._connections:cleanupGroup("hud_ult")

	local function onUltChanged()
		local ult = self._viewedPlayer:GetAttribute("Ultimate") or 0
		self._currentUlt = ult
		self:_setUltBar(ult, false)
	end

	self._connections:track(self._viewedPlayer, "AttributeChanged", function(attributeName)
		if attributeName == "Ultimate" then
			onUltChanged()
		end
	end, "hud_ult")

	onUltChanged()
end

function module:_refreshWeaponData()
	for _, slotType in SLOT_ORDER do
		self:_updateSlotData(slotType)
	end

	local equippedSlot = self._viewedPlayer and self._viewedPlayer:GetAttribute("EquippedSlot")
	if not equippedSlot then
		equippedSlot = "Primary"
	end
	self:_setSelectedSlot(equippedSlot)
end

function module:_updateSlotData(slotType)
	local data
	if slotType == "Kit" then
		data = self:getKitData()
	else
		data = self:getWeaponData(slotType)
	end

	self._weaponData[slotType] = data

	self:_buildLoadoutTemplates()

	local templateData = self._weaponTemplates[slotType]
	if not templateData or not data then
		return
	end

	if slotType ~= "Kit" then
		local weaponId = data.GunId or data.Gun
		local imageId, rarityName = self:_getWeaponImage(weaponId)
		if imageId then
			local icon = templateData.template:FindFirstChild("Icon", true)
			if icon and icon:IsA("ImageLabel") then
				icon.Image = imageId
			end
		end

		if rarityName then
			local rarityColor = getRarityColor(rarityName)
			self:_applyRarity(templateData.template, rarityColor)
			if templateData.reloadBg and rarityColor then
				templateData.reloadBg.ImageColor3 = rarityColor
			end
		end
	else
		local iconHolder = templateData.template:FindFirstChild("IconHolder", true)
		if iconHolder then
			local icon = iconHolder:FindFirstChild("Icon")
			if icon and icon:IsA("ImageLabel") then
				icon.Image = data.Icon or icon.Image
			end
		end

		local rarityInfo = data.Rarity and KitConfig.RarityInfo[data.Rarity]
		if rarityInfo then
			self:_applyRarity(templateData.template, rarityInfo.COLOR)
			if templateData.reloadBg then
				templateData.reloadBg.ImageColor3 = rarityInfo.COLOR
			end
		end
	end

	if slotType ~= "Kit" then
		self:_setupTemplateReloadState(templateData, data.Reloading == true, data.ReloadTime)
	else
		local isOnCooldown = data.AbilityOnCooldown == true
		local cooldownTime = data.AbilityCooldownRemaining or data.AbilityCooldown
		self:_setupTemplateReloadState(templateData, isOnCooldown, cooldownTime)
	end

	if self._selectedSlot == slotType and slotType ~= "Kit" then
		self:_updateItemDesc(data)
		self:_populateActions(slotType)
	end
end

function module:_setupWeaponConnections()
	if not self._viewedPlayer then
		return
	end

	self._connections:cleanupGroup("hud_weapons")

	self._connections:track(self._viewedPlayer, "AttributeChanged", function(attributeName)
		if attributeName == "SelectedLoadout" then
			if self:_syncFromSelectedLoadout() then
				self:_refreshWeaponData()
			end
			return
		end

		if attributeName == "EquippedSlot" then
			local slot = self._viewedPlayer:GetAttribute("EquippedSlot")
			if slot then
				self:_setSelectedSlot(slot)
			end
			return
		end

		if attributeName == "KitData" then
			self:_updateSlotData("Kit")
			return
		end

		for _, slotType in { "Primary", "Secondary", "Melee" } do
			if attributeName == slotType .. "Data" then
				self:_updateSlotData(slotType)
				return
			end
		end
	end, "hud_weapons")
end

function module:_setInitialState()
	local playerHolder = self._playerSpace.PlayerHolder
	local barHolders = self._playerSpace.BarHolders

	if self._itemHolderSpace and self._itemHolderOriginalPosition then
		self._itemHolderSpace.GroupTransparency = 1
		self._itemHolderSpace.Position = UDim2.new(
			self._itemHolderOriginalPosition.X.Scale,
			self._itemHolderOriginalPosition.X.Offset,
			self._itemHolderOriginalPosition.Y.Scale + 0.1,
			self._itemHolderOriginalPosition.Y.Offset
		)
	end

	playerHolder.GroupTransparency = 1
	playerHolder.Position = UDim2.new(
		self._playerHolderOriginalPosition.X.Scale,
		self._playerHolderOriginalPosition.X.Offset,
		self._playerHolderOriginalPosition.Y.Scale + 0.1,
		self._playerHolderOriginalPosition.Y.Offset
	)

	barHolders.GroupTransparency = 1
	barHolders.Position = UDim2.new(
		self._barHoldersOriginalPosition.X.Scale,
		self._barHoldersOriginalPosition.X.Offset,
		self._barHoldersOriginalPosition.Y.Scale + 0.1,
		self._barHoldersOriginalPosition.Y.Offset
	)
end

function module:_animateShow()
	local playerHolder = self._playerSpace.PlayerHolder
	local barHolders = self._playerSpace.BarHolders

	cancelTweens("show_player")
	cancelTweens("show_bars")
	cancelTweens("show_items")

	if self._itemHolderSpace and self._itemHolderOriginalPosition then
		local itemsTween = TweenService:Create(self._itemHolderSpace, TweenConfig.get("Main", "show"), {
			GroupTransparency = 0,
			Position = self._itemHolderOriginalPosition,
		})
		itemsTween:Play()
		currentTweens["show_items"] = { itemsTween }
	end

	local playerTween = TweenService:Create(playerHolder, TweenConfig.get("Main", "show"), {
		GroupTransparency = 0,
		Position = self._playerHolderOriginalPosition,
	})
	playerTween:Play()
	currentTweens["show_player"] = { playerTween }

	task.delay(TweenConfig.getDelay("Stagger"), function()
		if not self._ui or not self._ui.Parent then
			return
		end

		cancelTweens("show_bars")

		local barsTween = TweenService:Create(barHolders, TweenConfig.get("Main", "show"), {
			GroupTransparency = 0,
			Position = self._barHoldersOriginalPosition,
		})
		barsTween:Play()
		currentTweens["show_bars"] = { barsTween }
	end)

	return playerTween
end

function module:_animateHide()
	local playerHolder = self._playerSpace.PlayerHolder
	local barHolders = self._playerSpace.BarHolders

	cancelTweens("show_player")
	cancelTweens("show_bars")
	cancelTweens("show_items")

	if self._itemHolderSpace and self._itemHolderOriginalPosition then
		local targetItemsPos = UDim2.new(
			self._itemHolderOriginalPosition.X.Scale,
			self._itemHolderOriginalPosition.X.Offset,
			self._itemHolderOriginalPosition.Y.Scale + 0.1,
			self._itemHolderOriginalPosition.Y.Offset
		)

		local itemsTween = TweenService:Create(self._itemHolderSpace, TweenConfig.get("Main", "hide"), {
			GroupTransparency = 1,
			Position = targetItemsPos,
		})
		itemsTween:Play()
		currentTweens["show_items"] = { itemsTween }
	end

	local targetPlayerPos = UDim2.new(
		self._playerHolderOriginalPosition.X.Scale,
		self._playerHolderOriginalPosition.X.Offset,
		self._playerHolderOriginalPosition.Y.Scale + 0.1,
		self._playerHolderOriginalPosition.Y.Offset
	)

	local targetBarsPos = UDim2.new(
		self._barHoldersOriginalPosition.X.Scale,
		self._barHoldersOriginalPosition.X.Offset,
		self._barHoldersOriginalPosition.Y.Scale + 0.1,
		self._barHoldersOriginalPosition.Y.Offset
	)

	local playerTween = TweenService:Create(playerHolder, TweenConfig.get("Main", "hide"), {
		GroupTransparency = 1,
		Position = targetPlayerPos,
	})
	playerTween:Play()
	currentTweens["show_player"] = { playerTween }

	local barsTween = TweenService:Create(barHolders, TweenConfig.get("Main", "hide"), {
		GroupTransparency = 1,
		Position = targetBarsPos,
	})
	barsTween:Play()
	currentTweens["show_bars"] = { barsTween }

	return barsTween
end

function module:_init()
	if self._initialized then
		self:_setupHealthConnection()
		self:_setupUltConnection()
		self:_setupWeaponConnections()
		self:_refreshWeaponData()
		return
	end

	self._initialized = true

	self:_buildLoadoutTemplates()
	self:_setupHealthConnection()
	self:_setupUltConnection()
	self:_setupWeaponConnections()
	self:_refreshWeaponData()
end

function module:show()
	if not self._viewedPlayer then
		self._viewedPlayer = Players.LocalPlayer
	end

	-- Prefer the real server-selected loadout (Option A: show HUD on StartMatch).
	-- Fallback to mock data only if SelectedLoadout isn't available (studio/UI testing).
	if not self:_syncFromSelectedLoadout() then
		self:_initPlayerData()
	end
	self:_updatePlayerThumbnail()

	local health = self._viewedPlayer:GetAttribute("Health") or 100
	local maxHealth = self._viewedPlayer:GetAttribute("MaxHealth") or 100
	local ult = self._viewedPlayer:GetAttribute("Ultimate") or 0

	self:_setHealthBar(health, maxHealth, true)
	self:_setUltBar(ult, true)

	self._ui.Visible = true

	self:_setInitialState()
	self:_animateShow()

	self:_init()

	return true
end

function module:hide()
	local lastTween = self:_animateHide()

	if lastTween then
		lastTween.Completed:Wait()
	end

	self._ui.Visible = false

	return true
end

function module:_cleanup()
	self._initialized = false

	self._connections:cleanupGroup("hud_health")
	self._connections:cleanupGroup("hud_ult")
	self._connections:cleanupGroup("hud_weapons")

	for _, tweens in currentTweens do
		for _, tween in tweens do
			tween:Cancel()
		end
	end
	table.clear(currentTweens)

	-- Do NOT clear live player attributes here (health/loadout may be owned by gameplay).
	self:_clearTemplates()

	self._weaponData = {}
	self._selectedSlot = nil

	self._viewedPlayer = nil
	self._viewedCharacter = nil
end

return module
