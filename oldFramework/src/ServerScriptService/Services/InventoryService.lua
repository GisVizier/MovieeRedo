local InventoryService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local LoadoutConfig = require(ReplicatedStorage.Configs.LoadoutConfig)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

InventoryService.PlayerLoadouts = {}
InventoryService.PlayerEquippedSlot = {}

function InventoryService:Init()
	Log:RegisterCategory("INVENTORY", "Player inventory and loadout management")

	self:SetupListeners()

	Players.PlayerRemoving:Connect(function(player)
		self:ClearPlayerData(player)
	end)

	Log:Info("INVENTORY", "InventoryService initialized")
end

function InventoryService:SetupListeners()
	RemoteEvents:ConnectServer("RequestLoadout", function(player)
		self:SendLoadoutToPlayer(player)
	end)

	RemoteEvents:ConnectServer("SwitchWeapon", function(player, slotName)
		self:HandleWeaponSwitch(player, slotName)
	end)

	RemoteEvents:ConnectServer("UpdateLoadoutSlot", function(player, slotName, weaponData)
		self:HandleLoadoutUpdate(player, slotName, weaponData)
	end)
end

function InventoryService:InitializePlayerLoadout(player)
	local loadout = {}

	for slotName, defaultData in pairs(LoadoutConfig.DefaultLoadout) do
		loadout[slotName] = {
			WeaponType = defaultData.WeaponType,
			WeaponName = defaultData.WeaponName,
			SkinName = defaultData.SkinName or "Default",
		}
	end

	self.PlayerLoadouts[player.UserId] = loadout
	self.PlayerEquippedSlot[player.UserId] = "Primary"

	Log:Info("INVENTORY", "Initialized loadout for player", {
		Player = player.Name,
		PrimaryWeapon = loadout.Primary and loadout.Primary.WeaponName or "NONE",
		SecondaryWeapon = loadout.Secondary and loadout.Secondary.WeaponName or "NONE",
		EquippedSlot = "Primary",
	})
	
	print("[SERVER DEBUG] Loadout initialized - Primary:", loadout.Primary and loadout.Primary.WeaponName, "Secondary:", loadout.Secondary and loadout.Secondary.WeaponName)

	return loadout
end

function InventoryService:GetPlayerLoadout(player)
	local loadout = self.PlayerLoadouts[player.UserId]
	if not loadout then
		loadout = self:InitializePlayerLoadout(player)
	end
	return loadout
end

function InventoryService:GetPlayerEquippedSlot(player)
	return self.PlayerEquippedSlot[player.UserId] or "Primary"
end

function InventoryService:GetEquippedWeapon(player)
	local loadout = self:GetPlayerLoadout(player)
	local equippedSlot = self:GetPlayerEquippedSlot(player)
	return loadout[equippedSlot], equippedSlot
end

function InventoryService:SendLoadoutToPlayer(player)
	local loadout = self:GetPlayerLoadout(player)
	local equippedSlot = self:GetPlayerEquippedSlot(player)

	RemoteEvents:FireClient("LoadoutData", player, {
		Loadout = loadout,
		EquippedSlot = equippedSlot,
	})

	Log:Debug("INVENTORY", "Sent loadout to player", {
		Player = player.Name,
		EquippedSlot = equippedSlot,
	})
end

function InventoryService:HandleWeaponSwitch(player, slotName)
	if not LoadoutConfig.Slots[slotName] then
		Log:Warn("INVENTORY", "Invalid slot name", { Player = player.Name, Slot = slotName })
		return
	end

	local loadout = self:GetPlayerLoadout(player)
	local slotData = loadout[slotName]

	if not slotData or not slotData.WeaponName then
		Log:Warn("INVENTORY", "No weapon in slot", { Player = player.Name, Slot = slotName })
		return
	end

	local previousSlot = self.PlayerEquippedSlot[player.UserId]
	self.PlayerEquippedSlot[player.UserId] = slotName

	RemoteEvents:FireClient("WeaponSwitched", player, {
		Slot = slotName,
		WeaponType = slotData.WeaponType,
		WeaponName = slotData.WeaponName,
		SkinName = slotData.SkinName,
		PreviousSlot = previousSlot,
	})

	Log:Info("INVENTORY", "Player switched weapon", {
		Player = player.Name,
		FromSlot = previousSlot,
		ToSlot = slotName,
		Weapon = slotData.WeaponName,
	})
end

function InventoryService:HandleLoadoutUpdate(player, slotName, weaponData)
	if not LoadoutConfig.Slots[slotName] then
		Log:Warn("INVENTORY", "Invalid slot name for update", { Player = player.Name, Slot = slotName })
		return
	end

	if weaponData.WeaponName and not LoadoutConfig:IsWeaponAllowedInSlot(weaponData.WeaponName, slotName) then
		Log:Warn("INVENTORY", "Weapon not allowed in slot", {
			Player = player.Name,
			Weapon = weaponData.WeaponName,
			Slot = slotName,
		})
		return
	end

	local loadout = self:GetPlayerLoadout(player)
	loadout[slotName] = {
		WeaponType = weaponData.WeaponType,
		WeaponName = weaponData.WeaponName,
		SkinName = weaponData.SkinName or "Default",
	}

	self:SendLoadoutToPlayer(player)

	Log:Info("INVENTORY", "Updated loadout slot", {
		Player = player.Name,
		Slot = slotName,
		WeaponData = weaponData,
	})
end

function InventoryService:ResetPlayerLoadout(player)
	self:InitializePlayerLoadout(player)
	self:SendLoadoutToPlayer(player)

	Log:Info("INVENTORY", "Reset loadout for player", { Player = player.Name })
end

function InventoryService:ClearPlayerData(player)
	self.PlayerLoadouts[player.UserId] = nil
	self.PlayerEquippedSlot[player.UserId] = nil

	Log:Debug("INVENTORY", "Cleared inventory data for player", { Player = player.Name })
end

function InventoryService:SetEquippedSlot(player, slotName)
	if LoadoutConfig.Slots[slotName] then
		self.PlayerEquippedSlot[player.UserId] = slotName
	end
end

function InventoryService:CanPlayerFire(player)
	return true
end

return InventoryService
