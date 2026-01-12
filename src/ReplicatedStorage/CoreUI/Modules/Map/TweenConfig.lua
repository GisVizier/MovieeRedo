local TweenConfig = {}

TweenConfig.Delays = {
	BottomBar = 0.15,
	CurrentLineUp = 0.4,
	LineBg = 0,
	HideBottomBar = 0.15,
	HideTopBar = 0.3,
	PlayerTemplateStagger = 0.08,
	Rewards = 0.5,
	RewardTemplateStagger = 0.06,
	MapHolder = 0,
	MapTemplateStagger = 0.25,
	MapTemplateStart = 0.55,
	RightSideHolder = 0,
}

TweenConfig.Positions = {
	TopBar = {
		hidden = UDim2.fromScale(0, 0.0625),
		shown = UDim2.fromScale(1, 0.0625),
	},
	BottomBar = {
		hidden = UDim2.fromScale(1, 0.94),
		shown = UDim2.fromScale(0, 0.94),
	},
	CurrentLineUp = {
		hidden = UDim2.new(-0.1, 0, 0.5, 0),
		shown = UDim2.new(0, 0, 0.5, 0),
	},
	Rewards = {
		hidden = UDim2.fromScale(1.35, 0.5),
		shown = UDim2.fromScale(1, 0.5),
	},
	MapHolder = {
		hidden = UDim2.fromScale(0.12, 0.5),
		shown = UDim2.fromScale(0.19, 0.5),
	},
	RightSideHolder = {
		hidden = UDim2.fromScale(1.3, 0.5),
		shown = UDim2.fromScale(1, 0.5),
	},
}

TweenConfig.Elements = {
	TopBar = {
		show = {
			duration = 1,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.4,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		fade = {
			duration = 0.35,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
	},

	BottomBar = {
		show = {
			duration = 1,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.4,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		fade = {
			duration = 0.35,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
	},

	CurrentLineUp = {
		show = {
			duration = 1.15,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.4,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		fade = {
			duration = 0.67,
			easing = {Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.Out},
		},
	},

	LineBg = {
		show = {
			duration = 0.67,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.35,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
	},

	PlayerTemplate = {
		show = {
			duration = 1,
			easing = {Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.75,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
	},

	Rewards = {
		show = {
			duration = 0.8,
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

	RewardTemplate = {
		show = {
			duration = 0.5,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.3,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
	},

	MapHolder = {
		show = {
			duration = 0.8,
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

	MapTemplate = {
		show = {
			duration = 0.25,
			easing = {Style = Enum.EasingStyle.Back, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.15,
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

	RightSideHolder = {
		show = {
			duration = 0.6,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.35,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
		fade = {
			duration = 0.4,
			easing = {Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.Out},
		},
	},

	PlayerBlip = {
		show = {
			duration = 0.35,
			easing = {Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out},
		},
		hide = {
			duration = 0.2,
			easing = {Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In},
		},
	},
}

function TweenConfig.get(elementName, animationType)
	local element = TweenConfig.Elements[elementName]
	if not element then
		return TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	local anim = element[animationType]
	if not anim then
		return TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	return TweenInfo.new(
		anim.duration,
		anim.easing.Style,
		anim.easing.Direction
	)
end

function TweenConfig.getDelay(key)
	return TweenConfig.Delays[key] or 0
end

function TweenConfig.getPosition(elementName, state)
	local positions = TweenConfig.Positions[elementName]
	if not positions then
		return nil
	end

	return positions[state]
end

return TweenConfig
