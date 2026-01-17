local WeaponController = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local WeaponManager = require(Locations.Modules.Weapons.Managers.WeaponManager)
local LogService = require(Locations.Modules.Systems.Core.LogService)
local ServiceRegistry = require(Locations.Modules.Utils.ServiceRegistry)

local localPlayer = Players.LocalPlayer

WeaponController.CurrentWeapon = nil
WeaponController.CurrentWeaponName = nil
WeaponController.CurrentWeaponType = nil
WeaponController.CurrentSkin = nil
WeaponController.IsInputConnected = false
WeaponController.IsFiring = false
WeaponController.IsEquipping = false
WeaponController.EquipStartTime = 0
WeaponController.FireConnection = nil
WeaponController.BurstShotsFired = 0
WeaponController.ViewmodelController = nil

function WeaponController:Init()
	LogService:RegisterCategory("WEAPON", "Weapon system client-side management")

	self:SetupInput()

	LogService:Info("WEAPON", "WeaponController initialized")
end

function WeaponController:OnCharacterSpawned(character)
	LogService:Info("WEAPON", "Character spawned", { Character = character.Name })

	if not character or not character.Parent then
		LogService:Warn("WEAPON", "Character destroyed before weapon setup")
		return
	end

	self.ViewmodelController = ServiceRegistry:GetController("ViewmodelController")
end

function WeaponController:SetupInput()
	if self.IsInputConnected then
		LogService:Warn("WEAPON", "Input already connected")
		return
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:StartFiring()
		elseif input.KeyCode == Enum.KeyCode.R then
			self:ReloadWeapon()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:StopFiring()
		end
	end)

	self.IsInputConnected = true
	LogService:Info("WEAPON", "Weapon input connected (Left Mouse = Fire, R = Reload)")
end

function WeaponController:EquipWeapon(weaponType, weaponName, skinName)
	if self.CurrentWeapon then
		self:UnequipCurrentWeapon()
	end

	if not self.ViewmodelController then
		self.ViewmodelController = ServiceRegistry:GetController("ViewmodelController")
	end

	LogService:Info("WEAPON", "Equipping weapon", {
		Type = weaponType,
		Name = weaponName,
		Skin = skinName or "Default",
	})

	local weaponInstance = WeaponManager:InitializeWeapon(localPlayer, weaponType, weaponName)

	if not weaponInstance then
		LogService:Error("WEAPON", "Failed to initialize weapon", {
			Type = weaponType,
			Name = weaponName,
		})
		return false
	end

	WeaponManager:EquipWeapon(localPlayer, weaponInstance)

	self.CurrentWeapon = weaponInstance
	self.CurrentWeaponName = weaponName
	self.CurrentWeaponType = weaponType
	self.CurrentSkin = skinName or "Default"

	if self.ViewmodelController then
		self.ViewmodelController:CreateViewmodel(weaponName, self.CurrentSkin)

		self.IsEquipping = true
		self.EquipStartTime = tick()

		self.ViewmodelController:PlayAnimation("Equip")

		local equipTrack = self.ViewmodelController.ViewmodelAnimator:GetTrack("Equip")
		if equipTrack then
			local connection
			connection = equipTrack.Stopped:Connect(function()
				self.IsEquipping = false
				connection:Disconnect()
			end)

			task.delay(2, function()
				self.IsEquipping = false
			end)
		else
			self.IsEquipping = false
		end
	end

	LogService:Info("WEAPON", "Weapon equipped successfully", {
		Name = weaponName,
		Ammo = weaponInstance.Config.Ammo and weaponInstance.State.CurrentAmmo .. "/" .. weaponInstance.Config.Ammo.MagSize or "N/A",
	})

	return true
end

function WeaponController:UnequipCurrentWeapon()
	self:StopFiring()

	if self.CurrentWeapon then
		WeaponManager:UnequipWeapon(localPlayer, self.CurrentWeapon)
		self.CurrentWeapon = nil
		self.CurrentWeaponName = nil
		self.CurrentWeaponType = nil
	end

	if self.ViewmodelController and self.ViewmodelController:IsViewmodelActive() then
		self.ViewmodelController:DestroyViewmodel()
	end

	self.IsEquipping = false

	LogService:Info("WEAPON", "Weapon unequipped")
end

function WeaponController:CanFire()
	if not self.CurrentWeapon then
		return false
	end

	if self.IsEquipping then
		local viewmodelConfig = self.ViewmodelController and self.ViewmodelController:GetCurrentConfig()
		if viewmodelConfig and viewmodelConfig.CanFireDuringEquip then
			return true
		end
		return false
	end

	local inventoryController = ServiceRegistry:GetController("InventoryController")
	if inventoryController and not inventoryController:CanFire() then
		return false
	end

	return true
end

function WeaponController:StartFiring()
	if self.IsFiring then
		return
	end

	if not self:CanFire() then
		return
	end

	self.IsFiring = true

	if self.IsEquipping then
		self.IsEquipping = false
	end

	local fireMode = self.CurrentWeapon.Config.FireRate.FireMode

	if fireMode == "Semi" then
		self:FireWeapon()
	elseif fireMode == "Auto" then
		local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)

		self.FireConnection = RunService.Heartbeat:Connect(function()
			if not self.IsFiring then
				if self.FireConnection then
					self.FireConnection:Disconnect()
					self.FireConnection = nil
				end
				return
			end

			if not self.CurrentWeapon then
				self.IsFiring = false
				if self.FireConnection then
					self.FireConnection:Disconnect()
					self.FireConnection = nil
				end
				return
			end

			if self.CurrentWeapon.State.IsReloading then
				self.IsFiring = false
				if self.FireConnection then
					self.FireConnection:Disconnect()
					self.FireConnection = nil
				end
				return
			end

			local state = self.CurrentWeapon.State
			local cooldown = BaseGun.GetFireCooldown(self.CurrentWeapon)
			local currentTime = tick()

			if currentTime - state.LastFireTime >= cooldown then
				self:FireWeapon()
			end
		end)
	elseif fireMode == "Burst" then
		local burstConfig = self.CurrentWeapon.Config.FireRate

		self.BurstShotsFired = 0

		self.FireConnection = RunService.Heartbeat:Connect(function()
			if not self.CurrentWeapon then
				self.IsFiring = false
				if self.FireConnection then
					self.FireConnection:Disconnect()
					self.FireConnection = nil
				end
				return
			end

			if self.CurrentWeapon.State.IsReloading then
				self.IsFiring = false
				self.BurstShotsFired = 0
				if self.FireConnection then
					self.FireConnection:Disconnect()
					self.FireConnection = nil
				end
				return
			end

			if self.BurstShotsFired >= burstConfig.BurstCount then
				self.IsFiring = false
				self.BurstShotsFired = 0
				if self.FireConnection then
					self.FireConnection:Disconnect()
					self.FireConnection = nil
				end
				return
			end

			local state = self.CurrentWeapon.State
			local cooldown = burstConfig.BurstDelay or 0.1
			local currentTime = tick()

			if currentTime - state.LastFireTime >= cooldown then
				self:FireWeapon()
				self.BurstShotsFired = self.BurstShotsFired + 1
			end
		end)
	end
end

function WeaponController:StopFiring()
	self.IsFiring = false
	self.BurstShotsFired = 0

	if self.FireConnection then
		self.FireConnection:Disconnect()
		self.FireConnection = nil
	end
end

function WeaponController:FireWeapon()
	if not self.CurrentWeapon then
		LogService:Debug("WEAPON", "No weapon equipped")
		return
	end

	WeaponManager:AttackWeapon(localPlayer, self.CurrentWeapon)

	if self.ViewmodelController then
		self.ViewmodelController:PlayAnimation("Fire")
	end
end

function WeaponController:ReloadWeapon()
	if not self.CurrentWeapon then
		LogService:Debug("WEAPON", "No weapon equipped")
		return
	end

	WeaponManager:ReloadWeapon(localPlayer, self.CurrentWeapon)

	if self.ViewmodelController then
		self.ViewmodelController:PlayAnimation("Reload")
	end
end

function WeaponController:SetWeaponSkin(skinName)
	self.CurrentSkin = skinName

	if self.CurrentWeapon and self.ViewmodelController then
		self.ViewmodelController:DestroyViewmodel()
		self.ViewmodelController:CreateViewmodel(self.CurrentWeaponName, skinName)
	end

	LogService:Info("WEAPON", "Weapon skin changed", { Skin = skinName })
end

function WeaponController:GetCurrentWeight()
	if self.ViewmodelController then
		return self.ViewmodelController:GetCurrentWeight()
	end
	return 1.0
end

function WeaponController:GetCurrentWeapon()
	return self.CurrentWeapon
end

function WeaponController:GetCurrentWeaponName()
	return self.CurrentWeaponName
end

function WeaponController:IsWeaponEquipped()
	return self.CurrentWeapon ~= nil
end

return WeaponController
