local TweenConfig = {}

-- TweenInfo configurations by category and action
TweenConfig._configs = {
	Root = {
		show = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		hide = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	},
	Scale = {
		show = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		hide = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	},
	Bar = {
		hover = TweenInfo.new(0.15, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		unhover = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},
	Info = {
		show = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		hide = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	},
}

function TweenConfig.get(category: string, action: string): TweenInfo
	local categoryConfigs = TweenConfig._configs[category]
	if categoryConfigs then
		return categoryConfigs[action] or categoryConfigs.show or TweenInfo.new(0.25)
	end
	return TweenInfo.new(0.25)
end

return TweenConfig
