-- [ SERVICES / MODULES ]
local HttpService = game:GetService("HttpService")
local Utils = require(script.Utils)
local Mesh = require(script.Mesh)
local Cleanup = require(script.Cleanup)
local DebrisModule = require(script.Debris)

-- [ MODULE ]
local VoxDestruct = {
	VoxelCache = nil,
	-- Regeneration storage (stores ACTUAL parts, not copies)
	OriginalPartsCache = nil, -- Folder to hold cached original parts
	OriginalParts = {}, -- { [partId] = { part = Part, originalCFrame = CFrame } }
	VoxelToOriginal = {}, -- { [voxelPart] = partId }
	OriginalToVoxels = {}, -- { [partId] = { voxel1, voxel2, ... } }
	-- Debris callback (set by VoxManager:setDebrisCallback for client-side debris)
	DebrisCallback = nil,
}

-- [ CONSTANTS ]
local FRAME_BUDGET = 0.004 -- 4ms budget per frame before yielding
local FAR_AWAY_CFRAME = CFrame.new(0, -10000, 0) -- Hidden position for cached parts

-- [ CACHED FOLDERS ] (avoid FindFirstChild every explosion)
local meshedFolder = nil
local function getMeshedFolder()
	if not meshedFolder or not meshedFolder.Parent then
		meshedFolder = workspace:FindFirstChild("CurrentVoxels")
		if not meshedFolder then
			meshedFolder = Instance.new("Folder")
			meshedFolder.Name = "CurrentVoxels"
			meshedFolder.Parent = workspace
		end
	end
	return meshedFolder
end

local function getOriginalPartsCache()
	if not VoxDestruct.OriginalPartsCache or not VoxDestruct.OriginalPartsCache.Parent then
		VoxDestruct.OriginalPartsCache = workspace:FindFirstChild("OriginalPartsCache")
		if not VoxDestruct.OriginalPartsCache then
			VoxDestruct.OriginalPartsCache = Instance.new("Folder")
			VoxDestruct.OriginalPartsCache.Name = "OriginalPartsCache"
			VoxDestruct.OriginalPartsCache.Parent = workspace
		end
	end
	return VoxDestruct.OriginalPartsCache
end

-- [ HELPER FUNCTIONS ]

--! Recursive octree subdivision. Uses a shared output table to avoid allocations.
local function subdivideAABB(
	aabbCenter: Vector3,
	halfSize: Vector3,
	sphereCenter: Vector3,
	sphereRadius: number,
	minSize: number,
	output: { any }
)
	-- If the entire block is inside the sphere, remove it (add nothing).
	if Utils.isAABBInsideSphere(aabbCenter, halfSize, sphereCenter, sphereRadius) then
		return
	end

	-- If the block is fully outside the sphere, keep it as-is.
	if Utils.isAABBOutsideSphere(aabbCenter, halfSize, sphereCenter, sphereRadius) then
		output[#output + 1] = { center = aabbCenter, size = halfSize * 2 }
		return
	end

	-- Partial intersection — check if we've reached minimum size.
	local fullSize = halfSize * 2
	if fullSize.X <= minSize and fullSize.Y <= minSize and fullSize.Z <= minSize then
		-- At min size, use simple distance check to decide keep/remove
		local dx = aabbCenter.X - sphereCenter.X
		local dy = aabbCenter.Y - sphereCenter.Y
		local dz = aabbCenter.Z - sphereCenter.Z
		if dx * dx + dy * dy + dz * dz >= sphereRadius * sphereRadius then
			output[#output + 1] = { center = aabbCenter, size = fullSize }
		end
		return
	end

	-- Subdivide into 8 octants directly into the shared output table.
	local newHalf = halfSize * 0.5
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local offset = Vector3.new(newHalf.X * x, newHalf.Y * y, newHalf.Z * z)
				subdivideAABB(aabbCenter + offset, newHalf, sphereCenter, sphereRadius, minSize, output)
			end
		end
	end
end

--! Core voxelization: subtracts a sphere from a target part using octree + greedy meshing.
--  OPTIMIZED: No hitbox Part needed, time-budget yields, batched CFrame updates, minimal cloning.
function VoxDestruct.octreeMeshSubtraction(
	target: Part,
	sphereCenter: Vector3,
	sphereRadius: number,
	minSize: number,
	finalVoxelSize: number,
	randomColor: boolean,
	debris: boolean,
	debrisAmount: number,
	debrisSizeMultiplier: number
)
	local targetCFrame = target.CFrame
	local targetSize = target.Size
	local targetHalf = targetSize * 0.5

	local localSphereCenter = targetCFrame:PointToObjectSpace(sphereCenter)

	-- Subdivide via AABB into shared output table (zero intermediate allocations)
	local remainingBlocks = {}
	subdivideAABB(Vector3.zero, targetHalf, localSphereCenter, sphereRadius, minSize, remainingBlocks)

	-- If nothing was subtracted (all blocks remain), skip this part
	if #remainingBlocks == 0 then
		return nil, nil, nil
	end

	-- Using greedy meshing, merge blocks
	local mergedBlocks = Mesh.greedyMergeBlocks(remainingBlocks)

	-- Generate unique ID for this original part
	local partId = HttpService:GenerateGUID(false)

	-- Store the ACTUAL original part — move it to cache
	local cacheFolder = getOriginalPartsCache()
	local originalCFrame = target.CFrame

	-- Store reference and visual properties
	local originalInfo = {
		part = target,
		originalCFrame = originalCFrame,
		Material = target.Material,
		Color = target.Color,
		Transparency = target.Transparency,
		Reflectance = target.Reflectance,
	}
	VoxDestruct.OriginalParts[partId] = originalInfo
	VoxDestruct.OriginalToVoxels[partId] = {}

	-- Move original part to cache (hidden far away) instead of destroying
	target.CFrame = FAR_AWAY_CFRAME
	target.Anchored = true
	target.CanCollide = false
	target.Parent = cacheFolder

	-- Add debris if requested
	if debris and debrisAmount > 0 then
		if VoxDestruct.DebrisCallback then
			local debrisInfo = {
				Material = originalInfo.Material,
				Color = originalInfo.Color,
				Transparency = originalInfo.Transparency,
				Reflectance = originalInfo.Reflectance,
			}
			VoxDestruct.DebrisCallback(
				sphereCenter,
				sphereRadius,
				debrisAmount,
				debrisSizeMultiplier,
				debrisInfo
			)
		else
			-- Fallback server-side debris (pass center/radius directly)
			DebrisModule.makeDebris(debrisAmount, sphereCenter, sphereRadius, originalInfo, debrisSizeMultiplier)
		end
	end

	-- Build final voxel list
	local finalVoxels
	if finalVoxelSize and finalVoxelSize > minSize then
		finalVoxels = {}
		for _, block in ipairs(mergedBlocks) do
			local subVoxels = Cleanup.subdivideBlockToUniformVoxels(block, finalVoxelSize)
			for _, voxel in ipairs(subVoxels) do
				finalVoxels[#finalVoxels + 1] = voxel
			end
		end
	else
		finalVoxels = mergedBlocks
	end

	-- Clean up duplicate/unneeded voxels (low threshold to keep fine boundary detail)
	finalVoxels = Cleanup.cleanupVoxels(finalVoxels, 0.06)

	-- Pre-cache texture children from original part (only SurfaceAppearance matters at voxel scale)
	local cachedPart = originalInfo.part
	local textureChildren = nil
	if cachedPart then
		textureChildren = {}
		for _, child in ipairs(cachedPart:GetChildren()) do
			if child:IsA("SurfaceAppearance") then
				textureChildren[#textureChildren + 1] = child
			end
		end
		if #textureChildren == 0 then
			textureChildren = nil
		end
	end

	-- Get cached folder reference
	local voxelFolder = getMeshedFolder()

	-- BATCH: Collect all parts and CFrames for BulkMoveTo
	local createdParts = table.create(#finalVoxels)
	local bulkParts = table.create(#finalVoxels)
	local bulkCFrames = table.create(#finalVoxels)

	local clock = os.clock
	local lastYield = clock()

	for i, voxel in ipairs(finalVoxels) do
		local worldCFrame = targetCFrame * CFrame.new(voxel.center)

		local part = VoxDestruct.VoxelCache:GetPart()
		part.Size = voxel.size
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Transparency = originalInfo.Transparency
		part.Reflectance = originalInfo.Reflectance

		if randomColor then
			part.BrickColor = BrickColor.Random()
		else
			part.Color = originalInfo.Color
		end

		part.Material = originalInfo.Material
		part.Name = "MeshedVoxel"

		-- Only clone SurfaceAppearance (textures/decals are invisible at voxel scale)
		if textureChildren then
			for _, child in ipairs(textureChildren) do
				local clone = child:Clone()
				clone.Parent = part
			end
		end

		part.Parent = voxelFolder

		-- Collect for batch CFrame update
		bulkParts[i] = part
		bulkCFrames[i] = worldCFrame
		createdParts[i] = part

		-- Track for regeneration
		VoxDestruct.VoxelToOriginal[part] = partId
		VoxDestruct.OriginalToVoxels[partId][#VoxDestruct.OriginalToVoxels[partId] + 1] = part

		-- Time-budget yielding: only yield if we've exceeded the frame budget
		if clock() - lastYield > FRAME_BUDGET then
			task.wait()
			lastYield = clock()
		end
	end

	-- Batch-move all voxels to final positions at once
	if #bulkParts > 0 then
		workspace:BulkMoveTo(bulkParts, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	return finalVoxels, partId, createdParts
end

--! Subtracts the specified spherical area from all overlapping parts.
--  OPTIMIZED: No physical hitbox Part needed — uses position/radius directly.
function VoxDestruct.subtractHitbox(
	sphereCenter: Vector3,
	sphereRadius: number,
	minSize: number,
	finalVoxelSize: number,
	randomColor: boolean,
	debris: boolean,
	debrisAmount: number,
	ignore: {},
	voxelCache,
	debrisSizeMultiplier: number
)
	-- Update cache
	VoxDestruct.VoxelCache = voxelCache

	-- Build ignore list from instance names
	local ignoreInstances = {}
	if ignore then
		for _, name in ipairs(ignore) do
			if typeof(name) == "Instance" then
				ignoreInstances[#ignoreInstances + 1] = name
			elseif type(name) == "string" then
				local found = workspace:FindFirstChild(name, true)
				if found then
					ignoreInstances[#ignoreInstances + 1] = found
				end
			end
		end
	end

	-- Also ignore the meshed voxels folder and the original parts cache
	local voxelFolder = getMeshedFolder()
	if voxelFolder then
		ignoreInstances[#ignoreInstances + 1] = voxelFolder
	end

	-- Define overlap parameters
	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = ignoreInstances
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Get ALL overlapping parts upfront
	local overlappingParts = workspace:GetPartBoundsInRadius(sphereCenter, sphereRadius, overlapParams)

	-- Loop through all parts overlapping the hitbox
	local totalDebris = 0
	local affectedPartIds = {}
	local clock = os.clock
	local lastYield = clock()

	for _, object in ipairs(overlappingParts) do
		-- Skip non-block shapes (wedges, balls, cylinders, etc.)
		if object:IsA("WedgePart") or object:IsA("CornerWedgePart") or object:IsA("TrussPart") then
			continue
		end

		-- Skip Parts with non-Block shapes
		if object:IsA("Part") and object.Shape ~= Enum.PartType.Block then
			continue
		end

		-- Skip MeshParts (can't be properly voxelized)
		if object:IsA("MeshPart") then
			continue
		end

		-- Skip parts that are already voxels
		if object.Name == "MeshedVoxel" then
			continue
		end

		totalDebris = totalDebris + debrisAmount
		local localDebrisAmount = debrisAmount
		if totalDebris > debrisAmount * 4 then
			localDebrisAmount = 0
		end

		-- Subtract sphere from this part
		local _, partId = VoxDestruct.octreeMeshSubtraction(
			object,
			sphereCenter,
			sphereRadius,
			minSize,
			finalVoxelSize,
			randomColor,
			debris,
			localDebrisAmount,
			debrisSizeMultiplier
		)

		if partId then
			affectedPartIds[#affectedPartIds + 1] = partId
		end

		-- Yield between parts if we've exceeded frame budget
		if clock() - lastYield > FRAME_BUDGET then
			task.wait()
			lastYield = clock()
		end
	end

	return affectedPartIds
end

--! Regenerate a single original part by ID
function VoxDestruct.regenerate(partId: string)
	local originalInfo = VoxDestruct.OriginalParts[partId]
	if not originalInfo then
		return false
	end

	local originalPart = originalInfo.part
	if not originalPart or not originalPart.Parent then
		VoxDestruct.OriginalParts[partId] = nil
		VoxDestruct.OriginalToVoxels[partId] = nil
		return false
	end

	-- Return voxels to cache
	local voxels = VoxDestruct.OriginalToVoxels[partId]
	if voxels then
		for _, voxel in ipairs(voxels) do
			if voxel and voxel.Parent then
				-- Only clear SurfaceAppearance (we no longer clone Texture/Decal)
				for _, child in ipairs(voxel:GetChildren()) do
					if child:IsA("SurfaceAppearance") or child:IsA("SpecialMesh") then
						child:Destroy()
					end
				end
				VoxDestruct.VoxelCache:ReturnPart(voxel)
			end
			VoxDestruct.VoxelToOriginal[voxel] = nil
		end
	end

	-- Restore the original part
	originalPart.CFrame = originalInfo.originalCFrame
	originalPart.Anchored = true
	originalPart.CanCollide = true
	originalPart.Parent = workspace

	VoxDestruct.OriginalParts[partId] = nil
	VoxDestruct.OriginalToVoxels[partId] = nil

	return true, originalPart
end

--! Regenerate all stored original parts
function VoxDestruct.regenerateAll()
	local regenerated = {}
	for partId in pairs(VoxDestruct.OriginalParts) do
		local success, newPart = VoxDestruct.regenerate(partId)
		if success then
			regenerated[#regenerated + 1] = newPart
		end
	end
	return regenerated
end

--! Regenerate parts within a radius of a position
function VoxDestruct.regenerateInRadius(position: Vector3, radius: number)
	local regenerated = {}
	local toRegenerate = {}

	for partId, info in pairs(VoxDestruct.OriginalParts) do
		local partCenter = info.originalCFrame.Position
		local dx = partCenter.X - position.X
		local dy = partCenter.Y - position.Y
		local dz = partCenter.Z - position.Z
		if dx * dx + dy * dy + dz * dz <= radius * radius then
			toRegenerate[#toRegenerate + 1] = partId
		end
	end

	for _, partId in ipairs(toRegenerate) do
		local success, newPart = VoxDestruct.regenerate(partId)
		if success then
			regenerated[#regenerated + 1] = newPart
		end
	end

	return regenerated
end

--! Get list of stored part IDs
function VoxDestruct.getStoredPartIds()
	local ids = {}
	for partId in pairs(VoxDestruct.OriginalParts) do
		ids[#ids + 1] = partId
	end
	return ids
end

--! Clear all regeneration data
function VoxDestruct.clearRegenData()
	for _, info in pairs(VoxDestruct.OriginalParts) do
		if info.part and info.part.Parent then
			info.part:Destroy()
		end
	end

	if VoxDestruct.OriginalPartsCache and VoxDestruct.OriginalPartsCache.Parent then
		VoxDestruct.OriginalPartsCache:ClearAllChildren()
	end

	table.clear(VoxDestruct.OriginalParts)
	table.clear(VoxDestruct.VoxelToOriginal)
	table.clear(VoxDestruct.OriginalToVoxels)

	-- Reset cached folder references
	meshedFolder = nil
end

-- [ RETURNING ]
return VoxDestruct
