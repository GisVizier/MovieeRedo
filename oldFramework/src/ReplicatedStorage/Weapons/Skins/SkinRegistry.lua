local SkinRegistry = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local Log = require(Locations.Modules.Systems.Core.LogService)

SkinRegistry.Skins = {
	Shotgun = {
		Default = {
			DisplayName = "Standard",
			Rarity = "Common",
			ModelPath = "Shotguns/Shotgun_Default",
			Animations = {},
			FX = {},
			ConfigOverrides = {},
		},
		Golden = {
			DisplayName = "Golden Shotgun",
			Rarity = "Legendary",
			ModelPath = "Shotguns/Shotgun_Golden",
			Animations = {
				Fire = "rbxassetid://0",
			},
			FX = {
				MuzzleFlash = "GoldenMuzzle",
				TrailColor = Color3.fromRGB(255, 215, 0),
			},
			ConfigOverrides = {},
		},
	},

	AssaultRifle = {
		Default = {
			DisplayName = "Standard",
			Rarity = "Common",
			ModelPath = "Rifles/AssaultRifle_Default",
			Animations = {},
			FX = {},
			ConfigOverrides = {},
		},
	},

	SniperRifle = {
		Default = {
			DisplayName = "Standard",
			Rarity = "Common",
			ModelPath = "Snipers/SniperRifle_Default",
			Animations = {},
			FX = {},
			ConfigOverrides = {},
		},
	},

	Revolver = {
		Default = {
			DisplayName = "Standard",
			Rarity = "Common",
			ModelPath = "Pistols/Revolver_Default",
			Animations = {},
			FX = {},
			ConfigOverrides = {},
		},
	},

	Knife = {
		Default = {
			DisplayName = "Standard",
			Rarity = "Common",
			ModelPath = "Melee/Knife_Default",
			Animations = {},
			FX = {},
			ConfigOverrides = {},
		},
	},
}

SkinRegistry.RarityColors = {
	Common = Color3.fromRGB(150, 150, 150),
	Uncommon = Color3.fromRGB(30, 255, 30),
	Rare = Color3.fromRGB(30, 144, 255),
	Epic = Color3.fromRGB(163, 53, 238),
	Legendary = Color3.fromRGB(255, 215, 0),
}

function SkinRegistry:GetSkin(weaponName, skinName)
	local weaponSkins = self.Skins[weaponName]
	if not weaponSkins then
		Log:Warn("SKIN_REGISTRY", "No skins found for weapon", { Weapon = weaponName })
		return nil
	end

	local skin = weaponSkins[skinName]
	if not skin then
		Log:Debug("SKIN_REGISTRY", "Skin not found, using default", { Weapon = weaponName, Skin = skinName })
		return weaponSkins.Default
	end

	return skin
end

function SkinRegistry:GetAllSkinsForWeapon(weaponName)
	return self.Skins[weaponName] or {}
end

function SkinRegistry:GetSkinNames(weaponName)
	local weaponSkins = self.Skins[weaponName]
	if not weaponSkins then
		return {}
	end

	local names = {}
	for skinName in pairs(weaponSkins) do
		table.insert(names, skinName)
	end

	return names
end

function SkinRegistry:GetModelPath(weaponName, skinName)
	local skin = self:GetSkin(weaponName, skinName or "Default")
	if skin then
		return skin.ModelPath
	end
	return nil
end

function SkinRegistry:GetAnimationOverrides(weaponName, skinName)
	local skin = self:GetSkin(weaponName, skinName)
	if skin then
		return skin.Animations or {}
	end
	return {}
end

function SkinRegistry:GetFXOverrides(weaponName, skinName)
	local skin = self:GetSkin(weaponName, skinName)
	if skin then
		return skin.FX or {}
	end
	return {}
end

function SkinRegistry:GetConfigOverrides(weaponName, skinName)
	local skin = self:GetSkin(weaponName, skinName)
	if skin then
		return skin.ConfigOverrides or {}
	end
	return {}
end

function SkinRegistry:GetRarityColor(rarity)
	return self.RarityColors[rarity] or self.RarityColors.Common
end

function SkinRegistry:RegisterSkin(weaponName, skinName, skinData)
	if not self.Skins[weaponName] then
		self.Skins[weaponName] = {}
	end

	self.Skins[weaponName][skinName] = skinData
	Log:Info("SKIN_REGISTRY", "Registered skin", { Weapon = weaponName, Skin = skinName })
end

return SkinRegistry
