--[[
	WeaponIKConfig.lua
	
	Configuration for third-person weapon IK (Inverse Kinematics).
	Defines grip attachment paths for each weapon so arms can IK to hold weapons properly.
	
	Model Path: Path to the world model in Assets/Models/Weapons/
	RightGrip: Attachment path for right hand (pistol grip)
	LeftGrip: Attachment path for left hand (foregrip/pump)
	RigAttachment: Where on the rig the weapon should attach (default: Right Arm)
]]

local WeaponIKConfig = {}

-- Default grip attachment names (fallback if weapon-specific not found)
WeaponIKConfig.DefaultGrips = {
	RightGrip = "RightGrip",
	LeftGrip = "LeftGrip",
}

-- Per-weapon configuration
WeaponIKConfig.Weapons = {
	Shotgun = {
		ModelPath = "Weapons/Shotgun/Shotgun",
		RightGripPath = "Parts.Primary.RightGrip",
		LeftGripPath = "Parts.Grip.Forestock", -- Foregrip/pump area
		-- Alternative: "Parts.Primary.LeftGrip"
		RigAttachment = "Right Arm", -- Which rig part to weld to
		WeaponOffset = CFrame.new(0, -0.5, -0.3) * CFrame.Angles(math.rad(-90), 0, 0), -- Adjust as needed
	},
	
	AssaultRifle = {
		ModelPath = "Weapons/AssaultRifle/AssaultRifle",
		RightGripPath = "Parts.Primary.RightGrip",
		LeftGripPath = "Parts.Primary.LeftGrip",
		RigAttachment = "Right Arm",
		WeaponOffset = CFrame.new(0, -0.5, -0.3) * CFrame.Angles(math.rad(-90), 0, 0),
	},
	
	Revolver = {
		ModelPath = "Weapons/Revolver/Revolver",
		RightGripPath = "Parts.Primary.RightGrip",
		LeftGripPath = nil, -- One-handed weapon
		RigAttachment = "Right Arm",
		WeaponOffset = CFrame.new(0, -0.3, -0.2) * CFrame.Angles(math.rad(-90), 0, 0),
	},
	
	Sniper = {
		ModelPath = "Weapons/Sniper/Sniper",
		RightGripPath = "Parts.Primary.RightGrip",
		LeftGripPath = "Parts.Primary.LeftGrip",
		RigAttachment = "Right Arm",
		WeaponOffset = CFrame.new(0, -0.5, -0.3) * CFrame.Angles(math.rad(-90), 0, 0),
	},
	
	-- Melee weapons (typically one-handed, no IK needed)
	Knife = {
		ModelPath = "Weapons/Knife/Knife",
		RightGripPath = "Handle.RightGrip",
		LeftGripPath = nil,
		RigAttachment = "Right Arm",
		WeaponOffset = CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(-90), 0, 0),
		DisableIK = true, -- Melee typically uses animations only
	},
}

-- Helper to get attachment from path string like "Parts.Primary.RightGrip"
function WeaponIKConfig.GetAttachmentFromPath(model: Model, path: string): Attachment?
	if not model or not path then
		return nil
	end
	
	local current: Instance = model
	for _, partName in ipairs(string.split(path, ".")) do
		current = current:FindFirstChild(partName)
		if not current then
			return nil
		end
	end
	
	if current:IsA("Attachment") then
		return current
	end
	
	return nil
end

-- Get config for a weapon, with fallbacks
function WeaponIKConfig.GetConfig(weaponId: string)
	return WeaponIKConfig.Weapons[weaponId] or nil
end

return WeaponIKConfig
