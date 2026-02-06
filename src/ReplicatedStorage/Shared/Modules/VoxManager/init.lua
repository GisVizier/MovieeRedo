--[[
	VoxManager - Voxel Destruction System
	by @LxckyDev
	
	A high-performance voxel-based destruction system for Roblox.
	Uses octree subdivision + greedy meshing for optimized part counts.
	
	QUICK START:
	  local VoxManager = require(path.to.VoxManager)
	  
	  -- Explode at a position
	  VoxManager:explode(Vector3.new(0, 10, 0))
	  
	  -- Explode with custom radius
	  VoxManager:explode(position, 15)
	  
	  -- Explode with options
	  VoxManager:explode(position, 10, {
	      voxelSize = 2,
	      debris = true,
	      debrisAmount = 10
	  })
	  
	  -- Regenerate all destroyed parts
	  VoxManager:regenerateAll()
]]
--

-- [ MODULES / SERVICES ]
local Voxelizer = require(script.Voxelizer)
local ObjectCache = require(script.ObjectCache)

-- [ MODULE ]
local VoxManager = {
	-- Internal
	_voxelCache = nil,
	_voxelFolder = nil,
	_initialized = false,

	-- Default settings
	Defaults = {
		radius = 10,
		voxelSize = 1,
		debris = true,
		debrisAmount = 5,
		debrisSize = 0.3,
		ignore = { "Bedrock" },
		debugColors = false,
	},
}

--[[ ================== INTERNAL ================== ]]

function VoxManager:_init()
	if self._initialized then
		return
	end

	local template = Instance.new("Part")
	template.Anchored = true

	self._voxelFolder = Instance.new("Folder")
	self._voxelFolder.Name = "VoxelCache"
	self._voxelFolder.Parent = workspace

	self._voxelCache = ObjectCache.new(template, 10000, self._voxelFolder)
	self._voxelCache:SetExpandAmount(100)

	template:Destroy()
	self._initialized = true
end

--[[ ================== MAIN API ================== ]]

--[[
	Explode/voxelize at a position.
	
	@param position Vector3 - Center of explosion
	@param radius? number - Explosion radius (default: 10)
	@param options? table - Optional settings:
	    - voxelSize: number (default: 1)
	    - debris: boolean (default: true)
	    - debrisAmount: number (default: 5)
	    - ignore: {string} (default: {"Bedrock"})
	    - debugColors: boolean (default: false)
	
	@return boolean - Success
]]
function VoxManager:explode(position: Vector3, radius: number?, options: {}?)
	assert(position and typeof(position) == "Vector3", "Position must be a Vector3")

	self:_init()

	-- Merge options with defaults
	local opts = options or {}
	local r = radius or self.Defaults.radius
	local voxelSize = opts.voxelSize or self.Defaults.voxelSize
	local debris = opts.debris
	if debris == nil then
		debris = self.Defaults.debris
	end
	local debrisAmount = opts.debrisAmount or self.Defaults.debrisAmount
	local debrisSize = opts.debrisSize or self.Defaults.debrisSize
	local ignore = opts.ignore or self.Defaults.ignore
	local debugColors = opts.debugColors
	if debugColors == nil then
		debugColors = self.Defaults.debugColors
	end

	-- Create hitbox
	local hitbox = Instance.new("Part")
	hitbox.Shape = Enum.PartType.Ball
	hitbox.Position = position
	hitbox.Size = Vector3.new(r * 2, r * 2, r * 2)
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanQuery = false
	hitbox.Transparency = 1
	hitbox.Parent = workspace

	-- Execute voxelization (hitbox is destroyed inside subtractHitbox after processing)
	local ok, result = pcall(function()
		return Voxelizer.subtractHitbox(
			hitbox,
			voxelSize, -- minSize
			voxelSize, -- finalSize
			debugColors, -- randomColor
			debris, -- debris
			debrisAmount, -- debrisAmount
			ignore, -- ignore list
			self._voxelCache,
			debrisSize
		)
	end)

	-- Safety cleanup: if subtractHitbox errored, destroy the hitbox
	if not ok then
		if hitbox and hitbox.Parent then
			hitbox:Destroy()
		end
		return false
	end

	return result ~= nil
end

--[[
	Regenerate all destroyed parts back to their original state.
	
	@return {Part} - Array of regenerated parts
]]
function VoxManager:regenerateAll()
	return Voxelizer.regenerateAll()
end

--[[
	Set default options for all future explosions.
	
	@param options table - Default settings to apply:
	    - radius: number
	    - voxelSize: number
	    - debris: boolean
	    - debrisAmount: number
	    - debrisSize: number
	    - ignore: {string}
	    - debugColors: boolean
]]
function VoxManager:setDefaults(options: {})
	assert(options and typeof(options) == "table", "Options must be a table")

	for key, value in pairs(options) do
		if self.Defaults[key] ~= nil then
			self.Defaults[key] = value
		end
	end
end

--[[
	Set a callback for debris creation (for client-side debris).
	Callback receives: (position, radius, amount, sizeMultiplier, info)
	
	@param callback function
]]
function VoxManager:setDebrisCallback(callback: (...any) -> ())
	Voxelizer.DebrisCallback = callback
end

--[[
	Clean up all voxels and clear regeneration data.
	Call this when resetting or leaving a game.
]]
function VoxManager:cleanup()
	Voxelizer.clearRegenData()

	if self._voxelCache then
		self._voxelCache:Destroy()
		self._voxelFolder:Destroy()
		self._voxelCache = nil
		self._voxelFolder = nil
	end

	self._initialized = false
end

--[[ ================== ADVANCED API ================== ]]

--[[
	Explode using a pre-made spherical hitbox Part.
	For advanced users who want more control.
	
	@param hitbox Part - A Ball-shaped part
	@param options? table - Same as explode()
	@return boolean
]]
function VoxManager:explodeWithHitbox(hitbox: Part, options: {}?)
	assert(hitbox and hitbox:IsA("BasePart"), "Hitbox must be a Part")
	assert(hitbox.Shape == Enum.PartType.Ball, "Hitbox must be Ball shaped")

	self:_init()

	local opts = options or {}
	local voxelSize = opts.voxelSize or self.Defaults.voxelSize
	local debris = opts.debris
	if debris == nil then
		debris = self.Defaults.debris
	end
	local debrisAmount = opts.debrisAmount or self.Defaults.debrisAmount
	local debrisSize = opts.debrisSize or self.Defaults.debrisSize
	local ignore = opts.ignore or self.Defaults.ignore
	local debugColors = opts.debugColors
	if debugColors == nil then
		debugColors = self.Defaults.debugColors
	end

	local ok, result = pcall(function()
		return Voxelizer.subtractHitbox(
			hitbox,
			voxelSize,
			voxelSize,
			debugColors,
			debris,
			debrisAmount,
			ignore,
			self._voxelCache,
			debrisSize
		)
	end)

	if not ok then
		return false
	end

	return result ~= nil
end

--[[
	Get count of parts waiting to be regenerated.
	@return number
]]
function VoxManager:getPendingCount()
	return #Voxelizer.getStoredPartIds()
end

return VoxManager
