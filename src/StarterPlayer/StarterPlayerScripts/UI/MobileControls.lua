local MobileControls = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))
local PlayerDataTable = require(ReplicatedStorage:WaitForChild("PlayerDataTable"))
local Controls = require(ReplicatedStorage:WaitForChild("Global"):WaitForChild("Controls"))
local Positions = Controls.GetScaledPositions()

local LogService = nil
local function getLogService()
	if not LogService then
		LogService = require(Locations.Shared.Util.LogService)
	end
	return LogService
end

local LocalPlayer = Players.LocalPlayer

-- =============================================================================
-- STYLE CONSTANTS (colors only — layout comes from Controls.CustomizableKeybinds.DefaultPositions)
-- =============================================================================
local COLOR = Color3.new(0, 0, 0)
local TOGGLE_COLOR = Color3.fromRGB(40, 120, 220)
local ALPHA = 0.55
local WHITE = Color3.new(1, 1, 1)
local ARRANGE_SELECTED_COLOR = Color3.fromRGB(120, 180, 255)
local ARRANGE_MIN_SCALE = 0.7
local ARRANGE_MAX_SCALE = 1.45

-- =============================================================================
-- STATE
-- =============================================================================
MobileControls._input = nil

MobileControls.ScreenGui = nil
MobileControls.MovementStick = nil
MobileControls.CameraStick = nil
MobileControls.WeaponButtons = {}

MobileControls.MovementVector = Vector2.new(0, 0)
MobileControls.CameraVector = Vector2.new(0, 0)
MobileControls.ClaimedTouches = {}
MobileControls.CameraTouches = {}
MobileControls.IsAutoJumping = false
MobileControls.IsADSActive = false

MobileControls._buttons = {}
MobileControls._combatButtons = {}
MobileControls._crouchSlideIsSlide = false -- tracks what the merged button did on press
MobileControls._autoFireEnabled = false
MobileControls._autoFireActive = false
MobileControls._arrangeModeEnabled = false
MobileControls._arrangeElements = {}
MobileControls._arrangeSelectedId = nil
MobileControls._arrangePrimaryTouch = nil
MobileControls._arrangeSecondaryTouch = nil
MobileControls._arrangeTouchPositions = {}
MobileControls._arrangeDragStartTouchPos = nil
MobileControls._arrangeDragStartTopLeft = nil
MobileControls._arrangePinchInitialDistance = nil
MobileControls._arrangePinchInitialScale = 1
MobileControls._arrangeSaveQueued = false
MobileControls._lastResetNonce = 0

MobileControls.ActiveTouches = {
	Movement = nil,
	Camera = nil,
	Jump = nil,
	Fire = nil,
	Reload = nil,
	Crouch = nil, -- used for the merged CrouchSlide button
	Ability = nil,
	Ultimate = nil,
	Special = nil,
	Emote = nil,
	QuickMelee = nil,
	Inspect = nil,
	CamToggle = nil,
}

-- =============================================================================
-- INPUT GATING
-- =============================================================================
function MobileControls:_isBlocked()
	local im = self._input
	return self._arrangeModeEnabled or (im and (im.IsMenuOpen or im.IsChatFocused or im.IsSettingsOpen))
end

function MobileControls:_isToggleCrouchEnabled()
	return LocalPlayer and LocalPlayer:GetAttribute("SettingsToggleCrouch") == true
end

function MobileControls:_getViewportSize()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1920, 1080)
end

function MobileControls:_getParentAbsolutePosition(guiObject)
	local parent = guiObject and guiObject.Parent
	if parent and parent:IsA("GuiObject") then
		return parent.AbsolutePosition
	end
	return Vector2.new(0, 0)
end

function MobileControls:_getArrangeElementDataById(elementId)
	if not elementId then
		return nil
	end
	for _, data in ipairs(self._arrangeElements) do
		if data.id == elementId then
			return data
		end
	end
	return nil
end

function MobileControls:_getArrangeScaleObject(data)
	if not data or not data.scaleable then
		return nil
	end

	local existing = data.gui:FindFirstChild("_ArrangeScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	local scale = data.gui:FindFirstChildWhichIsA("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = data.gui
	end
	scale.Name = "_ArrangeScale"
	return scale
end

function MobileControls:_registerArrangeElement(id, gui, options)
	if not gui then
		return
	end

	local config = options or {}
	local data = {
		id = id,
		gui = gui,
		scaleable = config.scaleable == true,
		minScale = config.minScale or ARRANGE_MIN_SCALE,
		maxScale = config.maxScale or ARRANGE_MAX_SCALE,
		defaultPosition = gui.Position,
		defaultVisible = gui.Visible,
		defaultScale = 1,
	}

	if data.scaleable then
		local scaleObject = self:_getArrangeScaleObject(data)
		data.defaultScale = (scaleObject and scaleObject.Scale) or 1
	end

	table.insert(self._arrangeElements, data)
end

function MobileControls:_rebuildArrangeElements()
	self._arrangeElements = {}

	self:_registerArrangeElement("movement_stick", self.MovementStick and self.MovementStick.Container, {
		scaleable = false,
	})
	self:_registerArrangeElement("camera_stick", self.CameraStick and self.CameraStick.Container, {
		scaleable = false,
	})
	self:_registerArrangeElement("emote", self._buttons and self._buttons.Emote, {
		scaleable = true,
	})
	self:_registerArrangeElement("jump", self._buttons and self._buttons.Jump, {
		scaleable = true,
	})
	self:_registerArrangeElement("crouch_slide", self._buttons and self._buttons.CrouchSlide, {
		scaleable = true,
	})
	self:_registerArrangeElement("fire", self._buttons and self._buttons.Fire, {
		scaleable = true,
	})
	self:_registerArrangeElement("ads", self._buttons and self._buttons.ADS, {
		scaleable = true,
	})
	self:_registerArrangeElement("reload", self._buttons and self._buttons.Reload, {
		scaleable = true,
	})
	self:_registerArrangeElement("ability", self._buttons and self._buttons.Ability, {
		scaleable = true,
	})
	self:_registerArrangeElement("ultimate", self._buttons and self._buttons.Ultimate, {
		scaleable = true,
	})
	self:_registerArrangeElement("quick_melee", self._buttons and self._buttons.QuickMelee, {
		scaleable = true,
	})
	self:_registerArrangeElement("inspect", self._buttons and self._buttons.Inspect, {
		scaleable = true,
	})
	self:_registerArrangeElement("cam_toggle", self._buttons and self._buttons.CamToggle, {
		scaleable = true,
	})
	self:_registerArrangeElement("settings", self._buttons and self._buttons.Settings, {
		scaleable = true,
	})
	self:_registerArrangeElement("weapon_slots", self._slotContainer, {
		scaleable = true,
	})
	self:_registerArrangeElement("ammo_display", self._ammoDisplay, {
		scaleable = true,
	})

	table.sort(self._arrangeElements, function(a, b)
		local az = (a.gui and a.gui.ZIndex) or 0
		local bz = (b.gui and b.gui.ZIndex) or 0
		return az < bz
	end)
end

function MobileControls:_setArrangeSelection(elementId)
	if self._arrangeSelectedId == elementId then
		return
	end

	local previous = self:_getArrangeElementDataById(self._arrangeSelectedId)
	if previous and previous.gui then
		local stroke = previous.gui:FindFirstChild("_ArrangeSelectStroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Enabled = false
		end
	end

	self._arrangeSelectedId = elementId

	local current = self:_getArrangeElementDataById(elementId)
	if not current or not current.gui then
		return
	end

	local stroke = current.gui:FindFirstChild("_ArrangeSelectStroke")
	if not (stroke and stroke:IsA("UIStroke")) then
		stroke = Instance.new("UIStroke")
		stroke.Name = "_ArrangeSelectStroke"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = ARRANGE_SELECTED_COLOR
		stroke.Parent = current.gui
	end
	stroke.Enabled = true
end

function MobileControls:_clearArrangeTouchState()
	if self._arrangePrimaryTouch then
		self.ClaimedTouches[self._arrangePrimaryTouch] = nil
	end
	if self._arrangeSecondaryTouch then
		self.ClaimedTouches[self._arrangeSecondaryTouch] = nil
	end

	self._arrangePrimaryTouch = nil
	self._arrangeSecondaryTouch = nil
	self._arrangeDragStartTouchPos = nil
	self._arrangeDragStartTopLeft = nil
	self._arrangePinchInitialDistance = nil
	self._arrangePinchInitialScale = 1
end

function MobileControls:_setGuiTopLeft(gui, topLeft)
	if not gui then
		return
	end

	local parentPos = self:_getParentAbsolutePosition(gui)
	local absSize = gui.AbsoluteSize
	local anchor = gui.AnchorPoint
	local anchorX = (topLeft.X - parentPos.X) + (absSize.X * anchor.X)
	local anchorY = (topLeft.Y - parentPos.Y) + (absSize.Y * anchor.Y)

	gui.Position = UDim2.new(0, math.floor(anchorX + 0.5), 0, math.floor(anchorY + 0.5))
end

function MobileControls:_clampTopLeft(gui, topLeft)
	if not gui then
		return topLeft
	end

	local viewport = self:_getViewportSize()
	local size = gui.AbsoluteSize

	local maxX = math.max(0, viewport.X - size.X)
	local maxY = math.max(0, viewport.Y - size.Y)

	return Vector2.new(math.clamp(topLeft.X, 0, maxX), math.clamp(topLeft.Y, 0, maxY))
end

function MobileControls:_findArrangeElementAtPoint(point)
	for i = #self._arrangeElements, 1, -1 do
		local data = self._arrangeElements[i]
		local gui = data and data.gui
		if gui and gui.Parent and gui.Visible then
			local pos = gui.AbsolutePosition
			local size = gui.AbsoluteSize
			if point.X >= pos.X and point.X <= (pos.X + size.X) and point.Y >= pos.Y and point.Y <= (pos.Y + size.Y) then
				return data
			end
		end
	end
	return nil
end

function MobileControls:_serializeLayout()
	local layout = {
		version = 1,
		elements = {},
	}

	for _, data in ipairs(self._arrangeElements) do
		local gui = data.gui
		if gui and gui.Parent then
			local entry = {
				xScale = gui.Position.X.Scale,
				xOffset = gui.Position.X.Offset,
				yScale = gui.Position.Y.Scale,
				yOffset = gui.Position.Y.Offset,
			}

			if data.scaleable then
				local scaleObject = self:_getArrangeScaleObject(data)
				entry.scale = scaleObject and scaleObject.Scale or 1
			end

			layout.elements[data.id] = entry
		end
	end

	return layout
end

function MobileControls:_saveLayoutNow()
	local layout = self:_serializeLayout()
	PlayerDataTable.set("Gameplay", "MobileButtonLayout", layout)
end

function MobileControls:_queueSaveLayout()
	if self._arrangeSaveQueued then
		return
	end

	self._arrangeSaveQueued = true
	task.delay(0.2, function()
		self._arrangeSaveQueued = false
		self:_saveLayoutNow()
	end)
end

function MobileControls:_applySavedLayout()
	local saved = PlayerDataTable.get("Gameplay", "MobileButtonLayout")
	if type(saved) ~= "table" then
		return
	end

	local entries = saved.elements
	if type(entries) ~= "table" then
		entries = saved
	end
	if type(entries) ~= "table" then
		return
	end

	for _, data in ipairs(self._arrangeElements) do
		local gui = data.gui
		local entry = entries[data.id]
		if gui and gui.Parent and type(entry) == "table" then
			local xScale = tonumber(entry.xScale) or gui.Position.X.Scale
			local xOffset = tonumber(entry.xOffset) or gui.Position.X.Offset
			local yScale = tonumber(entry.yScale) or gui.Position.Y.Scale
			local yOffset = tonumber(entry.yOffset) or gui.Position.Y.Offset
			gui.Position = UDim2.new(xScale, xOffset, yScale, yOffset)

			if data.scaleable then
				local scaleObject = self:_getArrangeScaleObject(data)
				if scaleObject then
					local scale = tonumber(entry.scale) or data.defaultScale or 1
					scaleObject.Scale = math.clamp(scale, data.minScale, data.maxScale)
				end
			end
		end
	end
end

function MobileControls:ResetLayoutToDefaults()
	for _, data in ipairs(self._arrangeElements) do
		local gui = data.gui
		if gui and gui.Parent then
			gui.Position = data.defaultPosition
			if data.scaleable then
				local scaleObject = self:_getArrangeScaleObject(data)
				if scaleObject then
					scaleObject.Scale = data.defaultScale or 1
				end
			end
		end
	end

	self:_queueSaveLayout()
end

function MobileControls:_setAllArrangeElementsVisible(visible)
	for _, data in ipairs(self._arrangeElements) do
		local gui = data.gui
		if gui and gui.Parent then
			gui.Visible = visible
		end
	end
end

function MobileControls:_refreshCombatVisibility()
	if self._arrangeModeEnabled then
		self:SetCombatMode(true)
		self:_setAllArrangeElementsVisible(true)
		return
	end

	local inLobby = LocalPlayer:GetAttribute("InLobby")
	self:SetCombatMode(inLobby ~= true)
end

function MobileControls:SetArrangeMode(enabled)
	enabled = enabled == true
	if self._arrangeModeEnabled == enabled then
		return
	end

	self._arrangeModeEnabled = enabled

	if enabled then
		if self.ScreenGui then
			self.ScreenGui.Enabled = true
		end
		self:_setAllArrangeElementsVisible(true)
		self:SetCombatMode(true)
		self:ResetTouchState()
	else
		self:_clearArrangeTouchState()
		self:_setArrangeSelection(nil)
		self:ResetTouchState()
		self:_refreshCombatVisibility()
	end
end

function MobileControls:SetupArrangeInput()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not self._arrangeModeEnabled then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local touchPos = Vector2.new(input.Position.X, input.Position.Y)
		self._arrangeTouchPositions[input] = touchPos
		self.ClaimedTouches[input] = "arrange_blocked"

		if not self._arrangePrimaryTouch then
			local hit = self:_findArrangeElementAtPoint(touchPos)
			if not hit then
				return
			end

			self:_setArrangeSelection(hit.id)
			self._arrangePrimaryTouch = input
			self.ClaimedTouches[input] = "arrange_primary"
			self._arrangeDragStartTouchPos = touchPos
			self._arrangeDragStartTopLeft = hit.gui.AbsolutePosition
			return
		end

		if self._arrangeSecondaryTouch then
			return
		end

		local selected = self:_getArrangeElementDataById(self._arrangeSelectedId)
		if not selected or not selected.scaleable then
			return
		end

		local primaryPos = self._arrangeTouchPositions[self._arrangePrimaryTouch]
		if not primaryPos then
			return
		end

		self._arrangeSecondaryTouch = input
		self.ClaimedTouches[input] = "arrange_secondary"
		self._arrangePinchInitialDistance = math.max((touchPos - primaryPos).Magnitude, 1)
		local scaleObject = self:_getArrangeScaleObject(selected)
		self._arrangePinchInitialScale = (scaleObject and scaleObject.Scale) or 1
	end)

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed or not self._arrangeModeEnabled then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local touchPos = Vector2.new(input.Position.X, input.Position.Y)
		if self._arrangeTouchPositions[input] == nil then
			return
		end
		self._arrangeTouchPositions[input] = touchPos

		local selected = self:_getArrangeElementDataById(self._arrangeSelectedId)
		if not selected or not selected.gui then
			return
		end

		if self._arrangeSecondaryTouch and (input == self._arrangePrimaryTouch or input == self._arrangeSecondaryTouch) then
			local primaryPos = self._arrangeTouchPositions[self._arrangePrimaryTouch]
			local secondaryPos = self._arrangeTouchPositions[self._arrangeSecondaryTouch]
			if not primaryPos or not secondaryPos then
				return
			end

			local initialDistance = self._arrangePinchInitialDistance or 1
			local currentDistance = math.max((secondaryPos - primaryPos).Magnitude, 1)
			local rawScale = (self._arrangePinchInitialScale or 1) * (currentDistance / initialDistance)

			local scaleObject = self:_getArrangeScaleObject(selected)
			if scaleObject then
				scaleObject.Scale = math.clamp(rawScale, selected.minScale, selected.maxScale)
			end
			return
		end

		if input == self._arrangePrimaryTouch and self._arrangeDragStartTouchPos and self._arrangeDragStartTopLeft then
			local delta = touchPos - self._arrangeDragStartTouchPos
			local targetTopLeft = self._arrangeDragStartTopLeft + delta
			targetTopLeft = self:_clampTopLeft(selected.gui, targetTopLeft)
			self:_setGuiTopLeft(selected.gui, targetTopLeft)
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		self._arrangeTouchPositions[input] = nil

		if not self._arrangeModeEnabled then
			return
		end
		self.ClaimedTouches[input] = nil

		if input ~= self._arrangePrimaryTouch and input ~= self._arrangeSecondaryTouch then
			return
		end

		self:_clearArrangeTouchState()
		self:_queueSaveLayout()
	end)
end

function MobileControls:SetupArrangeSettingsListener()
	self._lastResetNonce = tonumber(LocalPlayer:GetAttribute("SettingsMobileButtonsResetNonce")) or 0

	LocalPlayer:GetAttributeChangedSignal("SettingsArrangeMobileButtons"):Connect(function()
		local enabled = LocalPlayer:GetAttribute("SettingsArrangeMobileButtons") == true
		self:SetArrangeMode(enabled)
	end)

	LocalPlayer:GetAttributeChangedSignal("SettingsMobileButtonsResetNonce"):Connect(function()
		local nonce = tonumber(LocalPlayer:GetAttribute("SettingsMobileButtonsResetNonce")) or 0
		if nonce == self._lastResetNonce then
			return
		end
		self._lastResetNonce = nonce
		self:ResetLayoutToDefaults()
	end)

	task.defer(function()
		local enabled = LocalPlayer:GetAttribute("SettingsArrangeMobileButtons") == true
		self:SetArrangeMode(enabled)
	end)
end

-- =============================================================================
-- INIT
-- =============================================================================
function MobileControls:Init(inputManager)
	if not UserInputService.TouchEnabled then
		return
	end

	self._input = inputManager
	PlayerDataTable.init()

	self:CreateMobileUI()
	self:SetupArrangeInput()
	self:SetupArrangeSettingsListener()
	self:SetupLobbyListener()
	self:_setupViewportListener()
	self:_setupAutoFireListener()

	if self._input then
		self._input.IsSprinting = true
		self._input:FireCallbacks("Sprint", true)
	end

	getLogService():Debug("MOBILE_UI", "MobileControls initialized")
end

-- =============================================================================
-- LOBBY / MATCH VISIBILITY
-- =============================================================================
function MobileControls:SetupLobbyListener()
	local function update()
		self:_refreshCombatVisibility()
	end
	LocalPlayer:GetAttributeChangedSignal("InLobby"):Connect(update)
	task.defer(update)
end

function MobileControls:SetCombatMode(enabled)
	for _, btn in ipairs(self._combatButtons) do
		btn.Visible = enabled
	end
	if self.CameraStick then
		self.CameraStick.Container.Visible = enabled
	end
	if self._slotContainer then
		self._slotContainer.Visible = enabled
	end
	if self._ammoDisplay then
		self._ammoDisplay.Visible = enabled
	end
end

-- =============================================================================
-- TOUCH STATE RESET
-- =============================================================================
function MobileControls:ResetTouchState()
	if self.MovementStick then
		self.MovementStick.IsDragging = false
		self.MovementStick.Stick.Position = self.MovementStick.CenterPosition
		self.MovementVector = Vector2.new(0, 0)
	end
	if self.CameraStick then
		self.CameraStick.IsDragging = false
		self.CameraStick.Stick.Position = self.CameraStick.CenterPosition
		self.CameraVector = Vector2.new(0, 0)
	end

	self.IsAutoJumping = false
	self._crouchSlideIsSlide = false

	if self._autoFireActive then
		self._autoFireActive = false
		if self._buttons.Fire then
			self._buttons.Fire.BackgroundColor3 = COLOR
		end
		if self._input then
			self._input:FireCallbacks("Fire", false)
		end
	end

	if self.IsADSActive then
		self.IsADSActive = false
		if self._buttons.ADS then
			self._buttons.ADS.BackgroundColor3 = COLOR
		end
	end

	for k, _ in pairs(self.ActiveTouches) do
		self.ActiveTouches[k] = nil
	end
	self.ClaimedTouches = {}

	if self._input then
		self._input:FireCallbacks("Emotes", false)
	end

	self:_updateCrouchSlideLabel()
end

-- =============================================================================
-- UI CREATION
-- =============================================================================
function MobileControls:CreateMobileUI()
	self.ScreenGui = Instance.new("ScreenGui")
	self.ScreenGui.Name = "MobileControls"
	self.ScreenGui.ResetOnSpawn = false
	self.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self.ScreenGui.DisplayOrder = 10
	self.ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	self:CreateMovementStick()
	self:CreateEmoteButton()
	self:CreateSettingsButton()
	self:CreateCameraStick()
	self:CreateActionCluster()
	self:CreateWeaponSlots()
	self:CreateMobileAmmoDisplay()
	self:_rebuildArrangeElements()
	self:_applySavedLayout()
end

-- =============================================================================
-- MOVEMENT STICK (Bottom-left)
-- =============================================================================
function MobileControls:CreateMovementStick()
	local cfg = Positions.MovementStick
	local stickSize = cfg.Size
	local thumbSize = cfg.ThumbSize

	local container = Instance.new("Frame")
	container.Name = "MovementStickContainer"
	container.Size = UDim2.fromOffset(stickSize, stickSize)
	container.Position = cfg.Position
	container.BackgroundTransparency = 0.6
	container.BackgroundColor3 = COLOR
	container.BorderSizePixel = 0
	container.Parent = self.ScreenGui
	Instance.new("UICorner", container).CornerRadius = UDim.new(0.5, 0)

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.Size = UDim2.fromOffset(thumbSize, thumbSize)
	thumb.Position = UDim2.new(0.5, -thumbSize / 2, 0.5, -thumbSize / 2)
	thumb.BackgroundColor3 = WHITE
	thumb.BackgroundTransparency = 0.3
	thumb.BorderSizePixel = 0
	thumb.Parent = container
	Instance.new("UICorner", thumb).CornerRadius = UDim.new(0.5, 0)

	self.MovementStick = {
		Container = container,
		Stick = thumb,
		ThumbSize = thumbSize,
		CenterPosition = UDim2.new(0.5, -thumbSize / 2, 0.5, -thumbSize / 2),
		MaxRadius = (stickSize - thumbSize) / 2,
		IsDragging = false,
	}
	self:SetupStickInput()
end

-- =============================================================================
-- EMOTE BUTTON (Left side, above movement stick)
-- =============================================================================
function MobileControls:CreateEmoteButton()
	local cfg = Positions.Emote
	local size = cfg.Size
	local leftOff = cfg.LeftOffset
	local bottomOff = cfg.BottomOffset
	local label = cfg.Label or "B"

	local btn = Instance.new("TextButton")
	btn.Name = "Emote"
	btn.Size = UDim2.fromOffset(size, size)
	btn.Position = UDim2.new(0, leftOff, 1, -(bottomOff + size))
	btn.BackgroundColor3 = COLOR
	btn.BackgroundTransparency = ALPHA
	btn.BorderSizePixel = 0
	btn.TextColor3 = WHITE
	btn.TextSize = math.clamp(math.floor(size * 0.28), 10, 18)
	btn.Font = Enum.Font.SourceSansBold
	btn.Text = label
	btn.Active = false
	btn.Parent = self.ScreenGui
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	self._buttons.Emote = btn
	self:SetupEmoteButtonInput()
end

-- =============================================================================
-- SETTINGS BUTTON (Top-left, always visible)
-- =============================================================================
function MobileControls:CreateSettingsButton()
	local cfg = Positions.Settings
	if not cfg then
		return
	end

	local btn = self:_makeBtn("Settings", cfg)
	self._buttons.Settings = btn
	self:SetupSettingsButtonInput()
end

function MobileControls:SetupSettingsButtonInput()
	local btn = self._buttons.Settings
	if not btn or not self._input then
		return
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if self:IsTouchClaimed(input) then
			return
		end
		if not self:_hitTest(input, btn) then
			return
		end

		self.ClaimedTouches[input] = "settings"
		self._input:FireCallbacks("Settings", true)
	end)

	UserInputService.InputEnded:Connect(function(input, _)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if self.ClaimedTouches[input] == "settings" then
			self.ClaimedTouches[input] = nil
		end
	end)
end

-- =============================================================================
-- CAMERA STICK (Right side, left of action cluster)
-- =============================================================================
function MobileControls:CreateCameraStick()
	local cfg = Positions.CameraStick
	local camSize = cfg.Size
	local thumbSize = cfg.ThumbSize

	local container = Instance.new("Frame")
	container.Name = "CameraStickContainer"
	container.Size = UDim2.fromOffset(camSize, camSize)
	container.Position = cfg.Position
	container.BackgroundTransparency = 0.6
	container.BackgroundColor3 = COLOR
	container.BorderSizePixel = 0
	container.Parent = self.ScreenGui
	Instance.new("UICorner", container).CornerRadius = UDim.new(0.5, 0)

	local thumb = Instance.new("Frame")
	thumb.Name = "CamThumb"
	thumb.Size = UDim2.fromOffset(thumbSize, thumbSize)
	thumb.Position = UDim2.new(0.5, -thumbSize / 2, 0.5, -thumbSize / 2)
	thumb.BackgroundColor3 = WHITE
	thumb.BackgroundTransparency = 0.3
	thumb.BorderSizePixel = 0
	thumb.Parent = container
	Instance.new("UICorner", thumb).CornerRadius = UDim.new(0.5, 0)

	self.CameraStick = {
		Container = container,
		Stick = thumb,
		ThumbSize = thumbSize,
		CenterPosition = UDim2.new(0.5, -thumbSize / 2, 0.5, -thumbSize / 2),
		MaxRadius = (camSize - thumbSize) / 2,
		IsDragging = false,
	}
	self:SetupCameraStickInput()
end

-- =============================================================================
-- ACTION CLUSTER (Bottom-right)
-- =============================================================================
--  Layout (right-anchored, from bottom up):
--
--  Row 3:         [E]  [Q]
--  Row 2:   [R] [ADS]  [FIRE]
--  Row 1:        [C/S]  [JUMP]
--
--  Jump is biggest (86), Fire is medium (66), rest are small (48).
-- =============================================================================
function MobileControls:CreateActionCluster()
	local P = Positions

	local jump = self:_makeBtn("Jump", P.Jump)
	local crouchSlide = self:_makeBtn("CrouchSlide", P.CrouchSlide)
	local fire = self:_makeBtn("Fire", P.Fire)
	local ads = self:_makeBtn("ADS", P.ADS)
	local reload = self:_makeBtn("Reload", P.Reload)
	local ability = self:_makeBtn("Ability", P.Ability)
	local ultimate = self:_makeBtn("Ultimate", P.Ultimate)
	local quickMelee = self:_makeBtn("QuickMelee", P.QuickMelee)
	local inspect = self:_makeBtn("Inspect", P.Inspect)
	local camToggle = self:_makeBtn("CamToggle", P.CamToggle)

	self._buttons.Jump = jump
	self._buttons.CrouchSlide = crouchSlide
	self._buttons.Fire = fire
	self._buttons.ADS = ads
	self._buttons.Reload = reload
	self._buttons.Ability = ability
	self._buttons.Ultimate = ultimate
	self._buttons.QuickMelee = quickMelee
	self._buttons.Inspect = inspect
	self._buttons.CamToggle = camToggle

	-- CrouchSlide stays visible in lobby (for sliding); rest are combat-only
	self._combatButtons = { fire, ads, reload, ability, ultimate, quickMelee, inspect, camToggle }

	self:SetupButtonInput()
end

-- =============================================================================
-- WEAPON SLOT BUTTONS (Top-right, horizontal)
-- =============================================================================
local SLOT_DEFS = {
	{ slot = "Primary", label = "1" },
	{ slot = "Secondary", label = "2" },
	{ slot = "Melee", label = "3" },
}

function MobileControls:CreateWeaponSlots()
	local slotCfg = Positions.WeaponSlots

	local container = Instance.new("Frame")
	container.Name = "WeaponSlots"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(1, 0)
	container.AutomaticSize = Enum.AutomaticSize.XY
	container.Size = UDim2.fromOffset(0, 0)
	container.Position = slotCfg.Position
	container.Parent = self.ScreenGui
	self._slotContainer = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, slotCfg.Gap)
	layout.Parent = container

	self._slotButtons = {}
	self._slotIcons = {}
	self._activeSlot = nil

	for i, def in ipairs(SLOT_DEFS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Slot_" .. def.slot
		btn.LayoutOrder = i
		btn.Size = UDim2.fromOffset(slotCfg.ButtonWidth, slotCfg.ButtonHeight)
		btn.BackgroundColor3 = COLOR
		btn.BackgroundTransparency = ALPHA
		btn.BorderSizePixel = 0
		btn.Text = ""
		btn.Active = false
		btn.ClipsDescendants = true
		btn.Parent = container
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Size = UDim2.new(1.8, 0, 1.8, 0)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = ""
		icon.Parent = btn

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = WHITE
		label.TextSize = 16
		label.Font = Enum.Font.SourceSansBold
		label.Text = def.label
		label.Parent = btn

		self._slotButtons[def.slot] = btn
		self._slotIcons[def.slot] = { icon = icon, label = label }
	end

	self:SetupWeaponSlotInput()
	self:SetupWeaponSlotListener()
end

-- =============================================================================
-- MOBILE AMMO DISPLAY (Super small, rightmost corner - reference style)
-- =============================================================================
local AMMO_FONT = Enum.Font.GothamBold

function MobileControls:CreateMobileAmmoDisplay()
	local ammoCfg = Positions.AmmoDisplay

	local container = Instance.new("Frame")
	container.Name = "MobileAmmoDisplay"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(1, 1)
	container.Size = ammoCfg.Size
	container.Position = ammoCfg.Position
	container.Parent = self.ScreenGui
	self._ammoDisplay = container

	-- Ammo row: current (larger) + total (smaller, right/above)
	local ammoRow = Instance.new("Frame")
	ammoRow.Name = "AmmoRow"
	ammoRow.BackgroundTransparency = 1
	ammoRow.Size = UDim2.new(1, 0, 0, 18)
	ammoRow.Position = UDim2.new(0, 0, 0, 0)
	ammoRow.Parent = container

	local currentLabel = Instance.new("TextLabel")
	currentLabel.Name = "Current"
	currentLabel.Size = UDim2.fromOffset(28, 18)
	currentLabel.Position = UDim2.new(0, 0, 0, 0)
	currentLabel.BackgroundTransparency = 1
	currentLabel.TextColor3 = WHITE
	currentLabel.TextSize = 16
	currentLabel.Font = AMMO_FONT
	currentLabel.Text = "0"
	currentLabel.TextXAlignment = Enum.TextXAlignment.Left
	currentLabel.Parent = ammoRow

	local totalLabel = Instance.new("TextLabel")
	totalLabel.Name = "Total"
	totalLabel.Size = UDim2.fromOffset(26, 12)
	totalLabel.Position = UDim2.new(0, 26, 0, -1)
	totalLabel.BackgroundTransparency = 1
	totalLabel.TextColor3 = WHITE
	totalLabel.TextSize = 11
	totalLabel.Font = AMMO_FONT
	totalLabel.Text = "/ 0"
	totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	totalLabel.Parent = ammoRow

	local weaponLabel = Instance.new("TextLabel")
	weaponLabel.Name = "WeaponName"
	weaponLabel.Size = UDim2.new(1, 0, 0, 12)
	weaponLabel.Position = UDim2.new(0, 0, 0, 18)
	weaponLabel.BackgroundTransparency = 1
	weaponLabel.TextColor3 = WHITE
	weaponLabel.TextSize = 11
	weaponLabel.Font = AMMO_FONT
	weaponLabel.Text = ""
	weaponLabel.TextXAlignment = Enum.TextXAlignment.Left
	weaponLabel.Parent = container

	self._ammoCurrentLabel = currentLabel
	self._ammoTotalLabel = totalLabel
	self._ammoWeaponLabel = weaponLabel

	self:SetupMobileAmmoListener()
end

function MobileControls:SetupMobileAmmoListener()
	local function update()
		local equipped = LocalPlayer:GetAttribute("EquippedSlot") or "Primary"
		local attrName = equipped .. "Data"
		local raw = LocalPlayer:GetAttribute(attrName)
		if type(raw) ~= "string" or raw == "" then
			self._ammoCurrentLabel.Text = "0"
			self._ammoTotalLabel.Text = "/ 0"
			self._ammoWeaponLabel.Text = ""
			return
		end

		local ok, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not ok or type(data) ~= "table" then
			return
		end

		local ammo = data.Ammo or 0
		local maxAmmo = data.MaxAmmo or 0
		local clipSize = data.ClipSize or 0
		local usesAmmo = clipSize > 0 or maxAmmo > 0

		if usesAmmo then
			self._ammoCurrentLabel.Text = tostring(ammo)
			self._ammoTotalLabel.Text = "/ " .. tostring(maxAmmo)
			local outOfAmmo = ammo <= 0 and maxAmmo <= 0
			self._ammoCurrentLabel.TextColor3 = outOfAmmo and Color3.fromRGB(250, 70, 70) or WHITE
			self._ammoTotalLabel.TextColor3 = outOfAmmo and Color3.fromRGB(250, 70, 70) or Color3.fromRGB(200, 200, 200)
		else
			self._ammoCurrentLabel.Text = ""
			self._ammoTotalLabel.Text = ""
		end

		self._ammoWeaponLabel.Text = tostring(data.Gun or data.GunId or "")
	end

	for _, slot in ipairs({ "Primary", "Secondary", "Melee" }) do
		LocalPlayer:GetAttributeChangedSignal(slot .. "Data"):Connect(update)
	end
	LocalPlayer:GetAttributeChangedSignal("EquippedSlot"):Connect(update)
	task.defer(update)
end

function MobileControls:SetupWeaponSlotInput()
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or self:_isBlocked() then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if self:IsTouchClaimed(input) then
			return
		end

		for _, def in ipairs(SLOT_DEFS) do
			local btn = self._slotButtons[def.slot]
			if btn and btn.Visible and self:_hitTest(input, btn) then
				self.ClaimedTouches[input] = "slot_" .. def.slot
				self._input:FireCallbacks("SlotChange", def.slot)
				return
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local claim = self.ClaimedTouches[input]
		if claim and type(claim) == "string" and claim:sub(1, 5) == "slot_" then
			self.ClaimedTouches[input] = nil
		end
	end)
end

function MobileControls:SetupWeaponSlotListener()
	local function refreshIcons()
		local raw = LocalPlayer:GetAttribute("SelectedLoadout")
		if type(raw) ~= "string" or raw == "" then
			return
		end

		local ok, loadout = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not ok or type(loadout) ~= "table" then
			return
		end

		local data = loadout.loadout or loadout

		for _, def in ipairs(SLOT_DEFS) do
			local parts = self._slotIcons[def.slot]
			if parts then
				local weaponId = data[def.slot]
				local weaponConfig = weaponId and LoadoutConfig.getWeapon(weaponId)
				local imageId = weaponConfig and weaponConfig.imageId

				if imageId and imageId ~= "" then
					parts.icon.Image = imageId
					parts.icon.Visible = true
					parts.label.Visible = false
				else
					parts.icon.Image = ""
					parts.icon.Visible = false
					parts.label.Visible = true
				end
			end
		end
	end

	LocalPlayer:GetAttributeChangedSignal("SelectedLoadout"):Connect(refreshIcons)
	task.defer(refreshIcons)

	local function refreshHighlight()
		local equipped = LocalPlayer:GetAttribute("EquippedSlot") or "Primary"
		self._activeSlot = equipped

		for slotName, btn in pairs(self._slotButtons) do
			if slotName == equipped then
				btn.BackgroundColor3 = TOGGLE_COLOR
				btn.BackgroundTransparency = 0.3
			else
				btn.BackgroundColor3 = COLOR
				btn.BackgroundTransparency = ALPHA
			end
		end
	end

	LocalPlayer:GetAttributeChangedSignal("EquippedSlot"):Connect(refreshHighlight)
	task.defer(refreshHighlight)
end

-- =============================================================================
-- EMOTE BUTTON INPUT
-- =============================================================================
function MobileControls:SetupEmoteButtonInput()
	local btn = self._buttons.Emote
	if not btn or not self._input then
		return
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or self:_isBlocked() then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if self:IsTouchClaimed(input) then
			return
		end
		if not self:_hitTest(input, btn) then
			return
		end

		self.ActiveTouches.Emote = input
		self.ClaimedTouches[input] = "emote"
		self._input:FireCallbacks("Emotes", true)
	end)

	UserInputService.InputEnded:Connect(function(input, _)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if input ~= self.ActiveTouches.Emote then
			return
		end

		self.ActiveTouches.Emote = nil
		self.ClaimedTouches[input] = nil
		self._input:FireCallbacks("Emotes", false)
	end)
end

-- =============================================================================
-- BUTTON HELPERS
-- =============================================================================
function MobileControls:_makeBtn(name, cfg)
	local size = cfg.Size
	local bottomOff = cfg.BottomOffset
	local text = cfg.Label or ""

	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(size, size)

	if cfg.TopOffset then
		if cfg.RightOffset then
			b.Position = UDim2.new(1, -(cfg.RightOffset + size), 0, cfg.TopOffset)
		else
			local leftOff = cfg.LeftOffset or 0
			b.Position = UDim2.new(0, leftOff, 0, cfg.TopOffset)
		end
	elseif cfg.LeftOffset then
		b.Position = UDim2.new(0, cfg.LeftOffset, 1, -(bottomOff + size))
	else
		local rightOff = cfg.RightOffset or 0
		b.Position = UDim2.new(1, -(rightOff + size), 1, -(bottomOff + size))
	end

	b.BackgroundColor3 = COLOR
	b.BackgroundTransparency = ALPHA
	b.BorderSizePixel = 0
	b.TextColor3 = WHITE
	b.TextSize = math.clamp(math.floor(size * 0.28), 10, 18)
	b.Font = Enum.Font.SourceSansBold
	b.Text = text
	b.Active = false
	b.Parent = self.ScreenGui
	Instance.new("UICorner", b).CornerRadius = UDim.new(0.5, 0)

	if cfg.Icon then
		b.Text = ""
		local iconSize = math.floor(size * 0.7)
		local icon = Instance.new("ImageLabel")
		icon.Name = "_Icon"
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromOffset(iconSize, iconSize)
		icon.BackgroundTransparency = 1
		icon.Image = cfg.Icon.Image
		icon.ImageRectOffset = cfg.Icon.ImageRectOffset
		icon.ImageRectSize = cfg.Icon.ImageRectSize
		icon.Parent = b
		b:SetAttribute("_IconRectOffset", cfg.Icon.ImageRectOffset)
		b:SetAttribute("_IconPressedRectOffset", cfg.Icon.PressedImageRectOffset)
	end

	return b
end

function MobileControls:_setButtonPressed(btn, pressed)
	if not btn then
		return
	end
	local icon = btn:FindFirstChild("_Icon")
	if icon and icon:IsA("ImageLabel") then
		local normalOffset = btn:GetAttribute("_IconRectOffset")
		local pressedOffset = btn:GetAttribute("_IconPressedRectOffset")
		if pressed and pressedOffset then
			icon.ImageRectOffset = pressedOffset
		elseif normalOffset then
			icon.ImageRectOffset = normalOffset
		end
	end
	btn.BackgroundTransparency = pressed and (ALPHA - 0.15) or ALPHA
end

-- =============================================================================
-- MOVEMENT STICK INPUT
-- =============================================================================
function MobileControls:SetupStickInput()
	local stick = self.MovementStick

	local function update(input)
		if not stick.IsDragging then
			return
		end
		local cSize = stick.Container.AbsoluteSize
		local cCenter = stick.Container.AbsolutePosition + cSize / 2
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pos - cCenter
		local dist = math.min(delta.Magnitude, stick.MaxRadius)

		if delta.Magnitude > 0 then
			local dir = delta.Unit
			local fp = dir * dist
			local half = stick.ThumbSize / 2
			stick.Stick.Position = UDim2.fromOffset(cSize.X / 2 + fp.X - half, cSize.Y / 2 + fp.Y - half)
			local dz = 0.15
			local norm = dist / stick.MaxRadius
			if norm > dz then
				local s = (norm - dz) / (1 - dz)
				self.MovementVector = Vector2.new((fp.X / stick.MaxRadius) * s, (-fp.Y / stick.MaxRadius) * s)
			else
				self.MovementVector = Vector2.new(0, 0)
			end
		else
			stick.Stick.Position = stick.CenterPosition
			self.MovementVector = Vector2.new(0, 0)
		end
		self._input.Movement = self.MovementVector
		self._input:FireCallbacks("Movement", self.MovementVector)

		-- Update CrouchSlide button label based on movement
		self:_updateCrouchSlideLabel()
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or self:_isBlocked() then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch and not self.ActiveTouches.Movement then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			local cp = stick.Container.AbsolutePosition
			local cs = stick.Container.AbsoluteSize
			if p.X >= cp.X and p.X <= cp.X + cs.X and p.Y >= cp.Y and p.Y <= cp.Y + cs.Y then
				self.ActiveTouches.Movement = input
				stick.IsDragging = true
				self.ClaimedTouches[input] = "movement"
				update(input)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input, _)
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Movement then
			update(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input, _)
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Movement then
			self.ActiveTouches.Movement = nil
			stick.IsDragging = false
			stick.Stick.Position = stick.CenterPosition
			self.MovementVector = Vector2.new(0, 0)
			self.ClaimedTouches[input] = nil
			self._input.Movement = self.MovementVector
			self._input:FireCallbacks("Movement", self.MovementVector)
			self:_updateCrouchSlideLabel()
		end
	end)
end

-- =============================================================================
-- CAMERA STICK INPUT
-- =============================================================================
function MobileControls:SetupCameraStickInput()
	local stick = self.CameraStick

	local function update(input)
		if not stick.IsDragging then
			return
		end
		local cSize = stick.Container.AbsoluteSize
		local cCenter = stick.Container.AbsolutePosition + cSize / 2
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pos - cCenter
		local dist = math.min(delta.Magnitude, stick.MaxRadius)

		if delta.Magnitude > 0 then
			local dir = delta.Unit
			local fp = dir * dist
			local half = stick.ThumbSize / 2
			stick.Stick.Position = UDim2.fromOffset(cSize.X / 2 + fp.X - half, cSize.Y / 2 + fp.Y - half)
			local dz = 0.2
			local norm = dist / stick.MaxRadius
			if norm > dz then
				local s = (norm - dz) / (1 - dz)
				self.CameraVector = Vector2.new((-fp.X / stick.MaxRadius) * s, (-fp.Y / stick.MaxRadius) * s)
			else
				self.CameraVector = Vector2.new(0, 0)
			end
		else
			stick.Stick.Position = stick.CenterPosition
			self.CameraVector = Vector2.new(0, 0)
		end
		self._input:FireCallbacks("Camera", self.CameraVector)
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or self:_isBlocked() then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch and not self.ActiveTouches.Camera then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			local cp = stick.Container.AbsolutePosition
			local cs = stick.Container.AbsoluteSize
			if p.X >= cp.X and p.X <= cp.X + cs.X and p.Y >= cp.Y and p.Y <= cp.Y + cs.Y then
				self.ActiveTouches.Camera = input
				stick.IsDragging = true
				self.ClaimedTouches[input] = "camera"
				update(input)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input, _)
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Camera then
			update(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input, _)
		if input.UserInputType == Enum.UserInputType.Touch and input == self.ActiveTouches.Camera then
			self.ActiveTouches.Camera = nil
			stick.IsDragging = false
			stick.Stick.Position = stick.CenterPosition
			self.CameraVector = Vector2.new(0, 0)
			self.ClaimedTouches[input] = nil
			self._input:FireCallbacks("Camera", self.CameraVector)
		end
	end)
end

-- =============================================================================
-- ACTION BUTTON INPUT
-- =============================================================================
function MobileControls:_hitTest(input, button)
	if not button or not button.Visible then
		return false
	end
	local p = Vector2.new(input.Position.X, input.Position.Y)
	local bp = button.AbsolutePosition
	local bs = button.AbsoluteSize
	local center = bp + bs / 2
	return (p - center).Magnitude <= math.min(bs.X, bs.Y) / 2
end

function MobileControls:SetupButtonInput()
	local B = self._buttons

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or self:_isBlocked() then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if self:IsTouchClaimed(input) then
			return
		end

		-- Jump (hold)
		if not self.ActiveTouches.Jump and self:_hitTest(input, B.Jump) then
			self.ActiveTouches.Jump = input
			self.ClaimedTouches[input] = "jump"
			self:_setButtonPressed(B.Jump, true)
			self:StartAutoJump()
			return
		end

		-- Fire (hold / auto-fire toggle)
		if not self.ActiveTouches.Fire and self:_hitTest(input, B.Fire) then
			self.ActiveTouches.Fire = input
			self.ClaimedTouches[input] = "fire"
			if self._autoFireEnabled then
				self._autoFireActive = not self._autoFireActive
				self._input:FireCallbacks("Fire", self._autoFireActive)
				B.Fire.BackgroundColor3 = self._autoFireActive and TOGGLE_COLOR or COLOR
			else
				self._input:FireCallbacks("Fire", true)
			end
			return
		end

		-- ADS toggle
		if not self.ActiveTouches.Special and self:_hitTest(input, B.ADS) then
			self.ActiveTouches.Special = input
			self.ClaimedTouches[input] = "ads"
			self.IsADSActive = not self.IsADSActive
			self._input:FireCallbacks("Special", self.IsADSActive)
			B.ADS.BackgroundColor3 = self.IsADSActive and TOGGLE_COLOR or COLOR
			return
		end

		-- Reload
		if not self.ActiveTouches.Reload and self:_hitTest(input, B.Reload) then
			self.ActiveTouches.Reload = input
			self.ClaimedTouches[input] = "reload"
			self._input:FireCallbacks("Reload", true)
			return
		end

		-- CrouchSlide — context-sensitive: moving → Slide, still → Crouch
		if not self.ActiveTouches.Crouch and self:_hitTest(input, B.CrouchSlide) then
			self.ActiveTouches.Crouch = input
			self.ClaimedTouches[input] = "crouchslide"
			local isMoving = self.MovementVector.Magnitude > 0.1
			if isMoving then
				self._crouchSlideIsSlide = true
				self._input:FireCallbacks("Slide", true)
			else
				self._crouchSlideIsSlide = false
				if self:_isToggleCrouchEnabled() then
					self._input.IsCrouching = not self._input.IsCrouching
					self._input:FireCallbacks("Crouch", self._input.IsCrouching)
				else
					self._input.IsCrouching = true
					self._input:FireCallbacks("Crouch", true)
				end
			end
			return
		end

		-- Ability (hold)
		if not self.ActiveTouches.Ability and self:_hitTest(input, B.Ability) then
			self.ActiveTouches.Ability = input
			self.ClaimedTouches[input] = "ability"
			self._input:FireCallbacks("Ability", Enum.UserInputState.Begin)
			return
		end

		-- Ultimate (hold)
		if not self.ActiveTouches.Ultimate and self:_hitTest(input, B.Ultimate) then
			self.ActiveTouches.Ultimate = input
			self.ClaimedTouches[input] = "ultimate"
			self._input:FireCallbacks("Ultimate", Enum.UserInputState.Begin)
			return
		end

		-- QuickMelee (instant)
		if not self.ActiveTouches.QuickMelee and self:_hitTest(input, B.QuickMelee) then
			self.ActiveTouches.QuickMelee = input
			self.ClaimedTouches[input] = "quickmelee"
			self._input:FireCallbacks("QuickMelee", true)
			return
		end

		-- Inspect (toggle)
		if not self.ActiveTouches.Inspect and self:_hitTest(input, B.Inspect) then
			self.ActiveTouches.Inspect = input
			self.ClaimedTouches[input] = "inspect"
			self._input:FireCallbacks("Inspect", true)
			return
		end

		-- Camera Toggle (instant)
		if not self.ActiveTouches.CamToggle and self:_hitTest(input, B.CamToggle) then
			self.ActiveTouches.CamToggle = input
			self.ClaimedTouches[input] = "camtoggle"
			self._input:FireCallbacks("ToggleCameraMode", true)
			return
		end
	end)

	UserInputService.InputEnded:Connect(function(input, _)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		if input == self.ActiveTouches.Fire then
			self.ActiveTouches.Fire = nil
			self.ClaimedTouches[input] = nil
			if not self._autoFireActive then
				self._input:FireCallbacks("Fire", false)
			end
		elseif input == self.ActiveTouches.Special then
			self.ActiveTouches.Special = nil
			self.ClaimedTouches[input] = nil
		elseif input == self.ActiveTouches.Jump then
			self.ActiveTouches.Jump = nil
			self.ClaimedTouches[input] = nil
			self:_setButtonPressed(self._buttons.Jump, false)
			self:StopAutoJump()
		elseif input == self.ActiveTouches.Reload then
			self.ActiveTouches.Reload = nil
			self.ClaimedTouches[input] = nil
		elseif input == self.ActiveTouches.Crouch then
			self.ActiveTouches.Crouch = nil
			self.ClaimedTouches[input] = nil
			if self._crouchSlideIsSlide then
				self._input:FireCallbacks("Slide", false)
			else
				if not self:_isToggleCrouchEnabled() then
					self._input.IsCrouching = false
					self._input:FireCallbacks("Crouch", false)
				end
			end
			self._crouchSlideIsSlide = false
		elseif input == self.ActiveTouches.Ability then
			self.ActiveTouches.Ability = nil
			self.ClaimedTouches[input] = nil
			self._input:FireCallbacks("Ability", Enum.UserInputState.End)
		elseif input == self.ActiveTouches.Ultimate then
			self.ActiveTouches.Ultimate = nil
			self.ClaimedTouches[input] = nil
			self._input:FireCallbacks("Ultimate", Enum.UserInputState.End)
		elseif input == self.ActiveTouches.QuickMelee then
			self.ActiveTouches.QuickMelee = nil
			self.ClaimedTouches[input] = nil
		elseif input == self.ActiveTouches.Inspect then
			self.ActiveTouches.Inspect = nil
			self.ClaimedTouches[input] = nil
		elseif input == self.ActiveTouches.CamToggle then
			self.ActiveTouches.CamToggle = nil
			self.ClaimedTouches[input] = nil
		end
	end)
end

-- =============================================================================
-- CROUCH/SLIDE LABEL UPDATE
-- =============================================================================
function MobileControls:_updateCrouchSlideLabel()
	local btn = self._buttons.CrouchSlide
	if not btn then
		return
	end
	local isMoving = self.MovementVector.Magnitude > 0.1
	btn.Text = isMoving and "SLIDE" or "C"
end

-- =============================================================================
-- UTILITY
-- =============================================================================
function MobileControls:GetMovementVector()
	return self.MovementVector
end
function MobileControls:GetCameraVector()
	return self.CameraVector
end
function MobileControls:IsTouchClaimed(input)
	return self.ClaimedTouches[input] ~= nil
end
function MobileControls:IsTouchBeingUsedForCamera(input)
	return self.CameraTouches and self.CameraTouches[input] ~= nil
end

function MobileControls:StartAutoJump()
	if self.IsAutoJumping then
		return
	end
	self.IsAutoJumping = true
	self._input.IsJumping = true
	self._input:FireCallbacks("Jump", true)
end

function MobileControls:StopAutoJump()
	if not self.IsAutoJumping then
		return
	end
	self.IsAutoJumping = false
	self._input.IsJumping = false
	self._input:FireCallbacks("Jump", false)
end

function MobileControls:IsAutoJumpActive()
	return self.IsAutoJumping
end

function MobileControls:ResetADS()
	if self.IsADSActive then
		self.IsADSActive = false
		self._input:FireCallbacks("Special", false)
		if self._buttons.ADS then
			self._buttons.ADS.BackgroundColor3 = COLOR
		end
	end
end

-- =============================================================================
-- VIEWPORT LISTENER (responsive rescaling on rotation)
-- =============================================================================
function MobileControls:_setupViewportListener()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		Positions = Controls.GetScaledPositions()
	end)
end

-- =============================================================================
-- AUTO-FIRE SETTINGS LISTENER
-- =============================================================================
function MobileControls:_setupAutoFireListener()
	self._autoFireEnabled = LocalPlayer:GetAttribute("SettingsAutoFireEnabled") == true

	LocalPlayer:GetAttributeChangedSignal("SettingsAutoFireEnabled"):Connect(function()
		local enabled = LocalPlayer:GetAttribute("SettingsAutoFireEnabled") == true
		self._autoFireEnabled = enabled
		if not enabled and self._autoFireActive then
			self._autoFireActive = false
			if self._buttons.Fire then
				self._buttons.Fire.BackgroundColor3 = COLOR
			end
			if self._input then
				self._input:FireCallbacks("Fire", false)
			end
		end
	end)
end

return MobileControls
