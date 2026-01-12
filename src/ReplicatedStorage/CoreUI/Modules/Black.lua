local module = {}
module.__index = module

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections

	self:_init()

	return self
end

function module:_init()

end

function module:show()
	self._ui.Visible = true
	local fadeTween = game.TweenService:Create(self._ui, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = .75,
	})

	fadeTween:Play()

	local blurTemplate = script:FindFirstChild("Blur")
	if blurTemplate then
		local blur = blurTemplate:Clone()
		blur.Parent = workspace.CurrentCamera

		game.TweenService:Create(blur, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = 15,
		}):Play()

		self.blur = blur
	end

	fadeTween.Completed:Wait()

	return true
end

function module:hide()
	local fadeTween = game.TweenService:Create(self._ui, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	})

	fadeTween:Play()
	
	if self.blur  then
		game.TweenService:Create(self.blur, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = 0,
		}):Play()

	end
	
	fadeTween.Completed:Wait()
	
	self._ui.Visible = false
	return true
end

function module:_cleanup()
	if self.blur then
		self.blur:Destroy()
		self.blur = nil
	end
end

return module