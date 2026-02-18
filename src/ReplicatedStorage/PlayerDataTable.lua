local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerDataTable = {}
PlayerDataTable.__index = PlayerDataTable

local Configs = ReplicatedStorage:WaitForChild("Configs")
local SettingsConfig = require(Configs.SettingsConfig)
local SettingsCallbacks = require(Configs.SettingsCallbacks)

local mockData = nil
local replicaData = nil -- Live server data when Replica connected
local dataChangedCallbacks = {}
local _initCount = 0
local _updateCount = 0

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

local function getDataSource()
	return replicaData or mockData
end

local _replicaClientLoaded = false
local function ensureReplicaClient()
	if RunService:IsClient() and not _replicaClientLoaded then
		_replicaClientLoaded = true
		local ok, Replica = pcall(require, ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ReplicaClient"))
		if ok and Replica then
			Replica.RequestData()
			Replica.OnNew("PlayerData", function(replica)
				if replica.Tags and replica.Tags.UserId == game:GetService("Players").LocalPlayer.UserId then
					replicaData = replica.Data
					local d = replicaData
					print(
						"[PlayerDataTable] Replica connected! GEMS:",
						d.GEMS,
						"WINS:",
						d.WINS,
						"STREAK:",
						d.STREAK,
						"| Loadout:",
						d.EQUIPPED and d.EQUIPPED.Primary or "?"
					)
					replica:OnChange(function(action, path, param1, param2)
						_updateCount += 1
						local pathStr = type(path) == "table" and table.concat(path, ".") or tostring(path)
						print("[PlayerDataTable] <- Update #" .. _updateCount, action, pathStr)
					end)
				end
			end)
		end
	end
end

function PlayerDataTable.init()
	ensureReplicaClient()
	if mockData then
		return
	end

	_initCount += 1
	mockData = {
		GEMS = 15000,
		CROWNS = 25,
		WINS = 42,
		STREAK = 14,

		EMOTES = {},

		OWNED = {
			OWNED_EMOTES = { "Template", `SBR`, `BC`, `CR`, `FR`, `HS`, `SB`, `BMB` },
			OWNED_KITS = { "WhiteBeard", "Genji", "Aki", "Airborne", "HonoredOne" },
			OWNED_PRIMARY = { "Shotgun", "Sniper" },
			OWNED_SECONDARY = { "Revolver", "Shorty", "DualPistols" },
			OWNED_MELEE = { "Tomahawk", "ExecutionerBlade" },
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
			-- Tomahawk = "Cleaver"
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
			Revolver = { "Energy" },
			Shotgun = { "OGPump" },
			Tomahawk = { "Cleaver" },
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
	print(
		"[PlayerDataTable] Init #" .. _initCount,
		replicaData and "Replica ready" or "Using mock (waiting for replica)"
	)
end

function PlayerDataTable.getData(key: string): any
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	return src and deepClone(src[key]) or nil
end

function PlayerDataTable.setData(key: string, value: any): boolean
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src then
		return false
	end
	local oldValue = src[key]
	if not replicaData then
		mockData[key] = deepClone(value)
	end
	PlayerDataTable._fireCallbacks("Data", key, value, oldValue)
	PlayerDataTable._savePathToServer({ key }, value)
	return true
end

function PlayerDataTable.getOwned(category: string): { any }
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	local owned = src and src.OWNED
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
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src or not src.OWNED then
		return false
	end
	if not src.OWNED[category] then
		src.OWNED[category] = {}
	end
	if table.find(src.OWNED[category], itemId) then
		return false
	end
	local newList = deepClone(src.OWNED[category])
	table.insert(newList, itemId)
	if not replicaData then
		src.OWNED[category] = newList
	end
	PlayerDataTable._fireCallbacks("Owned", category, itemId, nil)
	PlayerDataTable._savePathToServer({ "OWNED", category }, newList)
	return true
end

function PlayerDataTable.getOwnedSkins(weaponId: string): { string }
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src or not src.OWNED_SKINS then
		return {}
	end
	return deepClone(src.OWNED_SKINS[weaponId] or {})
end

function PlayerDataTable.isSkinOwned(weaponId: string, skinId: string): boolean
	local ownedSkins = PlayerDataTable.getOwnedSkins(weaponId)
	return table.find(ownedSkins, skinId) ~= nil
end

function PlayerDataTable.getOwnedWeaponsByType(weaponType: string): { any }
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	local owned = src and src.OWNED
	if not owned then
		return {}
	end
	if weaponType == "Kit" then
		return deepClone(owned.OWNED_KITS or {})
	elseif weaponType == "Primary" then
		return deepClone(owned.OWNED_PRIMARY or {})
	elseif weaponType == "Secondary" then
		return deepClone(owned.OWNED_SECONDARY or {})
	elseif weaponType == "Melee" then
		return deepClone(owned.OWNED_MELEE or {})
	end
	return {}
end

function PlayerDataTable.getEquippedLoadout(): { [string]: any }
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	return src and deepClone(src.EQUIPPED or {}) or {}
end

function PlayerDataTable.setEquippedWeapon(slotType: string, weaponId: any): boolean
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src then
		return false
	end
	if not src.EQUIPPED then
		src.EQUIPPED = {}
	end
	local oldValue = src.EQUIPPED[slotType]
	if not replicaData then
		src.EQUIPPED[slotType] = weaponId
	end
	PlayerDataTable._fireCallbacks("Equipped", slotType, weaponId, oldValue)
	PlayerDataTable._savePathToServer({ "EQUIPPED", slotType }, weaponId)
	return true
end

function PlayerDataTable.getEquippedSkin(weaponId: string): string?
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	return src and src.EQUIPPED_SKINS and src.EQUIPPED_SKINS[weaponId] or nil
end

function PlayerDataTable.setEquippedSkin(weaponId: string, skinId: string?): boolean
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src then
		return false
	end
	if not src.EQUIPPED_SKINS then
		src.EQUIPPED_SKINS = {}
	end
	local oldValue = src.EQUIPPED_SKINS[weaponId]
	if not replicaData then
		src.EQUIPPED_SKINS[weaponId] = skinId
	end
	PlayerDataTable._fireCallbacks("EquippedSkin", weaponId, skinId, oldValue)
	PlayerDataTable._savePathToServer({ "EQUIPPED_SKINS", weaponId }, skinId)
	return true
end

function PlayerDataTable.get(category: string, key: string): any
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	local categoryData = src and src.Settings and src.Settings[category]
	if not categoryData then
		return nil
	end

	if not categoryData then
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
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src or not src.Settings then
		return false
	end
	local categoryData = src.Settings[category]
	if not categoryData then
		return false
	end
	local oldValue = categoryData[key]
	if not replicaData then
		categoryData[key] = deepClone(value)
	end
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

function PlayerDataTable.getConflicts(
	keyCode: Enum.KeyCode,
	excludeKey: string?,
	excludeSlot: string?
): { { settingKey: string, slot: string } }
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	local conflicts = {}
	local controlsData = src and src.Settings and src.Settings.Controls
	if not controlsData then
		return conflicts
	end

	for settingKey, binds in controlsData do
		if typeof(binds) ~= "table" then
			continue
		end

		for slot, boundKey in binds do
			if boundKey == keyCode then
				if settingKey == excludeKey and slot == excludeSlot then
					continue
				end
				table.insert(conflicts, { settingKey = settingKey, slot = slot })
			end
		end
	end

	return conflicts
end

function PlayerDataTable.resetCategory(category: string): boolean
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src or not src.Settings then
		return false
	end
	local defaults = SettingsConfig.DefaultSettings
	local categoryDefaults = defaults[category]
	if not categoryDefaults then
		return false
	end
	local newCategory = {}
	for key, value in categoryDefaults do
		newCategory[key] = deepClone(value)
		PlayerDataTable._fireCallbacks(category, key, newCategory[key], nil)
	end
	if not replicaData then
		src.Settings[category] = newCategory
	end
	PlayerDataTable._savePathToServer({ "Settings", category }, newCategory)
	return true
end

function PlayerDataTable.getAllSettings(): { [string]: { [string]: any } }
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	return src and deepClone(src.Settings or {}) or {}
end

function PlayerDataTable.onChanged(
	callback: (category: string, key: string, newValue: any, oldValue: any) -> ()
): () -> ()
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

local function getNet()
	local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
	return require(Locations.Shared:WaitForChild("Net"):WaitForChild("Net"))
end

function PlayerDataTable._savePathToServer(path: { string }, value: any)
	if not RunService:IsClient() or type(path) ~= "table" or #path == 0 then
		return
	end
	local ok, net = pcall(getNet)
	if ok and net and net.FireServer then
		net:FireServer("PlayerDataUpdate", path, value)
	end
end

function PlayerDataTable._saveToServer(category: string, key: string, value: any)
	PlayerDataTable._savePathToServer({ "Settings", category, key }, value)
end

function PlayerDataTable._saveCategoryToServer(category: string)
	local src = getDataSource()
	if not src or not src.Settings or not src.Settings[category] then
		return
	end
	for key, value in src.Settings[category] do
		PlayerDataTable._savePathToServer({ "Settings", category, key }, value)
	end
end

-- Emote System Methods

function PlayerDataTable.getEquippedEmotes(): { [string]: string? }
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	return src and deepClone(src.EQUIPPED_EMOTES or {}) or {}
end

function PlayerDataTable.setEquippedEmote(slot: string, emoteId: string?): boolean
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src then
		return false
	end
	if not src.EQUIPPED_EMOTES then
		src.EQUIPPED_EMOTES = {}
	end
	local oldValue = src.EQUIPPED_EMOTES[slot]
	if not replicaData then
		src.EQUIPPED_EMOTES[slot] = emoteId
	end
	PlayerDataTable._fireCallbacks("EquippedEmote", slot, emoteId, oldValue)
	PlayerDataTable._savePathToServer({ "EQUIPPED_EMOTES", slot }, emoteId)
	return true
end

function PlayerDataTable.isEmoteOwned(emoteId: string): boolean
	return PlayerDataTable.isOwned("OWNED_EMOTES", emoteId)
end

function PlayerDataTable.getOwnedEmotes(): { string }
	return PlayerDataTable.getOwned("OWNED_EMOTES")
end

function PlayerDataTable.addOwnedEmote(emoteId: string): boolean
	return PlayerDataTable.addOwned("OWNED_EMOTES", emoteId)
end

-- Weapon Data Methods

function PlayerDataTable.getWeaponData(weaponId: string): { [string]: any }?
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src or not src.WEAPON_DATA then
		return nil
	end
	return deepClone(src.WEAPON_DATA[weaponId])
end

function PlayerDataTable.setWeaponData(weaponId: string, data: { [string]: any }): boolean
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src then
		return false
	end
	if not src.WEAPON_DATA then
		src.WEAPON_DATA = {}
	end
	local oldValue = src.WEAPON_DATA[weaponId]
	if not replicaData then
		src.WEAPON_DATA[weaponId] = deepClone(data)
	end
	PlayerDataTable._fireCallbacks("WeaponData", weaponId, data, oldValue)
	PlayerDataTable._savePathToServer({ "WEAPON_DATA", weaponId }, data)
	return true
end

function PlayerDataTable.getWeaponKillEffect(weaponId: string): string?
	local data = PlayerDataTable.getWeaponData(weaponId)
	return data and data.killEffect or nil
end

function PlayerDataTable.setWeaponKillEffect(weaponId: string, killEffect: string?): boolean
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	if not src then
		return false
	end
	if not src.WEAPON_DATA then
		src.WEAPON_DATA = {}
	end
	if not src.WEAPON_DATA[weaponId] then
		src.WEAPON_DATA[weaponId] = {}
	end
	local oldEffect = src.WEAPON_DATA[weaponId].killEffect
	if not replicaData then
		src.WEAPON_DATA[weaponId].killEffect = killEffect
	end
	PlayerDataTable._fireCallbacks("WeaponKillEffect", weaponId, killEffect, oldEffect)
	PlayerDataTable._savePathToServer({ "WEAPON_DATA", weaponId }, src.WEAPON_DATA[weaponId])
	return true
end

function PlayerDataTable.getAllWeaponData(): { [string]: { [string]: any } }
	if not getDataSource() then
		PlayerDataTable.init()
	end
	local src = getDataSource()
	return src and deepClone(src.WEAPON_DATA or {}) or {}
end

return PlayerDataTable
