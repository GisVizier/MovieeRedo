--[[
	PressureDestructionService.lua
	
	Server-side service for pressure-based wall destruction.
	Handles bullet impact accumulation and triggers VoxelDestruction when
	pressure thresholds are exceeded.
	
	Pattern: Similar to Rainbow Six Siege's soft destruction.
	- Shotguns: All pellets from one shot create one hole
	- Other weapons: Accumulate pressure in zones, trigger when threshold met
	
	Client sends impact data → Server validates distance → Server triggers VoxelDestruction
	VoxelDestruction handles finding "Breakable" tagged parts automatically.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local VoxelDestruction = require(ReplicatedStorage.Shared.Modules.VoxelDestruction)

local PressureDestructionService = {}

--------------------------------------------------------------------------------
-- DEBUG
--------------------------------------------------------------------------------

local DEBUG = false -- Set to false to disable debug logging/visuals

local function log(...)
	return
end

local function logWarn(...)
	return
end

local function summarizeParts(parts, maxCount)
	if not parts or #parts == 0 then
		return "none"
	end

	local cap = math.min(#parts, maxCount or 6)
	local names = table.create(cap)
	for i = 1, cap do
		local p = parts[i]
		names[i] = string.format(
			"%s(__Breakable=%s piece=%s canQuery=%s canCollide=%s transp=%.2f)",
			p:GetFullName(),
			tostring(p:GetAttribute("__Breakable")),
			tostring(p:HasTag("BreakablePiece")),
			tostring(p.CanQuery),
			tostring(p.CanCollide),
			p.Transparency
		)
	end

	local suffix = if #parts > cap then string.format(" (+%d more)", #parts - cap) else ""
	return table.concat(names, " | ") .. suffix
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
	-- Validation
	MAX_IMPACT_DISTANCE = 1000,     -- Max distance from player to impact (using replicated position)
	MAX_IMPACTS_PER_SECOND = 50,    -- Rate limit per player
	
	-- Shotgun cluster settings
	CLUSTER_WINDOW = 0.015,         -- 15ms - collect pellets very fast
	
	-- Pressure zone settings (non-shotgun)
	ZONE_RADIUS = 2.5,              -- Wider zone so rapid fire hits count together
	ZONE_LIFETIME = 0.03,           -- 30ms window for accumulation (snappier response)
	MIN_PRESSURE = 60,              -- Requires ~2-3 AR hits, 1 sniper hit
	
	-- Hole sizing based on pressure from LoadoutConfig
	-- Sniper (100) -> 6 studs, Shotgun (30*8=240) -> 12 studs (clamped)
	-- Shorty (50*6=300) -> 12 studs (clamped), AR (28) -> 1.68 (clamped to 1.5)
	MIN_HOLE_SIZE = 1,              -- Minimum hole radius (studs)
	MAX_HOLE_SIZE = 12,             -- Maximum hole radius (studs)
	MAX_SHOTGUN_HOLE_SIZE = 5.5,    -- Separate cap for grouped pellet shots
	PRESSURE_TO_SIZE = 0.06,        -- pressure * this = radius
	SHOTGUN_CLUSTER_PRESSURE_SCALE = 0.3, -- Slightly weaker grouped pellet pressure
	MIN_PART_CLAMP_RADIUS = 0.35,   -- Lower floor when clamping to small wall faces
	MAX_HOLE_RADIUS_RATIO_TO_FACE = 0.4, -- Max radius as ratio of the smallest face dimension
	MAX_DEPTH_RATIO_TO_THICKNESS = 0.9, -- Prevent depth from exceeding most of wall thickness
	IMPACT_PART_SEARCH_RADIUS = 8,  -- Search radius to find impacted breakable part
	
	-- VoxelDestruction settings
	VOXEL_SIZE = 2,                 -- Chunk size for destruction
	DEBRIS_COUNT = 4,               -- Less debris for performance
	DESTRUCTION_DEPTH = 3,          -- Base hole depth
	MIN_PENETRATION_DEPTH = 1.25,   -- Clamp min depth for reliable overlap
	MAX_PENETRATION_DEPTH = 6,      -- Clamp max depth to avoid giant tunnels
	MAX_DEPTH_TO_RADIUS = 2,        -- Prevent very long thin hitboxes (depth <= radius * ratio)
	PENETRATION_PADDING = 0.15,     -- Extra push inward so hitbox is not surface-flush
	PENETRATION_CENTER_RATIO = 0.22, -- Portion of depth used to shift hitbox center inward
	MAX_FORWARD_OFFSET = 1.2,       -- Hard cap so entry hole stays near impact

	-- Range scaling for penetration
	CLOSE_RANGE_DISTANCE = 15,      -- <= this distance gets max depth bonus
	FALLOFF_END_DISTANCE = 100,     -- >= this distance gets normal depth
	CLOSE_RANGE_DEPTH_MULT = 1.35,  -- Mild depth boost up close
	RANGE_DEPTH_BONUS_MULT = 0.2,   -- Additional up-to-20% depth at very close range vs weapon range
}

-- Default pressure if not provided by client
local DEFAULT_PRESSURE = 20

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

PressureDestructionService._registry = nil
PressureDestructionService._net = nil

-- Active pressure zones (non-shotgun)
local activeZones = {} -- [zoneId] = zoneData

-- Active shotgun clusters
local activeClusters = {} -- [clusterId] = clusterData

-- Rate limiting
local playerImpactCounts = {} -- [userId] = { count, resetTime }

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------


local function validatePlayerDistance(player, position)
	local playerPosition = nil
	
	-- Try to get replicated position first (more accurate than server character position)
	local registry = PressureDestructionService._registry
	if registry then
		local replicationService = registry:TryGet("ReplicationService")
		if replicationService and replicationService.PlayerStates then
			local playerData = replicationService.PlayerStates[player]
			if playerData and playerData.LastState and playerData.LastState.Position then
				playerPosition = playerData.LastState.Position
				log("Using replicated position for", player.Name)
			end
		end
	end
	
	-- Fallback to character root position
	if not playerPosition then
		local character = player.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Root")
			if root then
				playerPosition = root.Position
				log("Using fallback root position for", player.Name)
			end
		end
	end
	
	if not playerPosition then
		log("validatePlayerDistance: No position found for", player.Name)
		return false
	end
	
	local distance = (playerPosition - position).Magnitude
	local valid = distance <= CONFIG.MAX_IMPACT_DISTANCE
	if not valid then
		log("validatePlayerDistance: Distance", distance, "exceeds max", CONFIG.MAX_IMPACT_DISTANCE)
	end
	return valid
end

local function checkRateLimit(player)
	local userId = player.UserId
	local now = os.clock()
	
	local data = playerImpactCounts[userId]
	if not data or now >= data.resetTime then
		playerImpactCounts[userId] = { count = 1, resetTime = now + 1 }
		return true
	end
	
	if data.count >= CONFIG.MAX_IMPACTS_PER_SECOND then
		log("Rate limit exceeded for", player.Name)
		return false
	end
	
	data.count = data.count + 1
	return true
end

-- Calculate bounding sphere for shotgun pellet cluster
local function calculateBoundingSphere(positions)
	if #positions == 0 then return nil, 0 end
	if #positions == 1 then return positions[1], 0 end
	
	local sum = Vector3.zero
	for _, pos in ipairs(positions) do
		sum = sum + pos
	end
	local center = sum / #positions
	
	local maxDist = 0
	for _, pos in ipairs(positions) do
		local dist = (pos - center).Magnitude
		if dist > maxDist then
			maxDist = dist
		end
	end
	
	return center, maxDist
end

local function sanitizeNormal(normal)
	if typeof(normal) ~= "Vector3" then
		return Vector3.new(0, 0, -1)
	end

	if normal.Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return normal.Unit
end

local function calculateDistanceDepthMultiplier(impactDistance)
	if type(impactDistance) ~= "number" then
		return 1
	end

	if impactDistance <= CONFIG.CLOSE_RANGE_DISTANCE then
		return CONFIG.CLOSE_RANGE_DEPTH_MULT
	end

	if impactDistance >= CONFIG.FALLOFF_END_DISTANCE then
		return 1
	end

	local alpha = (impactDistance - CONFIG.CLOSE_RANGE_DISTANCE)
		/ (CONFIG.FALLOFF_END_DISTANCE - CONFIG.CLOSE_RANGE_DISTANCE)
	return CONFIG.CLOSE_RANGE_DEPTH_MULT + ((1 - CONFIG.CLOSE_RANGE_DEPTH_MULT) * alpha)
end

local function calculateRangeDepthMultiplier(impactDistance, weaponRange)
	if type(impactDistance) ~= "number" then
		return 1
	end

	if type(weaponRange) ~= "number" or weaponRange <= 0 then
		return 1
	end

	local distanceRatio = math.clamp(impactDistance / weaponRange, 0, 1)
	return 1 + ((1 - distanceRatio) * CONFIG.RANGE_DEPTH_BONUS_MULT)
end

local function calculatePenetrationDepth(impactDistance, weaponRange)
	local distanceMult = calculateDistanceDepthMultiplier(impactDistance)
	local rangeMult = calculateRangeDepthMultiplier(impactDistance, weaponRange)
	local depth = CONFIG.DESTRUCTION_DEPTH * distanceMult * rangeMult

	return math.clamp(depth, CONFIG.MIN_PENETRATION_DEPTH, CONFIG.MAX_PENETRATION_DEPTH)
end

local function findBreakablePartAtImpact(position)
	local bestPart = nil
	local bestScore = math.huge
	local edgeTolerance = 0.35
	local maxSearchRadius = CONFIG.IMPACT_PART_SEARCH_RADIUS

	for _, candidate in ipairs(CollectionService:GetTagged("Breakable")) do
		if candidate:IsA("BasePart") then
			local dist = (candidate.Position - position).Magnitude
			if dist <= maxSearchRadius then
				local localPos = candidate.CFrame:PointToObjectSpace(position)
				local sx, sy, sz = candidate.Size.X * 0.5, candidate.Size.Y * 0.5, candidate.Size.Z * 0.5
				local inside = math.abs(localPos.X) <= (sx + edgeTolerance)
					and math.abs(localPos.Y) <= (sy + edgeTolerance)
					and math.abs(localPos.Z) <= (sz + edgeTolerance)

				-- Strongly prefer parts that actually contain/near-contain the impact position.
				local score = inside and dist or (dist + maxSearchRadius)
				if score < bestScore then
					bestScore = score
					bestPart = candidate
				end
			end
		end
	end

	return bestPart
end

local function clampHoleToPart(part, inwardNormal, radius, penetrationDepth)
	if not part then
		return radius, penetrationDepth
	end

	local localNormal = part.CFrame:VectorToObjectSpace(inwardNormal)
	local ax, ay, az = math.abs(localNormal.X), math.abs(localNormal.Y), math.abs(localNormal.Z)

	local thickness, faceA, faceB
	if ax >= ay and ax >= az then
		thickness = part.Size.X
		faceA, faceB = part.Size.Y, part.Size.Z
	elseif ay >= ax and ay >= az then
		thickness = part.Size.Y
		faceA, faceB = part.Size.X, part.Size.Z
	else
		thickness = part.Size.Z
		faceA, faceB = part.Size.X, part.Size.Y
	end

	local maxRadiusByFace = math.max(
		CONFIG.MIN_PART_CLAMP_RADIUS,
		math.min(faceA, faceB) * CONFIG.MAX_HOLE_RADIUS_RATIO_TO_FACE
	)
	local maxDepthByThickness = math.max(
		CONFIG.MIN_PENETRATION_DEPTH,
		thickness * CONFIG.MAX_DEPTH_RATIO_TO_THICKNESS
	)

	local clampedRadius = math.min(radius, maxRadiusByFace)
	local clampedDepth = math.min(penetrationDepth, maxDepthByThickness)
	return clampedRadius, clampedDepth
end

--------------------------------------------------------------------------------
-- DESTRUCTION EXECUTION
--------------------------------------------------------------------------------

local function triggerDestruction(position, normal, radius, penetrationData)
	log("triggerDestruction at", position, "normal:", normal, "radius:", radius)

	local impactDistance = penetrationData and penetrationData.impactDistance
	local weaponRange = penetrationData and penetrationData.weaponRange
	local surfaceNormal = sanitizeNormal(normal)
	local inwardNormal = -surfaceNormal
	local penetrationDepth = calculatePenetrationDepth(impactDistance, weaponRange)
	local impactedPart = findBreakablePartAtImpact(position)
	radius, penetrationDepth = clampHoleToPart(impactedPart, inwardNormal, radius, penetrationDepth)
	local maxDepthByRadius = math.max(CONFIG.MIN_PENETRATION_DEPTH, radius * CONFIG.MAX_DEPTH_TO_RADIUS)
	penetrationDepth = math.min(penetrationDepth, maxDepthByRadius)
	local forwardOffset = math.min(
		(penetrationDepth * CONFIG.PENETRATION_CENTER_RATIO) + CONFIG.PENETRATION_PADDING,
		CONFIG.MAX_FORWARD_OFFSET
	)
	local centerPosition = position + (inwardNormal * forwardOffset)
	
	local hitbox = Instance.new("Part")
	hitbox.Name = "PressureDestructionHitbox"
	hitbox.Size = Vector3.new(radius * 2, radius * 2, penetrationDepth)
	hitbox.CFrame = CFrame.lookAt(centerPosition, centerPosition + inwardNormal)
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.Parent = workspace
	
	-- Keep hitbox hidden in normal gameplay; only show when DEBUG is enabled.
	if DEBUG then
		hitbox.Transparency = 0.3
		hitbox.Color = Color3.fromRGB(255, 0, 0)
		hitbox.Material = Enum.Material.Neon
	else
		hitbox.Transparency = 1
	end
	
	log(
		"Created hitbox. Size:",
		hitbox.Size,
		"CFrame:",
		hitbox.CFrame,
		"ImpactDistance:",
		impactDistance,
		"WeaponRange:",
		weaponRange,
		"PenDepth:",
		penetrationDepth,
		"ForwardOffset:",
		forwardOffset,
		"ImpactedPart:",
		impactedPart and impactedPart.Name or "nil"
	)
	if not impactedPart then
		logWarn("No impacted Breakable part found near impact position", position)
	end
	
	-- Check what breakable parts are nearby
	local breakableParts = CollectionService:GetTagged("Breakable")
	local nearbyCount = 0
	for _, part in ipairs(breakableParts) do
		if part:IsA("BasePart") then
			local dist = (part.Position - position).Magnitude
			if dist < 20 then
				nearbyCount = nearbyCount + 1
				log("Nearby breakable:", part.Name, "at distance", dist)
			end
		end
	end
	log("Total nearby breakable parts:", nearbyCount)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = breakableParts
	overlapParams.RespectCanCollide = false
	local overlapped = workspace:GetPartsInPart(hitbox, overlapParams)
	log(
		"Breakable overlap count at hitbox:",
		#overlapped,
		"overlaps:",
		summarizeParts(overlapped, 5)
	)
	
	-- Call VoxelDestruction (server-side, will replicate to clients)
	task.spawn(function()
		log("Calling VoxelDestruction.Destroy...")
		local success, destroyDebris, destroyWalls = pcall(function()
			return VoxelDestruction.Destroy(
				hitbox,
				nil,                    -- OverlapParams (nil = use default which finds all Breakable parts)
				CONFIG.VOXEL_SIZE,      -- voxelSize
				CONFIG.DEBRIS_COUNT,    -- debrisCount
				nil                     -- reset
			)
		end)
		
		if success then
			local debrisCount = type(destroyDebris) == "table" and #destroyDebris or 0
			local wallCount = type(destroyWalls) == "table" and #destroyWalls or 0
			log(
				"VoxelDestruction.Destroy completed successfully",
				"walls=", wallCount,
				"debris=", debrisCount
			)
			if wallCount == 0 then
				logWarn("Destroy returned zero walls. Impact likely did not resolve against active breakable targets.")
			end
		else
			logWarn("VoxelDestruction error:", destroyDebris)
		end
		
		-- Cleanup hitbox after delay
		task.delay(2, function()
			if hitbox and hitbox.Parent then
				hitbox:Destroy()
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- SHOTGUN CLUSTER HANDLING
--------------------------------------------------------------------------------

local function finalizeCluster(clusterId)
	local cluster = activeClusters[clusterId]
	if not cluster or cluster.triggered then return end
	
	cluster.triggered = true
	activeClusters[clusterId] = nil
	
	local pelletCount = #cluster.positions
	if pelletCount == 0 then 
		log("Cluster empty:", clusterId)
		return 
	end
	
	local perPelletPressure = cluster.pressure or 30
	log("Finalizing cluster:", clusterId, "with", pelletCount, "pellets", "pressure/pellet:", perPelletPressure)
	
	-- Calculate bounding sphere
	local center, spreadRadius = calculateBoundingSphere(cluster.positions)
	if not center then return end
	
	-- Calculate total pressure and hole size
	local totalPressure = perPelletPressure * pelletCount * CONFIG.SHOTGUN_CLUSTER_PRESSURE_SCALE
	local spreadBonus = math.min(spreadRadius * 0.5, 2)
	
	-- Hole radius based on total pressure
	local holeRadius = (totalPressure * CONFIG.PRESSURE_TO_SIZE) + spreadBonus
	holeRadius = math.clamp(
		holeRadius,
		CONFIG.MIN_HOLE_SIZE,
		math.min(CONFIG.MAX_HOLE_SIZE, CONFIG.MAX_SHOTGUN_HOLE_SIZE)
	)
	
	log("Cluster hole: totalPressure", totalPressure, "* multiplier + spreadBonus", spreadBonus, "= radius", holeRadius)
	
	-- Use average normal from cluster
	local normal = cluster.normal or Vector3.new(0, 0, -1)

	local avgImpactDistance = nil
	if cluster.impactDistanceSamples > 0 then
		avgImpactDistance = cluster.impactDistanceTotal / cluster.impactDistanceSamples
	end

	triggerDestruction(center, normal, holeRadius, {
		impactDistance = avgImpactDistance,
		weaponRange = cluster.weaponRange,
	})
end

local function addToCluster(clusterId, position, normal, pressure, impactDistance, weaponRange)
	local cluster = activeClusters[clusterId]
	local safeNormal = sanitizeNormal(normal)
	
	if not cluster then
		cluster = {
			id = clusterId,
			positions = {},
			normal = safeNormal,
			pressure = pressure or 30,
			createdAt = os.clock(),
			triggered = false,
			impactDistanceTotal = 0,
			impactDistanceSamples = 0,
			weaponRange = (type(weaponRange) == "number" and weaponRange > 0) and weaponRange or nil,
		}
		activeClusters[clusterId] = cluster
		log("Created new cluster:", clusterId, "pressure:", cluster.pressure)
		
		-- Schedule finalization
		task.delay(CONFIG.CLUSTER_WINDOW, function()
			finalizeCluster(clusterId)
		end)
	end
	
	table.insert(cluster.positions, position)
	log("Added position to cluster:", clusterId, "total:", #cluster.positions)

	if type(impactDistance) == "number" then
		cluster.impactDistanceTotal = cluster.impactDistanceTotal + impactDistance
		cluster.impactDistanceSamples = cluster.impactDistanceSamples + 1
	end

	if cluster.weaponRange == nil and type(weaponRange) == "number" and weaponRange > 0 then
		cluster.weaponRange = weaponRange
	end
	
	-- Update average normal
	if cluster.normal then
		local lerpedNormal = cluster.normal:Lerp(safeNormal, 0.3)
		if lerpedNormal.Magnitude > 0.001 then
			cluster.normal = lerpedNormal.Unit
		else
			cluster.normal = safeNormal
		end
	else
		cluster.normal = safeNormal
	end
end

--------------------------------------------------------------------------------
-- PRESSURE ZONE HANDLING (Non-Shotgun)
--------------------------------------------------------------------------------

local function triggerZoneDestruction(zone)
	if zone.triggered then return end
	zone.triggered = true
	activeZones[zone.id] = nil
	
	local holeRadius = zone.pressure * CONFIG.PRESSURE_TO_SIZE
	holeRadius = math.clamp(holeRadius, CONFIG.MIN_HOLE_SIZE, CONFIG.MAX_HOLE_SIZE)
	
	log("Triggering zone destruction. Pressure:", zone.pressure, "-> radius:", holeRadius)
	
	triggerDestruction(zone.position, zone.normal, holeRadius, {
		impactDistance = zone.impactDistance,
		weaponRange = zone.weaponRange,
	})
end

local function handleSingleImpact(position, normal, pressure, impactDistance, weaponRange)
	pressure = pressure or DEFAULT_PRESSURE
	log("handleSingleImpact. Pressure:", pressure)
	
	-- Find nearby existing zone
	local nearestZone = nil
	local nearestDist = math.huge
	
	for zoneId, zone in pairs(activeZones) do
		if not zone.triggered then
			local dist = (zone.position - position).Magnitude
			if dist < CONFIG.ZONE_RADIUS and dist < nearestDist then
				nearestZone = zone
				nearestDist = dist
			end
		end
	end
	
	if nearestZone then
		-- Add pressure to existing zone
		nearestZone.pressure = nearestZone.pressure + pressure
		nearestZone.hitCount = nearestZone.hitCount + 1
		nearestZone.position = nearestZone.position:Lerp(position, 0.3)

		if type(impactDistance) == "number" then
			if type(nearestZone.impactDistance) == "number" then
				nearestZone.impactDistance = nearestZone.impactDistance + ((impactDistance - nearestZone.impactDistance) * 0.3)
			else
				nearestZone.impactDistance = impactDistance
			end
		end

		if nearestZone.weaponRange == nil and type(weaponRange) == "number" and weaponRange > 0 then
			nearestZone.weaponRange = weaponRange
		end
		
		log("Added to existing zone. New pressure:", nearestZone.pressure, "Threshold:", CONFIG.MIN_PRESSURE)
		
		-- Check threshold
		if nearestZone.pressure >= CONFIG.MIN_PRESSURE then
			log("Zone pressure threshold exceeded!")
			triggerZoneDestruction(nearestZone)
		end
	else
		-- Create new zone
		local zoneId = tostring(os.clock()) .. "_" .. tostring(math.random(10000, 99999))
		local zone = {
			id = zoneId,
			position = position,
			normal = normal,
			pressure = pressure,
			hitCount = 1,
			createdAt = os.clock(),
			triggered = false,
			impactDistance = impactDistance,
			weaponRange = (type(weaponRange) == "number" and weaponRange > 0) and weaponRange or nil,
		}
		activeZones[zoneId] = zone
		
		log("Created new zone:", zoneId, "Initial pressure:", pressure)
		
		-- Check if single shot exceeds threshold
		if pressure >= CONFIG.MIN_PRESSURE then
			log("Single shot exceeds threshold! Triggering destruction.")
			triggerZoneDestruction(zone)
		else
			-- Schedule expiration - but ALWAYS create destruction (just smaller for low pressure)
			task.delay(CONFIG.ZONE_LIFETIME, function()
				if activeZones[zoneId] and not zone.triggered then
					-- Always trigger destruction - size scales with pressure
					log("Zone expired with", zone.pressure, "pressure. Creating hole.")
					triggerZoneDestruction(zone)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- SERVICE INTERFACE
--------------------------------------------------------------------------------

function PressureDestructionService:Init(registry, net)
	self._registry = registry
	self._net = net
	log("Service initialized")
end

function PressureDestructionService:Start()
	log("Service starting...")
	
	-- Listen for single impact events (non-shotgun)
	self._net:ConnectServer("PressureImpact", function(player, data)
		log("Received PressureImpact from", player.Name)
		
		if not data then 
			log("No data received")
			return 
		end
		if not checkRateLimit(player) then 
			log("Rate limited")
			return 
		end
		
		local position = data.position and Vector3.new(data.position.X, data.position.Y, data.position.Z)
		local normal = data.normal and Vector3.new(data.normal.X, data.normal.Y, data.normal.Z)
		local pressure = data.pressure or DEFAULT_PRESSURE
		local origin = data.origin and Vector3.new(data.origin.X, data.origin.Y, data.origin.Z)
		local weaponRange = (type(data.range) == "number" and data.range > 0) and data.range or nil
		local impactDistance = (origin and position) and (position - origin).Magnitude or nil
		
		log(
			"Impact data - Position:",
			position,
			"Normal:",
			normal,
			"Pressure:",
			pressure,
			"Distance:",
			impactDistance,
			"Range:",
			weaponRange
		)
		
		if not position or not normal then 
			log("Missing position or normal")
			return 
		end
		if not validatePlayerDistance(player, position) then 
			log("Player distance validation failed")
			return 
		end
		
		log("Validation passed, handling impact...")
		-- Trust client's validation - VoxelDestruction will only affect "Breakable" tagged parts
		handleSingleImpact(position, normal, pressure, impactDistance, weaponRange)
	end)
	
	-- Listen for shotgun cluster events
	self._net:ConnectServer("PressureShotgunCluster", function(player, data)
		log("Received PressureShotgunCluster from", player.Name)
		
		if not data then 
			log("No data received")
			return 
		end
		if not checkRateLimit(player) then 
			log("Rate limited")
			return 
		end
		
		local impacts = data.impacts
		local clusterId = data.clusterId
		local pressure = data.pressure or 30
		local origin = data.origin and Vector3.new(data.origin.X, data.origin.Y, data.origin.Z)
		local weaponRange = (type(data.range) == "number" and data.range > 0) and data.range or nil
		
		log("Cluster data - ID:", clusterId, "Impact count:", impacts and #impacts or 0, "Pressure/pellet:", pressure)
		
		if not impacts or type(impacts) ~= "table" or #impacts == 0 then 
			log("Invalid impacts data")
			return 
		end
		if not clusterId then 
			log("Missing clusterId")
			return 
		end
		
		-- Validate first impact position
		local firstPos = impacts[1] and Vector3.new(impacts[1].X, impacts[1].Y, impacts[1].Z)
		if not firstPos or not validatePlayerDistance(player, firstPos) then 
			log("First position validation failed")
			return 
		end
		
		log("Validation passed, adding impacts to cluster...")
		
		-- Add all impacts to cluster (only first call creates cluster with pressure)
		for i, impactData in ipairs(impacts) do
			local pos = Vector3.new(impactData.X, impactData.Y, impactData.Z)
			local norm = impactData.normal 
				and Vector3.new(impactData.normal.X, impactData.normal.Y, impactData.normal.Z)
				or Vector3.new(0, 0, -1)
			local impactDistance = origin and (pos - origin).Magnitude or nil
			
			log("Impact", i, "Position:", pos, "Normal:", norm)
			addToCluster(clusterId, pos, norm, pressure, impactDistance, weaponRange)
		end
	end)
	
	-- Cleanup on player leaving
	Players.PlayerRemoving:Connect(function(player)
		playerImpactCounts[player.UserId] = nil
	end)
	
	log("Service started successfully")
end

--[[
	Cleanup all active zones and clusters.
	Called on match/round end.
]]
function PressureDestructionService:Cleanup()
	activeZones = {}
	activeClusters = {}
end

return PressureDestructionService
