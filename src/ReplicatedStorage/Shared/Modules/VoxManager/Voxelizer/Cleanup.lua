-- [ VARIABLES ]
local Cleanup = {}

local YIELD_INTERVAL = 200 -- Yield every N voxels to prevent timeout
local MIN_DIMENSION = 1 -- Minimum size on any axis (prevents tiny slivers)

-- [ FUNCTIONS ]

--! Cleans up too small voxels (no longer double-merges to avoid lag).
function Cleanup.cleanupVoxels(voxels: {}, minVolume: number)
	local cleaned = {}
	for _, v in ipairs(voxels) do
		local vol = v.size.X * v.size.Y * v.size.Z

		-- Filter by both volume AND minimum dimension on each axis
		local minAxis = math.min(v.size.X, v.size.Y, v.size.Z)

		-- Only keep voxels that meet both thresholds
		if vol >= minVolume and minAxis >= MIN_DIMENSION then
			table.insert(cleaned, v)
		end
	end
	-- Removed redundant greedyMergeBlocks call - already merged in octreeMeshSubtraction
	return cleaned
end

--! Subdivides a given block, using a uniform voxel grid size.
function Cleanup.subdivideBlockToUniformVoxels(block, voxelSize: number)
	local voxels = {}
	local blockSize = block.size

	-- Snap the X/Y/Z to grid.
	local snappedSizeX = math.floor(blockSize.X / voxelSize) * voxelSize
	local snappedSizeY = math.floor(blockSize.Y / voxelSize) * voxelSize
	local snappedSizeZ = math.floor(blockSize.Z / voxelSize) * voxelSize
	local snappedSize = Vector3.new(snappedSizeX, snappedSizeY, snappedSizeZ)

	-- Recenter
	local lowerCorner = block.center - snappedSize * 0.5

	-- Find number of voxels along each axis.
	local numX = math.floor(snappedSizeX / voxelSize)
	local numY = math.floor(snappedSizeY / voxelSize)
	local numZ = math.floor(snappedSizeZ / voxelSize)

	local count = 0
	for x = 0, numX - 1 do
		for y = 0, numY - 1 do
			for z = 0, numZ - 1 do
				local center = lowerCorner
					+ Vector3.new((x + 0.5) * voxelSize, (y + 0.5) * voxelSize, (z + 0.5) * voxelSize)
				table.insert(voxels, { center = center, size = Vector3.new(voxelSize, voxelSize, voxelSize) })

				-- Yield periodically to prevent script timeout
				count += 1
				if count % YIELD_INTERVAL == 0 then
					task.wait()
				end
			end
		end
	end
	return voxels
end

-- [ RETURNING ]
return Cleanup
