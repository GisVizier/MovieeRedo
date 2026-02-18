local TweenConfig = {}

TweenConfig.Elements = {
	Main = {
		show = {
			duration = 0.5,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
		},
		hide = {
			duration = 0.4,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.In },
		},
	},
	Pulse = {
		inward = {
			duration = 0.4,
			easing = { Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut },
		},
		outward = {
			duration = 0.4,
			easing = { Style = Enum.EasingStyle.Sine, Direction = Enum.EasingDirection.InOut },
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

return TweenConfig
