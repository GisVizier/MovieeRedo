local module = {}
module.__index = module

module.Config = {
	velocitySensitivity = 0.12,
	velocityMinSpread = 0.5,
	velocityMaxSpread = 1.6,
	velocityRecoveryRate = 0.5,
	recoilRecoveryRate = 4,
	baseScale = 0.6,
	maxSpread = 50,
	maxRecoil = 2,
	raycastSpreadPixelScale = 380,
}

local function applyStrokeProps(instance, color, thickness, transparency)
	local stroke = instance:FindFirstChild("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness
		stroke.Transparency = transparency
	end
end

function module.new(template: Frame)
	local self = setmetatable({}, module)
	self._root = template
	self._uiScale = template:FindFirstChild("UIScale", true)
	self._currentRecoil = 0
	self._velocitySpread = 0
	self._customization = nil
	self._baseSize = template.Size
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

	for _, descendant in self._root:GetDescendants() do
		if descendant:IsA("TextLabel") then
			descendant.TextColor3 = mainColor
			descendant.TextTransparency = transparency
			applyStrokeProps(descendant, outlineColor, outlineThickness, transparency)
		elseif descendant:IsA("Frame") then
			if descendant.Name == "Dot" then
				descendant.BackgroundColor3 = mainColor
				descendant.BackgroundTransparency = transparency
				applyStrokeProps(descendant, outlineColor, outlineThickness, transparency)
			end
		end
	end

	local function setVisible(name, visible)
		for _, descendant in self._root:GetDescendants() do
			if descendant.Name == name then
				descendant.Visible = visible
			end
		end
	end

	setVisible("Dot", customization.showDot ~= false)
	setVisible("Left", customization.showLeftLine ~= false)
	setVisible("Right", customization.showRightLine ~= false)
	setVisible("Top", customization.showTopLine ~= false)
	setVisible("Bottom", customization.showBottomLine ~= false)
end

function module:Update(dt, state)
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
	local raycastSpreadMult = math.max(tonumber(state.raycastSpreadMultiplier) or 1, 0.001)
	local baseSpreadRadians = math.max(0, tonumber(weaponData.baseSpreadRadians) or tonumber(weaponData.baseSpread) or 0)
	if baseSpreadRadians > 0 and raycastSpreadMult > 0 then
		local raycastScale = math.max(tonumber(weaponData.raycastSpreadPixelScale) or self.Config.raycastSpreadPixelScale, 0.001)
		local raycastSpreadX =
			math.clamp((weaponData.spreadX or 1) * baseSpreadRadians * raycastSpreadMult * raycastScale, 0, self.Config.maxSpread)
		local raycastSpreadY =
			math.clamp((weaponData.spreadY or 1) * baseSpreadRadians * raycastSpreadMult * raycastScale, 0, self.Config.maxSpread)
		spreadX = math.max(spreadX, raycastSpreadX)
		spreadY = math.max(spreadY, raycastSpreadY)
	end
	local gap = (customization and customization.gapFromCenter) or weaponData.baseGap or 0
	local gapOffset = math.max(gap, 0) * 2

	if self._root and self._baseSize then
		local baseX = self._baseSize.X
		local baseY = self._baseSize.Y
		self._root.Size = UDim2.new(
			baseX.Scale,
			baseX.Offset + gapOffset + spreadX * 2,
			baseY.Scale,
			baseY.Offset + gapOffset + spreadY * 2
		)
	end
end

function module:OnRecoil(recoilData, weaponData)
	local recoilMultiplier = weaponData and weaponData.recoilMultiplier or 1
	local amount = recoilData and recoilData.amount or 0
	self._currentRecoil = math.min(self._currentRecoil + amount * recoilMultiplier, self.Config.maxRecoil)
end

return module
