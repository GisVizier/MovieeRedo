--[[
	PressureDestruction.lua (Client-Side)
	
	Client module for the pressure-based destruction system.
	Collects bullet impact data and sends it to the server for processing.
	Server handles actual VoxelDestruction to ensure proper replication.
	
	NOTE: We do NOT check if parts are "breakable" on the client.
	VoxelDestruction uses CollectionService:GetTagged("Breakable") to find
	breakable parts near the hitbox. The hit part itself doesn't need tags.
	
	Usage:
		local PressureDestruction = require(path.to.PressureDestruction)
		
		-- For shotguns (group pellets by shotId):
		PressureDestruction:RegisterImpact(position, normal, part, "Shotgun", true, shotId)
		
		-- For other weapons:
		PressureDestruction:RegisterImpact(position, normal, part, "Rifle", false)
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PressureDestruction = {}
PressureDestruction.__index = PressureDestruction

--------------------------------------------------------------------------------
-- DEBUG
--------------------------------------------------------------------------------

local DEBUG = false -- Set to false to disable debug logging

local function log(...)
	return
end

local function logWarn(...)
	return
end

--------------------------------------------------------------------------------
-- NETWORKING
--------------------------------------------------------------------------------

local Net = nil
local netInitialized = false

local function initNet()
	if netInitialized then return end
	netInitialized = true
	
	log("Initializing Net module...")
	
	-- Try to get Net module for remote calls
	local success, err = pcall(function()
		Net = require(ReplicatedStorage.Shared.Net.Net)
	end)
	
	if success and Net then
		log("Net module loaded successfully")
	else
		logWarn("Failed to load Net module:", err)
	end
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Active shotgun clusters (for grouping pellets before sending)
local activeClusters = {} -- [shotId] = clusterData

local CONFIG = {
	CLUSTER_WINDOW = 0.015, -- Match server cluster window to avoid delayed shotgun sends
}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

-- Convert Vector3 to table for network serialization
local function vector3ToTable(v)
	return { X = v.X, Y = v.Y, Z = v.Z }
end

local function normalizeRange(rangeValue)
	if type(rangeValue) == "number" and rangeValue > 0 then
		return rangeValue
	end
	return nil
end

local function describeHitPart(part)
	if not part or typeof(part) ~= "Instance" then
		return "part=nil"
	end

	local parentName = part.Parent and part.Parent.Name or "nil"
	return string.format(
		"path=%s parent=%s breakable=%s piece=%s debris=%s __Breakable=%s __BreakableClient=%s canQuery=%s canCollide=%s transp=%.2f",
		part:GetFullName(),
		parentName,
		tostring(part:HasTag("Breakable")),
		tostring(part:HasTag("BreakablePiece")),
		tostring(part:HasTag("Debris")),
		tostring(part:GetAttribute("__Breakable")),
		tostring(part:GetAttribute("__BreakableClient")),
		tostring(part.CanQuery),
		tostring(part.CanCollide),
		part.Transparency
	)
end

--------------------------------------------------------------------------------
-- SHOTGUN CLUSTER HANDLING
--------------------------------------------------------------------------------

--[[
	Add a pellet impact to a shot cluster.
	All pellets from the same shot (identified by shotId) are grouped together.
]]
function PressureDestruction:_addToCluster(shotId, position, normal, pressure, originPosition, weaponRange)
	local cluster = activeClusters[shotId]
	local normalizedRange = normalizeRange(weaponRange)
	
	if not cluster then
		-- Create new cluster for this shot
		cluster = {
			id = shotId,
			impacts = {},
			pressure = pressure or 30, -- Per-pellet pressure
			origin = originPosition, -- Store origin for distance calculation
			range = normalizedRange,
			createdAt = os.clock(),
			sent = false,
		}
		activeClusters[shotId] = cluster
		log("Created new shotgun cluster:", shotId, "pressure:", cluster.pressure)
		
		-- Schedule cluster finalization after the collection window
		task.delay(CONFIG.CLUSTER_WINDOW, function()
			self:_sendCluster(shotId)
		end)
	else
		if not cluster.origin and originPosition then
			cluster.origin = originPosition
		end
		if cluster.range == nil and normalizedRange ~= nil then
			cluster.range = normalizedRange
		end
	end
	
	-- Add this pellet's impact
	local impactData = vector3ToTable(position)
	impactData.normal = vector3ToTable(normal)
	table.insert(cluster.impacts, impactData)
	log("Added pellet to cluster:", shotId, "total pellets:", #cluster.impacts)
end

--[[
	Send the collected cluster data to the server.
]]
function PressureDestruction:_sendCluster(shotId)
	local cluster = activeClusters[shotId]
	if not cluster or cluster.sent then return end
	
	cluster.sent = true
	activeClusters[shotId] = nil
	
	if #cluster.impacts == 0 then 
		log("Cluster empty, not sending:", shotId)
		return 
	end
	
	initNet()
	if not Net then 
		logWarn("Cannot send cluster - Net is nil")
		return 
	end
	
	log("Sending shotgun cluster to server:", shotId, "with", #cluster.impacts, "pellets", "pressure:", cluster.pressure)
	Net:FireServer("PressureShotgunCluster", {
		clusterId = cluster.id,
		impacts = cluster.impacts,
		pressure = cluster.pressure,
		origin = cluster.origin and vector3ToTable(cluster.origin) or nil,
		range = cluster.range,
	})
end

--------------------------------------------------------------------------------
-- SINGLE IMPACT HANDLING (Non-Shotgun)
--------------------------------------------------------------------------------

--[[
	Send a single impact to the server immediately.
]]
function PressureDestruction:_sendSingleImpact(position, normal, pressure, originPosition, weaponRange)
	initNet()
	if not Net then 
		logWarn("Cannot send impact - Net is nil")
		return 
	end

	local normalizedRange = normalizeRange(weaponRange)
	
	log("Sending single impact to server. Pressure:", pressure, "Position:", position)
	Net:FireServer("PressureImpact", {
		position = vector3ToTable(position),
		normal = vector3ToTable(normal),
		pressure = pressure or 20,
		origin = originPosition and vector3ToTable(originPosition) or nil,
		range = normalizedRange,
	})
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
	Register a bullet/pellet impact on a surface.
	
	NOTE: We don't check if the part is "breakable" here. VoxelDestruction
	uses CollectionService:GetTagged("Breakable") to find breakable parts
	near the destruction hitbox. The specific part hit doesn't need tags.
	
	@param position Vector3 - Impact position
	@param normal Vector3 - Surface normal at impact
	@param part BasePart - The part that was hit (unused, kept for API compatibility)
	@param pressure number - Destruction pressure value from weapon config
	@param isShotgun boolean - Is this a shotgun pellet?
	@param shotId string? - Unique ID for this shot (required for shotguns to group pellets)
	@param options table? - Optional context: { origin = Vector3, range = number }
]]
function PressureDestruction:RegisterImpact(position, normal, part, pressure, isShotgun, shotId, options)
	log("RegisterImpact called. Pressure:", pressure, "IsShotgun:", isShotgun, "Position:", position)
	log("RegisterImpact hit part:", describeHitPart(part))
	
	-- Only run on client
	if RunService:IsServer() then 
		log("Running on server, skipping")
		return 
	end
	
	-- Validate inputs
	if not position or not normal then 
		logWarn("Missing position or normal")
		return 
	end
	
	-- No breakable check here - VoxelDestruction finds breakable parts via CollectionService
	local originPosition = options and options.origin
	local weaponRange = options and options.range

	if isShotgun and shotId then
		-- Shotgun: group pellets by shotId, then send as cluster
		log("Adding to shotgun cluster")
		self:_addToCluster(shotId, position, normal, pressure, originPosition, weaponRange)
	else
		-- Other weapons: send immediately
		log("Sending as single impact")
		self:_sendSingleImpact(position, normal, pressure, originPosition, weaponRange)
	end
end

--[[
	Generate a unique shot ID for grouping shotgun pellets.
	Call this once per shot, then pass to RegisterImpact for each pellet.
]]
function PressureDestruction:GenerateShotId()
	return HttpService:GenerateGUID(false)
end

--[[
	Cleanup all pending clusters (call on match end, etc.)
]]
function PressureDestruction:Cleanup()
	activeClusters = {}
end

return PressureDestruction
