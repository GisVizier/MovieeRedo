local WeldUtils = {}

function WeldUtils:CreateWeld(part0, part1, name, c0, c1)
	local weld = Instance.new("Weld")
	weld.Name = name
	weld.Part0 = part0
	weld.Part1 = part1
	weld.C0 = c0 or CFrame.new()
	weld.C1 = c1 or CFrame.new()
	weld.Parent = part0
	return weld
end

function WeldUtils:CreateBeanShapeWeld(root, part, name, positionOffset)
	return self:CreateWeld(
		root,
		part,
		name,
		positionOffset or CFrame.new(),
		CFrame.Angles(0, 0, math.rad(90))
	)
end

return WeldUtils
