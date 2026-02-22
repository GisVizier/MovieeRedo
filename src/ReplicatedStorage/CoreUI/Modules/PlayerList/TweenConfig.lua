local TweenConfig = {}

TweenConfig.Values = {
	HoverGlowMinTransparency = 0.22,
	HoverGlowMaxTransparency = 0.68,
	SelectedGlowTransparency = 0.12,
	HiddenGlowTransparency = 1,
	SectionCollapsedHeight = 0,
	RowLayoutBaseOrder = 10,
}

TweenConfig.Elements = {
	Panel = {
		show = {
			duration = 0.28,
			easing = { Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out },
		},
		hide = {
			duration = 0.2,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In },
		},
	},
	Section = {
		toggle = {
			duration = 0.2,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
		},
	},
	Row = {
		enter = {
			duration = 0.22,
			easing = { Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.Out },
		},
		exit = {
			duration = 0.16,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In },
		},
	},
	Glow = {
		hoverPulse = {
			duration = 0.42,
			easing = { Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut },
		},
		selectIn = {
			duration = 0.18,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
		},
		selectOut = {
			duration = 0.14,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
		},
	},
	Tab = {
		switch = {
			duration = 0.16,
			easing = { Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.Out },
		},
	},
	NotificationBar = {
		drain = {
			duration = 1,
			easing = { Style = Enum.EasingStyle.Linear, Direction = Enum.EasingDirection.Out },
		},
	},
}

function TweenConfig.get(elementName, animationType)
	local element = TweenConfig.Elements[elementName]
	local animation = element and element[animationType]
	if not animation then
		return TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	local easing = animation.easing or {}
	return TweenInfo.new(
		animation.duration or 0.2,
		easing.Style or Enum.EasingStyle.Quad,
		easing.Direction or Enum.EasingDirection.Out
	)
end

return TweenConfig
