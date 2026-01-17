--[[
	WeaponManager.lua

	Central weapon management system that handles:
	- Dynamic loading of weapon modules and their action scripts
	- Weapon initialization and lifecycle management
	- Centralized API for weapon operations (Equip, Attack, Reload, etc.)

	Usage:
		local WeaponManager = require(Locations.Modules.Weapons.Managers.WeaponManager)

		-- Initialize a weapon for a player
		local weapon = WeaponManager:InitializeWeapon(player, "Gun", "Revolver")

		-- Call weapon actions
		WeaponManager:EquipWeapon(player, weapon)
		WeaponManager:AttackWeapon(player, weapon)
		WeaponManager:UnequipWeapon(player, weapon)
]]

local WeaponManager = {}
WeaponManager.__index = WeaponManager

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Module paths (will be set via Locations after initial load)
local Locations = require(ReplicatedStorage.Modules.Locations)
local WeaponConfig = require(Locations.Modules.Weapons.Configs)

-- Active weapons per player (player -> weapon instance)
local activeWeapons = {}

-- Cached weapon modules (weaponType -> weaponName -> module)
local weaponModuleCache = {}

-- Cached action modules (weaponType -> weaponName -> actionName -> module)
local actionModuleCache = {}

--[[
	Load a weapon's main module dynamically
	@param weaponType string - "Gun" or "Melee"
	@param weaponName string - Name of the weapon (e.g., "Revolver")
	@return table - The weapon module
]]
function WeaponManager:LoadWeaponModule(weaponType, weaponName)
	-- Check cache first
	if weaponModuleCache[weaponType] and weaponModuleCache[weaponType][weaponName] then
		return weaponModuleCache[weaponType][weaponName]
	end

	-- Build path to weapon module
	local weaponPath = Locations.Modules.Weapons.Actions[weaponType][weaponName]
	if not weaponPath then
		warn("[WeaponManager] Weapon module not found:", weaponType, weaponName)
		return nil
	end

	-- Load the module
	local success, weaponModule = pcall(function()
		return require(weaponPath)
	end)

	if not success then
		warn("[WeaponManager] Failed to load weapon module:", weaponType, weaponName, weaponModule)
		return nil
	end

	-- Cache the module
	if not weaponModuleCache[weaponType] then
		weaponModuleCache[weaponType] = {}
	end
	weaponModuleCache[weaponType][weaponName] = weaponModule

	return weaponModule
end

--[[
	Load a weapon action script dynamically
	@param weaponType string - "Gun" or "Melee"
	@param weaponName string - Name of the weapon
	@param actionName string - Action name ("Equip", "Attack", "Reload", etc.)
	@return table - The action module
]]
function WeaponManager:LoadActionModule(weaponType, weaponName, actionName)
	-- Check cache first
	if
		actionModuleCache[weaponType]
		and actionModuleCache[weaponType][weaponName]
		and actionModuleCache[weaponType][weaponName][actionName]
	then
		return actionModuleCache[weaponType][weaponName][actionName]
	end

	-- Build path to action module
	local weaponPath = Locations.Modules.Weapons.Actions[weaponType][weaponName]
	if not weaponPath then
		warn("[WeaponManager] Weapon path not found for action:", weaponType, weaponName, actionName)
		return nil
	end

	local actionPath = weaponPath:FindFirstChild(actionName)
	if not actionPath then
		warn("[WeaponManager] Action module not found:", weaponType, weaponName, actionName)
		return nil
	end

	-- Load the action module
	local success, actionModule = pcall(function()
		return require(actionPath)
	end)

	if not success then
		warn("[WeaponManager] Failed to load action module:", weaponType, weaponName, actionName, actionModule)
		return nil
	end

	-- Cache the action module
	if not actionModuleCache[weaponType] then
		actionModuleCache[weaponType] = {}
	end
	if not actionModuleCache[weaponType][weaponName] then
		actionModuleCache[weaponType][weaponName] = {}
	end
	actionModuleCache[weaponType][weaponName][actionName] = actionModule

	return actionModule
end

--[[
	Initialize a weapon for a player
	@param player Player - The player to initialize the weapon for
	@param weaponType string - "Gun" or "Melee"
	@param weaponName string - Name of the weapon
	@return table - Weapon instance data
]]
function WeaponManager:InitializeWeapon(player, weaponType, weaponName)
	-- Get weapon config
	local config = WeaponConfig:GetWeaponConfig(weaponType, weaponName)
	if not config then
		warn("[WeaponManager] Failed to get config for weapon:", weaponType, weaponName)
		return nil
	end

	-- Load weapon module
	local weaponModule = self:LoadWeaponModule(weaponType, weaponName)
	if not weaponModule then
		warn("[WeaponManager] Failed to load weapon module:", weaponType, weaponName)
		return nil
	end

	-- Create weapon instance
	local weaponInstance = {
		Player = player,
		WeaponType = weaponType,
		WeaponName = weaponName,
		Config = config,
		Module = weaponModule,
		State = {
			Equipped = false,
			CurrentAmmo = config.Ammo and config.Ammo.MagSize or 0,
			ReserveAmmo = config.Ammo and config.Ammo.DefaultReserveAmmo or 0,
			IsReloading = false,
			IsAttacking = false,
		},
	}

	-- Call weapon's Initialize function if it exists
	if weaponModule.Initialize then
		weaponModule.Initialize(weaponInstance)
	end

	return weaponInstance
end

--[[
	Equip a weapon for a player
	@param player Player
	@param weaponInstance table - Weapon instance from InitializeWeapon
]]
function WeaponManager:EquipWeapon(player, weaponInstance)
	if not weaponInstance then
		warn("[WeaponManager] Invalid weapon instance")
		return
	end

	-- Load and call the Equip action
	local equipModule = self:LoadActionModule(weaponInstance.WeaponType, weaponInstance.WeaponName, "Equip")
	if equipModule and equipModule.Execute then
		equipModule.Execute(weaponInstance)
		weaponInstance.State.Equipped = true
		activeWeapons[player] = weaponInstance
	else
		warn("[WeaponManager] Equip action not found for:", weaponInstance.WeaponType, weaponInstance.WeaponName)
	end
end

--[[
	Unequip a weapon for a player
	@param player Player
	@param weaponInstance table - Weapon instance
]]
function WeaponManager:UnequipWeapon(player, weaponInstance)
	if not weaponInstance then
		warn("[WeaponManager] Invalid weapon instance")
		return
	end

	-- Load and call the Unequip action
	local unequipModule = self:LoadActionModule(weaponInstance.WeaponType, weaponInstance.WeaponName, "Unequip")
	if unequipModule and unequipModule.Execute then
		unequipModule.Execute(weaponInstance)
		weaponInstance.State.Equipped = false
		activeWeapons[player] = nil
	else
		warn("[WeaponManager] Unequip action not found for:", weaponInstance.WeaponType, weaponInstance.WeaponName)
	end
end

--[[
	Execute an attack with the weapon
	@param player Player
	@param weaponInstance table - Weapon instance
]]
function WeaponManager:AttackWeapon(player, weaponInstance)
	if not weaponInstance or not weaponInstance.State.Equipped then
		warn("[WeaponManager] Cannot attack - weapon not equipped")
		return
	end

	-- Load and call the Attack action
	local attackModule = self:LoadActionModule(weaponInstance.WeaponType, weaponInstance.WeaponName, "Attack")
	if attackModule and attackModule.Execute then
		attackModule.Execute(weaponInstance)
	else
		warn("[WeaponManager] Attack action not found for:", weaponInstance.WeaponType, weaponInstance.WeaponName)
	end
end

--[[
	Reload a gun weapon
	@param player Player
	@param weaponInstance table - Weapon instance
]]
function WeaponManager:ReloadWeapon(player, weaponInstance)
	if not weaponInstance or not weaponInstance.State.Equipped then
		warn("[WeaponManager] Cannot reload - weapon not equipped")
		return
	end

	-- Only guns can reload
	if weaponInstance.WeaponType ~= "Gun" then
		return
	end

	-- Load and call the Reload action
	local reloadModule = self:LoadActionModule(weaponInstance.WeaponType, weaponInstance.WeaponName, "Reload")
	if reloadModule and reloadModule.Execute then
		reloadModule.Execute(weaponInstance)
	else
		warn("[WeaponManager] Reload action not found for:", weaponInstance.WeaponType, weaponInstance.WeaponName)
	end
end

--[[
	Inspect a weapon (play inspect animation)
	@param player Player
	@param weaponInstance table - Weapon instance
]]
function WeaponManager:InspectWeapon(player, weaponInstance)
	if not weaponInstance or not weaponInstance.State.Equipped then
		warn("[WeaponManager] Cannot inspect - weapon not equipped")
		return
	end

	-- Load and call the Inspect action
	local inspectModule = self:LoadActionModule(weaponInstance.WeaponType, weaponInstance.WeaponName, "Inspect")
	if inspectModule and inspectModule.Execute then
		inspectModule.Execute(weaponInstance)
	else
		warn("[WeaponManager] Inspect action not found for:", weaponInstance.WeaponType, weaponInstance.WeaponName)
	end
end

--[[
	Get the active weapon for a player
	@param player Player
	@return table - Weapon instance or nil
]]
function WeaponManager:GetActiveWeapon(player)
	return activeWeapons[player]
end

--[[
	Clear a player's active weapon (cleanup on disconnect)
	@param player Player
]]
function WeaponManager:ClearPlayerWeapon(player)
	activeWeapons[player] = nil
end

return WeaponManager
