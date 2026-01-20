--[[
	ThirdPersonWeaponManager.lua
	
	Manages third-person weapon models attached to character rigs.
	- Clones world weapon models from Assets/Models/Weapons/
	- Welds them to the rig's arm
	- Applies arm IK to grip attachments
	
	Used by ClientReplicator (local player) and RemoteReplicator (other players).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local WeaponIKConfig = require(script.Parent:WaitForChild("WeaponIKConfig"))
local ArmIK = require(Locations.Shared.Util:WaitForChild("ArmIK"))

local ThirdPersonWeaponManager = {}
ThirdPersonWeaponManager.__index = ThirdPersonWeaponManager

-- Get the root folder for world weapon models
local function getWeaponModelsRoot(): Folder?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Models")
	return models
end

-- Resolve a weapon model from path like "Weapons/Shotgun/Shotgun"
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

-- Find an arm part in the rig
local function findRigArm(rig: Model, armName: string): BasePart?
	-- Direct child
	local arm = rig:FindFirstChild(armName)
	if arm and arm:IsA("BasePart") then
		return arm
	end
	
	-- Search descendants
	for _, desc in ipairs(rig:GetDescendants()) do
		if desc.Name == armName and desc:IsA("BasePart") then
			return desc
		end
	end
	
	return nil
end

--[[
	Create a new weapon manager for a specific rig.
	
	@param rig - The character rig (Model with arms)
	@return ThirdPersonWeaponManager instance
]]
function ThirdPersonWeaponManager.new(rig: Model)
	if not rig then
		return nil
	end
	
	local self = setmetatable({}, ThirdPersonWeaponManager)
	self.Rig = rig
	self.CurrentWeapon = nil -- The cloned weapon model
	self.CurrentWeaponId = nil
	self.ArmIK = nil
	self.RightGrip = nil -- Attachment for right hand
	self.LeftGrip = nil -- Attachment for left hand
	self.Weld = nil
	
	-- Initialize ArmIK for the rig
	self.ArmIK = ArmIK.new(rig)
	
	return self
end

--[[
	Equip a weapon to the rig.
	
	@param weaponId - The weapon identifier (e.g., "Shotgun")
	@return boolean - Success
]]
function ThirdPersonWeaponManager:EquipWeapon(weaponId: string): boolean
	-- Unequip current weapon first
	self:UnequipWeapon()
	
	if not weaponId or weaponId == "" or weaponId == "Fists" then
		return true -- No weapon to equip
	end
	
	local config = WeaponIKConfig.GetConfig(weaponId)
	if not config then
		warn("[ThirdPersonWeaponManager] No config for weapon:", weaponId)
		return false
	end
	
	-- Get the weapon model template
	local template = resolveWeaponModel(config.ModelPath)
	if not template then
		warn("[ThirdPersonWeaponManager] Weapon model not found:", config.ModelPath)
		return false
	end
	
	-- Clone the weapon
	local weapon = template:Clone()
	weapon.Name = weaponId .. "_ThirdPerson"
	
	-- Make all parts non-collidable and massless
	for _, part in ipairs(weapon:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			part.Anchored = false
		end
	end
	
	-- Find the rig arm to attach to
	local rigArm = findRigArm(self.Rig, config.RigAttachment or "Right Arm")
	if not rigArm then
		warn("[ThirdPersonWeaponManager] Rig arm not found:", config.RigAttachment)
		weapon:Destroy()
		return false
	end
	
	-- Get the weapon's root part (prefer Root, then PrimaryPart)
	local weaponRoot = weapon:FindFirstChild("Root") or weapon.PrimaryPart
	if not weaponRoot then
		-- Find any part as fallback
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
	
	-- Parent weapon first so attachments have world positions
	weapon.Parent = self.Rig
	
	-- Find the RightGrip attachment to position the weapon properly
	local rightGripAttachment = config.RightGripPath and WeaponIKConfig.GetAttachmentFromPath(weapon, config.RightGripPath)
	local leftGripAttachment = config.LeftGripPath and WeaponIKConfig.GetAttachmentFromPath(weapon, config.LeftGripPath)
	
	-- Calculate offset so the RightGrip is at the hand position
	-- The hand should be at the bottom/end of the arm
	local handOffset = CFrame.new(0, -rigArm.Size.Y / 2, 0) -- Bottom of arm
	
	local weldOffset
	if rightGripAttachment then
		-- Get the grip position relative to weapon root (position only)
		local gripLocalPos = weaponRoot.CFrame:PointToObjectSpace(rightGripAttachment.WorldPosition)
		
		-- The weld should position the weapon so the grip is at the hand
		-- Weapon rotation from config (how the weapon should be oriented in hand)
		local weaponRotation = config.WeaponRotation or CFrame.Angles(0, 0, 0)
		
		-- Offset: move to hand position, rotate, then offset by negative grip position
		weldOffset = handOffset * weaponRotation * CFrame.new(-gripLocalPos)
	else
		-- Fallback to config offset if no grip attachment
		weldOffset = config.WeaponOffset or CFrame.new(0, -0.5, -0.3) * CFrame.Angles(math.rad(-90), 0, 0)
	end
	
	-- Position weapon
	weaponRoot.CFrame = rigArm.CFrame * weldOffset
	
	-- Create weld
	local weld = Instance.new("Weld")
	weld.Part0 = rigArm
	weld.Part1 = weaponRoot
	weld.C0 = weldOffset
	weld.C1 = CFrame.new()
	weld.Parent = weaponRoot
	
	-- Store grip attachments for IK
	self.RightGrip = rightGripAttachment
	self.LeftGrip = leftGripAttachment
	
	-- Store references
	self.CurrentWeapon = weapon
	self.CurrentWeaponId = weaponId
	self.Weld = weld
	self.DisableIK = config.DisableIK or false
	
	return true
end

--[[
	Unequip the current weapon.
]]
function ThirdPersonWeaponManager:UnequipWeapon()
	if self.Weld then
		self.Weld:Destroy()
		self.Weld = nil
	end
	
	if self.CurrentWeapon then
		self.CurrentWeapon:Destroy()
		self.CurrentWeapon = nil
	end
	
	self.CurrentWeaponId = nil
	self.RightGrip = nil
	self.LeftGrip = nil
	self.DisableIK = false
	
	-- Reset arm IK
	if self.ArmIK then
		self.ArmIK:Reset()
	end
end

--[[
	Update arm IK to point at the weapon grips.
	Call this every frame after the rig has been positioned.
	
	@param aimDirection - Optional: direction the character is aiming (for arm pointing)
]]
function ThirdPersonWeaponManager:UpdateIK(aimDirection: Vector3?)
	if not self.ArmIK or not self.CurrentWeapon or self.DisableIK then
		return
	end
	
	-- Get grip world positions
	local rightTarget = nil
	local leftTarget = nil
	
	if self.RightGrip then
		rightTarget = self.RightGrip.WorldPosition
	end
	
	if self.LeftGrip then
		leftTarget = self.LeftGrip.WorldPosition
	end
	
	-- Apply IK to arms
	if rightTarget then
		self.ArmIK:SolveArm("Right", rightTarget, 0.8)
	end
	
	if leftTarget then
		self.ArmIK:SolveArm("Left", leftTarget, 0.8)
	end
end

--[[
	Get the current equipped weapon ID.
]]
function ThirdPersonWeaponManager:GetCurrentWeaponId(): string?
	return self.CurrentWeaponId
end

--[[
	Check if a weapon is currently equipped.
]]
function ThirdPersonWeaponManager:HasWeapon(): boolean
	return self.CurrentWeapon ~= nil
end

--[[
	Destroy the manager and cleanup.
]]
function ThirdPersonWeaponManager:Destroy()
	self:UnequipWeapon()
	
	if self.ArmIK then
		self.ArmIK:Destroy()
		self.ArmIK = nil
	end
	
	self.Rig = nil
end

return ThirdPersonWeaponManager
