--[[
	ThirdPersonWeaponManager.lua
	
	Manages third-person weapon models attached to character rigs.
	Weapon welding is currently disabled.
	
	Usage:
		local manager = ThirdPersonWeaponManager.new(rig)
		manager:EquipWeapon(weaponId) -- no-op when welding disabled
		manager:UnequipWeapon()
		manager:GetWeaponModel()
		manager:Destroy()
]]

local ThirdPersonWeaponManager = {}
ThirdPersonWeaponManager.__index = ThirdPersonWeaponManager

--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

function ThirdPersonWeaponManager.new(rig: Model)
	if not rig then
		return nil
	end
	
	local self = setmetatable({}, ThirdPersonWeaponManager)
	
	self.Rig = rig
	self.WeaponModel = nil
	self.WeaponId = nil
	self.Weld = nil
	
	return self
end

--------------------------------------------------------------------------------
-- WEAPON MANAGEMENT
--------------------------------------------------------------------------------

--[[
	Equip a weapon by ID.

	Weapon welding is disabled; this is a no-op that always succeeds.

	@param weaponId - Weapon identifier (e.g., "Shotgun")
	@return boolean - Success
]]
function ThirdPersonWeaponManager:EquipWeapon(weaponId: string): boolean
	self:UnequipWeapon()
	self.WeaponId = weaponId
	return true
end

--[[
	Unequip current weapon.
]]
function ThirdPersonWeaponManager:UnequipWeapon()
	if self.Weld then
		self.Weld:Destroy()
		self.Weld = nil
	end
	
	if self.WeaponModel then
		self.WeaponModel:Destroy()
		self.WeaponModel = nil
	end
	
	self.WeaponId = nil
end

--[[
	Get the current weapon model.
]]
function ThirdPersonWeaponManager:GetWeaponModel(): Model?
	return self.WeaponModel
end

--[[
	Get the current weapon ID.
]]
function ThirdPersonWeaponManager:GetWeaponId(): string?
	return self.WeaponId
end

--[[
	Check if a weapon is equipped.
]]
function ThirdPersonWeaponManager:HasWeapon(): boolean
	return self.WeaponModel ~= nil
end

--[[
	Cleanup.
]]
function ThirdPersonWeaponManager:Destroy()
	self:UnequipWeapon()
	self.Rig = nil
end

return ThirdPersonWeaponManager
