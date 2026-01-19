local WeaponAmmo = {}
WeaponAmmo.__index = WeaponAmmo

function WeaponAmmo.new(loadoutConfig, httpService)
	local self = setmetatable({}, WeaponAmmo)
	self._loadoutConfig = loadoutConfig
	self._httpService = httpService
	self._ammoData = {
		Primary = { currentAmmo = 0, reserveAmmo = 0 },
		Secondary = { currentAmmo = 0, reserveAmmo = 0 },
		Melee = { currentAmmo = 0, reserveAmmo = 0 },
	}
	return self
end

function WeaponAmmo:GetAmmoData()
	return self._ammoData
end

function WeaponAmmo:GetAmmo(slotType)
	return self._ammoData[slotType]
end

function WeaponAmmo:GetCurrentAmmo(slotType)
	local ammo = self._ammoData[slotType]
	return ammo and ammo.currentAmmo or 0
end

function WeaponAmmo:UpdateHUDAmmo(slotType, weaponConfig, localPlayer, isReloading, getCurrentSlot)
	if not localPlayer or not weaponConfig then
		return
	end

	local ammo = self._ammoData[slotType]
	if not ammo then
		return
	end

	local weaponData = {
		Gun = weaponConfig.name,
		GunId = weaponConfig.id,
		GunType = weaponConfig.weaponType,
		Ammo = ammo.currentAmmo,
		MaxAmmo = ammo.reserveAmmo,
		ClipSize = weaponConfig.clipSize,
		Reloading = isReloading and getCurrentSlot() == slotType,
		OnCooldown = false,
		Cooldown = weaponConfig.cooldown or 0,
		ReloadTime = weaponConfig.reloadTime or 0,
		Rarity = weaponConfig.rarity,
		UpdatedAt = os.clock(),
	}

	local attrName = slotType .. "Data"
	localPlayer:SetAttribute(attrName, nil)
	localPlayer:SetAttribute(attrName, self._httpService:JSONEncode(weaponData))
end

function WeaponAmmo:InitializeFromLoadout(localPlayer, isReloading, getCurrentSlot)
	if not localPlayer then
		return
	end

	local loadoutJson = localPlayer:GetAttribute("SelectedLoadout")
	if not loadoutJson or loadoutJson == "" then
		return
	end

	local success, loadoutData = pcall(function()
		return self._httpService:JSONDecode(loadoutJson)
	end)

	if not success then
		return
	end

	local loadout = loadoutData.loadout or loadoutData

	for _, slotType in ipairs({ "Primary", "Secondary", "Melee" }) do
		local weaponId = loadout[slotType]
		local weaponConfig = weaponId and self._loadoutConfig.getWeapon(weaponId)

		if weaponConfig then
			self._ammoData[slotType] = {
				currentAmmo = weaponConfig.clipSize or 0,
				reserveAmmo = weaponConfig.maxAmmo or 0,
			}
			self:UpdateHUDAmmo(slotType, weaponConfig, localPlayer, isReloading, getCurrentSlot)
		end
	end
end

function WeaponAmmo:ApplyState(state, slotType, weaponConfig, localPlayer, isReloading, getCurrentSlot)
	if not state or not slotType then
		return
	end

	local ammo = self._ammoData[slotType]
	if ammo then
		if type(state.CurrentAmmo) == "number" then
			ammo.currentAmmo = state.CurrentAmmo
		end
		if type(state.ReserveAmmo) == "number" then
			ammo.reserveAmmo = state.ReserveAmmo
		end
	end

	if weaponConfig then
		self:UpdateHUDAmmo(slotType, weaponConfig, localPlayer, isReloading, getCurrentSlot)
	end
end

function WeaponAmmo:DecrementAmmo(slotType, weaponConfig, localPlayer, isReloading, getCurrentSlot)
	local ammo = self._ammoData[slotType]
	if ammo and ammo.currentAmmo > 0 then
		ammo.currentAmmo = ammo.currentAmmo - 1
		if weaponConfig then
			self:UpdateHUDAmmo(slotType, weaponConfig, localPlayer, isReloading, getCurrentSlot)
		end
		return true
	end
	return false
end

return WeaponAmmo
