--[[
	Shotgun.lua (Main Module)

	Main weapon module for the Shotgun.
	Provides initialization and any weapon-specific logic.
]]

local Shotgun = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)

--[[
	Initialize the Shotgun weapon
	Called when the weapon is first created
	@param weaponInstance table - The weapon instance
]]
function Shotgun.Initialize(weaponInstance)
	-- Set up any shotgun-specific state or properties
	weaponInstance.State.LastFireTime = 0

	-- Log initialization
	print("[Shotgun] Initialized for player:", weaponInstance.Player.Name)
end

--[[
	Can the shotgun fire?
	Uses BaseGun logic but can be overridden for shotgun-specific behavior
	@param weaponInstance table - The weapon instance
	@return boolean - Whether the shotgun can fire
]]
function Shotgun.CanFire(weaponInstance)
	-- Use base gun logic
	return BaseGun.CanFire(weaponInstance)
end

--[[
	Calculate damage for the shotgun
	@param weaponInstance table - The weapon instance
	@param distance number - Distance to target
	@param isHeadshot boolean - Whether this is a headshot
	@return number - Calculated damage
]]
function Shotgun.CalculateDamage(weaponInstance, distance, isHeadshot)
	-- Use base gun damage calculation
	return BaseGun.CalculateDamage(weaponInstance, distance, isHeadshot)
end

return Shotgun
