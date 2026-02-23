local TweenConfig = {}

TweenConfig.Delays = {
	MapName = 0.1,
	Preview = 0.2,
	CurrentItems = 0.3,
	CurrentItemsStagger = 0.1,
	Timer = 0,
	TimerWhiteBar = 0.15,
	ItemScroller = 0.35,
	ItemScrollerStagger = 0.05,
}

TweenConfig.Positions = {
	MapName = {
		hidden = UDim2.fromScale(1.5, 0.087),
		shown = UDim2.fromScale(1, 0.087),
	},
	Preview = {
		hidden = UDim2.fromScale(0.5, -0.1),
		shown = UDim2.fromScale(0.5, 0),
	},
}

TweenConfig.Elements = {
	MapName = {
		show = {
			duration = 0.7,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.4,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		fade = {
			duration = 0.5,
			easing = {Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.Out},
		},
	},

	Preview = {
		show = {
			duration = 0.6,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.35,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		fade = {
			duration = 0.5,
			easing = {Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.Out},
		},
	},

	CurrentItems = {
		show = {
			duration = 0.5,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.3,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		fade = {
			duration = 0.4,
			easing = {Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.Out},
		},
	},

	SlotTemplate = {
		show = {
			duration = 0.4,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.25,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		hover = {
			duration = 0.2,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		unhover = {
			duration = 0.15,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out},
		},
		select = {
			duration = 0.25,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
	},

	Timer = {
		show = {
			duration = 0.5,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.4,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		progressBar = {
			duration = 0.1,
			easing = {Style = Enum.EasingStyle.Linear, Direction = Enum.EasingDirection.Out},
		},
		whiteBar = {
			duration = 0.3,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out},
		},
	},

	ItemScroller = {
		show = {
			duration = 0.45,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.3,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
	},

	SwapButton = {
		show = {
			duration = 0.4,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.25,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
	},

	ItemTemplate = {
		show = {
			duration = 0.35,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.2,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		hover = {
			duration = 0.2,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		unhover = {
			duration = 0.15,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out},
		},
		select = {
			duration = 0.25,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
	},
}

function TweenConfig.get(elementName, animationType)
	local element = TweenConfig.Elements[elementName]
	if not element then
		return TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	local animation = element[animationType]
	if not animation then
		return TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	local easing = animation.easing or {}
	return TweenInfo.new(
		animation.duration or 0.3,
		easing.Style or Enum.EasingStyle.Quad,
		easing.Direction or Enum.EasingDirection.Out
	)
end

function TweenConfig.getDelay(elementName)
	return TweenConfig.Delays[elementName] or 0
end

function TweenConfig.getPosition(elementName, state)
	local positions = TweenConfig.Positions[elementName]
	if not positions then
		return UDim2.fromScale(0.5, 0.5)
	end
	return positions[state] or UDim2.fromScale(0.5, 0.5)
end

return TweenConfig