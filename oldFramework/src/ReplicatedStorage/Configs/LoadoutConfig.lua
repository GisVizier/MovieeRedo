local LoadoutConfig = {}

LoadoutConfig.Slots = {
	Primary = {
		Index = 1,
		Key = Enum.KeyCode.One,
		DisplayName = "Primary",
		AllowedWeaponTypes = { "Gun" },
		AllowedWeapons = { "Shotgun", "AssaultRifle", "SniperRifle" },
	},

	Secondary = {
		Index = 2,
		Key = Enum.KeyCode.Two,
		DisplayName = "Secondary",
		AllowedWeaponTypes = { "Gun", "Melee" },
		AllowedWeapons = { "Revolver", "Knife" },
	},
}

LoadoutConfig.SlotOrder = { "Primary", "Secondary" }

LoadoutConfig.DefaultLoadout = {
	Primary = {
		WeaponType = "Melee",
		WeaponName = "Fist",
		SkinName = "Default",
	},

	Secondary = {
		WeaponType = "Gun",
		WeaponName = "Revolver",
		SkinName = "Default",
	},
}

LoadoutConfig.WeaponSlotMapping = {
	Shotgun = "Primary",
	AssaultRifle = "Primary",
	SniperRifle = "Primary",

	Revolver = "Secondary",
	Knife = "Secondary",
}

LoadoutConfig.Switching = {
	EnableScrollWheel = true,
	ScrollWheelCooldown = 0.15,

	EnableNumberKeys = true,

	SwitchCooldown = 0.1,

	PlayEquipAnimation = true,
	CanCancelEquipByFiring = true,
}

LoadoutConfig.Persistence = {
	ResetOnDeath = false,
	ResetOnRound = true,
	SaveBetweenSessions = false,
}

function LoadoutConfig:GetSlotByIndex(index)
	for slotName, slotData in pairs(self.Slots) do
		if slotData.Index == index then
			return slotName, slotData
		end
	end
	return nil, nil
end

function LoadoutConfig:GetSlotByKey(keyCode)
	for slotName, slotData in pairs(self.Slots) do
		if slotData.Key == keyCode then
			return slotName, slotData
		end
	end
	return nil, nil
end

function LoadoutConfig:GetSlotForWeapon(weaponName)
	return self.WeaponSlotMapping[weaponName]
end

function LoadoutConfig:IsWeaponAllowedInSlot(weaponName, slotName)
	local slot = self.Slots[slotName]
	if not slot then
		return false
	end

	for _, allowedWeapon in ipairs(slot.AllowedWeapons) do
		if allowedWeapon == weaponName then
			return true
		end
	end

	return false
end

function LoadoutConfig:GetDefaultForSlot(slotName)
	return self.DefaultLoadout[slotName]
end

function LoadoutConfig:GetNextSlot(currentSlot, direction)
	local currentIndex = self.Slots[currentSlot] and self.Slots[currentSlot].Index or 1
	local slotCount = #self.SlotOrder

	local nextIndex = currentIndex + direction
	if nextIndex < 1 then
		nextIndex = slotCount
	elseif nextIndex > slotCount then
		nextIndex = 1
	end

	return self.SlotOrder[nextIndex]
end

return LoadoutConfig
