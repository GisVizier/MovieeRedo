local Debris = game:GetService("Debris")

local VFXPlayer = {}

-- =============================================================================
-- Internals (ported/adapted from Moviee-Proj VFXController)
-- =============================================================================

local function disableCollisionAndHide(instance: Instance)
	local function apply(part: BasePart)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		-- Movement VFX templates often use invisible "Root" parts.
		part.Transparency = 1
	end

	if instance:IsA("BasePart") then
		apply(instance)
	end

	for _, d in ipairs(instance:GetDescendants()) do
		if d:IsA("BasePart") then
			apply(d)
		end
	end
end

local function activateEffects(instance: Instance)
	local function process(d: Instance)
		if d:IsA("ParticleEmitter") then
			local emitCount = d:GetAttribute("EmitCount")
			if type(emitCount) == "number" and emitCount > 0 then
				d:Emit(emitCount)
			end
			d.Enabled = true
		elseif d:IsA("Trail") or d:IsA("Beam") then
			d.Enabled = true
		elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			d.Enabled = true
		end
	end

	process(instance)
	for _, d in ipairs(instance:GetDescendants()) do
		process(d)
	end
end

local function findRootPart(instance: Instance): BasePart?
	-- Prefer explicit Root naming (matches your MovementFX hierarchy),
	-- otherwise fallback to any part we can find.
	local directRoot = instance:FindFirstChild("Root")
	if directRoot and directRoot:IsA("BasePart") then
		return directRoot
	end

	local anyRoot = instance:FindFirstChild("Root", true)
	if anyRoot and anyRoot:IsA("BasePart") then
		return anyRoot
	end

	local anyPart = instance:IsA("BasePart") and instance or instance:FindFirstChildWhichIsA("BasePart", true)
	return anyPart
end

local function collectOffsets(rootPart: BasePart, container: Instance): { [BasePart]: CFrame }
	local offsets: { [BasePart]: CFrame } = {}

	if container:IsA("BasePart") then
		offsets[container] = CFrame.identity
		return offsets
	end

	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") then
			offsets[d] = rootPart.CFrame:ToObjectSpace(d.CFrame)
		end
	end

	-- Ensure root itself is present even if it wasn't in descendants scan for some reason.
	offsets[rootPart] = offsets[rootPart] or CFrame.identity
	return offsets
end

local function applyOffsets(rootCFrame: CFrame, offsets: { [BasePart]: CFrame })
	for part, offset in pairs(offsets) do
		if part and part.Parent then
			part.CFrame = rootCFrame * offset
		end
	end
end

local function setEffectCFrame(effect: Instance, rootCFrame: CFrame, offsets: { [BasePart]: CFrame }?)
	if effect:IsA("Model") then
		effect:PivotTo(rootCFrame)
		return
	end
	if effect:IsA("BasePart") then
		effect.CFrame = rootCFrame
		return
	end
	if offsets then
		applyOffsets(rootCFrame, offsets)
	end
end

-- One-shot spawn at a world position.
-- Template must be Folder or effect instance (ParticleEmitter/Beam/Trail/Light).
function VFXPlayer:Play(template: Instance, position: Vector3, lifetime: number?)
	if typeof(position) ~= "Vector3" or typeof(template) ~= "Instance" then
		return
	end

	local clone = template:Clone()
	disableCollisionAndHide(clone)

	-- If the template contains any parts, place it in-world and align its Root.
	local rootPart = findRootPart(clone)
	if rootPart then
		local offsets = collectOffsets(rootPart, clone)
		clone.Parent = workspace
		setEffectCFrame(clone, CFrame.new(position), offsets)
	else
		-- Attachment-only (pure emitters/trails) fallback: anchor part + attachment.
		local anchor = Instance.new("Part")
		anchor.Name = "VFXAnchor"
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.Massless = true
		anchor.CFrame = CFrame.new(position)
		anchor.Parent = workspace

		local att = Instance.new("Attachment")
		att.Name = "VFX"
		att.Parent = anchor

		clone.Parent = att
	end

	activateEffects(clone)

	local lt = lifetime
	if type(lt) ~= "number" then
		local attr = template:GetAttribute("Lifetime")
		if type(attr) == "number" then
			lt = attr
		else
			lt = 0.5
		end
	end

	Debris:AddItem(clone, lt)
end

-- Continuous attach to a BasePart; stop by key.
VFXPlayer._active = {}

function VFXPlayer:Start(key: string, template: Instance, part: BasePart)
	if type(key) ~= "string" or key == "" then
		return
	end
	if typeof(template) ~= "Instance" or typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	if self._active[key] then
		return
	end

	local clone = template:Clone()
	disableCollisionAndHide(clone)

	-- If this effect uses parts/models, we can't rely on parenting under an Attachment.
	-- Instead, keep it in workspace and follow the part.
	local rootPart = findRootPart(clone)
	if rootPart then
		local offsets = collectOffsets(rootPart, clone)
		clone.Parent = workspace
		setEffectCFrame(clone, part.CFrame, offsets)

		self._active[key] = {
			kind = "world",
			effect = clone,
			follow = part,
			offsets = offsets,
		}
	else
		local att = Instance.new("Attachment")
		att.Name = "VFX_" .. key
		att.Parent = part
		clone.Parent = att

		self._active[key] = {
			kind = "attachment",
			attachment = att,
		}
	end

	activateEffects(clone)
end

function VFXPlayer:Stop(key: string)
	local entry = self._active[key]
	if type(entry) == "table" then
		if entry.kind == "attachment" then
			local att = entry.attachment
			if att and att.Parent then
				att:Destroy()
			end
		elseif entry.kind == "world" then
			local effect = entry.effect
			if effect and effect.Parent then
				effect:Destroy()
			end
		end
	end
	self._active[key] = nil
end

function VFXPlayer:IsActive(key: string): boolean
	return self._active[key] ~= nil
end

function VFXPlayer:UpdateYaw(key: string, direction: Vector3)
	local entry = self._active[key]
	if not entry then
		return
	end
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit
	local yaw = math.atan2(-flat.X, -flat.Z)

	if type(entry) == "table" and entry.kind == "attachment" then
		local att = entry.attachment
		if not att or not att.Parent then
			return
		end
		att.CFrame = CFrame.Angles(0, yaw, 0)
	elseif type(entry) == "table" and entry.kind == "world" then
		local effect = entry.effect
		local follow = entry.follow
		local offsets = entry.offsets
		if not effect or not effect.Parent or not follow or not follow.Parent then
			return
		end
		local pos = follow.Position
		local rootCFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		setEffectCFrame(effect, rootCFrame, offsets)
	end
end

return VFXPlayer

