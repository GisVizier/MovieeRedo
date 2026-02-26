local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataTable = require(ReplicatedStorage:WaitForChild("PlayerDataTable"))

local module = {}
module.__index = module

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections
	self._clickTarget = nil

	if ui:IsA("GuiButton") then
		self._clickTarget = ui
	else
		self._clickTarget = ui:FindFirstChildWhichIsA("GuiButton", true)
	end

	self._ui.Visible = false

	return self
end

function module:_requestHudUnhide()
	local current = PlayerDataTable.get("Gameplay", "HideHud")
	if current == false then
		return
	end
	PlayerDataTable.set("Gameplay", "HideHud", false)
end

function module:show()
	self._ui.Visible = true

	self._connections:cleanupGroup("input")

	if self._clickTarget and self._clickTarget:IsA("GuiButton") then
		self._clickTarget.Active = true
		self._clickTarget.Selectable = false
		self._connections:track(self._clickTarget, "Activated", function()
			self:_requestHudUnhide()
		end, "input")
	end

	self._connections:track(UserInputService, "InputBegan", function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.H then
			self:_requestHudUnhide()
		end
	end, "input")

	return true
end

function module:hide()
	self._connections:cleanupGroup("input")
	self._ui.Visible = false
	return true
end

function module:_cleanup()
	self._connections:cleanupGroup("input")
end

return module
