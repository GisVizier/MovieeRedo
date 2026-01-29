local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogueService = require(ReplicatedStorage:WaitForChild("Dialogue"))
local Configs = ReplicatedStorage:WaitForChild("Configs")
local KitConfig = require(Configs:WaitForChild("KitConfig"))

local module = {}
module.__index = module

local TWEEN_IN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.67, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

function module.start(export, ui)
	local self = setmetatable({}, module)
	self._export = export
	self._ui = ui
	self._connections = export.connections
	self._tween = export.tween
	self._initialized = false
	self._active = false
	self._currentTweens = {}
	self:_init()
	return self
end

function module:_init()
	if self._initialized then
		return
	end

	self._initialized = true

	self._template = self._ui:FindFirstChild("Template")
	self._data = self._template and self._template:FindFirstChild("Data") or nil
	self._texts = self._template and self._template:FindFirstChild("Texts") or nil
	self._textTemplate = self._texts and self._texts:FindFirstChild("Template") or nil
	self._textLabel = self._textTemplate and self._textTemplate:FindFirstChild("MainText") or nil
	self._icon = self._data and self._data:FindFirstChild("Icon") or nil
	self._glow = self._data and self._data:FindFirstChild("Glow") or nil
	self._talking = self._data and self._data:FindFirstChild("Talking") or nil
	self._talkingText = self._talking and self._talking:FindFirstChild("MainText") or nil

	if self._template then
		self._originalPosition = self._template.Position
		self._template.Visible = false
		self._template.GroupTransparency = 1
	end

	self._connections:add(DialogueService.onLine:connect(function(payload)
		self:_onLine(payload)
	end), "dialogue")
	self._connections:add(DialogueService.onStop:connect(function()
		self:_hide()
	end), "dialogue")
	self._connections:add(DialogueService.onFinish:connect(function()
		self:_hide()
	end), "dialogue")
end

function module:_cancelTweens()
	for _, tween in self._currentTweens do
		if tween then
			pcall(function()
				tween:Cancel()
			end)
		end
	end
	table.clear(self._currentTweens)
end

function module:_show()
	if not self._template then
		return
	end
	if self._active then
		return
	end
	self._active = true
	self._ui.Visible = true
	self._template.Visible = true
	self:_cancelTweens()
	local startPos = self._originalPosition + UDim2.new(0, 0, 0.01, 0)
	self._template.Position = startPos
	self._template.GroupTransparency = 1
	local tween = self._tween:tween(self._template, {
		Position = self._originalPosition,
		GroupTransparency = 0,
	}, TWEEN_IN, "dialogue")
	table.insert(self._currentTweens, tween)
end

function module:_hide()
	if not self._template then
		return
	end
	if not self._active then
		return
	end
	self._active = false
	self:_cancelTweens()
	local endPos = self._originalPosition + UDim2.new(0, 0, 0.01, 0)
	local tween = self._tween:tween(self._template, {
		Position = endPos,
		GroupTransparency = 1,
	}, TWEEN_OUT, "dialogue")

	table.insert(self._currentTweens, tween)
	tween.Completed:Once(function()
		if self._template then
			self._template.Visible = false
		end
		self._ui.Visible = false
	end)
end

function module:_applyKit(character: string)
	if not character then
		return
	end
	local kit = KitConfig.getKit(character)
	if not kit then
		return
	end
	if self._icon then
		self._icon.Image = kit.Icon
	end
	if self._talkingText then
		self._talkingText.Text = kit.Name or character
	end
	local color = kit.Color
	if not color and kit.Rarity then
		local info = KitConfig.RarityInfo[kit.Rarity]
		color = info and info.COLOR or nil
	end
	if color then
		if self._talkingText then
			self._talkingText.TextColor3 = color
		end
		if self._textLabel then
			self._textLabel.TextColor3 = color
		end
		if self._glow then
			self._glow.ImageColor3 = color
		end
	end
end

function module:_onLine(payload)
	if not payload or not self._template then
		return
	end
	self:_show()
	local character = payload.character
	if character then
		self:_applyKit(character)
	end
	if self._textLabel and payload.text then
		self._textLabel.Text = payload.text
	end
end

function module:show()
	self._ui.Visible = true
	self:_init()
	return true
end

function module:hide()
	self:_hide()
	return true
end

function module:_cleanup()
	self._initialized = false
	self._active = false
	self._connections:cleanupGroup("dialogue")
	self:_cancelTweens()
	if self._template then
		self._template.Visible = false
		self._template.GroupTransparency = 1
		self._template.Position = self._originalPosition or self._template.Position
	end
end

return module
