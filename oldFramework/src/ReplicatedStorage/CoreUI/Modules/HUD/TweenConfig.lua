local TweenConfig = {}

TweenConfig.Tweens = {
	Main = {
		show = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		hide = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	},

	Bar = {
		main = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		white = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},

	Selection = {
		update = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},

	ItemDesc = {
		show = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		hide = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	},

	Reload = {
		fadeIn = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		fadeOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	},
}

TweenConfig.Delays = {
	WhiteBar = 0.25,
	Stagger = 0.15,
}

TweenConfig.Values = {
	SelectedScale = 1.4,
	DeselectedScale = 1,
	ItemDescOffset = 0.08,
	ReloadDuration = 1,
	ReloadBgVisible = 0.2,
}

function TweenConfig.get(category, tweenType)
	local categoryData = TweenConfig.Tweens[category]
	if categoryData then
		return categoryData[tweenType]
	end
	return TweenInfo.new(0.3)
end

function TweenConfig.getDelay(delayType)
	return TweenConfig.Delays[delayType] or 0
end

return TweenConfig
