local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LogService = require(Locations.Shared.Util:WaitForChild("LogService"))

local ViewmodelConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("ViewmodelConfig"))
local ViewmodelRig = require(script.Parent:WaitForChild("ViewmodelRig"))
local ViewmodelAppearance = require(script.Parent:WaitForChild("ViewmodelAppearance"))

local CreateLoadout = {}

local function getViewmodelsRoot(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local viewModels = assets and assets:FindFirstChild("ViewModels")
	return viewModels
end

local function resolveModelTemplate(modelPath: string): Instance?
	local root = getViewmodelsRoot()
	if not root then
		return nil
	end

	local current: Instance = root
	local parts = string.split(modelPath, "/")
	for i = 1, #parts do
		current = current:FindFirstChild(parts[i])
		if not current then
			return nil
		end
	end

	return current
end

local function cloneRig(modelPath: string, name: string, player: Player?, silent: boolean?)
	local template = resolveModelTemplate(modelPath)
	if not template or not template:IsA("Model") then
		if silent ~= true then
			LogService:Warn("VIEWMODEL", "Missing viewmodel template", { Name = name, Path = modelPath })
		end
		return nil
	end

	local clone = template:Clone()
	clone.Name = name
	clone.Parent = nil -- parented when activated

	local rig = ViewmodelRig.new(clone, name)
	if player then
		-- Apply shirt from workspace rig (no fallback).
		rig:AddCleanup(ViewmodelAppearance.BindShirtToLocalRig(player, clone))
	end
	return rig
end

function CreateLoadout.create(loadout: { [string]: any }, player: Player?)
	-- Slots:
	-- - Fists (fallback / default)
	-- - Primary (weapon)
	-- - Secondary (weapon)
	-- - Melee (weapon)
	local rigs = {}

	-- Fists always exist (fallback).
	do
		local fistsCfg = ViewmodelConfig.Weapons.Fists
		local path = fistsCfg and fistsCfg.ModelPath or ViewmodelConfig.Models.Fists
		rigs.Fists = cloneRig(path, "Fists", player)
	end

	local function addWeaponSlot(slotName: string, weaponId: any)
		if type(weaponId) ~= "string" then
			return
		end

		local weaponCfg = ViewmodelConfig.Weapons[weaponId]
		local path = weaponCfg and weaponCfg.ModelPath
			or (ViewmodelConfig.Models.ByWeaponId and ViewmodelConfig.Models.ByWeaponId[weaponId])
		if type(path) ~= "string" or path == "" then
			-- Silently skip: missing config should not spam output during development.
			return
		end

		local silent = (slotName == "Melee")
		local rig = cloneRig(path, slotName, player, silent)

		-- If melee doesn't exist yet, treat it as fists (fallback).
		if slotName == "Melee" and rig == nil then
			return
		end

		rigs[slotName] = rig
	end

	addWeaponSlot("Primary", loadout and loadout.Primary)
	addWeaponSlot("Secondary", loadout and loadout.Secondary)
	addWeaponSlot("Melee", loadout and loadout.Melee)

	local obj = {}
	obj.Rigs = rigs

	function obj:Destroy()
		for _, rig in pairs(self.Rigs) do
			if rig and rig.Destroy then
				rig:Destroy()
			end
		end
		self.Rigs = {}
	end

	return obj
end

return CreateLoadout
