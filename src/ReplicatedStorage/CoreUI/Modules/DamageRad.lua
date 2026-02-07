local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local module = {}
module.__index = module

local SCALE_IN_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_OUT_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local START_SCALE = 0.5
local END_SCALE = 0.7

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections

	self._player = Players.LocalPlayer
	self._character = self._player and self._player.Character or nil
	self._sourcePosition = nil

	self._isActive = false
	self._isFadingOut = false
	self._expiresAt = 0

	self._holdDuration = 1
	self._rotationOffset = 0

	self._currentScaleTween = nil
	self._currentFadeTween = nil

	self._container = ui:FindFirstChild("Frame")
	self._arrow = self._container and self._container:FindFirstChild("Arrow")
	self._uiScale = self._arrow and self._arrow:FindFirstChildOfClass("UIScale")

	self._ui.Visible = false

	if self._arrow then
		self._arrow.ImageTransparency = 1
	end

	if self._uiScale then
		self._uiScale.Scale = END_SCALE
	end

	self:_bindCharacterTracking()

	return self
end

function module:_bindCharacterTracking()
	if not self._player then
		return
	end

	self._connections:cleanupGroup("damage_rad_character")
	self._connections:track(self._player, "CharacterAdded", function(character)
		self._character = character
	end, "damage_rad_character")
end

function module:_getRootPart()
	local character = self._character
	if not character or not character.Parent then
		character = self._player and self._player.Character or nil
		self._character = character
	end

	if not character then
		return nil
	end

	return character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
end

function module:_cancelTween(name)
	local tween = self[name]
	if tween then
		tween:Cancel()
		self[name] = nil
	end
end

function module:_cancelTweens()
	self:_cancelTween("_currentScaleTween")
	self:_cancelTween("_currentFadeTween")
end

function module:_setActiveRender(active)
	if active then
		if self._connections:getGroupCount("damage_rad_active") > 0 then
			return
		end

		self._connections:track(RunService, "RenderStepped", function()
			self:_onRenderStep()
		end, "damage_rad_active")
	else
		self._connections:cleanupGroup("damage_rad_active")
	end
end

function module:_updateRotation()
	if not self._arrow or not self._sourcePosition then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local rootPart = self:_getRootPart()
	if not rootPart then
		return
	end

	local toSource = self._sourcePosition - rootPart.Position
	toSource = Vector3.new(toSource.X, 0, toSource.Z)
	if toSource.Magnitude <= 0.001 then
		return
	end

	local sourceDir = toSource.Unit

	local camLook = camera.CFrame.LookVector
	camLook = Vector3.new(camLook.X, 0, camLook.Z)
	if camLook.Magnitude <= 0.001 then
		return
	end
	camLook = camLook.Unit

	local camRight = camera.CFrame.RightVector
	camRight = Vector3.new(camRight.X, 0, camRight.Z)
	if camRight.Magnitude <= 0.001 then
		return
	end
	camRight = camRight.Unit

	local x = sourceDir:Dot(camRight)
	local y = sourceDir:Dot(camLook)
	local angle = math.deg(math.atan2(x, y)) + self._rotationOffset
	self._arrow.Rotation = angle
end

function module:_showIndicator()
	if not self._arrow then
		return
	end

	self._ui.Visible = true
	self:_cancelTweens()
	self._isFadingOut = false
	self._arrow.ImageTransparency = 0

	if self._uiScale then
		self._uiScale.Scale = START_SCALE
		self._currentScaleTween = TweenService:Create(self._uiScale, SCALE_IN_TWEEN, {
			Scale = END_SCALE,
		})
		self._currentScaleTween:Play()
	end
end

function module:_fadeOutIndicator()
	if not self._arrow or self._isFadingOut then
		return
	end

	self._isFadingOut = true
	self:_cancelTween("_currentScaleTween")

	self._currentFadeTween = TweenService:Create(self._arrow, FADE_OUT_TWEEN, {
		ImageTransparency = 1,
	})
	self._currentFadeTween:Play()
	self._currentFadeTween.Completed:Once(function()
		self._isActive = false
		self._isFadingOut = false
		self._sourcePosition = nil
		self._currentFadeTween = nil
		self:_setActiveRender(false)
		self._ui.Visible = false
	end)
end

function module:_onRenderStep()
	if not self._isActive then
		return
	end

	if os.clock() >= self._expiresAt then
		self:_fadeOutIndicator()
		return
	end

	self:_updateRotation()
end

function module:reportDamageFromPosition(worldPosition)
	if typeof(worldPosition) ~= "Vector3" then
		return
	end

	self._sourcePosition = worldPosition
	self._expiresAt = os.clock() + self._holdDuration

	self:_showIndicator()

	self._isActive = true
	self:_setActiveRender(true)
	self:_updateRotation()
end

function module:reportDamageFromPart(part)
	if not part then
		return
	end

	if part:IsA("BasePart") then
		self:reportDamageFromPosition(part.Position)
	end
end

function module:reportDamageFromCharacter(character)
	if not character then
		return
	end

	local rootPart = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		self:reportDamageFromPosition(rootPart.Position)
	end
end

function module:setCharacter(character)
	self._character = character
end

function module:setHoldDuration(seconds)
	if type(seconds) ~= "number" then
		return
	end

	self._holdDuration = math.max(seconds, 0.05)
end

function module:setRotationOffset(degrees)
	if type(degrees) ~= "number" then
		return
	end

	self._rotationOffset = degrees
end

function module:bindGameplaySignals()
end

function module:bindRemotes()
end

function module:show()
	return true
end

function module:hide()
	self:_cancelTweens()
	self:_setActiveRender(false)
	self._isActive = false
	self._isFadingOut = false
	self._sourcePosition = nil

	if self._arrow then
		self._arrow.ImageTransparency = 1
		self._arrow.Rotation = 0
	end
	self._ui.Visible = false

	if self._uiScale then
		self._uiScale.Scale = END_SCALE
	end

	return true
end

function module:_cleanup()
	self:hide()
	self._connections:cleanupGroup("damage_rad_character")
end

return module
