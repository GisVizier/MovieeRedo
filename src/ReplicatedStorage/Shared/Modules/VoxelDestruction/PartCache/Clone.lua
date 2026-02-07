local module = {}

function module.wipeAttributes(part: Part)
	for i, tag in ipairs(part:GetTags()) do
		part:RemoveTag(tag)
	end

	for attribute, value in pairs(part:GetAttributes()) do
		part:SetAttribute(attribute, nil)
	end

	return part
end

function module.mirror(match: Part, mirror)
	if typeof(mirror) == "Instance" and mirror:IsA("Part") then
		match.CastShadow = mirror.CastShadow
		match.Color = mirror.Color
		match.Material = mirror.Material
		match.Reflectance = mirror.Reflectance
		match.Transparency = mirror.Transparency
		match.Archivable = mirror.Archivable
		match.Locked = mirror.Locked
		match.Name = mirror.Name
		match.Size = mirror.Size
		match.PivotOffset = mirror.PivotOffset
		match.CanCollide = mirror.CanCollide
		match.CanQuery = mirror.CanQuery
		match.CanTouch = mirror.CanTouch
		match.CollisionGroup = mirror.CollisionGroup
		match.Anchored = mirror.Anchored
		match.CustomPhysicalProperties = mirror.CustomPhysicalProperties
		match.Massless = mirror.Massless
		match.RootPriority = mirror.RootPriority
		match.Shape = mirror.Shape
		match.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		match.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
		match.TopSurface = mirror.TopSurface
		match.BottomSurface = mirror.BottomSurface
		match.LeftSurface = mirror.LeftSurface
		match.RightSurface = mirror.RightSurface
		match.FrontSurface = mirror.FrontSurface
		match.BackSurface = mirror.BackSurface
	elseif typeof(mirror) == "table" then
		for property, value in pairs(mirror) do
			match[property] = value
		end
	end

	module.wipeAttributes(match)

	for i, tag in ipairs(mirror:GetTags()) do
		match:AddTag(tag)
	end

	for attribute, value in pairs(mirror:GetAttributes()) do
		match:SetAttribute(attribute, value)
	end

	match.CFrame = mirror.CFrame
	match.Parent = mirror.Parent

	return match
end

return module
