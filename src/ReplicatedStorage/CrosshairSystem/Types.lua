local Types = {}

export type WeaponData = {
	spreadX: number,
	spreadY: number,
	recoilMultiplier: number,
}

export type RecoilData = {
	amount: number,
}

export type CustomizationData = {
	showDot: boolean,
	showTopLine: boolean,
	showBottomLine: boolean,
	showLeftLine: boolean,
	showRightLine: boolean,
	lineThickness: number,
	lineLength: number,
	gapFromCenter: number,
	dotSize: number,
	rotation: number,
	cornerRadius: number,
	mainColor: Color3,
	outlineColor: Color3,
	outlineThickness: number,
	opacity: number,
	scale: number,
	dynamicSpreadEnabled: boolean,
}

export type CrosshairState = {
	velocity: Vector3,
	speed: number,
	currentRecoil: number,
	weaponData: WeaponData,
	customization: CustomizationData?,
	dt: number,
}

export type CrosshairModule = {
	CreateFrame: (self: CrosshairModule) -> Frame,
	Update: (self: CrosshairModule, dt: number, state: CrosshairState) -> number?,
	OnRecoil: (self: CrosshairModule, recoilData: RecoilData, weaponData: WeaponData?) -> number?,
	ApplyCustomization: (self: CrosshairModule, customization: CustomizationData) -> (),
}

return Types
