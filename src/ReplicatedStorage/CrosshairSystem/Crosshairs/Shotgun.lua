local module = {}
module.__index = module

module.Config = {
	velocitySensitivity = 0.085,
	verticalVelocityWeight = 0.075,
	velocityMinSpread = 0.5,
	velocityMaxSpread = 9,
	adsVelocitySensitivityMult = 1.15,

	velocityRecoveryRate = 10,
	adsVelocityRecoveryMult = 1.3,
	movingBaseSpread = 0.75,
	movingThreshold = 1,

	recoilRecoveryRate = 8,
	maxRecoil = 3,

	spreadScale = 2.35,
	maxSpread = 75,
	raycastSpreadPixelScale = 420,

	crouchMult = 0.5,
	slideMult = 0.95,
	sprintMult = 1.8,
	airMult = 2.0,
	adsMult = 0.4,

	crouchRecoilMult = 1.1,
	slideRecoilMult = 0.95,
	sprintRecoilMult = 1.1,
	airRecoilMult = 1.2,
	adsRecoilMult = 0.72,

	defaultGap = 14,
	minGap = 10,
	maxGap = 34,
	crouchMinGap = 8,
	adsMinGap = 5,

	crouchGapMult = 0.75,
	adsGapMult = 0.45,
	adsSpreadResponseMult = 1.08,
}

local function applyStrokeProps(instance, color, thickness, transparency)
	local stroke = instance:FindFirstChild("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = thickness
		stroke.Transparency = transparency
	end
end

local function positiveMultiplier(value, fallback)
	if type(value) == "number" and value > 0 then
		return value
	end
	return fallback
end

local function resolveGap(customization, weaponData, config, state)
	local rawGap = (customization and customization.gapFromCenter) or weaponData.baseGap or config.defaultGap
	local minGap = config.minGap
	local maxGap = config.maxGap

	if state then
		local gapMult = 1
		if state.isCrouching then
			gapMult *= config.crouchGapMult
			minGap = math.min(minGap, config.crouchMinGap or minGap)
		end
		if state.isADS then
			gapMult *= config.adsGapMult
			minGap = math.min(minGap, config.adsMinGap or minGap)
		end
		rawGap *= gapMult
	end

	return math.clamp(rawGap, minGap, maxGap)
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
	local frameDt = math.clamp(dt or 0, 0, 0.1)
	local velocity = state.velocity or Vector3.zero
	local customization = state.customization or self._customization
	local weaponData = state.weaponData or {}

	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local verticalSpeed = math.abs(velocity.Y)
	local effectiveSpeed = horizontalSpeed + verticalSpeed * self.Config.verticalVelocityWeight

	local targetVelocitySpread = 0
	if not customization or customization.dynamicSpreadEnabled ~= false then
		local movingBase = 0
		if effectiveSpeed > self.Config.movingThreshold then
			movingBase = self.Config.movingBaseSpread
		end
		local adsVelocitySensitivityMult = state.isADS and self.Config.adsVelocitySensitivityMult or 1
		targetVelocitySpread = math.clamp(
			movingBase + (effectiveSpeed * self.Config.velocitySensitivity * adsVelocitySensitivityMult),
			self.Config.velocityMinSpread,
			self.Config.velocityMaxSpread
		)
	end

	local adsVelocityRecoveryMult = state.isADS and self.Config.adsVelocityRecoveryMult or 1
	local velocityAlpha = math.clamp(frameDt * self.Config.velocityRecoveryRate * adsVelocityRecoveryMult, 0, 1)
	self._velocitySpread += (targetVelocitySpread - self._velocitySpread) * velocityAlpha

	local crouchMult = positiveMultiplier(weaponData.crouchMult, self.Config.crouchMult)
	local slideMult = positiveMultiplier(weaponData.slideMult, self.Config.slideMult)
	local sprintMult = positiveMultiplier(weaponData.sprintMult, self.Config.sprintMult)
	local airMult = positiveMultiplier(weaponData.airMult, self.Config.airMult)
	local adsMult = positiveMultiplier(weaponData.adsMult, self.Config.adsMult)

	local spreadStateMult = 1
	if state.isCrouching then
		spreadStateMult *= crouchMult
	elseif state.isSliding then
		spreadStateMult *= slideMult
	elseif state.isSprinting then
		spreadStateMult *= sprintMult
	end
	if state.isGrounded == false then
		spreadStateMult *= airMult
	end
	if state.isADS then
		spreadStateMult *= adsMult
	end

	local recoilRecoveryMult = 1
	if state.isCrouching then
		recoilRecoveryMult *= self.Config.crouchRecoilMult
	elseif state.isSliding then
		recoilRecoveryMult *= self.Config.slideRecoilMult
	elseif state.isSprinting then
		recoilRecoveryMult *= self.Config.sprintRecoilMult
	end
	if state.isGrounded == false then
		recoilRecoveryMult *= self.Config.airRecoilMult
	end
	if state.isADS then
		recoilRecoveryMult *= self.Config.adsRecoilMult
	end

	self._currentRecoil = math.max(
		self._currentRecoil - frameDt * self.Config.recoilRecoveryRate * recoilRecoveryMult,
		0
	)

	local adsSpreadResponseMult = state.isADS and self.Config.adsSpreadResponseMult or 1
	local spreadAmount = (self._velocitySpread + self._currentRecoil) * spreadStateMult * adsSpreadResponseMult
	local spreadX = math.clamp((weaponData.spreadX or 1) * spreadAmount * self.Config.spreadScale, 0, self.Config.maxSpread)
	local spreadY = math.clamp((weaponData.spreadY or 1) * spreadAmount * self.Config.spreadScale, 0, self.Config.maxSpread)
	local raycastSpreadMult = positiveMultiplier(state.raycastSpreadMultiplier, 1)
	local baseSpreadRadians = math.max(0, tonumber(weaponData.baseSpreadRadians) or tonumber(weaponData.baseSpread) or 0)
	if baseSpreadRadians > 0 and raycastSpreadMult > 0 then
		local raycastScale = positiveMultiplier(weaponData.raycastSpreadPixelScale, self.Config.raycastSpreadPixelScale)
		local raycastSpreadX = math.clamp(
			(weaponData.spreadX or 1) * baseSpreadRadians * raycastSpreadMult * raycastScale,
			0,
			self.Config.maxSpread
		)
		local raycastSpreadY = math.clamp(
			(weaponData.spreadY or 1) * baseSpreadRadians * raycastSpreadMult * raycastScale,
			0,
			self.Config.maxSpread
		)
		spreadX = math.max(spreadX, raycastSpreadX)
		spreadY = math.max(spreadY, raycastSpreadY)
	end
	local gap = resolveGap(customization, weaponData, self.Config, state)
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
