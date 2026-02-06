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
local YIELD_INTERVAL = 50 -- Yield every N voxels during creation
local FAR_AWAY_CFRAME = CFrame.new(0, -10000, 0) -- Hidden position for cached parts

-- [ HELPER FUNCTIONS ]

--! Get or create the cache folder for original parts
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

--! Uses recursive octree subdivision.
local function subdivideAABB(
	aabbCenter: Vector3,
	halfSize: Vector3,
	sphereCenter: Vector3,
	sphereRadius: number,
	minSize: number
)
	local blocks = {}

	-- If the entire part is inside the hitbox, just remove it.
	if Utils.isAABBInsideSphere(aabbCenter, halfSize, sphereCenter, sphereRadius) then
		return {} -- This removes it.
	elseif Utils.isAABBOutsideSphere(aabbCenter, halfSize, sphereCenter, sphereRadius) then
		-- If it's outside, add it as extra.
		table.insert(blocks, { center = aabbCenter, size = halfSize * 2 })
		return blocks
	else
		-- Check for partial intersection.
		local fullSize = halfSize * 2

		-- If the block is less than the minSize, decide by just voxel sizes.
		if fullSize.X <= minSize and fullSize.Y <= minSize and fullSize.Z <= minSize then
			if (aabbCenter - sphereCenter).Magnitude >= sphereRadius then
				table.insert(blocks, { center = aabbCenter, size = fullSize })
			end
			return blocks
		else
			-- Subdivide into 8 octants/cubes, because subdividing a cube into equal parts is 8 parts.
			local newHalf = halfSize * 0.5
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						-- Calculate new offset and center, try subdivide again on new part if possible.
						local offset = Vector3.new(newHalf.X * x, newHalf.Y * y, newHalf.Z * z)
						local newCenter = aabbCenter + offset
						local subBlocks = subdivideAABB(newCenter, newHalf, sphereCenter, sphereRadius, minSize)

						-- Add the new part to list.
						for _, b in ipairs(subBlocks) do
							table.insert(blocks, b)
						end
					end
				end
			end
			return blocks
		end
	end
end

--! Using octrees, it takes in a sphereical part and subtracts like a negate part from a target, which is a part too.
function VoxDestruct.octreeMeshSubtraction(
	target: Part,
	sphereHitbox: Part,
	minSize: number,
	finalVoxelSize: number,
	randomColor: boolean,
	debris: boolean,
	debrisAmount: number,
	debrisSizeMultiplier
)
	-- Define variables
	local sphereCenterWorld = sphereHitbox.Position
	local sphereRadius = sphereHitbox.Size.X / 2

	local targetCFrame = target.CFrame
	local targetSize = target.Size
	local targetHalf = targetSize * 0.5

	local localSphereCenter = targetCFrame:PointToObjectSpace(sphereCenterWorld)

	-- Subdivide via AABB
	local remainingBlocks = subdivideAABB(Vector3.new(0, 0, 0), targetHalf, localSphereCenter, sphereRadius, minSize)

	-- Using greedy meshing, merge blocks
	local mergedBlocks = Mesh.greedyMergeBlocks(remainingBlocks)

	-- Generate unique ID for this original part
	local partId = HttpService:GenerateGUID(false)

	-- Store the ACTUAL original part (not a copy) - move it to cache
	local cacheFolder = getOriginalPartsCache()

	-- Store original CFrame before moving
	local originalCFrame = target.CFrame

	-- Store reference to actual part and its original position
	VoxDestruct.OriginalParts[partId] = {
		part = target,
		originalCFrame = originalCFrame,
		-- Store material/color for debris (since part is hidden, not destroyed)
		Material = target.Material,
		Color = target.Color,
		Transparency = target.Transparency,
		Reflectance = target.Reflectance,
	}
	VoxDestruct.OriginalToVoxels[partId] = {}

	-- Move original part to cache (hidden far away) instead of destroying
	target.CFrame = FAR_AWAY_CFRAME
	target.Anchored = true
	target.CanCollide = false
	target.Parent = cacheFolder

	-- Add debris if requested.
	local originalInfo = VoxDestruct.OriginalParts[partId]
	if debris then
		if VoxDestruct.DebrisCallback then
			-- Fire to clients for client-side debris physics
			local debrisInfo = {
				Material = originalInfo.Material,
				Color = originalInfo.Color,
				Transparency = originalInfo.Transparency,
				Reflectance = originalInfo.Reflectance,
			}
			VoxDestruct.DebrisCallback(
				sphereHitbox.Position,
				sphereHitbox.Size.X / 2,
				debrisAmount,
				debrisSizeMultiplier,
				debrisInfo
			)
		else
			-- Fallback to server-side debris (for testing or single-player)
			DebrisModule.makeDebris(debrisAmount, sphereHitbox, originalInfo, debrisSizeMultiplier)
		end
	end

	-- NOTE: hitbox cleanup is handled by subtractHitbox after all parts are processed

	-- Create folder to store meshes
	local meshedFolder = workspace:FindFirstChild("CurrentVoxels")
	if not meshedFolder then
		meshedFolder = Instance.new("Folder")
		meshedFolder.Name = "CurrentVoxels"
		meshedFolder.Parent = workspace
	end

	local finalVoxels = {}

	-- Resample the voxels if they are too big/small. Most of the time they will be resampled anyway.
	if finalVoxelSize and finalVoxelSize > minSize then
		for _, block in ipairs(mergedBlocks) do
			local subVoxels = Cleanup.subdivideBlockToUniformVoxels(block, finalVoxelSize)
			for _, voxel in ipairs(subVoxels) do
				table.insert(finalVoxels, voxel)
			end
		end
	else
		finalVoxels = mergedBlocks
	end

	-- Clean up duplicate/unneeded voxels
	finalVoxels = Cleanup.cleanupVoxels(finalVoxels, 0.5)

	-- Build the final voxels with yielding to prevent timeout
	-- Get the cached original part for cloning textures
	local cachedPart = originalInfo.part

	local createdParts = {}
	for i, voxel in ipairs(finalVoxels) do
		local worldCFrame = targetCFrame * CFrame.new(voxel.center)

		local part = VoxDestruct.VoxelCache:GetPart()
		part.Size = voxel.size
		part.CFrame = worldCFrame
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Transparency = originalInfo.Transparency
		part.Reflectance = originalInfo.Reflectance

		-- Debug random colors
		if randomColor then
			part.BrickColor = BrickColor.Random()
		else
			part.Color = originalInfo.Color
		end

		part.Material = originalInfo.Material
		part.Name = "MeshedVoxel"

		-- Clone textures from the ACTUAL cached original part
		if cachedPart then
			for _, child in ipairs(cachedPart:GetChildren()) do
				if child:IsA("SurfaceAppearance") or child:IsA("Texture") or child:IsA("Decal") then
					local clone = child:Clone()
					clone.Parent = part
				end
			end
		end

		part.Parent = meshedFolder

		-- Track for regeneration
		table.insert(createdParts, part)
		VoxDestruct.VoxelToOriginal[part] = partId
		table.insert(VoxDestruct.OriginalToVoxels[partId], part)

		-- Yield periodically to prevent script timeout
		if i % YIELD_INTERVAL == 0 then
			task.wait()
		end
	end

	return finalVoxels, partId, createdParts
end

--! Subtracts the specified area from a part, then uses octreeMeshSubtraction on it.
function VoxDestruct.subtractHitbox(
	sphereHitbox: Part,
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

	-- Build ignore list from instance names (resolve string names to actual workspace instances)
	local ignoreInstances = { sphereHitbox }
	if ignore then
		for _, name in ipairs(ignore) do
			if typeof(name) == "Instance" then
				table.insert(ignoreInstances, name)
			elseif type(name) == "string" then
				-- Find instances by name in workspace to exclude
				local found = workspace:FindFirstChild(name, true)
				if found then
					table.insert(ignoreInstances, found)
				end
			end
		end
	end

	-- Define overlap parameters.
	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = ignoreInstances
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Cache the hitbox position and radius before any processing
	-- (since the hitbox reference stays valid throughout)
	local hitboxPosition = sphereHitbox.Position
	local hitboxRadius = sphereHitbox.Size.X / 2

	-- Get ALL overlapping parts upfront before processing any of them
	local overlappingParts = workspace:GetPartBoundsInRadius(hitboxPosition, hitboxRadius, overlapParams)

	-- Loop through all parts overlapping the hitbox, and define debris.
	local totalDebris = 0
	local affectedPartIds = {}

	for _, object in ipairs(overlappingParts) do
		-- Skip non-block shapes (wedges, balls, cylinders, etc.) since voxels are cubes
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

		-- Skip parts that are already voxels (from previous destructions)
		if object.Name == "MeshedVoxel" then
			continue
		end

		totalDebris = totalDebris + debrisAmount

		-- Adjust debris amount based on total.
		local localDebrisAmount = debrisAmount
		if totalDebris > debrisAmount * 4 then
			localDebrisAmount = 0
		end

		-- Subtract specified area from part.
		local _, partId = VoxDestruct.octreeMeshSubtraction(
			object,
			sphereHitbox,
			minSize,
			finalVoxelSize,
			randomColor,
			debris,
			localDebrisAmount,
			debrisSizeMultiplier
		)

		if partId then
			table.insert(affectedPartIds, partId)
		end
	end

	-- Destroy the hitbox after ALL parts have been processed
	if sphereHitbox and sphereHitbox.Parent then
		sphereHitbox:Destroy()
	end

	return affectedPartIds
end

--! Regenerate a single original part by ID
function VoxDestruct.regenerate(partId: string)
	local originalInfo = VoxDestruct.OriginalParts[partId]
	if not originalInfo then
		return false
	end

	-- Get the actual cached original part
	local originalPart = originalInfo.part
	if not originalPart or not originalPart.Parent then
		-- Part was destroyed somehow, clean up
		VoxDestruct.OriginalParts[partId] = nil
		VoxDestruct.OriginalToVoxels[partId] = nil
		return false
	end

	-- Return voxels to cache first
	local voxels = VoxDestruct.OriginalToVoxels[partId]
	if voxels then
		for _, voxel in ipairs(voxels) do
			if voxel and voxel.Parent then
				-- Clear children before returning to cache
				for _, child in ipairs(voxel:GetChildren()) do
					if
						child:IsA("SurfaceAppearance")
						or child:IsA("Texture")
						or child:IsA("Decal")
						or child:IsA("SpecialMesh")
					then
						child:Destroy()
					end
				end
				VoxDestruct.VoxelCache:ReturnPart(voxel)
			end
			VoxDestruct.VoxelToOriginal[voxel] = nil
		end
	end

	-- Move the ORIGINAL part back to its original position
	originalPart.CFrame = originalInfo.originalCFrame
	originalPart.Anchored = true -- Restore anchored state
	originalPart.CanCollide = true -- Restore collision
	originalPart.Parent = workspace

	-- Remove from storage
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
			table.insert(regenerated, newPart)
		end
	end
	return regenerated
end

--! Regenerate parts within a radius of a position
function VoxDestruct.regenerateInRadius(position: Vector3, radius: number)
	local regenerated = {}
	local toRegenerate = {}

	-- Find parts whose original position is within radius
	for partId, info in pairs(VoxDestruct.OriginalParts) do
		local partCenter = info.originalCFrame.Position
		if (partCenter - position).Magnitude <= radius then
			table.insert(toRegenerate, partId)
		end
	end

	-- Regenerate them
	for _, partId in ipairs(toRegenerate) do
		local success, newPart = VoxDestruct.regenerate(partId)
		if success then
			table.insert(regenerated, newPart)
		end
	end

	return regenerated
end

--! Get list of stored part IDs for debugging/UI
function VoxDestruct.getStoredPartIds()
	local ids = {}
	for partId in pairs(VoxDestruct.OriginalParts) do
		table.insert(ids, partId)
	end
	return ids
end

--! Clear all regeneration data (call when cleaning up)
function VoxDestruct.clearRegenData()
	-- Destroy all cached original parts
	for _, info in pairs(VoxDestruct.OriginalParts) do
		if info.part and info.part.Parent then
			info.part:Destroy()
		end
	end

	-- Clear the cache folder
	if VoxDestruct.OriginalPartsCache and VoxDestruct.OriginalPartsCache.Parent then
		VoxDestruct.OriginalPartsCache:ClearAllChildren()
	end

	table.clear(VoxDestruct.OriginalParts)
	table.clear(VoxDestruct.VoxelToOriginal)
	table.clear(VoxDestruct.OriginalToVoxels)
end

-- [ RETURNING ]
return VoxDestruct
