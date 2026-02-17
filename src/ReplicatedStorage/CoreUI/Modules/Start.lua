local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataTable = require(ReplicatedStorage.PlayerDataTable)

local module = {}
module.__index = module

type ui = Frame & {
	UIListLayout: UIListLayout,
	UIScale: UIScale,

	Actions: Frame & {
		UIListLayout: UIListLayout,

		Inventory: Frame & {
			UICorner: UICorner,
			UIScale: UIScale,
			CanvasGroup: CanvasGroup,
		},

		Play: Frame & {
			UICorner: UICorner,
			UIScale: UIScale,
			CanvasGroup: CanvasGroup,
		},

		Settings: Frame & {
			UICorner: UICorner,
			UIScale: UIScale,
			CanvasGroup: CanvasGroup,
		},

		Shop: Frame & {
			UICorner: UICorner,
			UIScale: UIScale,
			CanvasGroup: CanvasGroup,
		},

		ImageButton: ImageButton,
	},

	Extras: Frame & {
		UIListLayout: UIListLayout,
		Party: ImageButton,
		Add: ImageButton,
		Template: ImageButton,
		User: ImageButton,
	},
}

type Template = Frame & {
	UICorner: UICorner,
	UIGradient: UIGradient,
	UIScale: UIScale,

	Frame: Frame & {
		UIListLayout: UIListLayout,

		Frame: Frame & {
			CanvasGroup: CanvasGroup & {
				UIListLayout: UIListLayout,
				Name: TextLabel,
				username: TextLabel,
			},
		},

		ImageLabel: ImageLabel & {
			UICorner: UICorner,
		},

		_: TextLabel,
	},
}

local TWEEN_SHOW = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_HIDE = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TWEEN_FAST = TweenInfo.new(0.01)

local TEMPLATE_SCALE_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TEMPLATE_SCALE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TEMPLATE_HOVER = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TEMPLATE_KICK_WARN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local KICK_WARNING_DURATION = 3
local TEMPLATE_BASE_LAYOUT_ORDER = 5

local ACTION_ORDER = { "Play", "Shop", "Inventory", "Settings" }
local STAGGER_DELAY = 0.25

local ActionHandlers = {}

function ActionHandlers.showChild(ui, canvas, originals)
	canvas.Position = UDim2.new(0.5, 0, -0.8, 0)
	canvas.GroupTransparency = 1

	local tweenProps = {
		Position = originals.Position,
		GroupTransparency = originals.GroupTransparency or 0,
	}

	local tween = TweenService:Create(canvas, TWEEN_SHOW, tweenProps)
	tween:Play()

	return tween
end

function ActionHandlers.hideChild(ui, canvas, originals)
	local tweenProps = {
		Position = UDim2.new(0.5, 0, -0.8, 0),
		GroupTransparency = 1,
	}

	local tween = TweenService:Create(canvas, TWEEN_HIDE, tweenProps)
	tween:Play()

	return tween
end

local currenttweens = {}

function ActionHandlers.setupHover(ui, canvas, connections, tween, originals)
	local DeviceConnections = {
		HoverStart = {
			"MouseEnter",
			"SelectionGained",
		},

		HoverEnd = {
			"MouseLeave",
			"SelectionLost",
		},
	}

	local isHovering = false

	local uiScale = ui:FindFirstChild("UIScale")
	local textLabel = canvas.Interface:FindFirstChild("TextLabel")

	local originalScale = uiScale and uiScale.Scale or 1
	local originalTextTransparency = textLabel and textLabel.TextTransparency or 1
	local originalTextPosition = textLabel and textLabel.Position or UDim2.new(0.5, 0, 0, 0)

	for _type, tbl in DeviceConnections do
		for _, device in tbl do
			if _type == "HoverStart" then
				connections:track(ui, device, function()
					if isHovering then
						return
					end

					isHovering = true

					if currenttweens[ui.Name] then
						for _, activeTween in currenttweens[ui.Name] do
							activeTween:Cancel()
						end
					end

					local sizetween = TweenService:Create(
						uiScale,
						TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{
							Scale = 1.15,
						}
					)

					local texttween = TweenService:Create(
						textLabel,
						TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						{
							TextTransparency = 0,
							Position = UDim2.new(0.5, 0, 0, -15),
						}
					)

					sizetween:Play()
					texttween:Play()

					currenttweens[ui.Name] = {
						sizetween,
						texttween,
					}
				end, "hover")
			else
				connections:track(ui, device, function()
					if not isHovering then
						return
					end

					isHovering = false

					if currenttweens[ui.Name] then
						for _, activeTween in currenttweens[ui.Name] do
							activeTween:Cancel()
						end
					end

					local sizetween = TweenService:Create(
						uiScale,
						TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{
							Scale = originalScale,
						}
					)

					local texttween = TweenService:Create(
						textLabel,
						TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{
							TextTransparency = originalTextTransparency,
							Position = originalTextPosition,
						}
					)

					sizetween:Play()
					texttween:Play()

					currenttweens[ui.Name] = {
						sizetween,
						texttween,
					}
				end, "hover")
			end
		end
	end
end

function module.start(export, ui: ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._tween = export.tween
	self._connections = export.connections
	self._actionData = {}
	self._templateData = {}
	self._templateCount = 0
	self._templateSource = script:FindFirstChild("Template")
	self._initialized = false
	self._buttonsActive = false
	self._actionDebounce = false

	self:_setupActions()

	return self
end

function module:_setupActions()
	local actions = self._ui.Actions

	for _, actionName in ACTION_ORDER do
		local actionFrame = actions:FindFirstChild(actionName)
		if not actionFrame then
			continue
		end

		local canvas = actionFrame:FindFirstChildWhichIsA("CanvasGroup")
		if not canvas then
			continue
		end

		local originalsPath = "Actions." .. actionName .. ".CanvasGroup"
		local originals = self._export:getOriginals(originalsPath)

		self._actionData[actionName] = {
			frame = actionFrame,
			canvas = canvas,
			originals = originals,
			isVisible = false,
		}
	end
end

function module:_setButtonsActive(active: boolean)
	self._buttonsActive = active

	for _, data in self._actionData do
		local button = data.canvas:FindFirstChild("Interface")
		if not button then
			continue
		end

		local actionButton = button:FindFirstChild("Action")
		if actionButton then
			actionButton.Active = active
			actionButton.Interactable = active
		end
	end

	local addButton = self._ui.Extras:FindFirstChild("Party"):FindFirstChild("Add")
	if addButton then
		addButton.Active = active
		addButton.Interactable = active
	end
end

function module:_showAction(actionName)
	local data = self._actionData[actionName]
	if not data or data.isVisible then
		return nil
	end

	data.isVisible = true

	local tween = ActionHandlers.showChild(data.frame, data.canvas, data.originals)

	ActionHandlers.setupHover(data.frame, data.canvas, self._connections, self._tween)

	return tween
end

function module:_hideAction(actionName)
	local data = self._actionData[actionName]
	if not data or not data.isVisible then
		return nil
	end

	data.isVisible = false

	self._connections:cleanupGroup("hover")

	return ActionHandlers.hideChild(data.frame, data.canvas, data.originals)
end

function module:_showExtras()
	local extras = self._ui.Extras
	local originals = self._export:getOriginals("Extras")

	if originals then
		extras.GroupTransparency = 1

		local tween = TweenService:Create(extras, TWEEN_SHOW, {
			GroupTransparency = originals.GroupTransparency or 0,
		})
		tween:Play()

		return tween
	end

	return nil
end

function module:_hideExtras()
	local extras = self._ui.Extras

	local tween = TweenService:Create(extras, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		GroupTransparency = 1,
	})
	tween:Play()

	return tween
end

function module:createTemplate(userId)
	if self._templateData[userId] then
		return self._templateData[userId].template
	end

	if not self._templateSource then
		return nil
	end

	local template: Template = self._templateSource:Clone()
	template.Name = "Template_" .. userId
	template.Visible = true

	self._templateCount += 1
	template.LayoutOrder = TEMPLATE_BASE_LAYOUT_ORDER + self._templateCount

	local uiScale = template:FindFirstChild("UIScale")
	if uiScale then
		uiScale.Scale = 0.67
	end

	template.Parent = self._ui.Extras.Party

	local displayName = ""
	local username = ""

	task.spawn(function()
		local success, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)

		if success then
			username = "@" .. name
		end

		local successDisplay, nameDisplay = pcall(function()
			local player = Players:GetPlayerByUserId(userId)
			if player then
				return player.DisplayName
			end

			return name
		end)

		if successDisplay then
			displayName = nameDisplay
		end

		local container = template:FindFirstChild("Frame")
		if container then
			local infoPanel = container:FindFirstChild("Frame")
			if infoPanel then
				local canvasGroup = infoPanel:FindFirstChild("CanvasGroup")

				if canvasGroup then
					local nameLabel = canvasGroup:FindFirstChild("_name")
					local usernameLabel = canvasGroup:FindFirstChild("usernam")

					if nameLabel then
						nameLabel.Text = displayName
					end

					if usernameLabel then
						usernameLabel.Text = username
					end
				end
			end
		end
	end)

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)

		if success and content then
			local container = template:FindFirstChild("Frame")
			if container then
				local imageLabel = container:FindFirstChild("ImageLabel")
				if imageLabel then
					imageLabel.Image = content
				end
			end
		end
	end)

	local originalGradientColor = template:FindFirstChild("UIGradient") and template.UIGradient.Color
		or ColorSequence.new(Color3.new(1, 1, 1))
	local originalBackgroundColor = template.BackgroundColor3

	self._templateData[userId] = {
		template = template,
		userId = userId,
		displayName = displayName,
		username = username,
		isKickWarning = false,
		kickResetThread = nil,
		originalGradientColor = originalGradientColor,
		originalBackgroundColor = originalBackgroundColor,
	}

	if uiScale then
		local scaleTween = TweenService:Create(uiScale, TEMPLATE_SCALE_IN, {
			Scale = 1,
		})
		scaleTween:Play()
	end

	self:_setupTemplateHover(template, userId)
	self:_setupTemplateClick(template, userId)

	return template
end

function module:removeTemplate(userId, skipEmit)
	local data = self._templateData[userId]
	if not data then
		return false
	end

	if data.kickResetThread then
		task.cancel(data.kickResetThread)
		data.kickResetThread = nil
	end

	self._connections:cleanupGroup("template_" .. userId)

	local template = data.template
	local uiScale = template:FindFirstChild("UIScale")

	--if uiScale then
	--	local scaleTween = TweenService:Create(uiScale, TEMPLATE_SCALE_OUT, {
	--		Scale = 0,
	--	})
	--	scaleTween:Play()

	--	scaleTween.Completed:Once(function()
	--		template:Destroy()
	--	end)
	--else
	template:Destroy()
	--end

	self._templateData[userId] = nil
	self._templateCount -= 1

	if not skipEmit then
		self._export:emit("PartyMemberRemoved", userId)
	end

	return true
end

function module:getTemplateData(userId)
	return self._templateData[userId]
end

function module:_setupTemplateHover(template: Template, userId)
	local DeviceConnections = {
		HoverStart = {
			"MouseEnter",
			"SelectionGained",
		},

		HoverEnd = {
			"MouseLeave",
			"SelectionLost",
		},
	}

	local isHovering = false
	local groupName = "template_" .. userId

	local container = template:FindFirstChild("Frame")
	if not container then
		return
	end

	local infoPanel: Frame = container:FindFirstChild("Frame")
	local spacer: TextLabel = container:FindFirstChild("_")

	if not infoPanel then
		return
	end

	local canvasGroup = infoPanel:FindFirstChild("CanvasGroup")
	if not canvasGroup then
		return
	end

	local originalInfoSize = infoPanel.Size
	local originalInfoTransparency = canvasGroup.GroupTransparency
	local originalSpacerTransparency = spacer and spacer.TextTransparency or 1

	infoPanel.Size = UDim2.new(originalInfoSize.X.Scale, originalInfoSize.X.Offset, 0, 0)
	canvasGroup.GroupTransparency = 1

	if spacer then
		spacer.TextTransparency = 1
	end

	for _type, tbl in DeviceConnections do
		for _, device in tbl do
			if _type == "HoverStart" then
				self._connections:track(template, device, function()
					if isHovering then
						return
					end

					isHovering = true

					infoPanel.Visible = true
					spacer.Visible = true

					if currenttweens[template.Name] then
						for _, activeTween in currenttweens[template.Name] do
							activeTween:Cancel()
						end
					end

					local sizeTween = TweenService:Create(infoPanel, TEMPLATE_HOVER, {
						Size = originalInfoSize,
					})

					local fadeTween = TweenService:Create(canvasGroup, TEMPLATE_HOVER, {
						GroupTransparency = originalInfoTransparency,
					})

					sizeTween:Play()
					fadeTween:Play()

					local tweens = { sizeTween, fadeTween }

					if spacer then
						local spacerTween = TweenService:Create(spacer, TEMPLATE_HOVER, {
							TextTransparency = 0,
						})
						spacerTween:Play()
						table.insert(tweens, spacerTween)
					end

					currenttweens[template.Name] = tweens
				end, groupName)
			else
				self._connections:track(template, device, function()
					if not isHovering then
						return
					end

					isHovering = false

					if currenttweens[template.Name] then
						for _, activeTween in currenttweens[template.Name] do
							activeTween:Cancel()
						end
					end

					local sizeTween = TweenService:Create(infoPanel, TEMPLATE_HOVER, {
						Size = UDim2.new(originalInfoSize.X.Scale, originalInfoSize.X.Offset, 0, 0),
					})

					local fadeTween = TweenService:Create(canvasGroup, TEMPLATE_HOVER, {
						GroupTransparency = 1,
					})

					sizeTween:Play()
					fadeTween:Play()

					infoPanel.Visible = false
					spacer.Visible = false

					currenttweens[template.Name] = { sizeTween, fadeTween }
				end, groupName)
			end
		end
	end
end

function module:_setupTemplateClick(template: Template, userId)
	local data = self._templateData[userId]
	if not data then
		return
	end

	local groupName = "template_" .. userId
	local gradient = template:FindFirstChild("UIGradient")

	if not gradient then
		return
	end

	local kickColor = Color3.fromRGB(255, 80, 80)

	self._connections:track(template, "Activated", function()
		if data.isKickWarning then
			if data.kickResetThread then
				task.cancel(data.kickResetThread)
				data.kickResetThread = nil
			end

			self._export:emit("KickPartyMember", userId)
			self:removeTemplate(userId, true)
		else
			data.isKickWarning = true

			if currenttweens[template.Name .. "_kick"] then
				for _, activeTween in currenttweens[template.Name .. "_kick"] do
					activeTween:Cancel()
				end
			end

			local redTween = TweenService:Create(template, TEMPLATE_KICK_WARN, {
				BackgroundColor3 = kickColor,
			})
			redTween:Play()

			currenttweens[template.Name .. "_kick"] = { redTween }

			data.kickResetThread = task.delay(KICK_WARNING_DURATION, function()
				if not data or not data.template or not data.template.Parent then
					return
				end

				data.isKickWarning = false
				data.kickResetThread = nil

				if currenttweens[template.Name .. "_kick"] then
					for _, activeTween in currenttweens[template.Name .. "_kick"] do
						activeTween:Cancel()
					end
				end

				local resetTween = TweenService:Create(template, TEMPLATE_KICK_WARN, {
					BackgroundColor3 = data.originalBackgroundColor,
				})
				resetTween:Play()

				currenttweens[template.Name .. "_kick"] = { resetTween }
			end)
		end
	end, groupName)
end

function module:_setupAddButton()
	local addButton = self._ui.Extras:FindFirstChild("Party"):FindFirstChild("Add")
	if not addButton then
		return
	end

	self._connections:track(addButton, "Activated", function()
		if not self._buttonsActive then
			return
		end

		if self._actionDebounce then
			return
		end

		self._export:show("Party", true)
		self:hideAll()
	end, "extras")
end

function module:_setupExtras()
	self:_setupAddButton()
end

function module:_setupEventListeners()
	self._export:on("PartyMemberAdded", function(data)
		if not self._templateData[data.userId] then
			self:createTemplate(data.userId)
		end
	end)

	self._export:on("PartyMemberRemoved", function(userId)
		if self._templateData[userId] then
			self:removeTemplate(userId)
		end
	end)
end

-- Visual transition for showing (fade in with TallFade)
function module:transitionIn()
	self:_setButtonsActive(false)

	task.wait(0.35)

	self._ui.Visible = true

	for _, actionName in ACTION_ORDER do
		local data = self._actionData[actionName]
		if data then
			data.canvas.Position = UDim2.new(0.5, 0, -0.8, 0)
			data.canvas.GroupTransparency = 1
		end
	end

	self._ui.Extras.GroupTransparency = 1
	self._ui.Actions.Play.CanvasGroup.Interface.Interface:FindFirstChild("UIStroke").Transparency = 1

	task.delay(STAGGER_DELAY * 1.45, function()
		self:_showExtras()
	end)

	for _, actionName in ACTION_ORDER do
		self:_showAction(actionName)
		task.wait(STAGGER_DELAY)
	end

	TweenService:Create(self._ui.Actions.Play.CanvasGroup.Interface.Interface:FindFirstChild("UIStroke"), TWEEN_HIDE, {
		Transparency = 0,
	}):Play()

	self:_setButtonsActive(true)
end

-- Visual transition for hiding (fade out with TallFade)
function module:transitionOut()
	self:_setButtonsActive(false)
	self._ui:SetAttribute("Active", false)

	self._connections:cleanupGroup("hover")
	self._connections:cleanupGroup("buttons")
	self._connections:cleanupGroup("extras")

	for userId in self._templateData do
		self._connections:cleanupGroup("template_" .. userId)
	end

	local lastTween = nil
	self:_hideExtras()

	for i = #ACTION_ORDER, 1, -1 do
		local actionName = ACTION_ORDER[i]
		lastTween = self:_hideAction(actionName)
		task.wait(0.1)
	end

	--self._export:hide("TallFade")

	if lastTween then
		lastTween.Completed:Wait()
	end

	self._ui.Visible = false

	for _, data in self._actionData do
		data.isVisible = false
	end
end

function module:show()
	self:transitionIn()
	self:_init()
end

function module:hide()
	self:transitionOut()
	return true
end

function module:_init()
	local MainUI: ui = self._ui
	MainUI:SetAttribute("Active", true)

	if self._initialized then
		return
	end

	self._initialized = true

	PlayerDataTable.init()

	local grad = MainUI.Actions.Play.CanvasGroup.Interface.Interface

	local shineInterval = 5
	local lastShineTime = os.clock()

	task.spawn(function()
		while MainUI and MainUI.Parent and MainUI:GetAttribute("Active") do
			if grad then
				local stroke = grad:FindFirstChild("UIStroke")
				if stroke and stroke:FindFirstChild("UIGradient") then
					local current = stroke.UIGradient.Rotation
					local nextRotation = (current + 0.25) % 360
					if nextRotation > 180 then
						nextRotation -= 360
					end
					stroke.UIGradient.Rotation = nextRotation
				end

				local now = os.clock()
				if now - lastShineTime >= shineInterval then
					lastShineTime = now

					local shine = grad:FindFirstChild("Shine")
					if stroke and shine:FindFirstChild("UIGradient") then
						local tween = TweenService:Create(
							shine:FindFirstChild("UIGradient"),
							TweenInfo.new(0.85, Enum.EasingStyle.Quad),
							{
								Offset = Vector2.new(1, 0),
							}
						)
						tween:Play()

						tween.Completed:Once(function()
							if MainUI and MainUI.Parent then
								shine:FindFirstChild("UIGradient").Offset = Vector2.new(-0.8, 0)
							end
						end)
					end
				end
			end

			game["Run Service"].RenderStepped:Wait()
		end
	end)

	self:_setupActionButtons()
	self:_setupExtras()
	self:_setupEventListeners()
	self:_setupLocalPlayerThumbnail()
end

function module:_setupLocalPlayerThumbnail()
	local party = self._ui.Extras:FindFirstChild("Party")
	if not party then
		return
	end

	local userFrame = party:FindFirstChild("User")
	if not userFrame then
		return
	end

	local imageLabel = userFrame:FindFirstChild("ImageLabel")
	if not imageLabel then
		return
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end

	task.spawn(function()
		userFrame.Visible = true
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				localPlayer.UserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420
			)
		end)

		if success and content then
			imageLabel.Image = content
		end
	end)
end

function module:hideAll()
	local mainCanvas = self._ui

	self:_setButtonsActive(false)

	if currenttweens["main"] then
		for _, activeTween in currenttweens["main"] do
			activeTween:Cancel()
		end
	end

	local fadeTween =
		TweenService:Create(mainCanvas, TweenInfo.new(0.67, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = 1,
			Position = UDim2.new(0, 15, 1.05, -15),
		})

	fadeTween:Play()

	currenttweens["main"] = { fadeTween }

	fadeTween.Completed:Wait()

	--self._connections:cleanupGroup("hover")
	--self._connections:cleanupGroup("buttons")
	--self._connections:cleanupGroup("extras")

	--for userId in self._templateData do
	--	self._connections:cleanupGroup("template_" .. userId)
	--end

	--for _, data in self._actionData do
	--	data.isVisible = false

	--	if data.hoverController then
	--		data.hoverController = nil
	--	end
	--end

	--self._export:setModuleState(nil, false)

	return true
end

function module:showAll()
	local mainCanvas = self._ui

	self:_setButtonsActive(false)

	if currenttweens["main"] then
		for _, activeTween in currenttweens["main"] do
			activeTween:Cancel()
		end
	end

	local originals = self._export:getOriginalsRaw(self._ui.Name)
	local targetTransparency = originals and originals.GroupTransparency or 0
	local targetposition = originals.Position
	mainCanvas.Position = UDim2.new(0, 15, 1.05, -15)

	local fadeTween =
		TweenService:Create(mainCanvas, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = targetTransparency,
			Position = targetposition,
		})

	fadeTween:Play()

	currenttweens["main"] = { fadeTween }

	fadeTween.Completed:Once(function()
		self:_setButtonsActive(true)
	end)

	self:_syncPartyTemplates()

	return true
end

function module:_syncPartyTemplates()
	local partyModule = self._export:getModule("Party")
	if not partyModule then
		return
	end

	local partyData = partyModule:getPartyData()
	if not partyData then
		return
	end

	local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId or nil

	for userId, data in partyData do
		if userId ~= localUserId and not self._templateData[userId] then
			self:createTemplate(userId)
		end
	end

	for userId in self._templateData do
		if not partyData[userId] then
			self:removeTemplate(userId)
		end
	end
end

function module:_setupActionButtons()
	for actionName, data in self._actionData do
		local button = data.canvas:FindFirstChild("Interface")
		if not button then
			continue
		end

		local actionButton = button:FindFirstChild("Action")
		if not actionButton then
			continue
		end

		self._connections:track(actionButton, "Activated", function()
			if not self._buttonsActive then
				return
			end

			if self._actionDebounce then
				return
			end

			self:_onActionActivated(actionName, data.canvas)
		end, "buttons")
	end
end

function module:_onActionActivated(actionName, actionButton)
	local coreui: Template = actionButton.Parent
	if not coreui then
		return
	end

	local uiScale = actionButton:FindFirstChild("UIScale")
	if uiScale then
		local scaleTween =
			TweenService:Create(uiScale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true), {
				Scale = 0.9,
			})
		scaleTween:Play()
	end

	if actionName == "Inventory" then
		self._actionDebounce = true

		local catgoryModule = self._export:getModule("Catgory")
		local lastScreen = "Kits"

		if catgoryModule then
			local lastCategory = catgoryModule:getLastSelectedCategory()
			if lastCategory == "Ability" then
				lastScreen = "Kits"
			elseif lastCategory == "Primary" then
				lastScreen = "Primary"
			elseif lastCategory == "Secondary" then
				lastScreen = "Secondary"
			elseif lastCategory == "Melee" then
				lastScreen = "Melee"
			end
		end

		self._export:show(lastScreen)
		self._export:show("Catgory")

		if catgoryModule then
			catgoryModule:setCurrentScreen(lastScreen)
		end

		self:hideAll()

		task.delay(1, function()
			self._actionDebounce = false
		end)
	elseif actionName == "Shop" then
		--self._export:emit("OpenShop")
	elseif actionName == "Settings" then
		self._actionDebounce = true

		self._export:show("Settings")
		self:hideAll()

		task.delay(1, function()
			self._actionDebounce = false
		end)
	elseif actionName == "Play" then
		-- Competitive matches use queue pads (MatchManager). No lobby Map flow.
		self._actionDebounce = true
		task.delay(1, function()
			self._actionDebounce = false
		end)
	end
end

function module:flashAction(actionName)
	local data = self._actionData[actionName]
	if not data then
		return
	end

	local interface = data.canvas:FindFirstChild("Interface")
	if not interface then
		return
	end

	local flash = interface:FindFirstChild("Flash", true)
	if flash then
		self._tween:flash(flash, 0.3, "flash")
	end
end

function module:_cleanup()
	self._ui:SetAttribute("Active", false)
	self._initialized = false

	self._connections:cleanupGroup("hover")
	self._connections:cleanupGroup("buttons")
	self._connections:cleanupGroup("extras")

	for userId, data in self._templateData do
		if data.kickResetThread then
			task.cancel(data.kickResetThread)
			data.kickResetThread = nil
		end

		self._connections:cleanupGroup("template_" .. userId)

		if data.template and data.template.Parent then
			data.template:Destroy()
		end
	end

	table.clear(self._templateData)
	self._templateCount = 0

	for tweenKey, tweens in currenttweens do
		for _, tween in tweens do
			tween:Cancel()
		end
	end
	table.clear(currenttweens)

	for _, data in self._actionData do
		data.isVisible = false
		data.hoverController = nil
	end
end

return module
