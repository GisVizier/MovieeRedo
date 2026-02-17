local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TweenConfig = require(script.TweenConfig)
local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local LoadoutConfig = require(ReplicatedStorage.Configs.LoadoutConfig)

local module = {}
module.__index = module

local HIDE_OFFSET = UDim2.new(1.2, 0, 0, 0)
local HEALTH_WHITE_LEAD = 0.05
local AUTO_HIDE_DURATION = 5

local currentTweens = {}
local autoHideThread = nil

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections
	self._tween = export.tween
	self._initialized = false
	self._originalPosition = ui.Position
	self._killerData = nil
	self._elements = {}

	self:_cacheElements()

	return self
end

function module:_cacheElements()
	local outerFrame = self._ui.Frame
	local innerCanvas = outerFrame.CanvasGroup
	local imageArea = innerCanvas.Frame
	local rotatedPanel = imageArea.Frame
	local bgArea = innerCanvas.CanvasGroup
	local infoFrame = outerFrame.Frame

	self._elements.playerImage = rotatedPanel.PlayerImage
	self._elements.kitIcon = imageArea.KitIcon
	self._elements.teamColorInner = bgArea.CanvasGroup.Color
	self._elements.teamColorOuter = bgArea.Color
	self._elements.teamColorBg = outerFrame.Bg.Color
	self._elements.displayName = infoFrame.DisplayName
	self._elements.userName = infoFrame.UserName
	self._elements.itemImage = outerFrame.ItemImage
	self._elements.healthFillGradient = outerFrame.HealthBarHolder.HealthBar.Image.UIGradient
	self._elements.healthWhiteGradient = outerFrame.HealthBarHolder.HealthBar.White.UIGradient

	for _, child in infoFrame:GetChildren() do
		if child:IsA("Frame") then
			if child.LayoutOrder == 2 then
				self._elements.weaponLabel = child:FindFirstChild("DisplayName")
			elseif child.LayoutOrder == 3 then
				for _, stat in child:GetChildren() do
					if stat:IsA("Frame") then
						local icon = stat:FindFirstChildWhichIsA("ImageLabel")
						if icon then
							if icon.Image:find("105873826321471") then
								self._elements.winsLabel = stat:FindFirstChild("DisplayName")
							elseif icon.Image:find("82840964166861") then
								self._elements.streakLabel = stat:FindFirstChild("DisplayName")
							end
						end
					end
				end
			end
		end
	end
end

function module:setKillerData(data)
	if not data then return end

	self._killerData = data

	local e = self._elements

	e.playerImage.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(data.userId) .. "&w=420&h=420"

	local kitData = data.kitId and KitConfig.getKit(data.kitId)
	if e.kitIcon then
		if kitData then
			e.kitIcon.Image = kitData.Icon
			e.kitIcon.Visible = true
		else
			e.kitIcon.Visible = false
		end
	end

	local weaponData = data.weaponId and LoadoutConfig.getWeapon(data.weaponId)
	if weaponData then
		if e.itemImage then
			e.itemImage.Image = weaponData.imageId
			e.itemImage.Visible = true
		end
		if e.weaponLabel then
			e.weaponLabel.Text = "ELIMINATED YOU WITH " .. weaponData.name:upper()
			e.weaponLabel.Visible = true
		end
	else
		-- Self-kill or no weapon - hide weapon elements
		if e.itemImage then
			e.itemImage.Visible = false
		end
		if e.weaponLabel then
			e.weaponLabel.Visible = false
		end
	end

	if e.displayName then
		e.displayName.Text = data.displayName
	end
	if e.userName then
		e.userName.Text = "@" .. data.userName
	end

	if e.winsLabel then
		e.winsLabel.Text = tostring(data.wins)
	end
	if e.streakLabel then
		e.streakLabel.Text = tostring(data.streak)
	end

	if data.teamColor then
		if e.teamColorInner then e.teamColorInner.ImageColor3 = data.teamColor end
		if e.teamColorOuter then e.teamColorOuter.ImageColor3 = data.teamColor end
		if e.teamColorBg then e.teamColorBg.ImageColor3 = data.teamColor end
	end

	local healthFraction = math.clamp((data.health or 100) / 100, 0, 1)
	if e.healthFillGradient then
		e.healthFillGradient.Offset = Vector2.new(healthFraction, 0.5)
	end
	if e.healthWhiteGradient then
		e.healthWhiteGradient.Offset = Vector2.new(healthFraction + HEALTH_WHITE_LEAD, 0.5)
	end
end

function module:_init()
	if self._initialized then
		return
	end

	self._initialized = true
end

function module:show()
	self._ui.Visible = true
	self._ui.GroupTransparency = 1
	self._ui.Position = HIDE_OFFSET

	if currentTweens["main"] then
		for _, t in currentTweens["main"] do
			t:Cancel()
		end
	end

	local tweenInfo = TweenConfig.get("Main", "show")
	local showTween = TweenService:Create(self._ui, tweenInfo, {
		GroupTransparency = 0,
		Position = self._originalPosition,
	})
	showTween:Play()
	currentTweens["main"] = { showTween }

	self:_init()

	self._export:emit("KillScreenShown", self._killerData)

	if autoHideThread then
		pcall(task.cancel, autoHideThread)
	end
	autoHideThread = task.delay(AUTO_HIDE_DURATION, function()
		autoHideThread = nil -- Clear before calling hide to prevent double-cancel
		self._export:hide()
	end)

	return true
end

function module:hide()
	if autoHideThread then
		pcall(task.cancel, autoHideThread)
		autoHideThread = nil
	end

	if currentTweens["main"] then
		for _, t in currentTweens["main"] do
			t:Cancel()
		end
	end

	local tweenInfo = TweenConfig.get("Main", "hide")
	local hideTween = TweenService:Create(self._ui, tweenInfo, {
		GroupTransparency = 1,
		Position = HIDE_OFFSET,
	})
	hideTween:Play()
	currentTweens["main"] = { hideTween }

	hideTween.Completed:Wait()
	self._ui.Visible = false

	self._export:emit("KillScreenHidden")

	return true
end

function module:_cleanup()
	self._initialized = false

	if autoHideThread then
		task.cancel(autoHideThread)
		autoHideThread = nil
	end

	for _, tweens in currentTweens do
		for _, t in tweens do
			t:Cancel()
		end
	end
	table.clear(currentTweens)

	self._connections:cleanupAll()
	self._killerData = nil
end

return module
