local module = {}
module.__index = module

module.Config = {
	velocitySensitivity = 0.15,
	velocityMinSpread = 0.5,
	velocityMaxSpread = 7.5,
	velocityRecoveryRate = 3.95,
	recoilRecoveryRate = 25,
	baseScale = 0.5,
	maxSpread = 75,
	maxRecoil = 5,
}

local function applyStrokeProps(instance, color, thickness, transparency)
	local stroke = instance:FindFirstChild("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness
		stroke.Transparency = transparency
	end
end

local function applyCorner(instance, radius)
	local corner = instance:FindFirstChild("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, radius)
	end
end

function module.new(template: Frame)
	local self = setmetatable({}, module)
	self._root = template
	self._lines = template:FindFirstChild("Lines")
	self._dot = template:FindFirstChild("Dot")
	self._uiScale = template:FindFirstChild("UIScale")
	self._top = self._lines and self._lines:FindFirstChild("Top")
	self._bottom = self._lines and self._lines:FindFirstChild("Bottom")
	self._left = self._lines and self._lines:FindFirstChild("Left")
	self._right = self._lines and self._lines:FindFirstChild("Right")
	self._currentRecoil = 0
	self._velocitySpread = 0
	self._customization = nil
	return self
end

function module:ApplyCustomization(customization)
	if not customization then
		return
	end

	self._customization = customization

	local opacity = math.clamp(customization.opacity or 1, 0, 1)
	local transparency = 1 - opacity
	local mainColor = customization.mainColor or Color3.new(1, 1, 1)
	local outlineColor = customization.outlineColor or Color3.new(0, 0, 0)
	local outlineThickness = customization.outlineThickness or 1
	local scale = customization.scale or 1

	if self._root then
		self._root.Rotation = customization.rotation or 0
	end
	if self._uiScale then
		self._uiScale.Scale = scale
	end

	if self._dot then
		self._dot.Visible = customization.showDot ~= false
		self._dot.BackgroundColor3 = mainColor
		self._dot.BackgroundTransparency = transparency
		applyStrokeProps(self._dot, outlineColor, outlineThickness, transparency)
		applyCorner(self._dot, customization.cornerRadius or 0)
		local dotSize = customization.dotSize or 2
		self._dot.Size = UDim2.fromOffset(dotSize, dotSize)
	end

	local function applyLine(line, visible)
		if not line then
			return
		end
		line.Visible = visible
		line.BackgroundColor3 = mainColor
		line.BackgroundTransparency = transparency
		applyStrokeProps(line, outlineColor, outlineThickness, transparency)
		applyCorner(line, customization.cornerRadius or 0)
	end

	applyLine(self._top, customization.showTopLine ~= false)
	applyLine(self._bottom, customization.showBottomLine ~= false)
	applyLine(self._left, customization.showLeftLine ~= false)
	applyLine(self._right, customization.showRightLine ~= false)

	local thickness = customization.lineThickness or 2
	local length = customization.lineLength or 10
	local gap = customization.gapFromCenter or 5

	if self._top then
		self._top.Size = UDim2.fromOffset(thickness, length)
		self._top.Position = UDim2.new(0.5, 0, 0.5, -gap)
	end

	if self._bottom then
		self._bottom.Size = UDim2.fromOffset(thickness, length)
		self._bottom.Position = UDim2.new(0.5, 0, 0.5, gap)
	end

	if self._left then
		self._left.Size = UDim2.fromOffset(length, thickness)
		self._left.Position = UDim2.new(0.5, -gap, 0.5, 0)
	end

	if self._right then
		self._right.Size = UDim2.fromOffset(length, thickness)
		self._right.Position = UDim2.new(0.5, gap, 0.5, 0)
	end
end

function module:Update(dt, state)
	task.wait();

	local velocity = state.velocity or Vector3.zero
	local speed = state.speed or velocity.Magnitude
	local customization = state.customization or self._customization

	local targetVelocitySpread = 0
	if not customization or customization.dynamicSpreadEnabled ~= false then
		targetVelocitySpread = math.clamp(
			speed * self.Config.velocitySensitivity,
			self.Config.velocityMinSpread,
			self.Config.velocityMaxSpread
		)
	end

	local velocityRate = self.Config.velocityRecoveryRate or 1
	local velocityAlpha = math.clamp(dt * velocityRate, 0, 1)
	self._velocitySpread += (targetVelocitySpread - self._velocitySpread) * velocityAlpha

	local recoilRate = self.Config.recoilRecoveryRate or 1
	self._currentRecoil = math.max(self._currentRecoil - dt * recoilRate, 0)

	local weaponData = state.weaponData or {}
	local spreadAmount = self._velocitySpread + self._currentRecoil
	local spreadX = math.clamp((weaponData.spreadX or 1) * spreadAmount * 4, 0, self.Config.maxSpread)
	local spreadY = math.clamp((weaponData.spreadY or 1) * spreadAmount * 4, 0, self.Config.maxSpread)
	local gap = (customization and customization.gapFromCenter) or 5

	if self._top then
		self._top.Position = UDim2.new(0.5, 0, 0.5, -(gap + spreadY))
	end

	if self._bottom then
		self._bottom.Position = UDim2.new(0.5, 0, 0.5, gap + spreadY)
	end

	if self._left then
		self._left.Position = UDim2.new(0.5, -(gap + spreadX), 0.5, 0)
	end

	if self._right then
		self._right.Position = UDim2.new(0.5, gap + spreadX, 0.5, 0)
	end
end

function module:OnRecoil(recoilData, weaponData)
	local recoilMultiplier = weaponData and weaponData.recoilMultiplier or 1
	local amount = recoilData and recoilData.amount or 0
	self._currentRecoil = math.min(self._currentRecoil + amount * recoilMultiplier, self.Config.maxRecoil)
end

return module
