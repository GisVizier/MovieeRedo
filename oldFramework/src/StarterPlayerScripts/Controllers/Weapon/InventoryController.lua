local InventoryController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local RemoteEvents = require(Locations.Modules.RemoteEvents)
local LoadoutConfig = require(ReplicatedStorage.Configs.LoadoutConfig)
local Log = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
local Signal = require(Locations.Modules.Utils.Signal)

local LocalPlayer = Players.LocalPlayer

InventoryController.Loadout = nil
InventoryController.EquippedSlot = nil
InventoryController.CurrentWeaponName = nil
InventoryController.IsInitialized = false
InventoryController.IsSwitching = false
InventoryController.LastSwitchTime = 0
InventoryController.LastScrollTime = 0
InventoryController.ViewmodelController = nil

-- Signals for other systems to listen to
InventoryController.WeaponEquipped = Signal.new()
InventoryController.WeaponUnequipped = Signal.new()
InventoryController.WeaponFired = Signal.new()

function InventoryController:Init()
	Log:RegisterCategory("INVENTORY", "Client inventory and weapon switching")

	self:SetupRemoteListeners()
	self:SetupInputListeners()

	Log:Info("INVENTORY", "InventoryController initialized")
end

function InventoryController:SetupRemoteListeners()
	RemoteEvents:ConnectClient("LoadoutData", function(data)
		self:OnLoadoutReceived(data)
	end)

	RemoteEvents:ConnectClient("WeaponSwitched", function(data)
		self:OnWeaponSwitched(data)
	end)
end

function InventoryController:SetupInputListeners()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if LoadoutConfig.Switching.EnableNumberKeys then
			local slotName, _ = LoadoutConfig:GetSlotByKey(input.KeyCode)
			if slotName then
				self:RequestWeaponSwitch(slotName)
			end
		end
	end)

	if LoadoutConfig.Switching.EnableScrollWheel then
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				local currentTime = tick()
				if currentTime - self.LastScrollTime < LoadoutConfig.Switching.ScrollWheelCooldown then
					return
				end
				self.LastScrollTime = currentTime

				local direction = input.Position.Z > 0 and -1 or 1
				self:SwitchToNextSlot(direction)
			end
		end)
	end
end

function InventoryController:OnCharacterSpawned(character)
	self.ViewmodelController = ServiceRegistry:GetController("ViewmodelController")
	RemoteEvents:FireServer("RequestLoadout")

	Log:Info("INVENTORY", "Character spawned, requesting loadout")
end

function InventoryController:OnLoadoutReceived(data)
	self.Loadout = data.Loadout
	self.EquippedSlot = data.EquippedSlot
	self.IsInitialized = true

	Log:Info("INVENTORY", "Loadout received", {
		EquippedSlot = self.EquippedSlot,
		Primary = self.Loadout.Primary and self.Loadout.Primary.WeaponName,
		Secondary = self.Loadout.Secondary and self.Loadout.Secondary.WeaponName,
	})

	self:EquipCurrentSlot()
end

function InventoryController:OnWeaponSwitched(data)
	self.EquippedSlot = data.Slot
	self.IsSwitching = false

	Log:Info("INVENTORY", "Weapon switch confirmed", {
		Slot = data.Slot,
		Weapon = data.WeaponName,
	})

	self:EquipWeaponFromData(data)
end

function InventoryController:EquipCurrentSlot()
	if not self.IsInitialized or not self.Loadout then
		return
	end

	local slotData = self.Loadout[self.EquippedSlot]
	if not slotData then
		return
	end

	self:EquipWeaponFromData({
		WeaponType = slotData.WeaponType,
		WeaponName = slotData.WeaponName,
		SkinName = slotData.SkinName,
		Slot = self.EquippedSlot,
	})
end

function InventoryController:EquipWeaponFromData(data)
	Log:Info("INVENTORY", "EquipWeaponFromData called", {
		WeaponType = data.WeaponType,
		WeaponName = data.WeaponName,
		SkinName = data.SkinName,
		Slot = data.Slot,
	})

	if not self.ViewmodelController then
		self.ViewmodelController = ServiceRegistry:GetController("ViewmodelController")
	end

	if not self.ViewmodelController then
		Log:Warn("INVENTORY", "ViewmodelController not found")
		return
	end

	-- Fire unequip signal for previous weapon
	if self.CurrentWeaponName then
		self.WeaponUnequipped:fire(self.CurrentWeaponName)
	end

	if self.ViewmodelController:IsViewmodelActive() then
		self.ViewmodelController:DestroyViewmodel()
	end

	self.CurrentWeaponName = data.WeaponName
	Log:Info("INVENTORY", "Creating viewmodel for weapon", { Weapon = data.WeaponName })
	self.ViewmodelController:Create(LocalPlayer, data.WeaponName)

	Log:Info("INVENTORY", "Weapon equipped", { Weapon = data.WeaponName })
	
	-- Fire equip signal for crosshairs and other systems
	self.WeaponEquipped:fire(data.WeaponName, {
		WeaponType = data.WeaponType,
		WeaponName = data.WeaponName,
		SkinName = data.SkinName,
		Slot = data.Slot,
	})
end

function InventoryController:RequestWeaponSwitch(slotName)
	if not self.IsInitialized then
		return
	end

	if self.EquippedSlot == slotName then
		return
	end

	local currentTime = tick()
	if currentTime - self.LastSwitchTime < LoadoutConfig.Switching.SwitchCooldown then
		return
	end

	if self.IsSwitching then
		return
	end

	self.IsSwitching = true
	self.LastSwitchTime = currentTime

	RemoteEvents:FireServer("SwitchWeapon", slotName)

	Log:Debug("INVENTORY", "Requesting weapon switch", { ToSlot = slotName })
end

function InventoryController:SwitchToNextSlot(direction)
	if not self.IsInitialized or not self.EquippedSlot then
		return
	end

	local weaponSlots = { "Primary", "Secondary" }
	local currentIndex = 1

	for i, slot in ipairs(weaponSlots) do
		if slot == self.EquippedSlot then
			currentIndex = i
			break
		end
	end

	local nextIndex = currentIndex + direction
	if nextIndex < 1 then
		nextIndex = #weaponSlots
	elseif nextIndex > #weaponSlots then
		nextIndex = 1
	end

	local nextSlot = weaponSlots[nextIndex]
	self:RequestWeaponSwitch(nextSlot)
end

function InventoryController:GetCurrentSlot()
	return self.EquippedSlot
end

function InventoryController:GetCurrentWeaponName()
	return self.CurrentWeaponName
end

function InventoryController:GetLoadout()
	return self.Loadout
end

function InventoryController:IsWeaponEquipped()
	return self.CurrentWeaponName ~= nil
end

return InventoryController
