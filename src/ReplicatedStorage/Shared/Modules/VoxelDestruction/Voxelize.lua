local voxelizeModule = {}

function voxelizeModule.voxelize(volume: Part, unit: number, cache, quantity, already, area)
	local voxels, debris = {}, {}

	local tester = nil
	if cache then
		tester = cache:GetPart()
	elseif not cache then
		tester = volume:Clone()
	end

	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { tester }
	params.FilterType = Enum.RaycastFilterType.Include

	local left_lower_front_corner = -volume.Size / 2
	local first_block_pos = left_lower_front_corner + Vector3.new(unit / 2, unit / 2, unit / 2)

	local function roundUp(x, n)
		return n * math.ceil(x / n)
	end

	local size = Vector3.new(roundUp(volume.Size.X, unit), roundUp(volume.Size.Y, unit), roundUp(volume.Size.Z, unit))

	for x = 0, size.X - unit, unit do
		for y = 0, size.Y - unit, unit do
			for z = 0, size.Z - unit, unit do
				local block_offset_objectspace = Vector3.new(x, y, z)
				local block_cframe = volume.CFrame * CFrame.new(first_block_pos + block_offset_objectspace)
				local new_block_size = Vector3.new(
					math.min(unit, volume.Size.X - x),
					math.min(unit, volume.Size.Y - y),
					math.min(unit, volume.Size.Z - z)
				)
				local adjusted_block_pos = block_offset_objectspace
					+ (new_block_size / 2)
					- (Vector3.new(unit, unit, unit) / 2)
				local new_block_cframe = volume.CFrame * CFrame.new(first_block_pos + adjusted_block_pos)

				local function createPart()
					local block = nil
					if cache then
						block = cache:GetPart(volume)
					elseif not cache then
						block = volume:Clone()
					end

					block.Size = new_block_size
					block.CFrame = new_block_cframe
					block.Parent = volume.Parent
					return block
				end

				tester.CFrame = new_block_cframe
				tester.Size = new_block_size

				local collides = false
				if area then
					local parts = game:GetService("Workspace"):GetPartsInPart(area, params)
					if #parts > 0 then
						collides = true
					else
						collides = false
					end
				end

				if collides == false then
					table.insert(voxels, createPart())
				elseif quantity == nil and collides == true or #debris + already < quantity and collides == true then
					table.insert(debris, createPart())
				end
			end
		end
	end

	if cache and table.find(cache.InUse, volume) then
		cache:ReturnPart(volume)
		cache:ReturnPart(tester)
	elseif not cache then
		volume:Destroy()
		tester:Destroy()
	end

	return voxels, debris
end

return voxelizeModule
