local TweenService = game:GetService("TweenService")

local TweenConfig = require(script.TweenConfig)

local module = {}
module.__index = module

local SHOW_POSITION = UDim2.new(0.5, 0, 0.87, 0)
local HIDE_POSITION = UDim2.new(0.5, 0, 1.15, 0)

local currentTweens = {}

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections
	self._tween = export.tween
	self._initialized = false
	self._elements = {}
	self._arrowsVisible = false

	self:_cacheElements()

	return self
end

function module:_cacheElements()
	local innerHolder = self._ui:FindFirstChild("Spec")
	if not innerHolder then return end

	local infoPanel = innerHolder:FindFirstChild("Spec")
	if infoPanel then
		self._elements.infoPanel = infoPanel
		self._elements.display = infoPanel:FindFirstChild("display")
		self._elements.user = infoPanel:FindFirstChild("user")
		self._elements.playerImage = infoPanel:FindFirstChild("PlayerImage")
		self._elements.bar = infoPanel:FindFirstChild("Bar")
		self._elements.glow = infoPanel:FindFirstChild("Glow")
	end

	local leftArrow, rightArrow
	for _, child in innerHolder:GetChildren() do
		if child:IsA("Frame") and child.Name == "Frame" then
			if not leftArrow then
				leftArrow = child
			elseif not rightArrow then
				rightArrow = child
			end
		end
	end

	if leftArrow and rightArrow then
		local leftX = leftArrow.Position.X.Scale + leftArrow.Position.X.Offset / 1920
		local rightX = rightArrow.Position.X.Scale + rightArrow.Position.X.Offset / 1920
		if leftX > rightX then
			leftArrow, rightArrow = rightArrow, leftArrow
		end
	end

	self._elements.leftArrow = leftArrow
	self._elements.rightArrow = rightArrow

	if leftArrow then
		local btn = leftArrow:FindFirstChild("Button")
		if btn and btn:IsA("GuiButton") then
			self._connections:add(btn.Activated:Connect(function()
				self._export:emit("SpecArrowLeft")
			end))
		end
	end

	if rightArrow then
		local btn = rightArrow:FindFirstChild("Button")
		if btn and btn:IsA("GuiButton") then
			self._connections:add(btn.Activated:Connect(function()
				self._export:emit("SpecArrowRight")
			end))
		end
	end
end

function module:setTarget(data)
	if not data then return end

	local e = self._elements

	if e.display then
		e.display.Text = data.displayName or ""
	end

	if e.user then
		e.user.Text = "@" .. (data.userName or "")
	end

	if e.playerImage and data.userId then
		e.playerImage.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(data.userId) .. "&w=420&h=420"
		e.playerImage.Visible = true
	end
end

function module:setArrowsVisible(visible)
	self._arrowsVisible = visible

	local e = self._elements
	if e.leftArrow then
		e.leftArrow.Visible = visible
	end
	if e.rightArrow then
		e.rightArrow.Visible = visible
	end
end

function module:show()
	self._ui.Visible = true
	self._ui.Position = HIDE_POSITION

	if currentTweens["main"] then
		for _, t in currentTweens["main"] do
			t:Cancel()
		end
	end

	local tweenInfo = TweenConfig.get("Main", "show")
	local showTween = TweenService:Create(self._ui, tweenInfo, {
		Position = SHOW_POSITION,
	})
	showTween:Play()
	currentTweens["main"] = { showTween }

	return true
end

function module:hide()
	if currentTweens["main"] then
		for _, t in currentTweens["main"] do
			t:Cancel()
		end
	end

	local tweenInfo = TweenConfig.get("Main", "hide")
	local hideTween = TweenService:Create(self._ui, tweenInfo, {
		Position = HIDE_POSITION,
	})
	hideTween:Play()
	currentTweens["main"] = { hideTween }

	hideTween.Completed:Wait()
	self._ui.Visible = false

	return true
end

function module:_cleanup()
	self._initialized = false

	for _, tweens in currentTweens do
		for _, t in tweens do
			t:Cancel()
		end
	end
	table.clear(currentTweens)

	self._connections:cleanupAll()
end

return module
