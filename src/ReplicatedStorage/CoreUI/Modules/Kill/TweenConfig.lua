local TweenConfig = {}

TweenConfig.Elements = {
	Main = {
		show = {
			duration = 0.67,
			easing = { Style = Enum.EasingStyle.Quad, Direction = Enum.EasingDirection.Out },
		},
		hide = {
			duration = 0.45,
			easing = { Style = Enum.EasingStyle.Quint, Direction = Enum.EasingDirection.In },
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
