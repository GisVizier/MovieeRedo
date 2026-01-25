--!strict
local Players = game:GetService("Players")

local TargetSelector = require(script.Parent.TargetSelector)

local AimAssistDebugVisualizer = {}
AimAssistDebugVisualizer.__index = AimAssistDebugVisualizer

-- Constants
local DEFAULT_COLOR = Color3.fromRGB(0, 0, 255)
local HIGHLIGHTED_COLOR = Color3.fromRGB(255, 0, 0)

local function angleToCircleSize(angle: number): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end

	local fovY = math.rad(camera.FieldOfView)
	local viewportSize = camera.ViewportSize
	local viewHeight = 2 * math.tan(fovY / 2) -- Height of view plane at unit distance

	local angleRad = math.rad(angle / 2)
	local angleTangent = math.tan(angleRad)

	local proportion = angleTangent / viewHeight
	local pixelDiameter = viewportSize.Y * proportion * 2

	return pixelDiameter
end

function AimAssistDebugVisualizer:_createTargetDot(index: number)
	-- Create the dot instance
	local dot = Instance.new("Part")
	dot.Material = Enum.Material.Plastic
	dot.Shape = Enum.PartType.Ball
	dot.Transparency = 1
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanQuery = false
	dot.CanTouch = false
	dot.Parent = self.dotsFolder

	-- Highlight for visibility
	local highlight = Instance.new("Highlight")
	highlight.Adornee = dot
	highlight.Parent = dot
	highlight.OutlineTransparency = 1
	highlight.FillTransparency = 0.5

	-- Store the dot info
	self.activeDots[index] = {
		dot = dot,
	}
end

function AimAssistDebugVisualizer:_ensureTargetDotsCreated(count: number)
	-- Create dot frames as needed
	while #self.activeDots < count do
		self:_createTargetDot(#self.activeDots + 1)
	end
end

function AimAssistDebugVisualizer:clearTargetDots()
	self.dotsFolder:ClearAllChildren()
	self.activeDots = {}
end

function AimAssistDebugVisualizer:updateTargetDots(
	allTargetPoints: { TargetSelector.TargetEntry },
	targetResult: TargetSelector.SelectTargetResult
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
			dotInfo.dot.Transparency = 0

			local weight = 0
			if targetResult and targetEntry.instance == targetResult.instance then
				weight = targetResult.weights[i]
			end

			if weight > 0 then
				local color = DEFAULT_COLOR:Lerp(HIGHLIGHTED_COLOR, weight)
				dotInfo.dot.Size = Vector3.new(2, 2, 2)
				dotInfo.dot.Highlight.FillColor = color
				dotInfo.dot.Color = color
			else
				dotInfo.dot.Size = Vector3.new(1.5, 1.5, 1.5)
				dotInfo.dot.Color = DEFAULT_COLOR
				dotInfo.dot.Highlight.FillColor = DEFAULT_COLOR
			end
		end
	end

	-- Hide any extra dots
	for i = pointCount + 1, #self.activeDots do
		self.activeDots[i].dot.Transparency = 1
	end
end

local function createCircleGui(screenGui: ScreenGui)
	-- Create a Frame for the circle
	local circle = Instance.new("Frame")
	circle.Name = "AimAssistRangeCircle"
	circle.BackgroundTransparency = 1
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	local pixelDiameter = 0
	circle.Size = UDim2.fromOffset(pixelDiameter, pixelDiameter)
	circle.Parent = screenGui

	-- Create a UIStroke for the circle outline
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 0, 0) -- Red color
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = circle

	-- Create a UICorner to make the frame circular
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- Makes it a circle
	corner.Parent = circle

	return circle
end

-- Create a ScreenGui to hold aim assist stats and visualization
function AimAssistDebugVisualizer:createVisualElements()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AimAssistDebugGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	-- Circle to visualize target selection FOV
	local circle = createCircleGui(screenGui)

	-- Text label to show stats
	local rangeLabel = Instance.new("TextLabel")
	rangeLabel.Name = "RangeLabel"
	rangeLabel.BackgroundTransparency = 1
	rangeLabel.Position = UDim2.new(0.5, 0, 1, 10)
	rangeLabel.Size = UDim2.fromOffset(200, 20)
	rangeLabel.AnchorPoint = Vector2.new(0.5, 0)
	rangeLabel.Font = Enum.Font.SourceSansBold
	rangeLabel.TextColor3 = Color3.new(1, 1, 1)
	rangeLabel.TextSize = 16
	rangeLabel.TextStrokeTransparency = 0.5
	rangeLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	rangeLabel.Text = "Aim Assist Disabled"
	rangeLabel.Parent = circle

	-- Create a container for target dots
	local dotsFolder = Instance.new("Folder")
	dotsFolder.Parent = workspace
	dotsFolder.Name = "TargetDotsFolder"

	self.screenGui = screenGui
	self.circle = circle
	self.rangeLabel = rangeLabel
	self.dotsFolder = dotsFolder
	self.activeDots = {}
end

-- Display target selection results on the debug GUI
function AimAssistDebugVisualizer:update(
	targetResult: TargetSelector.SelectTargetResult?,
	fov: number,
	allTargetPoints: { TargetSelector.TargetEntry }
)
	if not self.screenGui or not self.dotsFolder then
		return
	end

	if not targetResult then
		self.circle.UIStroke.Color = Color3.new(1, 1, 1)
		self.rangeLabel.Text = "Aim Assist Disabled"
	else
		local RED = Color3.new(1, 0, 0)
		local BLUE = Color3.new(0, 0, 1)
		self.circle.UIStroke.Color = RED:Lerp(BLUE, targetResult.normalizedAngle)
		self.rangeLabel.Text = string.format(
			"Aim Assist Angle: %.1f°\n" .. "Aim Assist Depth: %.1f",
			targetResult.angle,
			targetResult.distance
		)
	end

	local pixelDiameter = angleToCircleSize(fov)
	self.circle.Size = UDim2.fromOffset(pixelDiameter, pixelDiameter)

	self:updateTargetDots(allTargetPoints, targetResult)
end

function AimAssistDebugVisualizer:destroy()
	local screenGui = self.screenGui
	self.screenGui = nil
	if screenGui then
		screenGui:Destroy()
	end

	local dotsFolder = self.dotsFolder
	self.dotsFolder = nil
	if dotsFolder then
		dotsFolder:Destroy()
	end
end

function AimAssistDebugVisualizer.new()
	local self = {
		screenGui = nil :: ScreenGui?,
		dotsFolder = nil :: Folder?,
	}
	setmetatable(self, AimAssistDebugVisualizer)

	return self
end

return AimAssistDebugVisualizer
