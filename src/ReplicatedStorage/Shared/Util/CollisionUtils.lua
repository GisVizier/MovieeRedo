local RunService = game:GetService("RunService")

local CollisionUtils = {}

-- Storage for active ensure loops
CollisionUtils._ensureData = {} -- [instance] = { connections = {}, heartbeat = RBXScriptConnection?, options = {} }

function CollisionUtils:CreateExclusionOverlapParams(excludedInstances, options)
	options = options or {}

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludedInstances
	params.RespectCanCollide =  true --options.RespectCanCollide ~= nil and options.RespectCanCollide or true
	params.MaxParts = options.MaxParts or 20

	if options.CollisionGroup then
		params.CollisionGroup = options.CollisionGroup
	end

	return params
end

-- =============================================================================
-- NON-COLLIDEABLE UTILITIES
-- =============================================================================

--[[
	Apply non-collideable properties to a single BasePart.
	Options:
		- CanCollide: boolean (default false)
		- CanQuery: boolean (default false)
		- CanTouch: boolean (default false)
		- Massless: boolean (default true)
		- Anchored: boolean (default nil, won't change)
]]
function CollisionUtils:ApplyToBasePart(part: BasePart, options: {[string]: any}?)
	if not part or not part:IsA("BasePart") then
		return
	end
	
	options = options or {}
	
	part.CanCollide = options.CanCollide ~= nil and options.CanCollide or false
	part.CanQuery = options.CanQuery ~= nil and options.CanQuery or false
	part.CanTouch = options.CanTouch ~= nil and options.CanTouch or false
	part.Massless = options.Massless ~= nil and options.Massless or true
	
	if options.Anchored ~= nil then
		part.Anchored = options.Anchored
	end
end

--[[
	Apply non-collideable properties to all BaseParts in an instance (one-time).
	Returns the count of parts modified.
]]
function CollisionUtils:MakeNonCollideable(instance: Instance, options: {[string]: any}?): number
	if not instance then
		return 0
	end
	
	local count = 0
	
	-- Apply to the instance itself if it's a BasePart
	if instance:IsA("BasePart") then
		self:ApplyToBasePart(instance, options)
		count += 1
	end
	
	-- Apply to all descendants
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			self:ApplyToBasePart(descendant, options)
			count += 1
		end
	end
	
	return count
end

--[[
	ROBUST ensure - Sets up continuous enforcement that parts stay non-collideable.
	
	This creates:
	1. DescendantAdded connection - catches new parts immediately
	2. Optional Heartbeat loop - periodically re-applies to ALL parts (bulletproof)
	3. Destroying cleanup - auto-cleans when instance is destroyed
	
	Options:
		- CanCollide: boolean (default false)
		- CanQuery: boolean (default false)
		- CanTouch: boolean (default false)
		- Massless: boolean (default true)
		- Anchored: boolean (default nil)
		- UseHeartbeat: boolean (default true) - enables periodic re-check loop
		- HeartbeatInterval: number (default 0.5) - seconds between heartbeat checks
]]
function CollisionUtils:EnsureNonCollideable(instance: Instance, options: {[string]: any}?)
	if not instance then
		return
	end
	
	-- Clean up any existing ensure on this instance
	self:StopEnsuringNonCollideable(instance)
	
	options = options or {}
	local useHeartbeat = options.UseHeartbeat ~= false -- default true
	local heartbeatInterval = options.HeartbeatInterval or 0.5
	
	local data = {
		connections = {},
		heartbeat = nil,
		options = options,
		lastHeartbeat = 0,
	}
	
	-- Initial application to all existing parts
	self:MakeNonCollideable(instance, options)
	
	-- DescendantAdded - catch any new parts immediately
	local descendantConn = instance.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			self:ApplyToBasePart(descendant, options)
		end
	end)
	table.insert(data.connections, descendantConn)
	
	-- Heartbeat loop - paranoid re-check of ALL parts periodically
	if useHeartbeat then
		data.heartbeat = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - data.lastHeartbeat < heartbeatInterval then
				return
			end
			data.lastHeartbeat = now
			
			-- Re-apply to all parts
			if instance:IsA("BasePart") then
				self:ApplyToBasePart(instance, options)
			end
			for _, descendant in ipairs(instance:GetDescendants()) do
				if descendant:IsA("BasePart") then
					self:ApplyToBasePart(descendant, options)
				end
			end
		end)
	end
	
	-- Auto-cleanup when instance is destroyed
	local destroyingConn = instance.Destroying:Connect(function()
		self:StopEnsuringNonCollideable(instance)
	end)
	table.insert(data.connections, destroyingConn)
	
	self._ensureData[instance] = data
end

--[[
	Stop the ensure loop for an instance and clean up connections.
]]
function CollisionUtils:StopEnsuringNonCollideable(instance: Instance)
	local data = self._ensureData[instance]
	if not data then
		return
	end
	
	-- Disconnect all connections
	for _, conn in ipairs(data.connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	
	-- Disconnect heartbeat
	if data.heartbeat and data.heartbeat.Connected then
		data.heartbeat:Disconnect()
	end
	
	self._ensureData[instance] = nil
end

--[[
	Check if an instance has an active ensure loop.
]]
function CollisionUtils:IsEnsuringNonCollideable(instance: Instance): boolean
	return self._ensureData[instance] ~= nil
end

return CollisionUtils
