--[[
	ThirdPersonWeaponManager.lua

	Manages 3rd-person weapon models welded to player's character rig.
	- Welds weapon to Right Arm on the rig in workspace.Rigs
	- Weapon follows arm rotation (which follows camera pitch)
	- Only handles local player's rig (other players see via replication)

	Usage:
	local ThirdPersonWeaponManager = require(...)
	ThirdPersonWeaponManager:Init()
	ThirdPersonWeaponManager:EquipWeapon(weaponName, skinName)
	ThirdPersonWeaponManager:UnequipWeapon()
]]

local ThirdPersonWeaponManager = {}

-- Services
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local Locations = require(ReplicatedStorage:WaitForChild("Modules").Locations)
local ViewmodelConfig = require(ReplicatedStorage.Configs.ViewmodelConfig)
local RigManager = require(Locations.Modules.Systems.Character.RigManager)
local WeldUtils = require(Locations.Modules.Utils.WeldUtils)
local LogService = require(Locations.Modules.Systems.Core.LogService)

local LocalPlayer = Players.LocalPlayer

-- State
ThirdPersonWeaponManager.CurrentWeapon = nil
ThirdPersonWeaponManager.CurrentWeaponName = nil
ThirdPersonWeaponManager.WeaponWeld = nil

-- Configuration for weapon positioning on rig
ThirdPersonWeaponManager.WeaponConfig = {
	-- Offset from Right Arm grip point
	-- Adjust these to position weapon correctly in hand
	GripOffset = CFrame.new(0, -0.5, 0) * CFrame.Angles(math.rad(-90), 0, 0),

	-- Scale for 3rd-person model (if different from viewmodel)
	Scale = 1.0,
}

--============================================================================
-- INITIALIZATION
--============================================================================

function ThirdPersonWeaponManager:Init()
	LogService:RegisterCategory("3P_WEAPON", "Third-person weapon management")
	RigManager:Init()

	LogService:Info("3P_WEAPON", "ThirdPersonWeaponManager initialized")
end

--============================================================================
-- WEAPON MANAGEMENT
--============================================================================

--[[
	Get the weapon model from the ViewModels folder
	Uses the same path as viewmodel but looks for a 3rd-person variant first
	@param weaponName string - Name of the weapon
	@param skinName string|nil - Optional skin name
	@return Model|nil - The weapon model or nil
]]
function ThirdPersonWeaponManager:GetWeaponModel(weaponName, skinName)
	local config = ViewmodelConfig:GetResolvedConfig(weaponName, skinName)
	if not config then
		LogService:Warn("3P_WEAPON", "No config found for weapon", { Weapon = weaponName })
		return nil
	end

	local modelPath = config.ModelPath
	local viewmodelsFolder = ReplicatedFirst:FindFirstChild("ViewModels")
	if not viewmodelsFolder then
		LogService:Error("3P_WEAPON", "ViewModels folder not found in ReplicatedFirst")
		return nil
	end

	local pathParts = string.split(modelPath, "/")
	local currentFolder = viewmodelsFolder

	for i = 1, #pathParts - 1 do
		currentFolder = currentFolder:FindFirstChild(pathParts[i])
		if not currentFolder then
			LogService:Error("3P_WEAPON", "Weapon folder not found", { Path = modelPath })
			return nil
		end
	end

	local modelName = pathParts[#pathParts]

	-- Try to find a 3rd-person specific model first (e.g., "Shotgun_Default_3P")
	local thirdPersonModel = currentFolder:FindFirstChild(modelName .. "_3P")
	if thirdPersonModel then
		return thirdPersonModel:Clone()
	end

	-- Fall back to viewmodel and extract just the weapon part
	local viewmodelTemplate = currentFolder:FindFirstChild(modelName)
	if not viewmodelTemplate then
		LogService:Error("3P_WEAPON", "Weapon model not found", { Path = modelPath })
		return nil
	end

	-- Clone and extract just the weapon model (not the arms)
	local viewmodel = viewmodelTemplate:Clone()

	-- Find the weapon model within the viewmodel
	-- First try by weapon name, then look for any Model that isn't an arm
	local weaponModel = viewmodel:FindFirstChild(weaponName)
	if not weaponModel then
		for _, child in ipairs(viewmodel:GetChildren()) do
			if child:IsA("Model") and not child.Name:find("Arm") then
				weaponModel = child
				break
			end
		end
	end

	if weaponModel then
		weaponModel.Parent = nil -- Detach from viewmodel
		viewmodel:Destroy()
		return weaponModel
	end

	viewmodel:Destroy()
	LogService:Warn("3P_WEAPON", "Could not extract weapon from viewmodel", { Weapon = weaponName })
	return nil
end

--[[
	Get the player's active rig
	@return Model|nil - The rig or nil
]]
function ThirdPersonWeaponManager:GetPlayerRig()
	return RigManager:GetActiveRig(LocalPlayer)
end

--[[
	Equip a weapon on the player's rig
	@param weaponName string - Name of the weapon
	@param skinName string|nil - Optional skin name
	@return boolean - Success
]]
function ThirdPersonWeaponManager:EquipWeapon(weaponName, skinName)
	-- Unequip current weapon first
	self:UnequipWeapon()

	local rig = self:GetPlayerRig()
	if not rig then
		LogService:Warn("3P_WEAPON", "No rig found for local player")
		return false
	end

	local rightArm = rig:FindFirstChild("Right Arm")
	if not rightArm then
		LogService:Warn("3P_WEAPON", "Right Arm not found on rig")
		return false
	end

	-- Get weapon model
	local weaponModel = self:GetWeaponModel(weaponName, skinName)
	if not weaponModel then
		return false
	end

	-- Find the grip point on the weapon (Root part or Primary part)
	local gripPart = weaponModel:FindFirstChild("Root")
		or weaponModel:FindFirstChild("Primary")
		or weaponModel.PrimaryPart
		or weaponModel:FindFirstChildWhichIsA("BasePart")

	if not gripPart then
		LogService:Error("3P_WEAPON", "No grip part found on weapon model", { Weapon = weaponName })
		weaponModel:Destroy()
		return false
	end

	-- Make all parts non-collidable
	for _, part in ipairs(weaponModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false
		end
	end

	-- Parent weapon to rig
	weaponModel.Name = "EquippedWeapon"
	weaponModel.Parent = rig

	-- Create weld from Right Arm to weapon grip
	-- Find the Right Grip attachment if it exists
	local rightGrip = rightArm:FindFirstChild("RightGripAttachment")
	local gripOffset = self.WeaponConfig.GripOffset

	if rightGrip then
		-- Use attachment position for more accurate placement
		gripOffset = rightGrip.CFrame * gripOffset
	end

	-- Create Motor6D so weapon follows arm rotation
	local weaponMotor = Instance.new("Motor6D")
	weaponMotor.Name = "WeaponGrip"
	weaponMotor.Part0 = rightArm
	weaponMotor.Part1 = gripPart
	weaponMotor.C0 = gripOffset
	weaponMotor.C1 = CFrame.new()
	weaponMotor.Parent = rightArm

	self.CurrentWeapon = weaponModel
	self.CurrentWeaponName = weaponName
	self.WeaponWeld = weaponMotor

	LogService:Info("3P_WEAPON", "Weapon equipped on rig", {
		Weapon = weaponName,
		Skin = skinName or "Default",
	})

	return true
end

--[[
	Unequip the current weapon from the rig
]]
function ThirdPersonWeaponManager:UnequipWeapon()
	if self.WeaponWeld then
		self.WeaponWeld:Destroy()
		self.WeaponWeld = nil
	end

	if self.CurrentWeapon then
		self.CurrentWeapon:Destroy()
		self.CurrentWeapon = nil
	end

	self.CurrentWeaponName = nil

	LogService:Debug("3P_WEAPON", "Weapon unequipped from rig")
end

--[[
	Check if a weapon is currently equipped
	@return boolean
]]
function ThirdPersonWeaponManager:IsWeaponEquipped()
	return self.CurrentWeapon ~= nil
end

--[[
	Get the currently equipped weapon name
	@return string|nil
]]
function ThirdPersonWeaponManager:GetCurrentWeaponName()
	return self.CurrentWeaponName
end

--[[
	Cleanup all weapons (call on character death/removal)
]]
function ThirdPersonWeaponManager:Cleanup()
	self:UnequipWeapon()
end

return ThirdPersonWeaponManager
