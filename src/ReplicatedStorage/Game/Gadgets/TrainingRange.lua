--[[
	TrainingRange Gadget

	Board-driven practice controls for spawning practice dummies.
]]

local Players = game:GetService("Players")

local GadgetBase = require(script.Parent:WaitForChild("GadgetBase"))

local TrainingRange = setmetatable({}, { __index = GadgetBase })
TrainingRange.__index = TrainingRange
local DEBUG_LOGGING = false

local DEFAULT_COUNT = 4
local MIN_COUNT = 1
local MAX_COUNT = 8

local function findDescendantByName(root, name)
	if not root then
		return nil
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc.Name == name then
			return desc
		end
	end
	return nil
end

local function findClickable(container)
	if not container then
		return nil
	end
	if container:IsA("GuiButton") then
		return container
	end
	for _, desc in ipairs(container:GetDescendants()) do
		if desc:IsA("GuiButton") then
			return desc
		end
	end
	if container:IsA("GuiObject") then
		return container
	end
	return nil
end

local function bindClick(self, guiObject, callback)
	if not guiObject then
		return
	end
	local conn
	if guiObject:IsA("GuiButton") then
		conn = guiObject.MouseButton1Click:Connect(callback)
	elseif guiObject:IsA("GuiObject") then
		conn = guiObject.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				callback()
			end
		end)
	end
	if conn then
		table.insert(self._connections, conn)
	end
end

local function clampCount(value)
	return math.clamp(value, MIN_COUNT, MAX_COUNT)
end

function TrainingRange.new(params)
	local self = setmetatable(GadgetBase.new(params), TrainingRange)
	self._connections = {}
	self._count = DEFAULT_COUNT
	self._moveEnabled = false
	self._ownerUserId = nil
	self._ownerConn = nil
	self._ui = {}
	return self
end

function TrainingRange:onServerCreated()
	local players = Players
	self._ownerConn = players.PlayerRemoving:Connect(function(player)
		if self._ownerUserId and player.UserId == self._ownerUserId then
			local registry = self.context and self.context.registry
			local practiceService = registry and registry:TryGet("PracticeDummyService")
			if practiceService then
				practiceService:Stop()
			end
			self._ownerUserId = nil
		end
	end)
end

function TrainingRange:onClientCreated()
	local model = self.model
	if not model then
		return
	end

	local surfaceGui = model:FindFirstChild("SurfaceGui", true)
	if not surfaceGui then
		return
	end

	local moveFrame = findDescendantByName(surfaceGui, "Move")
	local amountFrame = findDescendantByName(surfaceGui, "DummyAmount")
	local practiceFrame = findDescendantByName(surfaceGui, "Practice")
	local exitFrame = findDescendantByName(surfaceGui, "Exit")

	self._ui.moveOutcome = moveFrame and findDescendantByName(moveFrame, "OutCome")
	self._ui.amountOutcome = amountFrame and findDescendantByName(amountFrame, "OutCome")

	local moveCheck1 = moveFrame and findClickable(findDescendantByName(moveFrame, "Check1"))
	local moveCheck2 = moveFrame and findClickable(findDescendantByName(moveFrame, "Check2"))
	local amountCheck1 = amountFrame and findClickable(findDescendantByName(amountFrame, "Check1"))
	local amountCheck2 = amountFrame and findClickable(findDescendantByName(amountFrame, "Check2"))

	local moveButton = findClickable(moveFrame)
	local practiceButton = findClickable(practiceFrame)
	local exitButton = findClickable(exitFrame)

	local function refreshUi()
		if self._ui.amountOutcome and self._ui.amountOutcome:IsA("TextLabel") then
			self._ui.amountOutcome.Text = tostring(self._count)
		end
		if self._ui.moveOutcome and self._ui.moveOutcome:IsA("TextLabel") then
			self._ui.moveOutcome.Text = self._moveEnabled and "On" or "Off"
		end
	end

	local function sendApply()
		local net = self.context and self.context.net
		if net then
			net:FireServer("GadgetUseRequest", self.id, {
				action = "apply",
				count = self._count,
				move = self._moveEnabled,
			})
		end
	end

	local function sendStop()
		local net = self.context and self.context.net
		if net then
			net:FireServer("GadgetUseRequest", self.id, {
				action = "stop",
			})
		end
	end

	bindClick(self, amountCheck1, function()
		self._count = clampCount(self._count + 1)
		refreshUi()
		sendApply()
	end)

	bindClick(self, amountCheck2, function()
		self._count = clampCount(self._count - 1)
		refreshUi()
		sendApply()
	end)

	if moveCheck1 and moveCheck2 then
		bindClick(self, moveCheck1, function()
			self._moveEnabled = true
			refreshUi()
			sendApply()
		end)
		bindClick(self, moveCheck2, function()
			self._moveEnabled = false
			refreshUi()
			sendApply()
		end)
	else
		bindClick(self, moveButton, function()
			self._moveEnabled = not self._moveEnabled
			refreshUi()
			sendApply()
		end)
	end

	bindClick(self, practiceButton, function()
		refreshUi()
		sendApply()
	end)

	bindClick(self, exitButton, function()
		sendStop()
	end)

	refreshUi()
end

function TrainingRange:onUseRequest(player, payload)
	if typeof(payload) ~= "table" then
		return { approved = false }
	end

	if not self._ownerUserId then
		self._ownerUserId = player.UserId
	end

	if self._ownerUserId ~= player.UserId then
		return { approved = false }
	end

	local registry = self.context and self.context.registry
	local practiceService = registry and registry:TryGet("PracticeDummyService")
	if not practiceService then
		return { approved = false }
	end

	local action = payload.action
	
	if action == "stop" then
		practiceService:Stop()
		self._ownerUserId = nil
		return { approved = true }
	end

	local count = tonumber(payload.count) or DEFAULT_COUNT
	count = math.clamp(count, MIN_COUNT, MAX_COUNT)
	local moveEnabled = payload.move == true
	
	practiceService:Reset(count, moveEnabled)

	return { approved = true }
end

function TrainingRange:destroy()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}

	if self._ownerConn then
		self._ownerConn:Disconnect()
		self._ownerConn = nil
	end

	self.model = nil
end

return TrainingRange
