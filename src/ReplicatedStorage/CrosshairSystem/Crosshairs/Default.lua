local module = {}
module.__index = module

local DEBUG_CROSSHAIR = false
local DEBUG_LOG_INTERVAL = 1
local lastDebugTime = 0


module.Config = {
	-- Movement spread
	velocitySensitivity = .075,
	verticalVelocityWeight = 0.075, -- Adds Y velocity influence into spread.
	velocityMinSpread = 0,
	velocityMaxSpread = 15,
	adsVelocitySensitivityMult = 1.2,

	velocityRecoveryRate = 12,
	adsVelocityRecoveryMult = 1.35,
	movingBaseSpread = .85,
	movingThreshold = 1,

	-- Recoil spread
	recoilRecoveryRate = 10, -- studs/sec-style decay for recoil spread.
	maxRecoil = 5,

	-- Final scaling
	spreadScale = 2.0,
	maxSpread = 90,

	-- State multipliers (spread)
	crouchMult = 0.8,
	slideMult = 0.9,
	sprintMult = 1.35,
	airMult = 1.5,
	adsMult = 0.8,

	-- State multipliers (recoil recovery strength)
	crouchRecoilMult = 1.15,
	slideRecoilMult = 0.9,
	sprintRecoilMult = 1.1,
	airRecoilMult = 1.2,
	adsRecoilMult = 0.75,

	-- Gap behavior
	defaultGap = 25,
	minGap = 20,
	maxGap = 45,
	crouchMinGap = 9.5,
	adsMinGap = 5,

	crouchGapMult = 0.5, -- Crouch pulls lines slightly inward.
	adsGapMult = 0.3, -- ADS pulls lines inward more.
	adsSpreadResponseMult = 1.12,
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
	local gap = resolveGap(customization, {}, self.Config, nil)

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
task.wait(); --heyy

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

	local gap = resolveGap(customization, weaponData, self.Config, state)

	if DEBUG_CROSSHAIR then
		local now = tick()
		if now - lastDebugTime > DEBUG_LOG_INTERVAL then
			lastDebugTime = now
		end
	end

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
	if amount <= 0 then
		return
	end

	local recoilDelta = amount * recoilMultiplier
	self._currentRecoil = math.min(self._currentRecoil + recoilDelta, self.Config.maxRecoil)
end

return module
