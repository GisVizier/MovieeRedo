local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Locations"))
local GadgetBase = require(Locations.Game:WaitForChild("Gadgets"):WaitForChild("GadgetBase"))

local Zipline = {}
Zipline.__index = Zipline
setmetatable(Zipline, GadgetBase)

local defaultSegmentCount = 16
local defaultSegmentSize = Vector3.new(0.2, 0.2, 0.2)

function Zipline.new(params)
	local self = GadgetBase.new(params)
	setmetatable(self, Zipline)
	self._segmentsFolder = nil
	return self
end

function Zipline:_getSegmentCount()
	local count = self.model and self.model:GetAttribute("SegmentCount")
	if type(count) ~= "number" or count < 2 then
		return defaultSegmentCount
	end
	return math.floor(count)
end

function Zipline:_getSegmentSize()
	local size = self.model and self.model:GetAttribute("SegmentSize")
	if typeof(size) == "Vector3" then
		return size
	end
	if type(size) == "number" and size > 0 then
		return Vector3.new(size, size, size)
	end
	return defaultSegmentSize
end

function Zipline:_findAttachment(name)
	if not self.model then
		return nil
	end
	for _, descendant in ipairs(self.model:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

function Zipline:_getRefPart()
	if not self.model then
		return nil
	end
	local ref = self.model:FindFirstChild("RefPart")
	if ref and ref:IsA("BasePart") then
		return ref
	end
	ref = self.model:FindFirstChild("refPart")
	if ref and ref:IsA("BasePart") then
		return ref
	end
	return nil
end

function Zipline:_getOrCreateSegmentsFolder()
	if self._segmentsFolder and self._segmentsFolder.Parent then
		return self._segmentsFolder
	end
	local folder = self.model and self.model:FindFirstChild("Segments")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Segments"
		folder.Parent = self.model
	end
	self._segmentsFolder = folder
	return folder
end

function Zipline:_clearSegments()
	local folder = self:_getOrCreateSegmentsFolder()
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

function Zipline:_applyRefProperties(part, refPart)
	if not part then
		return
	end
	if refPart then
		part.Color = refPart.Color
		part.Material = refPart.Material
		part.Transparency = refPart.Transparency
		part.Reflectance = refPart.Reflectance
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
end

function Zipline:_bezierPoint(p0, p1, p2, t)
	local inv = 1 - t
	return (inv * inv) * p0 + (2 * inv * t) * p1 + (t * t) * p2
end

function Zipline:_buildSegments(points)
	if not self.model then
		return
	end
	if #points < 2 then
		return
	end

	self:_clearSegments()
	local folder = self:_getOrCreateSegmentsFolder()
	local refPart = self:_getRefPart()
	local size = self:_getSegmentSize()

	for i, point in ipairs(points) do
		local part = Instance.new("Part")
		part.Name = "Segment_" .. tostring(i)
		part.Size = size
		part.CFrame = CFrame.new(point)
		self:_applyRefProperties(part, refPart)
		part.Parent = folder
	end
end

function Zipline:onServerCreated()
	if not self.model or not self.model.Parent then
		return
	end

	local startAttachment = self:_findAttachment("Start")
	local endAttachment = self:_findAttachment("End")
	if not startAttachment or not endAttachment then
		return
	end

	local centerAttachment = self:_findAttachment("Center")
	local count = self:_getSegmentCount()
	local points = {}

	if centerAttachment then
		local p0 = startAttachment.WorldPosition
		local p1 = centerAttachment.WorldPosition
		local p2 = endAttachment.WorldPosition
		for i = 0, count - 1 do
			local t = i / (count - 1)
			table.insert(points, self:_bezierPoint(p0, p1, p2, t))
		end
	else
		local p0 = startAttachment.WorldPosition
		local p1 = endAttachment.WorldPosition
		for i = 0, count - 1 do
			local t = i / (count - 1)
			table.insert(points, p0:Lerp(p1, t))
		end
	end

	self:_buildSegments(points)
end

return Zipline
