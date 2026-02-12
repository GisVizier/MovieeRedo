local module = {}
module.__index = module

module.Config = {
	-- Velocity-based spread (VERY HIGH for visible feedback)
	velocitySensitivity = 1.5,    -- Very high sensitivity to movement speed
	velocityMinSpread = 0,        -- Tight when standing still
	velocityMaxSpread = 60,       -- Large max spread from velocity
	velocityRecoveryRate = 3,     -- Slower recovery so changes are visible longer
	recoilRecoveryRate = 4,       -- Slower recoil recovery for visible kick
	baseScale = 0.5,
	maxSpread = 120,              -- Allow very large max spread
	maxRecoil = 8,                -- Higher max recoil for bigger kick
	
	-- Base spread when moving (always applied when speed > threshold)
	movingBaseSpread = 8,         -- Instant spread when you start moving
	movingThreshold = 1,          -- Low threshold - any movement triggers spread
	
	-- Movement state spread multipliers (VERY EXTREME for visibility)
	crouchMult = 0.3,             -- 70% reduction when crouching
	slideMult = 0.5,              -- 50% reduction when sliding
	sprintMult = 2.2,             -- 120% more spread when sprinting
	airMult = 2.5,                -- 150% more spread in air
	adsMult = 0.2,                -- 80% reduction when ADS
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
	local velocity = state.velocity or Vector3.zero
	local speed = state.speed or velocity.Magnitude
	local customization = state.customization or self._customization
	local weaponData = state.weaponData or {}

	-- Calculate base velocity spread
	local targetVelocitySpread = 0
	if not customization or customization.dynamicSpreadEnabled ~= false then
		-- Add base spread when moving (immediate feedback)
		local movingBase = 0
		if speed > self.Config.movingThreshold then
			movingBase = self.Config.movingBaseSpread
		end
		
		targetVelocitySpread = math.clamp(
			movingBase + (speed * self.Config.velocitySensitivity),
			self.Config.velocityMinSpread,
			self.Config.velocityMaxSpread
		)
	end

	local velocityRate = self.Config.velocityRecoveryRate or 1
	local velocityAlpha = math.clamp(dt * velocityRate, 0, 1)
	self._velocitySpread += (targetVelocitySpread - self._velocitySpread) * velocityAlpha

	local recoilRate = self.Config.recoilRecoveryRate or 1
	self._currentRecoil = math.max(self._currentRecoil - dt * recoilRate, 0)

	-- Calculate state multiplier based on movement state
	local stateMult = 1.0
	
	-- Get multipliers from weapon data or fall back to config defaults
	local crouchMult = weaponData.crouchMult or self.Config.crouchMult
	local slideMult = weaponData.slideMult or self.Config.slideMult
	local sprintMult = weaponData.sprintMult or self.Config.sprintMult
	local airMult = weaponData.airMult or self.Config.airMult
	local adsMult = weaponData.adsMult or self.Config.adsMult
	
	-- Apply movement state modifiers (mutually exclusive ground states)
	if state.isCrouching then
		stateMult = stateMult * crouchMult
	elseif state.isSliding then
		stateMult = stateMult * slideMult
	elseif state.isSprinting then
		stateMult = stateMult * sprintMult
	end
	
	-- Air penalty stacks with other states (big visual feedback)
	if state.isGrounded == false then
		stateMult = stateMult * airMult
	end
	
	-- ADS reduces spread
	if state.isADS then
		stateMult = stateMult * adsMult
	end

	-- Calculate final spread with state modifier (high multiplier for visible spread)
	local spreadAmount = (self._velocitySpread + self._currentRecoil) * stateMult
	local spreadX = math.clamp((weaponData.spreadX or 1) * spreadAmount * 5, 0, self.Config.maxSpread)
	local spreadY = math.clamp((weaponData.spreadY or 1) * spreadAmount * 5, 0, self.Config.maxSpread)
	
	-- Use weapon-specific base gap or fall back to customization
	local gap = weaponData.baseGap or (customization and customization.gapFromCenter) or 10

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
