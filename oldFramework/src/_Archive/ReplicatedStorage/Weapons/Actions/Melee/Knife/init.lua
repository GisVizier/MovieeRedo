--[[
	Knife.lua (Main Module)

	Main weapon module for the Knife.
	Provides initialization and any weapon-specific logic.
]]

local Knife = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseMelee = require(Locations.Modules.Weapons.Actions.Melee.BaseMelee)

--[[
	Initialize the Knife weapon
	Called when the weapon is first created
	@param weaponInstance table - The weapon instance
]]
function Knife.Initialize(weaponInstance)
	-- Set up any knife-specific state or properties
	weaponInstance.State.LastAttackTime = 0
	weaponInstance.State.ComboCount = 0

	-- Log initialization
	print("[Knife] Initialized for player:", weaponInstance.Player.Name)
end

--[[
	Can the knife attack?
	Uses BaseMelee logic but can be overridden for knife-specific behavior
	@param weaponInstance table - The weapon instance
	@return boolean - Whether the knife can attack
]]
function Knife.CanAttack(weaponInstance)
	-- Use base melee logic
	return BaseMelee.CanAttack(weaponInstance)
end

--[[
	Calculate damage for the knife
	@param weaponInstance table - The weapon instance
	@param isHeadshot boolean - Whether this is a headshot
	@param attackType string - "Light" or "Heavy"
	@return number - Calculated damage
]]
function Knife.CalculateDamage(weaponInstance, isHeadshot, attackType)
	-- Use base melee damage calculation
	return BaseMelee.CalculateDamage(weaponInstance, isHeadshot, attackType)
end

return Knife
