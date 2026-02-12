local TweenConfig = {}

-- Small, self-contained tween config for HUD.
-- Matches the get()/getDelay()/Values pattern used by other CoreUI modules.

TweenConfig.Delays = {
	Stagger = 0.12,
	WhiteBar = 0.15,
}

TweenConfig.Values = {
	SelectedScale = 1.1,
	DeselectedScale = 0.95,

	ItemDescOffset = 0.03,

	ReloadBgVisible = 0.35,
	ReloadDuration = 1.25,
	CooldownReadyDelay = 0.8,
}

TweenConfig.Elements = {
	Main = {
		show = {
			duration = 0.55,
			easing = { Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out },
		},
		hide = {
			duration = 0.35,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In },
		},
	},

	Selection = {
		update = {
			duration = 0.2,
			easing = { Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out },
		},
	},

	ItemDesc = {
		show = {
			duration = 0.25,
			easing = { Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.Out },
		},
		hide = {
			duration = 0.2,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In },
		},
	},

	Bar = {
		main = {
			duration = 0.12,
			easing = { Style = Enum.EasingStyle.Linear, Direction = Enum.EasingDirection.Out },
		},
		white = {
			duration = 0.25,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
		},
	},

	Reload = {
		fadeIn = {
			duration = 0.15,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
		},
		fadeOut = {
			duration = 0.2,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
		},
	},

	CooldownText = {
		fadeIn = {
			duration = 0.15,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
		},
		fadeOut = {
			duration = 0.4,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In },
		},
	},
}

function TweenConfig.get(elementName, animationType)
	local element = TweenConfig.Elements[elementName]
	local anim = element and element[animationType]
	if not anim then
		return TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end

	local easing = anim.easing or {}
	return TweenInfo.new(
		anim.duration or 0.3,
		easing.Style or Enum.EasingStyle.Quad,
		easing.Direction or Enum.EasingDirection.Out
	)
end

function TweenConfig.getDelay(key)
	return TweenConfig.Delays[key] or 0
end

return TweenConfig

