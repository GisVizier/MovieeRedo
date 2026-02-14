local MobileControls = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local LoadoutConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("LoadoutConfig"))

local LogService = nil
local function getLogService()
	if not LogService then
		LogService = require(Locations.Shared.Util.LogService)
	end
	return LogService
end

local LocalPlayer = Players.LocalPlayer

-- =============================================================================
-- LAYOUT CONSTANTS
-- =============================================================================
local EDGE = 14
local GAP = 10
local BOTTOM = 46             -- Bottom offset for action cluster

-- Sticks
local STICK_SIZE = 130
local THUMB_SIZE = 52
local CAM_STICK_SIZE = 120
local CAM_THUMB_SIZE = 46

-- Action button sizes (visual hierarchy)
local JUMP_SIZE = 86          -- Biggest  — primary thumb target
local FIRE_SIZE = 66          -- Medium   — second most used
local BTN = 48                -- Small    — utility buttons

-- Weapon slot bar
local SLOT_BTN_W = 72
local SLOT_BTN_H = 56
local SLOT_GAP = 6
local SLOT_TOP = 8            -- Top of screen, overlap CoreGui if needed

-- Colors
local COLOR = Color3.new(0, 0, 0)
local TOGGLE_COLOR = Color3.fromRGB(40, 120, 220)
local ALPHA = 0.55
local WHITE = Color3.new(1, 1, 1)

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
}

-- =============================================================================
-- INPUT GATING
-- =============================================================================
function MobileControls:_isBlocked()
	local im = self._input
	return im and (im.IsMenuOpen or im.IsChatFocused or im.IsSettingsOpen)
end

-- =============================================================================
-- INIT
-- =============================================================================
function MobileControls:Init(inputManager)
	if not UserInputService.TouchEnabled then
		return
	end

	self._input = inputManager

	self:CreateMobileUI()
	self:SetupLobbyListener()

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
		local inLobby = LocalPlayer:GetAttribute("InLobby")
		self:SetCombatMode(inLobby ~= true)
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
	self:CreateCameraStick()
	self:CreateActionCluster()
	self:CreateWeaponSlots()
end

-- =============================================================================
-- MOVEMENT STICK (Bottom-left)
-- =============================================================================
function MobileControls:CreateMovementStick()
	local container = Instance.new("Frame")
	container.Name = "MovementStickContainer"
	container.Size = UDim2.fromOffset(STICK_SIZE, STICK_SIZE)
	container.Position = UDim2.new(0, EDGE, 1, -(STICK_SIZE + BOTTOM))
	container.BackgroundTransparency = 0.6
	container.BackgroundColor3 = COLOR
	container.BorderSizePixel = 0
	container.Parent = self.ScreenGui
	Instance.new("UICorner", container).CornerRadius = UDim.new(0.5, 0)

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.Size = UDim2.fromOffset(THUMB_SIZE, THUMB_SIZE)
	thumb.Position = UDim2.new(0.5, -THUMB_SIZE / 2, 0.5, -THUMB_SIZE / 2)
	thumb.BackgroundColor3 = WHITE
	thumb.BackgroundTransparency = 0.3
	thumb.BorderSizePixel = 0
	thumb.Parent = container
	Instance.new("UICorner", thumb).CornerRadius = UDim.new(0.5, 0)

	self.MovementStick = {
		Container = container,
		Stick = thumb,
		CenterPosition = UDim2.new(0.5, -THUMB_SIZE / 2, 0.5, -THUMB_SIZE / 2),
		MaxRadius = (STICK_SIZE - THUMB_SIZE) / 2,
		IsDragging = false,
	}
	self:SetupStickInput()
end

-- =============================================================================
-- CAMERA STICK (Right side, left of action cluster)
-- =============================================================================
function MobileControls:CreateCameraStick()
	-- Widest row is row 2: FIRE + GAP + ADS + GAP + Reload = 66+10+48+10+48 = 182 from EDGE
	local clusterWidth = EDGE + FIRE_SIZE + GAP + BTN + GAP + BTN
	local container = Instance.new("Frame")
	container.Name = "CameraStickContainer"
	container.Size = UDim2.fromOffset(CAM_STICK_SIZE, CAM_STICK_SIZE)
	container.Position = UDim2.new(1, -(clusterWidth + GAP + CAM_STICK_SIZE), 1, -(CAM_STICK_SIZE + BOTTOM))
	container.BackgroundTransparency = 0.6
	container.BackgroundColor3 = COLOR
	container.BorderSizePixel = 0
	container.Parent = self.ScreenGui
	Instance.new("UICorner", container).CornerRadius = UDim.new(0.5, 0)

	local thumb = Instance.new("Frame")
	thumb.Name = "CamThumb"
	thumb.Size = UDim2.fromOffset(CAM_THUMB_SIZE, CAM_THUMB_SIZE)
	thumb.Position = UDim2.new(0.5, -CAM_THUMB_SIZE / 2, 0.5, -CAM_THUMB_SIZE / 2)
	thumb.BackgroundColor3 = WHITE
	thumb.BackgroundTransparency = 0.3
	thumb.BorderSizePixel = 0
	thumb.Parent = container
	Instance.new("UICorner", thumb).CornerRadius = UDim.new(0.5, 0)

	self.CameraStick = {
		Container = container,
		Stick = thumb,
		CenterPosition = UDim2.new(0.5, -CAM_THUMB_SIZE / 2, 0.5, -CAM_THUMB_SIZE / 2),
		MaxRadius = (CAM_STICK_SIZE - CAM_THUMB_SIZE) / 2,
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
	-- Row bottom offsets
	local r1 = BOTTOM
	local r2 = BOTTOM + JUMP_SIZE + GAP
	local r3 = r2 + FIRE_SIZE + GAP

	-- Row 1 — Jump (big) + CrouchSlide
	local jump = self:_makeBtn("Jump", JUMP_SIZE, EDGE, r1, "JUMP")
	local csRight = EDGE + JUMP_SIZE + GAP
	local csBottom = r1 + (JUMP_SIZE - BTN) / 2
	local crouchSlide = self:_makeBtn("CrouchSlide", BTN, csRight, csBottom, "C")

	-- Row 2 — Fire (medium) + ADS + Reload
	local fireRight = EDGE + (JUMP_SIZE - FIRE_SIZE) / 2 -- centered under Jump
	local fire = self:_makeBtn("Fire", FIRE_SIZE, fireRight, r2, "FIRE")
	local adsRight = fireRight + FIRE_SIZE + GAP
	local adsBottom = r2 + (FIRE_SIZE - BTN) / 2
	local ads = self:_makeBtn("ADS", BTN, adsRight, adsBottom, "ADS")
	local reloadRight = adsRight + BTN + GAP
	local reload = self:_makeBtn("Reload", BTN, reloadRight, adsBottom, "R")

	-- Row 3 — Ability + Ultimate
	local eRight = EDGE + (JUMP_SIZE - BTN) / 2 -- centered under Jump
	local ability = self:_makeBtn("Ability", BTN, eRight, r3, "E")
	local qRight = eRight + BTN + GAP
	local ultimate = self:_makeBtn("Ultimate", BTN, qRight, r3, "Q")

	self._buttons.Jump       = jump
	self._buttons.CrouchSlide = crouchSlide
	self._buttons.Fire       = fire
	self._buttons.ADS        = ads
	self._buttons.Reload     = reload
	self._buttons.Ability    = ability
	self._buttons.Ultimate   = ultimate

	-- CrouchSlide stays visible in lobby (for sliding); rest are combat-only
	self._combatButtons = { fire, ads, reload, ability, ultimate }

	self:SetupButtonInput()
end

-- =============================================================================
-- WEAPON SLOT BUTTONS (Top-right, horizontal)
-- =============================================================================
local SLOT_DEFS = {
	{ slot = "Primary",   label = "1" },
	{ slot = "Secondary", label = "2" },
	{ slot = "Melee",     label = "3" },
}

function MobileControls:CreateWeaponSlots()
	local container = Instance.new("Frame")
	container.Name = "WeaponSlots"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(1, 0)
	container.AutomaticSize = Enum.AutomaticSize.XY
	container.Size = UDim2.fromOffset(0, 0)
	container.Position = UDim2.new(1, -EDGE, 0, SLOT_TOP)
	container.Parent = self.ScreenGui
	self._slotContainer = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.Parent = container

	self._slotButtons = {}
	self._slotIcons = {}
	self._activeSlot = nil

	for i, def in ipairs(SLOT_DEFS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Slot_" .. def.slot
		btn.LayoutOrder = i
		btn.Size = UDim2.fromOffset(SLOT_BTN_W, SLOT_BTN_H)
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

function MobileControls:SetupWeaponSlotInput()
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or self:_isBlocked() then return end
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if self:IsTouchClaimed(input) then return end

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
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		local claim = self.ClaimedTouches[input]
		if claim and type(claim) == "string" and claim:sub(1, 5) == "slot_" then
			self.ClaimedTouches[input] = nil
		end
	end)
end

function MobileControls:SetupWeaponSlotListener()
	local function refreshIcons()
		local raw = LocalPlayer:GetAttribute("SelectedLoadout")
		if type(raw) ~= "string" or raw == "" then return end

		local ok, loadout = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if not ok or type(loadout) ~= "table" then return end

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
-- BUTTON HELPERS
-- =============================================================================
function MobileControls:_makeBtn(name, size, rightOff, bottomOff, text)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(size, size)
	b.Position = UDim2.new(1, -(rightOff + size), 1, -(bottomOff + size))
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
	return b
end

-- =============================================================================
-- MOVEMENT STICK INPUT
-- =============================================================================
function MobileControls:SetupStickInput()
	local stick = self.MovementStick

	local function update(input)
		if not stick.IsDragging then return end
		local cSize = stick.Container.AbsoluteSize
		local cCenter = stick.Container.AbsolutePosition + cSize / 2
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pos - cCenter
		local dist = math.min(delta.Magnitude, stick.MaxRadius)

		if delta.Magnitude > 0 then
			local dir = delta.Unit
			local fp = dir * dist
			local half = THUMB_SIZE / 2
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
		if gp or self:_isBlocked() then return end
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
		if not stick.IsDragging then return end
		local cSize = stick.Container.AbsoluteSize
		local cCenter = stick.Container.AbsolutePosition + cSize / 2
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = pos - cCenter
		local dist = math.min(delta.Magnitude, stick.MaxRadius)

		if delta.Magnitude > 0 then
			local dir = delta.Unit
			local fp = dir * dist
			local half = CAM_THUMB_SIZE / 2
			stick.Stick.Position = UDim2.fromOffset(cSize.X / 2 + fp.X - half, cSize.Y / 2 + fp.Y - half)
			local dz = 0.2
			local norm = dist / stick.MaxRadius
			if norm > dz then
				local s = (norm - dz) / (1 - dz)
				self.CameraVector = Vector2.new(
					(-fp.X / stick.MaxRadius) * s,
					(-fp.Y / stick.MaxRadius) * s
				)
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
		if gp or self:_isBlocked() then return end
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
	if not button or not button.Visible then return false end
	local p = Vector2.new(input.Position.X, input.Position.Y)
	local bp = button.AbsolutePosition
	local bs = button.AbsoluteSize
	local center = bp + bs / 2
	return (p - center).Magnitude <= math.min(bs.X, bs.Y) / 2
end

function MobileControls:SetupButtonInput()
	local B = self._buttons

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or self:_isBlocked() then return end
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		if self:IsTouchClaimed(input) then return end

		-- Jump (hold)
		if not self.ActiveTouches.Jump and self:_hitTest(input, B.Jump) then
			self.ActiveTouches.Jump = input
			self.ClaimedTouches[input] = "jump"
			self:StartAutoJump()
			return
		end

		-- Fire (hold)
		if not self.ActiveTouches.Fire and self:_hitTest(input, B.Fire) then
			self.ActiveTouches.Fire = input
			self.ClaimedTouches[input] = "fire"
			self._input:FireCallbacks("Fire", true)
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
				self._input.IsCrouching = true
				self._input:FireCallbacks("Crouch", true)
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
	end)

	UserInputService.InputEnded:Connect(function(input, _)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end

		if input == self.ActiveTouches.Fire then
			self.ActiveTouches.Fire = nil
			self.ClaimedTouches[input] = nil
			self._input:FireCallbacks("Fire", false)
		elseif input == self.ActiveTouches.Special then
			self.ActiveTouches.Special = nil
			self.ClaimedTouches[input] = nil
		elseif input == self.ActiveTouches.Jump then
			self.ActiveTouches.Jump = nil
			self.ClaimedTouches[input] = nil
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
				self._input.IsCrouching = false
				self._input:FireCallbacks("Crouch", false)
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
		end
	end)
end

-- =============================================================================
-- CROUCH/SLIDE LABEL UPDATE
-- =============================================================================
function MobileControls:_updateCrouchSlideLabel()
	local btn = self._buttons.CrouchSlide
	if not btn then return end
	local isMoving = self.MovementVector.Magnitude > 0.1
	btn.Text = isMoving and "SLIDE" or "C"
end

-- =============================================================================
-- UTILITY
-- =============================================================================
function MobileControls:GetMovementVector() return self.MovementVector end
function MobileControls:GetCameraVector() return self.CameraVector end
function MobileControls:IsTouchClaimed(input) return self.ClaimedTouches[input] ~= nil end
function MobileControls:IsTouchBeingUsedForCamera(input)
	return self.CameraTouches and self.CameraTouches[input] ~= nil
end

function MobileControls:StartAutoJump()
	if self.IsAutoJumping then return end
	self.IsAutoJumping = true
	self._input.IsJumping = true
	self._input:FireCallbacks("Jump", true)
end

function MobileControls:StopAutoJump()
	if not self.IsAutoJumping then return end
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

return MobileControls
