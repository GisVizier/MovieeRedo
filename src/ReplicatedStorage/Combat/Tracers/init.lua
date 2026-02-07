--[[
	Tracers/init.lua
	Tracer effect system using pooled Attachments for performance
	
	Simple usage:
	- Weapon config has tracerId (or nil to use player's equipped tracer)
	- Tracer follows projectile path via attachment
	- VFX attached to the moving attachment
]]

local Workspace = game:GetService("Workspace")

local Tracers = {}
Tracers._cache = {}
Tracers._attachmentPool = {}
Tracers._activeAttachments = {}
Tracers._poolPart = nil
Tracers._initialized = false

-- Config
Tracers.DEFAULT = "Default"
Tracers.POOL_SIZE = 50
Tracers.MAX_ACTIVE = 100

--[[
	Initializes the tracer system with pooled attachments
]]
function Tracers:Init()
	if self._initialized then return end
	self._initialized = true
	
	local poolPart = Instance.new("Part")
	poolPart.Name = "TracerPool"
	poolPart.Anchored = true
	poolPart.CanCollide = false
	poolPart.CanQuery = false
	poolPart.CanTouch = false
	poolPart.Transparency = 1
	poolPart.Size = Vector3.new(1, 1, 1)
	poolPart.CFrame = CFrame.new(0, -1000, 0)
	poolPart.Parent = Workspace
	self._poolPart = poolPart
	
	for i = 1, self.POOL_SIZE do
		local attachment = Instance.new("Attachment")
		attachment.Name = "TracerAttachment_" .. i
		attachment.Parent = poolPart
		table.insert(self._attachmentPool, attachment)
	end
end

--[[
	Gets an attachment from the pool
]]
function Tracers:_getAttachment(): Attachment?
	if #self._attachmentPool > 0 then
		return table.remove(self._attachmentPool)
	end
	
	if #self._activeAttachments < self.MAX_ACTIVE then
		local attachment = Instance.new("Attachment")
		attachment.Name = "TracerAttachment_Dynamic"
		attachment.Parent = self._poolPart
		return attachment
	end
	
	return nil
end

--[[
	Returns an attachment to the pool
]]
function Tracers:_returnAttachment(attachment: Attachment)
	for _, child in attachment:GetChildren() do
		child:Destroy()
	end
	
	attachment.WorldPosition = Vector3.new(0, -1000, 0)
	
	local idx = table.find(self._activeAttachments, attachment)
	if idx then
		table.remove(self._activeAttachments, idx)
	end
	
	table.insert(self._attachmentPool, attachment)
end

--[[
	Gets a tracer module by ID
]]
function Tracers:Get(tracerId: string)
	tracerId = tracerId or self.DEFAULT

	if self._cache[tracerId] then
		return self._cache[tracerId]
	end

	local moduleScript = script:FindFirstChild(tracerId)
	if not moduleScript then
		moduleScript = script:FindFirstChild(self.DEFAULT)
	end

	if not moduleScript then
		error("[Tracers] Default tracer not found!")
	end

	local ok, tracerModule = pcall(require, moduleScript)
	if not ok then
		warn("[Tracers] Failed to load tracer:", tracerId, tracerModule)
		return nil
	end

	self._cache[tracerId] = tracerModule
	return tracerModule
end

--[[
	Resolves which tracer to use
	@param tracerId string? - Weapon's tracer ID (nil = use player's equipped)
	@param playerTracerId string? - Player's equipped tracer cosmetic
]]
function Tracers:Resolve(tracerId: string?, playerTracerId: string?): string
	-- Weapon specifies a tracer = use it
	if tracerId and tracerId ~= "" then
		return tracerId
	end
	
	-- Otherwise use player's equipped tracer (from cosmetics/loadout)
	if playerTracerId and playerTracerId ~= "" then
		return playerTracerId
	end
	
	return self.DEFAULT
end

--[[
	Fires a tracer - returns attachment for the caller to animate
	@param tracerId string? - Tracer module to use
	@param origin Vector3 - Starting position
	@param gunModel Model? - Weapon model (for muzzle VFX)
	@return { attachment: Attachment, tracer: TracerModule, cleanup: () -> () }?
]]
function Tracers:Fire(tracerId: string?, origin: Vector3, gunModel: Model?)
	if not self._initialized then
		self:Init()
	end
	
	local tracer = self:Get(tracerId)
	if not tracer then return nil end
	
	local attachment = self:_getAttachment()
	if not attachment then
		warn("[Tracers] Pool exhausted")
		return nil
	end
	
	table.insert(self._activeAttachments, attachment)
	attachment.WorldPosition = origin
	
	-- Muzzle effect
	if tracer.Muzzle then
		tracer:Muzzle(origin, gunModel, attachment)
	end
	
	-- Return handle for caller to animate and cleanup
	return {
		attachment = attachment,
		tracer = tracer,
		cleanup = function()
			self:_returnAttachment(attachment)
		end,
	}
end

--[[
	Called when tracer hits a player
]]
function Tracers:HitPlayer(handle, hitPosition: Vector3, hitPart: BasePart, targetCharacter: Model)
	if not handle or not handle.tracer then return end
	
	handle.attachment.WorldPosition = hitPosition
	
	if handle.tracer.HitPlayer then
		handle.tracer:HitPlayer(hitPosition, hitPart, targetCharacter, handle.attachment)
	end
end

--[[
	Called when tracer hits world geometry
]]
function Tracers:HitWorld(handle, hitPosition: Vector3, hitNormal: Vector3, hitPart: BasePart)
	if not handle or not handle.tracer then return end
	
	handle.attachment.WorldPosition = hitPosition
	
	if handle.tracer.HitWorld then
		handle.tracer:HitWorld(hitPosition, hitNormal, hitPart, handle.attachment)
	end
end

--[[
	Cleans up all active tracers
]]
function Tracers:Cleanup()
	for _, attachment in self._activeAttachments do
		self:_returnAttachment(attachment)
	end
	self._activeAttachments = {}
end

return Tracers
