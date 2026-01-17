local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local CrosshairSystem = ReplicatedStorage:WaitForChild("Systems"):WaitForChild("Crosshair")
local CrosshairController = require(CrosshairSystem.CrosshairController)
local CrosshairConfig = require(Locations.Modules.Config.CrosshairConfig)

local CrosshairUIController = {}
CrosshairUIController.__index = CrosshairUIController

function CrosshairUIController:Init()
	self._controller = CrosshairController.new(Players.LocalPlayer)
	self._currentWeapon = nil
	self._customization = CrosshairConfig:GetDefaultCustomization()
	self._signalsConnected = false
	
	LogService:Info("CROSSHAIR_UI", "Initialized CrosshairUIController", {
		Player = Players.LocalPlayer and Players.LocalPlayer.Name or "nil"
	})
end

function CrosshairUIController:_setupSignalConnections()
	if self._signalsConnected then
		return
	end
	
	local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)
	local InventoryController = ServiceRegistry:GetController("InventoryController")
	
	if InventoryController then
		if InventoryController.WeaponEquipped then
			InventoryController.WeaponEquipped:connect(function(weaponName, weaponData)
				LogService:Debug("CROSSHAIR_UI", "WeaponEquipped signal received", { Weapon = weaponName })
				self:OnWeaponEquipped(weaponName, weaponData)
			end)
			LogService:Info("CROSSHAIR_UI", "Connected to WeaponEquipped signal")
		end

		if InventoryController.WeaponUnequipped then
			InventoryController.WeaponUnequipped:connect(function()
				self:RemoveCrosshair()
			end)
		end

		if InventoryController.WeaponFired then
			InventoryController.WeaponFired:connect(function(recoilData)
				if self._controller then
					self._controller:OnRecoil({ amount = recoilData.Recoil or 1 })
				end
			end)
		end
	end

	if self._controller then
		self._controller:SetCustomization(self._customization)
	end
	
	self._signalsConnected = true
end

function CrosshairUIController:OnCharacterSpawned(character)
	self:_setupSignalConnections()
	self:OnWeaponEquipped("Default", {})
end

function CrosshairUIController:OnWeaponEquipped(weaponName, weaponData)
	local crosshairType = CrosshairConfig:GetCrosshairType(weaponName)
	local spreadData = CrosshairConfig:GetWeaponData(weaponName)

	if self._controller then
		self._controller:ApplyCrosshair(crosshairType, spreadData)
		LogService:Debug("CROSSHAIR_UI", "Applied crosshair", {
			Weapon = weaponName,
			Type = crosshairType,
		})
	end
end

function CrosshairUIController:RemoveCrosshair()
	if self._controller then
		self._controller:RemoveCrosshair()
	end
end

function CrosshairUIController:UpdateCustomization(newCustomization)
	self._customization = newCustomization
	if self._controller then
		self._controller:SetCustomization(newCustomization)
	end
end

return CrosshairUIController
