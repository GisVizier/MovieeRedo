local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataTable = {}
PlayerDataTable.__index = PlayerDataTable

local Configs = ReplicatedStorage:WaitForChild("Configs")
local SettingsConfig = require(Configs.SettingsConfig)
local SettingsCallbacks = require(Configs.SettingsCallbacks)

local mockData = nil
local dataChangedCallbacks = {}

local function deepClone(tbl)
	if typeof(tbl) ~= "table" then
		return tbl
	end

	local clone = {}
	for k, v in tbl do
		clone[k] = deepClone(v)
	end
	return clone
end

function PlayerDataTable.init()
	if mockData then
		return
	end

	mockData = {
		GEMS = 15000,
		CROWNS = 25,
		STREAK = 14,

		EMOTES = {},

		OWNED = {
			OWNED_EMOTES = {"Template", `SBR`, `BC`,`CR`, `FR`, `HS`, `SB`, `BMB`},
			OWNED_KITS = {"WhiteBeard", "Genji", "Aki", "Airborne", "HonoredOne"},
			OWNED_PRIMARY = {"Shotgun", "Sniper"},
			OWNED_SECONDARY = {"Revolver"},
			OWNED_MELEE = {"Tomahawk", "ExecutionerBlade"},
		},

		EQUIPPED = {
			Kit = nil,
			Primary = "Shotgun",
			Secondary = "Revolver",
			Melee = "Tomahawk",
		},

		EQUIPPED_SKINS = {
			-- Revolver = "Energy",
			-- Shotgun = "OGPump",
		},

		EQUIPPED_EMOTES = {
			Slot1 = "Template",
			Slot2 = `SBR`,
			Slot3 = `BMB`,
			Slot4 = `BC`,
			Slot5 = `SB`,
			Slot6 = `CR`,
			Slot7 = `HS`,
			Slot8 = `FR`,
		},

		OWNED_SKINS = {
			Revolver = {"Energy"},
			Shotgun = {"OGPump"},
		},

		-- Per-weapon customization data (kill effects, etc.)
		WEAPON_DATA = {
			-- Example:
			-- ["Shotgun"] = {
			--     killEffect = "Ragdoll", -- Custom kill effect override
			-- },
		},

		Settings = {
			Gameplay = {},
			Controls = {},
			Crosshair = {},
		},
	}

	local defaults = SettingsConfig.DefaultSettings
	for category, settings in defaults do
		for key, value in settings do
			mockData.Settings[category][key] = deepClone(value)
		end
	end
end

function PlayerDataTable.getData(key: string): any
	if not mockData then
		PlayerDataTable.init()
	end

	return deepClone(mockData[key])
end

function PlayerDataTable.setData(key: string, value: any): boolean
	if not mockData then
		PlayerDataTable.init()
	end

	local oldValue = mockData[key]
	mockData[key] = deepClone(value)

	PlayerDataTable._fireCallbacks("Data", key, value, oldValue)

	return true
end

function PlayerDataTable.getOwned(category: string): {any}
	if not mockData then
		PlayerDataTable.init()
	end

	local owned = mockData.OWNED
	if not owned then
		return {}
	end

	return deepClone(owned[category] or {})
end

function PlayerDataTable.isOwned(category: string, itemId: any): boolean
	local ownedList = PlayerDataTable.getOwned(category)
	return table.find(ownedList, itemId) ~= nil
end

function PlayerDataTable.addOwned(category: string, itemId: any): boolean
	if not mockData then
		PlayerDataTable.init()
	end

	if not mockData.OWNED[category] then
		mockData.OWNED[category] = {}
	end

	if not table.find(mockData.OWNED[category], itemId) then
		table.insert(mockData.OWNED[category], itemId)
		PlayerDataTable._fireCallbacks("Owned", category, itemId, nil)
		return true
	end

	return false
end

function PlayerDataTable.getOwnedSkins(weaponId: string): {string}
	if not mockData then
		PlayerDataTable.init()
	end

	if not mockData.OWNED_SKINS then
		return {}
	end

	return deepClone(mockData.OWNED_SKINS[weaponId] or {})
end

function PlayerDataTable.isSkinOwned(weaponId: string, skinId: string): boolean
	local ownedSkins = PlayerDataTable.getOwnedSkins(weaponId)
	return table.find(ownedSkins, skinId) ~= nil
end

function PlayerDataTable.getOwnedWeaponsByType(weaponType: string): {any}
	if not mockData then
		PlayerDataTable.init()
	end

	if weaponType == "Kit" then
		return deepClone(mockData.OWNED.OWNED_KITS or {})
	elseif weaponType == "Primary" then
		return deepClone(mockData.OWNED.OWNED_PRIMARY or {})
	elseif weaponType == "Secondary" then
		return deepClone(mockData.OWNED.OWNED_SECONDARY or {})
	elseif weaponType == "Melee" then
		return deepClone(mockData.OWNED.OWNED_MELEE or {})
	end

	return {}
end

function PlayerDataTable.getEquippedLoadout(): {[string]: any}
	if not mockData then
		PlayerDataTable.init()
	end

	return deepClone(mockData.EQUIPPED or {})
end

function PlayerDataTable.setEquippedWeapon(slotType: string, weaponId: any): boolean
	if not mockData then
		PlayerDataTable.init()
	end

	if not mockData.EQUIPPED then
		mockData.EQUIPPED = {}
	end

	local oldValue = mockData.EQUIPPED[slotType]
	mockData.EQUIPPED[slotType] = weaponId

	PlayerDataTable._fireCallbacks("Equipped", slotType, weaponId, oldValue)

	return true
end

function PlayerDataTable.getEquippedSkin(weaponId: string): string?
	if not mockData then
		PlayerDataTable.init()
	end

	return mockData.EQUIPPED_SKINS and mockData.EQUIPPED_SKINS[weaponId] or nil
end

function PlayerDataTable.setEquippedSkin(weaponId: string, skinId: string?): boolean
	if not mockData then
		PlayerDataTable.init()
	end

	if not mockData.EQUIPPED_SKINS then
		mockData.EQUIPPED_SKINS = {}
	end

	local oldValue = mockData.EQUIPPED_SKINS[weaponId]
	mockData.EQUIPPED_SKINS[weaponId] = skinId

	PlayerDataTable._fireCallbacks("EquippedSkin", weaponId, skinId, oldValue)

	return true
end

function PlayerDataTable.get(category: string, key: string): any
	if not mockData then
		PlayerDataTable.init()
	end

	local categoryData = mockData.Settings[category]
	if not categoryData then
		warn("[PlayerDataTable] Unknown category:", category)
		return nil
	end

	local value = categoryData[key]
	if value == nil then
		local defaults = SettingsConfig.DefaultSettings
		local defaultValue = defaults[category] and defaults[category][key]
		return deepClone(defaultValue)
	end

	return deepClone(value)
end

function PlayerDataTable.set(category: string, key: string, value: any): boolean
	if not mockData then
		PlayerDataTable.init()
	end

	local categoryData = mockData.Settings[category]
	if not categoryData then
		warn("[PlayerDataTable] Unknown category:", category)
		return false
	end

	local oldValue = categoryData[key]
	categoryData[key] = deepClone(value)

	PlayerDataTable._fireCallbacks(category, key, value, oldValue)
	PlayerDataTable._saveToServer(category, key, value)

	return true
end

function PlayerDataTable.getBind(settingKey: string, slot: string): Enum.KeyCode?
	local binds = PlayerDataTable.get("Controls", settingKey)
	if not binds or typeof(binds) ~= "table" then
		return nil
	end
	return binds[slot]
end

function PlayerDataTable.setBind(settingKey: string, slot: string, keyCode: Enum.KeyCode?): boolean
	local binds = PlayerDataTable.get("Controls", settingKey)
	if not binds then
		binds = {}
	end

	binds[slot] = keyCode
	return PlayerDataTable.set("Controls", settingKey, binds)
end

function PlayerDataTable.getConflicts(keyCode: Enum.KeyCode, excludeKey: string?, excludeSlot: string?): {{settingKey: string, slot: string}}
	if not mockData then
		PlayerDataTable.init()
	end

	local conflicts = {}
	local controlsData = mockData.Settings.Controls

	for settingKey, binds in controlsData do
		if typeof(binds) ~= "table" then
			continue
		end

		for slot, boundKey in binds do
			if boundKey == keyCode then
				if settingKey == excludeKey and slot == excludeSlot then
					continue
				end
				table.insert(conflicts, {settingKey = settingKey, slot = slot})
			end
		end
	end

	return conflicts
end

function PlayerDataTable.resetCategory(category: string): boolean
	if not mockData then
		PlayerDataTable.init()
	end

	local defaults = SettingsConfig.DefaultSettings
	local categoryDefaults = defaults[category]

	if not categoryDefaults then
		warn("[PlayerDataTable] Unknown category:", category)
		return false
	end

	mockData.Settings[category] = {}

	for key, value in categoryDefaults do
		mockData.Settings[category][key] = deepClone(value)
		PlayerDataTable._fireCallbacks(category, key, mockData.Settings[category][key], nil)
	end

	PlayerDataTable._saveCategoryToServer(category)

	return true
end

function PlayerDataTable.getAllSettings(): {[string]: {[string]: any}}
	if not mockData then
		PlayerDataTable.init()
	end

	return deepClone(mockData.Settings)
end

function PlayerDataTable.onChanged(callback: (category: string, key: string, newValue: any, oldValue: any) -> ()): () -> ()
	table.insert(dataChangedCallbacks, callback)

	return function()
		local index = table.find(dataChangedCallbacks, callback)
		if index then
			table.remove(dataChangedCallbacks, index)
		end
	end
end

function PlayerDataTable._fireCallbacks(category: string, key: string, newValue: any, oldValue: any)
	for _, callback in dataChangedCallbacks do
		task.spawn(callback, category, key, newValue, oldValue)
	end

	SettingsCallbacks.fire(category, key, newValue, oldValue)
end

function PlayerDataTable._saveToServer(category: string, key: string, value: any)
	warn("[PlayerDataTable] MOCK: Would save to server:", category, key, value)
end

function PlayerDataTable._saveCategoryToServer(category: string)
	warn("[PlayerDataTable] MOCK: Would save category to server:", category)
end

-- Emote System Methods

function PlayerDataTable.getEquippedEmotes(): {[string]: string?}
	if not mockData then
		PlayerDataTable.init()
	end

	return deepClone(mockData.EQUIPPED_EMOTES or {})
end

function PlayerDataTable.setEquippedEmote(slot: string, emoteId: string?): boolean
	if not mockData then
		PlayerDataTable.init()
	end

	if not mockData.EQUIPPED_EMOTES then
		mockData.EQUIPPED_EMOTES = {}
	end

	local oldValue = mockData.EQUIPPED_EMOTES[slot]
	mockData.EQUIPPED_EMOTES[slot] = emoteId

	PlayerDataTable._fireCallbacks("EquippedEmote", slot, emoteId, oldValue)

	return true
end

function PlayerDataTable.isEmoteOwned(emoteId: string): boolean
	return PlayerDataTable.isOwned("OWNED_EMOTES", emoteId)
end

function PlayerDataTable.getOwnedEmotes(): {string}
	return PlayerDataTable.getOwned("OWNED_EMOTES")
end

function PlayerDataTable.addOwnedEmote(emoteId: string): boolean
	return PlayerDataTable.addOwned("OWNED_EMOTES", emoteId)
end

-- Weapon Data Methods

function PlayerDataTable.getWeaponData(weaponId: string): {[string]: any}?
	if not mockData then
		PlayerDataTable.init()
	end

	if not mockData.WEAPON_DATA then
		return nil
	end

	return deepClone(mockData.WEAPON_DATA[weaponId])
end

function PlayerDataTable.setWeaponData(weaponId: string, data: {[string]: any}): boolean
	if not mockData then
		PlayerDataTable.init()
	end

	if not mockData.WEAPON_DATA then
		mockData.WEAPON_DATA = {}
	end

	local oldValue = mockData.WEAPON_DATA[weaponId]
	mockData.WEAPON_DATA[weaponId] = deepClone(data)

	PlayerDataTable._fireCallbacks("WeaponData", weaponId, data, oldValue)

	return true
end

function PlayerDataTable.getWeaponKillEffect(weaponId: string): string?
	local data = PlayerDataTable.getWeaponData(weaponId)
	return data and data.killEffect or nil
end

function PlayerDataTable.setWeaponKillEffect(weaponId: string, killEffect: string?): boolean
	if not mockData then
		PlayerDataTable.init()
	end

	if not mockData.WEAPON_DATA then
		mockData.WEAPON_DATA = {}
	end

	if not mockData.WEAPON_DATA[weaponId] then
		mockData.WEAPON_DATA[weaponId] = {}
	end

	local oldEffect = mockData.WEAPON_DATA[weaponId].killEffect
	mockData.WEAPON_DATA[weaponId].killEffect = killEffect

	PlayerDataTable._fireCallbacks("WeaponKillEffect", weaponId, killEffect, oldEffect)

	return true
end

function PlayerDataTable.getAllWeaponData(): {[string]: {[string]: any}}
	if not mockData then
		PlayerDataTable.init()
	end

	return deepClone(mockData.WEAPON_DATA or {})
end

return PlayerDataTable
