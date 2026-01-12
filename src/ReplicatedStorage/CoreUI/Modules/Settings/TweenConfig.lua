local TweenConfig = {}

TweenConfig.Durations = {
	Show = 0.67,
	Hide = 0.4,
	CategorySwitch = 0,
	SettingRowStagger = 0.001,
	SettingSelect = 0.25,
	SettingDeselect = 0.2,
	SettingHover = 0.2,
	SettingHoverOut = 0.15,
	ArrowPress = 0.001,
	ArrowFlashRed = 0.25,
	SliderDrag = 0.05,
	OverlayFadeIn = 0.35,
	OverlayFadeOut = 0.25,
	BlurFadeIn = 0.3,
	BlurFadeOut = 0.25,
	InfoPanelSwap = 0.2,
	ImageCarouselSwap = 0.4,
	ImageCarouselInterval = 3,
	TemplateSelect = 0.2,
	TemplateDeselect = 0.15,
	ActionShow = 0.2,
	ActionHide = 0.15,
}

TweenConfig.Easings = {
	Show = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
	Hide = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
	Hover = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
	HoverOut = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out},
	Select = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
	Flash = {Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut},
	Overlay = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
	
	Fast = {Style = Enum.EasingStyle.Exponential, Direction = Enum.EasingDirection.Out},
}

TweenConfig.Values = {
	SettingsUIFadeOffset = 0.03,
	SettingRowHoverScale = 1.02,
	SettingsUIOverlayTransparency = 0.67,
	BlurOverlayTransparency = 0,
	BlurSize = 45,
	ArrowPressScale = 0.85,
	FlashRedColor = Color3.fromRGB(255, 60, 60),
	ConflictRedColor = Color3.fromRGB(255, 80, 80),
	ConflictBgColor = Color3.fromRGB(80, 30, 30),
	TemplateSelectedScaleY = 1,
	TemplateDeselectedScaleY = 0.5,
	TemplateSelectedTransparency = 0,
	TemplateDeselectedTransparency = 0.5,
	ActionShowScale = 1.015,
	ActionHideScale = 1,
	SliderMinPadding = 0,
	SliderMaxPadding = 0,
	SliderGradientOffset = 1,
}

function TweenConfig.create(key: string): TweenInfo
	local duration = TweenConfig.Durations[key] or 0.3
	local easing = TweenConfig.Easings[key] or TweenConfig.Easings.Show

	return TweenInfo.new(
		duration,
		easing.Style,
		easing.Direction
	)
end

function TweenConfig.createCustom(duration: number, easingKey: string?): TweenInfo
	local easing = TweenConfig.Easings[easingKey] or TweenConfig.Easings.Show

	return TweenInfo.new(
		duration,
		easing.Style,
		easing.Direction
	)
end

return TweenConfig
