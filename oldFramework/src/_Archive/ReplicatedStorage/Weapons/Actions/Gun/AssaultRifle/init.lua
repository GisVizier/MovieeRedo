--[[
	AssaultRifle.lua (Main Module)

	Main weapon module for the AssaultRifle.
	Provides initialization and any weapon-specific logic.
]]

local AssaultRifle = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)

--[[
	Initialize the AssaultRifle weapon
	Called when the weapon is first created
	@param weaponInstance table - The weapon instance
]]
function AssaultRifle.Initialize(weaponInstance)
	-- Set up any AssaultRifle-specific state or properties
	weaponInstance.State.LastFireTime = 0

	-- Log initialization
	print("[AssaultRifle] Initialized for player:", weaponInstance.Player.Name)
end

--[[
	Can the AssaultRifle fire?
	Uses BaseGun logic but can be overridden for AssaultRifle-specific behavior
	@param weaponInstance table - The weapon instance
	@return boolean - Whether the AssaultRifle can fire
]]
function AssaultRifle.CanFire(weaponInstance)
	-- Use base gun logic
	return BaseGun.CanFire(weaponInstance)
end

--[[
	Calculate damage for the AssaultRifle
	@param weaponInstance table - The weapon instance
	@param distance number - Distance to target
	@param isHeadshot boolean - Whether this is a headshot
	@return number - Calculated damage
]]
function AssaultRifle.CalculateDamage(weaponInstance, distance, isHeadshot)
	-- Use base gun damage calculation
	return BaseGun.CalculateDamage(weaponInstance, distance, isHeadshot)
end

return AssaultRifle
