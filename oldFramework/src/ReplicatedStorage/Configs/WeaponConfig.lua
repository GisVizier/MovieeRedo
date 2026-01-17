local WeaponConfig = {}

-- =============================================================================
-- DEFAULT WEAPON SPAWN
-- =============================================================================

WeaponConfig.DefaultWeapon = {
	Type = "Gun", -- "Gun" or "Melee"
	Name = "Shotgun", -- "Revolver", "Shotgun", "Knife", etc.
}

-- =============================================================================
-- WEAPON SWAP SETTINGS
-- =============================================================================

WeaponConfig.WeaponSwap = {
	Enabled = false, -- Allow players to swap weapons
	SwapKey = Enum.KeyCode.Q, -- Key to swap weapons (PC)
	SwapCooldown = 0.5, -- Cooldown between swaps (seconds)
}

-- =============================================================================
-- WEAPON PICKUP SETTINGS
-- =============================================================================

WeaponConfig.WeaponPickup = {
	Enabled = false, -- Allow picking up weapons from world
	InteractionKey = Enum.KeyCode.E, -- Key to pick up weapons
	InteractionDistance = 5, -- Max distance to pick up weapons (studs)
	DropOnDeath = false, -- Drop weapon when player dies
}

-- =============================================================================
-- WEAPON EQUIP SETTINGS
-- =============================================================================

WeaponConfig.Equip = {
	EquipAnimationTime = 0.5, -- Time for equip animation (seconds)
	UnequipAnimationTime = 0.3, -- Time for unequip animation (seconds)
}

return WeaponConfig
