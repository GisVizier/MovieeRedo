--[[
	SniperRifle.lua (Main Module)

	Main weapon module for the SniperRifle.
	Provides initialization and any weapon-specific logic.
]]

local SniperRifle = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseGun = require(Locations.Modules.Weapons.Actions.Gun.BaseGun)

--[[
	Initialize the SniperRifle weapon
	Called when the weapon is first created
	@param weaponInstance table - The weapon instance
]]
function SniperRifle.Initialize(weaponInstance)
	-- Set up any revolver-specific state or properties
	weaponInstance.State.LastFireTime = 0

	-- Log initialization
	print("[SniperRifle] Initialized for player:", weaponInstance.Player.Name)
end

--[[
	Can the revolver fire?
	Uses BaseGun logic but can be overridden for revolver-specific behavior
	@param weaponInstance table - The weapon instance
	@return boolean - Whether the revolver can fire
]]
function SniperRifle.CanFire(weaponInstance)
	-- Use base gun logic
	return BaseGun.CanFire(weaponInstance)
end

--[[
	Calculate damage for the revolver
	@param weaponInstance table - The weapon instance
	@param distance number - Distance to target
	@param isHeadshot boolean - Whether this is a headshot
	@return number - Calculated damage
]]
function SniperRifle.CalculateDamage(weaponInstance, distance, isHeadshot)
	-- Use base gun damage calculation
	return BaseGun.CalculateDamage(weaponInstance, distance, isHeadshot)
end

return SniperRifle
