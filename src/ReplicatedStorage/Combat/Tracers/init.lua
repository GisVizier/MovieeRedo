--[[
	Tracers/init.lua
	Tracer effect system using pooled Attachments for performance
	
	FX are cloned from ReplicatedStorage.Assets.Tracers.[tracerId]:
	- Trail/FX - Cloned to tracer attachment (follows projectile)
	- Muzzle   - Cloned to gun's muzzle attachment
	- Hit      - Cloned on impact
	- Highlight - Used for player hit effects
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local Tracers = {}
Tracers._cache = {}
Tracers._attachmentPool = {}
Tracers._activeAttachments = {}
Tracers._poolPart = nil
Tracers._initialized = false
Tracers._assetsFolder = nil

-- Config
Tracers.DEFAULT = "Default"
Tracers.POOL_SIZE = 50
Tracers.MAX_ACTIVE = 100

local _playerDataTable = nil
local _playerDataTableResolved = false

local function resolvePlayerDataTable()
	if _playerDataTableResolved then
		return _playerDataTable
	end
	_playerDataTableResolved = true

	local moduleScript = ReplicatedStorage:FindFirstChild("PlayerDataTable")
	if not moduleScript then
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if ok then
		_playerDataTable = result
	end

	return _playerDataTable
end

local function isSettingEnabledValue(value)
	if value == true then
		return true
	end
	if type(value) == "number" then
		return value == 1
	end
	if type(value) == "string" then
		local lowered = string.lower(value)
		return lowered == "enabled" or lowered == "true" or lowered == "on"
	end
	return false
end

function Tracers:IsMuzzleHidden(): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end

	local attrValue = player:GetAttribute("HideMuzzleFlashEnabled")
	if type(attrValue) == "boolean" then
		return attrValue
	end

	local playerDataTable = resolvePlayerDataTable()
	if playerDataTable and type(playerDataTable.get) == "function" then
		local ok, storedValue = pcall(function()
			return playerDataTable.get("Gameplay", "HideMuzzleFlash")
		end)
		if ok then
			return isSettingEnabledValue(storedValue)
		end
	end

	return false
end

--[[
	Initializes the tracer system with pooled attachments
]]
function Tracers:Init()
	if self._initialized then return end
	self._initialized = true
	
	-- Cache assets folder
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		self._assetsFolder = assets:FindFirstChild("Tracers")
	end
	
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
	
	-- Trail attachments pool
	for i = 1, self.POOL_SIZE do
		local attachment = Instance.new("Attachment")
		attachment.Name = "TracerAttachment_" .. i
		attachment.Parent = poolPart
		table.insert(self._attachmentPool, attachment)
	end
end

--[[
	Creates a hit attachment at the impact position (on demand, no pooling)
	@param hitPosition Vector3 - World position of impact
	@param hitNormal Vector3? - Surface normal (optional, for orientation)
	@param lifetime number? - Auto-cleanup after this many seconds (default 2)
	@return Attachment? - The hit attachment to add FX to
]]
function Tracers:CreateHitAttachment(hitPosition: Vector3, hitNormal: Vector3?, lifetime: number?): Attachment?
	if not self._initialized then
		self:Init()
	end
	
	-- Create attachment on demand
	local attachment = Instance.new("Attachment")
	attachment.Name = "HitAttachment"
	attachment.Parent = self._poolPart
	attachment.WorldPosition = hitPosition
	
	-- Orient attachment to face along the hit normal if provided
	if hitNormal then
		attachment.Axis = hitNormal
	end
	
	-- Auto-cleanup after lifetime
	local cleanupTime = 10
	task.delay(cleanupTime, function()
		if attachment and attachment.Parent then
			attachment:Destroy()
		end
	end)
	
	return attachment
end

--[[
	Clones hit FX to an attachment
	@param tracerId string - Tracer ID to get FX from
	@param attachment Attachment - Target attachment
	@return Instance? - The cloned FX container
]]
function Tracers:AttachHitFX(tracerId: string, attachment: Attachment): Instance?
	local assets = self:GetAssets(tracerId or self.DEFAULT)
	if not assets then return nil end
	
	local hitFolder = assets:FindFirstChild("Hit")
	if not hitFolder then return nil end
	
	local fx = hitFolder:FindFirstChild("FX")
	if not fx then return nil end
	
	local fxClone = fx:Clone()
	fxClone.Parent = attachment
	
	return fxClone
end

--[[
	Gets the FX assets folder for a tracer
	@param tracerId string - Tracer ID
	@return Folder? - The tracer's asset folder
]]
function Tracers:GetAssets(tracerId: string): Folder?
	if not self._assetsFolder then 
		return nil 
	end
	
	-- Try exact match first
	local folder = self._assetsFolder:FindFirstChild(tracerId)
	if folder then return folder end
	
	-- Try default (handles both "Default" and "Defualt" typo)
	folder = self._assetsFolder:FindFirstChild(self.DEFAULT)
	if folder then return folder end
	
	folder = self._assetsFolder:FindFirstChild("Defualt")
	if folder then return folder end
	
	return nil
end

--[[
	Scales VFX elements (ParticleEmitters, Trails, Beams) by a factor.
	@param fxInstance Instance - FX container (Folder, Model, Attachment, etc.) - scales all descendants
	@param scale number - Scale factor (e.g. 1.5 = 50% larger, 0.5 = half size)
]]
function Tracers:ScaleFX(fxInstance: Instance, scale: number)
	if not fxInstance or scale == 1 then return end

	local function scaleNumberSequence(seq: NumberSequence): NumberSequence
		local keypoints = {}
		for _, kp in seq.Keypoints do
			table.insert(keypoints, NumberSequenceKeypoint.new(kp.Time, kp.Value * scale))
		end
		return NumberSequence.new(keypoints)
	end

	local function scaleNumberRange(range: NumberRange): NumberRange
		return NumberRange.new(range.Min * scale, range.Max * scale)
	end

	for _, fx in fxInstance:GetDescendants() do
		if fx:IsA("ParticleEmitter") then
			fx.Size = scaleNumberSequence(fx.Size)
			fx.Speed = scaleNumberRange(fx.Speed)
		elseif fx:IsA("Trail") then
			fx.WidthScale = fx.WidthScale * scale
		elseif fx:IsA("Beam") then
			fx.Width0 = fx.Width0 * scale
			fx.Width1 = fx.Width1 * scale
		end
	end
end

--[[
	Clones trail FX to an attachment
	@param tracerId string - Tracer ID
	@param attachment Attachment - Target attachment
	@param scale number? - Optional scale factor for VFX size (default 1)
]]
function Tracers:_attachTrailFX(tracerId: string, attachment: Attachment, scale: number?)
	--warn(attachment, tracerId)
	--attachment.Visible = true
	
	local assets = self:GetAssets(tracerId)
	if not assets then 
		return 
	end
	
	local trailFolder = assets:FindFirstChild("Trail")
	if not trailFolder then 
		return 
	end
	
	local fx = trailFolder:FindFirstChild("FX")
	if not fx then 
		return 
	end

	local fxclone = fx:Clone()
	fxclone.Parent = attachment
	if scale and scale ~= 1 then
		self:ScaleFX(fxclone, scale)
	end
	for _, fx in fxclone:GetDescendants() do
		if fx:IsA("ParticleEmitter") then
			fx.Enabled = false
		elseif fx:IsA("Trail") then
			fx.Enabled = false
		elseif fx:IsA("Beam") then
			fx.Enabled = false
		end
	end

	
	task.delay(0.025, function()
		for _, fx in fxclone:GetDescendants() do
			if fx:IsA("ParticleEmitter") then
				fx.Enabled = true
			elseif fx:IsA("Trail") then
				fx.Enabled = true
			elseif fx:IsA("Beam") then
				fx.Enabled = true
			end
		end
	end)

end

--[[
	Finds muzzle attachment on a gun model
	@param gunModel Model - The weapon model (must be an Instance)
	@return Attachment? - The muzzle attachment
]]
function Tracers:FindMuzzleAttachment(gunModel: Model?): Attachment?
	if not gunModel then return nil end
	
	-- Type check - must be an Instance with GetDescendants
	if typeof(gunModel) ~= "Instance" then
		return nil
	end
	
	-- Common muzzle attachment names
	local muzzleNames = {"Muzzle", "MuzzleAttachment", "Barrel", "BarrelAttachment", "FirePoint"}
	
	-- Search all descendants
	for _, descendant in gunModel:GetDescendants() do
		if descendant:IsA("Attachment") then
			for _, name in muzzleNames do
				if descendant.Name == name then
					return descendant
				end
			end
		end
	end
	
	-- Fallback: find any attachment with "muzzle" in name (case insensitive)
	for _, descendant in gunModel:GetDescendants() do
		if descendant:IsA("Attachment") and string.lower(descendant.Name):find("muzzle") then
			return descendant
		end
	end

	-- Fallback: accept muzzle/barrel parts and attach FX to a child attachment
	for _, descendant in gunModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			local lowerName = string.lower(descendant.Name)
			local isMuzzlePart = lowerName == "muzzle"
				or lowerName == "barrel"
				or lowerName == "firepoint"
				or lowerName:find("muzzle")
				or lowerName:find("barrel")
			if isMuzzlePart then
				local childAttachment = descendant:FindFirstChildWhichIsA("Attachment")
				if childAttachment then
					return childAttachment
				end

				local createdAttachment = Instance.new("Attachment")
				createdAttachment.Name = "MuzzleAttachment"
				createdAttachment.Parent = descendant
				return createdAttachment
			end
		end
	end
	
	return nil
end

--[[
	Clones muzzle FX to gun's muzzle attachment
	@param tracerId string - Tracer ID
	@param gunModel Model - The weapon model
	@return {Instance} - Cloned FX (for cleanup)
]]
function Tracers:AttachMuzzleFX(tracerId: string, gunModel: Model?): {Instance}
	local clones = {}
	
	local muzzleAttachment = self:FindMuzzleAttachment(gunModel)
	if not muzzleAttachment then return clones end
	
	local assets = self:GetAssets(tracerId)
	if not assets then return clones end
	
	local muzzleFolder = assets:FindFirstChild("Muzzle")
	if not muzzleFolder then return clones end
	
	-- Clone all FX to muzzle attachment
	for _, fx in muzzleFolder:GetChildren() do
		local clone = fx:Clone()
		clone.Parent = muzzleAttachment
		table.insert(clones, clone)
		
		-- Emit particles once for muzzle flash
		if clone:IsA("ParticleEmitter") then
			clone:Emit(clone:GetAttribute("EmitCount") or 10)
			-- Cleanup after lifetime
			task.delay(clone.Lifetime.Max + 0.1, function()
				if clone and clone.Parent then
					clone:Destroy()
				end
			end)
		elseif clone:IsA("PointLight") then
			-- Flash light briefly
			task.delay(0.05, function()
				if clone and clone.Parent then
					clone:Destroy()
				end
			end)
		end
	end
	
	return clones
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
	@param playMuzzle boolean? - Whether to play muzzle FX (default true, set false for pellets 2+)
	@param scaleOrOptions number|table? - Optional trail scale number or table:
		{
			trailScale = number?, -- trail FX scale (default 1)
			muzzleScale = number?, -- muzzle FX scale (optional)
		}
	@return { attachment: Attachment, tracer: TracerModule, cleanup: () -> () }?
]]
function Tracers:Fire(
	tracerId: string?,
	origin: Vector3,
	gunModel: Model?,
	playMuzzle: boolean?,
	scaleOrOptions: number | { trailScale: number?, muzzleScale: number? }?
)
	if not self._initialized then
		self:Init()
	end
	
	-- Default playMuzzle to true
	if playMuzzle == nil then
		playMuzzle = true
	end
	
	local resolvedId = tracerId or self.DEFAULT
	local tracer = self:Get(resolvedId)
	if not tracer then return nil end

	local trailScale = 1
	local muzzleScale = nil
	if type(scaleOrOptions) == "number" then
		if scaleOrOptions > 0 then
			trailScale = scaleOrOptions
		end
	elseif type(scaleOrOptions) == "table" then
		local requestedTrailScale = scaleOrOptions.trailScale
		if type(requestedTrailScale) == "number" and requestedTrailScale > 0 then
			trailScale = requestedTrailScale
		end

		local requestedMuzzleScale = scaleOrOptions.muzzleScale
		if type(requestedMuzzleScale) == "number" and requestedMuzzleScale > 0 then
			muzzleScale = requestedMuzzleScale
		end
	end
	
	local attachment = self:_getAttachment()
	if not attachment then
		return nil
	end
	
	table.insert(self._activeAttachments, attachment)
	attachment.WorldPosition = origin
	
	-- Attach trail FX from assets (replicates to all clients)
	self:_attachTrailFX(resolvedId, attachment, trailScale)
	
	-- Only play muzzle FX once per shot (not per pellet)
	if playMuzzle and tracer.Muzzle and not self:IsMuzzleHidden() then
		local muzzleAttachment = self:FindMuzzleAttachment(gunModel)
		tracer:Muzzle(origin, gunModel, attachment, self, muzzleAttachment, {
			muzzleScale = muzzleScale,
		})
	end
	
	-- Return handle for caller to animate and cleanup
	return {
		attachment = attachment,
		tracer = tracer,
		tracerId = resolvedId,
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
		handle.tracer:HitPlayer(hitPosition, hitPart, targetCharacter, handle.attachment, self)
	end
end

--[[
	Called when tracer hits world geometry
]]
function Tracers:HitWorld(handle, hitPosition: Vector3, hitNormal: Vector3, hitPart: BasePart)
	if not handle or not handle.tracer then return end
	
	handle.attachment.WorldPosition = hitPosition
	
	if handle.tracer.HitWorld then
		handle.tracer:HitWorld(hitPosition, hitNormal, hitPart, handle.attachment, self)
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
