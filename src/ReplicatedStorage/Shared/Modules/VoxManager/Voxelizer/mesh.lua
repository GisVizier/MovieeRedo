-- [ VARIABLES ]
local Mesh = {}

-- [ CONSTANTS ]
local MAX_MERGE_PASSES = 5 -- Reduced from infinite; diminishing returns after ~4
local FRAME_BUDGET = 0.004 -- 4ms budget before yielding

-- [ FUNCTIONS ]

--! Sees if 2 blocks can be merged together. Returns merged block or nil.
-- OPTIMIZED: Extracted component access to reduce repeated indexing
function Mesh.tryMergeBlocks(
	blockA: { center: Vector3, size: Vector3 },
	blockB: { center: Vector3, size: Vector3 },
	tol: number?
)
	tol = tol or 0.001

	-- Extract components once
	local aCX, aCY, aCZ = blockA.center.X, blockA.center.Y, blockA.center.Z
	local aSX, aSY, aSZ = blockA.size.X, blockA.size.Y, blockA.size.Z
	local bCX, bCY, bCZ = blockB.center.X, blockB.center.Y, blockB.center.Z
	local bSX, bSY, bSZ = blockB.size.X, blockB.size.Y, blockB.size.Z

	local aMinX, aMinY, aMinZ = aCX - aSX * 0.5, aCY - aSY * 0.5, aCZ - aSZ * 0.5
	local aMaxX, aMaxY, aMaxZ = aCX + aSX * 0.5, aCY + aSY * 0.5, aCZ + aSZ * 0.5
	local bMinX, bMinY, bMinZ = bCX - bSX * 0.5, bCY - bSY * 0.5, bCZ - bSZ * 0.5
	local bMaxX, bMaxY, bMaxZ = bCX + bSX * 0.5, bCY + bSY * 0.5, bCZ + bSZ * 0.5

	local abs = math.abs

	-- Try merge along X axis
	if
		abs(aMinY - bMinY) < tol
		and abs(aMaxY - bMaxY) < tol
		and abs(aMinZ - bMinZ) < tol
		and abs(aMaxZ - bMaxZ) < tol
	then
		if abs(aMaxX - bMinX) < tol or abs(bMaxX - aMinX) < tol then
			local newMinX = math.min(aMinX, bMinX)
			local newMaxX = math.max(aMaxX, bMaxX)
			local cx = (newMinX + newMaxX) * 0.5
			local sx = newMaxX - newMinX
			return {
				center = Vector3.new(cx, aCY, aCZ),
				size = Vector3.new(sx, aSY, aSZ),
			}
		end
	end

	-- Try merge along Y axis
	if
		abs(aMinX - bMinX) < tol
		and abs(aMaxX - bMaxX) < tol
		and abs(aMinZ - bMinZ) < tol
		and abs(aMaxZ - bMaxZ) < tol
	then
		if abs(aMaxY - bMinY) < tol or abs(bMaxY - aMinY) < tol then
			local newMinY = math.min(aMinY, bMinY)
			local newMaxY = math.max(aMaxY, bMaxY)
			local cy = (newMinY + newMaxY) * 0.5
			local sy = newMaxY - newMinY
			return {
				center = Vector3.new(aCX, cy, aCZ),
				size = Vector3.new(aSX, sy, aSZ),
			}
		end
	end

	-- Try merge along Z axis
	if
		abs(aMinX - bMinX) < tol
		and abs(aMaxX - bMaxX) < tol
		and abs(aMinY - bMinY) < tol
		and abs(aMaxY - bMaxY) < tol
	then
		if abs(aMaxZ - bMinZ) < tol or abs(bMaxZ - aMinZ) < tol then
			local newMinZ = math.min(aMinZ, bMinZ)
			local newMaxZ = math.max(aMaxZ, bMaxZ)
			local cz = (newMinZ + newMaxZ) * 0.5
			local sz = newMaxZ - newMinZ
			return {
				center = Vector3.new(aCX, aCY, cz),
				size = Vector3.new(aSX, aSY, sz),
			}
		end
	end

	return nil
end

--! Greedy meshing: merge adjacent blocks to reduce part count.
-- OPTIMIZED: Time-budget yielding, early exit when merge rate drops, reduced passes
function Mesh.greedyMergeBlocks(blocks: {})
	local merged = blocks
	local passCount = 0

	local clock = os.clock
	local lastYield = clock()

	while passCount < MAX_MERGE_PASSES do
		passCount += 1

		local newMerged = {}
		local used = {}
		local mergeCount = 0
		local blockCount = #merged

		for i = 1, blockCount do
			if used[i] then
				continue
			end
			local current = merged[i]

			-- Adaptive tolerance based on block size
			local avgSize = (current.size.X + current.size.Y + current.size.Z) / 3
			local blockTolerance = avgSize < 2 and 0.01 or nil

			for j = i + 1, blockCount do
				if used[j] then
					continue
				end

				local tryBlock = Mesh.tryMergeBlocks(current, merged[j], blockTolerance)
				if tryBlock then
					current = tryBlock
					used[j] = true
					mergeCount += 1
				end

				-- Time-budget yielding instead of fixed interval
				if clock() - lastYield > FRAME_BUDGET then
					task.wait()
					lastYield = clock()
				end
			end

			newMerged[#newMerged + 1] = current
		end

		merged = newMerged

		-- Early exit: if no merges happened this pass, we're done
		if mergeCount == 0 then
			break
		end

		-- Early exit: if merge rate is very low (< 5% of blocks merged), diminishing returns
		if mergeCount < blockCount * 0.05 then
			break
		end
	end

	return merged
end

-- [ RETURNING ]
return Mesh
