--[[
	ThirdPersonWeaponManager.lua
	
	Manages third-person weapon models attached to character rigs.
	Handles weapon cloning, welding to arm, and cleanup.
	
	IK is handled separately by IKSystem - this just welds weapons.
	
	Usage:
		local manager = ThirdPersonWeaponManager.new(rig)
		manager:EquipWeapon(weaponId)
		manager:UnequipWeapon()
		manager:GetWeaponModel() -- For IKSystem to read grip attachments
		manager:Destroy()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local IKSolver = require(Locations.Shared.Util:WaitForChild("IKSolver"))

local ThirdPersonWeaponManager = {}
ThirdPersonWeaponManager.__index = ThirdPersonWeaponManager

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getWeaponModelsRoot(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	return models
end

local function resolveWeaponModel(modelPath: string): Model?
	local root = getWeaponModelsRoot()
	if not root then
		return nil
	end
	
	local current: Instance = root
	for _, partName in ipairs(string.split(modelPath, "/")) do
		current = current:FindFirstChild(partName)
		if not current then
			return nil
		end
	end
	
	if current:IsA("Model") then
		return current
	end
	
	return nil
end

local function findRigArm(rig: Model, armName: string): BasePart?
	local arm = rig:FindFirstChild(armName)
	if arm and arm:IsA("BasePart") then
		return arm
	end
	
	for _, desc in ipairs(rig:GetDescendants()) do
		if desc.Name == armName and desc:IsA("BasePart") then
			return desc
		end
	end
	
	return nil
end

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
	
	@param weaponId - Weapon identifier (e.g., "Shotgun")
	@return boolean - Success
]]
function ThirdPersonWeaponManager:EquipWeapon(weaponId: string): boolean
	self:UnequipWeapon()
	
	if not weaponId or weaponId == "" or weaponId == "Fists" then
		return true
	end
	
	-- Get weapon config from IKSolver
	local config = IKSolver.GetWeaponConfig(weaponId)
	if not config then
		warn("[ThirdPersonWeaponManager] No config for:", weaponId)
		return false
	end
	
	-- Build model path: Weapons/{WeaponId}/{WeaponId}
	local modelPath = "Weapons/" .. weaponId .. "/" .. weaponId
	
	local template = resolveWeaponModel(modelPath)
	if not template then
		warn("[ThirdPersonWeaponManager] Model not found:", modelPath)
		return false
	end
	
	-- Clone weapon
	local weapon = template:Clone()
	weapon.Name = weaponId .. "_3P"
	
	-- Make parts non-collidable
	for _, part in ipairs(weapon:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.Anchored = false
		end
	end
	
	-- Find rig arm
	local rigArm = findRigArm(self.Rig, "Right Arm")
	if not rigArm then
		warn("[ThirdPersonWeaponManager] Right Arm not found")
		weapon:Destroy()
		return false
	end
	
	-- Find weapon root
	local weaponRoot = weapon:FindFirstChild("Root") or weapon.PrimaryPart
	if not weaponRoot then
		for _, part in ipairs(weapon:GetDescendants()) do
			if part:IsA("BasePart") then
				weaponRoot = part
				break
			end
		end
	end
	
	if not weaponRoot then
		warn("[ThirdPersonWeaponManager] Weapon has no root part")
		weapon:Destroy()
		return false
	end
	
	-- Parent weapon
	weapon.Parent = self.Rig
	
	-- Find right grip attachment for positioning
	local rightGrip = config.RightGrip and IKSolver.GetAttachmentFromPath(weapon, config.RightGrip)
	
	-- Calculate weld offset
	local handOffset = CFrame.new(0, -rigArm.Size.Y / 2, 0)
	local weaponRotation = CFrame.Angles(math.rad(-90), math.rad(180), 0)
	
	local weldOffset
	if rightGrip then
		local gripLocalPos = weaponRoot.CFrame:PointToObjectSpace(rightGrip.WorldPosition)
		weldOffset = handOffset * weaponRotation * CFrame.new(-gripLocalPos)
	else
		weldOffset = handOffset * weaponRotation
	end
	
	-- Position and weld
	weaponRoot.CFrame = rigArm.CFrame * weldOffset
	
	local weld = Instance.new("Weld")
	weld.Part0 = rigArm
	weld.Part1 = weaponRoot
	weld.C0 = weldOffset
	weld.C1 = CFrame.new()
	weld.Parent = weaponRoot
	
	self.WeaponModel = weapon
	self.WeaponId = weaponId
	self.Weld = weld
	
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
	Get the current weapon model (for IKSystem to read grip attachments).
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
