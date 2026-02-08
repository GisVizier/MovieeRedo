local TweenService = game:GetService("TweenService")

local module = {}
module.__index = module

local HEALTH_FADE_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_OUT_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local FLASH_MIN_TRANSPARENCY = 0.45

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui

	self._dmg = ui:FindFirstChild("dmg")
	self._takeDmg = ui:FindFirstChild("takedmg")

	self._currentHealthTween = nil
	self._currentFlashInTween = nil
	self._currentFlashOutTween = nil

	self._ui.Visible = true

	if self._dmg then
		self._dmg.ImageTransparency = 1
	end

	if self._takeDmg then
		self._takeDmg.ImageTransparency = 1
	end

	return self
end

function module:_cancelTween(name)
	local tween = self[name]
	if tween then
		tween:Cancel()
		self[name] = nil
	end
end

function module:_cancelAllTweens()
	self:_cancelTween("_currentHealthTween")
	self:_cancelTween("_currentFlashInTween")
	self:_cancelTween("_currentFlashOutTween")
end

function module:setHealthState(health, maxHealth)
	if not self._dmg then
		return
	end

	if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return
	end

	local startOverlayHealth = math.min(60, maxHealth)
	local targetTransparency = 1

	if health < startOverlayHealth then
		targetTransparency = math.clamp(health / startOverlayHealth, 0, 1)
	end

	self:_cancelTween("_currentHealthTween")
	self._currentHealthTween = TweenService:Create(self._dmg, HEALTH_FADE_TWEEN, {
		ImageTransparency = targetTransparency,
	})
	self._currentHealthTween:Play()
end

function module:onDamageTaken(_damage)
	if not self._takeDmg then
		return
	end

	self:_cancelTween("_currentFlashInTween")
	self:_cancelTween("_currentFlashOutTween")

	self._takeDmg.ImageTransparency = FLASH_MIN_TRANSPARENCY

	self._currentFlashOutTween = TweenService:Create(self._takeDmg, FLASH_OUT_TWEEN, {
		ImageTransparency = 1,
	})
	self._currentFlashOutTween:Play()
	self._currentFlashOutTween.Completed:Once(function()
		self._currentFlashOutTween = nil
	end)
end

function module:onHealed(_amount)
	if self._takeDmg then
		self._takeDmg.ImageTransparency = 1
	end
end

function module:bindCombatSignals()
end

function module:bindRemotes()
end

function module:show()
	self._ui.Visible = true
	return true
end

function module:hide()
	self:_cancelAllTweens()
	self._ui.Visible = false

	if self._dmg then
		self._dmg.ImageTransparency = 1
	end

	if self._takeDmg then
		self._takeDmg.ImageTransparency = 1
	end

	return true
end

function module:_cleanup()
	self:_cancelAllTweens()
end

return module
