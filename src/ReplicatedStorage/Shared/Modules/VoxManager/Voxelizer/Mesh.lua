-- [ VARIABLES ]
local Mesh = {}

-- [ FUNCTIONS ]

--! Sees if 2 parts can be merged together.
function Mesh.tryMergeBlocks(blockA: Part, blockB: Part, tolOverride: boolean)
	-- Create variables
	local tol = tolOverride or 0.001
	local aMin = blockA.center - blockA.size * 0.5
	local aMax = blockA.center + blockA.size * 0.5
	local bMin = blockB.center - blockB.size * 0.5
	local bMax = blockB.center + blockB.size * 0.5

	-- Return if a minus b is less than the tolerance.
	local function checkTol(a, b)
		return math.abs(a - b) < tol
	end

	-- Try merge along X.
	if
		checkTol(aMin.Y, bMin.Y)
		and checkTol(aMax.Y, bMax.Y)
		and checkTol(aMin.Z, bMin.Z)
		and checkTol(aMax.Z, bMax.Z)
	then
		if math.abs(aMax.X - bMin.X) < tol or math.abs(bMax.X - aMin.X) < tol then
			-- calculate new positions and sizes.
			local newMinX = math.min(aMin.X, bMin.X)
			local newMaxX = math.max(aMax.X, bMax.X)
			local newMin = Vector3.new(newMinX, aMin.Y, aMin.Z)
			local newMax = Vector3.new(newMaxX, aMax.Y, aMax.Z)
			local newCenter = (newMin + newMax) * 0.5
			local newSize = newMax - newMin
			return { center = newCenter, size = newSize }
		end
	end

	-- Try merge along Y axis.
	if
		checkTol(aMin.X, bMin.X)
		and checkTol(aMax.X, bMax.X)
		and checkTol(aMin.Z, bMin.Z)
		and checkTol(aMax.Z, bMax.Z)
	then
		if math.abs(aMax.Y - bMin.Y) < tol or math.abs(bMax.Y - aMin.Y) < tol then
			-- calculate new positions and sizes.
			local newMinY = math.min(aMin.Y, bMin.Y)
			local newMaxY = math.max(aMax.Y, bMax.Y)
			local newMin = Vector3.new(aMin.X, newMinY, aMin.Z)
			local newMax = Vector3.new(aMax.X, newMaxY, aMax.Z)
			local newCenter = (newMin + newMax) * 0.5
			local newSize = newMax - newMin
			return { center = newCenter, size = newSize }
		end
	end

	-- Try merge along Z axis.
	if
		checkTol(aMin.X, bMin.X)
		and checkTol(aMax.X, bMax.X)
		and checkTol(aMin.Y, bMin.Y)
		and checkTol(aMax.Y, bMax.Y)
	then
		if math.abs(aMax.Z - bMin.Z) < tol or math.abs(bMax.Z - aMin.Z) < tol then
			-- calculate new positions and sizes.
			local newMinZ = math.min(aMin.Z, bMin.Z)
			local newMaxZ = math.max(aMax.Z, bMax.Z)
			local newMin = Vector3.new(aMin.X, aMin.Y, newMinZ)
			local newMax = Vector3.new(aMax.X, aMax.Y, newMaxZ)
			local newCenter = (newMin + newMax) * 0.5
			local newSize = newMax - newMin
			return { center = newCenter, size = newSize }
		end
	end

	-- If nothing, return nil.
	return nil
end

-- Configuration for merge limits
local MAX_MERGE_PASSES = 8 -- Cap outer while-loop iterations
local YIELD_INTERVAL = 400 -- Yield every N comparisons to avoid timeout

--! Greedy meshing the target blocks back togerher
function Mesh.greedyMergeBlocks(blocks: {})
	local merged = blocks
	local changed = true
	local passCount = 0

	-- Loop until no more blocks can be merged or we hit the cap.
	while changed and passCount < MAX_MERGE_PASSES do
		changed = false
		passCount += 1

		-- Store merged
		local newMerged = {}
		local used = {}
		local comparisons = 0

		for i = 1, #merged do
			if used[i] then
				continue
			end
			local current = merged[i]

			-- Use a higher "tolerance" if no blocks are merged.
			local blockTolerance = (current.size.X + current.size.Y + current.size.Z) / 3 < 2 and 0.01 or nil
			for j = i + 1, #merged do
				if used[j] then
					continue
				end

				-- Find if the block can be merged
				local tryBlock = Mesh.tryMergeBlocks(current, merged[j], blockTolerance)
				if tryBlock then
					current = tryBlock
					used[j] = true
					changed = true
				end

				-- Yield periodically to avoid script timeout
				comparisons += 1
				if comparisons % YIELD_INTERVAL == 0 then
					task.wait()
				end
			end

			table.insert(newMerged, current)
		end

		merged = newMerged
	end

	return merged
end

-- [ RETURNING ]
return Mesh
