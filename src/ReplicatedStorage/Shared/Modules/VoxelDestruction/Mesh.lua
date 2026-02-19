local Mesher = {}

local function canMerge(part1: Instance, part2: Instance, excludeAxis: string)
	local equalAxises = 0

	local equalPosAxises = 0

	for _, axisEnum in pairs(Enum.Axis:GetEnumItems()) do
		local axis = axisEnum.Name

		local diff = math.abs(part1.CFrame:ToObjectSpace(part2.CFrame).Position[axis])

		if diff <= 0.02 then
			equalPosAxises += 1

			if equalPosAxises == 2 then
				break
			end
		end
	end

	if equalPosAxises < 2 then
		return
	end

	for _, axisEnum in pairs(Enum.Axis:GetEnumItems()) do
		local axis = axisEnum.Name

		if axis == excludeAxis then
			continue
		end

		local diff = math.abs(part1.Size[axis] - part2.Size[axis])

		local compareProps = { "Color", "Material", "MaterialVariant", "Transparency", "Shape" }

		local propsEqual = 0
		for _, prop in pairs(compareProps) do
			if part1[prop] ~= part2[prop] then
				break
			end

			propsEqual += 1
		end

		local isPartOfSameGroup = propsEqual == #compareProps

		if diff <= 0.1 and isPartOfSameGroup then
			equalAxises += 1

			if equalAxises == 2 then
				return true
			end
		end
	end
end

function Mesher:MergeNearby(part: Instance, OP: OverlapParams, mergeProperties: table, cache)
	if not part.Parent then
		return
	end

	if not OP then
		OP = OverlapParams.new()
		OP.FilterType = Enum.RaycastFilterType.Include
		OP.FilterDescendantsInstances = { workspace }
	end

	mergeProperties = mergeProperties or {}

	for _, axisEnum in pairs(Enum.Axis:GetEnumItems()) do
		local axis = axisEnum.Name

		for _, mult in pairs({ -1, 1 }) do
			local extend = CFrame.new(
				axis == "X" and part.Size.X / 2 * mult or 0,
				axis == "Y" and part.Size.Y / 2 * mult or 0,
				axis == "Z" and part.Size.Z / 2 * mult or 0
			)

			local cfOrientation =
				CFrame.Angles(math.rad(part.Orientation.X), math.rad(part.Orientation.Y), math.rad(part.Orientation.Z))
			local origin = part.CFrame * (extend * cfOrientation)

			local boundSize = mergeProperties.BoundSize or Vector3.new(0.001, 0.001, 0.001)
			local touching = workspace:GetPartBoundsInBox(origin, boundSize, OP)

			for i = 1, #touching do
				local touchPart = touching[i]

				if touchPart == part then
					continue
				end

				if not touchPart:IsA("Part") then
					continue
				end

				if not table.find(self.parts, touchPart) then
					continue
				end

				if not canMerge(part, touchPart, axis, mergeProperties) then
					continue
				end

				if mergeProperties.Filter then
					if not mergeProperties.Filter(part, touchPart, axis) then
						continue
					end
				end

				local parent = part.Parent

				local model = Instance.new("Model")
				model.Parent = parent
				part.Parent = model
				touchPart.Parent = model

				local cframe, size = model:GetBoundingBox()
				part.Parent = parent
				touchPart.Parent = parent
				model:Destroy()

				part.CFrame = cframe
				part.Size = size

				table.remove(self.parts, table.find(self.parts, touchPart))

				if cache and table.find(cache.InUse, touchPart) then
					cache:ReturnPart(touchPart)
				elseif not cache then
					touchPart:Destroy()
				end

				self:MergeNearby(part, OP, mergeProperties, cache)

				return
			end
		end
	end
end

function Mesher:MergeParts(parts: table, mergeProperties: table, cache)
	local OP = OverlapParams.new()
	OP.FilterType = Enum.RaycastFilterType.Include
	OP.FilterDescendantsInstances = { parts }

	self.parts = parts

	for _, part in pairs(parts) do
		self:MergeNearby(part, OP, mergeProperties, cache)
	end

	return self.parts
end

return Mesher
