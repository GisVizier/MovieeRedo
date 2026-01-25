--[[
	DebugVisualizer.lua
	
	Provides visual debugging tools for the Aim Assist system.
	Shows FOV cone, target dots, and stats overlay.
]]

local Players = game:GetService("Players")

local TargetSelector = require(script.Parent.TargetSelector)

local DebugVisualizer = {}
DebugVisualizer.__index = DebugVisualizer

-- Constants
local DEFAULT_COLOR = Color3.fromRGB(0, 150, 255)
local HIGHLIGHTED_COLOR = Color3.fromRGB(255, 50, 50)
local NO_TARGET_COLOR = Color3.fromRGB(255, 255, 255)
local TARGET_COLOR = Color3.fromRGB(50, 255, 50)

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

local function angleToCircleSize(angle: number): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end

	local fovY = math.rad(camera.FieldOfView)
	local viewportSize = camera.ViewportSize
	local viewHeight = 2 * math.tan(fovY / 2)

	local angleRad = math.rad(angle / 2)
	local angleTangent = math.tan(angleRad)

	local proportion = angleTangent / viewHeight
	local pixelDiameter = viewportSize.Y * proportion * 2

	return pixelDiameter
end

-- =============================================================================
-- TARGET DOTS
-- =============================================================================

function DebugVisualizer:_createTargetDot(index: number)
	local dot = Instance.new("Part")
	dot.Name = "AimAssistDot_" .. index
	dot.Material = Enum.Material.Neon
	dot.Shape = Enum.PartType.Ball
	dot.Transparency = 0.3
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.CastShadow = false
	dot.Parent = self.dotsFolder

	-- Highlight for visibility
	local highlight = Instance.new("Highlight")
	highlight.Name = "DotHighlight"
	highlight.Adornee = dot
	highlight.Parent = dot
	highlight.OutlineTransparency = 1
	highlight.FillTransparency = 0.3

	self.activeDots[index] = {
		dot = dot,
	}
end

function DebugVisualizer:_ensureTargetDotsCreated(count: number)
	while #self.activeDots < count do
		self:_createTargetDot(#self.activeDots + 1)
	end
end

function DebugVisualizer:clearTargetDots()
	if self.dotsFolder then
		self.dotsFolder:ClearAllChildren()
	end
	self.activeDots = {}
end

function DebugVisualizer:updateTargetDots(
	allTargetPoints: { TargetSelector.TargetEntry },
	targetResult: TargetSelector.SelectTargetResult?
)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local pointCount = 0

	for _, targetEntry in allTargetPoints do
		if not targetEntry.instance then
			continue
		end

		for i, worldPoint in targetEntry.points do
			pointCount += 1
			self:_ensureTargetDotsCreated(pointCount)

			local dotInfo = self.activeDots[pointCount]
			dotInfo.dot.Position = worldPoint
			dotInfo.dot.Transparency = 0.3

			local weight = 0
			if targetResult and targetEntry.instance == targetResult.instance then
				weight = targetResult.weights[i] or 0
			end

			if weight > 0 then
				local color = DEFAULT_COLOR:Lerp(HIGHLIGHTED_COLOR, weight)
				dotInfo.dot.Size = Vector3.new(1.5, 1.5, 1.5)
				dotInfo.dot.Color = color
				if dotInfo.dot:FindFirstChild("DotHighlight") then
					dotInfo.dot.DotHighlight.FillColor = color
				end
			else
				dotInfo.dot.Size = Vector3.new(1, 1, 1)
				dotInfo.dot.Color = DEFAULT_COLOR
				if dotInfo.dot:FindFirstChild("DotHighlight") then
					dotInfo.dot.DotHighlight.FillColor = DEFAULT_COLOR
				end
			end
		end
	end

	-- Hide any extra dots
	for i = pointCount + 1, #self.activeDots do
		self.activeDots[i].dot.Transparency = 1
	end
end

-- =============================================================================
-- UI CREATION
-- =============================================================================

local function createCircleGui(screenGui: ScreenGui): Frame
	local circle = Instance.new("Frame")
	circle.Name = "AimAssistFOVCircle"
	circle.BackgroundTransparency = 1
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromOffset(0, 0)
	circle.Parent = screenGui

	local stroke = Instance.new("UIStroke")
	stroke.Name = "CircleStroke"
	stroke.Color = NO_TARGET_COLOR
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = circle

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle

	return circle
end

function DebugVisualizer:createVisualElements()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AimAssistDebugGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Parent = player.PlayerGui

	-- FOV Circle
	local circle = createCircleGui(screenGui)

	-- Stats Label
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "StatsLabel"
	statsLabel.BackgroundTransparency = 1
	statsLabel.Position = UDim2.new(0.5, 0, 1, 10)
	statsLabel.Size = UDim2.fromOffset(300, 60)
	statsLabel.AnchorPoint = Vector2.new(0.5, 0)
	statsLabel.Font = Enum.Font.RobotoMono
	statsLabel.TextColor3 = Color3.new(1, 1, 1)
	statsLabel.TextSize = 14
	statsLabel.TextStrokeTransparency = 0.3
	statsLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	statsLabel.Text = "Aim Assist: Searching..."
	statsLabel.TextXAlignment = Enum.TextXAlignment.Center
	statsLabel.Parent = circle

	-- Title Label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0.5, 0, 0, -25)
	titleLabel.Size = UDim2.fromOffset(200, 20)
	titleLabel.AnchorPoint = Vector2.new(0.5, 1)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextColor3 = Color3.new(1, 1, 0)
	titleLabel.TextSize = 12
	titleLabel.TextStrokeTransparency = 0.3
	titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	titleLabel.Text = "[AIM ASSIST DEBUG]"
	titleLabel.Parent = circle

	-- Dots folder in workspace
	local dotsFolder = Instance.new("Folder")
	dotsFolder.Name = "AimAssistDebugDots"
	dotsFolder.Parent = workspace

	self.screenGui = screenGui
	self.circle = circle
	self.statsLabel = statsLabel
	self.dotsFolder = dotsFolder
	self.activeDots = {}
end

-- =============================================================================
-- UPDATE
-- =============================================================================

function DebugVisualizer:update(
	targetResult: TargetSelector.SelectTargetResult?,
	fov: number,
	allTargetPoints: { TargetSelector.TargetEntry }
)
	if not self.screenGui or not self.dotsFolder then
		return
	end

	-- Update circle color based on target state
	local circleStroke = self.circle:FindFirstChild("CircleStroke")
	if circleStroke then
		if not targetResult then
			circleStroke.Color = NO_TARGET_COLOR
		else
			-- Color based on how centered the target is
			circleStroke.Color = NO_TARGET_COLOR:Lerp(TARGET_COLOR, 1 - targetResult.normalizedAngle)
		end
	end

	-- Update stats label
	if not targetResult then
		self.statsLabel.Text = "No Target"
	else
		self.statsLabel.Text = string.format(
			"Target: %s\nAngle: %.1f° | Distance: %.1f studs",
			targetResult.instance and targetResult.instance.Name or "Unknown",
			targetResult.angle,
			targetResult.distance
		)
	end

	-- Update circle size based on FOV
	local pixelDiameter = angleToCircleSize(fov)
	self.circle.Size = UDim2.fromOffset(pixelDiameter, pixelDiameter)

	-- Update target dots
	self:updateTargetDots(allTargetPoints, targetResult)
end

-- =============================================================================
-- CLEANUP
-- =============================================================================

function DebugVisualizer:destroy()
	if self.screenGui then
		self.screenGui:Destroy()
		self.screenGui = nil
	end

	if self.dotsFolder then
		self.dotsFolder:Destroy()
		self.dotsFolder = nil
	end

	self.circle = nil
	self.statsLabel = nil
	self.activeDots = {}
end

-- =============================================================================
-- CONSTRUCTOR
-- =============================================================================

function DebugVisualizer.new()
	local self = {
		screenGui = nil :: ScreenGui?,
		circle = nil :: Frame?,
		statsLabel = nil :: TextLabel?,
		dotsFolder = nil :: Folder?,
		activeDots = {},
	}
	
	setmetatable(self, DebugVisualizer)

	return self
end

return DebugVisualizer
