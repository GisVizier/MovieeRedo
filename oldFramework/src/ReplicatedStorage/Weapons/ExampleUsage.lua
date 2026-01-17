--[[
	ExampleUsage.lua

	This file demonstrates how to use the Weapon System.
	This is for reference only - do NOT require this file in production code.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local WeaponManager = require(Locations.Modules.Weapons.Managers.WeaponManager)
local WeaponConfig = require(Locations.Modules.Weapons.Configs)

--[[
	Example 1: Initialize and equip a gun
]]
local function ExampleEquipGun(player)
	-- Initialize a Revolver for the player
	local revolverWeapon = WeaponManager:InitializeWeapon(player, "Gun", "Revolver")

	if revolverWeapon then
		print("Revolver initialized!")
		print("Ammo:", revolverWeapon.State.CurrentAmmo, "/", revolverWeapon.Config.Ammo.MagSize)
		print("Reserve:", revolverWeapon.State.ReserveAmmo)

		-- Equip the weapon
		WeaponManager:EquipWeapon(player, revolverWeapon)
	end

	return revolverWeapon
end

--[[
	Example 2: Fire a gun multiple times
]]
local function ExampleFireGun(player, weaponInstance)
	print("\n=== Firing Gun Example ===")

	-- Fire 3 shots
	for i = 1, 3 do
		print("\nShot", i)
		WeaponManager:AttackWeapon(player, weaponInstance)
		task.wait(0.5) -- Wait between shots
	end

	print("\nAmmo after firing:", weaponInstance.State.CurrentAmmo, "/", weaponInstance.Config.Ammo.MagSize)
end

--[[
	Example 3: Reload a gun
]]
local function ExampleReloadGun(player, weaponInstance)
	print("\n=== Reload Gun Example ===")

	print("Before reload - Mag:", weaponInstance.State.CurrentAmmo, "Reserve:", weaponInstance.State.ReserveAmmo)

	-- Reload the weapon
	WeaponManager:ReloadWeapon(player, weaponInstance)

	print("After reload - Mag:", weaponInstance.State.CurrentAmmo, "Reserve:", weaponInstance.State.ReserveAmmo)
end

--[[
	Example 4: Inspect a weapon
]]
local function ExampleInspectWeapon(player, weaponInstance)
	print("\n=== Inspect Weapon Example ===")

	WeaponManager:InspectWeapon(player, weaponInstance)
end

--[[
	Example 5: Initialize and use a melee weapon
]]
local function ExampleUseMelee(player)
	print("\n=== Melee Weapon Example ===")

	-- Initialize a Knife for the player
	local knifeWeapon = WeaponManager:InitializeWeapon(player, "Melee", "Knife")

	if knifeWeapon then
		print("Knife initialized!")

		-- Equip the weapon
		WeaponManager:EquipWeapon(player, knifeWeapon)

		-- Perform light attack
		print("\nPerforming light attack...")
		WeaponManager:AttackWeapon(player, knifeWeapon)

		task.wait(1)

		-- Perform another attack (combo)
		print("\nPerforming combo attack...")
		WeaponManager:AttackWeapon(player, knifeWeapon)

		-- Unequip
		task.wait(1)
		WeaponManager:UnequipWeapon(player, knifeWeapon)
	end

	return knifeWeapon
end

--[[
	Example 6: Switch between weapons
]]
local function ExampleWeaponSwitch(player)
	print("\n=== Weapon Switch Example ===")

	-- Initialize both weapons
	local revolverWeapon = WeaponManager:InitializeWeapon(player, "Gun", "Revolver")
	local knifeWeapon = WeaponManager:InitializeWeapon(player, "Melee", "Knife")

	-- Equip revolver
	print("\nEquipping Revolver...")
	WeaponManager:EquipWeapon(player, revolverWeapon)

	-- Check active weapon
	local activeWeapon = WeaponManager:GetActiveWeapon(player)
	print("Active weapon:", activeWeapon and activeWeapon.WeaponName or "None")

	task.wait(1)

	-- Switch to knife
	print("\nSwitching to Knife...")
	WeaponManager:UnequipWeapon(player, revolverWeapon)
	WeaponManager:EquipWeapon(player, knifeWeapon)

	-- Check active weapon again
	activeWeapon = WeaponManager:GetActiveWeapon(player)
	print("Active weapon:", activeWeapon and activeWeapon.WeaponName or "None")

	task.wait(1)

	-- Unequip all
	WeaponManager:UnequipWeapon(player, knifeWeapon)
end

--[[
	Example 7: Get weapon configuration
]]
local function ExampleGetConfig()
	print("\n=== Get Config Example ===")

	-- Get Revolver config
	local revolverConfig = WeaponConfig:GetWeaponConfig("Gun", "Revolver")
	if revolverConfig then
		print("Revolver Info:")
		print("  Display Name:", revolverConfig.WeaponInfo.DisplayName)
		print("  Body Damage:", revolverConfig.Damage.BodyDamage)
		print("  Headshot Damage:", revolverConfig.Damage.HeadshotDamage)
		print("  Mag Size:", revolverConfig.Ammo.MagSize)
		print("  RPM:", revolverConfig.FireRate.RPM)
	end

	-- Get Knife config
	local knifeConfig = WeaponConfig:GetWeaponConfig("Melee", "Knife")
	if knifeConfig then
		print("\nKnife Info:")
		print("  Display Name:", knifeConfig.WeaponInfo.DisplayName)
		print("  Body Damage:", knifeConfig.Damage.BodyDamage)
		print("  Headshot Damage:", knifeConfig.Damage.HeadshotDamage)
		print("  Range:", knifeConfig.Attack.Range)
	end

	-- Get all guns
	print("\nAll Guns:")
	local guns = WeaponConfig:GetWeaponsByType("Gun")
	for name, config in pairs(guns) do
		print("  -", name)
	end

	-- Get all melee weapons
	print("\nAll Melee:")
	local meleeWeapons = WeaponConfig:GetWeaponsByType("Melee")
	for name, config in pairs(meleeWeapons) do
		print("  -", name)
	end
end

--[[
	Example 8: Complete workflow
]]
local function ExampleCompleteWorkflow(player)
	print("\n=== Complete Workflow Example ===")

	-- 1. Initialize weapon
	local weapon = WeaponManager:InitializeWeapon(player, "Gun", "Revolver")

	-- 2. Equip weapon
	WeaponManager:EquipWeapon(player, weapon)

	-- 3. Fire some shots
	for i = 1, 3 do
		WeaponManager:AttackWeapon(player, weapon)
		task.wait(0.2)
	end

	-- 4. Reload
	WeaponManager:ReloadWeapon(player, weapon)

	-- 5. Fire more shots
	for i = 1, 2 do
		WeaponManager:AttackWeapon(player, weapon)
		task.wait(0.2)
	end

	-- 6. Inspect
	WeaponManager:InspectWeapon(player, weapon)

	-- 7. Unequip
	WeaponManager:UnequipWeapon(player, weapon)

	print("\nWorkflow complete!")
end

--[[
	Run all examples when a player joins
	(Remove this in production - this is for testing only!)
]]
--[[
Players.PlayerAdded:Connect(function(player)
	task.wait(2) -- Wait for character to load

	-- Run examples
	ExampleGetConfig()

	local revolverWeapon = ExampleEquipGun(player)
	if revolverWeapon then
		ExampleFireGun(player, revolverWeapon)
		ExampleReloadGun(player, revolverWeapon)
		ExampleInspectWeapon(player, revolverWeapon)
	end

	ExampleUseMelee(player)
	ExampleWeaponSwitch(player)
	ExampleCompleteWorkflow(player)
end)
]]

return {
	ExampleEquipGun = ExampleEquipGun,
	ExampleFireGun = ExampleFireGun,
	ExampleReloadGun = ExampleReloadGun,
	ExampleInspectWeapon = ExampleInspectWeapon,
	ExampleUseMelee = ExampleUseMelee,
	ExampleWeaponSwitch = ExampleWeaponSwitch,
	ExampleGetConfig = ExampleGetConfig,
	ExampleCompleteWorkflow = ExampleCompleteWorkflow,
}
