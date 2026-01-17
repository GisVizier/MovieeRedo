local TweenService = game:GetService("TweenService")

local TweenLibrary = {}
TweenLibrary.__index = TweenLibrary

local DEFAULT_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local DIRECTIONS = {
	top = UDim2.new(0.5, 0, -1, 0),
	bottom = UDim2.new(0.5, 0, 2, 0),
	left = UDim2.new(-1, 0, 0.5, 0),
	right = UDim2.new(2, 0, 0.5, 0),
}

function TweenLibrary.new(connectionManager)
	local self = setmetatable({}, TweenLibrary)
	self._activeTweens = {}
	self._connectionManager = connectionManager
	return self
end

function TweenLibrary:tween(instance, properties, tweenInfo, groupName)
	tweenInfo = tweenInfo or DEFAULT_INFO

	local tween = TweenService:Create(instance, tweenInfo, properties)
	table.insert(self._activeTweens, tween)

	tween.Completed:Once(function()
		local index = table.find(self._activeTweens, tween)
		if index then
			table.remove(self._activeTweens, index)
		end
	end)

	if self._connectionManager and groupName then
		self._connectionManager:add(tween, groupName)
	end

	tween:Play()
	return tween
end

function TweenLibrary:tweenSequence(sequence, groupName)
	task.spawn(function()
		for _, step in sequence do
			local tween = self:tween(step.instance, step.properties, step.tweenInfo, groupName)
			if step.wait then
				tween.Completed:Wait()
			end
			if step.delay then
				task.wait(step.delay)
			end
		end
	end)
end

function TweenLibrary:fadeIn(instance, duration, groupName)
	local info = TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local property = instance:IsA("CanvasGroup") and "GroupTransparency" or "Transparency"

	if instance:IsA("GuiObject") and not instance:IsA("CanvasGroup") then
		property = "BackgroundTransparency"
	end

	return self:tween(instance, { [property] = 0 }, info, groupName)
end

function TweenLibrary:fadeOut(instance, duration, groupName)
	local info = TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local property = instance:IsA("CanvasGroup") and "GroupTransparency" or "Transparency"

	if instance:IsA("GuiObject") and not instance:IsA("CanvasGroup") then
		property = "BackgroundTransparency"
	end

	return self:tween(instance, { [property] = 1 }, info, groupName)
end

function TweenLibrary:slideIn(instance, fromDirection, duration, groupName)
	local originalPosition = instance.Position
	local startPosition = DIRECTIONS[fromDirection] or DIRECTIONS.bottom

	instance.Position = startPosition

	local info = TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	return self:tween(instance, { Position = originalPosition }, info, groupName)
end

function TweenLibrary:slideOut(instance, toDirection, duration, groupName)
	local endPosition = DIRECTIONS[toDirection] or DIRECTIONS.bottom

	local info = TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	return self:tween(instance, { Position = endPosition }, info, groupName)
end

function TweenLibrary:scaleIn(instance, duration, groupName)
	local uiScale = instance:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Scale = 0
		uiScale.Parent = instance
	else
		uiScale.Scale = 0
	end

	local info = TweenInfo.new(duration or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	return self:tween(uiScale, { Scale = 1 }, info, groupName)
end

function TweenLibrary:scaleOut(instance, duration, groupName)
	local uiScale = instance:FindFirstChildOfClass("UIScale")
	if not uiScale then
		return nil
	end

	local info = TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	return self:tween(uiScale, { Scale = 0 }, info, groupName)
end

function TweenLibrary:bounce(instance, intensity, duration, groupName)
	local uiScale = instance:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = instance
	end

	local originalScale = uiScale.Scale
	intensity = intensity or 0.1

	local info = TweenInfo.new((duration or 0.3) / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = self:tween(uiScale, { Scale = originalScale + intensity }, info, groupName)

	tween.Completed:Once(function()
		self:tween(uiScale, { Scale = originalScale }, info, groupName)
	end)

	return tween
end

function TweenLibrary:flash(instance, duration, groupName)
	local originalTransparency = instance.BackgroundTransparency
	instance.BackgroundTransparency = 0

	local info = TweenInfo.new(duration or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	return self:tween(instance, { BackgroundTransparency = originalTransparency }, info, groupName)
end

function TweenLibrary:scrollTo(scrollingFrame, position, duration, groupName)
	local info = TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	return self:tween(scrollingFrame, { CanvasPosition = position }, info, groupName)
end

function TweenLibrary:scrollToChild(scrollingFrame, child, duration, groupName)
	local targetPosition = Vector2.new(0, child.AbsolutePosition.Y - scrollingFrame.AbsolutePosition.Y)
	return self:scrollTo(scrollingFrame, targetPosition, duration, groupName)
end

function TweenLibrary:cancelAll()
	for _, tween in self._activeTweens do
		tween:Cancel()
	end
	table.clear(self._activeTweens)
end

function TweenLibrary:destroy()
	self:cancelAll()
	setmetatable(self, nil)
end

return TweenLibrary
