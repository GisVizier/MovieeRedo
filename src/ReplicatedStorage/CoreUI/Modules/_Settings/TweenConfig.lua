local TweenConfig = {}

TweenConfig.Durations = {
	Show        = 0.45,
	Hide        = 0.3,
	TopBarShow  = 0.65,
	TopBarHide  = 0.5,
	TabSelect   = 0.22,
	TabDeselect = 0.15,
	TabHover    = 0.18,
	TabHoverOut = 0.12,
	Flash = 0.2,
	ArrowPress = 0.08,
	RowSelect = 0.2,
	RowDeselect = 0.16,
	ImageCarouselSwap = 0.35,
	ImageCarouselInterval = 3,
}

TweenConfig.Easings = {
	Show      = { Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out },
	Hide      = { Style = Enum.EasingStyle.Quad,  Direction = Enum.EasingDirection.In  },
	Select    = { Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out },
	Deselect  = { Style = Enum.EasingStyle.Quad,  Direction = Enum.EasingDirection.Out },
	Hover     = { Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out },
	HoverOut  = { Style = Enum.EasingStyle.Quad,  Direction = Enum.EasingDirection.Out },
	Flash     = { Style = Enum.EasingStyle.Sine,  Direction = Enum.EasingDirection.InOut },
}

TweenConfig.Values = {
	SelectedButtonTransparency = 0,
	DeselectedButtonTransparency = 1,
	HoverButtonTransparency = 0.6,
	SelectedTextColor = Color3.fromRGB(0, 0, 0),
	DeselectedTextColor = Color3.fromRGB(255, 255, 255),
	SelectedStrokeColor = Color3.fromRGB(255, 255, 255),
	SelectedImageColor = Color3.fromRGB(0, 0, 0),
	DeselectedImageColor = Color3.fromRGB(255, 255, 255),

	SlideFadeOffset = 0.02,
	TopBarSlideOffset = 0.08,
	SideSlideOffset = 0.08,
	InfoSlideOffset = 0.03,
	BGVisibleTransparency = 0,
	RowSelectedScale = 1.02,
	SelectedIndicatorTransparency = 0.5,
	HoverIndicatorTransparency = 0.8,
	DeselectedIndicatorTransparency = 1,
	ArrowPressScale = 0.9,
	FlashRedColor = Color3.fromRGB(255, 60, 60),
	SliderMinPadding = 0,
	SliderMaxPadding = 0,
	SliderGradientOffset = 1,
}

function TweenConfig.create(key: string): TweenInfo
	local duration = TweenConfig.Durations[key] or 0.3
	-- Map the key name to the Easings table key
	local easingKey = key
	if key == "TabSelect"   then easingKey = "Select"   end
	if key == "TabDeselect" then easingKey = "Deselect" end
	if key == "TabHover"    then easingKey = "Hover"    end
	if key == "TabHoverOut" then easingKey = "HoverOut" end
	if key == "TopBarShow"  then easingKey = "Show"     end
	if key == "TopBarHide"  then easingKey = "Hide"     end
	if key == "RowSelect"   then easingKey = "Select"   end
	if key == "RowDeselect" then easingKey = "Deselect" end
	if key == "Flash"       then easingKey = "Flash"    end
	if key == "ImageCarouselSwap" then easingKey = "Select" end
	local easing = TweenConfig.Easings[easingKey] or TweenConfig.Easings.Show
	return TweenInfo.new(duration, easing.Style, easing.Direction)
end

return TweenConfig
