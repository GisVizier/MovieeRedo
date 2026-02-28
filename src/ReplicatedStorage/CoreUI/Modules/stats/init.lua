--[[
	Stats CoreUI Module

	Displays live ping (from server), FPS (client-side), and region/language (from server geolocation).
	Matches the UI structure: top row = GB/ENG + globe, bottom row = 0ms + 59 FPS.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local module = {}
module.__index = module

-- FPS color thresholds (green = good, yellow = warning, red = bad)
local FPS_GOOD = Color3.fromRGB(86, 198, 55)
local FPS_WARNING = Color3.fromRGB(250, 220, 70)
local FPS_BAD = Color3.fromRGB(250, 70, 70)

local PING_GOOD = Color3.fromRGB(86, 198, 55)
local PING_WARNING = Color3.fromRGB(250, 220, 70)
local PING_BAD = Color3.fromRGB(250, 70, 70)

local TWEEN_COLOR = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local PING_POLL_INTERVAL = 1 -- seconds

function module.start(export, ui)
	local self = setmetatable({}, module)

	self._export = export
	self._ui = ui
	self._connections = export.connections

	self._pingLabel = nil
	self._fpsLabel = nil
	self._regionLabel = nil

	self._pingMs = 0
	self._fps = 60
	self._lastFpsUpdate = 0
	self._frameCount = 0
	self._lastPingPoll = 0

	self:_bindUi()
	self:_bindEvents()
	self:_startFpsLoop()
	self:_startPingLoop()

	return self
end

function module:show()
	-- Re-bind after hide/cleanup (connections are cleared on hide)
	self._ui.Visible = true
	self:_bindEvents()
	self:_startFpsLoop()
	self:_startPingLoop()
end

function module:hide()
	self._ui.Visible = false
	return true -- Allow CoreUI to run _cleanupModule
end

function module:_bindUi()
	-- UI structure: stats > stats (inner Frame) > Frame (x2)
	-- Frame 1 (LayoutOrder 1): GB/ENG + globe
	-- Frame 2 (LayoutOrder 2): 0ms + network icon + 59 FPS
	local inner = self._ui:FindFirstChild("stats")
	if not inner then
		return
	end

	for _, frame in ipairs(inner:GetChildren()) do
		if not frame:IsA("Frame") then
			continue
		end

		local mapNameTexts = {}
		for _, child in frame:GetDescendants() do
			if child:IsA("TextLabel") and child.Name == "MapNameText" then
				table.insert(mapNameTexts, child)
			end
		end

		for _, label in ipairs(mapNameTexts) do
			local t = label.Text or ""
			if string.find(t, "ms") then
				self._pingLabel = label
			elseif string.find(t, "FPS") then
				self._fpsLabel = label
			elseif string.find(t, "GB") or string.find(t, "ENG") then
				self._regionLabel = label
			end
		end
	end

	if self._pingLabel then
		self._pingLabel.Text = "0ms"
	end
	if self._fpsLabel then
		self._fpsLabel.Text = "60 FPS"
		self._fpsLabel.TextColor3 = FPS_GOOD
	end
end

function module:_bindEvents()
	self._connections:add(self._export:on("PingUpdate", function(pingMs)
		self:_onPingUpdate(pingMs)
	end), "events")

	self._connections:add(self._export:on("RegionUpdate", function(regionText)
		self:_onRegionUpdate(regionText)
	end), "events")
end

function module:_startPingLoop()
	self._connections:add(RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if now - self._lastPingPoll < PING_POLL_INTERVAL then
			return
		end
		self._lastPingPoll = now

		local localPlayer = Players.LocalPlayer
		if not localPlayer then
			return
		end

		-- GetNetworkPing returns round-trip latency in seconds
		local ok, rtt = pcall(localPlayer.GetNetworkPing, localPlayer)
		if not ok or type(rtt) ~= "number" then
			return
		end

		self._pingMs = math.floor(rtt * 1000 + 0.5)
		self:_updatePingText()
	end), "ping")
end

function module:_onPingUpdate(pingMs)
	if type(pingMs) ~= "number" then
		return
	end
	self._pingMs = math.floor(pingMs + 0.5)
	self:_updatePingText()
end

function module:_updatePingText()
	if not self._pingLabel then
		return
	end
	self._pingLabel.Text = tostring(self._pingMs) .. "ms"

	local targetColor = PING_GOOD
	if self._pingMs > 150 then
		targetColor = PING_BAD
	elseif self._pingMs > 80 then
		targetColor = PING_WARNING
	end

	if self._pingLabel.TextColor3 ~= targetColor then
		local tween = TweenService:Create(self._pingLabel, TWEEN_COLOR, { TextColor3 = targetColor })
		tween:Play()
	end
end

function module:_onRegionUpdate(regionText)
	if type(regionText) ~= "string" or regionText == "" then
		return
	end
	if self._regionLabel then
		self._regionLabel.Text = regionText
	end
end

function module:_startFpsLoop()
	self._connections:add(RunService.RenderStepped:Connect(function()
		self._frameCount += 1
		local now = os.clock()
		if now - self._lastFpsUpdate >= 1 then
			self._fps = math.floor(self._frameCount / (now - self._lastFpsUpdate) + 0.5)
			self._frameCount = 0
			self._lastFpsUpdate = now
			self:_updateFpsText()
		end
	end), "fps")
end

function module:_updateFpsText()
	if not self._fpsLabel then
		return
	end
	self._fpsLabel.Text = tostring(self._fps) .. " FPS"

	-- Animate FPS color based on performance
	local targetColor = FPS_GOOD
	if self._fps < 30 then
		targetColor = FPS_BAD
	elseif self._fps < 50 then
		targetColor = FPS_WARNING
	end

	if self._fpsLabel.TextColor3 ~= targetColor then
		local tween = TweenService:Create(self._fpsLabel, TWEEN_COLOR, { TextColor3 = targetColor })
		tween:Play()
	end
end

function module:_cleanup()
	-- Connections cleaned by export.connections
end

return module
