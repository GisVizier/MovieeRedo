-- [ MODULES ]
local Mesh = require(script.Parent.Mesh)

-- [ VARIABLES ]
local Cleanup = {}

-- [ CONSTANTS ]
local FRAME_BUDGET = 0.004 -- 4ms budget before yielding
local MIN_DIMENSION = 0.4 -- Minimum size on any axis (prevents tiny slivers)

-- [ FUNCTIONS ]

--! Cleans up too small voxels.
-- OPTIMIZED: Filters by volume AND minimum dimension
function Cleanup.cleanupVoxels(voxels: {}, minVolume: number)
	local cleaned = {}
	for _, v in ipairs(voxels) do
		local sx, sy, sz = v.size.X, v.size.Y, v.size.Z
		local vol = sx * sy * sz
		local minAxis = math.min(sx, sy, sz)

		-- Filter by both volume AND minimum dimension on each axis
		if vol >= minVolume and minAxis >= MIN_DIMENSION then
			cleaned[#cleaned + 1] = v
		end
	end
	return cleaned
end

--! Subdivides a given block, using a uniform voxel grid size.
-- OPTIMIZED: Time-budget yielding, pre-computed values, #table+1 insertion
function Cleanup.subdivideBlockToUniformVoxels(block: { center: Vector3, size: Vector3 }, voxelSize: number)
	local voxels = {}
	local blockSize = block.size

	-- Snap the X/Y/Z to grid
	local numX = math.floor(blockSize.X / voxelSize)
	local numY = math.floor(blockSize.Y / voxelSize)
	local numZ = math.floor(blockSize.Z / voxelSize)

	if numX <= 0 or numY <= 0 or numZ <= 0 then
		return voxels
	end

	local snappedSizeX = numX * voxelSize
	local snappedSizeY = numY * voxelSize
	local snappedSizeZ = numZ * voxelSize

	-- Recenter: lower corner of the snapped region
	local lowerX = block.center.X - snappedSizeX * 0.5
	local lowerY = block.center.Y - snappedSizeY * 0.5
	local lowerZ = block.center.Z - snappedSizeZ * 0.5

	local halfVoxel = voxelSize * 0.5
	local voxelSizeVec = Vector3.new(voxelSize, voxelSize, voxelSize)

	local clock = os.clock
	local lastYield = clock()

	for x = 0, numX - 1 do
		local cx = lowerX + x * voxelSize + halfVoxel
		for y = 0, numY - 1 do
			local cy = lowerY + y * voxelSize + halfVoxel
			for z = 0, numZ - 1 do
				local cz = lowerZ + z * voxelSize + halfVoxel
				voxels[#voxels + 1] = {
					center = Vector3.new(cx, cy, cz),
					size = voxelSizeVec, -- Reuse same Vector3 for all uniform voxels
				}
			end
		end

		-- Time-budget yielding (check per X-row, not per voxel)
		if clock() - lastYield > FRAME_BUDGET then
			task.wait()
			lastYield = clock()
		end
	end

	return voxels
end

-- [ RETURNING ]
return Cleanup
