--[[
	Attack.lua (Knife)

	Handles attacking with the Knife weapon.
]]

local Attack = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Modules
local Locations = require(ReplicatedStorage.Modules.Locations)
local BaseMelee = require(Locations.Modules.Weapons.Actions.Melee.BaseMelee)

--[[
	Execute the attack action
	@param weaponInstance table - The weapon instance
	@param attackType string - "Light" or "Heavy" (optional, defaults to "Light")
]]
function Attack.Execute(weaponInstance, attackType)
	local player = weaponInstance.Player
	local config = weaponInstance.Config
	local state = weaponInstance.State

	-- Default to light attack
	attackType = attackType or "Light"

	-- Check if can attack
	if not BaseMelee.CanAttack(weaponInstance) then
		print("[Knife] Cannot attack - conditions not met")
		return
	end

	-- Check attack cooldown
	local currentTime = tick()
	local cooldown = BaseMelee.GetAttackCooldown(weaponInstance, attackType)

	if currentTime - state.LastAttackTime < cooldown then
		print("[Knife] Cooldown not ready")
		return
	end

	print("[Knife] Attacking for player:", player.Name, "Type:", attackType)

	-- Set attacking state
	state.IsAttacking = true
	state.LastAttackTime = currentTime

	-- Increment combo count
	state.ComboCount = state.ComboCount + 1

	-- Get attack duration
	local attackDuration = BaseMelee.GetAttackDuration(weaponInstance, attackType)

	-- TODO: Play attack animation based on combo count
	-- TODO: Play swing sound
	-- TODO: Enable weapon trail effect

	-- Perform hit detection
	-- TODO: Get player's camera look vector for attack direction
	-- TODO: Perform raycast or hitbox check
	-- TODO: Check for headshot, backstab
	-- TODO: Apply damage to hit target
	-- TODO: Play hit effect
	-- TODO: Apply camera shake

	-- Simulate attack duration
	task.wait(attackDuration)

	-- Clear attacking state
	state.IsAttacking = false

	-- Reset combo after a delay
	task.delay(1.0, function()
		if tick() - state.LastAttackTime >= 1.0 then
			state.ComboCount = 0
			print("[Knife] Combo reset")
		end
	end)
end

return Attack
