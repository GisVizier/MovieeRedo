local WeaponConfig = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponConfigsFolder = script

-- Auto-discover and load weapon configurations by category
local function LoadWeaponCategory(categoryFolder)
	local configs = {}
	if categoryFolder then
		for _, configModule in ipairs(categoryFolder:GetChildren()) do
			if configModule:IsA("ModuleScript") then
				local success, config = pcall(require, configModule)
				if success then
					configs[configModule.Name] = config
				else
					warn("[WeaponConfig] Failed to load", categoryFolder.Name, configModule.Name, ":", config)
				end
			end
		end
	end
	return configs
end

-- Auto-load all weapon categories
WeaponConfig.Guns = LoadWeaponCategory(WeaponConfigsFolder:FindFirstChild("Guns"))
WeaponConfig.Melee = LoadWeaponCategory(WeaponConfigsFolder:FindFirstChild("Melee"))

-- Helper function to get weapon config by type and name
function WeaponConfig:GetWeaponConfig(weaponType, weaponName)
	if weaponType == "Gun" and self.Guns[weaponName] then
		return self.Guns[weaponName]
	elseif weaponType == "Melee" and self.Melee[weaponName] then
		return self.Melee[weaponName]
	end
	warn("[WeaponConfig] Unknown weapon:", weaponType, weaponName)
	return nil
end

-- Get all weapon names by type
function WeaponConfig:GetWeaponsByType(weaponType)
	if weaponType == "Gun" then
		return self.Guns
	elseif weaponType == "Melee" then
		return self.Melee
	end
	return {}
end

return WeaponConfig
