local CrosshairConfig = {}

CrosshairConfig.DefaultCustomization = {
	showDot = true,
	showTopLine = true,
	showBottomLine = true,
	showLeftLine = true,
	showRightLine = true,
	lineThickness = 2,
	lineLength = 10,
	gapFromCenter = 5,
	dotSize = 4,
	rotation = 0,
	cornerRadius = 0,
	mainColor = Color3.fromRGB(255, 255, 255),
	outlineColor = Color3.fromRGB(0, 0, 0),
	outlineThickness = 1,
	opacity = 1,
	scale = 1,
	dynamicSpreadEnabled = true,
}

CrosshairConfig.WeaponCrosshairs = {
	Revolver = "Default",
	Rifle = "Default",
	Shotgun = "Shotgun",
	SMG = "Default",
	Sniper = "Default",
	Fist = "Default",
	Bow = "Bow",
	DoubleBarrel = "DoubleBarrel",
}

CrosshairConfig.WeaponSpreadData = {
	Default = {
		spreadX = 1,
		spreadY = 1,
		recoilMultiplier = 1,
	},
	Revolver = {
		spreadX = 1.5,
		spreadY = 1.5,
		recoilMultiplier = 1.8,
	},
	Rifle = {
		spreadX = 1.2,
		spreadY = 1.2,
		recoilMultiplier = 1.2,
	},
	Shotgun = {
		spreadX = 2.5,
		spreadY = 2.5,
		recoilMultiplier = 2.0,
	},
	SMG = {
		spreadX = 0.8,
		spreadY = 0.8,
		recoilMultiplier = 0.6,
	},
	Sniper = {
		spreadX = 0.5,
		spreadY = 0.5,
		recoilMultiplier = 2.5,
	},
	Fist = {
		spreadX = 0.5,
		spreadY = 0.5,
		recoilMultiplier = 0.3,
	},
	Bow = {
		spreadX = 0.6,
		spreadY = 0.6,
		recoilMultiplier = 1.0,
	},
	DoubleBarrel = {
		spreadX = 3.0,
		spreadY = 3.0,
		recoilMultiplier = 2.5,
	},
}

CrosshairConfig.Colors = {
	White = Color3.fromRGB(255, 255, 255),
	Green = Color3.fromRGB(0, 255, 0),
	Red = Color3.fromRGB(255, 0, 0),
	Cyan = Color3.fromRGB(0, 255, 255),
	Yellow = Color3.fromRGB(255, 255, 0),
	Pink = Color3.fromRGB(255, 105, 180),
}

function CrosshairConfig:GetCrosshairType(weaponName: string): string
	return self.WeaponCrosshairs[weaponName] or "Default"
end

function CrosshairConfig:GetWeaponData(weaponName: string): { spreadX: number, spreadY: number, recoilMultiplier: number }
	return self.WeaponSpreadData[weaponName] or self.WeaponSpreadData.Default
end

function CrosshairConfig:GetDefaultCustomization()
	local copy = {}
	for key, value in pairs(self.DefaultCustomization) do
		copy[key] = value
	end
	return copy
end

return CrosshairConfig
