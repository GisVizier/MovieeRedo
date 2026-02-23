local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local module = {}
module.__index = module

-- Tween configs — same feel as the old Arrow system
local FADE_IN_TWEEN  = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_OUT_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Damage threshold: >= this amount shows Bigger, below shows Smaller
local DAMAGE_THRESHOLD = 30

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export      = export
	self._ui          = ui
	self._connections = export.connections

	self._player    = Players.LocalPlayer
	self._character = self._player and self._player.Character or nil
	self._sourcePosition = nil

	self._isActive    = false
	self._isFadingOut = false
	self._expiresAt   = 0

	self._holdDuration   = 1
	self._rotationOffset = 0

	self._currentFadeInTween = nil
	self._currentFadeTween   = nil
	self._activeIndicator    = nil -- the CanvasGroup currently displayed

	-- New indicator refs
	self._indicator = ui:FindFirstChild("Indicator")
	self._bigger    = self._indicator and self._indicator:FindFirstChild("Bigger")
	self._smaller   = self._indicator and self._indicator:FindFirstChild("Smaller")

	-- Legacy arrow refs (kept so hide() + cleanup still work cleanly)
	self._container = ui:FindFirstChild("Frame")
	self._arrow     = self._container and self._container:FindFirstChild("Arrow")
	self._uiScale   = self._arrow and self._arrow:FindFirstChildOfClass("UIScale")

	self._ui.Visible = false

	-- Start both indicators fully hidden
	if self._bigger  then self._bigger.GroupTransparency  = 1 end
	if self._smaller then self._smaller.GroupTransparency = 1 end

	-- Keep legacy arrow hidden too
	if self._arrow then
		self._arrow.ImageTransparency = 1
	end

	self:_bindCharacterTracking()

	return self
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: character tracking
-- ─────────────────────────────────────────────────────────────────────────────

function module:_bindCharacterTracking()
	if not self._player then return end

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
	if not character then return nil end
	return character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: tween management
-- ─────────────────────────────────────────────────────────────────────────────

function module:_cancelTween(name)
	local tween = self[name]
	if tween then
		tween:Cancel()
		self[name] = nil
	end
end

function module:_cancelTweens()
	self:_cancelTween("_currentFadeInTween")
	self:_cancelTween("_currentFadeTween")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: render loop
-- ─────────────────────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: rotation
-- ─────────────────────────────────────────────────────────────────────────────

function module:_updateRotation()
	if not self._indicator or not self._sourcePosition then return end

	local camera = workspace.CurrentCamera
	if not camera then return end

	local rootPart = self:_getRootPart()
	if not rootPart then return end

	local toSource = self._sourcePosition - rootPart.Position
	toSource = Vector3.new(toSource.X, 0, toSource.Z)
	if toSource.Magnitude <= 0.001 then return end

	local sourceDir = toSource.Unit

	local camLook = camera.CFrame.LookVector
	camLook = Vector3.new(camLook.X, 0, camLook.Z)
	if camLook.Magnitude <= 0.001 then return end
	camLook = camLook.Unit

	local camRight = camera.CFrame.RightVector
	camRight = Vector3.new(camRight.X, 0, camRight.Z)
	if camRight.Magnitude <= 0.001 then return end
	camRight = camRight.Unit

	local x = sourceDir:Dot(camRight)
	local y = sourceDir:Dot(camLook)
	local angle = math.deg(math.atan2(x, y)) + self._rotationOffset

	-- Rotate the whole Indicator frame so Bigger/Smaller both point at the source
	self._indicator.Rotation = angle
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: pick which CanvasGroup to display for this hit
-- ─────────────────────────────────────────────────────────────────────────────

function module:_pickIndicator(damage)
	-- If no damage amount supplied, fall back to Bigger as default
	if type(damage) ~= "number" then
		return self._bigger or self._smaller
	end

	if damage >= DAMAGE_THRESHOLD then
		return self._bigger or self._smaller
	else
		return self._smaller or self._bigger
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: show / fade out
-- ─────────────────────────────────────────────────────────────────────────────

function module:_showIndicator(damage)
	local target = self:_pickIndicator(damage)
	if not target then return end

	self._ui.Visible = true
	self:_cancelTweens()
	self._isFadingOut = false

	-- Hide the other indicator immediately
	local other = (target == self._bigger) and self._smaller or self._bigger
	if other then
		other.GroupTransparency = 1
	end

	-- Record which CanvasGroup is active for the fade-out
	self._activeIndicator = target

	-- Fade the chosen indicator in
	target.GroupTransparency = 1
	self._currentFadeInTween = TweenService:Create(target, FADE_IN_TWEEN, {
		GroupTransparency = 0,
	})
	self._currentFadeInTween:Play()
	self._currentFadeInTween.Completed:Once(function()
		self._currentFadeInTween = nil
	end)
end

function module:_fadeOutIndicator()
	local target = self._activeIndicator
	if not target or self._isFadingOut then return end

	self._isFadingOut = true
	self:_cancelTween("_currentFadeInTween")

	self._currentFadeTween = TweenService:Create(target, FADE_OUT_TWEEN, {
		GroupTransparency = 1,
	})
	self._currentFadeTween:Play()
	self._currentFadeTween.Completed:Once(function()
		self._isActive        = false
		self._isFadingOut     = false
		self._sourcePosition  = nil
		self._activeIndicator = nil
		self._currentFadeTween = nil
		self:_setActiveRender(false)
		self._ui.Visible = false
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Internal: per-frame update
-- ─────────────────────────────────────────────────────────────────────────────

function module:_onRenderStep()
	if not self._isActive then return end

	if os.clock() >= self._expiresAt then
		self:_fadeOutIndicator()
		return
	end

	self:_updateRotation()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

--[[
	reportDamageFromPosition(worldPosition, damage?)
	
	worldPosition : Vector3  — position of the attacker / damage source
	damage        : number?  — optional damage amount used to pick Bigger vs Smaller
	                          >= DAMAGE_THRESHOLD → Bigger
	                          <  DAMAGE_THRESHOLD → Smaller
]]
function module:reportDamageFromPosition(worldPosition, damage)
	if typeof(worldPosition) ~= "Vector3" then return end

	self._sourcePosition = worldPosition
	self._expiresAt = os.clock() + self._holdDuration

	self:_showIndicator(damage)

	self._isActive = true
	self:_setActiveRender(true)
	self:_updateRotation()
end

function module:reportDamageFromPart(part, damage)
	if not part then return end
	if part:IsA("BasePart") then
		self:reportDamageFromPosition(part.Position, damage)
	end
end

function module:reportDamageFromCharacter(character, damage)
	if not character then return end
	local rootPart = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		self:reportDamageFromPosition(rootPart.Position, damage)
	end
end

function module:setCharacter(character)
	self._character = character
end

function module:setHoldDuration(seconds)
	if type(seconds) ~= "number" then return end
	self._holdDuration = math.max(seconds, 0.05)
end

function module:setRotationOffset(degrees)
	if type(degrees) ~= "number" then return end
	self._rotationOffset = degrees
end

function module:setDamageThreshold(value)
	if type(value) ~= "number" then return end
	DAMAGE_THRESHOLD = value
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
	self._isActive        = false
	self._isFadingOut     = false
	self._sourcePosition  = nil
	self._activeIndicator = nil

	if self._bigger  then self._bigger.GroupTransparency  = 1 end
	if self._smaller then self._smaller.GroupTransparency = 1 end
	if self._indicator then self._indicator.Rotation = 0 end

	-- Reset legacy arrow too
	if self._arrow then
		self._arrow.ImageTransparency = 1
		self._arrow.Rotation = 0
	end
	if self._uiScale then
		self._uiScale.Scale = 0.7
	end

	self._ui.Visible = false
	return true
end

function module:_cleanup()
	self:hide()
	self._connections:cleanupGroup("damage_rad_character")
end

return module
